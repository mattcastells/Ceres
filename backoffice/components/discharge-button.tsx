'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { browserClient } from '@/lib/supabase-browser';

/**
 * Dar de baja a un paciente: deja de compartir sus datos con vos y vuelve a
 * su plan (Gratis, o Premium si lo paga). La fila del acceso queda con fecha,
 * no se borra: lo dice `discharge_patient` (migración 55).
 */
export function DischargeButton({
  patientId,
  name,
}: {
  patientId: string;
  name: string;
}) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function discharge() {
    const quien = name || 'este paciente';
    if (
      !window.confirm(
        `¿Dar de baja a ${quien}? Deja de compartir sus datos con vos y, si ` +
          'la IA se la pagabas vos, vuelve a su plan.',
      )
    ) {
      return;
    }
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
    router.push('/');
    router.refresh();
  }

  return (
    <>
      <button
        type="button"
        className="button--quiet"
        onClick={discharge}
        disabled={busy}
      >
        {busy ? 'Dando de baja…' : 'Dar de baja'}
      </button>
      {error && (
        <span className="form-error" style={{ margin: 0 }}>
          {error}
        </span>
      )}
    </>
  );
}
