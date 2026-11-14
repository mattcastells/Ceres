-- Planes y organizaciones (migración 49).
--
--   1. Una cuenta sin plan asignado es Premium: las cuentas reales no cambian.
--   2. Gratis vinculado a una profesional Pro = paciente (la IA la paga ella).
--   3. La organización se ve entre sus miembros y no afuera, y su tablero da
--      conteos, no datos de los pacientes.
--   4. Ningún cliente puede asignarse un plan.
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
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'real@ceres.test', crypt('x', gen_salt('bf')), now(), now(), now()),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'pro@demo.ceres.test', crypt('x', gen_salt('bf')), now(), now(), now()),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'gratis@demo.ceres.app', crypt('x', gen_salt('bf')), now(), now(), now()),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'paciente@demo.ceres.test', crypt('x', gen_salt('bf')), now(), now(), now());

insert into public.account_plans (user_id, plan) values
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'pro'),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'free'),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'free');

insert into public.care_grants (owner_id, professional_id, status, share_meals, accepted_at)
values ('dddddddd-dddd-dddd-dddd-dddddddddddd',
        'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'accepted', true, now());

insert into public.organizations (id, name, ai_monthly_quota)
values ('eeeeeeee-0000-0000-0000-000000000001', 'Consultorio Demo', 1800);
insert into public.org_members (org_id, user_id, role)
values ('eeeeeeee-0000-0000-0000-000000000001',
        'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'owner');

set local role authenticated;

-- ── Planes ───────────────────────────────────────────────────────────────
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}', true);
select is(public.effective_plan(), 'free',
  'Una cuenta nueva, sin plan asignado, es Gratis (migración 55)');

select throws_ok(
  $$insert into public.account_plans (user_id, plan)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'pro')$$,
  '42501', null, 'Nadie se asigna un plan desde el cliente');

select set_config('request.jwt.claims',
  '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}', true);
select is(public.effective_plan(), 'pro', 'La profesional es Pro');

select set_config('request.jwt.claims',
  '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}', true);
select is(public.effective_plan(), 'free', 'Gratis sin profesional: sin IA');

select set_config('request.jwt.claims',
  '{"sub":"dddddddd-dddd-dddd-dddd-dddddddddddd","role":"authenticated"}', true);
select is(public.effective_plan(), 'patient',
  'Gratis pero paciente de una Pro: la IA la paga ella');

select public.revoke_care_access(
  (select id from public.care_grants
    where owner_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'));
select is(public.effective_plan(), 'free', 'Si corta el vínculo, vuelve a gratis');

-- ── Organizaciones ───────────────────────────────────────────────────────
select set_config('request.jwt.claims',
  '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}', true);
select is((select count(*)::int from public.organizations), 1, 'Un miembro ve su organización');
select is(
  (select org_name from public.my_organization() limit 1),
  'Consultorio Demo',
  'Y su tablero');

select set_config('request.jwt.claims',
  '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}', true);
select is((select count(*)::int from public.organizations), 0, 'Alguien de afuera no la ve');
select is((select count(*)::int from public.my_organization()), 0, 'Ni su tablero');

-- ── Compra simulada ──────────────────────────────────────────────────────
select set_config('request.jwt.claims',
  '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}', true);
select is(public.demo_switch_plan('premium'), 'premium',
  'Una cuenta demo se pasa a Premium sin cobro');

select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}', true);
select throws_ok($$select public.demo_switch_plan('free')$$, 'P0001', 'ERR_FORBIDDEN',
  'Una cuenta real no cambia de plan desde el cliente');

select * from finish();
rollback;
