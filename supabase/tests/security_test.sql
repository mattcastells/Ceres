-- Suite de hardening (migración 24).
--
-- Dos cosas: que los jobs de mantenimiento no sean invocables por cualquier
-- cuenta, y que `check_rate_limit` sea de verdad lo único que puede tocar
-- `rate_limits` —ni lectura ni escritura directa desde `authenticated`.
--
-- Correr con:  supabase test db

create extension if not exists pgtap with schema extensions;

begin;
select plan(9);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
)
values
  ('44444444-4444-4444-4444-444444444444',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'd@ceres.test', crypt('secreto-d', gen_salt('bf')), now(), now(), now());

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated"}', true);

-- ── Los jobs de mantenimiento no son de nadie más que de pg_cron ─────────
select throws_ok(
  $$select public.purge_soft_deleted()$$,
  '42501',
  null,
  'Ninguna cuenta puede disparar la purga de borrados'
);

-- `expire_food_cache` y `trim_recents` tenían su propia comprobación acá. Las
-- dos funciones se fueron con la migración 43, junto con las tablas que
-- limpiaban: nadie las leía nunca. Un test de permisos sobre una función que no
-- existe no protege nada.

select throws_ok(
  $$select public.purge_audit_log()$$,
  '42501',
  null,
  'Ninguna cuenta puede purgar la auditoría a mano'
);

-- La quinta llegó después que esta lista y nació abierta: una función nueva
-- trae `execute` para `public`, y la migración 23 revoca **una por una**, así
-- que no heredó nada. Estuvo un rato en producción pudiendo borrarle los días
-- compartidos a cualquiera desde cualquier sesión. Que esté acá es lo que hace
-- que la próxima que se agregue no repita el olvido.
select throws_ok(
  $$select public.purge_shared_days()$$,
  '42501',
  null,
  'Ninguna cuenta puede purgar los días compartidos a mano'
);

-- ── `rate_limits` no se lee ni se escribe directo ────────────────────────
select is(
  public.check_rate_limit('food_search', 2),
  true,
  'Primer uso del día: dentro del límite'
);

select is(
  public.check_rate_limit('food_search', 2),
  true,
  'Segundo uso: todavía dentro del límite'
);

select is(
  public.check_rate_limit('food_search', 2),
  false,
  'Tercer uso: ya pasó el límite'
);

-- Sin política de select, la fila que `check_rate_limit` sí escribió (como
-- `security definer`) queda invisible para la propia cuenta que la generó.
select is(
  (select count(*)::int from public.rate_limits
    where user_id = '44444444-4444-4444-4444-444444444444'),
  0,
  'La cuenta no puede leer su propio contador directo, solo por la función'
);

-- ── El bucket no lo elige el cliente ─────────────────────────────────────
-- `p_bucket` era texto libre, así que una cuenta podía llamar la función con un
-- nombre distinto cada vez y crear filas ilimitadas en `rate_limits`, que
-- además no purgaba nadie. Los tres nombres válidos salen de las Edge
-- Functions y de `request_pal`; agregar una cuota nueva pasa por una migración,
-- que es donde se ve.
select throws_ok(
  $$select public.check_rate_limit('inventado', 5)$$,
  '23514',
  null,
  'Un bucket que no existe no crea una fila: la función rechaza'
);

select is(
  (select count(*)::int from public.rate_limits where bucket = 'inventado'),
  0,
  'Y por lo tanto no queda nada suelto en la tabla'
);

select * from finish();
rollback;
