// El segundo proveedor, que existe por un solo motivo: Gemini se cuelga.
//
// Los datos de `ai_analyses` entre el 1 y el 28 de agosto, sobre 215 llamadas:
// **el 21 % de los intentos vuelve sin un byte**. No es el modelo pensando
// lento —cuando contesta, contesta en 9,6 s de mediana y nunca pasó de 28,7 s—,
// es que la llamada se muere muda y hay que esperar el tope entero para
// enterarse. Y no es nuestro: no depende del tamaño de la foto (mediana 140 kB,
// máximo 240 kB, y la tasa de cuelgue es igual en todas las bandas), ni de si
// el isolate estaba frío, ni de la forma del pedido.
//
// Reintentar contra Google arregla el caso suelto y **no arregla el que duele**:
// el 28 de agosto a las 13:03 hubo cinco fallos en seis minutos, uno de ellos
// un 503. Cuando el proveedor está caído, insistirle es esperar más para el
// mismo no. Contra eso solo sirve otro proveedor, porque lo único que baja la
// probabilidad conjunta es que los fallos sean **independientes**.
//
// Por eso esto es un respaldo y no un reemplazo: Gemini sigue primero —está
// medido, el prompt está afinado contra él y es más barato—, y Claude corre
// solo cuando el primero ya falló por algo pasajero. O sea en ~1 de cada 15
// análisis, que es donde la cuenta cierra: se paga un modelo caro justo en las
// veces que hoy son un fallo en la cara de la persona.
//
// **Todo lo de acá adentro degrada a lo de antes.** Si no hay clave, si el SDK
// no carga, si la respuesta viene rara: se devuelve el fallo de Gemini tal cual
// y la app se comporta como el martes pasado. Un respaldo que puede romper lo
// que respalda no es un respaldo.

import type { GeminiDiagnostics } from './estimation.ts';

/**
 * El modelo del respaldo.
 *
 * Opus 5 y no uno más chico porque acá lo que se estima es **la porción**, que
 * es de donde salen las calorías que después mira una nutricionista. Es el
 * mismo argumento que en `estimation.ts` mantuvo el razonamiento en `medium`:
 * un número mal estimado no se nota, y por eso no se puede elegir el barato sin
 * medir. Cuando haya con qué medirlo, bajarlo es un `secrets set`.
 */
export const CLAUDE_MODEL = Deno.env.get('CLAUDE_MODEL') ?? 'claude-opus-5';

/**
 * Cuánto se le deja razonar, en la escala de Claude.
 *
 * `medium` para que se parezca a lo que hace Gemini hoy (`thinkingLevel:
 * medium`) y porque este intento corre **contra un reloj**: entra recién
 * después de que Gemini se colgó, así que le queda lo que sobró del
 * presupuesto. `high` —el default de la API— pensaría más de lo que hay.
 */
const CLAUDE_EFFORT = (Deno.env.get('CLAUDE_EFFORT') ?? 'medium')
  .trim()
  .toLowerCase();

/** La versión del SDK, clavada: un respaldo que cambia solo no es un respaldo. */
const SDK = 'npm:@anthropic-ai/sdk@0.122.0';

export interface ClaudeOutcome {
  parsed: unknown;
  lastError: string;
  rateLimited: boolean;
  overloaded: boolean;
  timedOut: boolean;
  retryAfterSeconds: number | null;
  diagnostics: GeminiDiagnostics;
  /** Qué modelo contestó de verdad, para que `ai_analyses.model` no mienta. */
  modelUsed: string | null;
}

/** Está configurado, o esto no existe y `callModel` se comporta como antes. */
export function claudeDisponible(): boolean {
  return (Deno.env.get('ANTHROPIC_API_KEY') ?? '').trim().length > 0;
}

/**
 * El schema de Gemini, en JSON Schema.
 *
 * Gemini usa el dialecto OpenAPI con los tipos en mayúscula (`'STRING'`);
 * Claude usa JSON Schema, en minúscula. La traducción se hace acá en vez de
 * mantener dos schemas porque **dos contratos separados se separan más**: el
 * día que alguien agregue un campo, lo va a agregar en uno solo.
 *
 * `additionalProperties: false` va en cada objeto porque los modos estrictos lo
 * piden, y porque es lo que ya queremos: `validate()` descarta lo que no
 * reconoce, así que un campo de más solo puede confundir.
 */
export function aJsonSchema(node: unknown): unknown {
  if (Array.isArray(node)) return node.map(aJsonSchema);
  if (typeof node !== 'object' || node === null) return node;

  const salida: Record<string, unknown> = {};
  for (const [clave, valor] of Object.entries(node as Record<string, unknown>)) {
    if (clave === 'type' && typeof valor === 'string') {
      salida.type = valor.toLowerCase();
      continue;
    }
    salida[clave] = aJsonSchema(valor);
  }
  if (salida.type === 'object' && salida.properties !== undefined) {
    salida.additionalProperties = false;
  }
  return salida;
}

/**
 * Las `parts` de Gemini, en bloques de contenido de Claude.
 *
 * Se traduce en vez de cambiar a los que llaman porque **el orden es parte del
 * prompt**: en `analyze-meal-photo` la aclaración va después de la imagen a
 * propósito —lo que dice es sobre lo que se ve—. Si cada función armara su
 * propia lista para cada proveedor, ese detalle se perdería en una de las dos.
 */
export function aContenido(parts: unknown[]): unknown[] {
  const bloques: unknown[] = [];
  for (const part of parts) {
    const p = part as {
      text?: unknown;
      inlineData?: { mimeType?: unknown; data?: unknown };
    };
    if (typeof p?.text === 'string') {
      bloques.push({ type: 'text', text: p.text });
      continue;
    }
    const datos = p?.inlineData;
    if (typeof datos?.data === 'string') {
      bloques.push({
        type: 'image',
        source: {
          type: 'base64',
          media_type: typeof datos.mimeType === 'string'
            ? datos.mimeType
            : 'image/jpeg',
          data: datos.data,
        },
      });
    }
  }
  return bloques;
}

/** Vacío salvo que el proveedor diga: un `null` es "no sé", un 0 sería mentira. */
function diagnosticoVacio(): GeminiDiagnostics {
  return {
    finishReason: null,
    tokensIn: null,
    tokensOut: null,
    tokensThinking: null,
  };
}

function fallo(
  mensaje: string,
  extra: Partial<ClaudeOutcome> = {},
): ClaudeOutcome {
  return {
    parsed: null,
    lastError: mensaje,
    rateLimited: false,
    overloaded: false,
    timedOut: false,
    retryAfterSeconds: null,
    diagnostics: diagnosticoVacio(),
    modelUsed: null,
    ...extra,
  };
}

/**
 * Un intento contra Claude, con el tiempo que haya quedado.
 *
 * **Uno solo, nunca reintenta.** Entra recién cuando Gemini ya gastó lo suyo, y
 * el techo que importa es el del teléfono: entre que la app espera 90 s y que
 * acá quedan segundos prestados, un segundo intento llegaría tarde igual
 * habiendo gastado el doble.
 *
 * El SDK se importa **acá adentro y no arriba** por dos motivos que dan lo
 * mismo por separado y juntos deciden: el bundle del test se arma con esbuild
 * para node, que no resuelve `npm:`, y esta función corre en 1 de cada 15
 * análisis — cargar el SDK en el arranque de todas las invocaciones sería pagar
 * el arranque quince veces para usarlo una.
 */
export async function callClaude(
  parts: unknown[],
  schema: unknown,
  presupuestoMs: number,
): Promise<ClaudeOutcome> {
  const apiKey = (Deno.env.get('ANTHROPIC_API_KEY') ?? '').trim();
  if (!apiKey) {
    return fallo('Sin ANTHROPIC_API_KEY: no hay respaldo configurado');
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), presupuestoMs);

  try {
    const { default: Anthropic } = await import(SDK);
    // `maxRetries: 0` porque el reintento lo decidimos nosotros: el SDK
    // reintenta por su cuenta un 429 y se comería el presupuesto que le queda
    // al respaldo sin que nadie lo vea.
    const client = new Anthropic({ apiKey, maxRetries: 0 });

    const response = await client.messages.create({
      model: CLAUDE_MODEL,
      max_tokens: 16000,
      messages: [{ role: 'user', content: aContenido(parts) }],
      output_config: {
        effort: CLAUDE_EFFORT,
        format: { type: 'json_schema', schema: aJsonSchema(schema) },
      },
    }, { signal: controller.signal });

    const diagnostics: GeminiDiagnostics = {
      // En mayúscula para que `TERMINAL_FINISH` —escrito contra Gemini— lea a
      // los dos proveedores con la misma regla. `max_tokens` es terminal en los
      // dos: pedir de nuevo lo mismo se corta en el mismo lugar.
      finishReason: typeof response?.stop_reason === 'string'
        ? response.stop_reason.toUpperCase()
        : null,
      tokensIn: response?.usage?.input_tokens ?? null,
      tokensOut: response?.usage?.output_tokens ?? null,
      // Claude no informa los de razonamiento por separado. `null` es la verdad.
      tokensThinking: null,
    };

    // Un rechazo del clasificador llega como un 200 con `stop_reason:
    // 'refusal'`, no como una excepción. Sin este chequeo se leería como "el
    // modelo devolvió cualquier cosa" y mandaría a sacar otra foto.
    if (response?.stop_reason === 'refusal') {
      return fallo('Claude rechazó el pedido', {
        diagnostics,
        modelUsed: CLAUDE_MODEL,
      });
    }

    const texto = (response?.content ?? [])
      .filter((b: { type?: string }) => b?.type === 'text')
      .map((b: { text?: string }) => b.text ?? '')
      .join('');

    if (!texto) {
      return fallo(
        `Claude no devolvió contenido (corte: ${
          diagnostics.finishReason ?? 'sin motivo'
        })`,
        { diagnostics, modelUsed: CLAUDE_MODEL },
      );
    }

    try {
      return {
        parsed: JSON.parse(texto),
        lastError: '',
        rateLimited: false,
        overloaded: false,
        timedOut: false,
        retryAfterSeconds: null,
        diagnostics,
        modelUsed: CLAUDE_MODEL,
      };
    } catch (error) {
      return fallo(
        `Claude devolvió JSON inválido: ${
          error instanceof Error ? error.message : String(error)
        }`,
        { diagnostics, modelUsed: CLAUDE_MODEL },
      );
    }
  } catch (error) {
    if ((error as { name?: unknown })?.name === 'AbortError') {
      return fallo(
        `Claude no contestó en ${Math.round(presupuestoMs / 1000)} s`,
        { timedOut: true },
      );
    }

    // El SDK tira errores con `status`. Se lee el número y no el nombre de la
    // clase porque el import es dinámico: acá no hay a qué hacerle `instanceof`.
    const status = (error as { status?: unknown })?.status;
    const detalle = error instanceof Error ? error.message : String(error);
    if (status === 429) {
      const cabeceras = (error as { headers?: Record<string, string> })?.headers;
      const espera = Number(cabeceras?.['retry-after'] ?? '');
      return fallo(`Claude 429: ${detalle}`, {
        rateLimited: true,
        retryAfterSeconds: Number.isFinite(espera) && espera > 0 ? espera : null,
      });
    }
    if (typeof status === 'number' && status >= 500) {
      return fallo(`Claude ${status}: ${detalle}`, { overloaded: true });
    }
    return fallo(`Claude falló: ${detalle}`);
  } finally {
    clearTimeout(timer);
  }
}
