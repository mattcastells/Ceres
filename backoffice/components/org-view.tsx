import Link from 'next/link';
import { SignOut } from '@/components/sign-out';
import { AddMember, OrgPatientsTable, RemoveMember, type Miembro } from '@/components/org-manage';
import { conSigno, miles } from '@/lib/format';
import { porProfesional, resumirConsultorio, type OrgPatientRow, type ResumenConsultorio } from '@/lib/org';

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
 * El consultorio.
 *
 * Lo ven todas sus profesionales: quiénes son, cuántos pacientes tiene cada
 * una y cuánto del fondo de IA del mes se usó.
 *
 * Quien lo **administra** (la titular, o alguien con rol de administración)
 * además lo maneja (migración 56): los números de todo el consultorio, los
 * pacientes de todas con la profesional de cada uno —para reasignarlos o darlos
 * de baja—, y sumar o sacar profesionales. Las fichas de los pacientes de otra
 * profesional las abre en modo lectura: escribirle al paciente es de quien lo
 * atiende.
 *
 * Es una función pura de las filas, como `PatientView`, para poder mirarla
 * con datos de ejemplo (`app/preview/organizacion`).
 */
export function OrgView({
  rows,
  viewerId,
  pacientes = null,
  hoy,
}: {
  rows: OrgRow[];
  viewerId: string | null;
  /** `org_patients()`: `null` para quien no administra (o si falló). */
  pacientes?: OrgPatientRow[] | null;
  hoy: string;
}) {
  const org = rows[0];
  const usado = org.ai_used_month;
  const cupo = org.ai_monthly_quota;
  const pct = cupo > 0 ? Math.round((usado / cupo) * 100) : 0;
  const totalPacientes = rows.reduce((a, r) => a + r.member_patients, 0);

  const yo = rows.find((r) => r.member_id === viewerId);
  const administra = yo?.member_role === 'owner' || yo?.member_role === 'admin';
  const esTitular = yo?.member_role === 'owner';

  const miembros: Miembro[] = rows.map((r) => ({
    id: r.member_id,
    nombre: r.member_name || 'Sin nombre',
    rol: r.member_role,
    pacientes: r.member_patients,
  }));

  const resumen = pacientes ? resumirConsultorio(pacientes, hoy) : null;
  const porPro = pacientes ? porProfesional(pacientes, miembros, hoy) : null;

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
                {totalPacientes} {totalPacientes === 1 ? 'paciente' : 'pacientes'}
                {yo && ` · sos ${(ROL[yo.member_role] ?? yo.member_role).toLowerCase()}`}
              </p>
            </div>
            <nav className="row topbar-nav">
              {administra && <AddMember esTitular={esTitular} />}
              <SignOut />
            </nav>
          </div>
        </div>
      </header>

      <main className="page">
        {resumen && resumen.pacientes > 0 && <Numeros r={resumen} />}

        <section className="section" style={{ marginTop: resumen ? undefined : 'var(--s5)' }}>
          <h2>Profesionales</h2>
          <p className="caption" style={{ marginTop: 2, marginBottom: 'var(--s4)' }}>
            {administra
              ? 'Cómo viene el equipo de cada una. Activos: registraron comidas en los últimos 3 días.'
              : 'Quiénes atienden en el consultorio.'}
          </p>
          <div className="card scroll-x">
            <table className="tabla-datos">
              <thead>
                <tr>
                  <th>Nombre</th>
                  <th>Rol</th>
                  <th className="num">Pacientes</th>
                  {porPro && <th className="num">Activos</th>}
                  {porPro && <th className="num">Días con comidas (7)</th>}
                  {porPro && <th className="num">Dentro del objetivo</th>}
                  {administra && <th />}
                </tr>
              </thead>
              <tbody>
                {miembros.map((m) => {
                  const r = porPro?.find((x) => x.id === m.id)?.resumen;
                  return (
                    <tr key={m.id}>
                      <td>
                        {m.nombre}
                        {m.id === viewerId && <span className="caption"> · vos</span>}
                      </td>
                      <td>{ROL[m.rol] ?? m.rol}</td>
                      <td className="num tnum">{m.pacientes}</td>
                      {porPro && (
                        <td className="num tnum">
                          {r && r.pacientes > 0 ? `${r.activos} de ${r.pacientes}` : '—'}
                        </td>
                      )}
                      {porPro && (
                        <td className="num tnum">
                          {r?.adherencia !== null && r?.adherencia !== undefined
                            ? `${r.adherencia.toLocaleString('es-AR')} de 7`
                            : '—'}
                        </td>
                      )}
                      {porPro && (
                        <td className="num tnum">
                          {r && r.dentroObjetivo.de > 0
                            ? `${r.dentroObjetivo.si} de ${r.dentroObjetivo.de}`
                            : '—'}
                        </td>
                      )}
                      {administra && (
                        <td className="num">
                          {m.rol !== 'owner' && m.id !== viewerId && (
                            <RemoveMember id={m.id} nombre={m.nombre} />
                          )}
                        </td>
                      )}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </section>

        {pacientes && (
          <section className="section">
            <h2>Pacientes del consultorio · {pacientes.length}</h2>
            <p className="caption" style={{ marginTop: 2, marginBottom: 'var(--s4)' }}>
              Los de todas las profesionales. Para pasar a alguien con otra
              profesional, cambiala en su fila. Las fichas de otras se abren en
              modo lectura.
            </p>
            <OrgPatientsTable
              pacientes={pacientes}
              miembros={miembros}
              viewerId={viewerId}
              hoy={hoy}
            />
          </section>
        )}

        <section className="section">
          <h2>Fondo de IA del mes</h2>
          <p className="caption" style={{ marginTop: 2, marginBottom: 'var(--s4)' }}>
            Análisis de comidas de los pacientes e informes del panel, de todo el
            consultorio. Se renueva el 1.° de cada mes.
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
      <h2>El consultorio en números</h2>
      <p className="caption" style={{ marginTop: 2, marginBottom: 'var(--s4)' }}>
        Todos los pacientes, la última semana. Agregado: el detalle de cada uno
        está en su ficha.
      </p>
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
