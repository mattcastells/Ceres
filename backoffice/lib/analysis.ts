import { diaDeSemana, diasEntre, minutosDelDia } from './format.ts';
import { goalForDay } from './goals.ts';
import type { Goal, Meal, WeightLog } from './queries.ts';

/**
 * Las cuentas de "análisis de consulta" (`docs/panel-proximas-features.md`):
 * balance contra peso, los alimentos que se repiten, los horarios y semana
 * contra semana.
 *
 * Son **aritmética sobre lo que la ficha ya trajo**, sin IA y sin consultas
 * nuevas, y viven acá —funciones puras, con `analysis.test.ts`— y no adentro
 * de la vista por lo mismo que `lib/tracking.ts`: un número de consulta mal
 * calculado se ve igual de bien que uno bien calculado, y lo único que los
 * distingue es un test.
 */

/** Una kcal registrada de grasa corporal ≈ 7.700 kcal. Es la misma constante
 *  que usa `care-report/metrics.ts`: si el informe con IA y esta tarjeta
 *  usaran reglas distintas, dirían dos cambios esperados para el mismo mes. */
export const KCAL_POR_KG = 7700;

/** Por debajo de esto, la diferencia entre lo esperado y lo medido entra en lo
 *  que mueve el agua de un día para otro, y no se lee como brecha. */
export const MARGEN_KG = 1;

/** Con menos días registrados, un promedio de déficit es un par de días
 *  sueltos y el peso de una semana se mueve más por agua que por grasa. */
export const MIN_DIAS_BALANCE = 7;

export type Balance =
  | { estado: 'sin-gasto' }
  | { estado: 'pocos-dias'; dias: number }
  | { estado: 'sin-peso'; deficitPromedio: number; dias: number }
  | {
      estado: 'ok';
      /** Gasto estimado promedio de los días con registro (TDEE del objetivo). */
      gastoPromedio: number;
      /** Promedio de (gasto − comido) sobre los días con registro. Positivo =
       *  déficit. */
      deficitPromedio: number;
      /** Días con registro que entraron en la cuenta. */
      dias: number;
      /** Días entre el primer y el último pesaje del período. */
      diasEntrePesajes: number;
      esperadoKg: number;
      medidoKg: number;
      /** medido − esperado. Positivo = bajó menos (o subió más) de lo que
       *  explica el registro. */
      brechaKg: number;
      lectura: 'coincide' | 'menos-de-lo-esperado' | 'mas-de-lo-esperado';
    };

/**
 * Balance energético estimado contra peso real.
 *
 * Es la pregunta clínica número uno: si el registro dice un déficit de 500
 * kcal/día durante cuatro semanas y la balanza dice −0,3 kg, lo más probable no
 * es "no funcionó" sino **comida sin registrar**, y esa es otra conversación
 * que "hay que bajar más las calorías". Sin este cruce, el riesgo es recortar
 * el objetivo de alguien que ya come menos de lo que anota.
 *
 * - El gasto sale de `goals.tdee_kcal` del objetivo **de cada día**: la app ya
 *   lo calculó, y portar la fórmula acá sería la forma más segura de que el
 *   teléfono y la web estimen distinto. No se suma la actividad registrada: el
 *   TDEE ya incluye el nivel de actividad, y sumarla la contaría dos veces.
 * - El déficit se promedia **sobre los días con registro** —lo que no se
 *   registró no se sabe— y se proyecta sobre el tiempo entre el primer y el
 *   último pesaje. Es decir: "si los días sin anotar fueran como los anotados".
 *   El informe con IA (`metrics.ts`) suma el déficit de los días registrados
 *   sin proyectar; acá se proyecta porque lo que se compara es contra lo que
 *   marcó la balanza en esas fechas, y la balanza no se saltea los días.
 * - Hacen falta dos pesajes con al menos una semana entre medio.
 */
export function balanceEnergetico(input: {
  /** kcal comidas por fecha, solo los días con registro y dentro de la ventana. */
  kcalPorDia: Map<string, number>;
  goals: Goal[];
  /** Pesajes del período, en cualquier orden. */
  weights: WeightLog[];
}): Balance {
  const dias: { kcal: number; gasto: number }[] = [];
  for (const [fecha, kcal] of input.kcalPorDia) {
    const gasto = goalForDay(input.goals, fecha)?.tdee_kcal ?? null;
    if (gasto && gasto > 0) dias.push({ kcal, gasto });
  }

  if (dias.length === 0) return { estado: 'sin-gasto' };
  if (dias.length < MIN_DIAS_BALANCE) return { estado: 'pocos-dias', dias: dias.length };

  const gastoPromedio = promedio(dias.map((d) => d.gasto));
  const deficitPromedio = promedio(dias.map((d) => d.gasto - d.kcal));

  const pesajes = [...input.weights].sort((a, b) =>
    a.local_date.localeCompare(b.local_date),
  );
  const primero = pesajes[0];
  const ultimo = pesajes[pesajes.length - 1];
  const diasEntrePesajes =
    primero && ultimo ? diasEntre(primero.local_date, ultimo.local_date) : 0;

  if (pesajes.length < 2 || diasEntrePesajes < 7) {
    return {
      estado: 'sin-peso',
      deficitPromedio: Math.round(deficitPromedio),
      dias: dias.length,
    };
  }

  const esperadoKg = redondear((-deficitPromedio * diasEntrePesajes) / KCAL_POR_KG, 1);
  const medidoKg = redondear(Number(ultimo.weight_kg) - Number(primero.weight_kg), 1);
  const brechaKg = redondear(medidoKg - esperadoKg, 1);

  return {
    estado: 'ok',
    gastoPromedio: Math.round(gastoPromedio),
    deficitPromedio: Math.round(deficitPromedio),
    dias: dias.length,
    diasEntrePesajes,
    esperadoKg,
    medidoKg,
    brechaKg,
    lectura:
      Math.abs(brechaKg) < MARGEN_KG
        ? 'coincide'
        : brechaKg > 0
          ? 'menos-de-lo-esperado'
          : 'mas-de-lo-esperado',
  };
}

export type AlimentoFrecuente = {
  nombre: string;
  veces: number;
  /** En cuántos días distintos apareció. */
  dias: number;
  kcal: number;
  /** Qué parte de las kcal del período aportó, de 0 a 100. */
  pctKcal: number;
  /** En qué momentos aparece, en el orden fijo de la app. */
  momentos: string[];
};

const ORDEN_MOMENTOS = ['breakfast', 'lunch', 'snack', 'dinner'];

/**
 * El nombre con el que se agrupa: sin mayúsculas, sin tildes y sin espacios de
 * más.
 *
 * `meal_items` no guarda un id de alimento, y a propósito: el ítem es una foto
 * de lo que se comió ese día, y la migración 43 sacó las claves que apuntaban
 * al catálogo justamente porque una foto con puntero al original es una
 * contradicción. Los nombres vienen de tres catálogos y del modelo, así que
 * "Banana" y "banana " son la misma fila. "Pan integral" y "Pan lactal
 * integral" siguen siendo dos: juntarlos sería inventar una categorización
 * arriba de un dato bueno.
 */
export function normalizarNombre(nombre: string): string {
  return nombre
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * Los alimentos que se repiten en el período, del más repetido al menos.
 *
 * Contesta "¿qué desayunás normalmente?" con el dato medido en vez de con la
 * memoria del paciente. Solo entra lo que aparece **dos veces o más**: lo que
 * se comió una vez no "se repite", y una lista de cuarenta ítems sueltos tapa
 * a los cinco que importan.
 */
export function alimentosFrecuentes(
  meals: Pick<Meal, 'local_date' | 'slot' | 'meal_items'>[],
  limite = 15,
): AlimentoFrecuente[] {
  const grupos = new Map<
    string,
    {
      veces: number;
      kcal: number;
      dias: Set<string>;
      momentos: Set<string>;
      grafias: Map<string, number>;
    }
  >();
  let kcalTotal = 0;

  for (const m of meals) {
    for (const it of m.meal_items ?? []) {
      const kcal = Number(it.kcal) || 0;
      kcalTotal += kcal;
      const original = (it.name ?? '').trim();
      const clave = normalizarNombre(original);
      if (!clave) continue;
      const g = grupos.get(clave) ?? {
        veces: 0,
        kcal: 0,
        dias: new Set<string>(),
        momentos: new Set<string>(),
        grafias: new Map<string, number>(),
      };
      g.veces += 1;
      g.kcal += kcal;
      g.dias.add(m.local_date);
      g.momentos.add(m.slot);
      g.grafias.set(original, (g.grafias.get(original) ?? 0) + 1);
      grupos.set(clave, g);
    }
  }

  return [...grupos.values()]
    .filter((g) => g.veces >= 2)
    .sort((a, b) => b.veces - a.veces || b.kcal - a.kcal)
    .slice(0, limite)
    .map((g) => ({
      // Se muestra la grafía más usada, no la normalizada: "pan integral" en
      // minúscula y sin tilde parece un error de la pantalla.
      nombre: [...g.grafias.entries()].sort((a, b) => b[1] - a[1])[0][0],
      veces: g.veces,
      dias: g.dias.size,
      kcal: Math.round(g.kcal),
      pctKcal: kcalTotal > 0 ? Math.round((g.kcal / kcalTotal) * 100) : 0,
      momentos: ORDEN_MOMENTOS.filter((s) => g.momentos.has(s)).concat(
        [...g.momentos].filter((s) => !ORDEN_MOMENTOS.includes(s)),
      ),
    }));
}

export type DiaHorario = {
  fecha: string;
  /** Cada comida del día: minutos desde la medianoche y momento. */
  comidas: { min: number; slot: string }[];
  primera: number;
  ultima: number;
};

export type Horarios = {
  dias: DiaHorario[];
  primeraPromedio: number | null;
  ultimaPromedio: number | null;
  /** Minutos entre la primera y la última comida, en promedio. */
  ventanaPromedio: number | null;
  /** Desvío estándar de la hora de la primera comida, en minutos: lo que
   *  distingue a quien desayuna a las 8 todos los días de quien un día
   *  arranca a las 8 y otro a las 14, que tienen el mismo promedio. */
  variacionPrimera: number | null;
};

/**
 * A qué hora come, y cuánto varía.
 *
 * Sale de `meals.eaten_at`, que es la hora que la persona eligió en el
 * formulario ("Cambiar hora") y no la de carga: la migración 44 la renombró
 * desde `logged_at` justamente para que no pareciera un dato de auditoría.
 *
 * Una cena o un snack de después de medianoche (la 00:30 del sábado, que el
 * teléfono anotó en el viernes) se cuenta como 24:30 del día que lo tiene
 * anotado, no como la primera comida del viernes: si no, ese día "arrancaría"
 * a las 00:30 y la ventana se iría a veinte horas.
 */
export function horarios(
  meals: Pick<Meal, 'local_date' | 'slot' | 'eaten_at'>[],
): Horarios {
  const porDia = new Map<string, { min: number; slot: string }[]>();
  for (const m of meals) {
    if (!m.eaten_at) continue;
    let min = minutosDelDia(m.eaten_at);
    if (min === null) continue;
    if (min < 4 * 60 && (m.slot === 'dinner' || m.slot === 'snack')) min += 24 * 60;
    porDia.set(m.local_date, [...(porDia.get(m.local_date) ?? []), { min, slot: m.slot }]);
  }

  const dias: DiaHorario[] = [...porDia.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([fecha, comidas]) => {
      const orden = [...comidas].sort((a, b) => a.min - b.min);
      return {
        fecha,
        comidas: orden,
        primera: orden[0].min,
        ultima: orden[orden.length - 1].min,
      };
    });

  if (dias.length === 0) {
    return {
      dias,
      primeraPromedio: null,
      ultimaPromedio: null,
      ventanaPromedio: null,
      variacionPrimera: null,
    };
  }

  const primeras = dias.map((d) => d.primera);
  // La ventana solo tiene sentido en días con dos comidas o más: un día con
  // una sola comida cargada tiene "ventana cero", que no es lo que pasó.
  const conVentana = dias.filter((d) => d.comidas.length >= 2);

  return {
    dias,
    primeraPromedio: Math.round(promedio(primeras)),
    ultimaPromedio: Math.round(promedio(dias.map((d) => d.ultima))),
    ventanaPromedio: conVentana.length
      ? Math.round(promedio(conVentana.map((d) => d.ultima - d.primera)))
      : null,
    variacionPrimera: dias.length >= 3 ? Math.round(desvio(primeras)) : null,
  };
}

export type Semana = {
  /** El lunes de la semana (o el primer día de la ventana, si arranca después). */
  desde: string;
  hasta: string;
  /** Días de esa semana que caen en la ventana efectiva. */
  diasEnVentana: number;
  incompleta: boolean;
  diasConComidas: number;
  kcalPromedio: number | null;
  proteinaPromedio: number | null;
  minutosActividad: number;
  /** Último pesaje de la semana. */
  peso: number | null;
  diasEnfermedad: number;
  diasConAlcohol: number;
};

/**
 * Semana contra semana.
 *
 * El período es un bloque de 30 o 90 días, y la consulta piensa en semanas:
 * "las dos primeras bien y después se cayó". Las semanas son de lunes a
 * domingo, como el resto del panel, y se arman **sobre la ventana efectiva**
 * (`lib/tracking.ts`): la semana en que la persona empezó tiene los días desde
 * que empezó, no siete, y se marca como incompleta. No se compara media semana
 * contra una entera sin decirlo.
 */
export function semanas(input: {
  /** Las fechas de la ventana efectiva, de la más vieja a la más nueva. */
  fechas: string[];
  kcalPorDia: Map<string, number>;
  proteinaPorDia: Map<string, number>;
  minutosPorDia: Map<string, number>;
  weights: WeightLog[];
  diasEnfermedad: Set<string>;
  diasConAlcohol: Set<string>;
}): Semana[] {
  const grupos: string[][] = [];
  for (const f of input.fechas) {
    const actual = grupos[grupos.length - 1];
    if (!actual || diaDeSemana(f) === 0) grupos.push([f]);
    else actual.push(f);
  }

  const pesoPorFecha = new Map(
    input.weights.map((w) => [w.local_date, Number(w.weight_kg)]),
  );

  return grupos.map((dias) => {
    const conComida = dias.filter((d) => input.kcalPorDia.has(d));
    const pesos = dias.filter((d) => pesoPorFecha.has(d));
    return {
      desde: dias[0],
      hasta: dias[dias.length - 1],
      diasEnVentana: dias.length,
      incompleta: dias.length < 7,
      diasConComidas: conComida.length,
      kcalPromedio: conComida.length
        ? Math.round(promedio(conComida.map((d) => input.kcalPorDia.get(d)!)))
        : null,
      proteinaPromedio: conComida.length
        ? Math.round(promedio(conComida.map((d) => input.proteinaPorDia.get(d) ?? 0)))
        : null,
      minutosActividad: dias.reduce((a, d) => a + (input.minutosPorDia.get(d) ?? 0), 0),
      peso: pesos.length ? pesoPorFecha.get(pesos[pesos.length - 1])! : null,
      diasEnfermedad: dias.filter((d) => input.diasEnfermedad.has(d)).length,
      diasConAlcohol: dias.filter((d) => input.diasConAlcohol.has(d)).length,
    };
  });
}

function promedio(xs: number[]): number {
  return xs.reduce((a, b) => a + b, 0) / xs.length;
}

function desvio(xs: number[]): number {
  const m = promedio(xs);
  return Math.sqrt(promedio(xs.map((x) => (x - m) ** 2)));
}

function redondear(v: number, digitos: number): number {
  const f = 10 ** digitos;
  // `+ 0` convierte el −0 en 0: "−0,0 kg" es un número que no dice nada y
  // parece un error.
  return Math.round(v * f) / f + 0;
}

/**
 * Los días registrados por debajo del metabolismo basal de su objetivo
 * (`docs/panel-proximas-features.md` §6).
 *
 * Un día de 900 kcal casi nunca es un día de 900 kcal: es un día a medio
 * anotar, y baja el promedio de todo el período. No se excluye de ninguna
 * cuenta —eso sería la pantalla decidiendo qué datos son verdad—, pero se
 * dice. El basal es el de cada día (`goals.bmr_kcal`); un día sin basal no
 * cuenta.
 */
/** "Muy por debajo": a menos del 85 % del basal. Con un déficit indicado es
 *  normal comer cerca del basal, y un aviso por 50 kcal sería ruido. */
export const FRACCION_BASAL = 0.85;

export function diasBajoBasal(
  kcalPorDia: Map<string, number>,
  goals: Goal[],
): { dias: string[]; basal: number | null } {
  const dias: string[] = [];
  let basal: number | null = null;
  for (const [fecha, kcal] of [...kcalPorDia].sort((a, b) => a[0].localeCompare(b[0]))) {
    const b = goalForDay(goals, fecha)?.bmr_kcal ?? null;
    if (b && b > 0 && kcal < b * FRACCION_BASAL) {
      dias.push(fecha);
      basal = b;
    }
  }
  return { dias, basal };
}
