/**
 * El número de arriba de una sección, con su unidad y su aclaración.
 *
 * No es un gráfico y no debería serlo: "promedio de 1.940 kcal" es un dato que
 * se lee de una vez, y dibujarlo como barra de una sola barra sería decorar un
 * número. La guía de visualización llama a esto una stat tile.
 */
export function Stat({
  label,
  value,
  unit,
  caption,
  tone,
}: {
  label: string;
  value: string;
  unit?: string;
  caption?: string;
  tone?: 'estimate' | 'muted';
}) {
  return (
    <div className="card stat">
      <div className="caption stat-label">{label}</div>
      <div
        className="tnum stat-value"
        style={tone === 'estimate' ? { color: 'var(--caution)' } : undefined}
      >
        {value}
        {unit && <span className="muted stat-unit">{unit}</span>}
      </div>
      {/* El pie va siempre, aunque esté vacío: sin él las fichas de una fila
          tienen alturas distintas y los números dejan de estar alineados, que
          es justo para lo que sirve ponerlos en fila. */}
      <div className="caption stat-caption">{caption ?? ' '}</div>
    </div>
  );
}

/**
 * La tarjeta del tablero: un número grande, una línea que lo pone en contexto
 * y, abajo, una mini-visual —una pista contra el objetivo, una sparkline, los
 * puntos de los últimos días—.
 *
 * Es la evolución de `Stat` para el Resumen. Dieciséis fichas de un número
 * cada una eran una pared: había que leerlas todas para armarse la imagen.
 * Acá son menos tarjetas y cada una dice tres cosas, y la visual es la que
 * contesta "¿y cómo viene?" sin un gráfico entero.
 */
export function Kpi({
  label,
  value,
  unit,
  sub,
  tone,
  children,
}: {
  label: string;
  value: string;
  unit?: string;
  /** La línea de contexto, debajo del número. */
  sub?: string;
  tone?: 'estimate';
  /** La mini-visual. Opcional: sin ella la tarjeta es número y línea. */
  children?: React.ReactNode;
}) {
  return (
    <div className="card kpi">
      <div className="caption">{label}</div>
      <div
        className="tnum kpi-value"
        style={tone === 'estimate' ? { color: 'var(--caution)' } : undefined}
      >
        {value}
        {unit && <span className="kpi-unit">{unit}</span>}
      </div>
      <div className="caption kpi-sub">{sub ?? ' '}</div>
      {children && <div className="kpi-visual">{children}</div>}
    </div>
  );
}

/** Las tarjetas del tablero en fila: cuatro por línea donde entran. */
export function KpiRow({ children }: { children: React.ReactNode }) {
  return <div className="kpi-grid">{children}</div>;
}

/** Las fichas en fila, hasta cuatro por línea.
 *
 *  El tope de cuatro es lo que evita la huérfana: con `auto-fit` y un mínimo
 *  chico, en 1080 px entraban seis y la séptima quedaba sola abajo, a un sexto
 *  de ancho. Cuatro por fila reparte siete en 4 + 3, que se lee como una
 *  grilla y no como un sobrante. */
export function StatRow({ children }: { children: React.ReactNode }) {
  return <div className="stats">{children}</div>;
}

/** Un encabezado de sección con su bajada, para que cada bloque diga qué es. */
export function Section({
  title,
  hint,
  children,
}: {
  title: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <section className="section">
      <h2>{title}</h2>
      {hint && (
        <p className="caption" style={{ marginTop: 2, marginBottom: 'var(--s4)' }}>
          {hint}
        </p>
      )}
      {!hint && <div style={{ height: 'var(--s4)' }} />}
      {children}
    </section>
  );
}
