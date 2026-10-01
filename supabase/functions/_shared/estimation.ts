// Lo que comparten `analyze-meal-photo` y `analyze-meal-text`.
//
// Las dos estiman la misma cosa —los ítems de una comida— y difieren solo en
// qué le mandan a Gemini: una imagen o una descripción. Todo lo demás (el
// contrato de salida, la validación, la llamada, el manejo de límites) tiene
// que ser idéntico, y la única forma de que siga siéndolo dentro de seis meses
// es que sea el mismo código.
//
// Duplicar la validación sería peor que duplicar cualquier otra cosa: es la
// que impide que un "9000 kcal" entre al historial de alguien.

import type { CurrentItem } from './recalc.ts';

export const GEMINI_MODEL = Deno.env.get('GEMINI_MODEL') ?? 'gemini-3.6-flash';
/**
 * Qué versión del prompt y del contrato con el modelo corre: `v4` o `v3`.
 *
 * Es un interruptor y no solo una etiqueta. v4 cambió **qué** se le pregunta al
 * modelo (gramos y valores cada 100 g en vez de kcal; ver [RESPONSE_SCHEMA]) y
 * salió sin haberse medido contra comidas de calorías conocidas. Si empeora,
 * volver tiene que ser un `supabase secrets set GEMINI_PROMPT_VERSION=v3`, sin
 * desplegar y sin tocar código. Cualquier otro valor —vacío, un dedazo— corre
 * v4: un interruptor mal escrito no puede dejar el análisis sin prompt.
 *
 * Se guarda en `ai_analyses.prompt_version`, que es lo que permite comparar las
 * dos después.
 */
export const PROMPT_VERSION: 'v3' | 'v4' =
  (Deno.env.get('GEMINI_PROMPT_VERSION') ?? '').trim().toLowerCase() === 'v3'
    ? 'v3'
    : 'v4';

/**
 * Cuota diaria por usuario (D-18).
 *
 * Es **nuestro** techo, no el de Google: existe para que una cuenta no se lleve
 * puesto el cupo del proyecto entero, que es una sola clave para toda la app.
 * Se lee del entorno para poder subirlo sin tocar código el día que el plan del
 * proveedor dé para más.
 */
export const DAILY_QUOTA = Number(Deno.env.get('AI_DAILY_QUOTA') ?? '') || 20;

/**
 * Cuánto puede tardar **una** llamada al proveedor.
 *
 * No alcanza con esto solo: `callGemini` reintenta, así que este número no es el
 * techo de la función — ese es [GEMINI_BUDGET_MS].
 *
 * 30 s, medido contra `ai_analyses`: con [THINKING_LEVEL] en `medium` una
 * respuesta buena tarda entre 9 y 25 s —la más lenta que se midió fueron
 * 25215 ms—, así que abajo de 30 s estaríamos matando análisis que iban a
 * salir bien. Que es exactamente lo que no queremos: acá se prefiere esperar
 * a fallar.
 *
 * Los intentos que **sí** hay que cortar no tardan, se cuelgan: vuelven con
 * `tokens_in` en `null` —ni un byte— y topan justo contra este número. Se pagan
 * enteros, y esa es la parte fea de tenerlo alto. Distinguir un cuelgue de un
 * modelo pensando requeriría leer la respuesta en streaming y mirar si llega un
 * primer byte; mientras eso no exista, este número es el único árbitro y se
 * pone del lado de no perder un análisis bueno.
 *
 * Sale del entorno (`GEMINI_TIMEOUT_MS`) porque **está acoplado a
 * [THINKING_LEVEL]**: los dos tienen que moverse juntos. Con el razonamiento
 * bajo las respuestas llegan en 4 o 5 s y este tope puede bajar a 18 s, lo que
 * deja lugar para tres intentos en vez de dos.
 */
export const GEMINI_TIMEOUT_MS = leerMs('GEMINI_TIMEOUT_MS', 30_000);

/**
 * Cuánto puede tardar la función entera contra el proveedor, **sumando todos
 * los intentos**.
 *
 * Este número existe porque su ausencia era el bug original: el timeout de
 * arriba es por intento, así que con un reintento el servidor podía estar 50 s
 * en Gemini y las apps esperaban 45 s. O sea que cualquier llamada que
 * necesitara un segundo intento terminaba **garantizado** en "El análisis tardó
 * demasiado" — la app cortaba antes de que el servidor pudiera contestar, la
 * cuota ya estaba gastada y, si el segundo intento salía bien, el resultado se
 * tiraba a la basura sin que nadie lo viera.
 *
 * La regla es que el servidor siempre conteste primero: 50 s de techo acá, más
 * el resto de la función, entra en los 60 s que esperan los clientes. Y
 * contestar es mejor que no contestar aunque la respuesta sea un fallo: un
 * `ERR_UPSTREAM_TIMEOUT` queda registrado en `ai_analyses` y se puede mirar; un
 * `TimeoutException` del lado del teléfono no deja rastro en ningún lado.
 *
 * Con [GEMINI_TIMEOUT_MS] en 30 s esto da dos intentos y no tres: el primero
 * se lleva 30 s y al segundo le quedan 20, que alcanzan para la mediana de una
 * respuesta con razonamiento (~15 s) aunque no para la más lenta. Es el precio
 * de darle al modelo tiempo de pensar, y se paga a sabiendas.
 *
 * También del entorno (`GEMINI_BUDGET_MS`), por lo mismo que el de arriba. La
 * única regla que no se puede romper al moverlo: **tiene que quedar más chico
 * que el timeout del cliente**, con lugar para el resto de la función —bajar la
 * foto, pasarla a base64, escribir la fila—. Si el servidor tarda más que la
 * app, el teléfono corta primero, la cuota queda gastada y el fallo no se
 * registra en ningún lado: es el bug con el que empezó todo esto.
 *
 * De ahí que el default siga en 50 s aunque 1.22.3 haya subido los clientes a
 * 90 s. **El default lo manda el teléfono más viejo que siga andando**, no el
 * último que salió: 50 s es lo que aguanta un 1.22.2 con sus 60 s. Cuando no
 * queden teléfonos abajo de 1.22.3, esto sube a 78 s —30 + 30 + 18, tres
 * intentos— con un `supabase secrets set GEMINI_BUDGET_MS=78000`, sin
 * desplegar y sin tocar este archivo. Por eso es una variable de entorno y no
 * una constante: el número correcto depende de qué hay instalado afuera, que es
 * justo lo que el código no puede saber.
 */
export const GEMINI_BUDGET_MS = leerMs('GEMINI_BUDGET_MS', 50_000);

/**
 * Un número de milisegundos del entorno, o el de fábrica si no vino o vino mal.
 *
 * Se valida en vez de confiar: un `GEMINI_TIMEOUT_MS=` vacío o con un dedazo
 * daría `NaN`, y un `NaN` en un `setTimeout` no falla — dispara al instante y
 * cancela **todos** los intentos antes de empezar. Un tope mal escrito rompería
 * el análisis entero sin decir por qué.
 */
function leerMs(clave: string, porOmision: number): number {
  const valor = Number(Deno.env.get(clave) ?? '');
  return Number.isFinite(valor) && valor >= 1000 ? valor : porOmision;
}

/**
 * Cuántas veces se le pide al proveedor antes de rendirse.
 *
 * Tres, y no dos, por lo que se ve en `ai_analyses`: los intentos que se cuelgan
 * vienen de a rachas —tres seguidos en dos minutos, el 24 de agosto— y cada uno
 * que se cuelga no gasta nada del modelo, porque no llega a contestar. Con un
 * solo reintento, una racha así se le aparece a la persona como un fallo que
 * tiene que reintentar a mano.
 */
const MAX_ATTEMPTS = 3;

/**
 * Abajo de esto no vale la pena empezar otro intento: lo único que se consigue
 * es llegar tarde igual, habiendo gastado otra llamada al proveedor.
 */
const MIN_ATTEMPT_MS = 6_000;

/**
 * Cuánto se le deja "pensar" al modelo antes de contestar.
 *
 * `medium`, que es lo que hacen de fábrica los Gemini 3. Estuvo en `low` una
 * versión, buscando velocidad, y se volvió: **acá la precisión vale más que los
 * segundos.**
 *
 * El argumento para bajarlo era que esto es extracción estructurada, con el
 * `responseSchema` garantizando la forma. Esa mitad es cierta para *identificar*
 * qué hay en el plato, y falsa para lo que de verdad importa: estimar la
 * porción. "La milanesa ocupa dos tercios del plato, un plato son 26 cm,
 * entonces pesa unos 180 g" es una cadena de inferencia, no una lectura — y de
 * ahí salen las calorías que le quedan a alguien en el historial, que después
 * mira una nutricionista. Un número mal estimado no se nota, y ese es el
 * problema: no avisa.
 *
 * Con `low` las respuestas bajaban de ~15 s a ~5 s. Nunca se midió si además
 * empeoraban, y elegir velocidad sobre un riesgo sin medir, en una app de
 * nutrición, es elegir mal. La lentitud tampoco era la causa de los fallos —eran
 * los cuelgues, que se arreglan aparte—, así que el trueque compraba menos de lo
 * que parecía.
 *
 * Si algún día se mide contra comidas de calorías conocidas y `low` empata, es
 * un `secrets set` y listo. Ojo al moverlo: hay que mover [GEMINI_TIMEOUT_MS]
 * con él, en la dirección que corresponda.
 *
 * Sale del entorno también porque si `GEMINI_MODEL` se baja a un `gemini-2.5-*`,
 * que no entiende `thinkingLevel` y **rechaza el pedido entero con un 400**, se
 * pone `GEMINI_THINKING_LEVEL` en `default` y el campo deja de mandarse.
 */
const THINKING_LEVEL = (Deno.env.get('GEMINI_THINKING_LEVEL') ?? 'medium')
  .trim()
  .toLowerCase();

/** `default` (o vacío) significa "no mandes el campo y que decida el modelo". */
const SENDS_THINKING = THINKING_LEVEL !== '' && THINKING_LEVEL !== 'default';

export const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
};

export function fail(
  code: string,
  message: string,
  status = 400,
  // Lo que la app necesita además del texto. Hoy lo usa el 429 para decir
  // cuántos segundos faltan, que es lo único que permite apagar el botón de
  // reintentar en vez de dejar que se lo martille.
  extra: Record<string, unknown> = {},
): Response {
  return new Response(
    JSON.stringify({ error: { code, message, ...extra } }),
    { status, headers: { ...CORS, 'Content-Type': 'application/json' } },
  );
}

export function ok(payload: unknown): Response {
  return new Response(
    JSON.stringify(payload),
    { headers: { ...CORS, 'Content-Type': 'application/json' } },
  );
}

/**
 * Lo que se le pide al modelo, en el dialecto que entiende Gemini. Se pasa como
 * `responseSchema` para que no pueda devolver otra forma, y **igual** se valida
 * después: que el proveedor prometa un formato no es garantía de que lo cumpla.
 *
 * En v4 las kcal del ítem no son el número que dice el modelo: el modelo da
 * cuántos gramos hay en el plato y cuánto tiene el alimento cada 100 g, y la
 * cuenta la hace [validate]. Son dos preguntas que el modelo contesta con
 * distinta calidad —la porción es una inferencia sobre la foto; la densidad es
 * un dato de tabla— y pedírselas juntas, como un total redondo, es de donde
 * salían los "a ojo" que se pasaban. Separadas, cada una se puede revisar por
 * su lado.
 *
 * El `kcal` que igual se le pide es un control, no el resultado: si no coincide
 * con la cuenta, el modelo mezcló los campos (ver [fromPer100]).
 *
 * Hacia la app no cambia nada: [validate] devuelve los mismos campos de
 * siempre (`kcal`, `proteinG`, …), que es el contrato de
 * `docs/handoff/gemini-output-schema.json`.
 *
 * `propertyOrdering` no es decorativo: el modelo escribe en ese orden, y la
 * referencia visual va **antes** que los gramos para que el peso salga de la
 * referencia y no al revés.
 */
const RESPONSE_SCHEMA_V4 = {
  type: 'OBJECT',
  required: ['title', 'items', 'overallConfidence'],
  propertyOrdering: ['title', 'items', 'overallConfidence'],
  properties: {
    title: { type: 'STRING' },
    items: {
      type: 'ARRAY',
      maxItems: 12,
      items: {
        type: 'OBJECT',
        required: [
          'name', 'grams', 'quantity', 'unit',
          'kcalPer100g', 'proteinPer100g', 'carbsPer100g', 'fatPer100g',
          'kcal', 'confidence',
        ],
        propertyOrdering: [
          'name', 'preparation', 'visualReference', 'grams', 'quantity',
          'unit', 'kcalPer100g', 'proteinPer100g', 'carbsPer100g',
          'fatPer100g', 'alcoholPer100g', 'kcal', 'confidence',
        ],
        properties: {
          name: { type: 'STRING' },
          preparation: { type: 'STRING' },
          visualReference: { type: 'STRING' },
          grams: { type: 'NUMBER' },
          quantity: { type: 'NUMBER' },
          unit: {
            type: 'STRING',
            enum: ['g', 'ml', 'unidad', 'taza', 'cucharada', 'rebanada', 'porcion'],
          },
          kcalPer100g: { type: 'NUMBER' },
          proteinPer100g: { type: 'NUMBER' },
          carbsPer100g: { type: 'NUMBER' },
          fatPer100g: { type: 'NUMBER' },
          alcoholPer100g: { type: 'NUMBER' },
          kcal: { type: 'INTEGER' },
          confidence: { type: 'NUMBER' },
        },
      },
    },
    overallConfidence: { type: 'NUMBER' },
  },
};

/** El contrato de antes de v4: el modelo dice las kcal y los macros totales. */
const RESPONSE_SCHEMA_V3 = {
  type: 'OBJECT',
  required: ['title', 'items', 'overallConfidence'],
  properties: {
    title: { type: 'STRING' },
    items: {
      type: 'ARRAY',
      maxItems: 12,
      items: {
        type: 'OBJECT',
        required: [
          'name', 'quantity', 'unit', 'kcal',
          'proteinG', 'carbsG', 'fatG', 'confidence',
        ],
        properties: {
          name: { type: 'STRING' },
          quantity: { type: 'NUMBER' },
          unit: {
            type: 'STRING',
            enum: ['g', 'ml', 'unidad', 'taza', 'cucharada', 'rebanada', 'porcion'],
          },
          kcal: { type: 'INTEGER' },
          proteinG: { type: 'NUMBER' },
          carbsG: { type: 'NUMBER' },
          fatG: { type: 'NUMBER' },
          confidence: { type: 'NUMBER' },
          preparation: { type: 'STRING' },
          visualReference: { type: 'STRING' },
        },
      },
    },
    overallConfidence: { type: 'NUMBER' },
  },
};

/** El contrato que corresponde a [PROMPT_VERSION]. */
export const RESPONSE_SCHEMA =
  PROMPT_VERSION === 'v3' ? RESPONSE_SCHEMA_V3 : RESPONSE_SCHEMA_V4;

export interface AnalysisItem {
  name: string;
  quantity: number;
  unit: string;
  kcal: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
  confidence: number;
  preparation?: string;
  visualReference?: string;
}

const UNITS = ['g', 'ml', 'unidad', 'taza', 'cucharada', 'rebanada', 'porcion'];

/**
 * Cuánto pueden diferir las kcal cada 100 g de lo que dan sus macros antes de
 * que se las corrija: 20 %, o 15 kcal en los alimentos que casi no tienen.
 *
 * Holgado a propósito. Las tablas cuentan los carbohidratos con la fibra
 * adentro, y la fibra casi no aporta, así que una legumbre o un pan integral ya
 * dan algo por debajo de 4·P + 4·C + 9·G aun estando bien. Lo que se quiere
 * atrapar es otra cosa: el número que no sale de ninguna tabla.
 */
const ATWATER_TOLERANCE = 0.2;
const ATWATER_FLOOR_KCAL = 15;

/** Techo de confianza para un ítem cuyas kcal hubo que corregir. */
const CORRECTED_CONFIDENCE = 0.5;

/**
 * Cuánto pueden diferir la cuenta y el `kcal` que dijo el modelo antes de
 * sospechar que mezcló los campos: una vez y media, y más de 50 kcal (en un
 * ítem chico una diferencia de proporción no mueve el día de nadie).
 */
const CROSS_CHECK_RATIO = 1.5;
const CROSS_CHECK_FLOOR_KCAL = 50;

const inRange = (v: number, min: number, max: number) =>
  Number.isFinite(v) && v >= min && v <= max;

const redondear = (v: number) => Math.round(v * 10) / 10;

interface Totals {
  kcal: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
  /** Los gramos con que se hizo la cuenta, si se hizo. */
  grams: number | null;
  /** `false` si las kcal no cerraban con los macros y hubo que corregirlas. */
  consistent: boolean;
}

/**
 * Los totales del ítem a partir de gramos × valores cada 100 g.
 *
 * Es la cuenta que antes hacía el modelo de memoria y redondeando para arriba.
 * Acá además se controla que las kcal cierren con los macros (4·P + 4·C + 9·G +
 * 7·alcohol): si no cierran, una de las dos está inventada, y los macros —tres
 * números que tienen que sumar menos de 100 g— son más difíciles de inventar
 * bien que uno solo. Entonces las kcal se llevan al borde de la tolerancia, no
 * al valor exacto de Atwater, para no castigar a los alimentos con fibra.
 */
function fromPer100(i: Record<string, unknown>): Totals | null {
  const grams = Number(i.grams);
  const kcal100 = Number(i.kcalPer100g);
  const p100 = Number(i.proteinPer100g);
  const c100 = Number(i.carbsPer100g);
  const f100 = Number(i.fatPer100g);
  const a100 = i.alcoholPer100g == null ? 0 : Number(i.alcoholPer100g);

  if (!inRange(grams, 0.1, 5000)) return null;
  // 900 es grasa pura: nada de lo que se come tiene más.
  if (!inRange(kcal100, 0, 900)) return null;
  if (!inRange(p100, 0, 100)) return null;
  if (!inRange(c100, 0, 100)) return null;
  if (!inRange(f100, 0, 100)) return null;
  if (!inRange(a100, 0, 50)) return null;
  // En 100 g no entran más de 100 g de nada. Un poco de margen por redondeo.
  if (p100 + c100 + f100 + a100 > 105) return null;

  const atwater = 4 * p100 + 4 * c100 + 9 * f100 + 7 * a100;
  const tolerance = Math.max(ATWATER_FLOOR_KCAL, atwater * ATWATER_TOLERANCE);
  const kcalFixed = Math.min(
    Math.max(kcal100, atwater - tolerance),
    atwater + tolerance,
  );
  const computed = (grams * kcalFixed) / 100;

  // El control contra el `kcal` que dijo el modelo. El error que se busca no
  // es de puntería sino de casilla: el total del plato escrito donde iba el
  // valor cada 100 g. Ese error no lo ve Atwater —los macros vienen igual de
  // corridos y cierran entre sí— y multiplica por gramos/100 sin avisar: 450
  // kcal "cada 100 g" sobre 180 g son 810. Cuando la cuenta y el total del
  // modelo no se parecen, no se sabe cuál de los dos está mal, y se elige el
  // total del modelo: es el número que daba v3, así que en el peor caso v4
  // queda igual que antes, nunca peor por esto.
  const claimed = Number(i.kcal);
  if (
    Number.isFinite(claimed) && claimed > 0 && computed > 0 &&
    Math.abs(computed - claimed) > CROSS_CHECK_FLOOR_KCAL &&
    (computed / claimed > CROSS_CHECK_RATIO ||
      claimed / computed > CROSS_CHECK_RATIO)
  ) {
    const factor = claimed / computed;
    return {
      kcal: Math.round(claimed),
      proteinG: redondear((grams * p100 * factor) / 100),
      carbsG: redondear((grams * c100 * factor) / 100),
      fatG: redondear((grams * f100 * factor) / 100),
      grams,
      consistent: false,
    };
  }

  return {
    kcal: Math.round(computed),
    proteinG: redondear((grams * p100) / 100),
    carbsG: redondear((grams * c100) / 100),
    fatG: redondear((grams * f100) / 100),
    grams,
    consistent: kcalFixed === kcal100,
  };
}

/**
 * Los totales tal como los dio el modelo: el contrato de antes de v4.
 *
 * Queda como red. Si un modelo ignora el schema y contesta a la vieja usanza,
 * mejor una estimación sin control que perder el análisis entero.
 */
function fromTotals(i: Record<string, unknown>): Totals | null {
  const kcal = Number(i.kcal);
  const proteinG = Number(i.proteinG);
  const carbsG = Number(i.carbsG);
  const fatG = Number(i.fatG);
  if (!inRange(kcal, 0, 3000)) return null;
  if (!inRange(proteinG, 0, 500)) return null;
  if (!inRange(carbsG, 0, 500)) return null;
  if (!inRange(fatG, 0, 500)) return null;
  return {
    kcal: Math.round(kcal),
    proteinG,
    carbsG,
    fatG,
    grams: null,
    consistent: true,
  };
}

const normalizar = (s: string) => s.trim().toLowerCase().replace(/\s+/g, ' ');

/**
 * El ítem de la comida ya cargada que el modelo devolvió sin tocar, si es eso.
 *
 * En un recálculo, lo que la corrección no menciona tiene que volver **igual**
 * (ver `recalculatedFrom`). Antes eso dependía de que el modelo copiara bien los
 * números; ahora el modelo da gramos y valores cada 100 g, y rehacer la cuenta
 * movería un par de kcal en ítems que la persona ya había dado por buenos. Se
 * resuelve acá: mismo nombre, misma unidad, misma cantidad → mismos números.
 */
function unchanged(
  kept: CurrentItem[],
  name: string,
  quantity: number,
  unit: string,
): CurrentItem | undefined {
  const key = normalizar(name);
  return kept.find((k) =>
    normalizar(k.name) === key &&
    k.unit === unit &&
    Math.abs(k.quantity - quantity) <= 0.01 * Math.max(1, quantity)
  );
}

/**
 * Valida la respuesta, hace la cuenta de cada ítem y descarta los que no
 * cumplen.
 *
 * Devuelve `null` solo si la respuesta entera es inservible. Un ítem con un
 * número imposible se tira y los demás siguen: perder un alimento es mejor que
 * perder el análisis completo, y **muchísimo** mejor que meterle a alguien un
 * "9000 kcal" al historial.
 *
 * `kept` son los ítems de la comida cuando esto es un recálculo: los que vuelven
 * sin cambios conservan sus números exactos.
 */
export function validate(
  raw: unknown,
  kept: CurrentItem[] = [],
): AnalysisItem[] | null {
  if (!raw || typeof raw !== 'object') return null;
  const rawItems = (raw as { items?: unknown }).items;
  if (!Array.isArray(rawItems)) return null;

  const clean: AnalysisItem[] = [];
  for (const entry of rawItems.slice(0, 12)) {
    if (!entry || typeof entry !== 'object') continue;
    const i = entry as Record<string, unknown>;

    const name = typeof i.name === 'string' ? i.name.trim() : '';
    if (!name || name.length > 120) continue;

    let quantity = Number(i.quantity);
    let confidence = Number(i.confidence);
    const unit = typeof i.unit === 'string' ? i.unit : '';

    if (!inRange(quantity, 0.1, 5000)) continue;
    if (!inRange(confidence, 0, 1)) continue;
    if (!UNITS.includes(unit)) continue;

    const same = unchanged(kept, name, quantity, unit);
    const totals: Totals | null = same
      ? { ...same, grams: null, consistent: true }
      : fromPer100(i) ?? fromTotals(i);
    if (!totals) continue;
    if (!inRange(totals.kcal, 0, 3000)) continue;
    if (!inRange(totals.proteinG, 0, 500)) continue;
    if (!inRange(totals.carbsG, 0, 500)) continue;
    if (!inRange(totals.fatG, 0, 500)) continue;

    // Si la unidad es gramos, la cantidad que se muestra tiene que ser la misma
    // con la que se hizo la cuenta: "150 g · 400 kcal" calculado sobre 180 g
    // sería un número que no se puede verificar mirando la pantalla.
    if (unit === 'g' && totals.grams !== null) {
      quantity = Math.round(totals.grams);
    }
    if (!totals.consistent) {
      confidence = Math.min(confidence, CORRECTED_CONFIDENCE);
    }

    clean.push({
      name,
      quantity,
      unit,
      kcal: totals.kcal,
      proteinG: totals.proteinG,
      carbsG: totals.carbsG,
      fatG: totals.fatG,
      confidence,
      preparation: typeof i.preparation === 'string'
        ? i.preparation.slice(0, 60)
        : undefined,
      visualReference: typeof i.visualReference === 'string'
        ? i.visualReference.slice(0, 120)
        : undefined,
    });
  }

  // El array vacío es una respuesta válida — significa "no hay comida" — y por
  // eso se distingue de `null`, que es "la respuesta no se pudo leer".
  return clean;
}

/** Un título más largo que esto ya no se lee de un vistazo en una lista. */
const MAX_TITLE = 60;

/**
 * El nombre del plato entero: "Milanesa con puré", no el primer ingrediente.
 *
 * Devuelve `null` si no vino o si no sirve, y eso **no** invalida el análisis:
 * la app arma el título con los ítems cuando falta. Un modelo que se olvidó de
 * una etiqueta no puede costar una estimación que por lo demás está bien.
 */
export function validateTitle(raw: unknown): string | null {
  if (!raw || typeof raw !== 'object') return null;
  const title = (raw as { title?: unknown }).title;
  if (typeof title !== 'string') return null;
  // Una línea sola: un modelo que se entusiasma devuelve un párrafo, y eso en
  // una fila de lista es peor que no tener título.
  const clean = title.split('\n')[0].trim();
  if (!clean) return null;
  return clean.length > MAX_TITLE ? clean.slice(0, MAX_TITLE).trimEnd() : clean;
}

/**
 * Lo que el proveedor cuenta de la corrida, para guardarlo en `ai_analyses`.
 *
 * Todo esto venía en cada respuesta y se descartaba. Son las columnas que
 * agregó la migración 39: sin ellas, "el modelo devolvió cualquier cosa" es
 * todo lo que se puede decir de una falla, y con ellas se sabe **cuál** de las
 * cinco maneras de fallar fue.
 */
export interface GeminiDiagnostics {
  /** `STOP` si terminó de decir lo suyo; `MAX_TOKENS` si lo cortaron, etc. */
  finishReason: string | null;
  tokensIn: number | null;
  tokensOut: number | null;
  /** De los de salida, los que se fueron en razonar. Se facturan igual. */
  tokensThinking: number | null;
}

export interface GeminiOutcome {
  parsed: unknown;
  lastError: string;
  /** 429: la cuota del proyecto se agotó. */
  rateLimited: boolean;
  /** 503: el modelo está saturado. Se parece al 429 y no es lo mismo. */
  overloaded: boolean;
  /**
   * Se acabó [GEMINI_BUDGET_MS] antes de que el proveedor contestara.
   *
   * Va aparte de `lastError` porque quien llama tiene que poder decirlo con su
   * propio código —un 504, no un "el modelo devolvió cualquier cosa"—: mandar a
   * sacar otra foto cuando el problema fue la demora es mandar a arreglar el
   * lugar equivocado.
   */
  timedOut: boolean;
  /** Lo que el proveedor pide esperar, cuando lo dice. `null` si no lo dijo. */
  retryAfterSeconds: number | null;
  diagnostics: GeminiDiagnostics;
  latencyMs: number;
}

/**
 * Motivos de corte que **no cambian por reintentar**.
 *
 * Un JSON truncado a la mitad no se arregla pidiéndolo de nuevo: la respuesta
 * se va a cortar en el mismo lugar, porque el segundo intento va a
 * `temperature: 0` y es determinista. Un filtro de contenido, lo mismo. Antes
 * insistíamos igual y cada respuesta ilegible costaba dos pedidos de la cuota
 * — el 13 de agosto fueron 8 de 20 gastados así.
 */
const TERMINAL_FINISH = new Set<string>([
  'MAX_TOKENS',
  'SAFETY',
  'RECITATION',
  'BLOCKLIST',
  'PROHIBITED_CONTENT',
  'SPII',
]);

/**
 * Cuánto pide esperar Google, si lo dice.
 *
 * El cuerpo de un 429 trae `error.details[]` con un `RetryInfo` y un
 * `retryDelay` tipo `"26s"`. Es el único dato honesto que existe sobre cuándo
 * vale la pena volver: sin él, "esperá un minuto" es una adivinanza.
 */
function parseRetryDelay(body: string): number | null {
  const match = /"retryDelay"\s*:\s*"(\d+(?:\.\d+)?)s"/.exec(body);
  if (!match) return null;
  const seconds = Math.ceil(Number(match[1]));
  return Number.isFinite(seconds) && seconds > 0 ? seconds : null;
}

/**
 * Le manda las partes a Gemini y devuelve el JSON ya parseado.
 *
 * Reintenta una vez: si el JSON vino inválido, el segundo intento va con
 * `temperature: 0` y es determinista, así que insistir más no aportaría nada.
 *
 * **Un 429 no se reintenta.** Antes sí: esperaba 2 s y mandaba la llamada de
 * nuevo. Las dos mitades de esa idea estaban mal. La ventana del proveedor es
 * por minuto o por día, así que 2 s no libera nada y el segundo intento
 * rebota igual; y como la cuota es **del proyecto entero** —una sola clave
 * para toda la app— ese intento perdido no lo paga quien lo disparó, lo paga
 * la próxima persona que saque una foto. O sea: cuando ya estamos al límite,
 * el reintento nos hacía consumir el doble. Un 503 sí se reintenta, porque es
 * el modelo saturado un momento y no la cuota.
 *
 * Los dos se marcan aparte del resto: no son "la comida está mal descripta", y
 * decirlo así manda a corregir el lugar equivocado.
 */
export async function callGemini(
  apiKey: string,
  parts: unknown[],
  // Por omisión el contrato de estimación, que es el que usan las dos
  // funciones que estiman una comida. `suggest-meals` devuelve otra forma
  // —tres opciones, cada una con sus ingredientes y su receta— y pasa la suya.
  schema: unknown = RESPONSE_SCHEMA,
): Promise<GeminiOutcome> {
  const startedAt = Date.now();
  // El techo de todos los intentos juntos, fijado **una vez**. Cada intento se
  // corta con lo que quede, no con 18 s frescos: dos relojes independientes es
  // exactamente cómo se llegaba a 50 s.
  const deadline = startedAt + GEMINI_BUDGET_MS;
  let parsed: unknown = null;
  let lastError = '';
  let rateLimited = false;
  let overloaded = false;
  let timedOut = false;
  let retryAfterSeconds: number | null = null;
  const diagnostics: GeminiDiagnostics = {
    finishReason: null,
    tokensIn: null,
    tokensOut: null,
    tokensThinking: null,
  };

  for (let intento = 0; intento < MAX_ATTEMPTS; intento++) {
    // El primero con algo de temperatura y los siguientes en cero. El cero es
    // determinista, y de eso depende la regla de más abajo: si con cero el
    // modelo devolvió algo ilegible, pedírselo otra vez devuelve lo mismo.
    const temperature = intento === 0 ? 0.2 : 0;

    const left = deadline - Date.now();
    if (left < MIN_ATTEMPT_MS) {
      // Se acabó el presupuesto entre un intento y el otro. No es un intento
      // fallido más: es que ya no hay tiempo, y hay que decirlo así.
      timedOut = true;
      lastError = lastError ||
        `Sin tiempo para otro intento (${GEMINI_BUDGET_MS / 1000} s)`;
      break;
    }

    const controller = new AbortController();
    const timer = setTimeout(
      () => controller.abort(),
      Math.min(GEMINI_TIMEOUT_MS, left),
    );

    try {
      const response = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`,
        {
          method: 'POST',
          signal: controller.signal,
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': apiKey,
          },
          body: JSON.stringify({
            contents: [{ parts }],
            generationConfig: {
              temperature,
              responseMimeType: 'application/json',
              responseSchema: schema,
              // Ver [THINKING_LEVEL]: sin esto el modelo razona de fábrica y
              // cada foto se paga y se espera dos veces.
              ...(SENDS_THINKING
                ? { thinkingConfig: { thinkingLevel: THINKING_LEVEL } }
                : {}),
            },
          }),
        },
      );

      if (!response.ok) {
        // El cuerpo dice *por qué*; sin él, un 404 puede ser el modelo, la
        // clave o la URL y no hay forma de distinguirlos.
        const detail = await response.text().catch(() => '');
        lastError = `Gemini ${response.status}: ${detail.slice(0, 300)}`;
        if (response.status === 429) {
          // Cuota agotada. Insistir acá es gastar el cupo de otro: se corta.
          rateLimited = true;
          retryAfterSeconds = parseRetryDelay(detail);
          break;
        }
        if (response.status === 503) {
          // Saturación pasajera, no cuota. Esta sí se reintenta, y por eso se
          // marca aparte: mezclarlas hizo que un problema de dos segundos se
          // leyera como el límite del plan.
          overloaded = true;
          // La espera sale del mismo presupuesto que los intentos, así que se
          // duerme solo si después va a quedar tiempo para intentar de verdad.
          if (deadline - Date.now() > 2000 + MIN_ATTEMPT_MS) {
            await new Promise((r) => setTimeout(r, 2000));
          }
        }
        continue;
      }
      rateLimited = false;
      overloaded = false;
      // Contestó: lo que haya pasado en un intento anterior ya no es lo que hay
      // que reportar. Sin esto, un primer intento colgado dejaba `timedOut` en
      // `true` y el 504 le ganaba al resultado bueno del segundo.
      timedOut = false;
      retryAfterSeconds = null;

      const payload = await response.json();
      readDiagnostics(payload, diagnostics);

      const text = payload?.candidates?.[0]?.content?.parts?.[0]?.text;
      if (!text) {
        lastError = `Gemini no devolvió contenido (corte: ${
          diagnostics.finishReason ?? 'sin motivo'
        })`;
        if (isTerminal(diagnostics.finishReason) || temperature === 0) break;
        continue;
      }

      try {
        parsed = JSON.parse(text);
        break;
      } catch (error) {
        // El `try` propio es lo que hace útil al de arriba: un JSON cortado
        // caía en el `catch` general, que no distingue "el modelo devolvió
        // basura" de "se cayó la red" y reintentaba en los dos casos.
        parsed = null;
        lastError = `JSON inválido (corte: ${
          diagnostics.finishReason ?? 'sin motivo'
        }): ${error instanceof Error ? error.message : String(error)}`;
        // Un `temperature: 0` que devolvió basura la va a volver a devolver
        // igual: es determinista. Acá el intento de más no compra nada y se
        // paga, así que se corta aunque queden intentos en el presupuesto.
        if (isTerminal(diagnostics.finishReason) || temperature === 0) break;
        continue;
      }
    } catch (error) {
      lastError = error instanceof Error ? error.message : String(error);
      // Lo cortamos nosotros: el proveedor no contestó dentro del intento.
      //
      // **Esto sí se reintenta**, y haberlo hecho terminal fue un error que
      // costó una versión. El razonamiento era "si tardó, va a volver a
      // tardar"; los datos de `ai_analyses` dicen que no. Los intentos que
      // fallan no tardan, se **cuelgan**: vuelven con `tokens_in` en `null` —ni
      // un byte— y siempre topan exactos contra [GEMINI_TIMEOUT_MS], mientras
      // que el intento siguiente contesta en 5 o 15 s. Los análisis que antes
      // terminaban en 35 o 40 s eran justamente eso: un cuelgue y un reintento
      // que salió bien. Al cortarlos de una, esos pasaron a fallar y la persona
      // tuvo que reintentar a mano dos o tres veces — el mismo gasto, pero
      // encima molestando.
      //
      // Un cuelgue tampoco consume del proveedor: nunca llegó a generar nada.
      if (isAbort(error)) {
        timedOut = true;
        lastError = `El proveedor no contestó en ${
          Math.round(Math.min(GEMINI_TIMEOUT_MS, GEMINI_BUDGET_MS) / 1000)
        } s (intento ${intento + 1})`;
        continue;
      }
    } finally {
      // En el `finally` y no después del `fetch`: el temporizador tiene que
      // seguir armado mientras se lee el cuerpo. Cancelarlo apenas vuelven los
      // headers dejaba la lectura del JSON sin ningún techo, que es otra forma
      // —más silenciosa— de quedarse colgado para siempre.
      clearTimeout(timer);
    }
  }

  return {
    parsed,
    lastError,
    rateLimited,
    overloaded,
    timedOut,
    retryAfterSeconds,
    diagnostics,
    latencyMs: Date.now() - startedAt,
  };
}

/**
 * Si el corte lo pedimos nosotros.
 *
 * `AbortError` es lo que tira `fetch` cuando dispara nuestro temporizador. Se
 * distingue de un fallo de red porque la salida es distinta: contra la red
 * puede valer la pena insistir, contra el reloj no.
 *
 * Se mira el `name` y no `instanceof Error` porque lo que llega es un
 * `DOMException`: hereda de `Error` según la especificación, pero apoyar la
 * decisión en una cadena de prototipos que decide el runtime es apostar a que
 * no cambie. El `name` es parte del contrato.
 */
function isAbort(error: unknown): boolean {
  return typeof error === 'object' && error !== null &&
    (error as { name?: unknown }).name === 'AbortError';
}

function isTerminal(finishReason: string | null): boolean {
  return finishReason !== null && TERMINAL_FINISH.has(finishReason);
}

/**
 * Lee el motivo del corte y el consumo de la respuesta.
 *
 * Se toma todo como entrada, no como promesa: son campos del proveedor y
 * cualquiera puede faltar o venir con otra forma. Un `usageMetadata` ausente
 * deja las columnas en `null`, que es lo correcto —no sabemos— y no un cero,
 * que sería mentira.
 */
function readDiagnostics(payload: unknown, into: GeminiDiagnostics): void {
  const root = payload as {
    candidates?: Array<{ finishReason?: unknown }>;
    usageMetadata?: Record<string, unknown>;
  } | null;

  const reason = root?.candidates?.[0]?.finishReason;
  into.finishReason = typeof reason === 'string' && reason ? reason : null;

  const usage = root?.usageMetadata;
  const count = (key: string): number | null => {
    const value = usage?.[key];
    return typeof value === 'number' && Number.isFinite(value) ? value : null;
  };

  into.tokensIn = count('promptTokenCount');
  into.tokensOut = count('candidatesTokenCount');
  into.tokensThinking = count('thoughtsTokenCount');
}

/**
 * El 429 del proveedor, con su propio código y su propio texto.
 *
 * Cuando Google dice cuánto falta, se dice: "esperá un minuto" era una cifra
 * inventada, y si en realidad faltaban diez segundos la persona esperaba de
 * más, mientras que si el cupo se soltaba recién al otro día la mandábamos a
 * reintentar cincuenta veces contra una puerta cerrada.
 */
export function rateLimitedResponse(retryAfterSeconds: number | null = null): Response {
  return fail(
    'ERR_AI_RATE_LIMITED',
    // Ojo con el `+`: TypeScript **no** concatena literales adyacentes como
    // Dart. Sin él esto no es un string partido en dos líneas, es un error de
    // sintaxis, y el deploy de la función falla entero.
    'El servicio de análisis está al límite por ahora. ' +
      `${esperaHumana(retryAfterSeconds)}, o cargá la comida a mano.`,
    429,
    // El número, además del texto: con él la app apaga el botón hasta que
    // valga la pena tocarlo. Sin él lo único que se puede hacer es leer.
    retryAfterSeconds === null ? {} : { retryAfter: retryAfterSeconds },
  );
}

/**
 * El 503: el modelo está ocupado, no la cuota agotada.
 *
 * Merece texto propio porque la salida es distinta. Contra el límite del plan
 * no hay nada que hacer más que esperar o cargar a mano; contra la saturación,
 * insistir en unos segundos suele alcanzar — y decir "estás al límite" cuando
 * el problema dura diez segundos manda a la persona a rendirse de más.
 */
export function overloadedResponse(): Response {
  return fail(
    'ERR_AI_OVERLOADED',
    'El modelo está ocupado en este momento. Probá de nuevo en unos ' +
      'segundos, o cargá la comida a mano.',
    503,
  );
}

/**
 * El 504: el proveedor no contestó dentro de [GEMINI_BUDGET_MS].
 *
 * Existe para que la app **reciba un error** en vez de quedarse esperando hasta
 * su propio timeout. La diferencia no es cosmética: así el fallo queda en
 * `ai_analyses` con su latencia y su motivo, se puede contar cuántos hubo, y el
 * texto puede decir la verdad —fue la demora, no la foto— en vez del genérico
 * que arma el cliente cuando se cansa de esperar.
 */
export function timedOutResponse(salida = ''): Response {
  return fail(
    'ERR_UPSTREAM_TIMEOUT',
    'El modelo está tardando más de lo normal y cortamos la espera. Probá de ' +
      `nuevo en un momento${salida ? `, o ${salida}` : ''}.`,
    504,
  );
}

/** El "esperá tanto" en criollo, o el genérico cuando no vino el dato. */
function esperaHumana(seconds: number | null): string {
  if (seconds === null) return 'Probá de nuevo en un rato';
  if (seconds <= 90) return `Esperá ${seconds} segundos y probá de nuevo`;
  const minutes = Math.ceil(seconds / 60);
  if (minutes <= 90) return `Esperá ${minutes} minutos y probá de nuevo`;
  // Más de una hora y media es la cuota del día, no la del minuto: mandar a
  // reintentar sería mandar a chocar contra lo mismo.
  return 'Se agotó el cupo del día del servicio; volvé mañana';
}
