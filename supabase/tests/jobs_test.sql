-- Los jobs de mantenimiento borran, y por eso se prueban.
--
-- Una purga mal escrita no se nota: no falla, no avisa, y lo que se lleva de
-- más no vuelve. Acá se comprueban las dos mitades de la única regla que
-- tiene: que se vaya lo que ya nadie puede ver, y que **no** se vaya lo que
-- todavía se mira.
--
-- Todas las comprobaciones son `is` sobre un conteo y `lives_ok`, que es lo
-- que usa el resto de la suite. La primera versión usaba `isnt_empty` —la
-- única función de pgTAP que no aparecía en ningún otro archivo— y el paso
-- entero fallaba en CI mientras pasaba contra la base de producción, que tiene
-- otra versión de la extensión. Un test que solo corre en un lado no sirve
-- para nada.
--
-- Correr con:  supabase test db

create extension if not exists pgtap with schema extensions;

begin;
select plan(7);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'jobs-a@ceres.test', crypt('secreto-a', gen_salt('bf')),
   now(), now(), now());

-- ── shared_days ──────────────────────────────────────────────────────────
-- Cuatro días: hoy, el borde de la ventana que ve un pal, uno viejo y uno
-- muy viejo.
insert into public.shared_days (user_id, local_date, meals, activity_minutes)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', current_date, '[]'::jsonb, 0),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', current_date - 7, '[]'::jsonb, 0),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', current_date - 40, '[]'::jsonb, 0),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', current_date - 400, '[]'::jsonb, 0);

select is(
  (select count(*)::int from public.shared_days
    where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  4,
  'Arrancan las cuatro filas'
);

select lives_ok(
  'select public.purge_shared_days()',
  'La purga corre sin romper nada'
);

select is(
  (select count(*)::int from public.shared_days
    where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  2,
  'Se van las dos viejas y quedan las dos de la ventana'
);

-- El día de hoy es el que se está mirando ahora mismo: que sobreviva no es un
-- detalle, es la diferencia entre limpiar y romper.
select is(
  (select count(*)::int from public.shared_days
    where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      and local_date = current_date),
  1,
  'El día de hoy sigue estando'
);

-- El borde exacto de lo que la app deja abrir. Si se fuera acá, un pal vería
-- "no cargó nada" en un día que sí tenía cosas.
select is(
  (select count(*)::int from public.shared_days
    where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      and local_date = current_date - 7),
  1,
  'El día más viejo que se puede mirar sigue estando'
);

-- Y que la purga esté colgada del job nocturno, no suelta esperando que
-- alguien la llame: una función de limpieza que no está programada es una
-- función que no limpia.
--
-- Se comprueba **corriendo el job**, no leyendo el texto de su definición: lo
-- que importa es que la fila vieja desaparezca, no cómo esté escrito adentro.
insert into public.shared_days (user_id, local_date, meals, activity_minutes)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', current_date - 90, '[]'::jsonb, 0);

select lives_ok(
  'select public.purge_soft_deleted()',
  'El job nocturno se lleva los días viejos de shared_days'
);

select is(
  (select count(*)::int from public.shared_days
    where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  2,
  'Después del job nocturno quedan solo los dos días visibles'
);

select * from finish();
rollback;
