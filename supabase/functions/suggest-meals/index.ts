// suggest-meals — qué puedo comer con las calorías que me quedan.
//
// Le dan un presupuesto —"me quedan 600 kcal"— y devuelve tres platos que
// entran, cada uno con sus ingredientes y su receta.
//
// Comparte con las dos funciones de estimación la cuota, el manejo de errores y
// la llamada al modelo (`_shared/estimation.ts`). Lo que **no** comparte es la
// validación, porque el contrato de salida es otro: acá hay tres opciones, cada
// una con su lista de ingredientes y sus pasos.
//
// La regla del producto que manda acá es una sola: **ninguna opción puede
// pasarse del presupuesto**. Eso no se le delega al modelo. Se le pide en el
// prompt, sí, pero después se suma acá y lo que no cierra se descarta. Un plato
// de 800 kcal ofrecido a quien tiene 600 no es una sugerencia imprecisa: es la
// app diciéndole a alguien que puede comer algo que no puede.
//
// Tampoco se escribe en `ai_analyses`: esa tabla registra estimaciones de lo que
// alguien **comió**, y una sugerencia no es eso. Meterla ahí le cambiaría el
// significado a la tabla y al historial que sale de ella. La cuota se cuenta
// aparte, con `check_rate_limit`, que no depende de esa tabla.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { PROMPT_SUGGEST_V1 } from './prompts/suggest_v1.ts';
import {
  parseRestrictions,
  restrictionsPrompt,
  RestrictionId,
  violatesRestrictions,
} from './restrictions.ts';
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
 * Abajo de esto no hay comida que proponer sin faltar a la verdad. Es una
 * fruta, un yogur; sugerir "un plato" con 120 kcal sería inventarlo.
 */
const MIN_BUDGET = 150;

/** Un presupuesto más grande que esto es el día entero, no una comida. */
const MAX_BUDGET = 3000;

/**
 * Cuánto del presupuesto tiene que usar una opción para valer la pena.
 *
 * Bajo a propósito. El prompt pide entre 70 % y 95 %, así que esto no está para
 * afinar la respuesta sino para descartar el absurdo —una "opción" de 60 kcal
 * cuando quedan 600—. Cada filtro de más es una forma de que la pantalla quede
 * vacía, y una feature que siempre dice "esta vez no salió nada" es una feature
 * que no existe.
 */
const MIN_USE = 0.3;

/**
 * Cuánto puede desviarse un ingrediente de Atwater (4/4/9) antes de descartar
 * la opción.
 *
 * 25 % y no el 15 % del resto del proyecto. La validación que ya corre en
 * producción —la de las dos estimaciones— **no** chequea Atwater por ítem: solo
 * rangos. Poner acá una regla más dura que la que está probada contra el modelo
 * real es la forma más fácil de que esta pantalla no muestre nunca nada.
 *
 * 25 % deja pasar lo que legítimamente se desvía —una ensalada con aceite, algo
 * con fibra, el redondeo de una porción— y sigue atrapando lo que importa: un
 * ingrediente cuyos macros no tienen nada que ver con sus calorías.
 */
const ATWATER_TOLERANCE = 0.25;

const UNITS = ['g', 'ml', 'unidad', 'taza', 'cucharada', 'rebanada', 'porcion'];

const SUGGEST_SCHEMA = {
  type: 'OBJECT',
  required: ['options'],
  properties: {
    options: {
      type: 'ARRAY',
      maxItems: 3,
      items: {
        type: 'OBJECT',
        required: ['name', 'kcal', 'proteinG', 'carbsG', 'fatG', 'items', 'steps'],
        properties: {
          name: { type: 'STRING' },
          kcal: { type: 'INTEGER' },
          proteinG: { type: 'NUMBER' },
          carbsG: { type: 'NUMBER' },
          fatG: { type: 'NUMBER' },
          minutes: { type: 'INTEGER' },
          items: {
            type: 'ARRAY',
            maxItems: 8,
            items: {
              type: 'OBJECT',
              required: ['name', 'quantity', 'unit', 'kcal', 'proteinG', 'carbsG', 'fatG'],
              properties: {
                name: { type: 'STRING' },
                quantity: { type: 'NUMBER' },
                unit: { type: 'STRING', enum: UNITS },
                kcal: { type: 'INTEGER' },
                proteinG: { type: 'NUMBER' },
                carbsG: { type: 'NUMBER' },
                fatG: { type: 'NUMBER' },
              },
            },
          },
          steps: { type: 'ARRAY', maxItems: 6, items: { type: 'STRING' } },
        },
      },
    },
  },
};

interface SuggestionItem {
  name: string;
  quantity: number;
  unit: string;
  kcal: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
}

interface Suggestion {
  name: string;
  kcal: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
  minutes?: number;
  items: SuggestionItem[];
  steps: string[];
}

const num = (v: unknown): number | null => {
  const n = Number(v);
  return Number.isFinite(n) && n >= 0 ? n : null;
};

/**
 * Deja pasar solo las opciones que **cierran**.
 *
 * Tres cosas se comprueban acá y ninguna se le cree al modelo:
 *
 * 1. Que la opción entre en el presupuesto.
 * 2. Que las calorías del plato sean la suma de las de sus ingredientes. Si no,
 *    uno de los dos números miente y no hay forma de saber cuál.
 * 3. Atwater por ingrediente (4/4/9), con el mismo 15 % de margen que usa el
 *    resto del proyecto. Es la misma validación que atrapó "aceite de oliva,
 *    100 g de proteína" en la tabla de ARGENFOODS.
 *
 * Una opción que no cierra se descarta entera, no se corrige: un plato al que
 * le arreglamos un ingrediente ya no es lo que el modelo propuso, y la receta
 * dejaría de corresponderse con los números.
 */
function validateSuggestions(
  raw: unknown,
  budget: number,
  restrictions: RestrictionId[],
): Suggestion[] | null {
  if (!raw || typeof raw !== 'object') return null;
  const rawOptions = (raw as { options?: unknown }).options;
  if (!Array.isArray(rawOptions)) return null;

  const clean: Suggestion[] = [];

  for (const entry of rawOptions.slice(0, 3)) {
    if (!entry || typeof entry !== 'object') continue;
    const o = entry as Record<string, unknown>;

    const name = typeof o.name === 'string' ? o.name.trim() : '';
    if (!name || name.length > 60) continue;

    const kcal = num(o.kcal);
    const proteinG = num(o.proteinG);
    const carbsG = num(o.carbsG);
    const fatG = num(o.fatG);
    if (kcal === null || proteinG === null || carbsG === null || fatG === null) {
      continue;
    }

    // (1) El presupuesto. La regla entera de esta función.
    if (kcal > budget) continue;
    if (kcal < budget * MIN_USE) continue;

    const rawItems = Array.isArray(o.items) ? o.items : [];
    const items: SuggestionItem[] = [];
    let sumaKcal = 0;
    let itemInvalido = false;

    for (const rawItem of rawItems.slice(0, 8)) {
      if (!rawItem || typeof rawItem !== 'object') { itemInvalido = true; break; }
      const i = rawItem as Record<string, unknown>;

      const iName = typeof i.name === 'string' ? i.name.trim() : '';
      const quantity = num(i.quantity);
      const iKcal = num(i.kcal);
      const iProtein = num(i.proteinG);
      const iCarbs = num(i.carbsG);
      const iFat = num(i.fatG);
      const unit = typeof i.unit === 'string' ? i.unit : '';

      if (
        !iName || iName.length > 120 ||
        quantity === null || quantity <= 0 || quantity > 5000 ||
        iKcal === null || iKcal > 2000 ||
        iProtein === null || iCarbs === null || iFat === null ||
        !UNITS.includes(unit)
      ) {
        itemInvalido = true;
        break;
      }

      // (3) Atwater por ingrediente.
      const atwater = iProtein * 4 + iCarbs * 4 + iFat * 9;
      if (
        iKcal > 0 &&
        Math.abs(atwater - iKcal) > Math.max(iKcal * ATWATER_TOLERANCE, 30)
      ) {
        itemInvalido = true;
        break;
      }

      sumaKcal += iKcal;
      items.push({
        name: iName,
        quantity,
        unit,
        kcal: Math.round(iKcal),
        proteinG: Number(iProtein.toFixed(1)),
        carbsG: Number(iCarbs.toFixed(1)),
        fatG: Number(iFat.toFixed(1)),
      });
    }

    if (itemInvalido || items.length < 2) continue;

    // (2) El total contra la suma de sus partes.
    if (Math.abs(sumaKcal - kcal) > Math.max(kcal * 0.15, 40)) continue;

    // Y una vez más contra el presupuesto, ahora con la suma real: si el total
    // que declaró el modelo era optimista, lo que manda es lo que suman los
    // ingredientes, que es lo que la persona se va a comer.
    if (sumaKcal > budget) continue;

    const steps = (Array.isArray(o.steps) ? o.steps : [])
      .filter((s): s is string => typeof s === 'string' && s.trim().length > 0)
      .map((s) => s.trim().slice(0, 200))
      .slice(0, 6);
    if (steps.length < 2) continue;

    const minutes = num(o.minutes);

    // (4) Lo que esta persona no puede comer. Va último porque necesita la
    // lista de ingredientes ya saneada, y descarta la opción entera igual que
    // el resto: una receta a la que le sacamos el queso ya no es la receta que
    // el modelo propuso, y sus números dejarían de corresponderse.
    if (violatesRestrictions({ name, items, steps }, restrictions)) continue;

    clean.push({
      name,
      kcal: Math.round(sumaKcal),
      proteinG: Number(proteinG.toFixed(1)),
      carbsG: Number(carbsG.toFixed(1)),
      fatG: Number(fatG.toFixed(1)),
      minutes: minutes === null || minutes > 240 ? undefined : Math.round(minutes),
      items,
      steps,
    });
  }

  return clean;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return fail('ERR_UNAUTHENTICATED', 'Falta la sesión.', 401);

  const geminiKey = Deno.env.get('GEMINI_API_KEY');
  if (!geminiKey) {
    return fail(
      'ERR_PROVIDER_UNAVAILABLE',
      'Las sugerencias no están configuradas en el servidor.',
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

  let budget = 0;
  let slot = '';
  let proteinLeft: number | null = null;
  let restrictions: RestrictionId[] = [];
  let restrictionsNote = '';
  try {
    const body = await req.json();
    budget = Math.round(Number(body.remainingKcal));
    slot = typeof body.slot === 'string' ? body.slot.slice(0, 20) : '';
    const p = Number(body.remainingProteinG);
    proteinLeft = Number.isFinite(p) && p > 0 ? Math.round(p) : null;
    // Lo que esta persona no puede comer. Lo manda la app desde su perfil y no
    // se lee de `profiles` a propósito: así funciona igual con un perfil que
    // todavía no llegó a las tablas, y el dato no deja de ser suyo.
    restrictions = parseRestrictions(body.restrictions);
    restrictionsNote = typeof body.restrictionsNote === 'string'
      // El mismo techo que la columna y que el cliente. Un texto largo acá se
      // lleva puesto el prompt entero.
      ? body.restrictionsNote.trim().slice(0, 200)
      : '';
  } catch {
    return fail('ERR_VALIDATION', 'Falta cuántas calorías quedan.');
  }

  if (!Number.isFinite(budget) || budget < MIN_BUDGET) {
    return fail(
      'ERR_BUDGET_TOO_LOW',
      `Con menos de ${MIN_BUDGET} kcal no hay un plato que sugerir sin ` +
        'inventarlo. Para completar el día alcanza una fruta o un yogur.',
      422,
    );
  }
  if (budget > MAX_BUDGET) budget = MAX_BUDGET;

  // Misma cuota que las dos estimaciones: las tres gastan lo mismo del
  // proveedor, y darle a esta su propio cupo sería duplicarlo por la ventana.
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

  const contexto = [
    `Calorías disponibles: ${budget} kcal.`,
    slot ? `Momento del día: ${slot}.` : '',
    proteinLeft ? `Le faltan ${proteinLeft} g de proteína para su objetivo.` : '',
  ].filter(Boolean).join(' ');

  const restringido = restrictionsPrompt(restrictions, restrictionsNote);

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
      [{ text: `${PROMPT_SUGGEST_V1}${restringido}\n\n${contexto}` }],
      SUGGEST_SCHEMA,
    );

  if (parsed === null && rateLimited) {
    return rateLimitedResponse(retryAfterSeconds);
  }
  if (parsed === null && overloaded) return overloadedResponse();
  if (parsed === null && timedOut) return timedOutResponse();

  const options = validateSuggestions(parsed, budget, restrictions);
  if (options === null) {
    return fail(
      'ERR_AI_INVALID_RESPONSE',
      `No pudimos interpretar la respuesta (${lastError}).`,
      502,
    );
  }

  // Cero opciones no es un error del servidor: es que ninguna cerró. Se dice
  // así, porque "probá de nuevo" es un consejo que acá sí sirve —la próxima
  // tirada del modelo puede dar tres que cierren— y "algo salió mal" no.
  if (options.length === 0) {
    return fail(
      'ERR_AI_NO_SUGGESTIONS',
      restrictions.length > 0 || restrictionsNote
        // Se dice que las restricciones son parte del motivo. Sin esto, quien
        // cargó tres alergias y ve "probá de nuevo" prueba diez veces sin
        // entender que lo que conviene es subir el presupuesto.
        ? 'Esta vez no salió ninguna opción que entre en esas calorías y ' +
          'respete lo que no comés. Probá de nuevo o con un número más alto.'
        : 'Esta vez no salió ninguna opción que cierre con las calorías que te ' +
          'quedan. Probá de nuevo.',
      422,
    );
  }

  return ok({
    options,
    budgetKcal: budget,
    model: GEMINI_MODEL,
    promptVersion: PROMPT_VERSION,
    latencyMs,
  });
});
