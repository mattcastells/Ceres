-- Suite de Pals.
--
-- Lo que se verifica no es que la app muestre poco, sino que el servidor **no
-- tenga más para dar**. Un pal aceptado tiene que poder leer `shared_days` y
-- nada más: ni comidas, ni peso, ni medidas, ni actividades.
--
-- Correr con:  supabase test db

create extension if not exists pgtap with schema extensions;

begin;
select plan(19);

-- ── Tres usuarios: A y B se hacen pals, C queda afuera ───────────────────
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
)
values
  ('11111111-1111-1111-1111-111111111111',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'a@ceres.test', crypt('secreto-a', gen_salt('bf')), now(), now(), now()),
  ('22222222-2222-2222-2222-222222222222',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'b@ceres.test', crypt('secreto-b', gen_salt('bf')), now(), now(), now()),
  ('33333333-3333-3333-3333-333333333333',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'c@ceres.test', crypt('secreto-c', gen_salt('bf')), now(), now(), now());

-- ── Auditoría en profiles ────────────────────────────────────────────────
-- La migración 13 resolvía el dueño con `new.user_id` dentro de un CASE, y
-- PL/pgSQL resuelve todos los campos al planificar: cualquier update a
-- `profiles` moría con "record new has no field user_id". Se escondió porque
-- la app guarda el perfil en el teléfono y nunca escribe esta tabla.
select lives_ok(
  $q$update public.profiles set display_name = 'Ana'
      where id = '11111111-1111-1111-1111-111111111111'$q$,
  'Actualizar un perfil no rompe el trigger de auditoría'
);

select is(
  (select count(*)::int from public.audit_log
    where table_name = 'profiles'
      and user_id = '11111111-1111-1111-1111-111111111111'),
  1,
  'El cambio de perfil queda auditado a nombre de su dueño'
);

-- ── El código se genera solo y es único ──────────────────────────────────
select isnt(
  (select pal_code from public.profiles
    where id = '11111111-1111-1111-1111-111111111111'),
  null,
  'El alta genera un código de pal'
);

-- Acotado a los tres usuarios del test y no a `profiles` entera: contar toda
-- la tabla daba por sentado que la base arranca vacía, así que el test se ponía
-- rojo con cualquier fila previa —correr la suite contra una base con datos, que
-- es justo lo que uno hace para probar una migración de subida— y el mensaje
-- ("have 4, want 3") no dice en ningún lado que el problema es el vecino.
select is(
  (select count(distinct pal_code)::int from public.profiles
    where id in ('11111111-1111-1111-1111-111111111111',
                 '22222222-2222-2222-2222-222222222222',
                 '33333333-3333-3333-3333-333333333333')),
  3,
  'Los códigos no se repiten'
);

select matches(
  (select pal_code from public.profiles
    where id = '11111111-1111-1111-1111-111111111111'),
  '^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{8}$',
  'El código evita los caracteres que se confunden al dictarlo'
);

-- ── Días compartidos de cada uno ─────────────────────────────────────────
insert into public.shared_days (user_id, local_date, meals, activity_minutes, activity_count)
values
  ('11111111-1111-1111-1111-111111111111', current_date,
   '[{"slot":"breakfast","name":"Café con leche","kcal":180}]'::jsonb, 30, 1),
  ('22222222-2222-2222-2222-222222222222', current_date,
   '[{"slot":"lunch","name":"Milanesa","kcal":620}]'::jsonb, 0, 0),
  ('33333333-3333-3333-3333-333333333333', current_date,
   '[{"slot":"dinner","name":"Ensalada","kcal":300}]'::jsonb, 45, 2);

-- Datos privados de B, cargados como service_role. Son los que un pal **no**
-- tiene que poder ver aunque el vínculo esté aceptado.
insert into public.weight_logs (id, user_id, weight_kg, local_date)
values ('dddd0001-0000-4000-8000-000000000001',
        '22222222-2222-2222-2222-222222222222', 80, current_date);

insert into public.meals (id, user_id, slot, local_date, source)
values ('dddd0002-0000-4000-8000-000000000002',
        '22222222-2222-2222-2222-222222222222', 'lunch', current_date, 'manual');

insert into public.body_measurements (id, user_id, metric, value, local_date)
values ('dddd0003-0000-4000-8000-000000000003',
        '22222222-2222-2222-2222-222222222222', 'waist', 84, current_date);

-- Los códigos se guardan **antes** de asumir una identidad: una vez bajo RLS,
-- el propio test no puede leer el perfil ajeno — que es justamente lo que se
-- quiere. Por eso agregarse es por código y no buscando en `profiles`.
create temporary table codigos on commit drop as
  select id, pal_code from public.profiles;
grant select on codigos to authenticated;

-- ── A pide y B todavía no aceptó ─────────────────────────────────────────
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

select is(
  public.request_pal(
    (select pal_code from codigos
      where id = '22222222-2222-2222-2222-222222222222')),
  'sent',
  'A le manda una solicitud a B por código'
);

select is(
  public.request_pal('ZZZZZZZZ'),
  'not_found',
  'Un código inexistente no dice nada más que "no está"'
);

select is(
  public.request_pal(
    (select pal_code from codigos
      where id = '11111111-1111-1111-1111-111111111111')),
  'self',
  'Nadie puede agregarse a sí mismo'
);

select is(
  public.request_pal(
    (select pal_code from codigos
      where id = '22222222-2222-2222-2222-222222222222')),
  'already',
  'La solicitud repetida no crea un vínculo duplicado'
);

-- Con la solicitud pendiente todavía no se ve el día del otro.
select is(
  (select count(*)::int from public.shared_days
    where user_id = '22222222-2222-2222-2222-222222222222'),
  0,
  'Pendiente no alcanza: A no ve el día de B'
);

-- ── B acepta ─────────────────────────────────────────────────────────────
select set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);

update public.pals set status = 'accepted', responded_at = now()
 where requester_id = '11111111-1111-1111-1111-111111111111'
   and addressee_id = '22222222-2222-2222-2222-222222222222';

select is(
  (select count(*)::int from public.pals where status = 'accepted'),
  1,
  'B acepta la solicitud'
);

-- ── Ya como pals ─────────────────────────────────────────────────────────
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

select is(
  (select (meals -> 0 ->> 'name') from public.shared_days
    where user_id = '22222222-2222-2222-2222-222222222222'),
  'Milanesa',
  'A ve lo que comió B'
);

select is(
  (select count(*)::int from public.shared_days
    where user_id = '33333333-3333-3333-3333-333333333333'),
  0,
  'El día de C, que no es pal de nadie, sigue invisible'
);

-- ── Lo que un pal NO puede ver ───────────────────────────────────────────
-- Esta es la parte que importa: el vínculo abre `shared_days` y nada más.
select is(
  (select count(*)::int from public.weight_logs
    where user_id = '22222222-2222-2222-2222-222222222222'),
  0,
  'Ser pal no abre el peso'
);

select is(
  (select count(*)::int from public.meals
    where user_id = '22222222-2222-2222-2222-222222222222'),
  0,
  'Ser pal no abre las comidas con su detalle'
);

select is(
  (select count(*)::int from public.body_measurements
    where user_id = '22222222-2222-2222-2222-222222222222'),
  0,
  'Ser pal no abre las medidas corporales'
);

-- ── Escritura ────────────────────────────────────────────────────────────
-- Un UPDATE que RLS filtra **no lanza error**: simplemente no alcanza ninguna
-- fila. Por eso se verifica el resultado y no la excepción — esperar un error
-- acá daría un test verde por el motivo equivocado el día que la policy se
-- rompa y el update sí pase.
update public.shared_days set activity_minutes = 999
 where user_id = '22222222-2222-2222-2222-222222222222';

select is(
  (select activity_minutes from public.shared_days
    where user_id = '22222222-2222-2222-2222-222222222222'),
  0,
  'El intento de escribir en el día del pal no cambió nada'
);

select throws_ok(
  $$insert into public.pals (requester_id, addressee_id)
    values ('33333333-3333-3333-3333-333333333333',
            '22222222-2222-2222-2222-222222222222')$$,
  '42501',
  null,
  'Nadie puede pedir un vínculo a nombre de otro'
);

-- ── Al deshacer el vínculo se cierra el acceso ───────────────────────────
delete from public.pals
 where requester_id = '11111111-1111-1111-1111-111111111111';

select is(
  (select count(*)::int from public.shared_days
    where user_id = '22222222-2222-2222-2222-222222222222'),
  0,
  'Sacado el vínculo, A deja de ver el día de B'
);

select * from finish();
rollback;
