-- El contrato entre el push de la app y las tablas (migraciones 29, 30 y 46).
--
-- Dos cosas que no se ven mirando una fila sola y que decidían qué versión de
-- un dato sobrevivía:
--
-- 1. `updated_at` es lo que desempata la reconciliación. El trigger la movía en
--    **todo** UPDATE, y como el push reescribe todas las filas en cada corrida
--    —no es un diff—, el servidor quedaba siempre "más nuevo" que el teléfono y
--    su copia reemplazaba a la local en cada vuelta.
-- 2. El sueño no tenía lápida, así que borrar una noche no llegaba nunca al
--    servidor y la reconciliación la devolvía.
--
-- Correr con:  supabase test db

create extension if not exists pgtap with schema extensions;

begin;
select plan(32);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
)
values ('77777777-7777-7777-7777-777777777777',
        '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'g@ceres.test', crypt('secreto-g', gen_salt('bf')), now(), now(), now());

insert into public.meals (id, user_id, slot, local_date, source, name)
values ('eeee0001-0000-4000-8000-000000000001',
        '77777777-7777-7777-7777-777777777777', 'lunch', current_date,
        'manual', 'Milanesa');

-- Se retrasa a mano para que un bump se note: `now()` dentro de una
-- transacción devuelve siempre el mismo valor, así que sin envejecer la fila
-- primero el test pasaría por el motivo equivocado.
--
-- Y hay que apagar el trigger para lograrlo, lo cual dice algo bueno de él: una
-- sentencia que **solo** toca `updated_at` no cambia nada, así que la deja como
-- estaba. Eso es justamente lo que impide que un teléfono con el reloj corrido
-- se declare más nuevo sin haber cambiado un dato.
alter table public.meals disable trigger meals_set_updated_at;
update public.meals set updated_at = now() - interval '1 hour'
 where id = 'eeee0001-0000-4000-8000-000000000001';
alter table public.meals enable trigger meals_set_updated_at;

create temporary table antes on commit drop as
  select updated_at from public.meals
   where id = 'eeee0001-0000-4000-8000-000000000001';

-- ── Reescribir una fila idéntica no la vuelve más nueva ──────────────────
-- Es exactamente lo que hace el push con las cientos de filas que no cambiaron.
update public.meals
   set name = 'Milanesa', slot = 'lunch', updated_at = now()
 where id = 'eeee0001-0000-4000-8000-000000000001';

select is(
  (select updated_at from public.meals
    where id = 'eeee0001-0000-4000-8000-000000000001'),
  (select updated_at from antes),
  'Un push que reescribe la misma fila no la vuelve más nueva'
);

-- ── Un cambio de verdad sí ───────────────────────────────────────────────
update public.meals set name = 'Milanesa con puré'
 where id = 'eeee0001-0000-4000-8000-000000000001';

select ok(
  (select updated_at from public.meals
    where id = 'eeee0001-0000-4000-8000-000000000001')
  > (select updated_at from antes),
  'Un cambio de verdad sí mueve updated_at'
);

-- Y la pone el servidor, no el cliente: mandar una fecha vieja junto con un
-- cambio real no puede hacer que ese cambio parezca viejo.
update public.meals
   set name = 'Milanesa napolitana', updated_at = now() - interval '10 days'
 where id = 'eeee0001-0000-4000-8000-000000000001';

select ok(
  (select updated_at from public.meals
    where id = 'eeee0001-0000-4000-8000-000000000001')
  > now() - interval '1 minute',
  'La hora de un cambio la pone el servidor, no el reloj del teléfono'
);

-- Ni siquiera puede envejecerse sola: sin un cambio de datos que la acompañe,
-- la fecha que mande el cliente se descarta.
update public.meals set updated_at = now() - interval '10 days'
 where id = 'eeee0001-0000-4000-8000-000000000001';

select ok(
  (select updated_at from public.meals
    where id = 'eeee0001-0000-4000-8000-000000000001')
  > now() - interval '1 minute',
  'Un cliente no puede retrodatar una fila sin cambiarle nada'
);

-- ── El sueño tiene lápida ────────────────────────────────────────────────
select has_column(
  'public', 'sleep_logs', 'deleted_at',
  'sleep_logs puede llevar lápida'
);

insert into public.sleep_logs (id, user_id, local_date, minutes, quality, deleted_at)
values
  ('eeee0002-0000-4000-8000-000000000002',
   '77777777-7777-7777-7777-777777777777', current_date - 40, 420, 'good',
   now() - interval '31 days'),
  ('eeee0003-0000-4000-8000-000000000003',
   '77777777-7777-7777-7777-777777777777', current_date - 2, 400, 'ok',
   now() - interval '2 days');

select public.purge_soft_deleted();

select is(
  (select count(*)::int from public.sleep_logs
    where id = 'eeee0002-0000-4000-8000-000000000002'),
  0,
  'La purga se lleva una noche borrada hace más de 30 días'
);

select is(
  (select count(*)::int from public.sleep_logs
    where id = 'eeee0003-0000-4000-8000-000000000003'),
  1,
  'Y deja la que se borró hace dos: la ventana de deshacer es de 30 días'
);

-- ── El día manda, no el id ──────────────────────────────────────────────
--
-- `water_logs` y `sleep_logs` tienen **dos** claves únicas: la primary key y
-- una por día (`user_id, local_date`). El push resolvía el upsert contra la
-- primary key, y eso alcanza solo mientras el id sea la única forma de que dos
-- filas se pisen.
--
-- Deja de alcanzar en cuanto el id local y el del servidor se separan para el
-- mismo día — pasa al iniciar sesión, porque el id se deriva de la identidad de
-- la cuenta, y pasó a propósito cuando `repararRegistrosViejos` regeneró los
-- del agua—. Ahí el upsert por id no encuentra contra qué chocar, intenta
-- insertar, y la clave del día lo rechaza:
--
--   duplicate key value violates unique constraint "water_logs_one_per_day"
--
-- Una tabla que el servidor rechaza no sube **ninguna** de sus filas, así que
-- el síntoma era el respaldo trabado con un error permanente en pantalla.
--
-- Lo que se prueba es el contrato del que depende el arreglo: que resolviendo
-- contra la clave del día, una fila con **otro** id actualiza la que ya está en
-- vez de chocar. Que el id termine siendo el del teléfono es lo que hace que
-- las dos puntas converjan y el problema no se repita.
insert into public.water_logs (id, user_id, local_date, glasses)
values ('eeee0004-0000-4000-8000-000000000004',
        '77777777-7777-7777-7777-777777777777', current_date - 5, 3);

insert into public.water_logs (id, user_id, local_date, glasses)
values ('eeee0005-0000-4000-8000-000000000005',
        '77777777-7777-7777-7777-777777777777', current_date - 5, 8)
on conflict (user_id, local_date) do update
  set id = excluded.id, glasses = excluded.glasses;

select is(
  (select count(*)::int from public.water_logs
    where user_id = '77777777-7777-7777-7777-777777777777'
      and local_date = current_date - 5),
  1,
  'Un día sigue teniendo una sola fila de agua después del upsert por día'
);

select is(
  (select glasses::int from public.water_logs
    where user_id = '77777777-7777-7777-7777-777777777777'
      and local_date = current_date - 5),
  8,
  'Y se queda con el valor del teléfono, no con el que ya estaba'
);

select is(
  (select id::text from public.water_logs
    where user_id = '77777777-7777-7777-7777-777777777777'
      and local_date = current_date - 5),
  'eeee0005-0000-4000-8000-000000000005',
  'El id converge al del teléfono, así que la próxima vuelta ya no diverge'
);

-- Y el contrato tiene que existir: sin la clave única por día, `on conflict
-- (user_id, local_date)` es un error de sintaxis en tiempo de ejecución y todo
-- lo de arriba dejaría de proteger nada.
select col_is_unique(
  'public', 'sleep_logs', array['user_id', 'local_date'],
  'sleep_logs sigue teniendo una fila por día, que es contra lo que se upserta'
);

-- ── Resolver por día no salva de un id que ya es de otra persona ─────────
--
-- La otra mitad de la misma moneda, y el error que quedó después del arreglo
-- anterior:
--
--   duplicate key value violates unique constraint "sleep_logs_pkey"
--
-- Resolver contra `(user_id, local_date)` arregla el choque **dentro** de la
-- cuenta, pero la primary key sigue siendo global. Si el uuid que manda el
-- teléfono ya está en la fila de otra persona, el `ON CONFLICT` del día no la
-- encuentra —no es de esta cuenta—, Postgres intenta insertar, y el índice de
-- la primary key, que no sabe de RLS, la rechaza.
--
-- Eso deja de ser hipotético mirando de dónde salían los ids: la versión en la
-- que el sufijo de identidad era el literal `'local'` generaba el **mismo**
-- uuid para el mismo día en dos teléfonos distintos, y la primera cuenta que
-- sincronizó se quedó con él. Antes el síntoma era un error de RLS; desde que
-- se resuelve por día, es este.
--
-- Por eso `repararRegistrosViejos` regenera los ids del sueño con la identidad
-- de la cuenta: es lo único que hace que el uuid no pueda ser de otra persona.
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
)
values ('88888888-8888-8888-8888-888888888888',
        '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        't@ceres.test', crypt('secreto-t', gen_salt('bf')), now(), now(), now());

insert into public.sleep_logs (id, user_id, local_date, minutes)
values ('eeee0006-0000-4000-8000-000000000006',
        '88888888-8888-8888-8888-888888888888', current_date - 6, 420);

select throws_ok(
  $$insert into public.sleep_logs (id, user_id, local_date, minutes)
    values ('eeee0006-0000-4000-8000-000000000006',
            '77777777-7777-7777-7777-777777777777', current_date - 6, 480)
    on conflict (user_id, local_date) do update
      set id = excluded.id, minutes = excluded.minutes$$,
  '23505',
  'duplicate key value violates unique constraint "sleep_logs_pkey"',
  'Un id que ya es de otra cuenta choca contra la primary key, no contra el día'
);

-- Con un id propio —el que sale de derivar cuenta y día— la misma noche entra.
insert into public.sleep_logs (id, user_id, local_date, minutes)
values ('eeee0007-0000-4000-8000-000000000007',
        '77777777-7777-7777-7777-777777777777', current_date - 6, 480)
on conflict (user_id, local_date) do update
  set id = excluded.id, minutes = excluded.minutes;

select is(
  (select minutes::int from public.sleep_logs
    where user_id = '77777777-7777-7777-7777-777777777777'
      and local_date = current_date - 6),
  480,
  'Con un id derivado de la cuenta, la misma noche entra sin chocar'
);

select is(
  (select minutes::int from public.sleep_logs
    where id = 'eeee0006-0000-4000-8000-000000000006'),
  420,
  'Y la noche de la otra persona queda como estaba'
);

-- ── Lo que el cliente pasó a subir con las migraciones 43 y 44 ───────────
--
-- Estas tres comprobaciones existen porque las tres cosas estuvieron rotas por
-- **omisión** y no por error: la tabla estaba, el modelo tenía el dato, y nadie
-- había escrito el renglón que los une. Eso no se ve mirando ninguna de las dos
-- puntas por separado, y por eso se fija acá.

-- La hora de la comida se llama como lo que guarda.
select has_column('public', 'meals', 'eaten_at',
  'La comida guarda cuándo se comió, no cuándo se cargó');

-- `logged_at` sigue existiendo, pero ya no es la columna: es el espejo de
-- compatibilidad de la migración 45, para el teléfono que todavía no actualizó.
-- Lo que distingue a una de otra es cuál lleva el `not null`: la canónica es la
-- que la base exige, el espejo es el que la sigue.
select col_not_null('public', 'meals', 'eaten_at',
  'eaten_at es la canónica: la base la exige');
select col_is_null('public', 'meals', 'logged_at',
  'y logged_at es solo el espejo, así que puede faltar');

-- Los recordatorios: el cliente sube **sin id** y resuelve por (usuario, tipo).
-- Si la columna perdiera su default, el push fallaría entero con un not-null y
-- la app no tiene ningún id que mandar.
insert into public.reminders (user_id, kind, enabled, times)
values ('77777777-7777-7777-7777-777777777777', 'water', true,
        array[600, 840, 1080]::smallint[])
on conflict (user_id, kind) do update
  set enabled = excluded.enabled, times = excluded.times;

create temporary table recordatorio on commit drop as
  select id from public.reminders
   where user_id = '77777777-7777-7777-7777-777777777777';

-- La segunda subida es la que importa: con el id adentro del insert, el upsert
-- le reescribiría la primary key a la fila en cada sincronización.
insert into public.reminders (user_id, kind, enabled, times)
values ('77777777-7777-7777-7777-777777777777', 'water', false,
        array[540]::smallint[])
on conflict (user_id, kind) do update
  set enabled = excluded.enabled, times = excluded.times;

select is(
  (select count(*)::int from public.reminders
    where user_id = '77777777-7777-7777-7777-777777777777'),
  1,
  'Subir dos veces el mismo recordatorio deja una sola fila'
);

select is(
  (select id from public.reminders
    where user_id = '77777777-7777-7777-7777-777777777777'),
  (select id from recordatorio),
  'Y no le cambia el id en cada subida'
);

select is(
  (select times from public.reminders
    where user_id = '77777777-7777-7777-7777-777777777777'),
  array[540]::smallint[],
  'Los horarios viajan como minutos desde medianoche'
);

-- Las plantillas de ejercicio, con el mismo juego de columnas que manda el
-- cliente.
insert into public.exercise_templates (
  id, user_id, name, activity_type_id, default_duration_minutes,
  default_intensity, default_distance_meters, default_notes, use_count)
select 'eeee0007-0000-4000-8000-000000000007',
       '77777777-7777-7777-7777-777777777777', 'Caminata del parque',
       id, 40, 'moderate', 3200, null, 3
  from public.activity_types where slug = 'walking';

select is(
  (select default_duration_minutes from public.exercise_templates
    where id = 'eeee0007-0000-4000-8000-000000000007'),
  40,
  'La plantilla que arma la app entra con las columnas que manda'
);

-- ── El puente para el teléfono que todavía no actualizó (migración 45) ───
--
-- Renombrar `logged_at` a `eaten_at` dejó a cada cliente desplegado mandando
-- una columna inexistente. `logged_at` volvió como espejo mantenido por un
-- trigger, y lo que sigue prueba las cuatro combinaciones — porque **una de
-- ellas ya falló** en el primer intento de esa migración.
--
-- La que falló es la del cliente viejo corrigiendo la hora. En un `update`,
-- `eaten_at` no viene en el `set` —PostgREST arma el upsert solo con las
-- columnas que mandó el cliente— así que llega con su valor anterior y nunca es
-- null: la primera versión del trigger se guiaba por eso y descartaba la
-- corrección en silencio. Lo que distingue quién habla es cuál de las dos se
-- movió.

insert into public.meals (id, user_id, slot, local_date, logged_at, source, name)
values ('eeee0008-0000-4000-8000-000000000008',
        '77777777-7777-7777-7777-777777777777', 'lunch', current_date,
        timestamptz '2026-08-19 13:05:00-03', 'manual', 'App vieja');

select is(
  (select eaten_at from public.meals
    where id = 'eeee0008-0000-4000-8000-000000000008'),
  timestamptz '2026-08-19 13:05:00-03',
  'El cliente viejo inserta con logged_at y la hora llega a eaten_at'
);

-- El upsert del push, tal como lo arma PostgREST para un cliente que no manda
-- `eaten_at`. Este es el caso que se rompía.
insert into public.meals (id, user_id, slot, local_date, logged_at, source, name)
values ('eeee0008-0000-4000-8000-000000000008',
        '77777777-7777-7777-7777-777777777777', 'lunch', current_date,
        timestamptz '2026-08-19 14:20:00-03', 'manual', 'App vieja corrige')
on conflict (id) do update
  set logged_at = excluded.logged_at, name = excluded.name;

select is(
  (select eaten_at from public.meals
    where id = 'eeee0008-0000-4000-8000-000000000008'),
  timestamptz '2026-08-19 14:20:00-03',
  'Y si corrige la hora, la corrección no se pierde'
);

insert into public.meals (id, user_id, slot, local_date, eaten_at, source, name)
values ('eeee0009-0000-4000-8000-000000000009',
        '77777777-7777-7777-7777-777777777777', 'dinner', current_date,
        timestamptz '2026-08-19 21:30:00-03', 'manual', 'App nueva');

select is(
  (select logged_at from public.meals
    where id = 'eeee0009-0000-4000-8000-000000000009'),
  timestamptz '2026-08-19 21:30:00-03',
  'El cliente nuevo escribe eaten_at y el espejo lo sigue, así el viejo lo lee'
);

insert into public.meals (id, user_id, slot, local_date, eaten_at, source, name)
values ('eeee0009-0000-4000-8000-000000000009',
        '77777777-7777-7777-7777-777777777777', 'dinner', current_date,
        timestamptz '2026-08-19 22:45:00-03', 'manual', 'App nueva corrige')
on conflict (id) do update
  set eaten_at = excluded.eaten_at, name = excluded.name;

select is(
  (select logged_at from public.meals
    where id = 'eeee0009-0000-4000-8000-000000000009'),
  timestamptz '2026-08-19 22:45:00-03',
  'Y el espejo lo sigue también al corregir'
);

-- Ninguna comida puede quedar con el espejo vacío: si pasara, el cliente viejo
-- la leería sin hora y la saltearía al reconciliar.
select is(
  (select count(*)::int from public.meals where logged_at is null),
  0,
  'Ninguna comida queda sin espejo'
);

-- ── El upsert de day_markers, tal como lo manda la app (migración 46) ────
--
-- La app sube con `onConflict: 'user_id,local_date,kind'`, y el único de la
-- tabla era un índice **parcial** (`where deleted_at is null`): Postgres no lo
-- infiere para un `on conflict` sin el predicado, así que cada push de marcas
-- moría con 42P10 y un día de enfermedad marcado en el teléfono no llegaba
-- nunca a la base. Este bloque es ese mismo upsert contra el esquema real: con
-- el índice parcial falla, con el de la 46 pasa.
select lives_ok(
  $$insert into public.day_markers
      (id, user_id, local_date, kind, severity, note, tags)
    values ('eeee0010-0000-4000-8000-000000000010',
            '77777777-7777-7777-7777-777777777777', current_date - 8, 'sick',
            2, 'Angina', '{}')
    on conflict (user_id, local_date, kind) do update
      set severity = excluded.severity, note = excluded.note$$,
  'El push de una marca nueva entra con el on conflict que manda la app'
);

-- El mismo día otra vez —el push reescribe todo en cada corrida— pisa, no choca.
select lives_ok(
  $$insert into public.day_markers
      (id, user_id, local_date, kind, severity, note, tags)
    values ('eeee0011-0000-4000-8000-000000000011',
            '77777777-7777-7777-7777-777777777777', current_date - 8, 'sick',
            3, 'Angina, peor', '{}')
    on conflict (user_id, local_date, kind) do update
      set severity = excluded.severity, note = excluded.note$$,
  'El push repetido del mismo día pisa la marca en vez de chocar'
);

select is(
  (select count(*)::int from public.day_markers
    where user_id = '77777777-7777-7777-7777-777777777777'
      and local_date = current_date - 8 and kind = 'sick'),
  1,
  'Queda una sola marca por (día, tipo)'
);

select is(
  (select severity::int from public.day_markers
    where user_id = '77777777-7777-7777-7777-777777777777'
      and local_date = current_date - 8 and kind = 'sick'),
  3,
  'Y es la del último push'
);

-- Desmarcar viaja como lápida y volver a marcar la revive: una fila por
-- (día, tipo) siempre, muerta o viva. Es lo que hace imposible el estado que
-- el índice parcial permitía —una muerta y una viva del mismo día—.
update public.day_markers set deleted_at = now()
 where user_id = '77777777-7777-7777-7777-777777777777'
   and local_date = current_date - 8 and kind = 'sick';

select lives_ok(
  $$insert into public.day_markers
      (id, user_id, local_date, kind, severity, note, tags, deleted_at)
    values ('eeee0012-0000-4000-8000-000000000012',
            '77777777-7777-7777-7777-777777777777', current_date - 8, 'sick',
            1, null, '{}', null)
    on conflict (user_id, local_date, kind) do update
      set severity = excluded.severity, note = excluded.note,
          deleted_at = excluded.deleted_at$$,
  'Marcar de nuevo un día desmarcado revive la lápida en vez de duplicarla'
);

select is(
  (select count(*)::int from public.day_markers
    where user_id = '77777777-7777-7777-7777-777777777777'
      and local_date = current_date - 8 and kind = 'sick'
      and deleted_at is null),
  1,
  'La marca revivida queda viva y sigue siendo una sola'
);

select * from finish();
rollback;
