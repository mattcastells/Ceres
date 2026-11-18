import { MainNav } from '@/components/main-nav';
import { OrgPatientsTable } from '@/components/org-manage';
import { conSigno, miles } from '@/lib/format';
import { resumirConsultorio, type OrgPatientRow, type ResumenConsultorio } from '@/lib/org';

/** Una fila de `public.my_organization()` (migración 49): una por miembro, con
 *  los datos de la organización repetidos en cada una. */
export type OrgRow = {
  org_id: string;
  org_name: string;
  ai_monthly_quota: number;
  ai_used_month: number;
  member_id: string;
  member_name: string | null;
  member_role: 'owner' | 'admin' | 'professional' | string;
  member_patients: number;
};

/**
 * La portada: la organización de una sola profesional, su dueña (desde el
 * 15/11/2026; antes admitía varias, con reasignación entre ellas).
 *
 * Los números de todos sus pacientes, el análisis con IA, la tabla de
 * pacientes y el fondo de IA del mes.
 *
 * Es una función pura de las filas, como `PatientView`, para poder mirarla
 * con datos de ejemplo (`app/preview/organizacion`).
 */
export function OrgView({
  rows,
  viewerId,
  pacientes = null,
  hoy,
  plan = null,
  analisis = null,
}: {
  /** `effective_plan()`: lo usa el modal de Dar de alta (el código). */
  plan?: string | null;
  rows: OrgRow[];
  viewerId: string | null;
  /** `org_patients()`: `null` para quien no administra (o si falló). */
  pacientes?: OrgPatientRow[] | null;
  hoy: string;
  /** El análisis de los pacientes con IA (`TeamReport`), que vive acá desde
   *  el 15/11/2026. Llega armado para que esta vista siga siendo pura, y
   *  reemplaza al título "Pacientes · N": el botón va en esa misma fila. */
  analisis?: React.ReactNode;
}) {
  const org = rows[0];
  const usado = org.ai_used_month;
  const cupo = org.ai_monthly_quota;
  const pct = cupo > 0 ? Math.round((usado / cupo) * 100) : 0;
  const totalPacientes = rows.reduce((a, r) => a + r.member_patients, 0);

  const resumen = pacientes ? resumirConsultorio(pacientes, hoy) : null;

  return (
    <>
      <header className="topbar">
        <div className="topbar-inner topbar-inner--plain">
          <div className="topbar-id">
            <div style={{ minWidth: 0 }}>
              <h1>{org.org_name}</h1>
              <p className="topbar-sub caption">
                {totalPacientes} {totalPacientes === 1 ? 'paciente' : 'pacientes'}
              </p>
            </div>
            <MainNav actual="organizacion" plan={plan} />
          </div>
        </div>
      </header>

      <main className="page">
        {resumen && resumen.pacientes > 0 && <Numeros r={resumen} />}

        {pacientes ? (
          <section className="section">
            {/* El análisis con IA trae su propio título, con el botón en la misma fila. */}
            {analisis ?? <h2 style={{ marginBottom: 'var(--s4)' }}>Pacientes · {pacientes.length}</h2>}
            <OrgPatientsTable pacientes={pacientes} hoy={hoy} />
          </section>
        ) : (
          analisis && <section className="section">{analisis}</section>
        )}

        <section className="section">
          <h2 style={{ marginBottom: 'var(--s4)' }}>Recursos de IA</h2>
          <div className="card">
            <div className="row" style={{ justifyContent: 'space-between', alignItems: 'baseline' }}>
              <span className="tnum" style={{ fontSize: 25 }}>
                {miles(usado)}
                <span className="muted" style={{ fontSize: 14 }}> de {miles(cupo)}</span>
              </span>
              <span className="caption tnum">
                {cupo > usado ? `quedan ${miles(cupo - usado)}` : 'se usó todo el fondo'}
              </span>
            </div>
            <div className="split-track usage-track" aria-hidden>
              <div
                className="split-fill"
                style={{
                  width: `${Math.min(pct, 100)}%`,
                  // El ámbar de siempre para "pasó el tope", y no un rojo: que
                  // se acabe el fondo es para saberlo, no una emergencia.
                  background: pct >= 100 ? 'var(--chart-over)' : 'var(--chart-intake)',
                }}
              />
            </div>
            <p className="caption tnum" style={{ margin: 'var(--s2) 0 0' }}>
              {pct} % usado
            </p>
          </div>
        </section>
      </main>
    </>
  );
}

/**
 * Los datos de la comunidad del consultorio: agregados, nunca el detalle de
 * nadie. Cuatro números y una pista, como el resumen de la ficha.
 */
function Numeros({ r }: { r: ResumenConsultorio }) {
  const conPeso = r.peso.bajan + r.peso.estables + r.peso.suben;
  const tramo = (n: number) => (conPeso ? `${(n / conPeso) * 100}%` : '0%');
  const pctActivos = r.pacientes ? Math.round((r.activos / r.pacientes) * 100) : 0;
  const pctAdherencia = r.adherencia !== null ? Math.round((r.adherencia / 7) * 100) : null;

  return (
    <section className="section" style={{ marginTop: 'var(--s5)' }}>
      <h2 style={{ marginBottom: 'var(--s4)' }}>Estadísticas del equipo</h2>
      <div className="org-kpis">
        <div className="card org-kpi">
          <span className="caption">Activos</span>
          <span className="tnum org-kpi-value">
            {r.activos}
            <span className="muted" style={{ fontSize: 14 }}> de {r.pacientes}</span>
          </span>
          <div className="split-track" aria-hidden>
            <div className="split-fill" style={{ width: `${pctActivos}%`, background: 'var(--chart-intake)' }} />
          </div>
          <span className="caption">registraron comidas en los últimos 3 días</span>
        </div>

        <div className="card org-kpi" style={{ animationDelay: '40ms' }}>
          <span className="caption">Constancia</span>
          <span className="tnum org-kpi-value">
            {r.adherencia === null ? '—' : r.adherencia.toLocaleString('es-AR')}
            <span className="muted" style={{ fontSize: 14 }}> días de 7</span>
          </span>
          {pctAdherencia !== null && (
            <div className="split-track" aria-hidden>
              <div className="split-fill" style={{ width: `${pctAdherencia}%`, background: 'var(--chart-intake)' }} />
            </div>
          )}
          <span className="caption">con comidas, en promedio</span>
        </div>

        <div className="card org-kpi" style={{ animationDelay: '80ms' }}>
          <span className="caption">Dentro del objetivo</span>
          <span className="tnum org-kpi-value">
            {r.dentroObjetivo.si}
            <span className="muted" style={{ fontSize: 14 }}> de {r.dentroObjetivo.de}</span>
          </span>
          {r.dentroObjetivo.de > 0 && (
            <div className="split-track" aria-hidden>
              <div
                className="split-fill"
                style={{
                  width: `${Math.round((r.dentroObjetivo.si / r.dentroObjetivo.de) * 100)}%`,
                  background: 'var(--chart-intake)',
                }}
              />
            </div>
          )}
          <span className="caption">promedio semanal a ±10 % de sus calorías</span>
        </div>

        <div className="card org-kpi" style={{ animationDelay: '120ms' }}>
          <span className="caption">Peso, 30 días</span>
          <span className="tnum org-kpi-value">
            {r.peso.promedio === null ? '—' : conSigno(r.peso.promedio)}
            <span className="muted" style={{ fontSize: 14 }}> kg en promedio</span>
          </span>
          {conPeso > 0 && (
            <>
              <div className="org-split" aria-hidden>
                <span style={{ width: tramo(r.peso.bajan), background: 'var(--chart-intake)' }} />
                <span style={{ width: tramo(r.peso.estables), background: 'var(--chart-target)' }} />
                <span style={{ width: tramo(r.peso.suben), background: 'var(--chart-fat)' }} />
              </div>
              <span className="caption org-legend tnum">
                <span><i style={{ background: 'var(--chart-intake)' }} />{r.peso.bajan} bajan</span>
                <span><i style={{ background: 'var(--chart-target)' }} />{r.peso.estables} estables</span>
                <span><i style={{ background: 'var(--chart-fat)' }} />{r.peso.suben} suben</span>
              </span>
            </>
          )}
        </div>
      </div>
    </section>
  );
}
