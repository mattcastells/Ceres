-- El vínculo con la nutricionista (migración 55): todo compartido, la baja de
-- los dos lados y a qué plan vuelve cada uno.
--
-- Correr con:  supabase test db

create extension if not exists pgtap with schema extensions;

begin;
select plan(9);

-- Pro: la profesional. Libre: gratis. Paga: premium pagado. Otra: otra Pro.
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
)
values
  ('11111111-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'pro@ceres.test',
   crypt('x', gen_salt('bf')), now(), now(), now()),
  ('11111111-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'libre@ceres.test',
   crypt('x', gen_salt('bf')), now(), now(), now()),
  ('11111111-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'paga@ceres.test',
   crypt('x', gen_salt('bf')), now(), now(), now()),
  ('11111111-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'otra@ceres.test',
   crypt('x', gen_salt('bf')), now(), now(), now());

insert into public.account_plans (user_id, plan) values
  ('11111111-0000-0000-0000-000000000001', 'pro'),
  ('11111111-0000-0000-0000-000000000002', 'free'),
  ('11111111-0000-0000-0000-000000000003', 'premium'),
  ('11111111-0000-0000-0000-000000000004', 'pro');

update public.profiles set care_code = 'CE-PROTEST'
 where id = '11111111-0000-0000-0000-000000000001';

set local role authenticated;

-- ── Libre y Paga se suman pidiendo "solo comidas" ────────────────────────
select set_config('request.jwt.claims',
  '{"sub":"11111111-0000-0000-0000-000000000002","role":"authenticated"}', true);
select public.grant_care_access('CE-PROTEST', p_share_meals => true);

select is(
  (select share_body and share_photos and share_wellbeing
     from public.care_grants
    where owner_id = '11111111-0000-0000-0000-000000000002'),
  true,
  'Sumarse abre todo, pida lo que pida la app'
);
select is(public.effective_plan(), 'patient',
  'Gratis y con nutricionista Pro: la IA se la paga ella');

select set_config('request.jwt.claims',
  '{"sub":"11111111-0000-0000-0000-000000000003","role":"authenticated"}', true);
select public.grant_care_access('CE-PROTEST');
select is(public.effective_plan(), 'premium',
  'Quien paga Premium sigue en Premium con nutricionista');

-- ── Otra profesional no puede dar de baja a pacientes ajenos ────────────
select set_config('request.jwt.claims',
  '{"sub":"11111111-0000-0000-0000-000000000004","role":"authenticated"}', true);
select throws_ok(
  $$select public.discharge_patient('11111111-0000-0000-0000-000000000002')$$,
  'P0001', 'ERR_NOT_FOUND',
  'Otra profesional no da de baja a un paciente que no es suyo'
);

-- ── La profesional da de baja a los dos ──────────────────────────────────
select set_config('request.jwt.claims',
  '{"sub":"11111111-0000-0000-0000-000000000001","role":"authenticated"}', true);
select is(
  public.discharge_patient('11111111-0000-0000-0000-000000000002'), 1,
  'La profesional da de baja a un paciente suyo'
);
select public.discharge_patient('11111111-0000-0000-0000-000000000003');

select is(
  (select count(*)::int from public.care_patients), 0,
  'Dados de baja, ya no aparecen en su lista'
);

-- ── Cada uno vuelve a su plan ────────────────────────────────────────────
select set_config('request.jwt.claims',
  '{"sub":"11111111-0000-0000-0000-000000000002","role":"authenticated"}', true);
select is(public.effective_plan(), 'free',
  'Dado de baja, el que no pagaba vuelve a Gratis');

select set_config('request.jwt.claims',
  '{"sub":"11111111-0000-0000-0000-000000000003","role":"authenticated"}', true);
select is(public.effective_plan(), 'premium',
  'Dado de baja, el que pagaba sigue en Premium');

-- ── Y el registro de que existió queda ───────────────────────────────────
select is(
  (select revoked_at is not null from public.care_grants
    where owner_id = '11111111-0000-0000-0000-000000000003'),
  true,
  'La baja deja la fila con fecha, no la borra'
);

select * from finish();
rollback;
