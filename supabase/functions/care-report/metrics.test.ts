// Los números del informe. Corre con Deno o con Node 22+ (TypeScript directo):
//   node supabase/functions/care-report/metrics.test.ts
import { addDays, personMetrics, todayIn, type PersonData } from './metrics.ts';

let failures = 0;
let checks = 0;
function check(cond: unknown, msg: string) {
  checks++;
  if (!cond) {
    failures++;
    console.error(`✗ ${msg}`);
  }
}

const empty: PersonData = {
  meals: [], weights: [], activities: [], water: [], sleep: [], markers: [], alcohol: [],
  goal: null, indications: [], recentFeedback: [],
};

const meal = (local_date: string, kcal: number, eaten_at: string | null = null, extra = {}) => ({
  local_date, slot: 'lunch', eaten_at, total_kcal: kcal, total_protein_g: 30,
  total_carbs_g: 50, total_fat_g: 20, source: 'ai_photo',
  meal_items: [{ name: 'Pan francés', kcal: 140 }], ...extra,
});

// ── Fechas ────────────────────────────────────────────────────────────────
check(addDays('2026-11-01', -1) === '2026-10-31', 'addDays cruza el mes hacia atrás');
check(addDays('2026-12-31', 1) === '2027-01-01', 'addDays cruza el año');
// 02:00 UTC del 11 de noviembre todavía es el 10 en Buenos Aires.
check(
  todayIn('America/Argentina/Buenos_Aires', new Date('2026-11-11T02:00:00Z')) === '2026-11-10',
  'todayIn usa la zona de la persona, no UTC',
);
check(todayIn('Zona/Inventada', new Date('2026-11-11T12:00:00Z')) === '2026-11-11', 'Una zona inválida no rompe');

// ── Sin datos ─────────────────────────────────────────────────────────────
{
  const m = personMetrics(empty, '2026-11-01', '2026-11-07', 'America/Argentina/Buenos_Aires');
  check(m.periodo.dias === 7, 'El período de una semana tiene 7 días');
  check(m.diasConRegistro === 0, 'Sin comidas no hay días con registro');
  check(m.calorias.promedio === null, 'Sin comidas el promedio es null, no 0');
  check(m.peso === null && m.balanceEstimado === null, 'Sin datos no se inventa peso ni balance');
}

// ── Comidas y objetivo ────────────────────────────────────────────────────
{
  const data: PersonData = {
    ...empty,
    goal: { goal_type: 'lose', base_calorie_target: 2000, tdee_kcal: 2500, protein_g: 150 },
    meals: [
      // 13:00 en Buenos Aires = 16:00 UTC.
      meal('2026-11-02', 1000, '2026-11-02T16:00:00Z'),
      meal('2026-11-02', 900, '2026-11-02T23:30:00Z'),
      meal('2026-11-03', 2500, '2026-11-03T16:00:00Z'),
      meal('2026-11-07', 1800, null, { source: 'manual' }), // sábado
    ],
  };
  const m = personMetrics(data, '2026-11-01', '2026-11-07', 'America/Argentina/Buenos_Aires');
  check(m.diasConRegistro === 3, 'Tres días distintos con comidas');
  check(m.calorias.promedio === Math.round((1900 + 2500 + 1800) / 3), 'Promedio por día con registro');
  check(m.calorias.diasDentroDelObjetivo === 2, '1900 y 1800 están dentro del ±10 % de 2000; 2500 no');
  check(m.calorias.promedioFinDeSemana === 1800, 'El sábado va al promedio de fin de semana');
  check(m.horarios.primeraComidaPromedio === '13:00', 'La hora se lee en la zona de la persona');
  check(m.porcentajeCargadoConIA === 75, '3 de 4 comidas por IA');
  check(m.alimentosFrecuentes[0]?.nombre === 'pan francés' && m.alimentosFrecuentes[0]?.veces === 4,
    'Los alimentos se cuentan con el nombre normalizado');
  // Déficit: (2500-1900) + (2500-2500) + (2500-1800) = 1300 kcal → -0,2 kg.
  check(m.balanceEstimado?.cambioEsperadoKg === -0.2, 'El cambio esperado sale de tdee − kcal registradas');
  check(m.balanceEstimado?.sobreDias === 3, 'Y dice sobre cuántos días se calculó');
}

// ── Peso ──────────────────────────────────────────────────────────────────
{
  const data: PersonData = {
    ...empty,
    weights: [
      { local_date: '2026-10-28', weight_kg: 98 },
      { local_date: '2026-11-03', weight_kg: 97.6 },
      { local_date: '2026-11-06', weight_kg: 97.2 },
    ],
  };
  const m = personMetrics(data, '2026-11-01', '2026-11-07', 'America/Argentina/Buenos_Aires');
  check(m.peso?.inicial === 98, 'El punto de partida es el último pesaje anterior al período');
  check(m.peso?.cambio === -0.8, 'El cambio va del pesaje anterior al último del período');
  check(m.peso?.pesajes === 2, 'Pesajes cuenta solo los de adentro');

  const solo = personMetrics(
    { ...empty, weights: [{ local_date: '2026-11-03', weight_kg: 97 }] },
    '2026-11-01', '2026-11-07', 'America/Argentina/Buenos_Aires',
  );
  check(solo.peso === null, 'Con un solo pesaje no hay cambio que informar');
}

console.log(`${checks - failures}/${checks} comprobaciones`);
if (failures > 0) {
  // deno-lint-ignore no-explicit-any
  (globalThis as any).process?.exit?.(1);
  // deno-lint-ignore no-explicit-any
  (globalThis as any).Deno?.exit?.(1);
}
