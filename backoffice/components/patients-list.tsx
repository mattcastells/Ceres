import { MainNav } from '@/components/main-nav';
import { TeamGrid } from '@/components/team-grid';
import { InvitesList, type CareInvite } from '@/components/invite-patient';
import { fechaCorta } from '@/lib/format';
import { alertasDe, type OverviewRow } from '@/lib/team';

const PLAN: Record<string, string> = { pro: 'Pro', premium: 'Premium', free: 'Gratis' };

export type PatientRow = {
  grant_id: string;
  patient_id: string;
  patient_name: string | null;
  birth_date: string | null;
  share_meals: boolean;
  share_photos: boolean;
  share_body: boolean;
  share_wellbeing: boolean;
  expires_at: string | null;
  /** Ruta de la foto de perfil en `progress-photos` (migración 58). */
  avatar_path?: string | null;
};

/** Una fila de `care_discharged()` (migración 56). */
export type DischargedRow = {
  patient_id: string;
  patient_name: string | null;
  accepted_at: string | null;
  revoked_at: string;
};

/**
 * El equipo: a quién sigue esta cuenta y cómo viene cada uno.
 *
 * La lista sale de `care_patients`, la vista de columnas contadas: acá no se
 * consulta `profiles` ni se filtra por permisos en el cliente. Lo que muestra
 * es exactamente lo que la base devuelve.
 *
 * Los números de cada ficha salen de **una sola llamada** a `care_overview()`
 * (migración 48), que los calcula en la base. Reemplaza a la consulta de
 * comidas de la última semana para todos los pacientes, que no estaba
 * paginada: PostgREST corta en mil filas sin avisar, y a partir de unos 25
 * pacientes activos la semana de los últimos de la lista salía vacía.
 *
 * Los pacientes van por nombre, sin buscador ni orden por prioridad (se
 * sacaron el 15/11/2026: la profesional prefirió una lista estable). Cada
 * ficha sigue diciendo en una frase lo que conviene mirar, sin semáforos ni
 * puntajes: comer por encima del objetivo se menciona, pero no es una alarma
 * (README, "lo que la pantalla no califica").
 *
 * El ciclo del paciente empieza y termina acá: **Dar de alta** lo invita por
 * mail (migración 56), las invitaciones esperan debajo del código, y las bajas
 * de los últimos 90 días quedan al final.
 */
export function PatientsList({
  patients,
  overview,
  hoy,
  error,
  plan = null,
  hasOrg = false,
  avatars = {},
  invites = [],
  discharged = [],
}: {
  patients: PatientRow[];
  /** Filas de `care_overview()`. `null` = la llamada falló: la lista se
   *  muestra igual, sin números. */
  overview: OverviewRow[] | null;
  hoy: string;
  error?: boolean;
  plan?: string | null;
  hasOrg?: boolean;
  /** patient_id → URL firmada de la foto de perfil. */
  avatars?: Record<string, string>;
  invites?: CareInvite[];
  discharged?: DischargedRow[];
}) {
  const porId = new Map((overview ?? []).map((r) => [r.patient_id, r]));

  const filas = patients
    .map((p) => {
      const o = porId.get(p.patient_id) ?? null;
      return {
        patient: p,
        o,
        nombre: p.patient_name || 'Sin nombre',
        alertas: o ? alertasDe(o, hoy) : [],
        avatar: avatars[p.patient_id] ?? null,
      };
    })
    .sort((a, b) => a.nombre.localeCompare(b.nombre, 'es'));

  return (
    <>
      <header className="topbar">
        <div className="topbar-inner topbar-inner--plain">
          <div className="topbar-id">
            <div>
              <h1>Pacientes</h1>
              <p className="topbar-sub caption">
                {patients.length} {patients.length === 1 ? 'paciente' : 'pacientes'}
                {plan && PLAN[plan] && ` · plan ${PLAN[plan]}`}
              </p>
            </div>
            <MainNav actual="pacientes" plan={plan} conOrganizacion={hasOrg} />
          </div>
        </div>
      </header>

      <main className="page">
        {error && (
          <p className="form-error" style={{ marginTop: 'var(--s6)' }}>
            No pudimos cargar la lista. Probá de nuevo en un rato.
          </p>
        )}

        {!error && patients.length === 0 && (
          <div className="card" style={{ marginTop: 'var(--s6)' }}>
            <h3>Todavía no tenés pacientes</h3>
          </div>
        )}

        {overview === null && patients.length > 0 && !error && (
          // Mejor la lista sin números que ninguna lista: no saber quién dejó
          // de registrar es peor que la lista completa, pero mucho mejor que no
          // poder entrar a ninguna ficha.
          <p className="caption" style={{ marginTop: 'var(--s6)' }}>
            No se pudieron traer los números del equipo. Los datos están en cada
            ficha.
          </p>
        )}

        {filas.length > 0 && (
          <>
            <div className="section-header">Pacientes</div>
            <TeamGrid filas={filas} hoy={hoy} />
          </>
        )}

        {/* Debajo de los pacientes: lo que se mira primero es el equipo. */}
        <InvitesList invites={invites} />

        {discharged.length > 0 && (
          <details className="bajas">
            <summary className="section-header">
              Bajas de los últimos 90 días · {discharged.length}
            </summary>
            <div className="card scroll-x">
              <table className="tabla-datos">
                <thead>
                  <tr>
                    <th>Paciente</th>
                    <th>Desde</th>
                    <th>Baja</th>
                  </tr>
                </thead>
                <tbody>
                  {discharged.map((d) => (
                    <tr key={`${d.patient_id}-${d.revoked_at}`}>
                      <td>{d.patient_name || 'Sin nombre'}</td>
                      <td className="tnum">
                        {d.accepted_at ? fechaCorta(d.accepted_at.slice(0, 10)) : '—'}
                      </td>
                      <td className="tnum">{fechaCorta(d.revoked_at.slice(0, 10))}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </details>
        )}
      </main>
    </>
  );
}
