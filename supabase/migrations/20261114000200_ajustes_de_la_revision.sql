-- 57 · Lo que encontró la revisión de la 56.
--
-- 1. Las funciones de ayuda (`has_active_professional`,
--    `current_professional_name`, `is_professional`) quedaban ejecutables por
--    cualquier sesión: Supabase les da `execute` a `authenticated` por
--    defecto y el `revoke … from public` no lo saca. Con eso un paciente podía
--    preguntar quién es la nutricionista de otro.
-- 2. "Profesional" es plan Pro o miembro de un consultorio. El código ya no
--    cuenta: abrir el panel una vez por error (que pide el código) dejaba la
--    cuenta marcada como profesional y ya no podía sumarse a nadie.
-- 3. Sumar a alguien al consultorio no le abre pacientes sin que acepte: solo
--    se suman cuentas sin pacientes propios. Y todos los rechazos dicen lo
--    mismo, para que el panel no sirva para averiguar quién es paciente.
-- 4. Sacar a una profesional le devuelve el plan que tenía antes de entrar.
-- 5. Solo la titular saca a quien administra.
-- 6. `invite_patient` contesta igual sea la cuenta que sea.
-- 7. Un acceso vencido no cuenta como "tu nutricionista": se cierra antes de
--    sumarse a otra, y `reassign_patient` no lo reabre sin vencimiento.
-- 8. Sumarse por código cierra la invitación pendiente de esa misma
--    profesional, y el paciente no ve invitaciones de quien ya lo atiende.
-- 9. `care_invites`: sin escritura directa ni siquiera por error de RLS.

-- ── 1 · Las funciones de ayuda, solo para las de definidor ───────────────
revoke execute on function public.has_active_professional(uuid) from authenticated, anon;
revoke execute on function public.current_professional_name(uuid) from authenticated, anon;
revoke execute on function public.is_professional(uuid) from authenticated, anon;

revoke insert, update, delete on public.care_invites from authenticated, anon;

-- ── 2 · Qué es una cuenta profesional ────────────────────────────────────
create or replace function public.is_professional(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.account_plans
                  where user_id = p_user and plan = 'pro')
      or exists (select 1 from public.org_members where user_id = p_user);
$$;

-- Vigente = aceptado, sin revocar y sin vencer. Es lo mismo que mira
-- `has_care_access`; acá lo usan las reglas de "una sola nutricionista".
create or replace function public.has_active_professional(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.care_grants g
     where g.owner_id = p_user
       and g.status = 'accepted'
       and g.revoked_at is null
       and (g.expires_at is null or g.expires_at > now())
  );
$$;

-- Cierra los accesos vencidos que quedaron "abiertos": el índice de una sola
-- nutricionista los cuenta, y así no traban sumarse a otra.
create or replace function public.close_expired_grants(p_user uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.care_grants
     set status = 'revoked', revoked_at = now()
   where owner_id = p_user
     and revoked_at is null
     and expires_at is not null
     and expires_at <= now();
$$;

revoke all on function public.close_expired_grants(uuid) from public;
revoke execute on function public.close_expired_grants(uuid) from authenticated, anon;

-- ── 7 y 8 · Sumarse por código ───────────────────────────────────────────
create or replace function public.grant_care_access(
  p_code            text,
  p_share_meals     boolean default false,
  p_share_photos    boolean default false,
  p_share_body      boolean default false,
  p_share_wellbeing boolean default false,
  p_expires_at      timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  professional uuid;
  grant_id     uuid;
begin
  select id into professional
    from public.profiles
   where care_code = upper(trim(p_code));

  if professional is null then
    raise exception 'ERR_NOT_FOUND' using hint = 'Ese código no existe.';
  end if;

  if professional = auth.uid() then
    raise exception 'ERR_VALIDATION' using hint = 'Ese código es el tuyo.';
  end if;

  if public.is_professional(auth.uid()) then
    raise exception 'ERR_VALIDATION' using hint =
      'Esta es una cuenta profesional. Para registrar tus comidas usá una cuenta personal.';
  end if;

  perform public.close_expired_grants(auth.uid());

  if exists (
    select 1 from public.care_grants
     where owner_id = auth.uid() and professional_id <> professional
       and status = 'accepted' and revoked_at is null
  ) then
    raise exception 'ERR_CONFLICT' using hint = format(
      'Ya estás con %s. Date de baja primero para sumarte a otra nutricionista.',
      public.current_professional_name(auth.uid()));
  end if;

  insert into public.care_grants as g (
    owner_id, professional_id, status, expires_at, accepted_at
  )
  values (auth.uid(), professional, 'accepted', p_expires_at, now())
  on conflict (owner_id, professional_id) do update
     set status      = 'accepted',
         expires_at  = excluded.expires_at,
         accepted_at = now(),
         revoked_at  = null
  returning g.id into grant_id;

  -- Si ella ya lo había invitado, la invitación queda resuelta.
  update public.care_invites
     set status = 'accepted', responded_at = now()
   where professional_id = professional
     and status = 'pending'
     and email = (select lower(email) from auth.users where id = auth.uid());

  return grant_id;
end $$;

-- ── Aceptar una invitación ───────────────────────────────────────────────
create or replace function public.accept_care_invite(p_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  inv      public.care_invites;
  grant_id uuid;
begin
  select * into inv from public.care_invites
   where id = p_id and status = 'pending'
     and email = (select lower(email) from auth.users where id = auth.uid());

  if inv.id is null then
    raise exception 'ERR_NOT_FOUND' using hint = 'Esa invitación ya no está vigente.';
  end if;
  if public.is_professional(auth.uid()) then
    raise exception 'ERR_VALIDATION' using hint =
      'Esta es una cuenta profesional. Para registrar tus comidas usá una cuenta personal.';
  end if;

  perform public.close_expired_grants(auth.uid());

  if exists (
    select 1 from public.care_grants
     where owner_id = auth.uid() and professional_id <> inv.professional_id
       and status = 'accepted' and revoked_at is null
  ) then
    raise exception 'ERR_CONFLICT' using hint = format(
      'Ya estás con %s. Date de baja primero para sumarte a otra nutricionista.',
      public.current_professional_name(auth.uid()));
  end if;

  insert into public.care_grants as g (owner_id, professional_id, status, accepted_at)
  values (auth.uid(), inv.professional_id, 'accepted', now())
  on conflict (owner_id, professional_id) do update
     set status = 'accepted', accepted_at = now(), revoked_at = null,
         expires_at = null
  returning g.id into grant_id;

  update public.care_invites
     set status = 'accepted', responded_at = now()
   where id = inv.id;

  return grant_id;
end;
$$;

-- El paciente no ve invitaciones de quien ya lo atiende.
create or replace function public.my_care_invites()
returns table (
  id                uuid,
  professional_id   uuid,
  professional_name text,
  org_name          text,
  created_at        timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select i.id, i.professional_id, p.display_name, o.name, i.created_at
    from public.care_invites i
    join public.profiles p on p.id = i.professional_id
    left join public.org_members om on om.user_id = i.professional_id
    left join public.organizations o on o.id = om.org_id
   where i.status = 'pending'
     and i.email = (select lower(email) from auth.users where id = auth.uid())
     and not exists (
       select 1 from public.care_grants g
        where g.owner_id = auth.uid()
          and g.professional_id = i.professional_id
          and g.status = 'accepted' and g.revoked_at is null
     )
   order by i.created_at desc;
$$;

-- ── 6 · Invitar contesta igual sea la cuenta que sea ─────────────────────
-- Una cuenta profesional queda invitada como cualquiera; si intenta aceptar,
-- es ella la que recibe el "usá una cuenta personal".
create or replace function public.invite_patient(p_email text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email  text := lower(trim(p_email));
  target   uuid;
  existing uuid;
begin
  if not public.is_professional(auth.uid()) then
    raise exception 'ERR_FORBIDDEN' using hint = 'Solo una cuenta profesional da de alta pacientes.';
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'ERR_VALIDATION' using hint = 'Revisá el mail.';
  end if;

  select id into target from auth.users where lower(email) = v_email;

  if target = auth.uid() then
    raise exception 'ERR_VALIDATION' using hint = 'Ese mail es el tuyo.';
  end if;
  -- "Ya es tu paciente" no revela nada que ella no sepa.
  if target is not null and exists (
    select 1 from public.care_grants
     where owner_id = target and professional_id = auth.uid()
       and status = 'accepted' and revoked_at is null
  ) then
    raise exception 'ERR_CONFLICT' using hint = 'Ya es tu paciente.';
  end if;

  select id into existing from public.care_invites
   where professional_id = auth.uid() and email = v_email and status = 'pending';
  if existing is not null then
    return existing;
  end if;

  insert into public.care_invites (professional_id, email)
  values (auth.uid(), v_email)
  returning id into existing;
  return existing;
end;
$$;

-- ── 7 · Reasignar solo un acceso vigente ─────────────────────────────────
create or replace function public.reassign_patient(p_patient uuid, p_to uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_pro uuid;
  grant_id    uuid;
begin
  select professional_id into current_pro
    from public.care_grants
   where owner_id = p_patient and status = 'accepted' and revoked_at is null
     and (expires_at is null or expires_at > now());

  if current_pro is null or not public.manages_professional(current_pro) then
    raise exception 'ERR_NOT_FOUND' using hint = 'No es un paciente del consultorio.';
  end if;
  if not public.manages_professional(p_to) then
    raise exception 'ERR_VALIDATION' using hint = 'Esa profesional no es del consultorio.';
  end if;
  if current_pro = p_to then
    raise exception 'ERR_VALIDATION' using hint = 'Ya es su profesional.';
  end if;

  update public.care_grants
     set status = 'revoked', revoked_at = now()
   where owner_id = p_patient and professional_id = current_pro
     and revoked_at is null;

  insert into public.care_grants as g (owner_id, professional_id, status, accepted_at)
  values (p_patient, p_to, 'accepted', now())
  on conflict (owner_id, professional_id) do update
     set status = 'accepted', accepted_at = now(), revoked_at = null,
         expires_at = null
  returning g.id into grant_id;

  return grant_id;
end;
$$;

-- ── 3 y 4 · Sumar y sacar profesionales ──────────────────────────────────
-- El plan que tenía antes de entrar, para devolvérselo al salir: `none` = no
-- tenía fila; `null` = entró antes de esta migración y no se sabe, así que al
-- salir su plan no se toca.
alter table public.org_members add column if not exists plan_before text;

create or replace function public.org_add_member(p_email text, p_role text default 'professional')
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  my_org  uuid;
  my_role text;
  target  uuid;
  before  text;
begin
  select org_id, role into my_org, my_role
    from public.org_members where user_id = auth.uid();

  if my_org is null or my_role not in ('owner', 'admin') then
    raise exception 'ERR_FORBIDDEN' using hint = 'Solo quien administra el consultorio suma profesionales.';
  end if;
  if p_role not in ('admin', 'professional') then
    raise exception 'ERR_VALIDATION' using hint = 'Rol inválido.';
  end if;
  if p_role = 'admin' and my_role <> 'owner' then
    raise exception 'ERR_FORBIDDEN' using hint = 'Solo la titular nombra a quien administra.';
  end if;

  select id into target from auth.users
   where lower(email) = lower(trim(p_email));

  -- Una sola respuesta para todo lo que no se puede sumar: que no exista, que
  -- sea paciente, que ya atienda pacientes por su cuenta (sumarla abriría sus
  -- datos sin que nadie lo acepte) o que esté en otro consultorio.
  if target is null
     or target = auth.uid()
     or exists (select 1 from public.org_members where user_id = target)
     or public.has_active_professional(target)
     or exists (select 1 from public.care_grants
                 where professional_id = target
                   and status = 'accepted' and revoked_at is null)
  then
    raise exception 'ERR_VALIDATION' using hint =
      'No se pudo sumar esa cuenta. Tiene que ser una cuenta de Ceres propia, sin pacientes ni consultorio.';
  end if;

  select plan into before from public.account_plans where user_id = target;

  insert into public.org_members (org_id, user_id, role, plan_before)
  values (my_org, target, p_role, coalesce(before, 'none'));

  insert into public.account_plans (user_id, plan)
  values (target, 'pro')
  on conflict (user_id) do update set plan = 'pro', updated_at = now();

  return target;
end;
$$;

create or replace function public.org_remove_member(p_user uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  n       integer;
  m       public.org_members;
  my_role text;
begin
  if not public.manages_professional(p_user) then
    raise exception 'ERR_FORBIDDEN' using hint = 'No es del consultorio.';
  end if;

  select * into m from public.org_members where user_id = p_user;
  select role into my_role from public.org_members where user_id = auth.uid();

  if m.role = 'owner' then
    raise exception 'ERR_VALIDATION' using hint = 'La titular no se puede sacar.';
  end if;
  if m.role = 'admin' and my_role <> 'owner' then
    raise exception 'ERR_FORBIDDEN' using hint = 'Solo la titular saca a quien administra.';
  end if;

  select count(*) into n from public.care_grants
   where professional_id = p_user and status = 'accepted' and revoked_at is null;
  if n > 0 then
    raise exception 'ERR_CONFLICT' using hint = format(
      'Tiene %s %s. Reasignalos o dalos de baja primero.',
      n, case when n = 1 then 'paciente' else 'pacientes' end);
  end if;

  delete from public.org_members where user_id = p_user;

  -- Vuelve al plan que tenía: el Pro se lo pagaba el consultorio.
  if m.plan_before = 'none' then
    delete from public.account_plans where user_id = p_user;
  elsif m.plan_before is not null then
    update public.account_plans
       set plan = m.plan_before, updated_at = now()
     where user_id = p_user;
  end if;
end;
$$;

-- down
-- (vuelven las versiones de la migración 56)
-- alter table public.org_members drop column if exists plan_before;
-- drop function if exists public.close_expired_grants(uuid);
