-- 50 · Permisos explícitos para `service_role`.
--
-- `service_role` es el rol de administración: lo usan `delete-account` y los
-- scripts de `tool/demo/`, nunca un cliente. Saltea RLS por diseño, pero eso
-- no le da permisos de tabla: hasta ahora los tenía porque los proyectos de
-- Supabase los otorgaban solos al crear cada tabla, y las versiones nuevas de
-- la plataforma ya no lo hacen. Una base levantada de cero (CI, local) quedaba
-- con un `service_role` que no podía leer ni `activity_types`.
--
-- Se otorga explícito, y también para las tablas futuras, para que no dependa
-- de cómo se creó el proyecto.
grant select, insert, update, delete on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to service_role;
grant execute on all functions in schema public to service_role;

alter default privileges in schema public
  grant select, insert, update, delete on tables to service_role;
alter default privileges in schema public
  grant usage, select on sequences to service_role;
alter default privileges in schema public
  grant execute on functions to service_role;
