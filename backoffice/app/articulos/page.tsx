import { notFound } from 'next/navigation';
import { serverClient } from '@/lib/supabase';
import { fetchArticles, type CareArticle } from '@/lib/queries';
import { MainNav } from '@/components/main-nav';
import { ArticlesPanel } from '@/components/articles-panel';

export const dynamic = 'force-dynamic';

/**
 * Artículos y recetas para el equipo (migración 52).
 *
 * Se pide todo acá —lo propio y cuántos pacientes lo van a leer— y la isla de
 * cliente escribe con la sesión del navegador, como las devoluciones. Si la
 * consulta falla se dice, con el mensaje de PostgREST: una lista vacía por un
 * error se leería como "no escribiste nada".
 */
export default async function ArticulosPage() {
  const supabase = await serverClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) notFound();

  let articulos: CareArticle[] = [];
  let error: string | null = null;
  const [res, equipo] = await Promise.all([
    fetchArticles(supabase, user.id).then(
      (a) => ({ ok: true as const, a }),
      (e: unknown) => ({ ok: false as const, e: e instanceof Error ? e.message : String(e) }),
    ),
    supabase.from('care_patients').select('patient_id', { count: 'exact', head: true }),
  ]);
  if (res.ok) articulos = res.a;
  else error = res.e;

  const pacientes = equipo.error ? null : (equipo.count ?? 0);
  const publicados = articulos.filter((a) => a.published_at).length;

  return (
    <>
      <header className="topbar">
        <div className="topbar-inner topbar-inner--plain">
          <div className="topbar-id">
            <div style={{ minWidth: 0 }}>
              <h1>Artículos y recetas</h1>
              <p className="topbar-sub caption">
                {publicados} {publicados === 1 ? 'publicado' : 'publicados'}
                {pacientes !== null &&
                  ` · ${pacientes} ${pacientes === 1 ? 'paciente' : 'pacientes'}`}
              </p>
            </div>
            <MainNav actual="articulos" />
          </div>
        </div>
      </header>

      <main className="page">
        {error ? (
          <div className="card" style={{ marginTop: 'var(--s6)' }}>
            <p style={{ margin: 0 }}>No pudimos traer tus artículos.</p>
            <pre className="error-detail">{error}</pre>
          </div>
        ) : (
          <ArticlesPanel authorId={user.id} initial={articulos} />
        )}
      </main>
    </>
  );
}
