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
import { callGemini } from './estimation.ts';

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

  if (fallos > 0) {
    console.error(`\n${fallos} comprobación(es) fallaron.`);
    throw new Error('estimation.test.ts falló');
  }
  console.log('✓ 17 comprobaciones de la política de reintentos');
};

await main();
