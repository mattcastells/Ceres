import { SLOT_LABEL, type Meal } from '@/lib/queries';
import { miles } from '@/lib/format';

const SLOT_ORDER = ['breakfast', 'lunch', 'dinner', 'snack'];

/**
 * Cómo se reparten las calorías entre los cuatro momentos del día.
 *
 * Es una pregunta que el gráfico de calorías por día no contesta: dos personas
 * con el mismo promedio comen distinto si una hace tres comidas y la otra pone
 * la mitad del día en la cena. Cuatro barras con su nombre al lado, una sola
 * tinta: no hay tres colores de marca que distinguir.
 *
 * Sirve para un período —promedio por día sobre los días con comidas— y para
 * un solo día, con `diasConComida = 1` y `porDia = false`, que es como lo usa
 * la ficha del día: ahí "kcal/día" sería decir dos veces lo mismo.
 */
export function SlotSplit({
  meals,
  diasConComida,
  porDia = true,
}: {
  meals: Meal[];
  diasConComida: number;
  /** Si el número de la derecha es un promedio diario o el total de ese día. */
  porDia?: boolean;
}) {
  const total = meals.reduce((a, m) => a + m.total_kcal, 0);

  if (!total || !diasConComida) {
    return (
      <div className="card">
        <p className="muted" style={{ margin: 0 }}>
          Sin comidas cargadas en este período.
        </p>
      </div>
    );
  }

  return (
    <div className="card">
      {SLOT_ORDER.map((slot) => {
        const kcal = meals
          .filter((m) => m.slot === slot)
          .reduce((a, m) => a + m.total_kcal, 0);
        const pct = Math.round((kcal / total) * 100);

        return (
          <div className="split-row" key={slot}>
            <span>{SLOT_LABEL[slot]}</span>
            <div className="split-track" aria-hidden>
              <div className="split-fill" style={{ width: `${pct}%` }} />
            </div>
            <span className="tnum caption">
              {pct} % · {miles(kcal / diasConComida)} {porDia ? 'kcal/día' : 'kcal'}
            </span>
          </div>
        );
      })}
    </div>
  );
}
