-- El contexto del día, las devoluciones y los informes (migraciones 40, 41 y 48).
--
-- Va aparte de `care_access_test.sql` y no adentro porque aquel termina
-- revocando el acceso, y todo lo que se agregue después de esa línea prueba
-- otra cosa de la que dice probar.
--
-- Lo que se comprueba acá:
--
--   1. Las dos tablas nuevas se abren con el acceso (desde la migración 55,
--      todo acceso abre todo).
--   2. La profesional las lee, pero **no las puede escribir**: la promesa de la
--      migración 32 —los datos del paciente son de solo lectura— sigue en pie
--      aunque ahora exista una escritura en el panel.
--   3. Un borrador de devolución es de quien lo escribe: **el paciente no lo
--      ve** hasta que se publica, y publicada no la puede editar.
--   4. Revocar corta la escritura de devoluciones pero no borra lo escrito.
--   6. Los informes y el tablero del equipo solo muestran lo concedido.
--   5. `tracking_since` contesta lo mismo que la app, y solo a quien tiene
--      acceso.
--
-- Correr con:  supabase test db

create extension if not exists pgtap with schema extensions;

begin;
select plan(26);

-- ── Ana (paciente), Nutri (profesional) y Otra (una desconocida) ─────────
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'ana@ceres.test', crypt('secreto-ana', gen_salt('bf')), now(), now(), now()),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'nutri@ceres.test', crypt('secreto-nutri', gen_salt('bf')), now(), now(), now()),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'otra@ceres.test', crypt('secreto-otra', gen_salt('bf')), now(), now(), now());

-- El día de Ana. La comida es de hace diez días y el peso de hace veinte: el
-- orden importa para `tracking_since`, que tiene que devolver el más viejo de
-- los tres orígenes y no el primero que encuentre.
insert into public.meals (id, user_id, slot, local_date, name)
values ('dddddddd-0000-0000-0000-000000000001',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'lunch',
        current_date - 10, 'Milanesa con puré');

insert into public.weight_logs (id, user_id, local_date, weight_kg)
values ('dddddddd-0000-0000-0000-000000000002',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', current_date - 20, 100.0);

insert into public.day_markers (id, user_id, local_date, kind, severity, note)
values ('dddddddd-0000-0000-0000-000000000003',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', current_date - 3,
        'sick', 2, 'Angina');

insert into public.alcohol_logs (
  id, user_id, local_date, drink_type, quantity, volume_ml, abv_pct,
  std_drinks, kcal)
values ('dddddddd-0000-0000-0000-000000000004',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', current_date - 5,
        'beer', 2, 473, 5.0, 3.73, 400);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}', true);

select matches(public.ensure_care_code(),
  '^CE-[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{6}$',
  'La profesional pide su código');

reset role;
create temporary table codigos on commit drop as
  select id, care_code from public.profiles;
grant select on codigos to authenticated;
set local role authenticated;

-- ── Sin permiso, el contexto no se ve ────────────────────────────────────
select is(
  (select count(*)::int from public.day_markers
    where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0,
  'Sin permiso no ve los días de enfermedad'
);

select is(
  (select count(*)::int from public.alcohol_logs
    where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0,
  'Ni el alcohol'
);

-- Y `tracking_since` tampoco: la fecha en que alguien empezó a usar la app es
-- poca cosa al lado de una comida, pero sigue siendo un dato de esa persona.
select is(
  public.tracking_since('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  null,
  'Sin permiso, `tracking_since` no contesta'
);

-- ── Ana concede comidas, y **solo** comidas ──────────────────────────────
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}', true);

select ok(
  public.grant_care_access(
    (select care_code from codigos
      where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
    p_share_meals => true) is not null,
  'Ana le da acceso a las comidas'
);

select set_config('request.jwt.claims',
  '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}', true);

-- Desde la migración 55 el acceso abre todo, también el contexto del día.
select is(
  (select count(*)::int from public.day_markers
    where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  1,
  'El acceso abre también el contexto del día'
);

-- ── Ana suma el bienestar ────────────────────────────────────────────────
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}', true);

select ok(
  public.grant_care_access(
    (select care_code from codigos
      where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
    p_share_meals => true, p_share_wellbeing => true) is not null,
  'Ana suma la actividad, el agua, el sueño y el contexto'
);

select set_config('request.jwt.claims',
  '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}', true);

select is(
  (select note from public.day_markers
    where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  'Angina',
  'Y ve el día de enfermedad'
);

select is(
  (select std_drinks::numeric(5,2) from public.alcohol_logs
    where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  3.73::numeric(5,2),
  'Y lo que se tomó'
);

-- ── Pero **no** lo puede escribir ────────────────────────────────────────
-- Es la promesa de la migración 32 y sigue valiendo: lo que se abrió con las
-- notas es una tabla propia, no la de nadie más. Si el panel tuviera un bug
-- que intenta "corregir" un día de enfermedad, la base lo rechaza.
-- ⚠️ El update **no lanza**: sin una policy de update, la fila no es visible
-- para modificar y Postgres actualiza cero filas en silencio. Un `throws_ok`
-- acá pasaba a verde el día que alguien agregara la policy que falta, porque lo
-- que estaría comprobando es que tira error y no que el dato queda igual.
-- Lo que importa es lo segundo, así que se comprueba lo segundo.
update public.day_markers set note = 'otra cosa'
 where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

select is(
  (select note from public.day_markers
    where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  'Angina',
  'La profesional no puede editar el contexto del paciente'
);

select throws_ok(
  $$insert into public.alcohol_logs
      (id, user_id, local_date, drink_type, quantity, volume_ml, abv_pct,
       std_drinks, kcal)
    values ('dddddddd-0000-0000-0000-00000000000f',
            'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', current_date,
            'wine', 1, 150, 13.0, 1.5, 130)$$,
  '42501',
  null,
  'Ni cargarle un consumo a nombre de Ana'
);

-- ── `tracking_since` contesta lo mismo que la app ────────────────────────
-- El más viejo de comidas, actividades y pesos. Acá es el peso, que es 10 días
-- más viejo que la comida: si devolviera el primero que encuentra en vez del
-- mínimo, el panel arrancaría el período diez días tarde y contaría de menos.
select is(
  public.tracking_since('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  (current_date - 20)::date,
  'tracking_since es el día del registro más viejo, no el de la comida'
);

-- ── Las devoluciones ─────────────────────────────────────────────────────
-- Un borrador es privado: es lo que antes eran las notas de la profesional.
insert into public.care_feedback (id, author_id, patient_id, local_date, body)
values ('eeeeeeee-0000-0000-0000-000000000001',
        'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', current_date - 3,
        'Semana con angina. No leer la caída de actividad como abandono.');

select is(
  (select count(*)::int from public.care_feedback),
  1,
  'La profesional escribe un borrador'
);

select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}', true);

select is(
  (select count(*)::int from public.care_feedback),
  0,
  'Ana NO ve un borrador: hasta que se publica, es de quien lo escribe'
);

select set_config('request.jwt.claims',
  '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}', true);

update public.care_feedback set published_at = now()
 where id = 'eeeeeeee-0000-0000-0000-000000000001';

select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}', true);

select is(
  (select count(*)::int from public.care_feedback),
  1,
  'Publicada, Ana la ve'
);

-- Ana no puede reescribir lo que le escribió su nutricionista. Igual que con
-- el contexto del día, se comprueba que el dato queda igual y no que tire.
update public.care_feedback set body = 'otra cosa'
 where id = 'eeeeeeee-0000-0000-0000-000000000001';

select is(
  (select body from public.care_feedback
    where id = 'eeeeeeee-0000-0000-0000-000000000001'),
  'Semana con angina. No leer la caída de actividad como abandono.',
  'Ana no puede editar la devolución'
);

select public.mark_care_feedback_read('eeeeeeee-0000-0000-0000-000000000001');

select isnt(
  (select read_at from public.care_feedback
    where id = 'eeeeeeee-0000-0000-0000-000000000001'),
  null,
  'Pero sí marcarla como leída'
);

-- Un informe semanal propio sí; uno "profesional" sobre otra persona, no.
insert into public.care_reports (
  requested_by, patient_id, kind, period_from, period_to, content,
  model, prompt_version)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'patient_weekly',
        current_date - 7, current_date - 1, '{}', 'test', 'test');

select is(
  (select count(*)::int from public.care_reports),
  1,
  'Ana guarda su informe semanal'
);

select throws_ok(
  $$insert into public.care_reports (
      requested_by, patient_id, kind, period_from, period_to, content,
      model, prompt_version)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            'cccccccc-cccc-cccc-cccc-cccccccccccc', 'professional',
            current_date - 7, current_date - 1, '{}', 'test', 'test')$$,
  '42501',
  null,
  'Pero no un informe sobre alguien que no le dio acceso'
);

select set_config('request.jwt.claims',
  '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}', true);

select is(
  (select count(*)::int from public.care_feedback)
    + (select count(*)::int from public.care_reports),
  0,
  'Una desconocida no ve devoluciones ni informes ajenos'
);

select throws_ok(
  $$insert into public.care_feedback (author_id, patient_id, body)
    values ('cccccccc-cccc-cccc-cccc-cccccccccccc',
            'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'hola')$$,
  '42501',
  null,
  'Sin permiso vigente no se le escribe a nadie'
);

-- ── El tablero del equipo ────────────────────────────────────────────────
select set_config('request.jwt.claims',
  '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}', true);

select is(
  (select last_meal_date from public.care_overview()
    where patient_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  (current_date - 10)::date,
  'El tablero muestra la última comida de Ana'
);

-- Con todo compartido, el tablero muestra el peso.
select is(
  (select weight_last_30 from public.care_overview()
    where patient_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  100.00::numeric,
  'El tablero muestra el peso de Ana'
);

select set_config('request.jwt.claims',
  '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}', true);

select is(
  (select count(*)::int from public.care_overview()),
  0,
  'A una desconocida el tablero no le muestra a nadie'
);

-- ── Revocar corta la escritura, no borra lo escrito ──────────────────────
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}', true);

select public.revoke_care_access(
  (select id from public.care_grants
    where owner_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'));

select set_config('request.jwt.claims',
  '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}', true);

select is(
  (select count(*)::int from public.care_feedback),
  1,
  'Revocado, sigue viendo lo que escribió'
);

select throws_ok(
  $$insert into public.care_feedback (author_id, patient_id, body)
    values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
            'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'una más')$$,
  '42501',
  null,
  'Pero no puede escribir una nueva'
);

select * from finish();
rollback;
