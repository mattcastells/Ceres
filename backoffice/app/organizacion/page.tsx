import Link from 'next/link';
import { serverClient } from '@/lib/supabase';
import { OrgView, type OrgRow } from '@/components/org-view';

export const dynamic = 'force-dynamic';

/**
 * La organización de quien mira, si tiene una.
 *
 * El enlace del encabezado aparece solo cuando `my_organization()` devuelve
 * filas; si alguien llega acá igual —un enlace viejo, una URL tipeada—, se le
 * dice que no es parte de ninguna en vez de un 404, que se leería como un
 * error del panel.
 */
export default async function OrganizacionPage() {
  const supabase = await serverClient();
  const [{ data, error }, { data: auth }] = await Promise.all([
    supabase.rpc('my_organization'),
    supabase.auth.getUser(),
  ]);

  const rows = (data ?? []) as OrgRow[];

  if (error || rows.length === 0) {
    return (
      <main className="page">
        <p className="topbar-back caption">
          <Link href="/">← Tu equipo</Link>
        </p>
        <h1 style={{ marginTop: 'var(--s4)' }}>Organización</h1>
        <div className="card" style={{ marginTop: 'var(--s5)' }}>
          {error ? (
            <>
              <p style={{ margin: 0 }}>No pudimos traer los datos de la organización.</p>
              <pre className="error-detail">{error.message}</pre>
            </>
          ) : (
            <p className="muted" style={{ margin: 0 }}>
              Tu cuenta no es parte de ninguna organización.
            </p>
          )}
        </div>
      </main>
    );
  }

  return <OrgView rows={rows} viewerId={auth.user?.id ?? null} />;
}
