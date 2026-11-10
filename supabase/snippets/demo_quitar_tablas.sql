-- Saca las tablas del escenario de demostración (migración 49).
--
-- Correr **después** de `node tool/demo/limpiar.mjs --si`, desde el SQL
-- Editor. No toca nada anterior a la migración 49: las devoluciones y los
-- informes (migración 48) son parte del producto real y se quedan.
--
-- Después de correrlo, las funciones de IA siguen andando para todos: si
-- `effective_plan()` no existe, `_shared/plan.ts` trata a todos como Premium.
-- Igual conviene sacar el corte de las funciones en la próxima versión.

drop function if exists public.my_organization();
drop function if exists public.is_org_member(uuid) cascade;
drop table if exists public.org_members;
drop table if exists public.organizations;
drop function if exists public.effective_plan();
drop table if exists public.account_plans;
