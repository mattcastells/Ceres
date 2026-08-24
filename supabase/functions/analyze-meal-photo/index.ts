// analyze-meal-photo (08-supabase-plan.md §4, 12-external-integrations.md §1).
//
// Descarga la foto del bucket privado del usuario, se la manda a Gemini con el
// prompt versionado y el schema de salida, valida la respuesta y la persiste en
// `ai_analyses`.
//
// La clave de Gemini vive **solo acá**, en los secretos del proyecto. Ese es el
// motivo de que esta función exista en vez de que la app llame a Gemini
// directo: una clave dentro de un APK es una clave regalada.
//
// El contrato de salida, la validación y la llamada al modelo son los mismos
// que usa `analyze-meal-text` y viven en `_shared/estimation.ts`: las dos
// estiman la misma cosa y solo cambia qué se le manda al modelo.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { PROMPT_V3, describedBy } from './prompts/v3.ts';
import {
  CORS,
  DAILY_QUOTA,
  GEMINI_MODEL,
  PROMPT_VERSION,
  callGemini,
  fail,
  ok,
  overloadedResponse,
  rateLimitedResponse,
  timedOutResponse,
  validate,
  validateTitle,
} from '../_shared/estimation.ts';
import { parseCurrentItems, recalculatedFrom } from '../_shared/recalc.ts';

/** Mismo techo que `analyze-meal-text`: más que esto no es una aclaración. */
const MAX_DESCRIPTION = 400;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return fail('ERR_UNAUTHENTICATED', 'Falta la sesión.', 401);
  }

  const geminiKey = Deno.env.get('GEMINI_API_KEY');
  if (!geminiKey) {
    return fail(
      'ERR_PROVIDER_UNAVAILABLE',
      'El análisis por foto no está configurado en el servidor.',
      503,
    );
  }

  // El cliente se crea con el JWT de quien llama, no con la secret key: así
  // RLS sigue aplicando y la función no puede leer la foto de otra persona
  // aunque le pasen una ruta ajena.
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_PUBLISHABLE_KEY') ?? Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: userData, error: userError } = await supabase.auth.getUser();
  const user = userData?.user;
  if (userError || !user) {
    return fail('ERR_UNAUTHENTICATED', 'Tu sesión venció.', 401);
  }

  let photoPath: string;
  // Lo que la persona escribió sobre la foto, si escribió algo. Es opcional a
  // propósito: la foto sola tiene que seguir andando igual que antes.
  let description = '';
  // Los ítems que la comida ya tiene. Cuando vienen, esto no es un análisis
  // nuevo sino un recálculo, y `description` pasa a ser la corrección.
  let currentItems: ReturnType<typeof parseCurrentItems> = [];
  try {
    const body = await req.json();
    photoPath = String(body.photoPath ?? '');
    description = String(body.description ?? '').trim().slice(0, MAX_DESCRIPTION);
    currentItems = parseCurrentItems(body.currentItems);
  } catch {
    return fail('ERR_VALIDATION', 'Falta indicar la foto.');
  }
  if (!photoPath) return fail('ERR_VALIDATION', 'Falta indicar la foto.');

  // Defensa en profundidad: RLS ya impide leer la carpeta de otro, pero se
  // rechaza acá también para que el error sea claro y no un 403 de Storage.
  if (!photoPath.startsWith(`${user.id}/`)) {
    return fail('ERR_FORBIDDEN', 'Esa foto no es tuya.', 403);
  }

  // ── Cuota diaria ───────────────────────────────────────────────────────
  // Atómico vía `check_rate_limit` (migración 24) — ver el comentario gemelo
  // en `analyze-meal-text`, que comparte este mismo cupo.
  const { data: withinQuota, error: quotaError } = await supabase.rpc(
    'check_rate_limit',
    { p_bucket: 'ai_analysis', p_max: DAILY_QUOTA },
  );

  if (quotaError) {
    return fail('ERR_SERVER', 'No pudimos verificar tu cuota. Probá de nuevo.', 500);
  }
  if (!withinQuota) {
    return fail(
      'ERR_QUOTA_EXCEEDED',
      `Llegaste a los ${DAILY_QUOTA} análisis de hoy. Podés cargar la comida a mano.`,
      429,
    );
  }

  // ── Foto ───────────────────────────────────────────────────────────────
  const { data: blob, error: downloadError } = await supabase
    .storage.from('meal-photos').download(photoPath);

  if (downloadError || !blob) {
    return fail('ERR_NOT_FOUND', 'No encontramos esa foto.', 404);
  }

  const bytes = new Uint8Array(await blob.arrayBuffer());
  const base64 = toBase64(bytes);

  // ── Gemini ─────────────────────────────────────────────────────────────
  // La aclaración va **después** de la imagen: lo que dice es sobre lo que se
  // ve, no un pedido suelto. Al modelo se le explica cómo tratarla en
  // `describedBy` — es contexto que la foto no puede dar (el relleno de una
  // empanada), no permiso para agregar lo que no está.
  //
  // Con `currentItems` la comida ya existe y lo escrito es una corrección
  // ("le falta el pan", "la milanesa pesaba 200 g"): ahí manda el bloque de
  // recálculo, que pide devolver la comida entera ya corregida en vez de una
  // lectura nueva de la foto. Sin ellos, todo sigue igual que antes.
  const {
    parsed,
    lastError,
    rateLimited,
    overloaded,
    timedOut,
    retryAfterSeconds,
    diagnostics,
    latencyMs,
  } = await callGemini(
      geminiKey,
      [
        { text: PROMPT_V3 },
        { inlineData: { mimeType: 'image/jpeg', data: base64 } },
        ...(currentItems.length > 0
          ? [{
            text: recalculatedFrom(currentItems, description, {
              withPhoto: true,
            }),
          }]
          : description
          ? [{ text: describedBy(description) }]
          : []),
      ],
    );

  const registrar = async (errorCode: string) => {
    const { error } = await supabase.from('ai_analyses').insert({
      id: crypto.randomUUID(),
      user_id: user.id,
      source: 'photo',
      photo_path: photoPath,
      status: 'failed',
      model: GEMINI_MODEL,
      prompt_version: PROMPT_VERSION,
      error_code: errorCode,
      latency_ms: latencyMs,
      // Migración 39: la fila del fallo es justo la que necesita explicarse.
      finish_reason: diagnostics.finishReason,
      tokens_in: diagnostics.tokensIn,
      tokens_out: diagnostics.tokensOut,
      tokens_thinking: diagnostics.tokensThinking,
    });
    if (error) console.error('ai_analyses insert falló:', error.message);
  };

  // Los dos límites del proveedor tienen código y texto propios: no son un
  // problema de la foto ni del prompt, y la app no debería sugerir sacar otra.
  // Van separados porque la salida es distinta — contra la cuota hay que
  // esperar, contra la saturación alcanza con insistir en unos segundos.
  if (parsed === null && rateLimited) {
    await registrar('ERR_AI_RATE_LIMITED');
    return rateLimitedResponse(retryAfterSeconds);
  }
  if (parsed === null && overloaded) {
    await registrar('ERR_AI_OVERLOADED');
    return overloadedResponse();
  }
  // La demora también es un fallo con nombre propio, y se registra como los
  // otros. Sin esto la app cortaba sola por timeout y no quedaba **ninguna**
  // fila: "el análisis tarda mucho" era una impresión que no se podía medir.
  if (parsed === null && timedOut) {
    await registrar('ERR_UPSTREAM_TIMEOUT');
    return timedOutResponse('cargá la comida a mano');
  }

  const items = validate(parsed);
  if (items === null) {
    // Queda registrado el fallo: es lo que permite saber si el prompt empeoró
    // sin depender de que alguien lo reporte.
    await registrar('ERR_AI_INVALID_RESPONSE');
    return fail(
      'ERR_AI_INVALID_RESPONSE',
      `No pudimos leer la foto (${lastError}). Cargá la comida a mano; la foto queda adjunta.`,
      502,
    );
  }

  if (items.length === 0) {
    return fail(
      'ERR_AI_NO_FOOD',
      currentItems.length > 0
        ? 'El recálculo se quedó sin ítems. Revisá lo que escribiste y probá de nuevo.'
        : 'No vimos comida en la foto. Probá con otra o cargala a mano.',
      422,
    );
  }

  const confidenceAvg =
    items.reduce((acc, i) => acc + i.confidence, 0) / items.length;

  const id = crypto.randomUUID();
  const { error: insertError } = await supabase.from('ai_analyses').insert({
    id,
    user_id: user.id,
    source: 'photo',
    photo_path: photoPath,
    status: 'completed',
    model: GEMINI_MODEL,
    prompt_version: PROMPT_VERSION,
    items,
    raw_response: parsed,
    confidence_avg: Number(confidenceAvg.toFixed(2)),
    latency_ms: latencyMs,
    // También en las que salen bien: es acá donde se ve si el modelo viene
    // razonando de fábrica, que explicaría a la vez la demora y la mitad cara
    // de la factura. Guardarlo solo en los fallos dejaría afuera el caso
    // normal, que es el que se paga todos los días.
    finish_reason: diagnostics.finishReason,
    tokens_in: diagnostics.tokensIn,
    tokens_out: diagnostics.tokensOut,
    tokens_thinking: diagnostics.tokensThinking,
  });
  if (insertError) {
    console.error('ai_analyses insert falló:', insertError.message);
  }

  return ok({
    id,
    // Cómo se llama el plato entero. Puede ser `null` y la app lo resuelve: no
    // vale la pena tirar una estimación buena por una etiqueta que faltó.
    title: validateTitle(parsed),
    items,
    overallConfidence: Number(confidenceAvg.toFixed(2)),
    model: GEMINI_MODEL,
    promptVersion: PROMPT_VERSION,
    latencyMs,
  });
});

/**
 * Base64 por bloques.
 *
 * `String.fromCharCode(...bytes)` parece lo obvio y es una bomba: pasa cada
 * byte como un argumento, y con una foto de 1024 px son ~200 000 argumentos —
 * bastante más de lo que aguanta la pila. Reventaba con **cualquier** foto
 * real, que es por qué el análisis se quedaba cargando para siempre.
 */
function toBase64(bytes: Uint8Array): string {
  const CHUNK = 0x8000;
  let binary = '';
  for (let i = 0; i < bytes.length; i += CHUNK) {
    binary += String.fromCharCode(...bytes.subarray(i, i + CHUNK));
  }
  return btoa(binary);
}
