'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { browserClient } from '@/lib/supabase-browser';
import { ConfirmDialog } from '@/components/dialog';

/**
 * Dar de baja a un paciente: deja de compartir sus datos con vos y vuelve a
 * su plan (Gratis, o Premium si lo paga). La fila del acceso queda con fecha,
 * no se borra: lo dice `discharge_patient` (migraciones 55 y 56). La titular
 * del consultorio también puede darlo de baja.
 *
 * `onDone` reemplaza la vuelta al tablero cuando la baja se da desde una lista
 * (la de la organización), donde lo que corresponde es refrescar.
 */
export function DischargeButton({
  patientId,
  name,
  quiet = false,
  onDone,
}: {
  patientId: string;
  name: string;
  quiet?: boolean;
  onDone?: () => void;
}) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function discharge() {
    setBusy(true);
    setError(null);
    const { error } = await browserClient().rpc('discharge_patient', {
      p_patient: patientId,
    });
    if (error) {
      setBusy(false);
      setError(error.hint || 'No pudimos darlo de baja. Probá de nuevo.');
      return;
    }
    setBusy(false);
    setOpen(false);
    if (onDone) {
      onDone();
    } else {
      router.push('/');
    }
    router.refresh();
  }

  return (
    <>
      <button
        type="button"
        className={quiet ? 'button--link' : 'button--quiet'}
        onClick={() => {
          setError(null);
          setOpen(true);
        }}
      >
        Dar de baja
      </button>
      <ConfirmDialog
        open={open}
        title={`¿Dar de baja a ${name || 'este paciente'}?`}
        body={
          <>
            Deja de compartir sus datos con el consultorio y, si la IA se la
            pagaban ustedes, vuelve a su plan. Lo que le escribiste queda en su
            app. Para volver, se lo invita de nuevo.
          </>
        }
        confirmLabel="Dar de baja"
        busyLabel="Dando de baja…"
        busy={busy}
        error={error}
        danger
        onConfirm={discharge}
        onClose={() => setOpen(false)}
      />
    </>
  );
}
