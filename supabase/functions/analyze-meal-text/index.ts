// analyze-meal-text — estimar una comida a partir de una descripción escrita.
//
// "dos empanadas de carne y una coca". Es lo que Open Food Facts no puede
// contestar: su base son productos envasados con código de barras, y casi todo
// lo que se come acá —asado, milanesa, empanada, un plato de fideos— no tiene
// código de barras ni etiqueta.
//
// Comparte con `analyze-meal-photo` el contrato de salida, la validación, la
// cuota y el manejo de errores (`_shared/estimation.ts`). Lo único distinto es
// qué se le manda al modelo: acá texto, allá una imagen.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { PROMPT_TEXT_V1 } from './prompts/text_v1.ts';
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

/** Una descripción más larga que esto no es una comida, es un relato. */
const MAX_DESCRIPTION = 400;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return fail('ERR_UNAUTHENTICATED', 'Falta la sesión.', 401);

  const geminiKey = Deno.env.get('GEMINI_API_KEY');
  if (!geminiKey) {
    return fail(
      'ERR_PROVIDER_UNAVAILABLE',
      'La estimación por texto no está configurada en el servidor.',
      503,
    );
  }

  // Con el JWT de quien llama, no con la secret key: así RLS sigue aplicando.
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_PUBLISHABLE_KEY') ?? Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: userData, error: userError } = await supabase.auth.getUser();
  const user = userData?.user;
  if (userError || !user) return fail('ERR_UNAUTHENTICATED', 'Tu sesión venció.', 401);

  let description: string;
  // Los ítems que la comida ya tiene. Cuando vienen, esto es el recálculo de
  // una comida sin foto y `description` es la corrección, no el plato entero.
  let currentItems: ReturnType<typeof parseCurrentItems> = [];
  try {
    const body = await req.json();
    description = String(body.description ?? '').trim();
    currentItems = parseCurrentItems(body.currentItems);
  } catch {
    return fail('ERR_VALIDATION', 'Falta la descripción.');
  }
  if (description.length < 3) {
    return fail(
      'ERR_VALIDATION',
      currentItems.length > 0
        ? 'Contanos qué hay que corregir, con un poco más de detalle.'
        : 'Contanos qué comiste, con un poco más de detalle.',
    );
  }
  if (description.length > MAX_DESCRIPTION) {
    description = description.slice(0, MAX_DESCRIPTION);
  }

  // ── Cuota diaria ───────────────────────────────────────────────────────
  // Comparte el cupo con el análisis por foto: las dos gastan lo mismo del
  // proveedor, y separarlas daría 40 por día por la puerta de atrás.
  //
  // `check_rate_limit` es un `insert ... on conflict ... do update ...
  // returning` atómico (migración 24): dos pedidos en paralelo del mismo
  // usuario no pueden leer el mismo conteo viejo y pasar juntos el chequeo,
  // que es lo que sí podía pasar contando filas de `ai_analyses` a mano.
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
      `Llegaste a las ${DAILY_QUOTA} estimaciones de hoy. Podés cargar la comida a mano.`,
      429,
    );
  }

  // ── Gemini ─────────────────────────────────────────────────────────────
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
      [{
        text: currentItems.length > 0
          ? `${PROMPT_TEXT_V1}\n${recalculatedFrom(currentItems, description, {
            withPhoto: false,
          })}`
          : `${PROMPT_TEXT_V1}\n\nDescripción: ${description}`,
      }],
    );

  // `insert` no lanza: devuelve `{ error }`. Ignorarlo fue cómo esta función
  // pasó meses sin registrar una sola fila —`photo_path` era `not null` y una
  // estimación por texto no tiene foto (migración 26)—. Se mira el error y se
  // deja en el log: una tabla vacía que debería tener filas no puede ser una
  // sorpresa la próxima vez.
  const registrar = async (status: string, errorCode?: string) => {
    const { error } = await supabase.from('ai_analyses').insert({
      id: crypto.randomUUID(),
      user_id: user.id,
      source: 'text',
      status,
      model: GEMINI_MODEL,
      prompt_version: PROMPT_VERSION,
      error_code: errorCode,
      latency_ms: latencyMs,
      // Migración 39: lo que el proveedor contó de esta corrida.
      finish_reason: diagnostics.finishReason,
      tokens_in: diagnostics.tokensIn,
      tokens_out: diagnostics.tokensOut,
      tokens_thinking: diagnostics.tokensThinking,
    });
    if (error) console.error('ai_analyses insert falló:', error.message);
  };

  if (parsed === null && rateLimited) {
    await registrar('failed', 'ERR_AI_RATE_LIMITED');
    return rateLimitedResponse(retryAfterSeconds);
  }
  if (parsed === null && overloaded) {
    await registrar('failed', 'ERR_AI_OVERLOADED');
    return overloadedResponse();
  }
  if (parsed === null && timedOut) {
    await registrar('failed', 'ERR_UPSTREAM_TIMEOUT');
    return timedOutResponse('cargá la comida a mano');
  }

  const items = validate(parsed);
  if (items === null) {
    await registrar('failed', 'ERR_AI_INVALID_RESPONSE');
    return fail(
      'ERR_AI_INVALID_RESPONSE',
      `No pudimos interpretar la respuesta (${lastError}). Cargá la comida a mano.`,
      502,
    );
  }

  if (items.length === 0) {
    return fail(
      'ERR_AI_NO_FOOD',
      currentItems.length > 0
        ? 'El recálculo se quedó sin ítems. Revisá lo que escribiste y probá de nuevo.'
        : 'No reconocimos ninguna comida en esa descripción. Probá nombrando los ' +
          'alimentos y las cantidades: "dos empanadas de carne, un vaso de coca".',
      422,
    );
  }

  const confidenceAvg =
    items.reduce((acc, i) => acc + i.confidence, 0) / items.length;

  const id = crypto.randomUUID();
  const { error: insertError } = await supabase.from('ai_analyses').insert({
    id,
    user_id: user.id,
    source: 'text',
    status: 'completed',
    model: GEMINI_MODEL,
    prompt_version: PROMPT_VERSION,
    items,
    raw_response: parsed,
    confidence_avg: Number(confidenceAvg.toFixed(2)),
    latency_ms: latencyMs,
    finish_reason: diagnostics.finishReason,
    tokens_in: diagnostics.tokensIn,
    tokens_out: diagnostics.tokensOut,
    tokens_thinking: diagnostics.tokensThinking,
  });
  if (insertError) {
    // La estimación es buena y se devuelve igual: no se le va a negar a nadie
    // por un problema nuestro de registro. Pero queda en el log, y el `id` no
    // se puede seguir usando como si la fila existiera.
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
