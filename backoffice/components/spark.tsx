/**
 * Una mini-serie sin ejes, para adentro de una tarjeta de número.
 *
 * Es la única excepción a la regla de "el SVG se dibuja al ancho real de la
 * caja" (`lib/chart.ts`): acá no hay texto que se deforme, así que un `viewBox`
 * fijo estirado con `preserveAspectRatio="none"` está bien, y evita un
 * `ResizeObserver` por tarjeta. Por lo mismo no lleva esquinas redondeadas —se
 * deformarían— ni puntos en la línea.
 *
 * No reemplaza a un gráfico: no se lee un valor de acá. Dice la forma —si sube,
 * si baja, si está salteado— al lado del número que sí se lee.
 */
export function Spark({
  values,
  kind = 'bars',
  color = 'var(--chart-intake)',
  height = 36,
}: {
  values: number[];
  kind?: 'bars' | 'line';
  color?: string;
  height?: number;
}) {
  const W = 100;
  const H = 100;

  if (values.length === 0) {
    return <div className="spark spark--vacio" style={{ height }} aria-hidden />;
  }

  if (kind === 'line') {
    const min = Math.min(...values);
    const max = Math.max(...values);
    const rango = max - min || 1;
    // Un 10 % de aire arriba y abajo para que el trazo no toque el borde.
    const y = (v: number) => H - ((v - min) / rango) * (H * 0.8) - H * 0.1;
    const pts =
      values.length === 1
        ? `0,${y(values[0])} ${W},${y(values[0])}`
        : values
            .map((v, i) => `${(i / (values.length - 1)) * W},${y(v)}`)
            .join(' ');
    return (
      <svg
        className="spark"
        viewBox={`0 0 ${W} ${H}`}
        preserveAspectRatio="none"
        width="100%"
        height={height}
        aria-hidden
      >
        <polyline
          points={pts}
          fill="none"
          stroke={color}
          strokeWidth="2"
          strokeLinejoin="round"
          strokeLinecap="round"
          vectorEffect="non-scaling-stroke"
        />
      </svg>
    );
  }

  const max = Math.max(...values, 1e-9);
  const n = values.length;
  const paso = W / n;
  // Un cuarto del paso de aire entre barras, con un piso para que un período
  // de un año siga dibujando barras y no un bloque.
  const aire = Math.min(paso * 0.25, 1.5);
  return (
    <svg
      className="spark"
      viewBox={`0 0 ${W} ${H}`}
      preserveAspectRatio="none"
      width="100%"
      height={height}
      aria-hidden
    >
      {values.map((v, i) => {
        const h = (v / max) * H;
        return (
          <rect
            key={i}
            x={i * paso + aire / 2}
            y={H - h}
            width={Math.max(paso - aire, 0.4)}
            height={h}
            fill={color}
          />
        );
      })}
    </svg>
  );
}
