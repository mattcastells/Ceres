'use client';

import Link from 'next/link';
import { useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import { browserClient } from '@/lib/supabase-browser';
import { ConfirmDialog, Dialog } from '@/components/dialog';
import { DischargeButton } from '@/components/discharge-button';
import { conSigno, miles } from '@/lib/format';
import { cambioPeso, type OrgPatientRow } from '@/lib/org';
import { diasDesde } from '@/lib/team';

export type Miembro = {
  id: string;
  nombre: string;
  rol: string;
  pacientes: number;
};

/**
 * Sumar una profesional al consultorio, por el mail de su cuenta
 * (`org_add_member`). La cuenta tiene que existir y ser profesional: un
 * paciente no entra como profesional, y cada profesional usa una cuenta
 * propia.
 */
export function AddMember({ esTitular }: { esTitular: boolean }) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [email, setEmail] = useState('');
  const [rol, setRol] = useState<'professional' | 'admin'>('professional');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function cerrar() {
    setOpen(false);
    setEmail('');
    setRol('professional');
    setError(null);
  }

  async function sumar(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    const { error } = await browserClient().rpc('org_add_member', {
      p_email: email.trim(),
      p_role: rol,
    });
    setBusy(false);
    if (error) {
      setError(error.hint || 'No se pudo sumar. Probá de nuevo.');
      return;
    }
    cerrar();
    router.refresh();
  }

  return (
    <>
      <button type="button" className="button--primary" onClick={() => setOpen(true)}>
        Sumar profesional
      </button>
      <Dialog open={open} onClose={cerrar} title="Sumar una profesional">
        <form onSubmit={sumar} className="invite-form">
          <p className="muted" style={{ margin: 0 }}>
            Con el mail de su cuenta de Ceres: una cuenta propia, todavía sin
            pacientes. Entra con el plan Pro del consultorio.
          </p>
          <label className="caption" htmlFor="member-email">
            Mail
          </label>
          <input
            id="member-email"
            type="email"
            placeholder="nombre@consultorio.com"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            data-autofocus
            required
          />
          {esTitular && (
            <>
              <label className="caption" htmlFor="member-role">
                Rol
              </label>
              <select
                id="member-role"
                value={rol}
                onChange={(e) => setRol(e.target.value as 'professional' | 'admin')}
              >
                <option value="professional">Profesional · atiende a sus pacientes</option>
                <option value="admin">Administración · además ve y reasigna a todos</option>
              </select>
            </>
          )}
          {error && <p className="form-error" style={{ margin: 0 }}>{error}</p>}
          <div className="row dialog-actions">
            <button type="button" className="button--quiet" onClick={cerrar} disabled={busy}>
              Cancelar
            </button>
            <button type="submit" className="button--primary" disabled={busy || !email.trim()}>
              {busy ? 'Sumando…' : 'Sumar'}
            </button>
          </div>
        </form>
      </Dialog>
    </>
  );
}

/** Sacar a una profesional. La base no deja si todavía tiene pacientes: el
 *  mensaje dice cuántos, y la tabla de abajo es donde se reasignan. */
export function RemoveMember({ id, nombre }: { id: string; nombre: string }) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function sacar() {
    setBusy(true);
    setError(null);
    const { error } = await browserClient().rpc('org_remove_member', { p_user: id });
    setBusy(false);
    if (error) {
      setError(error.hint || 'No se pudo sacar. Probá de nuevo.');
      return;
    }
    setOpen(false);
    router.refresh();
  }

  return (
    <>
      <button
        type="button"
        className="button--link"
        onClick={() => {
          setError(null);
          setOpen(true);
        }}
      >
        Sacar
      </button>
      <ConfirmDialog
        open={open}
        title={`¿Sacar a ${nombre} del consultorio?`}
        body="Deja de ver el consultorio y pierde el plan Pro que le pagaba. Su cuenta y lo que escribió quedan."
        confirmLabel="Sacar"
        busyLabel="Sacando…"
        busy={busy}
        error={error}
        danger
        onConfirm={sacar}
        onClose={() => setOpen(false)}
      />
    </>
  );
}

/**
 * Los pacientes de todo el consultorio: de quién es cada uno, cómo viene, y
 * las dos acciones de quien administra —pasarlo a otra profesional o darlo de
 * baja—. El nombre abre la ficha (en modo lectura si no es suyo).
 */
export function OrgPatientsTable({
  pacientes,
  miembros,
  viewerId,
  hoy,
}: {
  pacientes: OrgPatientRow[];
  miembros: Miembro[];
  viewerId: string | null;
  hoy: string;
}) {
  const router = useRouter();
  const [q, setQ] = useState('');
  const [de, setDe] = useState('todas');
  const [mover, setMover] = useState<{ p: OrgPatientRow; a: Miembro } | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const visibles = useMemo(() => {
    const texto = q.trim().toLowerCase();
    return pacientes.filter(
      (p) =>
        (de === 'todas' || p.professional_id === de) &&
        (!texto || (p.patient_name ?? '').toLowerCase().includes(texto)),
    );
  }, [pacientes, q, de]);

  async function reasignar() {
    if (!mover) return;
    setBusy(true);
    setError(null);
    const { error } = await browserClient().rpc('reassign_patient', {
      p_patient: mover.p.patient_id,
      p_to: mover.a.id,
    });
    setBusy(false);
    if (error) {
      setError(error.hint || 'No se pudo reasignar. Probá de nuevo.');
      return;
    }
    setMover(null);
    router.refresh();
  }

  return (
    <>
      <div className="row org-tools">
        <input
          type="search"
          placeholder="Buscar paciente"
          value={q}
          onChange={(e) => setQ(e.target.value)}
          aria-label="Buscar paciente por nombre"
        />
        {miembros.length > 1 && (
          <select value={de} onChange={(e) => setDe(e.target.value)} aria-label="Filtrar por profesional">
            <option value="todas">Todas las profesionales</option>
            {miembros.map((m) => (
              <option key={m.id} value={m.id}>
                {m.nombre}
              </option>
            ))}
          </select>
        )}
      </div>
      <div style={{ height: 'var(--s4)' }} />
      <div className="card scroll-x">
        <table className="tabla-datos">
          <thead>
            <tr>
              <th>Paciente</th>
              <th>Profesional</th>
              <th className="num">Última comida</th>
              <th className="num">Días con comidas (7)</th>
              <th className="num">Calorías vs objetivo</th>
              <th className="num">Peso 30 días</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {visibles.map((p) => {
              const ultima = diasDesde(p.last_meal_date, hoy);
              const peso = cambioPeso(p);
              const pct =
                p.avg_kcal_7 && p.target_kcal
                  ? Math.round((p.avg_kcal_7 / p.target_kcal) * 100)
                  : null;
              return (
                <tr key={p.patient_id}>
                  <td>
                    <Link href={`/paciente/${p.patient_id}`}>{p.patient_name || 'Sin nombre'}</Link>
                  </td>
                  <td>
                    {miembros.length > 1 ? (
                      <select
                        value={p.professional_id}
                        aria-label={`Profesional de ${p.patient_name ?? 'este paciente'}`}
                        onChange={(e) => {
                          const a = miembros.find((m) => m.id === e.target.value);
                          if (a && a.id !== p.professional_id) {
                            setError(null);
                            setMover({ p, a });
                          }
                        }}
                      >
                        {miembros.map((m) => (
                          <option key={m.id} value={m.id}>
                            {m.nombre}
                            {m.id === viewerId ? ' (vos)' : ''}
                          </option>
                        ))}
                      </select>
                    ) : (
                      p.professional_name
                    )}
                  </td>
                  <td
                    className="num tnum"
                    style={ultima !== null && ultima >= 3 ? { color: 'var(--caution)' } : undefined}
                  >
                    {ultima === null ? '—' : ultima === 0 ? 'hoy' : ultima === 1 ? 'ayer' : `hace ${ultima} días`}
                  </td>
                  <td className="num tnum">{p.days_logged_7 ?? 0} de 7</td>
                  <td className="num tnum">
                    {pct === null ? '—' : `${pct} % de ${miles(p.target_kcal!)}`}
                  </td>
                  <td className="num tnum">{peso === null ? '—' : `${conSigno(peso)} kg`}</td>
                  <td className="num">
                    <DischargeButton
                      patientId={p.patient_id}
                      name={p.patient_name ?? ''}
                      quiet
                      onDone={() => {}}
                    />
                  </td>
                </tr>
              );
            })}
            {visibles.length === 0 && (
              <tr>
                <td colSpan={7} className="muted">
                  {pacientes.length === 0 ? 'Todavía no hay pacientes en el consultorio.' : 'Nadie con ese nombre.'}
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      <ConfirmDialog
        open={mover !== null}
        title={`¿Pasar a ${mover?.p.patient_name ?? 'este paciente'} con ${mover?.a.nombre ?? ''}?`}
        body={
          <>
            Desde ahora lo atiende {mover?.a.nombre}: ve su ficha y le escribe.{' '}
            {mover?.p.professional_name ?? 'Su profesional anterior'} deja de verlo.
            Las devoluciones que ya tiene quedan en su app.
          </>
        }
        confirmLabel="Reasignar"
        busyLabel="Reasignando…"
        busy={busy}
        error={error}
        onConfirm={reasignar}
        onClose={() => setMover(null)}
      />
    </>
  );
}
