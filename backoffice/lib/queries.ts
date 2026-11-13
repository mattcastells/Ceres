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
 *
 * ⚠️ **Toda consulta de acá lanza si la base devuelve un error.** supabase-js
 * no lanza: devuelve `{ data: null, error }`, y un `data ?? []` convierte ese
 * error en un vacío perfectamente creíble —"no registró agua este mes"—. Pasó
 * de verdad dos veces (`base_calorie_target`, `tracking_since`), y la auditoría
 * de noviembre encontró que ninguna de estas funciones miraba el error. Ahora
 * lo miran todas con `check`, y la página muestra "no se pudo abrir la ficha"
 * con el mensaje de PostgREST en vez de una ficha a medias.
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
 *  Pedir la que no existe devolvía un 400 que esta capa se tragaba, así que el
 *  objetivo llegaba en null y la línea de referencia no se dibujaba nunca.
 *
 *  `starts_on`/`ends_on` vienen porque el objetivo **cambia dentro de un
 *  período**: la app no edita el vigente, lo cierra y abre otro. Con un solo
 *  objetivo para los 90 días, el día de julio se comparaba contra la meta de
 *  octubre. Ver `lib/goals.ts`. `tdee_kcal` y `bmr_kcal` los escribe la app al
 *  crear el objetivo y son los que usa el balance energético. */
export type Goal = {
  base_calorie_target: number | null;
  protein_g: number | null;
  carbs_g: number | null;
  fat_g: number | null;
  goal_type: string | null;
  starts_on?: string | null;
  ends_on?: string | null;
  tdee_kcal?: number | null;
  bmr_kcal?: number | null;
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

/**
 * Lo que la profesional le escribe al paciente (migración 48).
 *
 * Es lo único —junto con los informes— que el panel escribe. Los datos del
 * paciente siguen siendo de solo lectura: no hay una sola política de escritura
 * sobre ellos para la profesional.
 */
export type CareFeedback = {
  id: string;
  patient_id: string;
  kind: 'feedback' | 'indication';
  local_date: string | null;
  body: string;
  source: 'manual' | 'ai_draft';
  /** `null` = borrador privado: el paciente no lo ve. */
  published_at: string | null;
  read_at: string | null;
  created_at: string;
  updated_at: string;
  /** El objetivo recomendado (migración 53): solo en indicaciones. `target_kcal`
   *  no nulo = es un objetivo; los macros pueden venir en null. */
  target_kcal?: number | null;
  target_protein_g?: number | null;
  target_carbs_g?: number | null;
  target_fat_g?: number | null;
  /** Lo marca el paciente al aplicarlo en la app (`mark_care_target_applied`). */
  applied_at?: string | null;
};

export const FEEDBACK_COLUMNS =
  'id, patient_id, kind, local_date, body, source, published_at, read_at, ' +
  'created_at, updated_at, target_kcal, target_protein_g, target_carbs_g, ' +
  'target_fat_g, applied_at';

/**
 * Un artículo o una receta para todo el equipo (migración 52).
 *
 * Como las devoluciones: borrador privado hasta que se publica, y borrar es
 * `deleted_at`. Lo publicado lo leen en la app los pacientes con un acceso
 * vigente a esta profesional.
 */
export type CareArticle = {
  id: string;
  kind: 'article' | 'recipe';
  title: string;
  body: string;
  tag: string | null;
  /** `null` = borrador: ningún paciente lo ve. */
  published_at: string | null;
  created_at: string;
  updated_at: string;
};

export const ARTICLE_COLUMNS =
  'id, kind, title, body, tag, published_at, created_at, updated_at';

/** Un informe guardado por `care-report`. `content` depende de `kind`; ver
 *  `lib/care-report.ts`. */
export type CareReport = {
  id: string;
  kind: 'professional' | 'team' | 'patient_weekly';
  patient_id: string | null;
  period_from: string;
  period_to: string;
  content: unknown;
  created_at: string;
};

export const REPORT_COLUMNS =
  'id, kind, patient_id, period_from, period_to, content, created_at';

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

/** Una consulta que falló, con el nombre de lo que se estaba pidiendo.
 *
 *  El mensaje de PostgREST solo ("column X does not exist") no dice de qué
 *  tabla; con el prefijo, la pantalla de error señala el lugar en una línea. */
export class QueryError extends Error {
  constructor(what: string, message: string) {
    super(`${what}: ${message}`);
    this.name = 'QueryError';
  }
}

/** Devuelve `data` o lanza. Ver el comentario de arriba del archivo. */
function check<T>(
  what: string,
  res: { data: unknown; error: { message: string } | null },
): T {
  if (res.error) throw new QueryError(what, res.error.message);
  return res.data as T;
}

/** Cuántas filas devuelve PostgREST de una: es el `max-rows` de Supabase, y no
 *  se puede subir desde el cliente —pedir `limit(2000)` igual corta en mil—. */
const PAGINA = 1000;

/** Tope duro, para que un error de datos no arrastre la página entera.
 *
 *  Un año registrando seis comidas por día son 2.190: el techo está bien
 *  arriba de cualquier uso real y solo existe para que un `local_date` corrupto
 *  no convierta esto en un bucle que baja la tabla completa. */
export const TOPE_COMIDAS = 6000;

export type MealsResult = {
  meals: Meal[];
  /** Se llegó a `TOPE_COMIDAS` y puede haber más. La pantalla lo dice: un
   *  tope silencioso es exactamente el corte de mil filas que esto vino a
   *  arreglar, solo que más arriba. */
  truncated: boolean;
};

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
 *
 * Por lo mismo, **una página que falla lanza**: antes cortaba el bucle con lo
 * que hubiera llegado, y la ficha mostraba dos tercios del año como si fueran
 * el año.
 */
export async function fetchMeals(
  db: SupabaseClient,
  userId: string,
  from: string,
  to: string,
): Promise<MealsResult> {
  const out: Meal[] = [];

  for (let desde = 0; desde < TOPE_COMIDAS; desde += PAGINA) {
    const lote = check<Meal[] | null>(
      'comidas',
      await db
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
        .range(desde, desde + PAGINA - 1),
    ) ?? [];

    out.push(...lote);
    if (lote.length < PAGINA) return { meals: out, truncated: false };
  }

  // Salir del bucle por el tope, con la última página llena, es "puede haber
  // más". No se sabe cuántas: contarlas sería otra consulta para un caso que
  // en la práctica es un dato roto.
  return { meals: out, truncated: true };
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
  const data = check<WeightLog[] | null>(
    'peso',
    await db
      .from('weight_logs')
      .select('local_date, weight_kg')
      .eq('user_id', userId)
      .is('deleted_at', null)
      .gte('local_date', from)
      .lte('local_date', to)
      .order('local_date'),
  );
  return data ?? [];
}

export async function fetchWater(
  db: SupabaseClient,
  userId: string,
  from: string,
  to: string,
): Promise<WaterLog[]> {
  const data = check<WaterLog[] | null>(
    'agua',
    await db
      .from('water_logs')
      .select('local_date, glasses')
      .eq('user_id', userId)
      .gte('local_date', from)
      .lte('local_date', to)
      .order('local_date'),
  );
  return data ?? [];
}

export async function fetchActivities(
  db: SupabaseClient,
  userId: string,
  from: string,
  to: string,
): Promise<Activity[]> {
  const data = check<Activity[] | null>(
    'actividad',
    await db
      .from('activities')
      .select(
        'id, local_date, started_at, duration_minutes, estimated_calories, intensity',
      )
      .eq('user_id', userId)
      .is('deleted_at', null)
      .gte('local_date', from)
      .lte('local_date', to)
      .order('local_date', { ascending: false }),
  );
  return data ?? [];
}

/**
 * Los objetivos que estuvieron vigentes **en algún día del período**.
 *
 * Antes era "el último objetivo" a secas, para todo el período: alguien que
 * pasó de 1.800 a 2.100 kcal a mitad de mes tenía los quince días viejos
 * contados contra 2.100, y "días dentro del objetivo" mezclaba dos metas. Ahora
 * vienen todos los que se solapan con el período y cada día se compara con el
 * suyo (`goalForDay` en `lib/goals.ts`).
 *
 * La base garantiza que no se pisan (`goals_no_overlap`), así que para cada
 * día hay como mucho uno.
 */
export async function fetchGoals(
  db: SupabaseClient,
  userId: string,
  from: string,
  to: string,
): Promise<Goal[]> {
  const data = check<Goal[] | null>(
    'objetivos',
    await db
      .from('goals')
      .select(
        'base_calorie_target, protein_g, carbs_g, fat_g, goal_type, ' +
          'starts_on, ends_on, tdee_kcal, bmr_kcal',
      )
      .eq('user_id', userId)
      .lte('starts_on', to)
      .or(`ends_on.is.null,ends_on.gte.${from}`)
      .order('starts_on', { ascending: true }),
  );
  return data ?? [];
}

export async function fetchSleep(
  db: SupabaseClient,
  userId: string,
  from: string,
  to: string,
): Promise<SleepLog[]> {
  const data = check<SleepLog[] | null>(
    'sueño',
    await db
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
      .order('local_date'),
  );
  return data ?? [];
}

export async function fetchMeasurements(
  db: SupabaseClient,
  userId: string,
  from: string,
  to: string,
): Promise<Measurement[]> {
  const data = check<Measurement[] | null>(
    'medidas',
    await db
      .from('body_measurements')
      .select('local_date, metric, value, unit')
      .eq('user_id', userId)
      .is('deleted_at', null)
      .gte('local_date', from)
      .lte('local_date', to)
      .order('local_date'),
  );
  return data ?? [];
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
  const data = check<DayMarker[] | null>(
    'contexto del día',
    await db
      .from('day_markers')
      .select('local_date, kind, severity, note, tags')
      .eq('user_id', userId)
      .is('deleted_at', null)
      .gte('local_date', from)
      .lte('local_date', to)
      .order('local_date'),
  );
  return data ?? [];
}

export async function fetchAlcohol(
  db: SupabaseClient,
  userId: string,
  from: string,
  to: string,
): Promise<AlcoholLog[]> {
  const data = check<Record<string, unknown>[] | null>(
    'alcohol',
    await db
      .from('alcohol_logs')
      .select('id, local_date, drink_type, quantity, std_drinks, kcal, note')
      .eq('user_id', userId)
      .is('deleted_at', null)
      .gte('local_date', from)
      .lte('local_date', to)
      .order('local_date'),
  );

  // `numeric` vuelve como String de PostgREST para no perder precisión. Sin
  // este paso, `std_drinks` sumaba como texto y "1" + "2" daba "12".
  return (data ?? []).map((r) => ({
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
 * Lo que esta profesional le escribió a este paciente: borradores y
 * publicados, sin los borrados.
 *
 * El filtro por `author_id` es el mismo "además de RLS" del resto del archivo:
 * la policy ya devuelve solo lo propio, pero si mañana se abre la lectura a
 * otras profesionales del mismo consultorio, esta pantalla no tiene que empezar
 * a mostrar como suyo lo que escribió otra.
 */
export async function fetchFeedback(
  db: SupabaseClient,
  authorId: string,
  patientId: string,
): Promise<CareFeedback[]> {
  const data = check<CareFeedback[] | null>(
    'devoluciones',
    await db
      .from('care_feedback')
      .select(FEEDBACK_COLUMNS)
      .eq('author_id', authorId)
      .eq('patient_id', patientId)
      .is('deleted_at', null)
      .order('created_at', { ascending: false })
      .limit(200),
  );
  return data ?? [];
}

/** Los artículos y recetas propios, sin los borrados, del más nuevo al más
 *  viejo. El filtro por autora es el mismo "además de RLS" de
 *  `fetchFeedback`: la policy también deja ver lo publicado por la
 *  profesional de quien mira, si alguna vez una profesional es paciente de
 *  otra. */
export async function fetchArticles(
  db: SupabaseClient,
  authorId: string,
): Promise<CareArticle[]> {
  const data = check<CareArticle[] | null>(
    'artículos',
    await db
      .from('care_articles')
      .select(ARTICLE_COLUMNS)
      .eq('author_id', authorId)
      .is('deleted_at', null)
      .order('created_at', { ascending: false })
      .limit(200),
  );
  return data ?? [];
}

/**
 * El último informe guardado de un tipo. Se lee antes de ofrecer generar uno:
 * cada informe cuesta una llamada al modelo y entre 10 y 40 segundos, y abrir la
 * ficha no tiene por qué pagarlos de nuevo.
 */
export async function fetchLatestReport(
  db: SupabaseClient,
  requestedBy: string,
  kind: 'professional' | 'team',
  patientId: string | null,
): Promise<CareReport | null> {
  let q = db
    .from('care_reports')
    .select(REPORT_COLUMNS)
    .eq('requested_by', requestedBy)
    .eq('kind', kind);
  q = patientId === null ? q.is('patient_id', null) : q.eq('patient_id', patientId);

  const data = check<CareReport[] | null>(
    'informes',
    await q.order('created_at', { ascending: false }).limit(1),
  );
  return data?.[0] ?? null;
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
  for (const res of respuestas) {
    // Un lote que falla entero es un error de verdad (el bucket, la sesión) y
    // se dice como tal. Una foto suelta que no se pudo firmar —la categoría no
    // está concedida, el archivo ya no existe— viene con `path` en null y se
    // saltea sin romper el resto.
    const data = check<{ path: string | null; signedUrl: string }[] | null>(
      'fotos',
      res,
    );
    for (const row of data ?? []) {
      if (row.path && row.signedUrl) out[row.path] = row.signedUrl;
    }
  }
  return out;
}
