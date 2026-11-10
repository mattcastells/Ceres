import type { Goal } from './queries.ts';

/**
 * El objetivo de cada día, no el último para todo el período.
 *
 * La app nunca edita un objetivo: lo cierra (`ends_on = ayer`) y abre otro. Así
 * que en un período de 90 días puede haber dos o tres, y el panel usaba el más
 * nuevo para todos: el día de julio se comparaba contra la meta de octubre, y
 * "días dentro del objetivo" mezclaba metas distintas sin decirlo.
 *
 * La base garantiza que dos objetivos no se pisan (`goals_no_overlap`), así que
 * para un día hay uno o ninguno. Si por un dato raro hubiera dos, gana el que
 * empezó más tarde, que es el criterio de la app.
 */
export function goalForDay(goals: Goal[], date: string): Goal | null {
  let best: Goal | null = null;
  for (const g of goals) {
    const desde = g.starts_on ?? '0000-01-01';
    const hasta = g.ends_on ?? '9999-12-31';
    if (desde <= date && date <= hasta) {
      if (!best || (best.starts_on ?? '') < desde) best = g;
    }
  }
  return best;
}

/**
 * El objetivo con el que se rotula la ficha: el vigente al final del período,
 * o si ese día no tenía ninguno, el último que hubo.
 *
 * Es el de la cabecera, el de la pestaña de macros y el de la línea del gráfico
 * cuando no cambió; la comparación día por día usa `goalForDay`.
 */
export function currentGoal(goals: Goal[], to: string): Goal | null {
  const vigente = goalForDay(goals, to);
  if (vigente) return vigente;
  const anteriores = goals
    .filter((g) => (g.starts_on ?? '') <= to)
    .sort((a, b) => (a.starts_on ?? '').localeCompare(b.starts_on ?? ''));
  return anteriores[anteriores.length - 1] ?? null;
}

/** El objetivo de calorías de cada fecha, en un mapa. `null` = ese día no
 *  tenía objetivo, que no es lo mismo que cero. */
export function targetsByDay(
  goals: Goal[],
  dates: string[],
): Map<string, number | null> {
  const out = new Map<string, number | null>();
  for (const d of dates) {
    const t = goalForDay(goals, d)?.base_calorie_target ?? null;
    out.set(d, t && t > 0 ? t : null);
  }
  return out;
}
