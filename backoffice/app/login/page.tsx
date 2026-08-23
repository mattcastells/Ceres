'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { browserClient } from '@/lib/supabase-browser';

/**
 * Entrar con la misma cuenta de Ceres.
 *
 * No hay alta desde acá a propósito: la cuenta se crea en la app, que es donde
 * están los términos y la política de privacidad. Un alta en el panel sería un
 * segundo camino a lo mismo, con la mitad de lo que hay que aceptar.
 */
export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function onSubmit(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    const { error } = await browserClient().auth.signInWithPassword({
      email: email.trim(),
      password,
    });

    if (error) {
      setBusy(false);
      // El mensaje del proveedor distingue "no existe" de "contraseña mal", y
      // repetirlo le cuenta a cualquiera qué correos tienen cuenta. Uno solo
      // para los dos casos.
      setError('No pudimos entrar. Revisá el correo y la contraseña.');
      return;
    }

    router.replace('/');
    router.refresh();
  }

  return (
    <main className="login">
      <div className="card" style={{ width: '100%', maxWidth: 380 }}>
        <h1>Ceres</h1>

        <form onSubmit={onSubmit} style={{ marginTop: 'var(--s7)' }}>
          <label className="grid" style={{ gap: 'var(--s2)' }}>
            <span className="caption">Correo</span>
            <input
              type="email"
              autoComplete="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
            />
          </label>

          <label
            className="grid"
            style={{ gap: 'var(--s2)', marginTop: 'var(--s4)' }}
          >
            <span className="caption">Contraseña</span>
            <input
              type="password"
              autoComplete="current-password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
            />
          </label>

          {error && (
            <p style={{ color: 'var(--danger)', marginTop: 'var(--s4)' }}>
              {error}
            </p>
          )}

          <button
            type="submit"
            className="button--primary"
            disabled={busy}
            style={{ marginTop: 'var(--s6)', width: '100%' }}
          >
            {busy ? 'Entrando…' : 'Entrar'}
          </button>
        </form>
      </div>
    </main>
  );
}
