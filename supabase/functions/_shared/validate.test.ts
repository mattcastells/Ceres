// La cuenta de las kcal de cada ítem, contra lo que tiene que hacer.
//
// Desde el prompt v4 el modelo da gramos y valores cada 100 g, y las kcal que
// le quedan a alguien en el historial salen de `validate`. Es aritmética y
// redondeos, o sea el tipo de código que se rompe en silencio: un `/ 100` de
// menos no tira error, multiplica por cien las calorías de todo el mundo. Por
// eso se corre, no alcanza con leerlo.
//
// Corre en CI con node, después de bundlear con esbuild.

import './deno_shim.test.ts';
import { validate } from './estimation.ts';

let fallos = 0;
let comprobaciones = 0;
function check(ok: boolean, mensaje: string): void {
  comprobaciones++;
  if (ok) return;
  fallos++;
  console.error(`✗ ${mensaje}`);
}

/** Un ítem v4 bien formado, con lo que haga falta pisar. */
function item(extra: Record<string, unknown> = {}) {
  return {
    name: 'Arroz blanco',
    preparation: 'hervido',
    visualReference: 'plato 26 cm, ocupa 1/4',
    grams: 180,
    quantity: 180,
    unit: 'g',
    // Arroz blanco cocido: 4·2,7 + 4·28 + 9·0,3 = 125,5, y la tabla dice 130.
    kcalPer100g: 130,
    proteinPer100g: 2.7,
    carbsPer100g: 28,
    fatPer100g: 0.3,
    confidence: 0.8,
    ...extra,
  };
}

const uno = (raw: unknown, kept = []) => validate({ items: [raw] }, kept)?.[0];

// ── La cuenta ───────────────────────────────────────────────────────────
{
  const r = uno(item());
  check(r?.kcal === 234, `180 g × 130 kcal/100 g tienen que ser 234 kcal, no ${r?.kcal}`);
  check(r?.proteinG === 4.9, `proteínas: se esperaban 4,9 g y salió ${r?.proteinG}`);
  check(r?.carbsG === 50.4, `carbohidratos: se esperaban 50,4 g y salió ${r?.carbsG}`);
  check(r?.confidence === 0.8, 'un ítem que cierra no tiene por qué perder confianza');
}

// Con `unit: "g"` la cantidad que se ve es la de la cuenta, no otra.
{
  const r = uno(item({ quantity: 150 }));
  check(r?.quantity === 180, `la cantidad en gramos no se alineó con grams: ${r?.quantity}`);
}

// En otra unidad la cantidad queda como la dijo el modelo.
{
  const r = uno(item({
    name: 'Empanada de carne',
    grams: 180,
    quantity: 2,
    unit: 'unidad',
    kcalPer100g: 280,
    proteinPer100g: 11,
    carbsPer100g: 27,
    fatPer100g: 14,
  }));
  check(r?.quantity === 2 && r?.unit === 'unidad', 'se pisó la cantidad en unidades');
  check(r?.kcal === 504, `2 empanadas de 90 g: se esperaban 504 kcal y salió ${r?.kcal}`);
}

// ── El control contra los macros ────────────────────────────────────────
// 400 kcal cada 100 g con macros que dan 125: el número no sale de ninguna
// tabla. Se lleva al borde de la tolerancia (125 + 25) y baja la confianza.
{
  const r = uno(item({
    grams: 100,
    quantity: 100,
    kcalPer100g: 400,
    proteinPer100g: 10,
    carbsPer100g: 10,
    fatPer100g: 5,
  }));
  check(r?.kcal === 150, `kcal infladas: se esperaban 150 tras corregir y salió ${r?.kcal}`);
  check(r?.confidence === 0.5, `kcal corregidas y la confianza quedó en ${r?.confidence}`);
}

// El alcohol cuenta: una cerveza no es "inconsistente" por no tener grasa.
{
  const r = uno(item({
    name: 'Cerveza',
    grams: 500,
    quantity: 500,
    unit: 'ml',
    kcalPer100g: 43,
    proteinPer100g: 0.5,
    carbsPer100g: 3.6,
    fatPer100g: 0,
    alcoholPer100g: 3.9,
  }));
  check(r?.kcal === 215, `cerveza: se esperaban 215 kcal y salió ${r?.kcal}`);
  check(r?.confidence === 0.8, 'la cerveza se tomó como inconsistente por el alcohol');
}

// Lo que casi no tiene calorías no se corrige por diferencias de 2 kcal.
{
  const r = uno(item({
    name: 'Café',
    grams: 200,
    quantity: 200,
    unit: 'ml',
    kcalPer100g: 2,
    proteinPer100g: 0.1,
    carbsPer100g: 0,
    fatPer100g: 0,
  }));
  check(r?.kcal === 4 && r?.confidence === 0.8, `el café se corrigió de más: ${r?.kcal} kcal`);
}

// ── El control contra el total que dice el modelo ───────────────────────
// Si el total coincide con la cuenta, no pasa nada.
{
  const r = uno(item({ kcal: 234 }));
  check(r?.kcal === 234 && r?.confidence === 0.8, 'un total que coincide alteró el ítem');
}

// Una diferencia chica de redondeo del modelo tampoco: manda la cuenta.
{
  const r = uno(item({ kcal: 260 }));
  check(r?.kcal === 234, `una diferencia de redondeo pisó la cuenta: ${r?.kcal}`);
}

// El error que se busca: el plato entero escrito como si fuera cada 100 g.
// 420 "cada 100 g" sobre 180 g darían 756; el total que dijo es 420.
{
  const r = uno(item({
    name: 'Milanesa frita',
    grams: 180,
    quantity: 1,
    unit: 'unidad',
    kcalPer100g: 420,
    proteinPer100g: 30,
    carbsPer100g: 20,
    fatPer100g: 24,
    kcal: 420,
  }));
  check(r?.kcal === 420, `campos mezclados: se esperaban 420 kcal y salió ${r?.kcal}`);
  check(r?.proteinG === 30, `campos mezclados: los macros no se escalaron (${r?.proteinG} g)`);
  check(r?.confidence === 0.5, 'campos mezclados y la confianza no bajó');
}

// En un ítem chico la proporción no alcanza: 40 kcal de diferencia no mueven
// el día de nadie, y no vale la pena dudar de la cuenta por eso.
{
  const r = uno(item({
    name: 'Manteca',
    grams: 14,
    quantity: 14,
    kcalPer100g: 717,
    proteinPer100g: 0.9,
    carbsPer100g: 0.1,
    fatPer100g: 81,
    kcal: 60,
  }));
  check(r?.kcal === 100, `un ítem chico se corrigió por proporción: ${r?.kcal}`);
}

// ── La tabla SARA 2 (v5) ────────────────────────────────────────────────
// Con una fila válida, los valores cada 100 g salen de la tabla y no del
// modelo: S150 es "Arroz blanco, hervido", 126 kcal (el modelo dijo 130).
{
  const r = uno(item({ saraId: 'S150' }));
  check(r?.kcal === 227, `arroz por tabla: se esperaban 227 kcal y salió ${r?.kcal}`);
  check(r?.proteinG === 4.3, `arroz por tabla: proteínas ${r?.proteinG}`);
  check(r?.confidence === 0.8, 'una fila que coincide no tiene por qué bajar la confianza');
}

// El código se tolera como lo copie el modelo: minúsculas, con el nombre al lado.
{
  const r = uno(item({ saraId: ' s150 Arroz blanco, hervido' }));
  check(r?.kcal === 227, `el código con nombre no se reconoció: ${r?.kcal}`);
}

// Un código que no existe no rompe nada: siguen los valores del modelo.
{
  const r = uno(item({ saraId: 'S99999' }));
  check(r?.kcal === 234, `un código inexistente cambió la cuenta: ${r?.kcal}`);
}
{
  const r = uno(item({ saraId: '' }));
  check(r?.kcal === 234, `saraId vacío cambió la cuenta: ${r?.kcal}`);
}

// Fila equivocada: "Tostadas integrales" (envasadas, 386) para una rebanada de
// pan tostado que el modelo mismo estimó en 260. No se usa la fila, se usa lo
// que estimó el modelo y la confianza baja.
{
  const r = uno(item({
    name: 'Pan integral tostado',
    saraId: 'S379',
    grams: 30,
    quantity: 1,
    unit: 'rebanada',
    kcalPer100g: 260,
    proteinPer100g: 9,
    carbsPer100g: 48,
    fatPer100g: 3.5,
  }));
  check(r?.kcal === 78, `fila equivocada: se esperaban 78 kcal del modelo y salió ${r?.kcal}`);
  check(r?.confidence === 0.5, 'fila equivocada y la confianza no bajó');
}

// ── Lo imposible se tira ────────────────────────────────────────────────
{
  const r = validate({
    items: [item({ proteinPer100g: 40, carbsPer100g: 50, fatPer100g: 30 })],
  });
  check(r?.length === 0, 'pasaron 120 g de macros en 100 g de alimento');
}
{
  const r = validate({ items: [item({ grams: 50000, quantity: 50000 })] });
  check(r?.length === 0, 'pasó un ítem de 50 kg');
}

// ── Red: un modelo que contesta con el contrato viejo ───────────────────
{
  const r = uno({
    name: 'Milanesa',
    quantity: 1,
    unit: 'unidad',
    kcal: 420,
    proteinG: 30,
    carbsG: 20,
    fatG: 24,
    confidence: 0.7,
  });
  check(r?.kcal === 420, 'una respuesta con totales viejos se perdió');
}

// ── Recálculo: lo que no se tocó vuelve con sus números exactos ─────────
{
  const kept = [{
    name: 'Milanesa',
    quantity: 1,
    unit: 'unidad',
    kcal: 420,
    proteinG: 30,
    carbsG: 20,
    fatG: 24,
  }];
  const r = validate({
    items: [
      item({
        name: 'milanesa',
        grams: 160,
        quantity: 1,
        unit: 'unidad',
        kcalPer100g: 250,
        proteinPer100g: 18,
        carbsPer100g: 12,
        fatPer100g: 14,
      }),
      item(),
    ],
  }, kept as never);
  check(r?.[0].kcal === 420, `la milanesa sin tocar cambió a ${r?.[0].kcal} kcal`);
  check(r?.[0].fatG === 24, 'la milanesa sin tocar perdió sus macros');
  check(r?.[1].kcal === 234, 'el ítem nuevo del recálculo no se calculó');
}
// Si la corrección cambió la cantidad, ya no es el mismo ítem: se recalcula.
{
  const kept = [{
    name: 'Arroz blanco',
    quantity: 250,
    unit: 'g',
    kcal: 400,
    proteinG: 7,
    carbsG: 70,
    fatG: 1,
  }];
  const r = uno(item(), kept as never);
  check(r?.kcal === 234, `el arroz corregido a 180 g conservó las kcal viejas: ${r?.kcal}`);
}

if (fallos > 0) {
  console.error(`\n${fallos} comprobación(es) fallaron.`);
  throw new Error('validate.test.ts falló');
}
console.log(`✓ ${comprobaciones} comprobaciones de la cuenta de kcal`);
