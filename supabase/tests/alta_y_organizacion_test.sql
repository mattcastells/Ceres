-- El alta desde el panel, una sola nutricionista, el consultorio y los
-- comentarios sobre una comida (migración 56).
--
-- Correr con:  supabase test db

create extension if not exists pgtap with schema extensions;

begin;
select plan(27);

-- Titular (Pro, dueña del consultorio), Socia (Pro, del consultorio),
-- Afuera (Pro, sin consultorio), Pac (paciente), Otro (paciente), Suelta
-- (cuenta sin nada, para sumar al consultorio).
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
)
select id::uuid, '00000000-0000-0000-0000-000000000000', 'authenticated',
       'authenticated', email, crypt('x', gen_salt('bf')), now(), now(), now()
  from (values
    ('22222222-0000-0000-0000-000000000001', 'titular@ceres.test'),
    ('22222222-0000-0000-0000-000000000002', 'socia@ceres.test'),
    ('22222222-0000-0000-0000-000000000003', 'afuera@ceres.test'),
    ('22222222-0000-0000-0000-000000000004', 'pac@ceres.test'),
    ('22222222-0000-0000-0000-000000000005', 'otro@ceres.test'),
    ('22222222-0000-0000-0000-000000000006', 'suelta@ceres.test')
  ) as u(id, email);

insert into public.account_plans (user_id, plan) values
  ('22222222-0000-0000-0000-000000000001', 'pro'),
  ('22222222-0000-0000-0000-000000000002', 'pro'),
  ('22222222-0000-0000-0000-000000000003', 'pro'),
  ('22222222-0000-0000-0000-000000000004', 'free'),
  ('22222222-0000-0000-0000-000000000005', 'free');

update public.profiles set care_code = 'CE-TITULAR' where id = '22222222-0000-0000-0000-000000000001';
update public.profiles set care_code = 'CE-AFUERA1' where id = '22222222-0000-0000-0000-000000000003';

insert into public.organizations (id, name)
values ('33333333-0000-0000-0000-000000000001', 'Consultorio de prueba');
insert into public.org_members (org_id, user_id, role) values
  ('33333333-0000-0000-0000-000000000001', '22222222-0000-0000-0000-000000000001', 'owner'),
  ('33333333-0000-0000-0000-000000000001', '22222222-0000-0000-0000-000000000002', 'professional');

insert into public.meals (id, user_id, slot, local_date, name) values
  ('44444444-0000-0000-0000-000000000001', '22222222-0000-0000-0000-000000000004',
   'lunch', current_date, 'Milanesa con puré'),
  ('44444444-0000-0000-0000-000000000002', '22222222-0000-0000-0000-000000000005',
   'lunch', current_date, 'De otro paciente');

set local role authenticated;

-- ── El alta: la titular invita a Pac por mail ────────────────────────────
select set_config('request.jwt.claims',
  '{"sub":"22222222-0000-0000-0000-000000000001","role":"authenticated"}', true);

select isnt(public.invite_patient('  Pac@Ceres.test '), null,
  'La profesional invita por mail (sin importar mayúsculas ni espacios)');
select is(public.invite_patient('pac@ceres.test'),
  (select id from public.care_invites where email = 'pac@ceres.test'),
  'Invitar dos veces al mismo mail devuelve la misma invitación');
select lives_ok($$select public.invite_patient('socia@ceres.test')$$,
  'Una cuenta profesional queda invitada igual: el panel no revela de quién es cada mail (57)');
select throws_ok($$select public.invite_patient('no-es-un-mail')$$,
  'P0001', 'ERR_VALIDATION', 'Un mail mal escrito no se invita');
select lives_ok($$select public.invite_patient('nadie@ceres.test')$$,
  'Un mail sin cuenta queda invitado igual: el panel no revela quién usa Ceres');

-- Un paciente no puede invitar.
select set_config('request.jwt.claims',
  '{"sub":"22222222-0000-0000-0000-000000000005","role":"authenticated"}', true);
select throws_ok($$select public.invite_patient('pac@ceres.test')$$,
  'P0001', 'ERR_FORBIDDEN', 'Una cuenta que no es profesional no invita');

-- ── Pac ve la invitación y la acepta ─────────────────────────────────────
select set_config('request.jwt.claims',
  '{"sub":"22222222-0000-0000-0000-000000000004","role":"authenticated"}', true);
select is((select org_name from public.my_care_invites()), 'Consultorio de prueba',
  'El paciente ve la invitación con el nombre del consultorio');
select is((select count(*)::int from public.care_invites), 0,
  'El paciente no lee la tabla de invitaciones directo');
select lives_ok(
  $$select public.accept_care_invite((select id from public.my_care_invites()))$$,
  'El paciente acepta');
select is(public.effective_plan(), 'patient',
  'Aceptada la invitación de una Pro, la IA se la paga ella');

-- Una sola nutricionista: el código de otra lo rechaza.
select throws_ok($$select public.grant_care_access('CE-AFUERA1')$$,
  'P0001', 'ERR_CONFLICT', 'Con nutricionista, no se suma a una segunda');
select throws_ok($$select public.ensure_care_code()$$,
  'P0001', 'ERR_VALIDATION', 'Una cuenta de paciente no pide código de profesional');

-- ── Una cuenta profesional no se suma como paciente ──────────────────────
select set_config('request.jwt.claims',
  '{"sub":"22222222-0000-0000-0000-000000000003","role":"authenticated"}', true);
select throws_ok($$select public.grant_care_access('CE-TITULAR')$$,
  'P0001', 'ERR_VALIDATION', 'Una profesional no se suma como paciente');

-- ── La titular invita a Otro; lo atiende la Socia ────────────────────────
select set_config('request.jwt.claims',
  '{"sub":"22222222-0000-0000-0000-000000000001","role":"authenticated"}', true);
select is((select count(*)::int from public.care_patients), 1,
  'Pac aparece en la lista de la titular');

reset role;
-- Otro se suma a la Socia (el código se pone acá para no depender del panel).
update public.profiles set care_code = 'CE-SOCIA01' where id = '22222222-0000-0000-0000-000000000002';
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"22222222-0000-0000-0000-000000000005","role":"authenticated"}', true);
select public.grant_care_access('CE-SOCIA01');

-- ── La titular administra el consultorio ─────────────────────────────────
select set_config('request.jwt.claims',
  '{"sub":"22222222-0000-0000-0000-000000000001","role":"authenticated"}', true);
select is((select count(*)::int from public.org_patients()), 2,
  'La titular ve a los pacientes de todo el consultorio');
select is((select count(*)::int from public.meals
            where user_id = '22222222-0000-0000-0000-000000000005'), 1,
  'La titular lee las comidas de un paciente de la socia');
select throws_ok(
  $$insert into public.care_feedback (author_id, patient_id, body)
    values ('22222222-0000-0000-0000-000000000001',
            '22222222-0000-0000-0000-000000000005', 'Hola')$$,
  '42501', null, 'Pero no le escribe: eso es de su profesional');

-- Comentar una comida: la del paciente sí, la de otro no.
select lives_ok(
  $$insert into public.care_feedback (author_id, patient_id, body, meal_id, local_date)
    values ('22222222-0000-0000-0000-000000000001',
            '22222222-0000-0000-0000-000000000004', 'Buen almuerzo',
            '44444444-0000-0000-0000-000000000001', current_date)$$,
  'La profesional comenta una comida de su paciente');
select throws_ok(
  $$insert into public.care_feedback (author_id, patient_id, body, meal_id)
    values ('22222222-0000-0000-0000-000000000001',
            '22222222-0000-0000-0000-000000000004', 'Hola',
            '44444444-0000-0000-0000-000000000002')$$,
  '42501', null, 'No se cuelga un comentario de la comida de otra persona');

-- Reasignar a Otro a la titular.
select lives_ok(
  $$select public.reassign_patient('22222222-0000-0000-0000-000000000005',
                                   '22222222-0000-0000-0000-000000000001')$$,
  'La titular reasigna un paciente');
select is((select count(*)::int from public.care_patients), 2,
  'Reasignado, aparece en su lista');

-- Sumar profesionales.
select throws_ok($$select public.org_add_member('pac@ceres.test')$$,
  'P0001', 'ERR_VALIDATION', 'Un paciente no entra al consultorio como profesional');
reset role;
insert into public.organizations (id, name)
values ('33333333-0000-0000-0000-000000000002', 'Otro consultorio');
insert into public.org_members (org_id, user_id, role)
values ('33333333-0000-0000-0000-000000000002', '22222222-0000-0000-0000-000000000003', 'owner');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"22222222-0000-0000-0000-000000000001","role":"authenticated"}', true);
select throws_ok($$select public.org_add_member('afuera@ceres.test')$$,
  'P0001', 'ERR_VALIDATION', 'Una profesional de otro consultorio no se suma (mismo mensaje que el resto, 57)');
select lives_ok($$select public.org_add_member('suelta@ceres.test')$$,
  'Una cuenta libre se suma al consultorio');
select throws_ok(
  $$select public.org_remove_member('22222222-0000-0000-0000-000000000001')$$,
  'P0001', 'ERR_VALIDATION', 'La titular no se saca');

-- ── La socia no administra ───────────────────────────────────────────────
select set_config('request.jwt.claims',
  '{"sub":"22222222-0000-0000-0000-000000000002","role":"authenticated"}', true);
select is((select count(*)::int from public.org_patients()), 0,
  'Una profesional del consultorio no ve la lista de todos');
select throws_ok(
  $$select public.discharge_patient('22222222-0000-0000-0000-000000000004')$$,
  'P0001', 'ERR_NOT_FOUND', 'Ni da de baja a pacientes de otra');

select * from finish();
rollback;
