'use client';

import { useState } from 'react';
import { fechaCorta, fechaMedia, miles } from '@/lib/format';
import { ejeLindo, useChartWidth } from '@/lib/chart';
import { useAbrirDia } from '@/components/day-modal';

export type DayKcal = { date: string; kcal: number };

/**
 * Calorías por día contra el objetivo.
 *
 * Una sola serie de barras y una línea de referencia. **No** es un gráfico de
 * dos ejes: el objetivo está en las mismas kcal que las barras, así que
 * comparte la escala y se lee como lo que es, una raya que se cruza o no.
 *
 * Las barras nacen en el cero y no en el mínimo del rango: en una magnitud, un
 * eje truncado convierte 1.900 contra 2.100 en el doble.
 *
 * **El eje X son los días con comidas, uno al lado del otro.** Con el período
 * de noventa días de alguien que empezó hace treinta, un eje calendario era dos
 * tercios de gráfico en blanco y las barras apretadas en la punta derecha. Cada
 * barra ocupa un lugar y el globito dice de qué fecha es; los extremos del eje
 * son el primer y el último día con comidas. Los días sin registro no se
 * dibujan —una barra en cero diría que comió cero, que no es lo que pasó— y
 * quién dejó de registrar lo cuenta el calendario del día a día.
 *
 * El día que se pasó del objetivo va en otro tono. Es la única codificación por
 * color de la pantalla y se sostiene sola: el tono de "por encima" está sobre
 * la línea punteada y el de "por debajo" abajo, así que la posición dice lo
 * mismo que el color y no hace falta distinguirlos para leer el gráfico.
 *
 * Cada barra **se abre**: el clic va al mismo modal del día que usa el
 * calendario (`useAbrirDia`). El gráfico contesta "cuánto" y el modal "qué",
 * sin pasar por la pestaña del día a día.
 */
export function CaloriesChart({
  days,
  target,
}: {
  days: DayKcal[];
  target: number | null;
}) {
  const [hover, setHover] = useState<number | null>(null);
  const [box, ancho] = useChartWidth();
  const abrir = useAbrirDia();

  const W = Math.max(ancho, 240);
  const H = 240;
  const PAD = { top: 18, right: 12, bottom: 26, left: 46 };
  const innerW = W - PAD.left - PAD.right;
  const innerH = H - PAD.top - PAD.bottom;

  const { max, ticks } = ejeLindo(
    Math.max(...days.map((d) => d.kcal), target ?? 0),
    5,
  );
  const inicio = days[0]?.date ?? '';
  const fin = days[days.length - 1]?.date ?? inicio;

  const step = innerW / Math.max(days.length, 1);
  // 2 px de aire entre barras: sin el respiro, dos días seguidos se leen como
  // un bloque. Y un techo de 56: en el período de 7 días son cinco barras
  // repartiéndose mil píxeles, y sin el tope cada una queda de 190 px de ancho.
  const barW = Math.min(Math.max(step - 2, 1.5), 56);
  const x = (i: number) => PAD.left + i * step + (step - barW) / 2;

  const y = (v: number) => PAD.top + innerH - (v / max) * innerH;
  const point = hover === null ? null : days[hover];

  return (
    <div className="scroll-x chart" ref={box} style={{ position: 'relative' }}>
      {days.length === 0 ? (
        <p className="muted" style={{ margin: 0 }}>
          Sin comidas cargadas en este período.
        </p>
      ) : (
        <svg
          viewBox={`0 0 ${W} ${H}`}
          width={W}
          height={H}
          style={{ display: 'block' }}
          role="img"
          aria-label="Calorías consumidas por día registrado"
          onMouseLeave={() => setHover(null)}
        >
          {ticks.map((v) => (
            <g key={v}>
              <line
                x1={PAD.left}
                x2={W - PAD.right}
                y1={y(v)}
                y2={y(v)}
                stroke="var(--divider)"
                strokeWidth="1"
              />
              <text
                x={PAD.left - 7}
                y={y(v) + 4}
                textAnchor="end"
                fontSize="11"
                fill="var(--text-muted)"
                className="tnum"
              >
                {miles(v)}
              </text>
            </g>
          ))}

          {days.map((d, i) => {
            const pasado = target !== null && target > 0 && d.kcal > target;
            return (
              <rect
                key={d.date}
                className="bar"
                x={x(i)}
                y={y(d.kcal)}
                width={barW}
                height={Math.max(innerH - (y(d.kcal) - PAD.top), 0)}
                rx={Math.min(4, barW / 2)}
                fill={pasado ? 'var(--chart-over)' : 'var(--chart-intake)'}
                opacity={hover === null || hover === i ? 1 : 0.45}
              />
            );
          })}

          {/* Zonas de hover más anchas que las barras: con un año de registro
              diario una barra mide un píxel y medio. Son también el clic que
              abre el día, por lo mismo: a una barra finita no se le apunta. */}
          {days.map((d, i) => (
            <rect
              key={`zona-${d.date}`}
              x={x(i) + barW / 2 - Math.max(step, 8) / 2}
              y={PAD.top}
              width={Math.max(step, 8)}
              height={innerH}
              fill="transparent"
              style={abrir ? { cursor: 'pointer' } : undefined}
              onMouseEnter={() => setHover(i)}
              onClick={() => abrir?.(d.date)}
            />
          ))}

          {target !== null && target > 0 && (
            <>
              <line
                x1={PAD.left}
                x2={W - PAD.right}
                y1={y(target)}
                y2={y(target)}
                stroke="var(--chart-target)"
                strokeWidth="2"
                strokeDasharray="6 5"
              />
              <text
                x={W - PAD.right}
                y={y(target) - 7}
                textAnchor="end"
                fontSize="11"
                fill="var(--text-muted)"
                className="tnum"
              >
                objetivo {miles(target)}
              </text>
            </>
          )}

          <text
            x={PAD.left}
            y={H - 7}
            fontSize="11"
            fill="var(--text-muted)"
            className="tnum"
          >
            {fechaCorta(inicio)}
          </text>
          {fin !== inicio && (
            <text
              x={W - PAD.right}
              y={H - 7}
              textAnchor="end"
              fontSize="11"
              fill="var(--text-muted)"
              className="tnum"
            >
              {fechaCorta(fin)}
            </text>
          )}
        </svg>
      )}

      {point && (
        <div className="chart-tip tnum">
          <div className="caption">{fechaMedia(point.date)}</div>
          <div style={{ fontSize: 17 }}>{miles(point.kcal)} kcal</div>
          {target !== null && target > 0 && (
            <div className="caption">
              {point.kcal > target
                ? `${miles(point.kcal - target)} por encima`
                : `${miles(target - point.kcal)} por debajo`}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
