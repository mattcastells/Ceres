'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { browserClient } from '@/lib/supabase-browser';
import { Dialog } from '@/components/dialog';
import { fechaHora } from '@/lib/format';

/** Una fila de `care_invites` (migración 56), como la lee la profesional. */
export type CareInvite = {
  id: string;
  email: string;
  status: 'pending' | 'accepted' | 'declined' | 'cancelled';
  created_at: string;
  responded_at: string | null;
};

/**
 * El alta de un paciente desde el panel: la profesional escribe el mail con
 * el que la persona usa (o va a usar) Ceres, y le llega una invitación en la
 * app. Recién cuando la acepta empieza a compartir: el consentimiento sigue
 * siendo del paciente.
 *
 * La respuesta es la misma exista o no la cuenta (`invite_patient`), así que
 * el panel no sirve para averiguar quién usa Ceres.
 */
export function InvitePatient() {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [email, setEmail] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [enviada, setEnviada] = useState<string | null>(null);

  function cerrar() {
    setOpen(false);
    setEmail('');
    setError(null);
    setEnviada(null);
  }

  async function invitar(e: React.FormEvent) {
    e.preventDefault();
    const mail = email.trim();
    if (!mail) return;
    setBusy(true);
    setError(null);
    const { error } = await browserClient().rpc('invite_patient', { p_email: mail });
    setBusy(false);
    if (error) {
      setError(error.hint || 'No pudimos enviar la invitación. Probá de nuevo.');
      return;
    }
    setEnviada(mail.toLowerCase());
    setEmail('');
    router.refresh();
  }

  return (
    <>
      <button type="button" className="button--primary" onClick={() => setOpen(true)}>
        Dar de alta
      </button>
      <Dialog open={open} onClose={cerrar} title="Dar de alta a un paciente">
        {enviada ? (
          <>
            <p className="muted" style={{ margin: 0 }}>
              Listo: la invitación a <strong className="invite-mail">{enviada}</strong> ya
              está en su app, en Perfil → Mi nutricionista. Cuando la acepte,
              aparece en tu equipo.
            </p>
            <div className="row dialog-actions">
              <button type="button" className="button--quiet" onClick={() => setEnviada(null)}>
                Invitar a otra persona
              </button>
              <button type="button" className="button--primary" onClick={cerrar} autoFocus>
                Listo
              </button>
            </div>
          </>
        ) : (
          <form onSubmit={invitar} className="invite-form">
            <p className="muted" style={{ margin: 0 }}>
              Escribí el mail con el que usa Ceres. Le llega una invitación en la
              app y, cuando la acepta, ves todo lo que registra. Si todavía no
              tiene cuenta, la ve al crearla con ese mail.
            </p>
            <label className="caption" htmlFor="invite-email">
              Mail del paciente
            </label>
            <input
              id="invite-email"
              type="email"
              inputMode="email"
              autoComplete="off"
              placeholder="nombre@mail.com"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              data-autofocus
              required
            />
            {error && <p className="form-error" style={{ margin: 0 }}>{error}</p>}
            <div className="row dialog-actions">
              <button type="button" className="button--quiet" onClick={cerrar} disabled={busy}>
                Cancelar
              </button>
              <button type="submit" className="button--primary" disabled={busy || !email.trim()}>
                {busy ? 'Enviando…' : 'Enviar invitación'}
              </button>
            </div>
          </form>
        )}
      </Dialog>
    </>
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
            <span className="invite-mail">{i.email}</span>
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
