'use client';

import Link from 'next/link';
import { useMemo, useState } from 'react';
import { browserClient } from '@/lib/supabase-browser';
import type { CareReport } from '@/lib/queries';
import { invokeCareReport, planPermiteInformes, type InformeEquipo } from '@/lib/care-report';
import { fechaHora } from '@/lib/format';
import { AiProgress } from '@/components/ai-progress';

/**
 * "Analizar el equipo con IA": a quién contactar primero y qué se repite en el
 * equipo.
 *
 * Igual que el informe de un paciente, se muestra el último guardado y se
 * regenera solo a pedido: abrir la lista no paga un informe. Los números con
 * los que se redacta son los de `care_overview()` —los mismos de las fichas de
 * abajo—, así que el texto y las fichas no pueden discutir.
 *
 * Las prioridades nombran pacientes por id y la función ya descarta los que no
 * vinieron en los datos; acá además se descarta el que no está en la lista que
 * se ve (un acceso revocado desde que se generó el informe), en vez de mostrar
 * un enlace a una ficha que va a dar 404.
 */
export function TeamReport({
  initial,
  nombres,
  plan,
}: {
  initial: CareReport | null;
  /** patient_id → nombre, de la lista que se está viendo. */
  nombres: Record<string, string>;
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
    const res = await invokeCareReport<{ report: CareReport }>(db, { kind: 'team' });
    setGenerando(false);
    if (!res.ok) return setError(res.message);
    setReport(res.data.report);
  }

  const c = report ? leer(report.content) : null;
  const prioridades = c ? c.prioridades.filter((p) => nombres[p.patientId]) : [];

  return (
    <section className="section team-ai">
      <div className="card">
        <div className="ai-toolbar ai-toolbar--plain">
          <div style={{ minWidth: 0 }}>
            <h2>El equipo, con IA</h2>
            <p className="caption" style={{ margin: 'var(--s1) 0 0' }}>
              {report
                ? `Análisis del ${fechaHora(report.created_at)}, sobre los mismos números de las fichas de abajo.`
                : 'A quién conviene escribirle primero y qué se repite en el equipo, sobre los números de las fichas de abajo.'}
            </p>
          </div>
          <button
            type="button"
            className={report ? undefined : 'button--primary'}
            onClick={generar}
            disabled={generando || !permitido}
          >
            {generando ? 'Analizando…' : report ? 'Analizar de nuevo' : 'Analizar el equipo con IA'}
          </button>
        </div>

        {!permitido && (
          <p className="caption" style={{ margin: 'var(--s3) 0 0' }}>
            El análisis del equipo con IA es parte del plan Pro.
          </p>
        )}
        {generando && (
          <div style={{ marginTop: 'var(--s4)' }}>
            <AiProgress
              etapas={['Leyendo el tablero del equipo', 'Buscando a quién priorizar', 'Redactando']}
            />
          </div>
        )}
        {error && (
          <p className="form-error" role="alert" style={{ marginTop: 'var(--s4)' }}>
            {error}
          </p>
        )}

        {c && (
          <div className="ai-text" style={{ marginTop: 'var(--s5)' }}>
            <span className="chip chip--warn ai-tag">Redactado con IA · revisalo</span>
            <p className="ai-resumen">{c.resumen}</p>

            {prioridades.length > 0 && (
              <>
                <h3 style={{ marginTop: 'var(--s5)' }}>Para contactar primero</h3>
                <ol className="team-prioridades">
                  {prioridades.map((p) => (
                    <li key={p.patientId}>
                      <Link href={`/paciente/${p.patientId}`}>{nombres[p.patientId]}</Link>
                      <span>{p.motivo}</span>
                      {p.accion && <span className="caption">{p.accion}</span>}
                    </li>
                  ))}
                </ol>
              </>
            )}

            {c.observaciones.length > 0 && (
              <>
                <h3 style={{ marginTop: 'var(--s5)' }}>En el equipo</h3>
                <ul className="ai-lista">
                  {c.observaciones.map((o, i) => (
                    <li key={i}>{o}</li>
                  ))}
                </ul>
              </>
            )}
          </div>
        )}
      </div>
    </section>
  );
}

function leer(raw: unknown): InformeEquipo | null {
  if (!raw || typeof raw !== 'object') return null;
  const o = raw as Record<string, unknown>;
  if (typeof o.resumen !== 'string') return null;
  return {
    resumen: o.resumen,
    prioridades: Array.isArray(o.prioridades)
      ? o.prioridades
          .map((p) => p as Record<string, unknown>)
          .filter((p) => typeof p?.patientId === 'string' && typeof p?.motivo === 'string')
          .map((p) => ({
            patientId: p.patientId as string,
            motivo: p.motivo as string,
            accion: typeof p.accion === 'string' ? p.accion : '',
          }))
      : [],
    observaciones: Array.isArray(o.observaciones)
      ? o.observaciones.filter((x): x is string => typeof x === 'string')
      : [],
  };
}
