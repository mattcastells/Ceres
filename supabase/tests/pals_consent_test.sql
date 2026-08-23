-- El consentimiento de Pals (migración 28).
--
-- Esta suite existe por un agujero concreto: `pals_update` dejaba que **quien
-- manda la solicitud** la aceptara solo, y desde ahí veía el día del otro sin
-- que el otro hiciera nada. Lo que se prueba acá no es que la app no ofrezca
-- ese botón, sino que el servidor rechaza la escritura venga de donde venga.
--
-- Correr con:  supabase test db

create extension if not exists pgtap with schema extensions;

begin;
select plan(10);

-- ── A, B y C ─────────────────────────────────────────────────────────────
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
   'b@ceres.test', crypt('secreto-b', gen_salt('bf')), now(), now(), now()),
  ('33333333-3333-3333-3333-333333333333',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'c@ceres.test', crypt('secreto-c', gen_salt('bf')), now(), now(), now());

update public.profiles set display_name = 'Ana', birth_date = '1990-05-01',
       height_cm = 170
 where id = '22222222-2222-2222-2222-222222222222';

insert into public.shared_days (user_id, local_date, meals)
values ('22222222-2222-2222-2222-222222222222', current_date,
        '[{"slot":"lunch","name":"Milanesa","kcal":620}]'::jsonb);

-- Los códigos se copian antes de asumir una identidad: bajo RLS el propio test
-- ya no puede leer el perfil ajeno, que es justamente lo que se quiere.
create temporary table codigos on commit drop as
  select id, pal_code from public.profiles;
grant select on codigos to authenticated;

-- ── La vista no tiene más columnas que las dos que necesita la lista ─────
-- Es un test estructural a propósito: la policy anterior "abría solo el
-- nombre" según su comentario y abría la fila entera. Que la superficie sea
-- una vista de dos columnas es lo que hace que eso no pueda repetirse.
select columns_are(
  'public', 'pal_profiles', array['id', 'display_name'],
  'La vista de pals expone el id y el nombre, y nada más'
);

-- ── A le manda una solicitud a B ─────────────────────────────────────────
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

select is(
  public.request_pal(
    (select pal_code from codigos
      where id = '22222222-2222-2222-2222-222222222222')),
  'sent',
  'A le manda una solicitud a B'
);

-- ── Lo que A NO puede hacer con su propia solicitud ──────────────────────
-- Un UPDATE que RLS filtra no lanza: no alcanza ninguna fila. Por eso se
-- verifica el resultado y no la excepción — esperar un error acá daría verde
-- por el motivo equivocado el día que la policy se rompa y el update sí pase.
update public.pals set status = 'accepted', responded_at = now()
 where requester_id = '11111111-1111-1111-1111-111111111111';

select is(
  (select status from public.pals
    where requester_id = '11111111-1111-1111-1111-111111111111'),
  'pending',
  'El que pide el vínculo no puede aceptárselo solo'
);

select is(
  (select count(*)::int from public.shared_days
    where user_id = '22222222-2222-2222-2222-222222222222'),
  0,
  'Y por lo tanto sigue sin ver el día de B'
);

update public.pals set addressee_id = '33333333-3333-3333-3333-333333333333'
 where requester_id = '11111111-1111-1111-1111-111111111111';

select is(
  (select addressee_id from public.pals
    where requester_id = '11111111-1111-1111-1111-111111111111'),
  '22222222-2222-2222-2222-222222222222'::uuid,
  'Tampoco puede reapuntar la solicitud a un tercero'
);

-- ── Con la solicitud pendiente, el perfil de B sigue cerrado ─────────────
select is(
  (select count(*)::int from public.profiles
    where id = '22222222-2222-2222-2222-222222222222'),
  0,
  'Una solicitud pendiente no abre el perfil de B'
);

select is(
  (select display_name from public.pal_profiles
    where id = '22222222-2222-2222-2222-222222222222'),
  'Ana',
  'Pero sí el nombre, que es lo que la pantalla necesita para decidir'
);

-- ── Y el código propio no se reescribe desde el cliente ──────────────────
-- Sin esto, el índice único de `pal_code` es un oráculo de enumeración que
-- esquiva el límite de 20 solicitudes por día de `request_pal`.
select throws_ok(
  $q$update public.profiles set pal_code = 'ABCDEFGH'
      where id = '11111111-1111-1111-1111-111111111111'$q$,
  '23514',
  null,
  'Nadie reescribe su código de pal, ni para probar los ajenos'
);

-- ── B, que sí recibió la solicitud, acepta ───────────────────────────────
select set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);

-- Aceptar cambiando de quién viene el vínculo dejaría a C adentro sin haberlo
-- pedido. El `with check` de la policy no lo ve —mira la fila resultante, no
-- la anterior—, así que lo frena el trigger.
select throws_ok(
  $q$update public.pals
        set status = 'accepted',
            requester_id = '33333333-3333-3333-3333-333333333333'
      where addressee_id = '22222222-2222-2222-2222-222222222222'$q$,
  '23514',
  null,
  'Aceptar no puede cambiar de quién viene el vínculo'
);

update public.pals set status = 'accepted', responded_at = now()
 where addressee_id = '22222222-2222-2222-2222-222222222222';

select is(
  (select status from public.pals
    where addressee_id = '22222222-2222-2222-2222-222222222222'),
  'accepted',
  'El que recibe la solicitud sí la acepta'
);

select * from finish();
rollback;
