import Link from 'next/link';
import { SignOut } from '@/components/sign-out';
import { MyCode } from '@/components/my-code';
import { TeamReport } from '@/components/team-report';
import { conSigno, diasEntre, fechaCorta, miles } from '@/lib/format';
import {
  alertasDe,
  cambioPeso30,
  diasDesde,
  ordenarEquipo,
  pideAtencion,
  type Alerta,
  type OverviewRow,
} from '@/lib/team';
import type { CareReport } from '@/lib/queries';

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
};

/**
 * El equipo: a quién sigue esta cuenta y cómo viene cada uno.
 *
 * La lista sale de `care_patients`, la vista de columnas contadas: acá no se
 * consulta `profiles` ni se filtra por permisos en el cliente. Lo que muestra
 * es exactamente lo que la base devuelve, y lo que la base devuelve es lo que
 * cada paciente concedió.
 *
 * Los números de cada ficha salen de **una sola llamada** a `care_overview()`
 * (migración 48), que los calcula en la base respetando las categorías
 * concedidas. Reemplaza a la consulta de comidas de la última semana para todos
 * los pacientes, que no estaba paginada: PostgREST corta en mil filas sin
 * avisar, y a partir de unos 25 pacientes activos la semana de los últimos de
 * la lista salía vacía —"sin cargar"— cuando sí habían cargado.
 *
 * La pantalla contesta **a quién le escribo hoy**: arriba va quien pide
 * atención (`lib/team.ts`), y cada ficha dice por qué en una frase. Sin
 * semáforos ni puntajes: comer por encima del objetivo se menciona, pero no es
 * una alarma (README, "lo que la pantalla no califica").
 */
export function PatientsList({
  patients,
  overview,
  hoy,
  error,
  plan = null,
  hasOrg = false,
  teamReport = null,
}: {
  patients: PatientRow[];
  /** Filas de `care_overview()`. `null` = la llamada falló: la lista se
   *  muestra igual, sin números. */
  overview: OverviewRow[] | null;
  hoy: string;
  error?: boolean;
  plan?: string | null;
  hasOrg?: boolean;
  teamReport?: CareReport | null;
}) {
  const porId = new Map((overview ?? []).map((r) => [r.patient_id, r]));

  const filas = ordenarEquipo(
    patients.map((p) => {
      const o = porId.get(p.patient_id) ?? null;
      return {
        patient: p,
        o,
        nombre: p.patient_name || 'Sin nombre',
        alertas: o ? alertasDe(o, hoy) : [],
      };
    }),
  );

  const atencion = filas.filter((f) => pideAtencion(f.alertas)).length;
  const nombres = Object.fromEntries(filas.map((f) => [f.patient.patient_id, f.nombre]));

  return (
    <>
      <header className="topbar">
        <div className="topbar-inner topbar-inner--plain">
          <div className="topbar-id">
            <div>
              <h1>Tu equipo</h1>
              <p className="topbar-sub caption">
                {patients.length} {patients.length === 1 ? 'paciente' : 'pacientes'}
                {atencion > 0 && ` · ${atencion} para mirar hoy`}
              </p>
            </div>
            <nav className="row topbar-nav">
              {hasOrg && <Link href="/organizacion">Organización</Link>}
              <SignOut />
            </nav>
          </div>
        </div>
      </header>

      <main className="page">
        <MyCode plan={plan} />

        {error && (
          <p className="form-error" style={{ marginTop: 'var(--s6)' }}>
            No pudimos cargar la lista. Probá de nuevo en un rato.
          </p>
        )}

        {!error && patients.length === 0 && (
          <div className="card" style={{ marginTop: 'var(--s6)' }}>
            <h3>Todavía no te dio acceso nadie</h3>
            <p className="muted" style={{ marginTop: 'var(--s2)' }}>
              Pasale tu código de arriba a la persona que vas a seguir. Lo carga
              en la app, en Perfil → Mi nutricionista, y elige qué querés ver.
            </p>
          </div>
        )}

        {patients.length > 0 && (
          <TeamReport initial={teamReport} nombres={nombres} plan={plan} />
        )}

        {overview === null && patients.length > 0 && !error && (
          // Mejor la lista sin números que ninguna lista: no saber quién dejó
          // de registrar es peor que la lista completa, pero mucho mejor que no
          // poder entrar a ninguna ficha.
          <p className="caption" style={{ marginTop: 'var(--s6)' }}>
            No pudimos traer los números del equipo. La lista está completa; los
            datos de cada paciente están en su ficha.
          </p>
        )}

        {filas.length > 0 && (
          <>
            <div className="section-header">
              {atencion > 0 ? 'Primero, quien pide atención' : 'Pacientes'}
            </div>
            <div className="grid grid--auto">
              {filas.map((f) => (
                <Card
                  key={f.patient.grant_id}
                  patient={f.patient}
                  o={f.o}
                  alertas={f.alertas}
                  hoy={hoy}
                />
              ))}
            </div>
          </>
        )}
      </main>
    </>
  );
}

function Card({
  patient: p,
  o,
  alertas,
  hoy,
}: {
  patient: PatientRow;
  o: OverviewRow | null;
  alertas: Alerta[];
  hoy: string;
}) {
  const cats = categorias(p);
  const ultima = o ? diasDesde(o.last_meal_date, hoy) : null;
  const peso = o ? cambioPeso30(o) : null;
  // Los denominadores salen de la ventana efectiva, como en la ficha: quien
  // empezó hace cuatro días registró 4 de 4, no 4 de 7. Ver `lib/tracking.ts`.
  const antiguedad = o?.tracking_since
    ? diasEntre(o.tracking_since.slice(0, 10), hoy) + 1
    : null;
  const de7 = antiguedad === null ? 7 : Math.max(Math.min(7, antiguedad), 0);
  const de14 = antiguedad === null ? 14 : Math.max(Math.min(14, antiguedad), 0);
  const pct =
    o?.avg_kcal_7 && o.target_kcal ? Math.round((o.avg_kcal_7 / o.target_kcal) * 100) : null;
  const sinLeer = o?.unread_feedback ?? 0;

  return (
    <Link href={`/paciente/${p.patient_id}`} className="card card-link plist">
      <div className="row" style={{ justifyContent: 'space-between' }}>
        <h3>{p.patient_name || 'Sin nombre'}</h3>
        {p.birth_date && (
          <span className="caption tnum">{edad(p.birth_date)} años</span>
        )}
      </div>

      {alertas.length > 0 && (
        <div className="chips">
          {alertas.map((a) => (
            <span key={a.id} className={a.tono === 'atencion' ? 'chip chip--warn' : 'chip chip--on'}>
              {a.texto}
            </span>
          ))}
        </div>
      )}

      {o && (
        <dl className="team-stats">
          {p.share_meals && (
            <>
              <div>
                <dt className="caption">Última comida</dt>
                <dd className="tnum">
                  {ultima === null
                    ? '—'
                    : ultima === 0
                      ? 'hoy'
                      : ultima === 1
                        ? 'ayer'
                        : `hace ${ultima} días`}
                </dd>
              </div>
              <div>
                <dt className="caption">Días con comidas</dt>
                <dd className="tnum">
                  {o.days_logged_7 ?? 0}
                  <span className="muted"> de {de7}</span>
                  <span className="caption"> · {o.days_logged_14 ?? 0} de {de14}</span>
                </dd>
              </div>
              <div>
                <dt className="caption">Calorías, últimos 7 días</dt>
                <dd className="tnum">
                  {o.avg_kcal_7 ? `${miles(o.avg_kcal_7)} kcal` : '—'}
                  {pct !== null && (
                    <span
                      className="caption"
                      // El mismo ámbar del resto del panel para lo que pasó el
                      // objetivo, y nada para lo que quedó debajo: ni verde de
                      // logro ni rojo de alarma.
                      style={pct > 100 ? { color: 'var(--caution)' } : undefined}
                    >
                      {' '}· {pct} % de {miles(o.target_kcal!)}
                    </span>
                  )}
                </dd>
              </div>
            </>
          )}
          {p.share_body && (
            <div>
              <dt className="caption">Peso, 30 días</dt>
              <dd className="tnum">{peso === null ? '—' : `${conSigno(peso)} kg`}</dd>
            </div>
          )}
          <div>
            <dt className="caption">Devoluciones</dt>
            <dd className="tnum">
              {sinLeer > 0 ? `${sinLeer} sin leer` : <span className="muted">al día</span>}
            </dd>
          </div>
        </dl>
      )}

      <div className="chips" style={{ marginTop: 'auto' }}>
        {cats.map((c) => (
          <span key={c} className="chip">
            {c}
          </span>
        ))}
        {cats.length === 0 && (
          <span className="chip chip--warn">Sin categorías: no vas a ver datos</span>
        )}
      </div>

      {p.expires_at && (
        <p className="caption" style={{ margin: 0 }}>
          El acceso vence el {fechaCorta(p.expires_at.slice(0, 10))}
        </p>
      )}
    </Link>
  );
}

function categorias(p: PatientRow): string[] {
  return [
    p.share_meals && 'Comidas',
    p.share_photos && 'Fotos',
    p.share_body && 'Peso y medidas',
    p.share_wellbeing && 'Hábitos y contexto',
  ].filter(Boolean) as string[];
}

function edad(birthDate: string): number {
  const nacimiento = new Date(birthDate);
  const hoy = new Date();
  let años = hoy.getFullYear() - nacimiento.getFullYear();
  const mes = hoy.getMonth() - nacimiento.getMonth();
  if (mes < 0 || (mes === 0 && hoy.getDate() < nacimiento.getDate())) años--;
  return años;
}
