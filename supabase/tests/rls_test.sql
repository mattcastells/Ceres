-- Suite de RLS (08-supabase-plan.md §2, decisions.md §4 paso 4).
--
-- Con el JWT del usuario A se intenta leer, escribir y borrar filas del
-- usuario B en cada tabla. Se espera 0 filas o error en todos los casos.
-- **No se avanza a la app hasta que esto esté en verde**: es lo que hace
-- segura a la `anon key` que viaja en el cliente.
--
-- Correr con:  supabase test db

create extension if not exists pgtap with schema extensions;

begin;
select plan(21);

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

-- El trigger `on_auth_user_created` ya creó los dos perfiles.
select is(
  (select count(*)::int from public.profiles
    where id in ('11111111-1111-1111-1111-111111111111',
                 '22222222-2222-2222-2222-222222222222')),
  2,
  'El trigger de alta creó un perfil por usuario'
);

-- ── Datos de cada uno, como service_role (saltea RLS) ────────────────────
insert into public.goals (
  id, user_id, goal_type, rate_kg_per_week, base_calorie_target,
  target_method, protein_g, carbs_g, fat_g, macro_method, starts_on)
values
  ('aaaa0001-0000-4000-8000-000000000001',
   '11111111-1111-1111-1111-111111111111', 'lose', 0.5, 2100,
   'calculated', 140, 200, 60, 'default', current_date),
  ('bbbb0001-0000-4000-8000-000000000001',
   '22222222-2222-2222-2222-222222222222', 'maintain', 0, 2500,
   'calculated', 120, 250, 70, 'default', current_date);

insert into public.meals (id, user_id, slot, local_date, source)
values
  ('aaaa0002-0000-4000-8000-000000000002',
   '11111111-1111-1111-1111-111111111111', 'lunch', current_date, 'manual'),
  ('bbbb0002-0000-4000-8000-000000000002',
   '22222222-2222-2222-2222-222222222222', 'lunch', current_date, 'manual');

insert into public.meal_items (id, meal_id, name, quantity, unit, kcal)
values
  ('aaaa0003-0000-4000-8000-000000000003',
   'aaaa0002-0000-4000-8000-000000000002', 'Milanesa', 1, 'unidad', 289),
  ('bbbb0003-0000-4000-8000-000000000003',
   'bbbb0002-0000-4000-8000-000000000002', 'Ensalada', 1, 'plato', 45);

insert into public.activities (
  id, user_id, activity_type_id, started_at, local_date,
  duration_minutes, intensity, estimated_calories, exercise_credit_percentage)
select
  'aaaa0004-0000-4000-8000-000000000004',
  '11111111-1111-1111-1111-111111111111',
  id, now(), current_date, 30, 'moderate', 184, 0
from public.activity_types where slug = 'walking';

insert into public.activities (
  id, user_id, activity_type_id, started_at, local_date,
  duration_minutes, intensity, estimated_calories, exercise_credit_percentage)
select
  'bbbb0004-0000-4000-8000-000000000004',
  '22222222-2222-2222-2222-222222222222',
  id, now(), current_date, 45, 'vigorous', 400, 50
from public.activity_types where slug = 'running';

insert into public.weight_logs (id, user_id, weight_kg, local_date)
values
  ('aaaa0005-0000-4000-8000-000000000005',
   '11111111-1111-1111-1111-111111111111', 100.0, current_date),
  ('bbbb0005-0000-4000-8000-000000000005',
   '22222222-2222-2222-2222-222222222222', 70.0, current_date);

-- El trigger de RN-02 corrigió las calorías aplicadas.
select is(
  (select applied_calories from public.activities
    where id = 'bbbb0004-0000-4000-8000-000000000004'),
  200,
  'applied_calories = round(estimadas × porcentaje) lo calcula la base'
);

-- El trigger de D-11 mantiene los totales de la comida.
select is(
  (select total_kcal from public.meals
    where id = 'aaaa0002-0000-4000-8000-000000000002'),
  289,
  'Los totales de la comida los mantiene el trigger, no el cliente'
);

-- ── A partir de acá, todo con el JWT del usuario A ───────────────────────
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}',
  true);

-- Lectura: solo lo propio.
select is((select count(*)::int from public.profiles), 1,
  'A ve un solo perfil: el suyo');
select is((select count(*)::int from public.goals), 1,
  'A ve un solo objetivo: el suyo');
select is((select count(*)::int from public.meals), 1,
  'A ve una sola comida: la suya');
select is((select count(*)::int from public.meal_items), 1,
  'A ve un solo ítem: el de su comida');
select is((select count(*)::int from public.activities), 1,
  'A ve una sola actividad: la suya');
select is((select count(*)::int from public.weight_logs), 1,
  'A ve un solo peso: el suyo');

select is(
  (select count(*)::int from public.activities
    where id = 'bbbb0004-0000-4000-8000-000000000004'),
  0,
  'La actividad de B es invisible para A aun pidiéndola por id'
);

-- Escritura a nombre de otro: rechazada por la policy de insert.
select throws_ok(
  $$insert into public.activities (
      id, user_id, activity_type_id, started_at, local_date,
      duration_minutes, intensity, estimated_calories, exercise_credit_percentage)
    select 'cccc0001-0000-4000-8000-000000000001',
           '22222222-2222-2222-2222-222222222222',
           id, now(), current_date, 30, 'moderate', 200, 0
      from public.activity_types where slug = 'walking'$$,
  '42501',
  null,
  'A no puede insertar una actividad a nombre de B'
);

select throws_ok(
  $$insert into public.weight_logs (id, user_id, weight_kg, local_date)
    values ('cccc0002-0000-4000-8000-000000000002',
            '22222222-2222-2222-2222-222222222222', 80, current_date)$$,
  '42501',
  null,
  'A no puede registrar un peso a nombre de B'
);

-- Actualización de lo ajeno: no afecta ninguna fila.
update public.activities
   set estimated_calories = 1
 where id = 'bbbb0004-0000-4000-8000-000000000004';
select is(
  (select estimated_calories from public.activities
    where id = 'bbbb0004-0000-4000-8000-000000000004'),
  null::integer,
  'El update de A sobre la actividad de B no toca nada'
);

update public.meals set name = 'hackeada'
 where id = 'bbbb0002-0000-4000-8000-000000000002';
select is(
  (select count(*)::int from public.meals where name = 'hackeada'),
  0,
  'El update de A sobre la comida de B no toca nada'
);

-- Borrado físico: prohibido incluso sobre lo propio (se usa deleted_at).
with intento as (
  delete from public.activities
   where id = 'aaaa0004-0000-4000-8000-000000000004'
  returning 1
)
select is(
  (select count(*)::int from intento),
  0,
  'El borrado físico está prohibido: la app hace soft delete'
);

select is(
  (select count(*)::int from public.activities
    where id = 'aaaa0004-0000-4000-8000-000000000004'),
  1,
  'La actividad propia sigue ahí después del intento de borrado'
);

-- Soft delete: eso sí funciona.
update public.activities set deleted_at = now(), deletion_reason = 'user'
 where id = 'aaaa0004-0000-4000-8000-000000000004';
select is(
  (select count(*)::int from public.v_active_activities),
  0,
  'La vista de activas respeta el soft delete'
);

-- Catálogos: los tipos del sistema los lee cualquiera autenticado.
select cmp_ok(
  (select count(*)::int from public.activity_types where is_system),
  '>=',
  15,
  'A lee los 15 tipos de actividad del sistema'
);

select throws_ok(
  $$insert into public.activity_types (
      slug, display_name, category, default_met, is_system, user_id)
    values ('trampa', 'Trampa', 'other', 5, true, null)$$,
  '42501',
  null,
  'A no puede crear un tipo marcado como del sistema'
);

-- audit_log: se lee el propio, no se escribe desde el cliente.
select cmp_ok(
  (select count(*)::int from public.audit_log),
  '>=',
  1,
  'A lee su propio registro de auditoría'
);

select is(
  (select count(*)::int from public.audit_log
    where user_id = '22222222-2222-2222-2222-222222222222'),
  0,
  'El registro de auditoría de B es invisible para A'
);

-- Acá había una comprobación de que `get_daily_summary` solo hablaba del
-- usuario del JWT. La función se fue con la migración 43: no la llamaba nadie
-- —el resumen del día lo calcula el dominio en el teléfono— y mantenerla era
-- tener dos implementaciones de la misma cuenta, una de las cuales nunca se
-- ejecutaba y por lo tanto nunca se iba a notar cuando dejaran de coincidir.

select * from finish();
rollback;
