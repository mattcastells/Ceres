// La política de reintentos de `callGemini`, contra lo que ya salió mal.
//
// Este bucle se rompió dos veces en dos semanas, y las dos veces en direcciones
// opuestas:
//
// 1. No tenía techo total. Cada intento se cortaba a los 25 s por su cuenta, así
//    que dos intentos daban 50 s de servidor contra 45 s de espera del cliente:
//    la app cortaba primero y el resultado bueno del segundo intento se tiraba.
// 2. Al ponerle el techo, se hizo **terminal** el corte por cuelgue, con el
//    argumento de que un intento lento se repite lento. Los datos de
//    `ai_analyses` dijeron lo contrario: los intentos que fallan no tardan, se
//    cuelgan —vuelven con `tokens_in` en `null`, sin un byte— y el intento
//    siguiente contesta en 5 o 15 s. Los análisis que terminaban en 35 o 40 s
//    eran eso. Cortarlos de una los convirtió en fallos, y la persona terminó
//    reintentando a mano dos o tres veces.
//
// Ninguna de las dos se ve leyendo el código: las dos se ven corriéndolo. Por
// eso esto existe.
//
// El `fetch` está falseado y devuelve al instante, así que el test no espera los
// 18 s de verdad: lo que se prueba es **qué hace el bucle** con cada respuesta,
// no el reloj.
//
// Corre en CI con node, después de bundlear con esbuild.

import './deno_shim.test.ts';
import { RESPONSE_SCHEMA, callGemini, callModel } from './estimation.ts';
import { aContenido, aJsonSchema } from './claude.ts';

let fallos = 0;
function check(ok: boolean, mensaje: string): void {
  if (ok) return;
  fallos++;
  console.error(`✗ ${mensaje}`);
}

/** El cuelgue: lo que tira `fetch` cuando salta nuestro `AbortController`. */
function colgado(): Promise<never> {
  const error = new Error('The signal has been aborted');
  error.name = 'AbortError';
  return Promise.reject(error);
}

/** Una respuesta buena del proveedor, con la forma que lee `readDiagnostics`. */
function bien(texto = '{"items":[],"title":"Milanesa"}'): Promise<unknown> {
  return Promise.resolve({
    ok: true,
    status: 200,
    json: () =>
      Promise.resolve({
        candidates: [
          { content: { parts: [{ text: texto }] }, finishReason: 'STOP' },
        ],
        usageMetadata: {
          promptTokenCount: 1500,
          candidatesTokenCount: 200,
        },
      }),
  });
}

/** Un error HTTP del proveedor. */
function httpError(status: number, body = ''): Promise<unknown> {
  return Promise.resolve({
    ok: false,
    status,
    text: () => Promise.resolve(body),
  });
}

/**
 * Corre `callGemini` con una lista de respuestas guionadas y devuelve el
 * resultado junto con cuántas veces se llamó al proveedor.
 *
 * La cuenta de llamadas es la mitad del test: un reintento de más no se ve en el
 * resultado —sale igual— y se paga igual.
 */
async function correr(guion: Array<() => Promise<unknown>>) {
  let llamadas = 0;
  const original = globalThis.fetch;
  globalThis.fetch = ((..._args: unknown[]) => {
    const paso = guion[Math.min(llamadas, guion.length - 1)];
    llamadas++;
    return paso() as Promise<Response>;
  }) as typeof fetch;
  try {
    const outcome = await callGemini('clave-de-mentira', [{ text: 'hola' }]);
    return { ...outcome, llamadas };
  } finally {
    globalThis.fetch = original;
  }
}

/**
 * Lo mismo pero contra `callModel`, con el respaldo falseado.
 *
 * El respaldo se inyecta en vez de falsear su `fetch` porque lo que se prueba
 * acá es **la decisión** —cuándo se llama y con qué resultado se queda—, no el
 * cable contra Anthropic. Esa mitad no se puede probar sin una clave, y hacerla
 * pasar por un `fetch` de mentira solo daría la sensación de que sí.
 */
async function correrModel(
  guion: Array<() => Promise<unknown>>,
  opciones: { hay: boolean; respaldoBueno?: boolean },
) {
  let llamadas = 0;
  let respaldos = 0;
  const original = globalThis.fetch;
  globalThis.fetch = ((..._args: unknown[]) => {
    const paso = guion[Math.min(llamadas, guion.length - 1)];
    llamadas++;
    return paso() as Promise<Response>;
  }) as typeof fetch;

  const respaldo = (async () => {
    respaldos++;
    const bueno = opciones.respaldoBueno !== false;
    return {
      parsed: bueno ? { items: [], title: 'Milanesa' } : null,
      lastError: bueno ? '' : 'no contestó',
      rateLimited: false,
      overloaded: false,
      timedOut: false,
      retryAfterSeconds: null,
      diagnostics: {
        finishReason: bueno ? 'END_TURN' : null,
        tokensIn: bueno ? 1600 : null,
        tokensOut: bueno ? 250 : null,
        tokensThinking: null,
      },
      modelUsed: bueno ? 'claude-de-mentira' : null,
    };
  }) as never;

  try {
    const outcome = await callModel(
      'clave-de-mentira',
      [{ text: 'hola' }],
      RESPONSE_SCHEMA,
      respaldo,
      () => opciones.hay,
    );
    return { ...outcome, llamadas, respaldos };
  } finally {
    globalThis.fetch = original;
  }
}

const main = async () => {
  // ── Lo que rompió la versión 1.22.2 ───────────────────────────────────
  {
    const r = await correr([colgado, bien]);
    check(r.parsed !== null, 'un cuelgue seguido de una respuesta buena no devolvió el resultado');
    check(r.timedOut === false, 'quedó marcado como timeout habiendo contestado el segundo intento');
    check(r.llamadas === 2, `se esperaban 2 llamadas y hubo ${r.llamadas}`);
    check(r.diagnostics.tokensIn === 1500, 'no se leyeron los diagnósticos del intento bueno');
  }

  // Dos cuelgues seguidos tampoco se rinden: en `ai_analyses` vienen de a
  // rachas, y el tercero suele contestar.
  {
    const r = await correr([colgado, colgado, bien]);
    check(r.parsed !== null, 'dos cuelgues seguidos se rindieron antes del tercer intento');
    check(r.llamadas === 3, `se esperaban 3 llamadas y hubo ${r.llamadas}`);
    check(r.timedOut === false, 'marcado como timeout con el tercer intento bueno');
  }

  // ── Y lo que no puede volver a pasar del otro lado ─────────────────────
  // Rendirse tiene que ser posible: si se cuelgan todos, sale un timeout
  // reportable y no un intento eterno.
  {
    const r = await correr([colgado]);
    check(r.parsed === null, 'todos colgados y sin embargo devolvió algo');
    check(r.timedOut === true, 'todos colgados y no se marcó como timeout');
    check(r.llamadas === 3, `el techo de intentos no se respetó: ${r.llamadas}`);
  }

  // Un JSON ilegible a `temperature: 0` es determinista: pedirlo de nuevo trae
  // lo mismo. Se corta aunque queden intentos, porque el de más se paga.
  {
    const r = await correr([() => bien('esto no es json')]);
    check(r.parsed === null, 'un JSON ilegible pasó como bueno');
    check(r.timedOut === false, 'un JSON ilegible se reportó como timeout');
    check(
      r.llamadas === 2,
      `un JSON ilegible tiene que costar 2 llamadas, no ${r.llamadas}`,
    );
  }

  // El 429 es la cuota del proyecto entero: insistir ahí gasta el cupo de la
  // próxima persona que saque una foto. Una sola llamada.
  {
    const r = await correr([() => httpError(429, '{"error":{"details":[{"retryDelay":"26s"}]}}')]);
    check(r.rateLimited === true, 'el 429 no se marcó como cuota del proveedor');
    check(r.retryAfterSeconds === 26, `no se leyó el retryDelay: ${r.retryAfterSeconds}`);
    check(r.llamadas === 1, `el 429 no se reintenta, y hubo ${r.llamadas} llamadas`);
    check(r.timedOut === false, 'el 429 se reportó como timeout');
  }

  // ── Cuándo entra el respaldo, y cuándo no ─────────────────────────────
  // La misma clase de error que los de arriba: no se ve leyéndolo. Un respaldo
  // que corre de más se paga en cada análisis; uno que corre de menos no existe.

  // Sin `ANTHROPIC_API_KEY` esto tiene que comportarse como antes de que el
  // respaldo existiera. Es la comprobación más importante de las de acá abajo:
  // el respaldo no puede empeorar el caso en que no hay respaldo.
  {
    const r = await correrModel([colgado], { hay: false });
    check(r.parsed === null, 'sin respaldo configurado devolvió algo');
    check(r.timedOut === true, 'sin respaldo se perdió el motivo del fallo');
    check(r.respaldos === 0, `se llamó al respaldo sin clave: ${r.respaldos}`);
  }

  // Un análisis que salió no se paga dos veces.
  {
    const r = await correrModel([bien], { hay: true });
    check(r.parsed !== null, 'Gemini contestó y el resultado se perdió');
    check(r.respaldos === 0, 'se llamó al respaldo con Gemini contestando');
    check(
      r.modelUsed === 'gemini-3.6-flash',
      `el modelo reportado no es el que contestó: ${r.modelUsed}`,
    );
  }

  // El caso para el que se escribió todo esto: Gemini se cuelga las tres veces.
  {
    const r = await correrModel([colgado], { hay: true });
    check(r.parsed !== null, 'el respaldo contestó y el resultado se perdió');
    check(r.respaldos === 1, `el respaldo corre una sola vez, no ${r.respaldos}`);
    check(
      r.modelUsed === 'claude-de-mentira',
      `contestó el respaldo y la fila diría ${r.modelUsed}`,
    );
    check(r.timedOut === false, 'contestó el respaldo y quedó marcado como timeout');
  }

  // El 429 de Google no se reintenta contra Google —gasta el cupo de otro— pero
  // sí contra otro proveedor, que tiene su propia cuota. Son 8 en dos semanas.
  {
    const r = await correrModel([() => httpError(429, '')], { hay: true });
    check(r.respaldos === 1, 'la cuota agotada de Google no llamó al respaldo');
    check(r.parsed !== null, 'el respaldo no salvó un 429');
  }

  // Si fallan los dos, lo que se le dice a la persona sale del primero: un 429
  // de Google y un cuelgue de Claude no son la misma salida para ella.
  {
    const r = await correrModel([colgado], { hay: true, respaldoBueno: false });
    check(r.parsed === null, 'fallaron los dos y devolvió algo');
    check(r.timedOut === true, 'fallaron los dos y se perdió el motivo de Gemini');
    check(
      r.lastError.includes('respaldo:'),
      `el error no dice qué pasó con el respaldo: ${r.lastError}`,
    );
  }

  // ── La traducción del contrato ────────────────────────────────────────
  // Un schema mal traducido no falla ruidoso: el modelo devuelve algo con otra
  // forma, `validate()` lo descarta y queda como "el modelo devolvió cualquier
  // cosa". Se prueba acá porque es puro y no necesita red.
  {
    const s = aJsonSchema(RESPONSE_SCHEMA) as Record<string, unknown>;
    check(s.type === 'object', `el tipo raíz no se tradujo: ${s.type}`);
    const props = s.properties as Record<string, Record<string, unknown>>;
    check(props.title.type === 'string', 'un tipo hoja quedó en mayúscula');
    check(
      s.additionalProperties === false,
      'no se cerró el objeto: un campo de más solo puede confundir',
    );
    const item = (props.items.items ?? {}) as Record<string, unknown>;
    const campos = item.properties as Record<string, Record<string, unknown>>;
    check(campos.kcal.type === 'integer', 'INTEGER no se tradujo a integer');
    check(
      Array.isArray(campos.unit.enum) && campos.unit.enum.includes('g'),
      'se perdió el enum de unidades al traducir',
    );
  }

  // El orden de las partes es parte del prompt: en la foto la aclaración va
  // después de la imagen a propósito.
  {
    const c = aContenido([
      { text: 'prompt' },
      { inlineData: { mimeType: 'image/jpeg', data: 'AAAA' } },
      { text: 'aclaración' },
    ]) as Array<Record<string, unknown>>;
    check(c.length === 3, `se perdió una parte al traducir: ${c.length}`);
    check(c[0].type === 'text' && c[2].type === 'text', 'se alteró el orden');
    const src = c[1].source as Record<string, unknown>;
    check(
      c[1].type === 'image' && src.type === 'base64' &&
        src.media_type === 'image/jpeg' && src.data === 'AAAA',
      'la imagen no se tradujo a un bloque de Claude',
    );
  }

  if (fallos > 0) {
    console.error(`\n${fallos} comprobación(es) fallaron.`);
    throw new Error('estimation.test.ts falló');
  }
  console.log('✓ 40 comprobaciones de la política de reintentos y del respaldo');
};

await main();
