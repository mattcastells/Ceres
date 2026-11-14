-- Lo que corrigió la migración 57 después de la revisión de la 56.
--
-- Correr con:  supabase test db

create extension if not exists pgtap with schema extensions;

begin;
select plan(10);

-- Titular (Pro, dueña), Indep (Pro con un paciente propio, sin consultorio),
-- Pac (paciente de Indep), Nuevo (cuenta libre), Vencido (paciente con un
-- acceso vencido a Indep), Curioso (cuenta cualquiera).
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
)
select id::uuid, '00000000-0000-0000-0000-000000000000', 'authenticated',
       'authenticated', email, crypt('x', gen_salt('bf')), now(), now(), now()
  from (values
    ('55555555-0000-0000-0000-000000000001', 'titular57@ceres.test'),
    ('55555555-0000-0000-0000-000000000002', 'indep57@ceres.test'),
    ('55555555-0000-0000-0000-000000000003', 'pac57@ceres.test'),
    ('55555555-0000-0000-0000-000000000004', 'nuevo57@ceres.test'),
    ('55555555-0000-0000-0000-000000000005', 'vencido57@ceres.test'),
    ('55555555-0000-0000-0000-000000000006', 'curioso57@ceres.test')
  ) as u(id, email);

insert into public.account_plans (user_id, plan) values
  ('55555555-0000-0000-0000-000000000001', 'pro'),
  ('55555555-0000-0000-0000-000000000002', 'pro');

update public.profiles set care_code = 'CE-TIT57AA' where id = '55555555-0000-0000-0000-000000000001';
update public.profiles set care_code = 'CE-IND57AA' where id = '55555555-0000-0000-0000-000000000002';

insert into public.organizations (id, name)
values ('66666666-0000-0000-0000-000000000001', 'Consultorio 57');
insert into public.org_members (org_id, user_id, role) values
  ('66666666-0000-0000-0000-000000000001', '55555555-0000-0000-0000-000000000001', 'owner');

insert into public.care_grants (owner_id, professional_id, status, accepted_at, expires_at) values
  ('55555555-0000-0000-0000-000000000003', '55555555-0000-0000-0000-000000000002', 'accepted', now(), null),
  ('55555555-0000-0000-0000-000000000005', '55555555-0000-0000-0000-000000000002', 'accepted',
   now() - interval '30 days', now() - interval '1 day');

set local role authenticated;

-- ── Las funciones de ayuda no se llaman desde afuera ─────────────────────
select set_config('request.jwt.claims',
  '{"sub":"55555555-0000-0000-0000-000000000006","role":"authenticated"}', true);
select throws_ok(
  $$select public.current_professional_name('55555555-0000-0000-0000-000000000003')$$,
  '42501', null,
  'Nadie averigua la nutricionista de otro');

-- Pedir un código (abrir el panel por error) no convierte la cuenta en
-- profesional: después se puede sumar a una nutricionista igual.
select public.ensure_care_code();
select lives_ok($$select public.grant_care_access('CE-TIT57AA')$$,
  'Una cuenta con código pero sin Pro ni consultorio se suma como paciente');

-- ── Un acceso vencido no traba sumarse a otra ────────────────────────────
select set_config('request.jwt.claims',
  '{"sub":"55555555-0000-0000-0000-000000000005","role":"authenticated"}', true);
select lives_ok($$select public.grant_care_access('CE-TIT57AA')$$,
  'Con el acceso anterior vencido, se suma a otra');

-- ── Sumarse por código cierra la invitación de esa misma profesional ─────
select set_config('request.jwt.claims',
  '{"sub":"55555555-0000-0000-0000-000000000001","role":"authenticated"}', true);
select public.invite_patient('nuevo57@ceres.test');
select set_config('request.jwt.claims',
  '{"sub":"55555555-0000-0000-0000-000000000004","role":"authenticated"}', true);
select public.grant_care_access('CE-TIT57AA');
select is((select count(*)::int from public.my_care_invites()), 0,
  'Sumado por código, la invitación de la misma profesional ya no aparece');

reset role;
select is((select status from public.care_invites where email = 'nuevo57@ceres.test'),
  'accepted', 'Y queda resuelta');
set local role authenticated;

-- ── Sumar al consultorio ─────────────────────────────────────────────────
select set_config('request.jwt.claims',
  '{"sub":"55555555-0000-0000-0000-000000000001","role":"authenticated"}', true);
select throws_ok($$select public.org_add_member('indep57@ceres.test')$$,
  'P0001', 'ERR_VALIDATION',
  'Una profesional con pacientes propios no se suma sin aceptar (se abrirían sus datos)');
select throws_ok($$select public.org_add_member('no-existe57@ceres.test')$$,
  'P0001', 'ERR_VALIDATION',
  'Un mail sin cuenta recibe el mismo mensaje que el resto');

-- Una cuenta libre entra con Pro y, al salir, vuelve a no tener plan.
reset role;
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at)
values ('55555555-0000-0000-0000-000000000007', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'libre57@ceres.test', crypt('x', gen_salt('bf')),
  now(), now(), now());
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"55555555-0000-0000-0000-000000000001","role":"authenticated"}', true);
select public.org_add_member('libre57@ceres.test');
reset role;
select is((select plan from public.account_plans
            where user_id = '55555555-0000-0000-0000-000000000007'), 'pro',
  'Entra al consultorio con Pro');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"55555555-0000-0000-0000-000000000001","role":"authenticated"}', true);
select lives_ok(
  $$select public.org_remove_member('55555555-0000-0000-0000-000000000007')$$,
  'La titular la saca');
reset role;
select is((select count(*)::int from public.account_plans
            where user_id = '55555555-0000-0000-0000-000000000007'), 0,
  'Al salir vuelve al plan que tenía (ninguno): el Pro lo pagaba el consultorio');

select * from finish();
rollback;
