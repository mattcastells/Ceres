// Las cuentas del análisis de consulta: balance contra peso, alimentos que se
// repiten, horarios y semana contra semana.
//
// Son números que la nutricionista va a citar en la consulta ("según lo que
// anotaste, tendrías que haber bajado 1,8 kg"), así que un error acá no se ve
// como un error: se ve como un dato. Corre con `npm test`.

import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import {
  alimentosFrecuentes,
  balanceEnergetico,
  diasBajoBasal,
  horarios,
  normalizarNombre,
  semanas,
} from './analysis.ts';
import { rangoDeFechas } from './format.ts';
import type { Goal } from './queries.ts';

const objetivo = (o: Partial<Goal>): Goal => ({
  base_calorie_target: 2000,
  protein_g: 100,
  carbs_g: 200,
  fat_g: 60,
  goal_type: 'lose',
  starts_on: '2026-01-01',
  ends_on: null,
  tdee_kcal: 2500,
  bmr_kcal: 1600,
  ...o,
});

function kcalConstante(desde: string, hasta: string, kcal: number) {
  return new Map(rangoDeFechas(desde, hasta).map((d) => [d, kcal]));
}

describe('balance energético contra peso', () => {
  test('sin TDEE en el objetivo no hay balance que calcular', () => {
    const b = balanceEnergetico({
      kcalPorDia: kcalConstante('2026-10-01', '2026-10-20', 2000),
      goals: [objetivo({ tdee_kcal: null })],
      weights: [],
    });
    assert.equal(b.estado, 'sin-gasto');
  });

  test('con menos de una semana registrada no se proyecta nada', () => {
    const b = balanceEnergetico({
      kcalPorDia: kcalConstante('2026-10-01', '2026-10-05', 2000),
      goals: [objetivo({})],
      weights: [],
    });
    assert.deepEqual(b, { estado: 'pocos-dias', dias: 5 });
  });

  test('sin dos pesajes separados por una semana dice el déficit y nada más', () => {
    const b = balanceEnergetico({
      kcalPorDia: kcalConstante('2026-10-01', '2026-10-20', 2000),
      goals: [objetivo({})],
      weights: [
        { local_date: '2026-10-01', weight_kg: 80 },
        { local_date: '2026-10-04', weight_kg: 79.8 },
      ],
    });
    assert.deepEqual(b, { estado: 'sin-peso', deficitPromedio: 500, dias: 20 });
  });

  test('500 kcal de déficit durante 28 días son 1,8 kg; si la balanza dice −0,4 la brecha es el dato', () => {
    const b = balanceEnergetico({
      kcalPorDia: kcalConstante('2026-10-01', '2026-10-29', 2000),
      goals: [objetivo({})],
      weights: [
        { local_date: '2026-10-29', weight_kg: 79.6 },
        { local_date: '2026-10-01', weight_kg: 80 },
      ],
    });
    assert.equal(b.estado, 'ok');
    if (b.estado !== 'ok') return;
    assert.equal(b.deficitPromedio, 500);
    assert.equal(b.diasEntrePesajes, 28);
    // 500 × 28 / 7700 = 1,818…
    assert.equal(b.esperadoKg, -1.8);
    assert.equal(b.medidoKg, -0.4);
    assert.equal(b.brechaKg, 1.4);
    assert.equal(b.lectura, 'menos-de-lo-esperado');
  });

  test('cada día se compara contra el gasto de su objetivo, no el del último', () => {
    // Del 1 al 14 un TDEE de 2.500; del 15 al 28, uno de 2.000. Comió 2.000
    // todos los días: déficit de 500 la primera mitad y cero la segunda.
    const b = balanceEnergetico({
      kcalPorDia: kcalConstante('2026-10-01', '2026-10-28', 2000),
      goals: [
        objetivo({ starts_on: '2026-09-01', ends_on: '2026-10-14', tdee_kcal: 2500 }),
        objetivo({ starts_on: '2026-10-15', ends_on: null, tdee_kcal: 2000 }),
      ],
      weights: [
        { local_date: '2026-10-01', weight_kg: 80 },
        { local_date: '2026-10-28', weight_kg: 79.1 },
      ],
    });
    assert.equal(b.estado, 'ok');
    if (b.estado !== 'ok') return;
    assert.equal(b.deficitPromedio, 250);
    assert.equal(b.lectura, 'coincide');
  });

  test('una diferencia menor al margen se lee como que coincide, sin −0', () => {
    const b = balanceEnergetico({
      kcalPorDia: kcalConstante('2026-10-01', '2026-10-15', 2500),
      goals: [objetivo({})],
      weights: [
        { local_date: '2026-10-01', weight_kg: 80 },
        { local_date: '2026-10-15', weight_kg: 80 },
      ],
    });
    assert.equal(b.estado, 'ok');
    if (b.estado !== 'ok') return;
    assert.equal(Object.is(b.esperadoKg, -0), false);
    assert.equal(b.lectura, 'coincide');
  });
});

describe('los alimentos que se repiten', () => {
  const item = (name: string, kcal: number) => ({
    id: name,
    name,
    quantity: 1,
    unit: 'u',
    kcal,
    protein_g: 0,
    carbs_g: 0,
    fat_g: 0,
    ai_confidence: null,
  });

  test('agrupa por nombre sin tildes, mayúsculas ni espacios de más', () => {
    assert.equal(normalizarNombre('  Café   con LECHE '), 'cafe con leche');
  });

  test('cuenta, suma kcal y dice en qué momentos aparece', () => {
    const lista = alimentosFrecuentes([
      { local_date: '2026-10-01', slot: 'breakfast', meal_items: [item('Pan integral', 150), item('Café', 10)] },
      { local_date: '2026-10-02', slot: 'breakfast', meal_items: [item('pan integral ', 150)] },
      { local_date: '2026-10-02', slot: 'dinner', meal_items: [item('Pan Integral', 100), item('Milanesa', 400)] },
      { local_date: '2026-10-03', slot: 'lunch', meal_items: [item('Café', 10)] },
    ]);
    // La milanesa aparece una sola vez: no "se repite".
    assert.deepEqual(
      lista.map((a) => a.nombre),
      ['Pan integral', 'Café'],
    );
    const pan = lista[0];
    assert.equal(pan.veces, 3);
    assert.equal(pan.dias, 2);
    assert.equal(pan.kcal, 400);
    // 400 de 820 kcal del período.
    assert.equal(pan.pctKcal, 49);
    assert.deepEqual(pan.momentos, ['breakfast', 'dinner']);
  });
});

describe('los horarios', () => {
  test('primera y última comida en el huso de Buenos Aires, no en UTC', () => {
    const h = horarios([
      { local_date: '2026-10-01', slot: 'breakfast', eaten_at: '2026-10-01T11:00:00Z' },
      { local_date: '2026-10-01', slot: 'dinner', eaten_at: '2026-10-02T00:30:00Z' },
    ]);
    // 11:00 UTC = 08:00 en Buenos Aires; 00:30 UTC = 21:30 del día anterior.
    assert.equal(h.dias[0].primera, 8 * 60);
    assert.equal(h.dias[0].ultima, 21 * 60 + 30);
    assert.equal(h.ventanaPromedio, 13 * 60 + 30);
  });

  test('una cena de después de medianoche no se vuelve la primera comida del día', () => {
    const h = horarios([
      { local_date: '2026-10-03', slot: 'breakfast', eaten_at: '2026-10-03T12:00:00Z' },
      // 00:30 del 4 en Buenos Aires, anotada en el 3.
      { local_date: '2026-10-03', slot: 'dinner', eaten_at: '2026-10-04T03:30:00Z' },
    ]);
    assert.equal(h.dias[0].primera, 9 * 60);
    assert.equal(h.dias[0].ultima, 24 * 60 + 30);
  });

  test('el desvío distingue horarios fijos de horarios que bailan', () => {
    const fijo = horarios(
      ['01', '02', '03'].map((d) => ({
        local_date: `2026-10-${d}`,
        slot: 'breakfast',
        eaten_at: `2026-10-${d}T11:00:00Z`,
      })),
    );
    assert.equal(fijo.variacionPrimera, 0);
    assert.equal(fijo.primeraPromedio, 8 * 60);
  });
});

describe('semana contra semana', () => {
  test('arma semanas de lunes a domingo sobre la ventana y marca las incompletas', () => {
    // Del miércoles 7 al domingo 18 de octubre de 2026.
    const fechas = rangoDeFechas('2026-10-07', '2026-10-18');
    const s = semanas({
      fechas,
      kcalPorDia: new Map([
        ['2026-10-07', 1800],
        ['2026-10-08', 2200],
        ['2026-10-13', 2000],
      ]),
      proteinaPorDia: new Map([
        ['2026-10-07', 80],
        ['2026-10-08', 100],
        ['2026-10-13', 90],
      ]),
      minutosPorDia: new Map([['2026-10-14', 30]]),
      weights: [
        { local_date: '2026-10-12', weight_kg: 80 },
        { local_date: '2026-10-17', weight_kg: 79.5 },
      ],
      diasEnfermedad: new Set(['2026-10-09']),
      diasConAlcohol: new Set(['2026-10-17']),
    });
    assert.equal(s.length, 2);
    assert.deepEqual(
      s.map((x) => [x.desde, x.hasta, x.diasEnVentana, x.incompleta]),
      [
        ['2026-10-07', '2026-10-11', 5, true],
        ['2026-10-12', '2026-10-18', 7, false],
      ],
    );
    assert.equal(s[0].kcalPromedio, 2000);
    assert.equal(s[0].proteinaPromedio, 90);
    assert.equal(s[0].diasEnfermedad, 1);
    assert.equal(s[1].peso, 79.5);
    assert.equal(s[1].minutosActividad, 30);
    assert.equal(s[1].diasConAlcohol, 1);
  });
});

describe('diasBajoBasal', () => {
  const goal = (bmr: number | null): Goal => ({
    base_calorie_target: 1800, protein_g: null, carbs_g: null, fat_g: null, goal_type: 'lose',
    starts_on: '2026-01-01', ends_on: null, bmr_kcal: bmr,
  });

  test('cuenta los días muy por debajo del basal de su objetivo', () => {
    // 1.400 está debajo de 1.450 pero dentro del margen: no se menciona.
    const kcal = new Map([
      ['2026-03-03', 1100], ['2026-03-02', 900], ['2026-03-01', 1500], ['2026-03-04', 1400],
    ]);
    assert.deepEqual(diasBajoBasal(kcal, [goal(1450)]), {
      dias: ['2026-03-02', '2026-03-03'],
      basal: 1450,
    });
  });

  test('sin basal cargado no dice nada', () => {
    assert.deepEqual(diasBajoBasal(new Map([['2026-03-02', 500]]), [goal(null)]), {
      dias: [],
      basal: null,
    });
  });
});
