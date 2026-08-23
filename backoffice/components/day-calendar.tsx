'use client';

import { useMemo } from 'react';
import { SLOT_LABEL } from '@/lib/queries';
import { diaDeSemana, fechaLarga, miles } from '@/lib/format';
import { useAbrirDia } from '@/components/day-modal';
import type { DayBundle } from '@/components/day-detail';

const LETRAS = ['Lu', 'Ma', 'Mi', 'Ju', 'Vi', 'Sá', 'Do'];
const SLOT_ORDER = ['breakfast', 'lunch', 'dinner', 'snack'];

/**
 * El día a día como calendario: un mes por bloque, una celda por día.
 *
 * Antes era una lista de filas, una por día con registro, cada una con su
 * `<details>`. Servía para leer de corrido pero no para **ubicarse**: "¿qué
 * pasó el fin de semana del 15?" era bajar contando, y un hueco de tres días no
 * se veía porque los días sin registro no tenían fila. En un calendario el
 * hueco es una celda con el número solo entre dos llenas, y el sábado está
 * debajo del sábado anterior.
 *
 * Los meses van **del más reciente al más viejo**: la ficha se abre para mirar
 * lo último, y con un año de período el mes de hoy tiene que estar arriba y no
 * doce pantallas más abajo. Adentro de cada mes el orden es el del almanaque.
 *
 * Solo se dibujan las semanas que tocan el período —de una semana de período
 * salen una o dos filas, no un mes entero con siete celdas prendidas—, y los
 * días anteriores al primer registro de la cuenta ni aparecen: el calendario
 * arranca donde arrancó la persona. Ver `lib/tracking.ts`.
 *
 * Cada celda con registro dice lo que se pregunta primero sin abrirla: las
 * calorías, qué momentos cargó —las cuatro rayitas— y el agua, el sueño y la
 * actividad en una línea. El detalle se abre con `useAbrirDia`: el modal no es
 * de este componente sino de la ficha (`components/day-modal.tsx`), porque el
 * gráfico de calorías también abre días.
 */
export function DayCalendar({
  desde,
  hasta,
  hoy,
  dias,
  targetKcal,
  shareMeals,
  shareWellbeing,
}: {
  /** El primer día que se dibuja: el del período, o el primero de la persona. */
  desde: string;
  hasta: string;
  hoy: string;
  /** Solo los días con algo registrado. El resto del calendario sale de `desde`
   *  y `hasta`. */
  dias: DayBundle[];
  targetKcal: number | null;
  shareMeals: boolean;
  shareWellbeing: boolean;
}) {
  const porFecha = useMemo(
    () => new Map(dias.map((d) => [d.date, d])),
    [dias],
  );
  const meses = useMemo(() => mesesEntre(desde, hasta), [desde, hasta]);
  const abrir = useAbrirDia();

  if (dias.length === 0) {
    return (
      <div className="card">
        <p className="muted" style={{ margin: 0 }}>
          Sin registros en este período.
        </p>
      </div>
    );
  }

  return (
    <>
      {meses.map((mes) => (
        <div className="dcal-month" key={mes.clave}>
          <h3 className="dcal-title">{mes.titulo}</h3>
          <div className="dcal-dow" aria-hidden>
            {LETRAS.map((l) => (
              <span key={l}>{l}</span>
            ))}
          </div>
          <div className="dcal-grid">
            {mes.semanas.flat().map((fecha, i) => {
              if (fecha === null || fecha < desde || fecha > hasta) {
                return (
                  <span
                    key={`off-${mes.clave}-${i}`}
                    className="dcal-cell dcal-cell--off"
                    aria-hidden
                  />
                );
              }
              const d = porFecha.get(fecha);
              if (!d) {
                return (
                  <span
                    key={fecha}
                    className="dcal-cell dcal-cell--empty"
                    data-today={fecha === hoy ? '1' : undefined}
                    title={`${fechaLarga(fecha)} · sin registro`}
                  >
                    <span className="dcal-num tnum">{Number(fecha.slice(8))}</span>
                  </span>
                );
              }
              return (
                <Celda
                  key={fecha}
                  dia={d}
                  hoy={hoy}
                  targetKcal={targetKcal}
                  shareMeals={shareMeals}
                  shareWellbeing={shareWellbeing}
                  onOpen={() => abrir?.(fecha)}
                />
              );
            })}
          </div>
        </div>
      ))}
    </>
  );
}

/**
 * Un día con registro, cerrado.
 *
 * Lo que dice sin abrirse: el número del día, las calorías —en ámbar si se pasó
 * del objetivo, el mismo ámbar del gráfico—, las cuatro rayitas de los momentos
 * y una línea con lo de alrededor. Un punto arriba a la derecha si el día tuvo
 * enfermedad o alcohol: es lo que explica al resto, y tiene que verse antes de
 * abrir. Ver `docs/contexto-diario.md`.
 */
function Celda({
  dia,
  hoy,
  targetKcal,
  shareMeals,
  shareWellbeing,
  onOpen,
}: {
  dia: DayBundle;
  hoy: string;
  targetKcal: number | null;
  shareMeals: boolean;
  shareWellbeing: boolean;
  onOpen: () => void;
}) {
  const kcal = dia.meals.reduce((a, m) => a + m.total_kcal, 0);
  const pasado = targetKcal !== null && targetKcal > 0 && kcal > targetKcal;
  const enfermo = dia.markers.some((m) => m.kind === 'sick');
  const alcohol = dia.alcohol.length > 0;
  const minutos = dia.activities.reduce((a, x) => a + x.duration_minutes, 0);

  const alrededor = [
    minutos ? `${minutos} min` : null,
    dia.water ? `${dia.water.glasses} vasos` : null,
    dia.sleep ? horasCortas(dia.sleep.minutes) : null,
  ]
    .filter(Boolean)
    .join(' · ');

  const etiqueta = [
    fechaLarga(dia.date),
    shareMeals && dia.meals.length ? `${miles(kcal)} kcal` : null,
    alrededor || null,
    enfermo ? 'día de enfermedad' : null,
    alcohol ? 'con alcohol' : null,
  ]
    .filter(Boolean)
    .join(', ');

  return (
    <button
      type="button"
      className="dcal-cell dcal-cell--on"
      data-today={dia.date === hoy ? '1' : undefined}
      onClick={onOpen}
      aria-label={etiqueta}
    >
      <span className="dcal-top">
        <span className="dcal-num tnum">{Number(dia.date.slice(8))}</span>
        {(enfermo || alcohol) && (
          <span className="dcal-marks" aria-hidden>
            {enfermo && (
              <i className="dcal-mark dcal-mark--sick" title="Día de enfermedad" />
            )}
            {alcohol && (
              <i className="dcal-mark dcal-mark--drink" title="Con alcohol" />
            )}
          </span>
        )}
      </span>

      {shareMeals &&
        (dia.meals.length ? (
          <span className={`dcal-kcal tnum${pasado ? ' dcal-kcal--over' : ''}`}>
            {miles(kcal)}
            <small> kcal</small>
          </span>
        ) : (
          <span className="dcal-kcal dcal-kcal--none muted">
            <span className="dcal-long">sin comidas</span>
            <span className="dcal-short" aria-hidden>
              —
            </span>
          </span>
        ))}

      {shareMeals && (
        <span className="dcal-slots" aria-hidden>
          {SLOT_ORDER.map((slot) => (
            <i
              key={slot}
              data-on={dia.meals.some((m) => m.slot === slot) ? '1' : '0'}
              title={SLOT_LABEL[slot]}
            />
          ))}
        </span>
      )}

      {shareWellbeing && alrededor && (
        <span className="dcal-sub caption tnum">{alrededor}</span>
      )}
    </button>
  );
}

type Mes = {
  clave: string;
  titulo: string;
  /** Filas de siete: la fecha, o `null` fuera del mes. Solo las semanas que
   *  tocan el período. */
  semanas: (string | null)[][];
};

/** Los meses del período, del más reciente al más viejo. */
function mesesEntre(desde: string, hasta: string): Mes[] {
  const out: Mes[] = [];
  let [y, m] = desde.split('-').map(Number);
  const [hy, hm] = hasta.split('-').map(Number);
  while (y < hy || (y === hy && m <= hm)) {
    out.push(mes(y, m, desde, hasta));
    m += 1;
    if (m > 12) {
      m = 1;
      y += 1;
    }
  }
  return out.reverse();
}

function mes(y: number, m: number, desde: string, hasta: string): Mes {
  const clave = `${y}-${pad(m)}`;
  // El día 0 del mes siguiente es el último de este.
  const diasDelMes = new Date(y, m, 0).getDate();
  const celdas: (string | null)[] = Array.from(
    { length: diaDeSemana(`${clave}-01`) },
    () => null,
  );
  for (let d = 1; d <= diasDelMes; d++) celdas.push(`${clave}-${pad(d)}`);
  while (celdas.length % 7 !== 0) celdas.push(null);

  const semanas: (string | null)[][] = [];
  for (let i = 0; i < celdas.length; i += 7) semanas.push(celdas.slice(i, i + 7));

  const texto = new Date(y, m - 1, 1).toLocaleDateString('es-AR', {
    month: 'long',
    year: 'numeric',
  });

  return {
    clave,
    titulo: texto.charAt(0).toUpperCase() + texto.slice(1),
    semanas: semanas.filter((s) =>
      s.some((f) => f !== null && f >= desde && f <= hasta),
    ),
  };
}

/** "7 h 58" en vez de "7 h 58 min": en una celda de calendario cada letra
 *  cuenta, y con la "h" adelante los dos dígitos de atrás no se leen como otra
 *  cosa que minutos. */
function horasCortas(minutos: number): string {
  const h = Math.floor(minutos / 60);
  const m = minutos % 60;
  return m === 0 ? `${h} h` : `${h} h ${pad(m)}`;
}

function pad(n: number): string {
  return String(n).padStart(2, '0');
}
