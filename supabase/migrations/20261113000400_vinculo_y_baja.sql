-- 55 · El vínculo con la nutricionista: todo o nada, y la baja de los dos
-- lados.
--
-- Tres decisiones de producto (13 de noviembre):
--
-- 1. **La profesional ve todo.** El paciente ya no elige categorías: si se
--    sumó a su nutricionista, ella ve comidas, fotos, peso, medidas,
--    actividad, agua y sueño. Las columnas `share_*` quedan (las usan RLS, el
--    tablero y el panel) pero siempre en `true`, y la base lo hace cumplir.
-- 2. **La baja es de los dos lados.** El paciente ya podía cortar el acceso
--    (`revoke_care_access`); ahora la profesional también puede dar de baja
--    a un paciente suyo (`discharge_patient`).
-- 3. **Sin nutricionista, cada uno vuelve a su plan.** Si la IA se la pagaba
--    la profesional, al darse de baja queda en Gratis; si pagaba Premium,
--    sigue en Premium. Para eso una cuenta **sin fila** en `account_plans`
--    pasa a ser Gratis (antes era Premium), y las cuentas que ya existen se
--    anotan como Premium para que nadie pierda nada con esta migración.

-- ── 1 · Todo compartido ───────────────────────────────────────────────────
update public.care_grants
   set share_meals = true,
       share_photos = true,
       share_body = true,
       share_wellbeing = true
 where not (share_meals and share_photos and share_body and share_wellbeing);

alter table public.care_grants
  alter column share_meals     set default true,
  alter column share_photos    set default true,
  alter column share_body      set default true,
  alter column share_wellbeing set default true;

-- El paciente ya no puede apagar categorías desde la app vieja.
revoke update (share_meals, share_photos, share_body, share_wellbeing)
  on public.care_grants from authenticated;

-- Y lo que entre por cualquier camino (la función, un script con la clave de
-- servicio) queda con todo prendido.
create or replace function public.care_grants_share_all()
returns trigger
language plpgsql
as $$
begin
  new.share_meals := true;
  new.share_photos := true;
  new.share_body := true;
  new.share_wellbeing := true;
  return new;
end;
$$;

drop trigger if exists care_grants_share_all on public.care_grants;
create trigger care_grants_share_all
  before insert or update on public.care_grants
  for each row execute function public.care_grants_share_all();

-- `grant_care_access` conserva la firma (la usa la app publicada) pero ya no
-- mira las categorías: las pone el trigger de arriba.

-- ── 2 · La profesional da de baja ────────────────────────────────────────
-- Solo a sus pacientes. Deja la fila con `revoked_at`, igual que cuando corta
-- el paciente: un acceso a datos de salud que desaparece sin rastro no se
-- puede auditar. Devuelve cuántos accesos cortó (0 = no era su paciente).
create or replace function public.discharge_patient(p_patient uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  n integer;
begin
  update public.care_grants
     set status = 'revoked', revoked_at = now()
   where owner_id = p_patient
     and professional_id = auth.uid()
     and revoked_at is null;
  get diagnostics n = row_count;
  if n = 0 then
    raise exception 'ERR_NOT_FOUND' using hint = 'No es un paciente tuyo.';
  end if;
  return n;
end;
$$;

revoke all on function public.discharge_patient(uuid) from public;
grant execute on function public.discharge_patient(uuid) to authenticated;

-- ── 3 · Sin fila, Gratis ─────────────────────────────────────────────────
-- Las cuentas de hoy quedan Premium, como venían. Las nuevas nacen Gratis.
insert into public.account_plans (user_id, plan)
select p.id, 'premium'
  from public.profiles p
on conflict (user_id) do nothing;

create or replace function public.effective_plan()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when ap.plan = 'pro' then 'pro'
    when ap.plan = 'premium' then 'premium'
    -- Gratis, o sin fila: si su nutricionista es Pro, la IA se la paga ella.
    when exists (
      select 1
        from public.care_grants g
        join public.account_plans pro
          on pro.user_id = g.professional_id and pro.plan = 'pro'
       where g.owner_id = auth.uid()
         and g.status = 'accepted'
         and g.revoked_at is null
         and (g.expires_at is null or g.expires_at > now())
    ) then 'patient'
    else 'free'
  end
  from (select auth.uid() as id) me
  left join public.account_plans ap on ap.user_id = me.id;
$$;

revoke all on function public.effective_plan() from public;
grant execute on function public.effective_plan() to authenticated;

-- down
-- (effective_plan vuelve a la versión de la migración 49; las filas premium
--  agregadas acá no se pueden distinguir de las demás y quedan)
-- revoke all on function public.discharge_patient(uuid) from authenticated;
-- drop function if exists public.discharge_patient(uuid);
-- drop trigger if exists care_grants_share_all on public.care_grants;
-- drop function if exists public.care_grants_share_all();
-- grant update (share_meals, share_photos, share_body, share_wellbeing)
--   on public.care_grants to authenticated;
