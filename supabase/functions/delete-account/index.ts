// delete-account — borrar la cuenta de verdad.
//
// Existía la pantalla, con su "escribí ELIMINAR" y su botón rojo que dice
// "Eliminar definitivamente", y lo único que hacía era cerrar sesión. Las 26
// tablas, las fotos de los tres buckets, el historial de respaldos y el usuario
// de Auth quedaban intactos — y como las tablas son la fuente de verdad, volver
// a entrar con el mismo correo **restauraba todo**. La política de privacidad
// publicada prometía lo contrario.
//
// Esta función es lo que faltaba. Hace falta que sea una Edge Function y no un
// RPC porque borrar de `auth.users` necesita la secret key, y esa clave no
// puede vivir en el APK: solo en los secretos del proyecto.
//
// ## El orden importa
//
// Primero Storage, después la cuenta. Al revés, si el borrado de los objetos
// falla a la mitad, quedan fotos de comida y de progreso —el dato más sensible
// que guarda la app— en buckets cuyo dueño ya no existe: nadie las lista, nadie
// las reclama y nadie las borra nunca más.
//
// Por eso, si Storage falla, la función **aborta y no toca la cuenta**. Que
// haya que reintentar es peor experiencia que un borrado a medias, pero un
// borrado a medias sobre datos de salud no es una opción.
//
// El resto de las tablas no se tocan a mano: `profiles.id` referencia
// `auth.users(id) on delete cascade`, y las 25 tablas restantes cuelgan de
// `profiles` con la misma regla. Borrar el usuario las vacía a todas.

import { createClient, type SupabaseClient } from 'jsr:@supabase/supabase-js@2';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
};

/** Los cuatro buckets: los tres de fotos (migración 18) y el de respaldos (19). */
const BUCKETS = ['meal-photos', 'activity-photos', 'progress-photos', 'backups'];

/**
 * Cuántos niveles de carpeta se recorren debajo de `{uid}/`.
 *
 * Hoy hace falta uno solo: las fotos son `{uid}/{id}.jpg` y los respaldos
 * `{uid}/backup.json` más `{uid}/history/backup-<fecha>.json`. El tope está
 * para que un prefijo inesperado no convierta esto en una recursión sin fondo.
 */
const MAX_DEPTH = 3;

function fail(code: string, message: string, status = 400): Response {
  return new Response(
    JSON.stringify({ error: { code, message } }),
    { status, headers: { ...CORS, 'Content-Type': 'application/json' } },
  );
}

/**
 * Junta las rutas de todo lo que cuelga de [prefix], entrando en las carpetas.
 *
 * `list()` devuelve archivos y carpetas mezclados y los distingue por `id`:
 * una carpeta no tiene. Es la única forma de saberlo con esta API.
 */
const PAGE = 1000;

async function listAll(
  admin: SupabaseClient,
  bucket: string,
  prefix: string,
  depth = 0,
): Promise<string[]> {
  if (depth >= MAX_DEPTH) return [];

  // Paginado: `list` devuelve como mucho [PAGE] entradas, y las fotos viven
  // todas planas en `userId/`. Con una sola página, quien tenía más de mil
  // fotos se iba con la cuenta borrada y el resto de sus fotos en el bucket,
  // sin dueño y sin forma de encontrarlas.
  const paths: string[] = [];
  for (let offset = 0; ; offset += PAGE) {
    const { data, error } = await admin.storage
      .from(bucket)
      .list(prefix, { limit: PAGE, offset });
    if (error) throw new Error(`${bucket}/${prefix}: ${error.message}`);
    if (!data || data.length === 0) break;

    for (const entry of data) {
      const full = `${prefix}/${entry.name}`;
      if (entry.id === null) {
        paths.push(...await listAll(admin, bucket, full, depth + 1));
      } else {
        paths.push(full);
      }
    }
    if (data.length < PAGE) break;
  }
  return paths;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return fail('ERR_UNAUTHENTICATED', 'Falta la sesión.', 401);

  const secretKey = Deno.env.get('SUPABASE_SECRET_KEY') ??
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!secretKey) {
    return fail(
      'ERR_PROVIDER_UNAVAILABLE',
      'El borrado de cuenta no está configurado en el servidor.',
      503,
    );
  }

  const url = Deno.env.get('SUPABASE_URL')!;

  // Quién pide el borrado se resuelve con **su** JWT, nunca con lo que venga en
  // el cuerpo: una función que borra cuentas no puede aceptar a quién borrar
  // como parámetro.
  const caller = createClient(
    url,
    Deno.env.get('SUPABASE_PUBLISHABLE_KEY') ?? Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: userData, error: userError } = await caller.auth.getUser();
  const user = userData?.user;
  if (userError || !user) {
    return fail('ERR_UNAUTHENTICATED', 'Tu sesión venció.', 401);
  }

  const admin = createClient(url, secretKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // ── 1 · Storage ────────────────────────────────────────────────────────
  for (const bucket of BUCKETS) {
    try {
      const paths = await listAll(admin, bucket, user.id);
      if (paths.length === 0) continue;

      // De a [PAGE] por llamada: la API de Storage no borra lotes sin techo.
      for (let i = 0; i < paths.length; i += PAGE) {
        const { error } = await admin.storage.from(bucket).remove(paths.slice(i, i + PAGE));
        if (error) throw new Error(error.message);
      }
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      console.error(`delete-account: falló ${bucket}:`, detail);
      return fail(
        'ERR_DELETE_INCOMPLETE',
        'No pudimos borrar tus fotos, así que no borramos la cuenta: quedaría ' +
          'a medias. Probá de nuevo en un rato.',
        502,
      );
    }
  }

  // ── 2 · La cuenta, y con ella las 26 tablas por cascada ────────────────
  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteError) {
    console.error('delete-account: falló deleteUser:', deleteError.message);
    return fail(
      'ERR_SERVER',
      'No pudimos borrar la cuenta. Probá de nuevo en un rato.',
      500,
    );
  }

  return new Response(
    JSON.stringify({ deleted: true }),
    { headers: { ...CORS, 'Content-Type': 'application/json' } },
  );
});
