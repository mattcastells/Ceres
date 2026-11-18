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
  titulo,
}: {
  initial: CareReport | null;
  /** patient_id → nombre, de la lista que se está viendo. */
  nombres: Record<string, string>;
  plan: string | null;
  /** El título de la sección donde vive ("Pacientes · 13"): el botón va en su
   *  misma fila, a la derecha, y el análisis aparece debajo cuando lo hay. */
  titulo: React.ReactNode;
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

  const hayAlgo = !permitido || generando || !!error || !!c;

  return (
    <>
      <div className="section-title-row">
        <h2>{titulo}</h2>
        <div className="ai-action">
          {report && !generando && <span className="caption tnum">{fechaHora(report.created_at)}</span>}
          <button
            type="button"
            className="button--ai"
            onClick={generar}
            disabled={generando || !permitido}
          >
            <Destello />
            {generando ? 'Analizando…' : report ? 'Volver a analizar' : 'Analizar con IA'}
          </button>
        </div>
      </div>

      {hayAlgo && (
        <div className="card team-ai-card">
          {!permitido && (
            <p className="caption" style={{ margin: 0 }}>
              El análisis del equipo con IA es parte del plan Pro.
            </p>
          )}
          {generando && (
            <div>
              <AiProgress
                etapas={['Leyendo el tablero del equipo', 'Buscando a quién priorizar', 'Redactando']}
              />
            </div>
          )}
          {error && (
            <p className="form-error" role="alert" style={{ margin: 0 }}>
              {error}
            </p>
          )}

          {c && !generando && (
            <div className="ai-text">
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
      )}
    </>
  );
}

/** La estrellita de "esto usa IA", la misma idea que en la app. */
function Destello() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinejoin="round">
      <path d="M11 3.5l1.8 4.9 4.9 1.8-4.9 1.8L11 16.9l-1.8-4.9-4.9-1.8 4.9-1.8z" />
      <path d="M18.5 14.5l.8 2.1 2.1.8-2.1.8-.8 2.1-.8-2.1-2.1-.8 2.1-.8z" />
    </svg>
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
