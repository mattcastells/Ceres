import type { Goal, Meal } from '@/lib/queries';
import { miles } from '@/lib/format';

/**
 * Promedio de proteínas, carbohidratos y grasas contra el objetivo.
 *
 * Es la pregunta que sigue a "cuántas calorías": dos días de 1.900 kcal son
 * planes distintos si uno tiene 60 g de proteína y el otro 130. Estaba en la
 * base —`goals` guarda los tres objetivos— y no se mostraba en ninguna parte;
 * de los tres macros solo las proteínas tenían gráfico.
 *
 * **Columnas con su nombre y una sola tinta**, no tres colores de marca. Los
 * tres colores de macros de la paleta (`#9184d9`, `#7fa8d9`, `#d9b46a`) están a
 * ΔE 9,6 entre proteínas y carbohidratos, cuando el piso para distinguir series
 * es 15: un gráfico que dependa de separarlos no se puede leer. Acá cada fila
 * dice qué es, así que no hay nada que distinguir por color.
 *
 * El promedio va sobre los días **con comidas cargadas** y no sobre el período,
 * por lo mismo que en el reparto por momento: dividir por los días en blanco
 * diría que come menos, cuando lo que pasó es que no registró.
 *
 * Con `diasConComida = 1` y `porDia = false` es el mismo cuadro para un solo
 * día, que es como lo usa la ficha del día.
 */
export function MacroSplit({
  meals,
  diasConComida,
  goal,
  porDia = true,
}: {
  meals: Meal[];
  diasConComida: number;
  goal: Goal | null;
  /** Si los gramos son un promedio diario o el total de ese día. */
  porDia?: boolean;
}) {
  if (!diasConComida || meals.length === 0) {
    return (
      <div className="card">
        <p className="muted" style={{ margin: 0 }}>
          Sin comidas cargadas en este período.
        </p>
      </div>
    );
  }

  const suma = (f: (m: Meal) => number) =>
    meals.reduce((a, m) => a + Number(f(m)), 0) / diasConComida;

  const macros = [
    {
      key: 'protein',
      label: 'Proteínas',
      gramos: suma((m) => m.total_protein_g),
      objetivo: goal?.protein_g ?? null,
      kcalPorGramo: 4,
    },
    {
      key: 'carbs',
      label: 'Carbohidratos',
      gramos: suma((m) => m.total_carbs_g),
      objetivo: goal?.carbs_g ?? null,
      kcalPorGramo: 4,
    },
    {
      key: 'fat',
      label: 'Grasas',
      gramos: suma((m) => m.total_fat_g),
      objetivo: goal?.fat_g ?? null,
      kcalPorGramo: 9,
    },
  ];

  const kcalTotales = macros.reduce((a, m) => a + m.gramos * m.kcalPorGramo, 0);

  return (
    <div className="card">
      {macros.map((m) => {
        const pctKcal = kcalTotales
          ? Math.round(((m.gramos * m.kcalPorGramo) / kcalTotales) * 100)
          : 0;
        // La barra se mide contra el objetivo, así que el 100 % es la marca y
        // no el máximo de la serie: "le falta un cuarto de la proteína" se ve
        // sin leer los números. Con el objetivo sin cargar no hay contra qué
        // medir y la barra no se dibuja: una barra sin referencia sería una
        // decoración con forma de dato.
        const cumple = m.objetivo ? (m.gramos / m.objetivo) * 100 : null;

        return (
          <div className="macro-row" key={m.key}>
            <span className="macro-name">{m.label}</span>

            <div className="macro-bar">
              {cumple !== null ? (
                <div className="split-track">
                  <div
                    className="split-fill"
                    style={{ width: `${Math.min(cumple, 100)}%` }}
                  />
                </div>
              ) : (
                <span className="caption muted">sin objetivo cargado</span>
              )}
            </div>

            <span className="macro-value tnum">
              {miles(m.gramos)}
              <span className="muted">{porDia ? ' g/día' : ' g'}</span>
            </span>

            {/* El aviso de que se pasó va acá y no al lado de la barra: ahí era
                un hermano flex y le comía el ancho justo al macro que más
                interesa mirar, así que la barra más larga se dibujaba más
                corta que las otras. */}
            <span className="macro-goal caption tnum">
              {m.objetivo ? `de ${miles(m.objetivo)} g · ` : ''}
              {pctKcal} % de las kcal
              {cumple !== null && cumple > 105 && (
                <span className="macro-over">
                  {' · '}
                  {Math.round(cumple)} % del objetivo
                </span>
              )}
            </span>
          </div>
        );
      })}
    </div>
  );
}
