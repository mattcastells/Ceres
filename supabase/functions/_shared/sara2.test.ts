// La tabla SARA 2 que viaja en las funciones de estimación.
//
// Igual que con el catálogo ARGENFOODS de la app, estos tests no prueban el
// extractor —ya corrió— sino **el archivo que se despliega**. Si alguien lo
// regenera con un extractor roto, o lo edita a mano, esto lo frena antes de
// que una columna corrida termine en el historial de alguien.
//
// Corre en CI con node, después de bundlear con esbuild.

import './deno_shim.test.ts';
import { SARA2 } from './sara2_data.ts';
import { SARA2_PROMPT, sara2Row } from './sara2.ts';

let fallos = 0;
let comprobaciones = 0;
function check(ok: boolean, mensaje: string): void {
  comprobaciones++;
  if (ok) return;
  fallos++;
  console.error(`✗ ${mensaje}`);
}

check(SARA2.length > 900, `la tabla tiene ${SARA2.length} filas; se esperaban más de 900`);

const ids = new Set(SARA2.map((f) => f.id));
check(ids.size === SARA2.length, 'hay códigos repetidos');

for (const f of SARA2) {
  const atwater = 4 * f.proteinG + 4 * f.carbsG + 9 * f.fatG + 7 * f.alcoholG;
  const delta = Math.abs(f.kcal - atwater);
  check(
    delta <= Math.max(5, f.kcal * 0.1),
    `${f.id} ${f.name}: ${f.kcal} kcal no cierra con sus macros (${Math.round(atwater)})`,
  );
  check(
    f.proteinG + f.carbsG + f.fatG + f.alcoholG <= 110,
    `${f.id} ${f.name}: más de 100 g de macros en 100 g`,
  );
  check(f.name.length > 1 && !/\d,\d/.test(f.name), `${f.id}: nombre sospechoso "${f.name}"`);
  check(SARA2_PROMPT.includes(`${f.id} ${f.name}\n`), `${f.id} no está en el prompt`);
}

// Filas que el prompt nombra como ejemplo: si el extractor las renumera, el
// prompt y los tests quedan hablando de otra cosa.
check(sara2Row('S150')?.name === 'Arroz blanco, hervido', 'S150 ya no es el arroz hervido');
check(sara2Row('S379')?.name === 'Tostadas integrales', 'S379 ya no son las tostadas integrales');
check(sara2Row('s150')?.id === 'S150', 'el código en minúsculas no se reconoce');
check(sara2Row('S150 Arroz blanco')?.id === 'S150', 'el código con nombre no se reconoce');
check(sara2Row('S0') === undefined, 'un código inexistente devolvió una fila');
check(sara2Row(150) === undefined, 'un número suelto devolvió una fila');

if (fallos > 0) {
  console.error(`\n${fallos} comprobación(es) fallaron.`);
  throw new Error('sara2.test.ts falló');
}
console.log(
  `✓ ${comprobaciones} comprobaciones de la tabla SARA 2 ` +
    `(${SARA2.length} alimentos; el prompt de la tabla son ${SARA2_PROMPT.length} caracteres)`,
);
