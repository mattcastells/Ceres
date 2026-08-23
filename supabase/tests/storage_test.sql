-- Suite de Storage (08-supabase-plan.md §3).
--
-- Misma lógica que rls_test.sql pero sobre `storage.objects`: con el JWT del
-- usuario A se intenta leer y escribir en la carpeta de B. Se espera 0 filas o
-- error en todos los casos.
--
-- Acá la seguridad depende de una **convención de rutas**: la primera carpeta
-- del nombre es el `user_id`. Si esa convención se rompiera en el cliente, las
-- políticas dejarían de proteger nada, así que se verifica que se cumpla.
--
-- Correr con:  supabase test db

create extension if not exists pgtap with schema extensions;

begin;
select plan(9);

-- ── Dos usuarios de prueba ───────────────────────────────────────────────
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
   'b@ceres.test', crypt('secreto-b', gen_salt('bf')), now(), now(), now());

-- ── Los buckets existen y son privados ───────────────────────────────────
select is(
  (select count(*)::int from storage.buckets
    where id in ('meal-photos', 'activity-photos', 'progress-photos')),
  3,
  'Los tres buckets de la §3 existen'
);

select is(
  (select count(*)::int from storage.buckets
    where id in ('meal-photos', 'activity-photos', 'progress-photos')
      and public),
  0,
  'Ninguno es público: las fotos se sirven con URL firmada'
);

select is(
  (select count(*)::int from storage.buckets
    where id in ('meal-photos', 'activity-photos', 'progress-photos')
      and file_size_limit = 8388608),
  3,
  'Los tres topean en 8 MB'
);

-- ── Un objeto de cada uno, como service_role (saltea RLS) ────────────────
insert into storage.objects (bucket_id, name, owner)
values
  ('meal-photos',
   '11111111-1111-1111-1111-111111111111/aaaa0001.jpg',
   '11111111-1111-1111-1111-111111111111'),
  ('meal-photos',
   '22222222-2222-2222-2222-222222222222/bbbb0001.jpg',
   '22222222-2222-2222-2222-222222222222'),
  ('progress-photos',
   '22222222-2222-2222-2222-222222222222/bbbb0002.jpg',
   '22222222-2222-2222-2222-222222222222');

-- ── A partir de acá, todo con el JWT del usuario A ───────────────────────
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}',
  true);

select is(
  (select count(*)::int from storage.objects where bucket_id = 'meal-photos'),
  1,
  'A ve una sola foto de comida: la suya'
);

select is(
  (select count(*)::int from storage.objects
    where name = '22222222-2222-2222-2222-222222222222/bbbb0001.jpg'),
  0,
  'La foto de B es invisible para A aun pidiéndola por ruta exacta'
);

select is(
  (select count(*)::int from storage.objects
    where bucket_id = 'progress-photos'),
  0,
  'La política vale igual en progress-photos'
);

-- ── Escritura ────────────────────────────────────────────────────────────
-- Sin `with check` esto pasaría: A no puede *ver* la carpeta de B, pero nada
-- le impediría escribir adentro. Por eso las políticas llevan las dos mitades.
select throws_ok(
  $$insert into storage.objects (bucket_id, name, owner)
    values ('meal-photos',
            '22222222-2222-2222-2222-222222222222/intruso.jpg',
            '11111111-1111-1111-1111-111111111111')$$,
  '42501',
  null,
  'A no puede escribir dentro de la carpeta de B'
);

select lives_ok(
  $$insert into storage.objects (bucket_id, name, owner)
    values ('meal-photos',
            '11111111-1111-1111-1111-111111111111/aaaa0002.jpg',
            '11111111-1111-1111-1111-111111111111')$$,
  'A sí puede escribir en la suya'
);

-- Una ruta sin carpeta no tiene dueño deducible: no debe entrar nunca.
select throws_ok(
  $$insert into storage.objects (bucket_id, name, owner)
    values ('meal-photos', 'suelta.jpg',
            '11111111-1111-1111-1111-111111111111')$$,
  '42501',
  null,
  'Una foto sin carpeta de usuario queda afuera'
);

select * from finish();
rollback;
