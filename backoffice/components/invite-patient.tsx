'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { browserClient } from '@/lib/supabase-browser';
import { Dialog } from '@/components/dialog';
import { MyCode } from '@/components/my-code';
import { fechaHora } from '@/lib/format';
import { ANAMNESIS, intakeDe, validar } from '@/lib/alta';

/** Una fila de `care_invites` (migraciones 56 y 60), como la lee la profesional. */
export type CareInvite = {
  id: string;
  email: string;
  status: 'pending' | 'accepted' | 'declined' | 'cancelled';
  created_at: string;
  responded_at: string | null;
  patient_name?: string | null;
  /** Solo para saber si salió con datos: el contenido no se muestra acá. */
  intake?: unknown;
};

type Camino = 'datos' | 'mail' | 'codigo';

const CAMINOS: { id: Camino; label: string }[] = [
  { id: 'datos', label: 'Cargar sus datos' },
  { id: 'mail', label: 'Invitar por mail' },
  { id: 'codigo', label: 'Darle tu código' },
];

/**
 * Dar de alta a un paciente, por cualquiera de los tres caminos:
 *
 * 1. **Cargar sus datos**: la profesional hace la primera consulta y completa
 *    el formulario. La invitación sale con los datos de la app (que la persona
 *    revisa y confirma en el onboarding) y con la anamnesis, que es solo de
 *    ella y al aceptar queda en la ficha del paciente (migración 60).
 * 2. **Invitar por mail**: la invitación sale vacía y la persona completa sus
 *    datos sola (migración 56).
 * 3. **Darle tu código**: para quien ya usa Ceres; lo carga en Perfil → Mi
 *    nutricionista.
 *
 * En los tres el consentimiento es del paciente: nada se comparte hasta que
 * acepta. La respuesta de `invite_patient` es la misma exista o no la cuenta,
 * así que el panel no sirve para averiguar quién usa Ceres.
 */
export function InvitePatient({ plan = null }: { plan?: string | null }) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [camino, setCamino] = useState<Camino>('datos');
  const [enviada, setEnviada] = useState<{ mail: string; conDatos: boolean } | null>(null);

  function cerrar() {
    setOpen(false);
    setEnviada(null);
    setCamino('datos');
  }

  function listo(mail: string, conDatos: boolean) {
    setEnviada({ mail, conDatos });
    router.refresh();
  }

  return (
    <>
      <button type="button" className="button--primary" onClick={() => setOpen(true)}>
        Dar de alta
      </button>
      <Dialog
        open={open}
        onClose={cerrar}
        title="Dar de alta a un paciente"
        // El mismo ancho en las tres pestañas: si cambiara, las pestañas se
        // correrían de lugar bajo el puntero al pasar de una a otra.
        wide={!enviada}
      >
        {enviada ? (
          <>
            <p style={{ margin: 0 }}>
              Invitación enviada a <strong className="invite-mail">{enviada.mail}</strong>.
            </p>
            <div className="row dialog-actions">
              <button type="button" className="button--quiet" onClick={() => setEnviada(null)}>
                Dar de alta a otra persona
              </button>
              <button type="button" className="button--primary" onClick={cerrar} autoFocus>
                Listo
              </button>
            </div>
          </>
        ) : (
          <>
            <div className="tabs alta-caminos" role="tablist" aria-label="Cómo dar de alta">
              {CAMINOS.map((c) => (
                <button
                  key={c.id}
                  type="button"
                  role="tab"
                  className="tab"
                  aria-selected={camino === c.id}
                  onClick={() => setCamino(c.id)}
                >
                  {c.label}
                </button>
              ))}
            </div>
            {camino === 'datos' && <FormDatos onListo={listo} onCancelar={cerrar} />}
            {camino === 'mail' && <FormMail onListo={listo} onCancelar={cerrar} />}
            {camino === 'codigo' && (
              <div className="alta-codigo">
                <MyCode plan={plan} />
              </div>
            )}
          </>
        )}
      </Dialog>
    </>
  );
}

// ── Camino 2: solo el mail ─────────────────────────────────────────────────

function FormMail({
  onListo,
  onCancelar,
}: {
  onListo: (mail: string, conDatos: boolean) => void;
  onCancelar: () => void;
}) {
  const [nombre, setNombre] = useState('');
  const [email, setEmail] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    const mail = email.trim();
    if (!mail) return;
    setBusy(true);
    setError(null);
    const { error } = await browserClient().rpc('invite_patient', {
      p_email: mail,
      p_name: nombre.trim() || null,
    });
    setBusy(false);
    if (error) return setError(error.hint || 'No pudimos enviar la invitación. Probá de nuevo.');
    onListo(mail.toLowerCase(), false);
  }

  return (
    <form onSubmit={enviar} className="invite-form">
      <label className="caption" htmlFor="alta-mail-nombre">
        Nombre
      </label>
      <input
        id="alta-mail-nombre"
        autoComplete="off"
        value={nombre}
        onChange={(e) => setNombre(e.target.value)}
        maxLength={80}
      />
      <label className="caption" htmlFor="alta-mail-email">
        Mail del paciente
      </label>
      <input
        id="alta-mail-email"
        type="email"
        inputMode="email"
        autoComplete="off"
        placeholder="nombre@mail.com"
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        required
      />
      {error && <p className="form-error" style={{ margin: 0 }}>{error}</p>}
      <div className="row dialog-actions">
        <button type="button" className="button--quiet" onClick={onCancelar} disabled={busy}>
          Cancelar
        </button>
        <button type="submit" className="button--primary" disabled={busy || !email.trim()}>
          {busy ? 'Enviando…' : 'Enviar invitación'}
        </button>
      </div>
    </form>
  );
}

// ── Camino 1: la primera consulta ──────────────────────────────────────────

// Los valores son los `wire` de los enums de la app (lib/domain/enums/enums.dart):
// la app los lee tal cual para proponerlos en el onboarding.
const SEXOS = [
  { v: 'female', l: 'Femenino' },
  { v: 'male', l: 'Masculino' },
  { v: 'unspecified', l: 'Prefiere no decirlo' },
];
const ACTIVIDADES = [
  { v: 'sedentary', l: 'Sedentario' },
  { v: 'light', l: 'Ligero (1–2 por semana)' },
  { v: 'moderate', l: 'Moderado (3–4)' },
  { v: 'high', l: 'Alto (5–6)' },
  { v: 'very_high', l: 'Muy alto (diario)' },
];
const OBJETIVOS = [
  { v: 'lose', l: 'Bajar de peso' },
  { v: 'maintain', l: 'Mantener' },
  { v: 'gain', l: 'Subir de peso' },
  { v: 'gain_muscle', l: 'Ganar músculo' },
];
const RESTRICCIONES = [
  { v: 'vegetarian', l: 'Vegetariano' },
  { v: 'vegan', l: 'Vegano' },
  { v: 'gluten_free', l: 'Sin gluten' },
  { v: 'lactose_free', l: 'Sin lactosa' },
  { v: 'nut_free', l: 'Sin frutos secos' },
  { v: 'seafood_free', l: 'Sin pescado ni mariscos' },
  { v: 'diabetes', l: 'Diabetes' },
  { v: 'hypertension', l: 'Hipertensión' },
];

function FormDatos({
  onListo,
  onCancelar,
}: {
  onListo: (mail: string, conDatos: boolean) => void;
  onCancelar: () => void;
}) {
  const [f, setF] = useState({
    nombre: '',
    email: '',
    sexo: '',
    nacimiento: '',
    altura: '',
    peso: '',
    actividad: '',
    objetivo: '',
    calorias: '',
  });
  const [flags, setFlags] = useState<string[]>([]);
  const [anam, setAnam] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const set = (k: keyof typeof f) => (e: { target: { value: string } }) =>
    setF((prev) => ({ ...prev, [k]: e.target.value }));

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    const err = validar(f);
    if (err) return setError(err);
    setBusy(true);
    setError(null);
    const anamnesis = Object.fromEntries(
      Object.entries(anam)
        .map(([k, v]) => [k, v.trim()])
        .filter(([, v]) => v),
    );
    const { error } = await browserClient().rpc('invite_patient', {
      p_email: f.email.trim(),
      p_name: f.nombre.trim(),
      p_intake: intakeDe(f, flags),
      p_anamnesis: Object.keys(anamnesis).length ? anamnesis : null,
    });
    setBusy(false);
    if (error) return setError(error.hint || 'No pudimos enviar la invitación. Probá de nuevo.');
    onListo(f.email.trim().toLowerCase(), true);
  }

  return (
    <form onSubmit={enviar} className="alta-form" noValidate>
      <fieldset className="alta-grupo">
        <legend>Persona</legend>
        <div className="alta-grid">
          <Campo id="alta-nombre" label="Nombre y apellido">
            <input id="alta-nombre" value={f.nombre} onChange={set('nombre')} maxLength={80} required />
          </Campo>
          <Campo id="alta-email" label="Mail">
            <input
              id="alta-email"
              type="email"
              inputMode="email"
              autoComplete="off"
              placeholder="nombre@mail.com"
              value={f.email}
              onChange={set('email')}
              required
            />
          </Campo>
        </div>
      </fieldset>

      <fieldset className="alta-grupo">
        <legend>Datos para la app</legend>
        <div className="alta-grid">
          <Campo id="alta-sexo" label="Sexo biológico">
            <select id="alta-sexo" value={f.sexo} onChange={set('sexo')}>
              <option value="">—</option>
              {SEXOS.map((o) => <option key={o.v} value={o.v}>{o.l}</option>)}
            </select>
          </Campo>
          <Campo id="alta-nac" label="Fecha de nacimiento">
            <input id="alta-nac" type="date" value={f.nacimiento} onChange={set('nacimiento')} />
          </Campo>
          <Campo id="alta-altura" label="Altura (cm)">
            <input id="alta-altura" inputMode="decimal" value={f.altura} onChange={set('altura')} placeholder="165" />
          </Campo>
          <Campo id="alta-peso" label="Peso (kg)">
            <input id="alta-peso" inputMode="decimal" value={f.peso} onChange={set('peso')} placeholder="70,5" />
          </Campo>
          <Campo id="alta-act" label="Actividad">
            <select id="alta-act" value={f.actividad} onChange={set('actividad')}>
              <option value="">—</option>
              {ACTIVIDADES.map((o) => <option key={o.v} value={o.v}>{o.l}</option>)}
            </select>
          </Campo>
          <Campo id="alta-obj" label="Objetivo">
            <select id="alta-obj" value={f.objetivo} onChange={set('objetivo')}>
              <option value="">—</option>
              {OBJETIVOS.map((o) => <option key={o.v} value={o.v}>{o.l}</option>)}
            </select>
          </Campo>
          <Campo id="alta-kcal" label="Calorías por día">
            <input
              id="alta-kcal"
              inputMode="numeric"
              value={f.calorias}
              onChange={set('calorias')}
            />
          </Campo>
        </div>
        <fieldset className="alta-flags">
          <legend className="caption">Restricciones</legend>
          <div className="alta-checks">
            {RESTRICCIONES.map((r) => (
              <label key={r.v} className="alta-check">
                <input
                  type="checkbox"
                  checked={flags.includes(r.v)}
                  onChange={(e) =>
                    setFlags((prev) =>
                      e.target.checked ? [...prev, r.v] : prev.filter((x) => x !== r.v),
                    )
                  }
                />
                {r.l}
              </label>
            ))}
          </div>
        </fieldset>
      </fieldset>

      <fieldset className="alta-grupo">
        <legend>Anamnesis</legend>
        <div className="alta-grid alta-grid--texto">
          {ANAMNESIS.map((a) => (
            <Campo
              key={a.k}
              id={`alta-an-${a.k}`}
              label={a.l}
              ancho={a.k === 'notas'}
            >
              <textarea
                id={`alta-an-${a.k}`}
                rows={a.k === 'notas' ? 3 : 2}
                maxLength={1500}
                value={anam[a.k] ?? ''}
                onChange={(e) => setAnam((prev) => ({ ...prev, [a.k]: e.target.value }))}
              />
            </Campo>
          ))}
        </div>
      </fieldset>

      {error && <p className="form-error" role="alert" style={{ margin: 0 }}>{error}</p>}
      <div className="row dialog-actions">
        <button type="button" className="button--quiet" onClick={onCancelar} disabled={busy}>
          Cancelar
        </button>
        <button type="submit" className="button--primary" disabled={busy}>
          {busy ? 'Enviando…' : 'Enviar invitación'}
        </button>
      </div>
    </form>
  );
}

function Campo({
  id,
  label,
  ancho = false,
  children,
}: {
  id: string;
  label: string;
  /** Ocupa todo el ancho de la grilla. */
  ancho?: boolean;
  children: React.ReactNode;
}) {
  return (
    <div className={ancho ? 'alta-campo alta-campo--ancho' : 'alta-campo'}>
      <label className="caption" htmlFor={id}>{label}</label>
      {children}
    </div>
  );
}

/**
 * Las invitaciones que todavía no se resolvieron, y las rechazadas de las
 * últimas dos semanas (para saber que no hace falta esperar). Las aceptadas no
 * van: esa persona ya está en la lista del equipo.
 */
export function InvitesList({ invites }: { invites: CareInvite[] }) {
  const router = useRouter();
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  if (invites.length === 0) return null;

  async function cancelar(id: string) {
    setBusy(id);
    setError(null);
    const { error } = await browserClient().rpc('cancel_care_invite', { p_id: id });
    setBusy(null);
    if (error) {
      setError('No se pudo cancelar. Probá de nuevo.');
      return;
    }
    router.refresh();
  }

  const pendientes = invites.filter((i) => i.status === 'pending').length;

  return (
    <section className="invites">
      <div className="section-header">
        Invitaciones{pendientes > 0 ? ` · ${pendientes} sin responder` : ''}
      </div>
      <div className="card invites-list">
        {invites.map((i) => (
          <div key={i.id} className="invite-row">
            <span className="invite-mail">
              {i.patient_name ? (
                <>
                  {i.patient_name} <span className="caption">· {i.email}</span>
                </>
              ) : (
                i.email
              )}
            </span>
            {i.intake ? <span className="chip chip--on">Con sus datos</span> : null}
            <span className="caption tnum">
              {i.status === 'pending'
                ? `Enviada el ${fechaHora(i.created_at)} · esperando que la acepte`
                : `Rechazó la invitación el ${fechaHora(i.responded_at ?? i.created_at)}`}
            </span>
            <span style={{ flex: 1 }} />
            {i.status === 'pending' && (
              <button
                type="button"
                className="button--link"
                onClick={() => cancelar(i.id)}
                disabled={busy !== null}
              >
                {busy === i.id ? 'Cancelando…' : 'Cancelar'}
              </button>
            )}
          </div>
        ))}
        {error && <p className="form-error">{error}</p>}
      </div>
    </section>
  );
}
