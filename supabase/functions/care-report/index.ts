// Informes con IA: el resumen semanal del paciente, el informe de consulta de
// la profesional, el borrador de devolución y el análisis del equipo.
//
// Mismo patrón que el resto de las funciones: entra con la sesión de quien
// llama y la publishable key. **No hay clave de servicio**: lo que se puede
// leer de un paciente lo decide RLS a partir de `care_grants`, exactamente
// igual que en el panel. Si la profesional no tiene la categoría de cuerpo, el
// peso no llega acá, y por lo tanto tampoco al modelo.
//
// La división del trabajo es la de siempre en Ceres: **los números los calcula
// el servidor** (`metrics.ts`) y el modelo solo redacta sobre ellos. Los
// números viajan además en la respuesta, para que la pantalla los muestre
// como datos y no como texto del modelo.

import { createClient, type SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import {
  CORS,
  GEMINI_MODEL,
  callGemini,
  fail,
  ok,
  overloadedResponse,
  rateLimitedResponse,
  timedOutResponse,
} from '../_shared/estimation.ts';
import { effectivePlan } from '../_shared/plan.ts';
import {
  PROMPT_FEEDBACK_DRAFT,
  PROMPT_PATIENT_WEEKLY,
  PROMPT_PROFESSIONAL,
  PROMPT_TEAM,
  REPORT_PROMPT_VERSION,
  SCHEMA_FEEDBACK_DRAFT,
  SCHEMA_PATIENT_WEEKLY,
  SCHEMA_PROFESSIONAL,
  SCHEMA_TEAM,
} from './prompts.ts';
import {
  addDays,
  personMetrics,
  todayIn,
  type PersonData,
} from './metrics.ts';

type Kind = 'patient_weekly' | 'professional' | 'feedback_draft' | 'team';
const KINDS: Kind[] = ['patient_weekly', 'professional', 'feedback_draft', 'team'];

/** Cuántos informes por día. Son caros y no hay razón para pedir cincuenta. */
const WEEKLY_QUOTA = Number(Deno.env.get('WEEKLY_REPORT_QUOTA') ?? '') || 5;
const CARE_QUOTA = Number(Deno.env.get('CARE_REPORT_QUOTA') ?? '') || 40;

const DEFAULT_TZ = 'America/Argentina/Buenos_Aires';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return fail('ERR_UNAUTHENTICATED', 'Falta la sesión.', 401);

  const geminiKey = Deno.env.get('GEMINI_API_KEY');
  if (!geminiKey) {
    return fail('ERR_PROVIDER_UNAVAILABLE', 'Los informes no están configurados en el servidor.', 503);
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_PUBLISHABLE_KEY') ?? Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: userData, error: userError } = await supabase.auth.getUser();
  const user = userData?.user;
  if (userError || !user) return fail('ERR_UNAUTHENTICATED', 'Tu sesión venció.', 401);

  // ── Pedido ─────────────────────────────────────────────────────────────
  let kind: Kind;
  let patientId: string | null = null;
  let focus = '';
  let localDate: string | null = null;
  try {
    const body = await req.json();
    kind = body.kind;
    if (!KINDS.includes(kind)) throw new Error('kind');
    patientId = typeof body.patientId === 'string' ? body.patientId : null;
    focus = typeof body.focus === 'string' ? body.focus.trim().slice(0, 300) : '';
    localDate = typeof body.localDate === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(body.localDate)
      ? body.localDate
      : null;
  } catch {
    return fail('ERR_VALIDATION', 'Falta indicar qué informe pedís.');
  }

  if ((kind === 'professional' || kind === 'feedback_draft') && !patientId) {
    return fail('ERR_VALIDATION', 'Falta indicar el paciente.');
  }
  if (kind === 'patient_weekly') patientId = user.id;

  // ── Plan ───────────────────────────────────────────────────────────────
  // El resumen semanal es IA del paciente: premium (o paciente de una Pro).
  // Los informes de consulta y de equipo son del panel profesional.
  const plan = await effectivePlan(supabase);
  if (kind === 'patient_weekly' && plan === 'free') {
    return fail('ERR_PLAN_REQUIRED', 'El resumen semanal con IA es parte de Ceres Premium.', 402, { plan });
  }
  if (kind !== 'patient_weekly' && (plan === 'free' || plan === 'patient')) {
    return fail('ERR_PLAN_REQUIRED', 'Los informes con IA son parte del plan Pro.', 402, { plan });
  }

  // ── Zona horaria y período ─────────────────────────────────────────────
  const { data: me } = await supabase
    .from('profiles').select('display_name, timezone').eq('id', user.id).maybeSingle();
  const tz = (me?.timezone as string | undefined) ?? DEFAULT_TZ;
  const today = todayIn(tz);
  // Semana cerrada para el paciente (los últimos 7 días sin contar hoy, que
  // todavía no terminó); dos semanas para la consulta, que es el ritmo típico.
  const days = kind === 'patient_weekly' ? 7 : 14;
  const to = addDays(today, -1);
  const from = addDays(to, -(days - 1));

  // ── Permiso, antes de gastar nada ──────────────────────────────────────
  // RLS ya devolvería vacío, pero un informe "sin datos" de alguien que no te
  // dio acceso es un mensaje confuso: mejor decirlo.
  let patientName = (me?.display_name as string | undefined) ?? '';
  let shares = { meals: true, photos: true, body: true, wellbeing: true };
  if (kind === 'professional' || kind === 'feedback_draft') {
    const { data: p } = await supabase
      .from('care_patients')
      .select('patient_name, share_meals, share_photos, share_body, share_wellbeing')
      .eq('patient_id', patientId!)
      .maybeSingle();
    if (!p) return fail('ERR_FORBIDDEN', 'No tenés acceso a ese paciente.', 403);
    patientName = p.patient_name ?? '';
    shares = {
      meals: p.share_meals, photos: p.share_photos, body: p.share_body, wellbeing: p.share_wellbeing,
    };
  }

  // ── Cuota ──────────────────────────────────────────────────────────────
  const bucket = kind === 'patient_weekly' ? 'weekly_report' : 'care_report';
  const max = kind === 'patient_weekly' ? WEEKLY_QUOTA : CARE_QUOTA;
  const { data: withinQuota, error: quotaError } = await supabase.rpc(
    'check_rate_limit', { p_bucket: bucket, p_max: max },
  );
  if (quotaError) return fail('ERR_SERVER', 'No pudimos verificar tu cuota. Probá de nuevo.', 500);
  if (!withinQuota) {
    return fail('ERR_QUOTA_EXCEEDED', `Llegaste a los ${max} informes de hoy.`, 429);
  }

  // ── Datos y prompt ─────────────────────────────────────────────────────
  let prompt: string;
  let schema: unknown;
  let metrics: unknown;

  if (kind === 'team') {
    const { data: overview, error } = await supabase.rpc('care_overview');
    if (error) return fail('ERR_SERVER', 'No pudimos leer tu equipo.', 500);
    const rows = (overview ?? []) as Record<string, unknown>[];
    if (rows.length === 0) {
      return fail('ERR_NO_DATA', 'Todavía no tenés pacientes vinculados.', 422);
    }
    metrics = { hoy: today, pacientes: rows.map(teamRow) };
    prompt = PROMPT_TEAM;
    schema = SCHEMA_TEAM;
  } else {
    let data: PersonData;
    try {
      data = await loadPerson(supabase, patientId!, from, to, kind === 'feedback_draft');
    } catch {
      return fail('ERR_SERVER', 'No pudimos leer los registros. Probá de nuevo.', 500);
    }
    const m = personMetrics(data, from, to, tz);
    if (m.diasConRegistro === 0 && m.peso === null && m.actividad.minutos === 0) {
      return fail(
        'ERR_NO_DATA',
        kind === 'patient_weekly'
          ? 'No hay registros en la última semana para armar el resumen.'
          : 'No hay registros compartidos en las últimas dos semanas.',
        422,
      );
    }
    metrics = {
      ...m,
      nombre: patientName.split(' ')[0] || null,
      categoriasCompartidas: kind === 'patient_weekly' ? null : shares,
      indicacionesVigentes: data.indications,
      devolucionesRecientes: data.recentFeedback,
      foco: kind === 'feedback_draft' ? (focus || null) : undefined,
      diaElegido: kind === 'feedback_draft' ? localDate : undefined,
    };
    prompt = kind === 'patient_weekly' ? PROMPT_PATIENT_WEEKLY
      : kind === 'professional' ? PROMPT_PROFESSIONAL
      : PROMPT_FEEDBACK_DRAFT;
    schema = kind === 'patient_weekly' ? SCHEMA_PATIENT_WEEKLY
      : kind === 'professional' ? SCHEMA_PROFESSIONAL
      : SCHEMA_FEEDBACK_DRAFT;
  }

  const outcome = await callGemini(
    geminiKey,
    [{ text: `${prompt}\n\n## Datos\n${JSON.stringify(metrics)}` }],
    schema,
  );

  if (outcome.parsed === null && outcome.rateLimited) return rateLimitedResponse(outcome.retryAfterSeconds);
  if (outcome.parsed === null && outcome.overloaded) return overloadedResponse();
  if (outcome.parsed === null && outcome.timedOut) return timedOutResponse();

  const content = clean(kind, outcome.parsed);
  // En el informe de equipo, el modelo solo puede nombrar pacientes que
  // existen: un id que no vino en los datos se descarta, no se muestra.
  if (content && kind === 'team') {
    const ids = new Set(((metrics as { pacientes: { patientId: unknown }[] }).pacientes)
      .map((p) => String(p.patientId)));
    content.prioridades = (content.prioridades as { patientId: string }[])
      .filter((p) => ids.has(p.patientId));
  }
  if (content === null) {
    return fail('ERR_AI_INVALID_RESPONSE', `No pudimos armar el informe (${outcome.lastError}).`, 502);
  }

  const diag = outcome.diagnostics;

  // ── Borrador de devolución: queda como borrador privado ────────────────
  if (kind === 'feedback_draft') {
    const { data: draft, error } = await supabase
      .from('care_feedback')
      .insert({
        author_id: user.id,
        patient_id: patientId,
        kind: 'feedback',
        local_date: localDate,
        body: (content as { texto: string }).texto,
        source: 'ai_draft',
      })
      .select('id, body, local_date, created_at')
      .single();
    if (error || !draft) return fail('ERR_SERVER', 'No pudimos guardar el borrador.', 500);
    return ok({ draft, model: GEMINI_MODEL, promptVersion: REPORT_PROMPT_VERSION });
  }

  // ── Informe: se guarda para no volver a pagarlo ────────────────────────
  const stored = { ...content, metricas: metrics };
  const { data: report, error: insertError } = await supabase
    .from('care_reports')
    .insert({
      requested_by: user.id,
      patient_id: kind === 'team' ? null : patientId,
      kind,
      period_from: kind === 'team' ? addDays(today, -13) : from,
      period_to: kind === 'team' ? today : to,
      content: stored,
      model: GEMINI_MODEL,
      prompt_version: REPORT_PROMPT_VERSION,
      tokens_in: diag.tokensIn,
      tokens_out: diag.tokensOut,
      tokens_thinking: diag.tokensThinking,
      latency_ms: outcome.latencyMs,
    })
    .select('id, kind, patient_id, period_from, period_to, content, created_at')
    .single();
  if (insertError || !report) return fail('ERR_SERVER', 'No pudimos guardar el informe.', 500);

  return ok({ report, model: GEMINI_MODEL, promptVersion: REPORT_PROMPT_VERSION });
});

// ── Lectura ──────────────────────────────────────────────────────────────
async function loadPerson(
  db: SupabaseClient,
  userId: string,
  from: string,
  to: string,
  withFeedback: boolean,
): Promise<PersonData> {
  const weightFrom = addDays(from, -14);
  const q = <T>(p: PromiseLike<{ data: T | null; error: unknown }>) =>
    Promise.resolve(p).then((r) => {
      if (r.error) throw r.error;
      return (r.data ?? []) as T;
    });

  const [meals, weights, activities, water, sleep, markers, alcohol, goals, indications, recentFeedback] =
    await Promise.all([
      q(db.from('meals')
        .select('local_date, slot, eaten_at, total_kcal, total_protein_g, total_carbs_g, total_fat_g, source, meal_items(name, kcal)')
        .eq('user_id', userId).is('deleted_at', null)
        .gte('local_date', from).lte('local_date', to)
        .limit(1000)),
      q(db.from('weight_logs').select('local_date, weight_kg')
        .eq('user_id', userId).is('deleted_at', null)
        .gte('local_date', weightFrom).lte('local_date', to)
        .order('local_date')),
      q(db.from('activities')
        .select('local_date, duration_minutes, estimated_calories, custom_name, activity_types(display_name)')
        .eq('user_id', userId).is('deleted_at', null)
        .gte('local_date', from).lte('local_date', to)),
      q(db.from('water_logs').select('local_date, glasses')
        .eq('user_id', userId).gte('local_date', from).lte('local_date', to)),
      q(db.from('sleep_logs').select('local_date, minutes, quality')
        .eq('user_id', userId).is('deleted_at', null)
        .gte('local_date', from).lte('local_date', to)),
      q(db.from('day_markers').select('local_date, kind, severity, note')
        .eq('user_id', userId).is('deleted_at', null)
        .gte('local_date', from).lte('local_date', to)),
      q(db.from('alcohol_logs').select('local_date, std_drinks')
        .eq('user_id', userId).is('deleted_at', null)
        .gte('local_date', from).lte('local_date', to)),
      q(db.from('goals').select('goal_type, base_calorie_target, tdee_kcal, protein_g, starts_on')
        .eq('user_id', userId).lte('starts_on', to)
        .order('starts_on', { ascending: false }).limit(1)),
      // Las indicaciones vigentes de su nutricionista: el resumen del paciente
      // no puede contradecirlas. RLS ya filtra: el paciente ve solo las
      // publicadas; la profesional, las suyas.
      q(db.from('care_feedback').select('body, published_at')
        .eq('patient_id', userId).eq('kind', 'indication')
        .not('published_at', 'is', null).is('deleted_at', null)
        .order('published_at', { ascending: false }).limit(5)),
      withFeedback
        ? q(db.from('care_feedback').select('body, published_at')
          .eq('patient_id', userId).eq('kind', 'feedback')
          .not('published_at', 'is', null).is('deleted_at', null)
          .order('published_at', { ascending: false }).limit(3))
        : Promise.resolve([]),
    ]);

  return {
    meals: meals as PersonData['meals'],
    weights: weights as PersonData['weights'],
    activities: activities as PersonData['activities'],
    water: water as PersonData['water'],
    sleep: sleep as PersonData['sleep'],
    markers: markers as PersonData['markers'],
    alcohol: alcohol as PersonData['alcohol'],
    goal: ((goals as unknown[])[0] ?? null) as PersonData['goal'],
    indications: (indications as { body: string }[]).map((i) => i.body),
    recentFeedback: (recentFeedback as { body: string }[]).map((i) => i.body),
  };
}

function teamRow(r: Record<string, unknown>) {
  const first = r.weight_first_30 as number | null;
  const last = r.weight_last_30 as number | null;
  return {
    patientId: r.patient_id,
    nombre: r.patient_name,
    ultimaComida: r.last_meal_date,
    diasConRegistro7: r.days_logged_7,
    diasConRegistro14: r.days_logged_14,
    promedioKcal7: r.avg_kcal_7,
    objetivoKcal: r.target_kcal,
    cambioPeso30: first !== null && last !== null ? Math.round((last - first) * 10) / 10 : null,
    devolucionesSinLeer: r.unread_feedback,
  };
}

// ── Validación de la respuesta ───────────────────────────────────────────
const str = (v: unknown, max: number): string | null =>
  typeof v === 'string' && v.trim() ? v.trim().slice(0, max) : null;
const strs = (v: unknown, n: number, max: number): string[] =>
  Array.isArray(v) ? v.map((x) => str(x, max)).filter((x): x is string => !!x).slice(0, n) : [];

function clean(kind: Kind, raw: unknown): Record<string, unknown> | null {
  if (!raw || typeof raw !== 'object') return null;
  const o = raw as Record<string, unknown>;
  switch (kind) {
    case 'patient_weekly': {
      const titulo = str(o.titulo, 80);
      const resumen = str(o.resumen, 800);
      if (!titulo || !resumen) return null;
      return {
        titulo, resumen,
        logros: strs(o.logros, 3, 300),
        patrones: strs(o.patrones, 3, 300),
        sugerencias: strs(o.sugerencias, 3, 300),
        cierre: str(o.cierre, 300) ?? '',
      };
    }
    case 'professional': {
      const resumen = str(o.resumen, 1200);
      if (!resumen) return null;
      const alertas = Array.isArray(o.alertas)
        ? o.alertas.map((a) => {
          const x = a as Record<string, unknown>;
          const texto = str(x?.texto, 300);
          return texto ? { nivel: x.nivel === 'atencion' ? 'atencion' : 'info', texto } : null;
        }).filter(Boolean).slice(0, 3)
        : [];
      return {
        resumen,
        puntosClave: strs(o.puntosClave, 5, 300),
        alertas,
        balance: str(o.balance, 500) ?? '',
        preguntas: strs(o.preguntas, 5, 250),
      };
    }
    case 'feedback_draft': {
      const texto = str(o.texto, 1500);
      return texto ? { texto } : null;
    }
    case 'team': {
      const resumen = str(o.resumen, 800);
      if (!resumen) return null;
      const prioridades = Array.isArray(o.prioridades)
        ? o.prioridades.map((p) => {
          const x = p as Record<string, unknown>;
          const patientId = str(x?.patientId, 64);
          const motivo = str(x?.motivo, 300);
          return patientId && motivo ? { patientId, motivo, accion: str(x.accion, 200) ?? '' } : null;
        }).filter(Boolean).slice(0, 5)
        : [];
      return { resumen, prioridades, observaciones: strs(o.observaciones, 3, 300) };
    }
  }
}
