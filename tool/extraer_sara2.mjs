// Extractor de la tabla SARA 2: docs/fuentes/sara2.pdf -> supabase/functions/_shared/sara2_data.ts
//
// SARA 2 es la tabla de composición química de alimentos para Argentina que
// compiló el Ministerio de Salud para la ENNyS 2 (2022): ~1000 alimentos, cada
// 100 g de porción comestible, con versiones cocidas de lo que se come cocido.
// La usa la estimación de comidas (prompt v5): el modelo elige la fila y estima
// los gramos, y las kcal salen de acá en vez de su memoria.
//
// Lee solo las tablas "A" (macronutrientes). De las 20 columnas se quedan las
// que hacen falta: kcal, proteínas, lípidos, carbohidratos disponibles, fibra y
// alcohol.
//
// **Cada fila se valida contra Atwater antes de entrar.** SARA 2 calcula sus
// kcal con 4/4/9/7 sobre los carbohidratos disponibles, así que una fila bien
// leída cierra exacta (salvo redondeo). Una que no cierra es casi seguro una
// columna corrida —con ARGENFOODS el primer intento dio "aceite de oliva, 100 g
// de proteína"—, y no entra: queda listada para revisarla a mano.
//
// Uso:  node tool/extraer_sara2.mjs           (escribe el archivo)
//       node tool/extraer_sara2.mjs --check   (falla si está desactualizado)
//
// Necesita `pdftotext` (poppler; viene con Git para Windows).

import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';

const FUENTE = 'docs/fuentes/sara2.pdf';
const SALIDA = 'supabase/functions/_shared/sara2_data.ts';

/** Columnas de las tablas A, en orden. */
const COLUMNAS = 20;
const IDX = { kcal: 0, prot: 2, lip: 3, choDisp: 14, fibra: 18, alcohol: 19 };

const numero = (t) => Number(t.replace(',', '.'));
const esNumero = (t) => /^-?\d+([.,]\d+)?$/.test(t);

const texto = execFileSync(
  'pdftotext',
  ['-enc', 'UTF-8', '-raw', '-f', '18', '-l', '139', FUENTE, '-'],
  { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 },
);

const filas = [];
const rechazadas = [];

// Las páginas vienen separadas por form feed.
for (const pagina of texto.split('\f')) {
  const lineas = pagina.split(/\r?\n/).map((l) => l.trim());
  const titulo = lineas.find((l) => /^tabla\s*\d+\.?\s*[AB]\s*:/i.test(l));
  if (!titulo || !/^tabla\s*\d+\.?\s*A\s*:/i.test(titulo)) continue;
  const grupo = titulo
    .replace(/^tabla\s*\d+\.?\s*A\s*:\s*/i, '')
    .replace(/,?\s*macronutrientes.*$/i, '')
    .trim();

  // Los datos empiezan después de la fila de unidades ("Kcal g g g mg ...").
  let i = lineas.findIndex((l) => /^Kcal\b/.test(l));
  if (i < 0) continue;
  i++;

  let nombre = [];
  for (; i < lineas.length; i++) {
    const l = lineas[i];
    if (!l) continue;
    // Una tabla B en la misma página, o las notas al pie: ahí termina.
    if (/^tabla\s*\d+\.?\s*B/i.test(l)) break;
    if (/^\*/.test(l) || /^ENNYS/i.test(l) || /^\d+$/.test(l)) continue;

    const tokens = l.split(/\s+/);
    let k = tokens.length;
    while (k > 0 && esNumero(tokens[k - 1])) k--;
    // Más de 20 números: los que sobran son del nombre ("McNuggets x 10").
    if (tokens.length - k > COLUMNAS) k = tokens.length - COLUMNAS;
    const nums = tokens.slice(k);
    const prefijo = tokens.slice(0, k).join(' ');

    if (nums.length < 10) {
      // Solo texto: es parte de un nombre largo.
      nombre.push(l);
      continue;
    }
    if (prefijo) nombre.push(prefijo);
    const crudo = nombre
      .join(' ')
      .replace(/(\p{L})- (\p{Ll})/gu, '$1$2') // "parti- da" -> "partida"
      .replace(/\s+/g, ' ')
      .trim();
    nombre = [];

    // Con las 20 columnas, cada una en su lugar. Si falta alguna celda (vienen
    // en blanco en el PDF), las que importan están en las puntas: las cuatro
    // primeras y las seis últimas.
    const v = nums.map(numero);
    const col = (j) =>
      v.length === COLUMNAS ? v[j] : j < 4 ? v[j] : v[v.length - (COLUMNAS - j)];
    const fila = {
      name: crudo,
      group: grupo,
      kcal: col(IDX.kcal),
      proteinG: col(IDX.prot),
      fatG: col(IDX.lip),
      carbsG: col(IDX.choDisp),
      fiberG: col(IDX.fibra),
      alcoholG: col(IDX.alcohol),
    };

    const atwater =
      4 * fila.proteinG + 4 * fila.carbsG + 9 * fila.fatG + 7 * fila.alcoholG;
    const delta = Math.abs(fila.kcal - atwater);
    const valores = [fila.kcal, fila.proteinG, fila.fatG, fila.carbsG, fila.alcoholG];
    // La suma con margen: la propia tabla tiene filas que pasan 100 g por
    // redondeo. Lo que se busca acá son columnas corridas, que dan cualquier cosa.
    const sanos = valores.every((x) => Number.isFinite(x) && x >= 0) &&
      fila.kcal <= 900 &&
      fila.proteinG + fila.fatG + fila.carbsG + fila.alcoholG <= 110;

    // Misma tolerancia que el catálogo ARGENFOODS de la app (5 kcal o 10 %):
    // alcanza para el redondeo de la tabla y frena una columna corrida.
    if (!crudo || !sanos || delta > Math.max(5, fila.kcal * 0.1)) {
      rechazadas.push({ ...fila, columnas: v.length, atwater: Math.round(atwater) });
    } else {
      filas.push(fila);
    }
  }
}

// Ids estables y cortos: el modelo los copia, así que cuanto más cortos menos
// se equivoca. Se numeran en el orden de la tabla.
const salida = filas.map((f, n) => ({ id: `S${n + 1}`, ...f }));

const ts = `// GENERADO por tool/extraer_sara2.mjs a partir de docs/fuentes/sara2.pdf. No editar a mano.
//
// SARA 2: Tabla de composición química de alimentos para Argentina. Compilación
// para ENNyS 2. Ministerio de Salud de la Nación, 2022. Valores cada 100 g de
// porción comestible; carbohidratos disponibles (sin fibra). Cada fila cierra
// con Atwater 4/4/9/7: el extractor no deja entrar las que no.

export interface Sara2Food {
  id: string;
  name: string;
  group: string;
  kcal: number;
  proteinG: number;
  fatG: number;
  carbsG: number;
  fiberG: number;
  alcoholG: number;
}

export const SARA2: readonly Sara2Food[] = ${JSON.stringify(salida, null, 0)
  .replace(/^\[/, '[\n  ')
  .replace(/\},\{/g, '},\n  {')
  .replace(/\]$/, ',\n]')};
`;

if (process.argv.includes('--check')) {
  const actual = existsSync(SALIDA) ? readFileSync(SALIDA, 'utf8') : '';
  if (actual !== ts) {
    console.error(`${SALIDA} está desactualizado: corré node tool/extraer_sara2.mjs`);
    process.exit(1);
  }
  console.log(`✓ ${SALIDA} al día (${salida.length} alimentos)`);
} else {
  writeFileSync(SALIDA, ts);
  console.log(`✓ ${salida.length} alimentos escritos en ${SALIDA}`);
}

if (rechazadas.length > 0) {
  console.log(`\n${rechazadas.length} filas no cerraron con Atwater y quedaron afuera:`);
  for (const r of rechazadas) {
    console.log(
      `  · ${r.name || '(sin nombre)'} [${r.group}] — ${r.kcal} kcal vs ${r.atwater} ` +
        `(P ${r.proteinG} / G ${r.fatG} / C ${r.carbsG} / A ${r.alcoholG}; ${r.columnas} columnas)`,
    );
  }
}
