import { createServerClient, type CookieOptions } from '@supabase/ssr';
import { cookies } from 'next/headers';

type CookieToSet = { name: string; value: string; options: CookieOptions };

/**
 * Cliente para Server Components y Route Handlers.
 *
 * Lee la sesión de las cookies que escribe el proxy (`proxy.ts`). En un Server
 * Component las cookies son de solo lectura, así que `setAll` no hace nada: el
 * refresh del token lo hace el proxy, que sí puede escribirlas.
 *
 * El cliente del navegador vive en `supabase-browser.ts`, aparte, porque el
 * `next/headers` de acá no se puede resolver en un Client Component.
 *
 * En los dos casos se entra con la **publishable key** y la sesión de quien
 * mira. No hay service-role key en ningún lado de este proyecto: esa clave
 * saltea RLS, así que en un frontend —o en una variable de entorno de Vercel
 * que cualquiera con acceso al proyecto puede leer— es una llave maestra a los
 * datos de todos. Con la publishable, si mañana hay un bug acá, la base sigue
 * sin devolver lo que el paciente no concedió.
 */
export async function serverClient() {
  const store = await cookies();
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    {
      cookies: {
        getAll: () => store.getAll(),
        setAll: (list: CookieToSet[]) => {
          try {
            list.forEach(({ name, value, options }) =>
              store.set(name, value, options),
            );
          } catch {
            // Server Component: lo resuelve el proxy.
          }
        },
      },
    },
  );
}
