'use client';

import { useMemo, useState } from 'react';
import { browserClient } from '@/lib/supabase-browser';
import type { CareReport } from '@/lib/queries';
import {
  invokeCareReport,
  planPermiteInformes,
  type InformeConsulta,
  type MetricasPaciente,
} from '@/lib/care-report';
import { conSigno, dec, fechaCorta, fechaHora, miles } from '@/lib/format';
import { Kpi, KpiRow, Section } from '@/components/stat';
import { CaloriesChart } from '@/components/calories-chart';
import { AiProgress } from '@/components/ai-progress';

/**
 * El informe de consulta con IA: generarlo, y leer el último guardado.
 *
 * **Se lee el guardado antes de ofrecer uno nuevo.** Cada informe es una
 * llamada al modelo, entre 10 y 40 segundos y un lugar en la cuota del día; la
 * ficha trae el último de `care_reports` y esta pestaña lo muestra sin pedir
 * nada. "Generar de nuevo" es explícito.
 *
 * **Lo calculado y lo redactado van separados y rotulados.** Los números salen
 * de `care-report/metrics.ts` —código con test— y viajan en `content.metricas`;
 * el modelo solo redacta sobre ellos. Por eso los gráficos y las tarjetas de
 * abajo dicen "calculado sobre los registros" y el texto de arriba dice
 * "redactado con IA, revisalo": un promedio que dice el modelo puede estar mal
 * y nadie se entera, y la profesional tiene que poder distinguir de un vistazo
 * cuál de las dos cosas está leyendo. El texto va con el ámbar con el que la
 * app marca toda estimación de IA.
 */
export function AiReport({
  patientId,
  patientName,
  initial,
  plan,
}: {
  patientId: string;
  patientName: string | null;
  initial: CareReport | null;
  plan: string | null;
}) {
  const db = useMemo(() => browserClient(), []);
  const [report, setReport] = useState(initial);
  const [generando, setGenerando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const permitido = planPermiteInformes(plan);

  async function generar() {
    setGenerando(true);
    setError(null);
    const res = await invokeCareReport<{ report: CareReport }>(db, {
      kind: 'professional',
      patientId,
    });
    setGenerando(false);
    if (!res.ok) return setError(res.message);
    setReport(res.data.report);
  }

  const contenido = report ? leerInforme(report.content) : null;

  return (
    <>
      <Section
        title="Informe para la consulta"
        hint="Las dos últimas semanas cerradas, hasta ayer. Los números los calcula Ceres sobre los registros; el texto lo redacta la IA a partir de esos números."
      >
        <div className="card ai-toolbar">
          <div style={{ minWidth: 0 }}>
            {report ? (
              <>
                <div>
                  Informe del {fechaCorta(report.period_from)} al {fechaCorta(report.period_to)}
                </div>
                <div className="caption tnum">generado el {fechaHora(report.created_at)}</div>
              </>
            ) : (
              <>
                <div>Todavía no generaste un informe de {patientName || 'esta persona'}.</div>
                <div className="caption">
                  Resume las últimas dos semanas, marca lo que conviene mirar y
                  propone preguntas para la consulta.
                </div>
              </>
            )}
          </div>
          <button
            type="button"
            className={report ? undefined : 'button--primary'}
            onClick={generar}
            disabled={generando || !permitido}
          >
            {generando ? 'Generando…' : report ? 'Generar de nuevo' : 'Generar informe'}
          </button>
        </div>

        {!permitido && (
          <p className="caption" style={{ marginTop: 'var(--s3)' }}>
            Los informes con IA son parte del plan Pro.
          </p>
        )}
        {generando && (
          <div className="card" style={{ marginTop: 'var(--s4)' }}>
            <AiProgress
              etapas={[
                'Leyendo los registros compartidos',
                'Calculando los números del período',
                'Redactando el informe',
                'Revisando el texto',
              ]}
            />
          </div>
        )}
        {error && (
          <p className="form-error" role="alert" style={{ marginTop: 'var(--s4)' }}>
            {error}
          </p>
        )}
        {report && !contenido && (
          <p className="caption" style={{ marginTop: 'var(--s4)' }}>
            Este informe se guardó con un formato que esta pantalla no reconoce.
            Generá uno nuevo.
          </p>
        )}
      </Section>

      {contenido && <Informe c={contenido} />}
    </>
  );
}

function Informe({ c }: { c: InformeConsulta }) {
  const m = c.metricas ?? {};
  return (
    <>
      <Section title="Lo que dice el informe">
        <div className="card ai-text">
          <EtiquetaIA />
          <p className="ai-resumen">{c.resumen}</p>

          {c.alertas.length > 0 && (
            <ul className="ai-alertas">
              {c.alertas.map((a, i) => (
                <li key={i} className={`ai-alerta ai-alerta--${a.nivel}`}>
                  <span className="caption">{a.nivel === 'atencion' ? 'Para mirar' : 'Dato'}</span>
                  <span>{a.texto}</span>
                </li>
              ))}
            </ul>
          )}
        </div>

        <div className="grid grid--auto grid--parejo" style={{ marginTop: 'var(--s4)' }}>
          <div className="card ai-text">
            <h3>Puntos clave</h3>
            <EtiquetaIA />
            {c.puntosClave.length ? (
              <ul className="ai-lista">
                {c.puntosClave.map((p, i) => <li key={i}>{p}</li>)}
              </ul>
            ) : (
              <p className="muted">Sin puntos clave.</p>
            )}
          </div>
          <div className="card ai-text">
            <h3>Preguntas para la consulta</h3>
            <EtiquetaIA />
            {c.preguntas.length ? (
              <ol className="ai-lista">
                {c.preguntas.map((p, i) => <li key={i}>{p}</li>)}
              </ol>
            ) : (
              <p className="muted">Sin preguntas propuestas.</p>
            )}
          </div>
        </div>

        {(c.balance || m.balanceEstimado || m.peso) && (
          <div className="card" style={{ marginTop: 'var(--s4)' }}>
            <h3>Balance</h3>
            {c.balance && (
              <div className="ai-text">
                <EtiquetaIA />
                <p style={{ margin: 'var(--s2) 0 0' }}>{c.balance}</p>
              </div>
            )}
            <BalanceCalculado m={m} />
          </div>
        )}
      </Section>

      <Numeros m={m} />
    </>
  );
}

function EtiquetaIA() {
  return <span className="chip chip--warn ai-tag">Redactado con IA · revisalo</span>;
}

function EtiquetaCalculado() {
  return <span className="chip chip--on">Calculado sobre los registros</span>;
}

function BalanceCalculado({ m }: { m: MetricasPaciente }) {
  const b = m.balanceEstimado;
  const p = m.peso;
  if (!b && !p) return null;
  return (
    <div style={{ marginTop: 'var(--s4)' }}>
      <EtiquetaCalculado />
      <div className="kpi-grid" style={{ marginTop: 'var(--s3)' }}>
        {b && (
          <Dato
            label={b.deficitPromedioDiario >= 0 ? 'Déficit registrado' : 'Superávit registrado'}
            valor={`≈ ${miles(Math.abs(b.deficitPromedioDiario))} kcal/día`}
            sub={`gasto estimado ${miles(b.gastoEstimadoDiario)} · ${b.sobreDias} días con registro`}
            estimado
          />
        )}
        {b && (
          <Dato
            label="Cambio esperado"
            valor={`${conSigno(b.cambioEsperadoKg)} kg`}
            sub="sumando el déficit de los días registrados"
            estimado
          />
        )}
        {p && (
          <Dato
            label="Cambio medido"
            valor={`${conSigno(p.cambio)} kg`}
            sub={`${dec(p.inicial)} → ${dec(p.final)} kg · ${fechaCorta(p.fechaInicial)} a ${fechaCorta(p.fechaFinal)}`}
          />
        )}
      </div>
    </div>
  );
}

function Dato({
  label,
  valor,
  sub,
  estimado,
}: {
  label: string;
  valor: string;
  sub: string;
  estimado?: boolean;
}) {
  return (
    <div>
      <div className="caption">{label}</div>
      <div className={`tnum${estimado ? ' estimate' : ''}`} style={{ fontSize: 21, lineHeight: 1.2 }}>
        {valor}
      </div>
      <div className="caption">{sub}</div>
    </div>
  );
}

/** Los números del informe, como datos y no como texto. */
function Numeros({ m }: { m: MetricasPaciente }) {
  const cal = m.calorias;
  const comparte = m.categoriasCompartidas;
  const dias = m.periodo?.dias ?? null;

  return (
    <Section
      title="Los números del informe"
      hint="Los mismos con los que se redactó el texto de arriba, calculados por Ceres sobre lo que la persona registró."
    >
      <div style={{ marginBottom: 'var(--s4)' }}>
        <EtiquetaCalculado />
      </div>

      <KpiRow>
        <Kpi
          label="Días con registro"
          value={String(m.diasConRegistro ?? 0)}
          unit={dias ? `de ${dias}` : undefined}
          sub={m.comidasPorDia ? `${String(m.comidasPorDia).replace('.', ',')} comidas por día registrado` : ' '}
        />
        <Kpi
          label="Calorías por día"
          value={cal?.promedio ? miles(cal.promedio) : '—'}
          unit="kcal"
          sub={
            cal?.objetivo
              ? `objetivo ${miles(cal.objetivo)}${
                  cal.diasDentroDelObjetivo !== null
                    ? ` · ${cal.diasDentroDelObjetivo} días a ±10 %`
                    : ''
                }`
              : 'sin objetivo cargado'
          }
        />
        <Kpi
          label="Semana y fin de semana"
          value={cal?.promedioDiasDeSemana ? miles(cal.promedioDiasDeSemana) : '—'}
          unit="kcal"
          sub={
            cal?.promedioFinDeSemana
              ? `entre semana · fin de semana ${miles(cal.promedioFinDeSemana)}`
              : 'entre semana · sin registros de fin de semana'
          }
        />
        <Kpi
          label="Horarios"
          value={m.horarios?.primeraComidaPromedio ?? '—'}
          sub={
            m.horarios?.ultimaComidaPromedio
              ? `primera comida · la última, ${m.horarios.ultimaComidaPromedio}`
              : 'primera comida, en promedio'
          }
        />
      </KpiRow>

      {(m.macros || m.porcentajeCargadoConIA != null || m.actividad || m.sueno || m.agua) && (
        <KpiRow>
          {m.macros && (
            <Kpi
              label="Proteínas por día"
              value={miles(m.macros.proteinaPromedioG)}
              unit="g"
              sub={
                m.macros.objetivoProteinaG
                  ? `objetivo ${miles(m.macros.objetivoProteinaG)} g · carbohidratos ${miles(m.macros.carbohidratosPromedioG)} · grasas ${miles(m.macros.grasasPromedioG)}`
                  : `carbohidratos ${miles(m.macros.carbohidratosPromedioG)} g · grasas ${miles(m.macros.grasasPromedioG)} g`
              }
            />
          )}
          {m.porcentajeCargadoConIA != null && (
            <Kpi
              label="Cargado con IA"
              value={String(m.porcentajeCargadoConIA)}
              unit="%"
              sub="de las comidas, por foto o por texto: son estimaciones"
              tone="estimate"
            />
          )}
          {comparte?.wellbeing !== false && m.actividad && (
            <Kpi
              label="Actividad"
              value={miles(m.actividad.minutos)}
              unit="min"
              sub={`${m.actividad.sesiones} ${m.actividad.sesiones === 1 ? 'sesión' : 'sesiones'}${
                m.actividad.tipos.length ? ` · ${m.actividad.tipos.map((t) => t.tipo).join(', ')}` : ''
              }`}
            />
          )}
          {(m.sueno || m.agua) && (
            <Kpi
              label="Sueño y agua"
              value={m.sueno ? `${String(m.sueno.promedioHoras).replace('.', ',')} h` : '—'}
              sub={[
                m.sueno ? `${m.sueno.noches} noches` : null,
                m.agua ? `${String(m.agua.promedioVasos).replace('.', ',')} vasos por día` : null,
              ]
                .filter(Boolean)
                .join(' · ')}
            />
          )}
        </KpiRow>
      )}

      {cal && cal.porDia.length > 0 && (
        <div className="card" style={{ marginTop: 'var(--s4)' }}>
          <h3>Calorías por día</h3>
          <p className="caption" style={{ margin: 'var(--s1) 0 var(--s3)' }}>
            Los días con registro del informe. La línea punteada es el objetivo.
          </p>
          <CaloriesChart
            days={cal.porDia.map((d) => ({ date: d.fecha, kcal: d.kcal }))}
            target={cal.objetivo}
          />
        </div>
      )}

      {m.alimentosFrecuentes && m.alimentosFrecuentes.length > 0 && (
        <div className="card scroll-x" style={{ marginTop: 'var(--s4)' }}>
          <h3>Los alimentos que más se repiten</h3>
          <table className="tabla-datos" style={{ marginTop: 'var(--s3)' }}>
            <thead>
              <tr>
                <th>Alimento</th>
                <th className="num">Veces</th>
                <th className="num">kcal en el período</th>
              </tr>
            </thead>
            <tbody>
              {m.alimentosFrecuentes.map((a) => (
                <tr key={a.nombre}>
                  <td>{a.nombre.charAt(0).toUpperCase() + a.nombre.slice(1)}</td>
                  <td className="num tnum">{a.veces}</td>
                  <td className="num tnum">{miles(a.kcal)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {m.contexto && m.contexto.length > 0 && (
        <div className="card" style={{ marginTop: 'var(--s4)' }}>
          <h3>Contexto del período</h3>
          <ul className="ai-lista">
            {m.contexto.map((x, i) => (
              <li key={i}>
                <span className="tnum">{fechaCorta(x.fecha)}</span> · {x.tipo}
                {x.nota ? ` — ${x.nota}` : ''}
              </li>
            ))}
          </ul>
        </div>
      )}
    </Section>
  );
}

/** El `content` de `care_reports` es `jsonb`: se valida la forma antes de
 *  dibujarlo, para que un informe viejo o a medio guardar diga "no lo
 *  reconozco" en vez de romper la pestaña entera. */
function leerInforme(raw: unknown): InformeConsulta | null {
  if (!raw || typeof raw !== 'object') return null;
  const o = raw as Record<string, unknown>;
  if (typeof o.resumen !== 'string') return null;
  const strs = (v: unknown) => (Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : []);
  return {
    resumen: o.resumen,
    puntosClave: strs(o.puntosClave),
    preguntas: strs(o.preguntas),
    balance: typeof o.balance === 'string' ? o.balance : '',
    alertas: Array.isArray(o.alertas)
      ? o.alertas
          .map((a) => a as { nivel?: unknown; texto?: unknown })
          .filter((a) => typeof a?.texto === 'string')
          .map((a) => ({
            nivel: a.nivel === 'atencion' ? ('atencion' as const) : ('info' as const),
            texto: a.texto as string,
          }))
      : [],
    metricas: (o.metricas && typeof o.metricas === 'object' ? o.metricas : {}) as MetricasPaciente,
  };
}
