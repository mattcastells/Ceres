'use client';

import { useCallback, useEffect, useState } from 'react';
import { browserClient } from '@/lib/supabase-browser';

const PLAN_LABEL: Record<string, string> = {
  pro: 'Pro',
  premium: 'Premium',
  free: 'Gratis',
  patient: 'Paciente',
};

/**
 * El código que hay que dictarle al paciente, y el plan de la cuenta.
 *
 * Se pide con `ensure_care_code`, que lo crea la primera vez y después
 * devuelve siempre el mismo. Por eso se llama al abrir la pantalla y no hay un
 * botón "generar": un código que se puede regenerar es un código que alguien
 * va a regenerar sin querer, dejando afuera a quien ya lo tenía anotado. Los
 * nuevos empiezan con `CE-`; los `NT-` de antes siguen valiendo.
 *
 * ⚠️ Antes el error de la llamada se ignoraba y la tarjeta mostraba "…" para
 * siempre, que se lee como "está cargando" y no como "falló". Ahora un fallo
 * lo dice y deja reintentar: sin código, la profesional no tiene cómo sumar a
 * nadie.
 */
export function MyCode({ plan }: { plan?: string | null }) {
  const [code, setCode] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);
  // El motivo, cuando la base lo da: una cuenta de paciente no tiene código
  // de profesional (migración 56), y reintentar no lo arregla.
  const [motivo, setMotivo] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  const load = useCallback(() => {
    setFailed(false);
    browserClient()
      .rpc('ensure_care_code')
      .then(
        ({ data, error }) => {
          if (error || typeof data !== 'string') {
            setFailed(true);
            setMotivo(error?.hint ?? null);
            return;
          }
          setCode(data);
        },
        () => setFailed(true),
      );
  }, []);

  useEffect(load, [load]);

  return (
    <div className="card my-code">
      <div>
        <div className="caption row" style={{ gap: 'var(--s3)' }}>
          Tu código
          {plan && PLAN_LABEL[plan] && (
            // El plan va al lado del código porque es lo que decide si los
            // botones de IA del panel funcionan: con plan gratis, "Generar
            // informe" contesta que hace falta Pro, y conviene saberlo antes.
            <span className="badge" title="Tu plan">
              {PLAN_LABEL[plan]}
            </span>
          )}
        </div>
        {failed ? (
          <div style={{ marginTop: 'var(--s1)' }}>
            <span className="form-error" style={{ margin: 0 }}>
              {motivo ?? 'No pudimos traer tu código.'}
            </span>
          </div>
        ) : (
          <div className="tnum my-code-value">{code ?? '…'}</div>
        )}
      </div>

      {failed ? (
        !motivo && <button type="button" onClick={load}>
          Reintentar
        </button>
      ) : (
        code && (
          <button
            type="button"
            onClick={async () => {
              await navigator.clipboard.writeText(code);
              setCopied(true);
              setTimeout(() => setCopied(false), 2000);
            }}
          >
            {copied ? 'Copiado' : 'Copiar'}
          </button>
        )
      )}
    </div>
  );
}
