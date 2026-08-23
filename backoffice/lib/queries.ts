import type { SupabaseClient } from '@supabase/supabase-js';

/**
 * Lo que el panel lee de un paciente.
 *
 * Todas las consultas filtran por `user_id` **además** de apoyarse en RLS. No
 * es redundancia defensiva por gusto: sin el filtro, una tabla que mañana sume
 * una policy nueva empezaría a devolver filas de otra persona en esta misma
 * pantalla, y el bug se vería como "datos mezclados" y no como un permiso mal
 * puesto.
 *
 * Cuando una categoría no está concedida la consulta no falla: devuelve vacío.
 * Por eso la pantalla distingue "no compartido" de "sin registros" con el flag
 * del permiso, no con el largo del resultado.
 */

export type Meal = {
  id: string;
  slot: string;
  local_date: string;
  eaten_at: string;
  name: string | null;
  total_kcal: number;
  total_protein_g: number;
  total_carbs_g: number;
  total_fat_g: number;
  source: string;
  photo_path: string | null;
  meal_items: MealItem[];
};

export type MealItem = {
  id: string;
  name: string;
  quantity: number;
  unit: string;
  kcal: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
  ai_confidence: number | null;
};

export type WeightLog = { local_date: string; weight_kg: number };
export type WaterLog = { local_date: string; glasses: number };
export type Activity = {
  id: string;
  local_date: string;
  started_at: string;
  duration_minutes: number;
  estimated_calories: number | null;
  intensity: string;
};
/** Ojo con los nombres: la columna es `base_calorie_target`, no `target_kcal`.
 *  Pedir la que no existe devuelve un 400 que esta capa se traga, así que el
 *  objetivo llegaba en null y la línea de referencia no se dibujaba nunca. */
export type Goal = {
  base_calorie_target: number | null;
  protein_g: number | null;
  carbs_g: number | null;
  fat_g: number | null;
  goal_type: string | null;
};

export type SleepLog = {
  local_date: string;
  minutes: number;
  quality: string | null;
};

export type Measurement = {
  local_date: string;
  metric: string;
  value: number;
  unit: string;
};

/** Una marca sobre un día: descanso o enfermedad. Ver `docs/contexto-diario.md`. */
export type DayMarker = {
  local_date: string;
  kind: string;
  severity: number | null;
  note: string | null;
  tags: string[] | null;
};

/** Un consumo de alcohol. Hay varios por día a propósito. */
export type AlcoholLog = {
  id: string;
  local_date: string;
  drink_type: string;
  quantity: number;
  std_drinks: number;
  kcal: number;
  note: string | null;
};

export const SEVERITY_LABEL: Record<number, string> = {
  1: 'leve',
  2: 'moderada',
  3: 'fuerte',
};

export const DRINK_LABEL: Record<string, string> = {
  beer: 'Cerveza',
  wine: 'Vino',
  spirits: 'Destilado',
  cocktail: 'Trago',
  cider: 'Sidra',
  other: 'Otra',
};

export const QUALITY_LABEL: Record<string, string> = {
  bad: 'Mala',
  poor: 'Regular',
  ok: 'Normal',
  good: 'Buena',
  great: 'Muy buena',
};

export const METRIC_LABEL: Record<string, string> = {
  waist: 'Cintura',
  hip: 'Cadera',
  chest: 'Pecho',
  arm: 'Brazo',
  thigh: 'Muslo',
  neck: 'Cuello',
  body_fat_pct: 'Grasa corporal',
};

export const SLOT_LABEL: Record<string, string> = {
  breakfast: 'Desayuno',
  lunch: 'Almuerzo',
  dinner: 'Cena',
  snack: 'Snacks',
};

/** Cuántas filas devuelve PostgREST de una: es el `max-rows` de Supabase, y no
 *  se puede subir desde el cliente —pedir `limit(2000)` igual corta en mil—. */
const PAGINA = 1000;

/** Tope duro, para que un error de datos no arrastre la página entera.
 *
 *  Un año registrando seis comidas por día son 2.190: el techo está bien
 *  arriba de cualquier uso real y solo existe para que un `local_date` corrupto
 *  no convierta esto en un bucle que baja la tabla completa. */
const TOPE_COMIDAS = 6000;

/**
 * Las comidas del período, **paginadas**.
 *
 * Sin las páginas, PostgREST devuelve mil filas y corta: no falla, no avisa y
 * no hay nada en la respuesta que lo diga. Con 7, 30 o 90 días eso no se
 * notaba —90 días de cuatro comidas son 360—, pero un año de registro pasa las
 * dos mil y la ficha habría mostrado medio año largo como si fuera el año
 * entero, con los promedios y el conteo de días calculados sobre lo que llegó.
 * Un dato faltante que se ve igual de bien que uno completo es peor que un
 * error.
 */
export async function fetchMeals(
  db: SupabaseClient,
  userId: string,
  from: string,
  to: string,
): Promise<Meal[]> {
  const out: Meal[] = [];

  for (let desde = 0; desde < TOPE_COMIDAS; desde += PAGINA) {
    const { data } = await db
      .from('meals')
      .select(
        'id, slot, local_date, eaten_at, name, total_kcal, total_protein_g, ' +
          'total_carbs_g, total_fat_g, source, photo_path, ' +
          'meal_items(id, name, quantity, unit, kcal, protein_g, carbs_g, ' +
          'fat_g, ai_confidence)',
      )
      .eq('user_id', userId)
      .is('deleted_at', null)
      .gte('local_date', from)
      .lte('local_date', to)
      .order('local_date', { ascending: false })
      .order('eaten_at', { ascending: true })
      // El orden de arriba es total —fecha y hora— así que las páginas no se
      // pisan ni se saltean entre sí.
      .order('id', { ascending: true })
      .range(desde, desde + PAGINA - 1);

    const lote = (data ?? []) as unknown as Meal[];
    out.push(...lote);
    if (lote.length < PAGINA) break;
  }

  return out;
}

/** Si los números de esta comida los estimó el modelo y no los cargó alguien.
 *
 *  Vive acá y no adentro de una pantalla porque lo preguntan la ficha del día y
 *  la galería de fotos, y son dos lugares donde la respuesta tiene que ser la
 *  misma: una estimación nunca se muestra con la misma cara que una medición. */
export function esEstimacionIA(m: Meal): boolean {
  return m.source === 'ai_photo' || m.source === 'ai_text';
}

export async function fetchWeights(
  db: SupabaseClient,
  userId: string,
  from: string,
  to: string,
): Promise<WeightLog[]> {
  const { data } = await db
    .from('weight_logs')
    .select('local_date, weight_kg')
    .eq('user_id', userId)
    .is('deleted_at', null)
    .gte('local_date', from)
    .lte('local_date', to)
    .order('local_date');

  return (data ?? []) as unknown as WeightLog[];
}

export async function fetchWater(
  db: SupabaseClient,
  userId: string,
  from: string,
  to: string,
): Promise<WaterLog[]> {
  const { data } = await db
    .from('water_logs')
    .select('local_date, glasses')
    .eq('user_id', userId)
    .gte('local_date', from)
    .lte('local_date', to)
    .order('local_date');

  return (data ?? []) as unknown as WaterLog[];
}

export async function fetchActivities(
  db: SupabaseClient,
  userId: string,
  from: string,
  to: string,
): Promise<Activity[]> {
  const { data } = await db
    .from('activities')
    .select(
      'id, local_date, started_at, duration_minutes, estimated_calories, intensity',
    )
    .eq('user_id', userId)
    .is('deleted_at', null)
    .gte('local_date', from)
    .lte('local_date', to)
    .order('local_date', { ascending: false });

  return (data ?? []) as unknown as Activity[];
}

export async function fetchGoal(
  db: SupabaseClient,
  userId: string,
): Promise<Goal | null> {
  const { data } = await db
    .from('goals')
    .select('base_calorie_target, protein_g, carbs_g, fat_g, goal_type')
    .eq('user_id', userId)
    .order('starts_on', { ascending: false })
    .limit(1)
    .maybeSingle();

  return (data ?? null) as unknown as Goal | null;
}

export async function fetchSleep(
  db: SupabaseClient,
  userId: string,
  from: string,
  to: string,
): Promise<SleepLog[]> {
  const { data } = await db
    .from('sleep_logs')
    // La lápida se filtra igual que en el resto de las tablas. Faltaba acá y
    // solo acá: `sleep_logs` fue la última en tener `deleted_at` —la agregó
    // `20260801002800_sleep_soft_delete.sql`— y esta consulta quedó de antes,
    // así que una noche que el paciente borró de la app le seguía apareciendo
    // a la profesional, con el promedio y el gráfico contándola.
    .select('local_date, minutes, quality')
    .eq('user_id', userId)
    .is('deleted_at', null)
    .gte('local_date', from)
    .lte('local_date', to)
    .order('local_date');

  return (data ?? []) as unknown as SleepLog[];
}

export async function fetchMeasurements(
  db: SupabaseClient,
  userId: string,
  from: string,
  to: string,
): Promise<Measurement[]> {
  const { data } = await db
    .from('body_measurements')
    .select('local_date, metric, value, unit')
    .eq('user_id', userId)
    .is('deleted_at', null)
    .gte('local_date', from)
    .lte('local_date', to)
    .order('local_date');

  return (data ?? []) as unknown as Measurement[];
}

/**
 * Las marcas del día del período.
 *
 * Van con `wellbeing` porque se conceden con la misma llave que la actividad,
 * el agua y el sueño: las cuatro categorías del permiso son las cuatro pestañas
 * del panel, y una quinta sin pestaña propia rompería esa correspondencia.
 */
export async function fetchDayMarkers(
  db: SupabaseClient,
  userId: string,
  from: string,
  to: string,
): Promise<DayMarker[]> {
  const { data } = await db
    .from('day_markers')
    .select('local_date, kind, severity, note, tags')
    .eq('user_id', userId)
    .is('deleted_at', null)
    .gte('local_date', from)
    .lte('local_date', to)
    .order('local_date');

  return (data ?? []) as unknown as DayMarker[];
}

export async function fetchAlcohol(
  db: SupabaseClient,
  userId: string,
  from: string,
  to: string,
): Promise<AlcoholLog[]> {
  const { data } = await db
    .from('alcohol_logs')
    .select('id, local_date, drink_type, quantity, std_drinks, kcal, note')
    .eq('user_id', userId)
    .is('deleted_at', null)
    .gte('local_date', from)
    .lte('local_date', to)
    .order('local_date');

  // `numeric` vuelve como String de PostgREST para no perder precisión. Sin
  // este paso, `std_drinks` sumaba como texto y "1" + "2" daba "12".
  return ((data ?? []) as unknown as Record<string, unknown>[]).map((r) => ({
    id: String(r.id),
    local_date: String(r.local_date),
    drink_type: String(r.drink_type),
    quantity: Number(r.quantity ?? 0),
    std_drinks: Number(r.std_drinks ?? 0),
    kcal: Number(r.kcal ?? 0),
    note: (r.note as string | null) ?? null,
  }));
}

/**
 * URLs firmadas para las fotos del bucket privado.
 *
 * Se firman del lado del servidor y duran una hora: una URL de foto de comida
 * que no vence es una foto pública con dirección difícil de adivinar, que no es
 * lo mismo que una foto privada.
 */
export async function signPhotos(
  db: SupabaseClient,
  paths: string[],
): Promise<Record<string, string>> {
  const unique = [...new Set(paths.filter(Boolean))];
  if (unique.length === 0) return {};

  // De a 400 y en paralelo: con el período de un año, alguien que fotografía
  // cada comida junta más de mil rutas, y eso en un solo pedido es un cuerpo
  // enorme que además tarda todo lo que tarda el más lento. Partido, son varios
  // pedidos chicos que viajan juntos.
  const lotes: string[][] = [];
  for (let i = 0; i < unique.length; i += 400) lotes.push(unique.slice(i, i + 400));

  const respuestas = await Promise.all(
    lotes.map((lote) =>
      db.storage.from('meal-photos').createSignedUrls(lote, 60 * 60),
    ),
  );

  const out: Record<string, string> = {};
  for (const { data } of respuestas) {
    for (const row of data ?? []) {
      // `path` viene null si esa foto puntual no se pudo firmar —por ejemplo si
      // la categoría no está concedida—. Se saltea sin romper el resto.
      if (row.path && row.signedUrl) out[row.path] = row.signedUrl;
    }
  }
  return out;
}
