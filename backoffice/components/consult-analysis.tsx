import { SLOT_LABEL } from '@/lib/queries';
import { conSigno, dec, fechaCorta, hhmm, horas, miles } from '@/lib/format';
import type { Balance, AlimentoFrecuente, Horarios, Semana } from '@/lib/analysis';

/**
 * Las cuatro piezas del análisis de consulta, como vistas sin estado.
 *
 * Las cuentas están en `lib/analysis.ts` (con test); acá solo se dibujan. No
 * hay `'use client'`: son HTML que llega armado del servidor, sin hidratación,
 * y la tira de horarios se dibuja con `div`s posicionados en porcentaje y no
 * con un SVG, así no hace falta medir la caja (`useChartWidth`) para que el
 * texto no se deforme.
 *
 * Ninguna califica: no hay verde de "bien" ni rojo de "mal". La brecha del
 * balance es una hipótesis para chequear, y se dice con palabras.
 */

/* ── 1 · Balance energético contra peso real ──────────────────────────── */

export function BalanceCard({ b, shareBody }: { b: Balance; shareBody: boolean }) {
  if (b.estado === 'sin-gasto') {
    return (
      <div className="card">
        <p className="muted" style={{ margin: 0 }}>
          Su objetivo no tiene gasto estimado (TDEE): no hay contra qué comparar.
        </p>
      </div>
    );
  }

  if (b.estado === 'pocos-dias') {
    return (
      <div className="card">
        <p className="muted" style={{ margin: 0 }}>
          {b.dias} {b.dias === 1 ? 'día registrado' : 'días registrados'} de
          los 7 que hacen falta.
        </p>
      </div>
    );
  }

  // Positivo = comió de menos. Se dice como "de más / de menos" contra lo que
  // gasta, que es como se habla en consulta, y no como déficit o superávit.
  const deficit = b.deficitPromedio;
  const linea = (
    <div className="balance-row">
      <span className="caption">Come por día</span>
      <span className="tnum balance-value estimate">
        ≈ {miles(Math.abs(deficit))} kcal {deficit >= 0 ? 'de menos' : 'de más'}
      </span>
      <span className="caption">
        {b.estado === 'ok' ? `gasta ≈ ${miles(b.gastoPromedio)} kcal · ` : ''}
        {b.dias} días registrados
      </span>
    </div>
  );

  if (b.estado === 'sin-peso') {
    return (
      <div className="card">
        {linea}
        <p className="caption" style={{ margin: 'var(--s4) 0 0' }}>
          {shareBody ? 'Faltan dos pesajes separados por una semana.' : 'El peso no está compartido.'}
        </p>
      </div>
    );
  }

  return (
    <div className="card">
      {linea}
      <div className="balance-row">
        <span className="caption">Según lo que comió</span>
        <span className="tnum balance-value estimate">{conSigno(b.esperadoKg)} kg</span>
        <span className="caption">en {b.diasEntrePesajes} días</span>
      </div>
      <div className="balance-row">
        <span className="caption">Según la balanza</span>
        <span className="tnum balance-value">{conSigno(b.medidoKg)} kg</span>
        <span className="caption">
          {b.lectura === 'coincide'
            ? 'casi lo mismo'
            : `${dec(Math.abs(b.brechaKg))} kg de diferencia`}
        </span>
      </div>

      <p style={{ margin: 'var(--s5) 0 0' }}>{LECTURA[b.lectura]}</p>
    </div>
  );
}

const LECTURA: Record<'coincide' | 'menos-de-lo-esperado' | 'mas-de-lo-esperado', string> = {
  coincide: 'Cierra: lo que registra explica lo que pesa.',
  'menos-de-lo-esperado':
    'No cierra: pesa más de lo que explica el registro. Lo más común es comida sin anotar, sobre todo los fines de semana.',
  'mas-de-lo-esperado':
    'No cierra: bajó más de lo que explica el registro. Al principio suele ser agua; si sigue, gasta más de lo estimado.',
};

/* ── 3 · Los alimentos que se repiten ─────────────────────────────────── */

export function FrecuentesTable({ items }: { items: AlimentoFrecuente[] }) {
  if (items.length === 0) {
    return (
      <div className="card">
        <p className="muted" style={{ margin: 0 }}>
          Ningún alimento aparece más de una vez en el período.
        </p>
      </div>
    );
  }
  return (
    <div className="card scroll-x">
      <table className="tabla-datos">
        <thead>
          <tr>
            <th>Alimento</th>
            <th className="num">Veces</th>
            <th className="num">Días</th>
            <th className="num">kcal en el período</th>
            <th className="num">De las kcal</th>
            <th>Cuándo</th>
          </tr>
        </thead>
        <tbody>
          {items.map((a) => (
            <tr key={a.nombre}>
              <td>{a.nombre}</td>
              <td className="num tnum">{a.veces}</td>
              <td className="num tnum">{a.dias}</td>
              <td className="num tnum">{miles(a.kcal)}</td>
              <td className="num tnum">
                {/* La pista es la parte de las kcal: es la columna que dice
                    "el 18 % del mes viene del pan", que es lo que se busca. */}
                <span className="pct-cell">
                  <span className="split-track" aria-hidden>
                    <span
                      className="split-fill"
                      style={{ width: `${Math.min(a.pctKcal, 100)}%`, display: 'block' }}
                    />
                  </span>
                  {a.pctKcal} %
                </span>
              </td>
              <td className="caption">
                {a.momentos.map((s) => SLOT_LABEL[s] ?? s).join(', ')}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/* ── 2 · Horarios y ventana de alimentación ───────────────────────────── */

/** Cuántos días se dibujan como tira: los últimos. Más de tres semanas de
 *  tiras ya no se comparan de un vistazo, y el promedio de arriba es de todo
 *  el período. */
const TIRAS = 21;

export function HorariosStrip({ h }: { h: Horarios }) {
  if (h.dias.length === 0 || h.primeraPromedio === null) {
    return (
      <div className="card">
        <p className="muted" style={{ margin: 0 }}>
          Sin comidas con hora en el período.
        </p>
      </div>
    );
  }

  const dias = h.dias.slice(-TIRAS).reverse();
  // El eje va de las 6 a las 24 salvo que alguien coma antes o después: así
  // dos fichas se comparan con la misma regla en el caso común, y la cena de
  // la 01:00 igual entra.
  const minimo = Math.min(6 * 60, Math.floor(Math.min(...dias.map((d) => d.primera)) / 60) * 60);
  const maximo = Math.max(24 * 60, Math.ceil(Math.max(...dias.map((d) => d.ultima)) / 60) * 60);
  const pos = (min: number) => `${((min - minimo) / (maximo - minimo)) * 100}%`;
  const marcas: number[] = [];
  for (let m = minimo; m <= maximo; m += 6 * 60) marcas.push(m);

  return (
    <div className="card">
      <div className="kpi-grid" style={{ marginBottom: 'var(--s5)' }}>
        <Dato label="Primera comida" valor={hhmm(h.primeraPromedio)} sub="en promedio" />
        <Dato
          label="Última comida"
          valor={h.ultimaPromedio === null ? '—' : hhmm(h.ultimaPromedio)}
          sub="en promedio"
        />
        <Dato
          label="Ventana"
          valor={h.ventanaPromedio === null ? '—' : horas(h.ventanaPromedio)}
          sub="de la primera a la última, en días con dos o más"
        />
        <Dato
          label="Cuánto varía el arranque"
          valor={h.variacionPrimera === null ? '—' : `± ${h.variacionPrimera < 60 ? `${h.variacionPrimera} min` : horas(h.variacionPrimera)}`}
          sub="desvío de la hora de la primera comida"
        />
      </div>

      <div className="hstrip" role="img" aria-label="Horario de cada comida, por día">
        <div className="hstrip-row hstrip-axis" aria-hidden>
          <span />
          <div className="hstrip-track hstrip-track--axis">
            {marcas.map((m) => (
              <span key={m} className="caption tnum hstrip-tick" style={{ left: pos(m) }}>
                {hhmm(m % (24 * 60))}
              </span>
            ))}
          </div>
        </div>
        {dias.map((d) => (
          <div key={d.fecha} className="hstrip-row">
            <span className="caption tnum">{fechaCorta(d.fecha)}</span>
            <div className="hstrip-track">
              {d.comidas.length >= 2 && (
                <span
                  className="hstrip-span"
                  style={{ left: pos(d.primera), width: `calc(${pos(d.ultima)} - ${pos(d.primera)})` }}
                />
              )}
              {d.comidas.map((c, i) => (
                <span
                  key={i}
                  className="hstrip-dot"
                  style={{ left: pos(c.min) }}
                  title={`${SLOT_LABEL[c.slot] ?? c.slot} · ${hhmm(c.min % (24 * 60))}`}
                />
              ))}
            </div>
          </div>
        ))}
      </div>
      {h.dias.length > TIRAS && (
        <p className="caption" style={{ margin: 'var(--s3) 0 0' }}>
          Se dibujan los últimos {TIRAS} días con comidas; los promedios son de
          los {h.dias.length}.
        </p>
      )}
    </div>
  );
}

function Dato({ label, valor, sub }: { label: string; valor: string; sub: string }) {
  return (
    <div>
      <div className="caption">{label}</div>
      <div className="tnum" style={{ fontSize: 21, lineHeight: 1.2 }}>{valor}</div>
      <div className="caption">{sub}</div>
    </div>
  );
}

/* ── 4 · Semana contra semana ─────────────────────────────────────────── */

export function SemanasTable({
  semanas,
  shareMeals,
  shareBody,
  shareWellbeing,
}: {
  semanas: Semana[];
  shareMeals: boolean;
  shareBody: boolean;
  shareWellbeing: boolean;
}) {
  // De la más nueva a la más vieja, como el calendario: la semana que se
  // discute en la consulta es la de arriba.
  const filas = [...semanas].reverse();
  return (
    <div className="card scroll-x">
      <table className="tabla-datos">
        <thead>
          <tr>
            <th>Semana</th>
            {shareMeals && <th className="num">Días con comidas</th>}
            {shareMeals && <th className="num">kcal por día</th>}
            {shareMeals && <th className="num">Proteínas por día</th>}
            {shareWellbeing && <th className="num">Actividad</th>}
            {shareBody && <th className="num">Peso al cierre</th>}
            {shareWellbeing && <th>Contexto</th>}
          </tr>
        </thead>
        <tbody>
          {filas.map((s) => (
            <tr key={s.desde}>
              <td>
                <span className="tnum">
                  {fechaCorta(s.desde)} – {fechaCorta(s.hasta)}
                </span>
                {s.incompleta && (
                  <div className="caption">
                    incompleta · {s.diasEnVentana} {s.diasEnVentana === 1 ? 'día' : 'días'}
                  </div>
                )}
              </td>
              {shareMeals && (
                <td className="num tnum">
                  {s.diasConComidas} <span className="muted">de {s.diasEnVentana}</span>
                </td>
              )}
              {shareMeals && (
                <td className="num tnum">{s.kcalPromedio === null ? '—' : miles(s.kcalPromedio)}</td>
              )}
              {shareMeals && (
                <td className="num tnum">
                  {s.proteinaPromedio === null ? '—' : `${miles(s.proteinaPromedio)} g`}
                </td>
              )}
              {shareWellbeing && (
                <td className="num tnum">{s.minutosActividad ? `${miles(s.minutosActividad)} min` : '—'}</td>
              )}
              {shareBody && (
                <td className="num tnum">{s.peso === null ? '—' : `${dec(s.peso)} kg`}</td>
              )}
              {shareWellbeing && (
                <td className="caption">
                  {[
                    s.diasEnfermedad
                      ? `${s.diasEnfermedad} ${s.diasEnfermedad === 1 ? 'día' : 'días'} de enfermedad`
                      : null,
                    s.diasConAlcohol
                      ? `${s.diasConAlcohol} con alcohol`
                      : null,
                  ]
                    .filter(Boolean)
                    .join(' · ') || '—'}
                </td>
              )}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
