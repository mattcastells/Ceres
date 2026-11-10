import Link from 'next/link';
import { SignOut } from '@/components/sign-out';
import { miles } from '@/lib/format';

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

const ROL: Record<string, string> = {
  owner: 'Titular',
  admin: 'Administración',
  professional: 'Profesional',
};

/**
 * El consultorio: quiénes son, cuántos pacientes tiene cada una y cuánto del
 * fondo de IA del mes se usó.
 *
 * **Agregado, nunca detalle.** La organización paga la IA de los pacientes de
 * sus profesionales, pero eso no le abre sus datos: `my_organization()` es una
 * función de definidor que devuelve conteos —cuántos análisis, cuántos
 * pacientes—, no una policy que abra `ai_analyses`. Esta pantalla no tiene
 * enlaces a pacientes de otras profesionales porque no hay a dónde llevarlos.
 *
 * Es una función pura de las filas, como `PatientView`, para poder mirarla
 * con datos de ejemplo (`app/preview/organizacion`).
 */
export function OrgView({ rows, viewerId }: { rows: OrgRow[]; viewerId: string | null }) {
  const org = rows[0];
  const usado = org.ai_used_month;
  const cupo = org.ai_monthly_quota;
  const pct = cupo > 0 ? Math.round((usado / cupo) * 100) : 0;
  const pacientes = rows.reduce((a, r) => a + r.member_patients, 0);

  return (
    <>
      <header className="topbar">
        <div className="topbar-inner topbar-inner--plain">
          <div className="topbar-id">
            <div style={{ minWidth: 0 }}>
              <p className="topbar-back caption">
                <Link href="/">← Tu equipo</Link>
              </p>
              <h1>{org.org_name}</h1>
              <p className="topbar-sub caption">
                {rows.length} {rows.length === 1 ? 'profesional' : 'profesionales'} ·{' '}
                {pacientes} {pacientes === 1 ? 'paciente' : 'pacientes'}
              </p>
            </div>
            <SignOut />
          </div>
        </div>
      </header>

      <main className="page">
        <section className="section" style={{ marginTop: 'var(--s5)' }}>
          <h2>Fondo de IA del mes</h2>
          <p className="caption" style={{ marginTop: 2, marginBottom: 'var(--s4)' }}>
            Los análisis de comidas de los pacientes de todo el consultorio y los
            informes del panel, desde el 1.° del mes. Se renueva el primer día de
            cada mes.
          </p>
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

        <section className="section">
          <h2>Profesionales</h2>
          <div style={{ height: 'var(--s4)' }} />
          <div className="card scroll-x">
            <table className="tabla-datos">
              <thead>
                <tr>
                  <th>Nombre</th>
                  <th>Rol</th>
                  <th className="num">Pacientes</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.member_id}>
                    <td>
                      {r.member_name || 'Sin nombre'}
                      {r.member_id === viewerId && <span className="caption"> · vos</span>}
                    </td>
                    <td>{ROL[r.member_role] ?? r.member_role}</td>
                    <td className="num tnum">{r.member_patients}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      </main>
    </>
  );
}
