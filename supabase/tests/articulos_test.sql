-- Artículos y recetas de la profesional (migración 52).
--
--   1. Un borrador es de quien lo escribe: ni su paciente lo ve.
--   2. Publicado, lo ve su paciente —sin ninguna categoría prendida— y no una
--      desconocida ni el paciente de otra profesional.
--   3. Nadie edita el artículo de otra, y no se borra de verdad.
--   4. Borrado o con el acceso cortado, el paciente deja de verlo.
--   5. La limpieza diaria se lo lleva a los 30 días.
--
-- Correr con:  supabase test db

create extension if not exists pgtap with schema extensions;

begin;
select plan(14);

-- Nutri (profesional), Ana (su paciente, sin categorías), Otra (otra
-- profesional) y Beto (paciente de Otra).
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'ana@ceres.test', crypt('x', gen_salt('bf')), now(), now(), now()),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'nutri@ceres.test', crypt('x', gen_salt('bf')), now(), now(), now()),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'otra@ceres.test', crypt('x', gen_salt('bf')), now(), now(), now()),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'beto@ceres.test', crypt('x', gen_salt('bf')), now(), now(), now());

-- Ana le dio acceso a Nutri **sin ninguna categoría**: leer lo que publica su
-- nutricionista no depende de qué datos le comparte.
insert into public.care_grants (owner_id, professional_id, status, accepted_at)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'accepted', now()),
       ('dddddddd-dddd-dddd-dddd-dddddddddddd',
        'cccccccc-cccc-cccc-cccc-cccccccccccc', 'accepted', now());

set local role authenticated;

-- ── Nutri escribe un borrador ────────────────────────────────────────────
select set_config('request.jwt.claims',
  '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}', true);

insert into public.care_articles (id, author_id, kind, title, body, tag)
values ('eeeeeeee-0000-0000-0000-000000000001',
        'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'recipe',
        'Budín de avena', 'Mezclar avena, banana y huevo. Horno 25 min.', 'Desayunos');

select is(
  (select count(*)::int from public.care_articles),
  1,
  'La profesional ve su borrador'
);

select throws_ok(
  $$insert into public.care_articles (author_id, title, body)
    values ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'Ajeno', 'No')$$,
  '42501', null,
  'No se escribe un artículo a nombre de otra'
);

select throws_ok(
  $$insert into public.care_articles (author_id, kind, title, body)
    values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'video', 'X', 'Y')$$,
  '23514', null,
  'El tipo es artículo o receta'
);

select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}', true);

select is(
  (select count(*)::int from public.care_articles),
  0,
  'Ana NO ve un borrador'
);

-- ── Publicado ────────────────────────────────────────────────────────────
select set_config('request.jwt.claims',
  '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}', true);

update public.care_articles set published_at = now()
 where id = 'eeeeeeee-0000-0000-0000-000000000001';

select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}', true);

select is(
  (select title from public.care_articles
    where published_at is not null and deleted_at is null),
  'Budín de avena',
  'Publicado, Ana lo ve aunque no comparta ninguna categoría'
);

update public.care_articles set title = 'otra cosa'
 where id = 'eeeeeeee-0000-0000-0000-000000000001';

select is(
  (select title from public.care_articles
    where id = 'eeeeeeee-0000-0000-0000-000000000001'),
  'Budín de avena',
  'Ana no puede editarlo'
);

select set_config('request.jwt.claims',
  '{"sub":"dddddddd-dddd-dddd-dddd-dddddddddddd","role":"authenticated"}', true);

select is(
  (select count(*)::int from public.care_articles),
  0,
  'El paciente de otra profesional no lo ve'
);

select set_config('request.jwt.claims',
  '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}', true);

select is(
  (select count(*)::int from public.care_articles),
  0,
  'Otra profesional tampoco'
);

update public.care_articles set deleted_at = now()
 where id = 'eeeeeeee-0000-0000-0000-000000000001';

-- ── Borrar ───────────────────────────────────────────────────────────────
select set_config('request.jwt.claims',
  '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}', true);

select is(
  (select deleted_at from public.care_articles
    where id = 'eeeeeeee-0000-0000-0000-000000000001'),
  null,
  'Otra profesional no puede borrarlo'
);

delete from public.care_articles where id = 'eeeeeeee-0000-0000-0000-000000000001';

select is(
  (select count(*)::int from public.care_articles),
  1,
  'Un DELETE no borra: el borrado es deleted_at'
);

update public.care_articles set deleted_at = now()
 where id = 'eeeeeeee-0000-0000-0000-000000000001';

select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}', true);

select is(
  (select count(*)::int from public.care_articles),
  0,
  'Borrado, Ana deja de verlo'
);

-- ── Cortar el acceso corta la lectura ────────────────────────────────────
select set_config('request.jwt.claims',
  '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}', true);

insert into public.care_articles (id, author_id, title, body, published_at)
values ('eeeeeeee-0000-0000-0000-000000000002',
        'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        'La vianda de la semana', 'Cociná dos bases y combiná.', now());

select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}', true);

select is(
  (select count(*)::int from public.care_articles),
  1,
  'Ana ve el artículo nuevo'
);

select public.revoke_care_access(
  (select id from public.care_grants
    where owner_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'));

select is(
  (select count(*)::int from public.care_articles),
  0,
  'Con el acceso cortado, deja de verlo'
);

-- ── La limpieza diaria ───────────────────────────────────────────────────
-- Corre como el job nocturno: sin sesión de nadie.
reset role;
select set_config('request.jwt.claims', '', true);
update public.care_articles set deleted_at = now() - interval '31 days'
 where id = 'eeeeeeee-0000-0000-0000-000000000001';
select public.purge_soft_deleted();

-- Por id: sin rol, `count(*)` también contaría lo que haya en la base.
select is(
  (select count(*)::int from public.care_articles
    where id in ('eeeeeeee-0000-0000-0000-000000000001',
                 'eeeeeeee-0000-0000-0000-000000000002')),
  1,
  'La purga se lleva el artículo borrado hace más de 30 días, y solo ese'
);

select * from finish();
rollback;
