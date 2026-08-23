-- El acceso profesional (migración 32).
--
-- Acá se prueba lo único que importa de esa migración: que abrir los datos a
-- una nutricionista no abra nada más que lo concedido, y que dejar de
-- concederlo cierre de verdad. Son datos de salud de una persona; el resto de
-- la funcionalidad puede fallar y arreglarse mañana, esto no.
--
-- Lo que se comprueba no es que el backoffice no muestre de más, sino que el
-- servidor **no devuelve** de más, venga la consulta de donde venga.
--
-- Correr con:  supabase test db

create extension if not exists pgtap with schema extensions;

begin;
select plan(23);

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

update public.profiles set display_name = 'Ana'
 where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

-- El día de Ana: una comida con su ítem, un peso, una medida y un vaso de
-- agua. Uno de cada categoría, que es lo que hay que poder abrir por separado.
-- Sin `total_kcal`: ese campo lo escribe **solo** el trigger de totales a
-- partir de los ítems (D-11). Ponerlo a mano acá daría un número que el primer
-- insert de un ítem pisa, y el test quedaría comparando contra algo que la
-- base ya reemplazó.
insert into public.meals (id, user_id, slot, local_date, name)
values ('dddddddd-0000-0000-0000-000000000001',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'lunch', current_date,
        'Milanesa con puré');

insert into public.meal_items (id, meal_id, name, quantity, unit, kcal)
values ('dddddddd-0000-0000-0000-000000000002',
        'dddddddd-0000-0000-0000-000000000001',
        'Milanesa de carne', 1, 'unidad', 289);

insert into public.weight_logs (id, user_id, local_date, weight_kg)
values ('dddddddd-0000-0000-0000-000000000003',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', current_date, 100.0);

insert into public.water_logs (id, user_id, local_date, glasses)
values ('dddddddd-0000-0000-0000-000000000004',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', current_date, 6);

-- ── El código no existe hasta que alguien lo pide ────────────────────────
-- Un código que existe es una superficie que se puede adivinar. Las cuentas
-- que nunca ejercen de profesional no tienen por qué tener uno.
--
-- Se lee `profiles` directo porque todavía no se asumió ninguna identidad: acá
-- el test sigue siendo el dueño de la base.
select is(
  (select care_code from public.profiles
    where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
  null,
  'Una cuenta nueva no trae código de profesional'
);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}', true);

select matches(
  public.ensure_care_code(),
  '^NT-[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{6}$',
  'La profesional pide su código y sale con el formato dictable'
);

select is(
  public.ensure_care_code(),
  (select care_code from public.profiles
    where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
  'Pedirlo dos veces devuelve el mismo, no uno nuevo'
);

-- ── El código, a mano, para poder dictárselo a Ana ───────────────────────
-- Se copia **acá** y no al principio: a diferencia de `pal_code`, que lo pone
-- un trigger al crear la cuenta, este no existe hasta que la profesional lo
-- pide. Copiarlo antes guardaba un null, y Ana terminaba concediendo acceso
-- "al código null" — que es exactamente lo que hacía fallar la suite.
--
-- `reset role` vuelve al dueño de la base para poder crear la temporal; el
-- `set local role` de abajo retoma la identidad.
reset role;

create temporary table codigos on commit drop as
  select id, care_code from public.profiles;
grant select on codigos to authenticated;

set local role authenticated;

-- ── Sin permiso no ve nada ───────────────────────────────────────────────
-- El estado inicial y el más importante: tener cuenta y código no abre nada.
select is(
  (select count(*)::int from public.meals
    where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0,
  'Sin permiso, la profesional no ve las comidas de Ana'
);

select is(
  (select count(*)::int from public.weight_logs
    where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0,
  'Ni su peso'
);

select is(
  (select count(*)::int from public.care_patients),
  0,
  'Ni aparece Ana en su lista de pacientes'
);

-- ── Nadie se concede acceso a sí mismo ───────────────────────────────────
-- La política de insert exige `owner_id = auth.uid()`, así que este INSERT no
-- alcanza ninguna fila. Se verifica el resultado y no una excepción: esperar
-- un error daría verde por el motivo equivocado el día que la policy se rompa.
select throws_ok(
  $q$insert into public.care_grants
       (owner_id, professional_id, status, share_meals)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'accepted', true)$q$,
  '42501',
  null,
  'La profesional no puede concederse el permiso ella misma'
);

-- ── Ana concede, y solo comidas ──────────────────────────────────────────
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}', true);

-- `ok(... is not null)` y no `isnt(..., null)`: el `null` pelado deja a pgTAP
-- sin poder resolver el tipo polimórfico y el test falla por la firma, no por
-- lo que se quería probar.
select ok(
  public.grant_care_access(
    (select care_code from codigos
      where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
    p_share_meals => true) is not null,
  'Ana concede acceso a las comidas, y nada más'
);

-- ── Lo concedido se ve; lo demás no ──────────────────────────────────────
-- Esta es la prueba de que las categorías son categorías y no un interruptor
-- único disfrazado.
select set_config('request.jwt.claims',
  '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}', true);

select is(
  (select name from public.meals
    where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  'Milanesa con puré',
  'Ahora sí ve la comida'
);

select is(
  (select name from public.meal_items
    where meal_id = 'dddddddd-0000-0000-0000-000000000001'),
  'Milanesa de carne',
  'Y su detalle, que es de lo que se trata el seguimiento'
);

select is(
  (select count(*)::int from public.weight_logs
    where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0,
  'Pero el peso sigue cerrado: esa categoría no se prendió'
);

select is(
  (select count(*)::int from public.water_logs
    where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0,
  'Y el agua tampoco'
);

select is(
  (select patient_name from public.care_patients),
  'Ana',
  'Ana aparece en la lista de pacientes, con su nombre'
);

-- ── El perfil no se abre por policy ──────────────────────────────────────
-- Tests estructurales, y están acá por un antecedente concreto: la policy que
-- abría `profiles` a los pals decía en su comentario que abría "solo el
-- nombre" y abría la fila entera —nacimiento, altura y el código que es la
-- llave para pedir vínculos a nombre de otro— (migración 28).
--
-- La primera versión de esta migración repetía ese error. Que la superficie
-- sea una vista de columnas contadas es lo que hace que no se repita, y esto
-- es lo que lo fija.
select is(
  (select count(*)::int from public.profiles
    where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0,
  'El acceso concedido no abre la tabla de perfiles'
);

select columns_are(
  'public', 'care_patients',
  array['grant_id', 'patient_id', 'patient_name', 'biological_sex',
        'birth_date', 'height_cm', 'unit_system', 'share_meals',
        'share_photos', 'share_body', 'share_wellbeing', 'accepted_at',
        'expires_at',
        -- Desde cuándo lleva registro (migración 41). El panel la necesita
        -- para no contar como huecos los días anteriores a la cuenta, y no se
        -- puede calcular sola: solo consulta el período elegido.
        'tracking_since'],
  'La lista de pacientes tiene las columnas del cálculo, y ningún código'
);

select columns_are(
  'public', 'care_professionals', array['id', 'display_name'],
  'Y del profesional, el dueño ve el nombre y nada más'
);

-- ── Solo lectura ─────────────────────────────────────────────────────────
-- No hay una sola política de escritura para la profesional. Si mañana el
-- backoffice tuviera un bug que intenta corregir una comida, la base lo frena.
--
-- Se verifica el efecto y no una excepción: un UPDATE o un DELETE que RLS
-- filtra **no lanza**, simplemente no alcanza ninguna fila. Esperar un error
-- daría verde por el motivo equivocado el día que la policy se rompa y la
-- escritura sí pase.
update public.meals set total_kcal = 100
 where id = 'dddddddd-0000-0000-0000-000000000001';

select is(
  (select total_kcal from public.meals
    where id = 'dddddddd-0000-0000-0000-000000000001'),
  289,
  'Ver no es editar: la comida de Ana queda como la dejó el trigger'
);

delete from public.meals
 where id = 'dddddddd-0000-0000-0000-000000000001';

select is(
  (select count(*)::int from public.meals
    where id = 'dddddddd-0000-0000-0000-000000000001'),
  1,
  'Ni borrarla'
);

-- ── El permiso no se lo amplía la profesional ────────────────────────────
-- Sin esto, el acceso a comidas sería en la práctica acceso a todo: le
-- alcanzaría con prender las otras categorías de su propia fila.
update public.care_grants set share_body = true, share_wellbeing = true
 where owner_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

select is(
  (select count(*)::int from public.weight_logs
    where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0,
  'No puede prenderse sola las categorías que Ana no le dio'
);

-- ── Ana suma el cuerpo ───────────────────────────────────────────────────
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}', true);

select ok(
  public.grant_care_access(
    (select care_code from codigos
      where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
    p_share_meals => true, p_share_body => true) is not null,
  'Ana suma el peso al permiso que ya existía'
);

select set_config('request.jwt.claims',
  '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}', true);

select is(
  (select weight_kg::numeric(5,1) from public.weight_logs
    where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  100.0::numeric(5,1),
  'Y recién ahora ve el peso'
);

-- ── Revocar cierra ───────────────────────────────────────────────────────
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}', true);

select public.revoke_care_access(
  (select id from public.care_grants
    where owner_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'));

select set_config('request.jwt.claims',
  '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}', true);

select is(
  (select count(*)::int from public.meals
    where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
  + (select count(*)::int from public.weight_logs
      where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0,
  'Revocado deja de ver todo, en el acto'
);

-- ── Una desconocida nunca vio nada ───────────────────────────────────────
-- El permiso es por par: que exista uno no abre la puerta a cualquiera con
-- cuenta.
select set_config('request.jwt.claims',
  '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}', true);

select is(
  (select count(*)::int from public.meals
    where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0,
  'Una cuenta sin vínculo no ve nada de Ana en ningún momento'
);

select * from finish();
rollback;
