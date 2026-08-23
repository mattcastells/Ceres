'use client';

import { useState } from 'react';
import { fechaCorta } from '@/lib/format';
import { ejeLindo, useChartWidth } from '@/lib/chart';

export type Point = { date: string; value: number };

/**
 * Barras por día, una sola serie, **solo de los días con registro**.
 *
 * Deliberadamente genérico y de una serie: agua, sueño, actividad y cada macro
 * usan este mismo componente. Una sola serie no necesita paleta categórica ni
 * leyenda —el título la nombra— y así ninguno de estos gráficos depende de
 * distinguir dos colores de marca, que es donde la paleta de la app no llega.
 *
 * **El eje X son los días registrados, uno al lado del otro, y no el
 * calendario.** Con el período de noventa días de alguien que empezó hace
 * treinta, un eje calendario era dos tercios de gráfico en blanco y las barras
 * apretadas en la punta derecha. Cada barra ocupa un lugar y el globito dice de
 * qué fecha es; los extremos del eje son el primer y el último día con datos.
 *
 * El día sin registro no se dibuja, ni siquiera en cero: cero diría que comió
 * cero, que no es lo que pasó. Quién dejó de registrar y cuándo lo cuenta el
 * calendario del día a día, que es el lugar donde los huecos se ven.
 *
 * Las bandas de contexto —enfermedad, alcohol— le agregan su día al eje aunque
 * ese día no tenga barra: un día de enfermedad sin actividad es justo el que
 * hay que poder explicar, y si no tuviera lugar en el eje la banda no se vería.
 *
 * Las barras nacen en cero. En una magnitud, un eje truncado convierte 1.900
 * contra 2.100 en el doble.
 */
export function BarChart({
  points,
  unit,
  color = 'var(--chart-intake)',
  target,
  targetLabel,
  decimals = 0,
  height = 150,
  sickDays = [],
  drinkDays = [],
}: {
  points: Point[];
  unit: string;
  /** Fechas marcadas como enfermedad. Ver `docs/contexto-diario.md`. */
  sickDays?: string[];
  /** Fechas con algún consumo de alcohol. */
  drinkDays?: string[];
  color?: string;
  target?: number | null;
  targetLabel?: string;
  /** Cuántos decimales mostrar.
   *
   *  Es un número y no una función de formato a propósito: este componente es
   *  un Client Component y quien lo usa es un Server Component, así que **una
   *  función no puede cruzar esa frontera** — React no la puede serializar y la
   *  página muere con "Functions cannot be passed directly to Client
   *  Components". Un número viaja; el formateo se hace de este lado. */
  decimals?: number;
  height?: number;
}) {
  const [hover, setHover] = useState<number | null>(null);
  const [box, ancho] = useChartWidth();

  const fmt = (v: number) =>
    decimals === 0
      ? String(Math.round(v))
      : v.toFixed(decimals).replace('.', ',');

  // El eje se escribe sin los decimales que no aportan: con `decimals = 1` las
  // rayas del sueño salían "0,0 · 5,0 · 10,0", que es ruido en una escala de
  // horas enteras. El globito sí los mantiene, porque ahí el dato es exacto.
  const fmtEje = (v: number) => (Number.isInteger(v) ? String(v) : fmt(v));

  // El ancho lo manda la caja: dibujar siempre en 720 y estirar con CSS
  // escalaba también las etiquetas del eje.
  const W = Math.max(ancho, 240);
  // Las bandas de contexto viven **abajo del eje**, así que necesitan lugar
  // propio: sin sumarlo, la de alcohol se dibujaba encima de la fecha del
  // extremo izquierdo. Se suma al alto y no se le resta al área de las barras,
  // porque achicar el gráfico para agregar una banda de 3 px sería pagar caro.
  const bandas = (sickDays.length ? 1 : 0) + (drinkDays.length ? 1 : 0);
  const H = height + bandas * 5;
  const PAD = { top: 10, right: 10, bottom: 20 + bandas * 5, left: 40 };
  const innerW = W - PAD.left - PAD.right;
  const innerH = H - PAD.top - PAD.bottom;

  // Menos rayas en un gráfico bajo: cinco etiquetas en 120 px de alto se tocan.
  const { max, ticks } = ejeLindo(
    Math.max(...points.map((p) => p.value), target ?? 0),
    innerH < 140 ? 3 : 5,
  );

  // Los lugares del eje: cada día con barra y cada día con banda, en orden.
  const lugares = [
    ...new Set([...points.map((p) => p.date), ...sickDays, ...drinkDays]),
  ].sort();
  const indice = new Map(lugares.map((d, i) => [d, i]));
  const inicio = lugares[0] ?? '';
  const fin = lugares[lugares.length - 1] ?? inicio;

  const step = innerW / Math.max(lugares.length, 1);
  // 2 px de aire, un techo de 56 —con 7 días son cinco barras repartiéndose mil
  // píxeles— y un piso de 1,2 para que un año de registro diario siga dibujando
  // una línea por día en vez de nada.
  const barW = Math.min(Math.max(step - 2, 1.2), 56);
  const x = (fecha: string) =>
    PAD.left + (indice.get(fecha) ?? 0) * step + (step - barW) / 2;
  const y = (v: number) => PAD.top + innerH - (v / max) * innerH;

  const point = hover === null ? null : points[hover];

  return (
    <div className="scroll-x chart" ref={box} style={{ position: 'relative' }}>
      {points.length === 0 ? (
        <p className="muted" style={{ margin: 0 }}>
          Sin registros en este período.
        </p>
      ) : (
        <svg
          viewBox={`0 0 ${W} ${H}`}
          width={W}
          height={H}
          style={{ display: 'block' }}
          role="img"
          aria-label={`Valores por día registrado en ${unit}, del ${fechaCorta(inicio)} al ${fechaCorta(fin)}`}
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
                {fmtEje(v)}
              </text>
            </g>
          ))}

          {/* ── El contexto, debajo de las barras ──────────────────────────
              Va como una banda de 3 px al pie del gráfico y **no** como color
              de la barra: teñir la barra cambiaría lo que la barra mide, y un
              día de enfermedad con 20 minutos de caminata sigue siendo 20
              minutos. Abajo, la marca dice "acá pasó algo" sin tocar el dato.

              Debajo del eje y no encima: un día de enfermedad **sin** actividad
              no tiene barra, y una marca superpuesta a una barra inexistente no
              se vería — que es justo el día que hay que poder explicar. */}
          {sickDays.map((f) => (
            <rect
              key={`sick-${f}`}
              x={x(f)}
              y={PAD.top + innerH + 2}
              width={barW}
              height={3}
              rx={1.5}
              fill="var(--caution)"
            >
              <title>{`${fechaCorta(f)} · día de enfermedad`}</title>
            </rect>
          ))}
          {drinkDays.map((f) => (
            <rect
              key={`drink-${f}`}
              x={x(f)}
              y={PAD.top + innerH + (sickDays.length ? 7 : 2)}
              width={barW}
              height={3}
              rx={1.5}
              fill="var(--info)"
            >
              <title>{`${fechaCorta(f)} · con alcohol`}</title>
            </rect>
          ))}

          {points.map((p, i) => (
            <rect
              key={p.date}
              className="bar"
              x={x(p.date)}
              y={y(p.value)}
              width={barW}
              height={Math.max(innerH - (y(p.value) - PAD.top), 0)}
              rx={Math.min(3, barW / 2)}
              fill={color}
              opacity={hover === null || hover === i ? 1 : 0.45}
            />
          ))}

          {target != null && target > 0 && (
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
              {/* La raya con su nombre: sin la etiqueta hay que ir a leer la
                  bajada de la sección para saber qué representa, y la bajada
                  queda arriba y fuera de la vista al scrollear. */}
              {targetLabel && (
                <text
                  x={W - PAD.right}
                  y={y(target) - 6}
                  textAnchor="end"
                  fontSize="11"
                  fill="var(--text-muted)"
                  className="tnum"
                >
                  {targetLabel}
                </text>
              )}
            </>
          )}

          {/* Zonas de hover más anchas que las barras: con un año de registro
              diario una barra mide un píxel y medio y apuntarle sería una
              prueba de puntería, no una interacción. */}
          {points.map((p, i) => (
            <rect
              key={`zona-${p.date}`}
              x={x(p.date) + barW / 2 - Math.max(step, 8) / 2}
              y={PAD.top}
              width={Math.max(step, 8)}
              height={innerH}
              fill="transparent"
              onMouseEnter={() => setHover(i)}
            />
          ))}

          <text
            x={PAD.left}
            y={H - 5}
            fontSize="10.5"
            fill="var(--text-muted)"
            className="tnum"
          >
            {fechaCorta(inicio)}
          </text>
          {fin !== inicio && (
            <text
              x={W - PAD.right}
              y={H - 5}
              textAnchor="end"
              fontSize="10.5"
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
          <div className="caption">{fechaCorta(point.date)}</div>
          <div>
            {fmt(point.value)} {unit}
          </div>
          {target != null && target > 0 && (
            <div className="caption">
              {point.value >= target
                ? `${fmt(point.value - target)} por encima`
                : `${fmt(target - point.value)} por debajo`}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
