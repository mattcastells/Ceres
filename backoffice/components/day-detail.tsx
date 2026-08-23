import {
  SLOT_LABEL,
  QUALITY_LABEL,
  type Activity,
  type AlcoholLog,
  type DayMarker,
  type Goal,
  type Meal,
  type SleepLog,
  type WaterLog,
} from '@/lib/queries';
import { hora, horas, miles, num } from '@/lib/format';
import { DayContext } from '@/components/day-context';
import { MealRow } from '@/components/meal-row';
import { SlotSplit } from '@/components/slot-split';
import { MacroSplit } from '@/components/macro-split';

const SLOT_ORDER = ['breakfast', 'lunch', 'dinner', 'snack'];

/** Los vasos que la app toma como meta del día; es el mismo 8 de "Llegó a 8
 *  vasos" en Hábitos. */
export const VASOS_META = 8;

/** Las horas contra las que se dibuja la barra del sueño. Es una referencia
 *  para leer la barra, no una meta clínica: por eso va como "de 8 h" y no como
 *  objetivo. */
export const HORAS_SUENO_REF = 8;

/**
 * Todo lo que se registró un día, junto.
 *
 * Es lo que viaja del servidor al calendario: una bolsa por día con registro,
 * y nada de los días vacíos. Los días se cuentan en el calendario, no acá.
 */
export type DayBundle = {
  date: string;
  meals: Meal[];
  activities: Activity[];
  water: WaterLog | null;
  sleep: SleepLog | null;
  markers: DayMarker[];
  alcohol: AlcoholLog[];
};

/**
 * Un día abierto: lo que comió, cómo se repartió, y el agua, el sueño y la
 * actividad alrededor.
 *
 * Es el contenido del modal del calendario y no sabe que está en un modal: no
 * tiene estado, recibe el día y lo dibuja. Las comidas van agrupadas por
 * momento y **en orden fijo** —desayuno, almuerzo, cena, snacks— y no por la
 * hora de cada una: así no hay que leer los títulos para saber dónde mirar. Un
 * momento sin nada se muestra igual, en gris: "no cenó" es información, y si la
 * fila desaparece se confunde con "no lo cargó".
 *
 * Los cuadros de reparto son los mismos de la pestaña Comidas, para un solo
 * día: el porcentaje por momento y los macros contra el objetivo. No hay un
 * gráfico de barras por hora: con cuatro comidas, cuatro filas con su nombre se
 * leen mejor que cuatro barras.
 */
export function DayDetail({
  dia,
  targetKcal,
  goal,
  photoUrls,
  shareMeals,
  sharePhotos,
  shareWellbeing,
}: {
  dia: DayBundle;
  targetKcal: number | null;
  goal: Goal | null;
  photoUrls: Record<string, string>;
  shareMeals: boolean;
  sharePhotos: boolean;
  shareWellbeing: boolean;
}) {
  const { meals, activities, water, sleep, markers, alcohol } = dia;

  const total = meals.reduce((a, m) => a + m.total_kcal, 0);
  const p = meals.reduce((a, m) => a + Number(m.total_protein_g), 0);
  const c = meals.reduce((a, m) => a + Number(m.total_carbs_g), 0);
  const g = meals.reduce((a, m) => a + Number(m.total_fat_g), 0);
  const diff = targetKcal ? total - targetKcal : null;
  const pctObjetivo = targetKcal ? Math.round((total / targetKcal) * 100) : null;

  const minutos = activities.reduce((a, x) => a + x.duration_minutes, 0);
  const kcalAct = activities.reduce((a, x) => a + (x.estimated_calories ?? 0), 0);

  return (
    <>
      <DayContext markers={markers} alcohol={alcohol} />

      {shareMeals && meals.length === 0 && (
        <p className="muted" style={{ margin: 0 }}>
          Sin comidas registradas este día.
        </p>
      )}

      {shareMeals && meals.length > 0 && (
        <>
          <div className="modal-totals">
            <Total label="Calorías" value={miles(total)} unit="kcal" />
            <Total label="Proteínas" value={num(p)} unit="g" />
            <Total label="Carbohidratos" value={num(c)} unit="g" />
            <Total label="Grasas" value={num(g)} unit="g" />
          </div>

          {/* La distancia al objetivo, como barra y como número. Sin verde de
              "bien": quedarse 700 kcal abajo no es un logro en una consulta, es
              sub-registro o una restricción. El único color es el ámbar de
              haberse pasado, el mismo del gráfico de calorías. */}
          {targetKcal !== null && targetKcal > 0 && diff !== null && (
            <div className="dd-target">
              <div className="split-track" aria-hidden>
                <div
                  className="split-fill"
                  style={{
                    width: `${Math.min(pctObjetivo ?? 0, 100)}%`,
                    background:
                      diff > 0 ? 'var(--chart-over)' : 'var(--chart-intake)',
                  }}
                />
              </div>
              <span
                className="caption tnum"
                style={diff > 0 ? { color: 'var(--caution)' } : undefined}
              >
                {pctObjetivo} % del objetivo ·{' '}
                {diff > 0 ? `+${miles(diff)}` : `−${miles(Math.abs(diff))}`} kcal
              </span>
            </div>
          )}

          <div className="dd-grid">
            <div>
              <div className="section-header dd-header">Por momento del día</div>
              <SlotSplit meals={meals} diasConComida={1} porDia={false} />
            </div>
            <div>
              <div className="section-header dd-header">Macros</div>
              <MacroSplit
                meals={meals}
                diasConComida={1}
                goal={goal}
                porDia={false}
              />
            </div>
          </div>

          <div>
            <div className="section-header dd-header">Comidas</div>
            {SLOT_ORDER.map((slot) => {
              const del = meals.filter((m) => m.slot === slot);
              return (
                <div className="slot" key={slot}>
                  <div className="slot-head">
                    <strong
                      style={{
                        fontWeight: 500,
                        color: del.length ? 'var(--text)' : 'var(--text-muted)',
                      }}
                    >
                      {SLOT_LABEL[slot]}
                    </strong>
                    <span className="tnum caption">
                      {del.length
                        ? `${miles(del.reduce((a, m) => a + m.total_kcal, 0))} kcal`
                        : 'Sin registro'}
                    </span>
                  </div>

                  {del.map((m) => (
                    <MealRow
                      key={m.id}
                      meal={m}
                      photoUrls={photoUrls}
                      sharePhotos={sharePhotos}
                    />
                  ))}
                </div>
              );
            })}
          </div>
        </>
      )}

      {shareWellbeing && (
        <div>
          <div className="section-header dd-header">Actividad, agua y sueño</div>
          <div className="dd-habitos">
            <div className="card dd-habito">
              <div className="caption">Actividad</div>
              {activities.length === 0 ? (
                <div className="dd-habito-value muted">Sin registro</div>
              ) : (
                <>
                  <div className="dd-habito-value tnum">
                    {miles(minutos)} <span className="muted">min</span>
                    {kcalAct > 0 && (
                      <span className="estimate dd-habito-kcal">
                        ≈ {miles(kcalAct)} kcal
                      </span>
                    )}
                  </div>
                  <ul className="dd-sesiones">
                    {activities.map((a) => (
                      <li key={a.id} className="caption tnum">
                        {hora(a.started_at)} · {a.duration_minutes} min
                        {a.estimated_calories !== null && (
                          <span className="estimate">
                            {' '}
                            · ≈ {a.estimated_calories} kcal
                          </span>
                        )}
                      </li>
                    ))}
                  </ul>
                </>
              )}
            </div>

            <div className="card dd-habito">
              <div className="caption">Agua</div>
              {!water ? (
                <div className="dd-habito-value muted">Sin registro</div>
              ) : (
                <>
                  <div className="dd-habito-value tnum">
                    {water.glasses}{' '}
                    <span className="muted">de {VASOS_META} vasos</span>
                  </div>
                  <div className="split-track" aria-hidden>
                    <div
                      className="split-fill"
                      style={{
                        width: `${Math.min((water.glasses / VASOS_META) * 100, 100)}%`,
                        background: 'var(--info)',
                      }}
                    />
                  </div>
                </>
              )}
            </div>

            <div className="card dd-habito">
              <div className="caption">Sueño</div>
              {!sleep ? (
                <div className="dd-habito-value muted">Sin registro</div>
              ) : (
                <>
                  <div className="dd-habito-value tnum">
                    {horas(sleep.minutes)}
                    <span className="muted">
                      {' '}
                      · {QUALITY_LABEL[sleep.quality ?? 'ok'] ?? ''}
                    </span>
                  </div>
                  <div className="split-track" aria-hidden>
                    <div
                      className="split-fill"
                      style={{
                        width: `${Math.min((sleep.minutes / (HORAS_SUENO_REF * 60)) * 100, 100)}%`,
                        background: 'var(--chart-weight)',
                      }}
                    />
                  </div>
                  <div className="caption">de {HORAS_SUENO_REF} h</div>
                </>
              )}
            </div>
          </div>
        </div>
      )}
    </>
  );
}

/** "4 comidas · 5 fotos" — la línea de abajo del título del día. */
export function resumenDelDia(
  dia: DayBundle,
  photoUrls: Record<string, string>,
  sharePhotos: boolean,
): string {
  const fotos = dia.meals.filter(
    (m) => sharePhotos && m.photo_path && photoUrls[m.photo_path],
  ).length;
  const partes = [
    dia.meals.length
      ? `${dia.meals.length} ${dia.meals.length === 1 ? 'comida' : 'comidas'}`
      : null,
    fotos ? `${fotos} ${fotos === 1 ? 'foto' : 'fotos'}` : null,
    dia.activities.length
      ? `${dia.activities.length} ${dia.activities.length === 1 ? 'sesión' : 'sesiones'}`
      : null,
  ].filter(Boolean);
  return partes.join(' · ');
}

function Total({
  label,
  value,
  unit,
}: {
  label: string;
  value: string;
  unit: string;
}) {
  return (
    <div>
      <div className="caption">{label}</div>
      <div className="tnum modal-total-value">
        {value}
        <span className="muted modal-total-unit">{unit}</span>
      </div>
    </div>
  );
}
