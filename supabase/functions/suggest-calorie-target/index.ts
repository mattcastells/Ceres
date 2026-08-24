// suggest-calorie-target — que la IA proponga el objetivo diario.
//
// Se llama desde el último paso del alta guiada (S-05), al lado del número que
// da la fórmula. La persona ve los dos y elige.
//
// Es la única función del proyecto cuyo resultado es **un número del que cuelga
// todo lo demás**: las calorías del día, los macros, el anillo de Inicio, la
// adherencia. Por eso acá el modelo tiene menos libertad que en ninguna otra
// parte, y la regla del producto no se le delega en ningún momento:
//
// 1. **El servidor recalcula el metabolismo basal y el gasto**, con las mismas
//    fórmulas que la app (`lib/domain/calculations/{bmr,tdee}.dart`). No usa
//    números que le manden: si el techo del que se cuelga la validación viniera
//    del cliente, la validación no estaría validando nada. Es la razón por la
//    que la entrada son datos crudos —sexo, edad, altura, peso, actividad— y no
//    un TDEE ya masticado.
// 2. **Lo que devuelve el modelo se acota contra ese gasto**, no contra lo que
//    el modelo diga que es razonable. Fuera de la banda se descarta entero.
// 3. **El mínimo de RN-12 sube el número y lo dice** (`clamped`), igual que en
//    la fórmula. Callarlo sería presentar un tope como si fuera una
//    recomendación.
//
// No escribe en `ai_analyses`: esa tabla registra estimaciones de lo que alguien
// comió. La cuota se cuenta con `check_rate_limit`, que no depende de ella, y es
// la misma que comparten las otras tres funciones.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { PROMPT_TARGET_V1 } from './prompts/target_v1.ts';
import {
  CORS,
  DAILY_QUOTA,
  GEMINI_MODEL,
  PROMPT_VERSION,
  callGemini,
  fail,
  ok,
  overloadedResponse,
  rateLimitedResponse,
  timedOutResponse,
} from '../_shared/estimation.ts';

/**
 * Los mismos topes que `CalorieTargetRules` en Dart.
 *
 * Duplicarlos es el precio de que la validación no dependa del cliente. Si
 * cambian allá, cambian acá: no hay forma de compartir código entre el
 * teléfono y Deno, y tener el número en un solo lado significaría confiárselo
 * a quien llama.
 */
const ABSOLUTE_MIN = 800;
const ABSOLUTE_MAX = 6000;
const MAX_DEFICIT_FRACTION = 0.30;
const MAX_SURPLUS_FRACTION = 0.25;

const MINIMUM_FOR: Record<string, number> = {
  female: 1200,
  male: 1500,
  unspecified: 1350,
};

/** `ActivityLevel.factor` en Dart. */
const ACTIVITY_FACTOR: Record<string, number> = {
  sedentary: 1.2,
  light: 1.375,
  moderate: 1.55,
  high: 1.725,
  very_high: 1.9,
};

const GOAL_TYPES = ['lose', 'maintain', 'gain', 'gain_muscle'];

const TARGET_SCHEMA = {
  type: 'OBJECT',
  required: ['targetKcal', 'rationale'],
  properties: {
    targetKcal: { type: 'INTEGER' },
    rationale: { type: 'STRING' },
  },
};

/** Mifflin-St Jeor, igual que `bmrMifflinStJeor`. */
function bmr(
  weightKg: number,
  heightCm: number,
  ageYears: number,
  sex: string,
): number {
  const base = 10 * weightKg + 6.25 * heightCm - 5 * ageYears;
  const offset = sex === 'male' ? 5 : sex === 'female' ? -161 : (5 - 161) / 2;
  return Math.round(base + offset);
}

interface Stats {
  sex: string;
  ageYears: number;
  heightCm: number;
  weightKg: number;
  activityLevel: string;
  goalType: string;
  formulaTarget: number;
}

/** `null` si falta algo o si algún valor está fuera de los rangos de §1. */
function readStats(body: Record<string, unknown>): Stats | null {
  const sex = typeof body.sex === 'string' ? body.sex : '';
  const activityLevel = typeof body.activityLevel === 'string'
    ? body.activityLevel
    : '';
  const goalType = typeof body.goalType === 'string' ? body.goalType : '';

  const ageYears = Number(body.ageYears);
  const heightCm = Number(body.heightCm);
  const weightKg = Number(body.weightKg);
  const formulaTarget = Number(body.formulaTarget);

  const inRange = (v: number, min: number, max: number) =>
    Number.isFinite(v) && v >= min && v <= max;

  if (!(sex in MINIMUM_FOR)) return null;
  if (!(activityLevel in ACTIVITY_FACTOR)) return null;
  if (!GOAL_TYPES.includes(goalType)) return null;
  if (!inRange(ageYears, 13, 100)) return null;
  if (!inRange(heightCm, 90, 250)) return null;
  if (!inRange(weightKg, 25, 400)) return null;
  if (!inRange(formulaTarget, ABSOLUTE_MIN, ABSOLUTE_MAX)) return null;

  return {
    sex,
    ageYears: Math.round(ageYears),
    heightCm,
    weightKg,
    activityLevel,
    goalType,
    formulaTarget: Math.round(formulaTarget),
  };
}

interface Proposal {
  targetKcal: number;
  rationale: string;
  clamped: boolean;
}

/**
 * Deja pasar la propuesta solo si cae dentro de la banda que permite el gasto
 * de esta persona.
 *
 * Fuera de la banda se descarta **entera** en vez de recortarse: un número tan
 * lejos del gasto significa que el modelo no entendió el pedido, y su
 * explicación —que es la mitad del valor de esto— hablaría de un número que ya
 * no es el que se devuelve. Recortarlo dejaría un objetivo sin explicación
 * pegado a una explicación de otro objetivo.
 *
 * El mínimo de RN-12 es la excepción: ahí sí se sube y se avisa, que es lo que
 * hace la fórmula.
 */
function validateProposal(
  raw: unknown,
  tdee: number,
  sex: string,
): Proposal | null {
  if (!raw || typeof raw !== 'object') return null;
  const o = raw as Record<string, unknown>;

  const proposed = Number(o.targetKcal);
  if (!Number.isFinite(proposed)) return null;

  let target = Math.round(proposed);
  if (target < ABSOLUTE_MIN || target > ABSOLUTE_MAX) return null;
  if (target < tdee * (1 - MAX_DEFICIT_FRACTION)) return null;
  if (target > tdee * (1 + MAX_SURPLUS_FRACTION)) return null;

  const minimum = MINIMUM_FOR[sex];
  let clamped = false;
  if (target < minimum) {
    target = minimum;
    clamped = true;
  }

  const rationale = typeof o.rationale === 'string' ? o.rationale.trim() : '';
  // Sin explicación esto no tiene sentido: el número solo ya lo da la fórmula,
  // y gratis. Lo que se paga acá es el porqué.
  if (rationale.length < 20) return null;

  return { targetKcal: target, rationale: rationale.slice(0, 240), clamped };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return fail('ERR_UNAUTHENTICATED', 'Falta la sesión.', 401);

  const geminiKey = Deno.env.get('GEMINI_API_KEY');
  if (!geminiKey) {
    return fail(
      'ERR_PROVIDER_UNAVAILABLE',
      'El cálculo con IA no está configurado en el servidor.',
      503,
    );
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_PUBLISHABLE_KEY') ?? Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: userData, error: userError } = await supabase.auth.getUser();
  const user = userData?.user;
  if (userError || !user) return fail('ERR_UNAUTHENTICATED', 'Tu sesión venció.', 401);

  let stats: Stats | null = null;
  try {
    stats = readStats(await req.json());
  } catch {
    stats = null;
  }
  if (stats === null) {
    return fail(
      'ERR_VALIDATION',
      'Faltan datos para calcular, o alguno está fuera de rango.',
    );
  }

  const bmrKcal = bmr(stats.weightKg, stats.heightCm, stats.ageYears, stats.sex);
  const tdeeKcal = Math.round(bmrKcal * ACTIVITY_FACTOR[stats.activityLevel]);

  const { data: withinQuota, error: quotaError } = await supabase.rpc(
    'check_rate_limit',
    { p_bucket: 'ai_analysis', p_max: DAILY_QUOTA },
  );
  if (quotaError) {
    return fail('ERR_SERVER', 'No pudimos verificar tu cuota. Probá de nuevo.', 500);
  }
  if (!withinQuota) {
    return fail(
      'ERR_QUOTA_EXCEEDED',
      `Llegaste a las ${DAILY_QUOTA} consultas de hoy.`,
      429,
    );
  }

  const objetivo: Record<string, string> = {
    lose: 'bajar de peso',
    maintain: 'mantener el peso',
    gain: 'subir de peso',
    gain_muscle: 'ganar músculo',
  };
  const perfil: Record<string, string> = {
    male: 'masculino',
    female: 'femenino',
    unspecified: 'sin especificar',
  };
  const movimiento: Record<string, string> = {
    sedentary: 'sedentario (trabajo de oficina, poco movimiento)',
    light: 'ligero (camina bastante o entrena 1 o 2 veces por semana)',
    moderate: 'moderado (entrena 3 o 4 veces por semana)',
    high: 'alto (entrena 5 o 6 veces por semana)',
    very_high: 'muy alto (trabajo físico o entrenamiento diario intenso)',
  };

  const contexto = [
    `Perfil: ${perfil[stats.sex]}, ${stats.ageYears} años, ` +
      `${stats.heightCm} cm, ${stats.weightKg} kg.`,
    `Nivel de actividad declarado: ${movimiento[stats.activityLevel]}.`,
    `Objetivo: ${objetivo[stats.goalType]}.`,
    `Metabolismo basal (Mifflin-St Jeor): ${bmrKcal} kcal.`,
    `Gasto diario estimado: ${tdeeKcal} kcal.`,
    `Objetivo que da la fórmula: ${stats.formulaTarget} kcal.`,
  ].join(' ');

  const {
    parsed,
    lastError,
    rateLimited,
    overloaded,
    timedOut,
    retryAfterSeconds,
    latencyMs,
  } = await callGemini(
      geminiKey,
      [{ text: `${PROMPT_TARGET_V1}\n\n${contexto}` }],
      TARGET_SCHEMA,
    );

  if (parsed === null && rateLimited) {
    return rateLimitedResponse(retryAfterSeconds);
  }
  if (parsed === null && overloaded) return overloadedResponse();
  if (parsed === null && timedOut) {
    return timedOutResponse('seguir con el número calculado');
  }

  const proposal = validateProposal(parsed, tdeeKcal, stats.sex);
  if (proposal === null) {
    // Se distingue del error de proveedor a propósito: acá el modelo contestó,
    // pero con algo que no se puede poner delante de nadie. "Probá de nuevo"
    // sirve —la próxima tirada puede caer en banda— y "algo salió mal" no.
    return fail(
      'ERR_AI_INVALID_RESPONSE',
      `Esta vez la propuesta no cerró con tus datos (${lastError}). Probá de ` +
        'nuevo, o usá el número calculado.',
      422,
    );
  }

  return ok({
    targetKcal: proposal.targetKcal,
    rationale: proposal.rationale,
    clamped: proposal.clamped,
    bmrKcal,
    tdeeKcal,
    model: GEMINI_MODEL,
    promptVersion: PROMPT_VERSION,
    latencyMs,
  });
});
