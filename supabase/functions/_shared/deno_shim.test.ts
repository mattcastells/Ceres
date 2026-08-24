// El mínimo `Deno` que necesita `estimation.ts` para importarse fuera de Deno.
//
// `estimation.ts` lee `Deno.env.get(...)` en el cuerpo del módulo, así que sin
// esto el import explota antes de que ningún test llegue a correr. Va en su
// propio archivo y no dentro del test porque los imports de un módulo ESM se
// evalúan **antes** que su cuerpo: un `globalThis.Deno = ...` escrito arriba del
// `import` igual correría tarde. Importado primero, el orden queda garantizado.
//
// Solo para tests. No lo importa nada de lo que se despliega.

declare global {
  // eslint-disable-next-line no-var
  var Deno: { env: { get(key: string): string | undefined } } | undefined;
}

if (typeof globalThis.Deno === 'undefined') {
  globalThis.Deno = {
    env: {
      get: (key: string) =>
        (globalThis as { process?: { env: Record<string, string | undefined> } })
          .process?.env[key],
    },
  };
}

export {};
