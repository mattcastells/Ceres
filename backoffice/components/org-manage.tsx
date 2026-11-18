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
 * Los pacientes de la organización (todos de su única profesional), con los
 * números del tablero y la baja. Se busca por nombre.
 */
export function OrgPatientsTable({
  pacientes,
  hoy,
}: {
  pacientes: OrgPatientRow[];
  hoy: string;
}) {
  const [q, setQ] = useState('');

  const visibles = useMemo(() => {
    const texto = q.trim().toLowerCase();
    return pacientes.filter(
      (p) => !texto || (p.patient_name ?? '').toLowerCase().includes(texto),
    );
  }, [pacientes, q]);

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
      </div>
      <div style={{ height: 'var(--s4)' }} />
      <div className="card scroll-x">
        <table className="tabla-datos">
          <thead>
            <tr>
              <th>Paciente</th>
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
                <td colSpan={6} className="muted">
                  {pacientes.length === 0 ? 'Todavía no hay pacientes.' : 'Nadie con ese nombre.'}
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </>
  );
}
