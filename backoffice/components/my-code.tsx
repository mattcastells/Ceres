'use client';

import { useEffect, useState } from 'react';
import { browserClient } from '@/lib/supabase-browser';

/**
 * El código que hay que dictarle al paciente.
 *
 * Se pide con `ensure_care_code`, que lo crea la primera vez y después
 * devuelve siempre el mismo. Por eso se llama al abrir la pantalla y no hay un
 * botón "generar": un código que se puede regenerar es un código que alguien
 * va a regenerar sin querer, dejando afuera a quien ya lo tenía anotado.
 */
export function MyCode() {
  const [code, setCode] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    browserClient()
      .rpc('ensure_care_code')
      .then(({ data }) => setCode(typeof data === 'string' ? data : null));
  }, []);

  return (
    <div
      className="card"
      style={{
        marginTop: 'var(--s6)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        gap: 'var(--s4)',
        flexWrap: 'wrap',
      }}
    >
      <div>
        <div className="caption">Tu código</div>
        <div
          className="tnum"
          style={{
            fontSize: 22,
            letterSpacing: '0.06em',
            marginTop: 'var(--s1)',
          }}
        >
          {code ?? '…'}
        </div>
      </div>

      {code && (
        <button
          onClick={async () => {
            await navigator.clipboard.writeText(code);
            setCopied(true);
            setTimeout(() => setCopied(false), 2000);
          }}
        >
          {copied ? 'Copiado' : 'Copiar'}
        </button>
      )}
    </div>
  );
}
