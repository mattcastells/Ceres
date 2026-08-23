import Link from 'next/link';
import { SignOut } from '@/components/sign-out';
import { MyCode } from '@/components/my-code';
import { fechaCorta } from '@/lib/format';

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
 * A quién puede seguir esta cuenta.
 *
 * La lista sale de `care_patients`, la vista de columnas contadas: acá no se
 * consulta `profiles` ni se filtra por permisos en el cliente. Lo que muestra
 * es exactamente lo que la base devuelve, y lo que la base devuelve es lo que
 * cada paciente concedió.
 *
 * Cada ficha contesta **quién dejó de registrar**, que es la pregunta con la
 * que se abre esta pantalla cuando hay más de tres pacientes. Antes había que
 * entrar a cada uno para enterarse de que hacía nueve días que no cargaba nada,
 * y eso convertía la lista en un índice y no en un tablero.
 */
export function PatientsList({
  patients,
  diasConCarga,
  ultimos,
  error,
}: {
  patients: PatientRow[];
  /** Fechas `YYYY-MM-DD` de los últimos siete días, de la más vieja a hoy. */
  ultimos: string[];
  /** Por paciente, qué días de `ultimos` tienen alguna comida cargada. */
  diasConCarga: Record<string, string[]>;
  error?: boolean;
}) {
  const orden = [...patients].sort((a, b) =>
    (a.patient_name ?? '').localeCompare(b.patient_name ?? '', 'es'),
  );
  const resumen = resumenDeLaSemana(patients, diasConCarga);

  return (
    <>
      <header className="topbar">
        <div className="topbar-inner topbar-inner--plain">
          <div className="topbar-id">
            <h1>Pacientes</h1>
            <SignOut />
          </div>
        </div>
      </header>

      <main className="page">
        <MyCode />

        {error && (
          <p style={{ color: 'var(--danger)', marginTop: 'var(--s6)' }}>
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

        {orden.length > 0 && (
          <>
            <div className="section-header">{resumen}</div>
            <div className="grid grid--auto">
              {orden.map((p) => (
                <Card
                  key={p.grant_id}
                  patient={p}
                  ultimos={ultimos}
                  cargados={diasConCarga[p.patient_id] ?? []}
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
  ultimos,
  cargados,
}: {
  patient: PatientRow;
  ultimos: string[];
  cargados: string[];
}) {
  const cats = categorias(p);
  const set = new Set(cargados);
  const ultimaCarga = [...cargados].sort().pop() ?? null;
  const desde = ultimaCarga ? diasAtras(ultimaCarga, ultimos) : null;

  return (
    <Link href={`/paciente/${p.patient_id}`} className="card card-link plist">
      <div className="row" style={{ justifyContent: 'space-between' }}>
        <h3>{p.patient_name || 'Sin nombre'}</h3>
        {p.birth_date && (
          <span className="caption tnum">{edad(p.birth_date)} años</span>
        )}
      </div>

      {/* La semana de un vistazo. Siete puntos y no un número: "hace 3 días" no
          distingue a quien carga salteado de quien dejó de cargar el martes, y
          eso es lo que cambia de qué se habla en la consulta. */}
      {p.share_meals ? (
        <div className="plist-week">
          <div className="week-dots" aria-hidden>
            {ultimos.map((d) => (
              <span
                key={d}
                className="week-dot"
                data-on={set.has(d) ? '1' : '0'}
                title={`${fechaCorta(d)} · ${set.has(d) ? 'con comidas' : 'sin registro'}`}
              />
            ))}
          </div>
          <span className="caption">
            {desde === null
              ? 'sin cargar en la última semana'
              : desde === 0
                ? 'cargó hoy'
                : desde === 1
                  ? 'cargó ayer'
                  : `última carga hace ${desde} días`}
          </span>
        </div>
      ) : (
        <p className="caption plist-week" style={{ margin: 0 }}>
          Las comidas no están compartidas.
        </p>
      )}

      <div className="chips">
        {cats.map((c) => (
          <span key={c} className="chip chip--on">
            {c}
          </span>
        ))}
        {cats.length === 0 && (
          <span className="chip" style={{ color: 'var(--caution)' }}>
            Sin categorías: no vas a ver datos
          </span>
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

/** La línea que encabeza la lista: cuántos son y, si los hay, cuántos se
 *  quedaron sin cargar nada en la semana. Es la respuesta corta a la pregunta
 *  con la que se abre la pantalla; quiénes son lo dice cada ficha. Solo cuenta
 *  a quienes comparten las comidas: de los demás no se sabe si cargaron. */
function resumenDeLaSemana(
  patients: PatientRow[],
  diasConCarga: Record<string, string[]>,
): string {
  const n = patients.length;
  const sinCargar = patients.filter(
    (p) => p.share_meals && (diasConCarga[p.patient_id] ?? []).length === 0,
  ).length;
  const partes = [`${n} ${n === 1 ? 'paciente' : 'pacientes'}`];
  if (sinCargar > 0) {
    partes.push(`${sinCargar} sin cargar en la última semana`);
  }
  return partes.join(' · ');
}

function categorias(p: PatientRow): string[] {
  return [
    p.share_meals && 'Comidas',
    p.share_photos && 'Fotos',
    p.share_body && 'Peso y medidas',
    p.share_wellbeing && 'Actividad, agua, sueño y contexto',
  ].filter(Boolean) as string[];
}

/** Cuántos días atrás cae una fecha, contando sobre la ventana ya calculada.
 *
 *  Se cuenta con el índice y no restando `Date`s para no volver a meter el huso
 *  en el medio: la ventana ya viene del día local del paciente. */
function diasAtras(fecha: string, ultimos: string[]): number | null {
  const i = ultimos.indexOf(fecha);
  return i === -1 ? null : ultimos.length - 1 - i;
}

function edad(birthDate: string): number {
  const nacimiento = new Date(birthDate);
  const hoy = new Date();
  let años = hoy.getFullYear() - nacimiento.getFullYear();
  const mes = hoy.getMonth() - nacimiento.getMonth();
  if (mes < 0 || (mes === 0 && hoy.getDate() < nacimiento.getDate())) años--;
  return años;
}
