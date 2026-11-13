-- El objetivo recomendado (migración 53).
--
--   1. Es una indicación con números: una devolución no los lleva, y un macro
--      sin calorías tampoco.
--   2. Los topes son los de `goals`: no se recomienda lo que la app no podría
--      guardar.
--   3. "Leída" y "aplicado" son del paciente: la profesional no los escribe ni
--      en sus propias filas, y el paciente solo por función.
--   4. La profesional sigue sin poder tocar `goals`.
--
-- Correr con:  supabase test db

create extension if not exists pgtap with schema extensions;

begin;
select plan(13);

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
   'nutri@ceres.test', crypt('x', gen_salt('bf')), now(), now(), now());

insert into public.care_grants (owner_id, professional_id, status, share_meals, accepted_at)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'accepted', true, now());

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}', true);

-- ── La forma ─────────────────────────────────────────────────────────────
select lives_ok(
  $$insert into public.care_feedback (
      id, author_id, patient_id, kind, body,
      target_kcal, target_protein_g, target_carbs_g, target_fat_g, published_at)
    values ('eeeeeeee-0000-0000-0000-000000000001',
            'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
            'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'indication',
            'Objetivo recomendado: 1.600 kcal por día.', 1600, 95, 180, 55, now())$$,
  'La profesional publica un objetivo recomendado'
);

select lives_ok(
  $$insert into public.care_feedback (author_id, patient_id, kind, body, target_kcal)
    values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
            'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'indication',
            'Solo calorías.', 1700)$$,
  'Puede fijar solo las calorías'
);

select throws_ok(
  $$insert into public.care_feedback (author_id, patient_id, kind, body, target_kcal)
    values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
            'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'feedback', 'X', 1600)$$,
  '23514', null,
  'Una devolución no lleva objetivo'
);

select throws_ok(
  $$insert into public.care_feedback (author_id, patient_id, kind, body, target_protein_g)
    values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
            'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'indication', 'X', 100)$$,
  '23514', null,
  'Un macro sin calorías no es un objetivo'
);

select throws_ok(
  $$insert into public.care_feedback (author_id, patient_id, kind, body, target_kcal)
    values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
            'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'indication', 'X', 600)$$,
  '23514', null,
  'Los mismos topes que goals: menos de 800 kcal no'
);

-- ── Las marcas del paciente ──────────────────────────────────────────────
select throws_ok(
  $$update public.care_feedback set applied_at = now()
     where id = 'eeeeeeee-0000-0000-0000-000000000001'$$,
  '42501', null,
  'La profesional no marca "aplicado" por el paciente'
);

select throws_ok(
  $$update public.care_feedback set read_at = now()
     where id = 'eeeeeeee-0000-0000-0000-000000000001'$$,
  '42501', null,
  'Ni "leída"'
);

select lives_ok(
  $$update public.care_feedback set target_kcal = 1650
     where id = 'eeeeeeee-0000-0000-0000-000000000001'$$,
  'Sí corrige sus números'
);

-- Escribir en `goals` sigue cerrado: recomendar no es fijar.
select throws_ok(
  $$insert into public.goals (id, user_id, goal_type, base_calorie_target, starts_on)
    values (gen_random_uuid(), 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            'lose', 1600, current_date)$$,
  '42501', null,
  'La profesional no puede escribir el objetivo del paciente'
);

-- ── El paciente ──────────────────────────────────────────────────────────
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}', true);

select is(
  (select target_kcal from public.care_feedback
    where kind = 'indication' and target_kcal is not null
      and published_at is not null and deleted_at is null
    order by published_at desc limit 1),
  1650,
  'Ana ve el objetivo publicado (el borrador de solo calorías no)'
);

-- Como con el texto de una devolución: se comprueba que el dato queda igual.
update public.care_feedback set target_kcal = 3000
 where id = 'eeeeeeee-0000-0000-0000-000000000001';

select is(
  (select target_kcal from public.care_feedback
    where id = 'eeeeeeee-0000-0000-0000-000000000001'),
  1650,
  'Ana no reescribe los números'
);

select public.mark_care_target_applied('eeeeeeee-0000-0000-0000-000000000001');

select is(
  (select (applied_at is not null) and (read_at is not null)
     from public.care_feedback
    where id = 'eeeeeeee-0000-0000-0000-000000000001'),
  true,
  'Ana lo aplica por función, y aplicar lo marca como leído'
);

select set_config('request.jwt.claims',
  '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}', true);

select isnt(
  (select applied_at from public.care_feedback
    where id = 'eeeeeeee-0000-0000-0000-000000000001'),
  null,
  'La profesional ve que lo aplicó'
);

select * from finish();
rollback;
