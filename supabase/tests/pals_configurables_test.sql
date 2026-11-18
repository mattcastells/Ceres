-- Pals configurables (migración 54): comida, actividad y peso con interruptor,
-- y la base limpiando lo que no se comparte aunque la app lo mande.
--
-- Correr con:  supabase test db

create extension if not exists pgtap with schema extensions;

begin;
select plan(12);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
)
values
  ('77777777-7777-7777-7777-777777777777',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'g@ceres.test', crypt('secreto-g', gen_salt('bf')), now(), now(), now()),
  ('88888888-8888-8888-8888-888888888888',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'h@ceres.test', crypt('secreto-h', gen_salt('bf')), now(), now(), now());

insert into public.pals (requester_id, addressee_id, status, responded_at)
values ('77777777-7777-7777-7777-777777777777',
        '88888888-8888-8888-8888-888888888888', 'accepted', now());

-- ── H publica su día con todo adentro, con los valores por defecto ───────
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"88888888-8888-8888-8888-888888888888","role":"authenticated"}', true);

insert into public.shared_days (
  user_id, local_date, meals, activity_minutes, activity_count, activities,
  water_glasses, weight_kg, weight_date
)
values (
  '88888888-8888-8888-8888-888888888888', current_date,
  jsonb_build_array(jsonb_build_object(
    'slot', 'lunch', 'name', 'Milanesa', 'kcal', 600,
    'photoPath', '88888888-8888-8888-8888-888888888888/x.jpg')),
  45, 1,
  jsonb_build_array(jsonb_build_object('name', 'Correr', 'minutes', 45)),
  6, 80.5, current_date
);

-- ── G mira ────────────────────────────────────────────────────────────────
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}', true);

select is(
  (select jsonb_array_length(meals) from public.shared_days
    where user_id = '88888888-8888-8888-8888-888888888888'),
  1, 'Por defecto la comida se comparte');

select is(
  (select meals -> 0 ->> 'photoPath' from public.shared_days
    where user_id = '88888888-8888-8888-8888-888888888888'),
  null, 'Con las fotos apagadas, la base saca la ruta aunque la app la mande');

select is(
  (select activity_minutes from public.shared_days
    where user_id = '88888888-8888-8888-8888-888888888888'),
  45, 'Por defecto el total de actividad se comparte');

select is(
  (select jsonb_array_length(activities) from public.shared_days
    where user_id = '88888888-8888-8888-8888-888888888888'),
  0, 'Sin el detalle prendido, la lista de actividades no se guarda');

select is(
  (select water_glasses from public.shared_days
    where user_id = '88888888-8888-8888-8888-888888888888'),
  null, 'El agua, apagada por defecto, no se guarda');

select is(
  (select weight_kg from public.shared_days
    where user_id = '88888888-8888-8888-8888-888888888888'),
  null, 'El peso, apagado por defecto, no se guarda');

-- ── H apaga comida y actividad, prende el peso y republica ───────────────
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"88888888-8888-8888-8888-888888888888","role":"authenticated"}', true);

update public.profiles
   set pal_share_meals = false,
       pal_share_activity = false,
       pal_share_weight = true
 where id = '88888888-8888-8888-8888-888888888888';

-- ── G, sin que H haya vuelto a publicar ──────────────────────────────────
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}', true);

select is(
  (select jsonb_array_length(meals) from public.shared_days
    where user_id = '88888888-8888-8888-8888-888888888888'),
  0, 'Apagar la comida limpia el día ya publicado, sin esperar a la app');

select is(
  (select meals_shared from public.shared_days
    where user_id = '88888888-8888-8888-8888-888888888888'),
  false, 'Y el día dice que no se comparte, no que no comió');

select is(
  (select activity_count from public.shared_days
    where user_id = '88888888-8888-8888-8888-888888888888'),
  0, 'Apagar la actividad limpia el total');

select is(
  (select activity_shared from public.shared_days
    where user_id = '88888888-8888-8888-8888-888888888888'),
  false, 'Y el día dice que la actividad no se comparte');

-- ── H republica con el peso ──────────────────────────────────────────────
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"88888888-8888-8888-8888-888888888888","role":"authenticated"}', true);

update public.shared_days
   set weight_kg = 80.5, weight_date = current_date
 where user_id = '88888888-8888-8888-8888-888888888888';

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}', true);

select is(
  (select weight_kg from public.shared_days
    where user_id = '88888888-8888-8888-8888-888888888888'),
  80.50::numeric, 'Prendido el peso, G lo ve');

select ok(
  public.pal_shares('88888888-8888-8888-8888-888888888888', 'weight')
  and not public.pal_shares('88888888-8888-8888-8888-888888888888', 'meals'),
  'pal_shares conoce las categorías nuevas');

select * from finish();
rollback;
