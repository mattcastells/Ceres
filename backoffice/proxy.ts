import { createServerClient, type CookieOptions } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';

type CookieToSet = { name: string; value: string; options: CookieOptions };

/**
 * Refresca la sesión y saca de las páginas a quien no entró.
 *
 * El guard de acá es de **navegación**, no de seguridad: quien tenga sesión
 * válida pero ningún permiso vigente puede llegar a las páginas y no va a ver
 * nada, porque lo que decide qué datos vuelven son las políticas de Postgres.
 * Un middleware que se rompa no filtra nada; solo deja pasar a una pantalla
 * vacía.
 */
export async function middleware(request: NextRequest) {
  let response = NextResponse.next({ request });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    {
      cookies: {
        getAll: () => request.cookies.getAll(),
        setAll: (list: CookieToSet[]) => {
          list.forEach(({ name, value }) =>
            request.cookies.set(name, value),
          );
          response = NextResponse.next({ request });
          list.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options),
          );
        },
      },
    },
  );

  // `getUser` y no `getSession`: el segundo lee la cookie y le cree. Este
  // valida el token contra el servidor de auth, que es lo que corresponde
  // cuando de eso depende dejar pasar.
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const isLogin = request.nextUrl.pathname.startsWith('/login');

  if (!user && !isLogin) {
    const url = request.nextUrl.clone();
    url.pathname = '/login';
    return NextResponse.redirect(url);
  }

  if (user && isLogin) {
    const url = request.nextUrl.clone();
    url.pathname = '/';
    return NextResponse.redirect(url);
  }

  return response;
}

/**
 * `preview` está excluido para poder mirar el diseño con datos de ejemplo sin
 * una sesión (`app/preview/`).
 *
 * Que esté acá **no la deja abierta en producción**: esas rutas devuelven 404
 * cuando `NODE_ENV` es `production`, y ese es el guard que importa. Este
 * `matcher` solo evita el redirect al login en desarrollo, que es donde la ruta
 * existe. Los dos están separados a propósito: sacar esta línea no habilita
 * nada, y sacar el guard de allá tampoco alcanza para exponerla desde acá.
 */
export const config = {
  matcher: ['/((?!preview|_next/static|_next/image|favicon.ico).*)'],
};
