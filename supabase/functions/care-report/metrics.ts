// Los números de los informes, calculados acá y no por el modelo.
//
// Es el mismo reparto que la estimación de comidas desde la v4: el modelo
// interpreta y redacta, la cuenta la hace código que se puede testear. Un
// promedio de calorías que dice el modelo puede estar mal y nadie se entera;
// uno que sale de acá tiene `metrics.test.ts`.

export interface PersonData {
  meals: Array<{
    local_date: string;
    slot: string;
    eaten_at: string | null;
    total_kcal: number;
    total_protein_g: number;
    total_carbs_g: number;
    total_fat_g: number;
    source: string;
    meal_items?: Array<{ name: string | null; kcal: number | null }>;
  }>;
  weights: Array<{ local_date: string; weight_kg: number }>;
  activities: Array<{
    local_date: string;
    duration_minutes: number | null;
    estimated_calories: number | null;
    custom_name: string | null;
    activity_types?: { display_name: string } | null;
  }>;
  water: Array<{ local_date: string; glasses: number }>;
  sleep: Array<{ local_date: string; minutes: number; quality: number | null }>;
  markers: Array<{ local_date: string; kind: string; severity: number | null; note: string | null }>;
  alcohol: Array<{ local_date: string; std_drinks: number }>;
  goal: {
    goal_type: string;
    base_calorie_target: number;
    tdee_kcal: number | null;
    protein_g: number | null;
  } | null;
  indications: string[];
  recentFeedback: string[];
}

/** La fecha de hoy en la zona horaria de la persona, como `YYYY-MM-DD`. */
export function todayIn(tz: string, now = new Date()): string {
  try {
    return new Intl.DateTimeFormat('en-CA', { timeZone: tz }).format(now);
  } catch {
    return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Argentina/Buenos_Aires' }).format(now);
  }
}

/** Suma días a una fecha `YYYY-MM-DD` sin pasar por horas (sin husos). */
export function addDays(date: string, n: number): string {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

const round = (v: number, d = 0) => {
  const f = 10 ** d;
  return Math.round(v * f) / f;
};
const avg = (xs: number[]) => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null);

/** Minutos desde la medianoche, en la zona de la persona. */
function minutesOfDay(iso: string, tz: string): number | null {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  try {
    const parts = new Intl.DateTimeFormat('en-GB', {
      timeZone: tz, hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
    }).formatToParts(d);
    const h = Number(parts.find((p) => p.type === 'hour')?.value);
    const m = Number(parts.find((p) => p.type === 'minute')?.value);
    return Number.isFinite(h) && Number.isFinite(m) ? h * 60 + m : null;
  } catch {
    return null;
  }
}

const hhmm = (mins: number | null) =>
  mins === null ? null : `${String(Math.floor(mins / 60)).padStart(2, '0')}:${String(Math.round(mins % 60)).padStart(2, '0')}`;

/** Una persona come mal un sábado y eso no es un patrón; tres sábados sí. */
const isWeekend = (date: string) => {
  const dow = new Date(`${date}T12:00:00Z`).getUTCDay();
  return dow === 0 || dow === 6;
};

/** Una kcal registrada de grasa corporal ≈ 7.700 kcal. Es la regla de siempre. */
const KCAL_PER_KG = 7700;

export function personMetrics(data: PersonData, from: string, to: string, tz: string) {
  const periodDays = Math.round(
    (Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / 86_400_000,
  ) + 1;

  // ── Comidas, por día ──────────────────────────────────────────────────
  const byDay = new Map<string, { kcal: number; p: number; c: number; f: number; n: number }>();
  const slots: Record<string, number> = {};
  const firstOfDay = new Map<string, number>();
  const lastOfDay = new Map<string, number>();
  const foods = new Map<string, { veces: number; kcal: number }>();
  let aiMeals = 0;

  for (const m of data.meals) {
    const d = byDay.get(m.local_date) ?? { kcal: 0, p: 0, c: 0, f: 0, n: 0 };
    d.kcal += Number(m.total_kcal) || 0;
    d.p += Number(m.total_protein_g) || 0;
    d.c += Number(m.total_carbs_g) || 0;
    d.f += Number(m.total_fat_g) || 0;
    d.n += 1;
    byDay.set(m.local_date, d);
    slots[m.slot] = (slots[m.slot] ?? 0) + 1;
    if (m.source === 'ai_photo' || m.source === 'ai_text') aiMeals++;

    if (m.eaten_at) {
      const mins = minutesOfDay(m.eaten_at, tz);
      if (mins !== null) {
        firstOfDay.set(m.local_date, Math.min(firstOfDay.get(m.local_date) ?? Infinity, mins));
        lastOfDay.set(m.local_date, Math.max(lastOfDay.get(m.local_date) ?? -Infinity, mins));
      }
    }
    for (const it of m.meal_items ?? []) {
      const name = (it.name ?? '').trim().toLowerCase();
      if (!name) continue;
      const f = foods.get(name) ?? { veces: 0, kcal: 0 };
      f.veces += 1;
      f.kcal += Number(it.kcal) || 0;
      foods.set(name, f);
    }
  }

  const logged = [...byDay.entries()].sort(([a], [b]) => a.localeCompare(b));
  const kcalDays = logged.map(([, d]) => d.kcal);
  const target = data.goal?.base_calorie_target ?? null;
  const within = target
    ? kcalDays.filter((k) => Math.abs(k - target) <= target * 0.1).length
    : null;

  const weekend = logged.filter(([date]) => isWeekend(date)).map(([, d]) => d.kcal);
  const weekday = logged.filter(([date]) => !isWeekend(date)).map(([, d]) => d.kcal);

  // ── Peso ──────────────────────────────────────────────────────────────
  // El punto de partida es el último pesaje **antes** del período si existe:
  // comparar contra el primero de adentro perdería la primera semana.
  const before = data.weights.filter((w) => w.local_date < from);
  const inside = data.weights.filter((w) => w.local_date >= from && w.local_date <= to);
  let peso = null as null | {
    inicial: number; final: number; cambio: number; pesajes: number;
    fechaInicial: string; fechaFinal: string;
  };
  if (inside.length > 0) {
    const start = before.length ? before[before.length - 1] : inside[0];
    const end = inside[inside.length - 1];
    if (start.local_date !== end.local_date) {
      peso = {
        inicial: Number(start.weight_kg),
        final: Number(end.weight_kg),
        cambio: round(Number(end.weight_kg) - Number(start.weight_kg), 1),
        pesajes: inside.length,
        fechaInicial: start.local_date,
        fechaFinal: end.local_date,
      };
    }
  }

  // ── Balance registrado ────────────────────────────────────────────────
  // Solo sobre los días con registro, y se dice así: lo que no se registró no
  // se sabe. Es una estimación y viaja marcada como tal.
  const tdee = data.goal?.tdee_kcal ?? null;
  const balanceEstimado = tdee && kcalDays.length >= 3
    ? (() => {
      const deficit = kcalDays.reduce((acc, k) => acc + (tdee - k), 0);
      return {
        gastoEstimadoDiario: Math.round(tdee),
        deficitPromedioDiario: Math.round(deficit / kcalDays.length),
        cambioEsperadoKg: round(-deficit / KCAL_PER_KG, 1),
        sobreDias: kcalDays.length,
      };
    })()
    : null;

  // ── Actividad, sueño, agua, contexto ──────────────────────────────────
  const minutos = data.activities.reduce((a, x) => a + (Number(x.duration_minutes) || 0), 0);
  const tipos = new Map<string, number>();
  for (const a of data.activities) {
    const name = a.custom_name ?? a.activity_types?.display_name ?? 'Actividad';
    tipos.set(name, (tipos.get(name) ?? 0) + 1);
  }
  const sleepAvg = avg(data.sleep.map((s) => s.minutes));
  const waterAvg = avg(data.water.map((w) => w.glasses));

  return {
    periodo: { desde: from, hasta: to, dias: periodDays },
    diasConRegistro: logged.length,
    comidasPorDia: logged.length ? round(data.meals.length / logged.length, 1) : 0,
    calorias: {
      promedio: kcalDays.length ? Math.round(avg(kcalDays)!) : null,
      objetivo: target,
      diasDentroDelObjetivo: within,
      promedioFinDeSemana: weekend.length ? Math.round(avg(weekend)!) : null,
      promedioDiasDeSemana: weekday.length ? Math.round(avg(weekday)!) : null,
      porDia: logged.map(([fecha, d]) => ({ fecha, kcal: Math.round(d.kcal) })),
    },
    macros: logged.length
      ? {
        proteinaPromedioG: Math.round(avg(logged.map(([, d]) => d.p))!),
        objetivoProteinaG: data.goal?.protein_g ?? null,
        carbohidratosPromedioG: Math.round(avg(logged.map(([, d]) => d.c))!),
        grasasPromedioG: Math.round(avg(logged.map(([, d]) => d.f))!),
      }
      : null,
    momentos: slots,
    horarios: {
      primeraComidaPromedio: hhmm(avg([...firstOfDay.values()])),
      ultimaComidaPromedio: hhmm(avg([...lastOfDay.values()])),
    },
    alimentosFrecuentes: [...foods.entries()]
      .sort((a, b) => b[1].veces - a[1].veces || b[1].kcal - a[1].kcal)
      .slice(0, 8)
      .map(([nombre, f]) => ({ nombre, veces: f.veces, kcal: Math.round(f.kcal) })),
    porcentajeCargadoConIA: data.meals.length ? Math.round((aiMeals / data.meals.length) * 100) : null,
    peso,
    balanceEstimado,
    actividad: {
      sesiones: data.activities.length,
      minutos,
      tipos: [...tipos.entries()].sort((a, b) => b[1] - a[1]).slice(0, 4).map(([n, v]) => ({ tipo: n, veces: v })),
    },
    sueno: sleepAvg === null ? null : { promedioHoras: round(sleepAvg / 60, 1), noches: data.sleep.length },
    agua: waterAvg === null ? null : { promedioVasos: round(waterAvg, 1), dias: data.water.length },
    contexto: data.markers.map((m) => ({
      fecha: m.local_date,
      tipo: m.kind === 'sick' ? 'enfermedad' : 'descanso',
      nota: m.note,
    })),
    alcohol: data.alcohol.length
      ? { unidadesEstandar: round(data.alcohol.reduce((a, x) => a + Number(x.std_drinks), 0), 1) }
      : null,
  };
}
