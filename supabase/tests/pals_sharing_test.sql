-- Suite de privacidad por categoría en Pals (migración 25).
--
-- Antes de esta migración, lo que había en `shared_days` (comida + agregado
-- de actividad) era lo único que existía del lado del servidor para un pal, y
-- no había forma de elegir. Ahora agua, sueño y fotos también pueden viajar,
-- pero **apagados por default** y solo si quien comparte los prende. Esto
-- prueba las tres puertas nuevas — y que prender el interruptor no alcanza
-- por sí solo para una foto: también tiene que estar publicada y ser reciente.
--
-- Correr con:  supabase test db

create extension if not exists pgtap with schema extensions;

begin;
select plan(8);

-- ── A y B, ya pals aceptados ──────────────────────────────────────────────
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
)
values
  ('55555555-5555-5555-5555-555555555555',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'e@ceres.test', crypt('secreto-e', gen_salt('bf')), now(), now(), now()),
  ('66666666-6666-6666-6666-666666666666',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'f@ceres.test', crypt('secreto-f', gen_salt('bf')), now(), now(), now());

insert into public.pals (requester_id, addressee_id, status, responded_at)
values (
  '55555555-5555-5555-5555-555555555555',
  '66666666-6666-6666-6666-666666666666',
  'accepted', now()
);

-- ── Datos de B: agua, sueño, y dos comidas con foto en días distintos ────
insert into public.water_logs (id, user_id, local_date, glasses)
values (gen_random_uuid(), '66666666-6666-6666-6666-666666666666', current_date, 6);

insert into public.sleep_logs (id, user_id, local_date, minutes, quality)
values (gen_random_uuid(), '66666666-6666-6666-6666-666666666666', current_date, 420, 'good');

insert into storage.objects (bucket_id, name, owner)
values
  ('meal-photos',
   '66666666-6666-6666-6666-666666666666/hoy.jpg',
   '66666666-6666-6666-6666-666666666666'),
  ('meal-photos',
   '66666666-6666-6666-6666-666666666666/no-publicada.jpg',
   '66666666-6666-6666-6666-666666666666'),
  ('meal-photos',
   '66666666-6666-6666-6666-666666666666/vieja.jpg',
   '66666666-6666-6666-6666-666666666666');

-- Hoy, con una comida que sí tiene foto — "no-publicada.jpg" adrede no entra
-- en ningún `shared_days`, para probar que el toggle solo no alcanza.
insert into public.shared_days (user_id, local_date, meals)
values (
  '66666666-6666-6666-6666-666666666666', current_date,
  jsonb_build_array(
    jsonb_build_object('slot', 'lunch', 'name', 'Milanesa', 'kcal', 600,
                        'photoPath', '66666666-6666-6666-6666-666666666666/hoy.jpg')
  )
);

-- Hace 10 días, con la tercera foto — para probar la ventana de 7 días.
insert into public.shared_days (user_id, local_date, meals)
values (
  '66666666-6666-6666-6666-666666666666', current_date - 10,
  jsonb_build_array(
    jsonb_build_object('slot', 'dinner', 'name', 'Pizza', 'kcal', 800,
                        'photoPath', '66666666-6666-6666-6666-666666666666/vieja.jpg')
  )
);

-- ── A, antes de que B prenda nada ─────────────────────────────────────────
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated"}', true);

select is(
  (select count(*)::int from public.water_logs
    where user_id = '66666666-6666-6666-6666-666666666666'),
  0,
  'Con el toggle apagado, A no ve el agua de B'
);

select is(
  (select count(*)::int from public.sleep_logs
    where user_id = '66666666-6666-6666-6666-666666666666'),
  0,
  'Con el toggle apagado, A no ve el sueño de B'
);

select is(
  (select count(*)::int from storage.objects
    where name = '66666666-6666-6666-6666-666666666666/hoy.jpg'),
  0,
  'Con el toggle apagado, A no ve la foto de B aunque esté publicada'
);

-- ── B prende los tres interruptores ───────────────────────────────────────
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}', true);

update public.profiles
   set pal_share_water = true,
       pal_share_sleep = true,
       pal_share_photos = true
 where id = '66666666-6666-6666-6666-666666666666';

-- ── A, con los interruptores prendidos ────────────────────────────────────
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated"}', true);

select is(
  (select glasses::int from public.water_logs
    where user_id = '66666666-6666-6666-6666-666666666666'),
  6,
  'Prendido el agua, A ve los vasos de B'
);

select is(
  (select quality from public.sleep_logs
    where user_id = '66666666-6666-6666-6666-666666666666'),
  'good',
  'Prendido el sueño, A ve cómo durmió B'
);

select is(
  (select count(*)::int from storage.objects
    where name = '66666666-6666-6666-6666-666666666666/hoy.jpg'),
  1,
  'Prendidas las fotos, A ve la que B publicó hoy'
);

select is(
  (select count(*)::int from storage.objects
    where name = '66666666-6666-6666-6666-666666666666/no-publicada.jpg'),
  0,
  'El toggle prendido no alcanza: la que B nunca publicó sigue invisible'
);

select is(
  (select count(*)::int from storage.objects
    where name = '66666666-6666-6666-6666-666666666666/vieja.jpg'),
  0,
  'Publicada hace 10 días, fuera de la ventana de 7: sigue invisible'
);

select * from finish();
rollback;
