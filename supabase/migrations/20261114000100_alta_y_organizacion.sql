-- 56 · El alta desde el panel, una sola nutricionista, el consultorio
-- completo y los comentarios sobre una comida.
--
-- Cuatro decisiones de producto (14 de noviembre):
--
-- 1. **La nutricionista da el alta.** Hasta acá el vínculo lo empezaba el
--    paciente cargando el código `CE-…`. Ahora la profesional también puede
--    invitarlo desde el panel con su mail; el paciente ve la invitación en la
--    app y la acepta. El código sigue andando.
-- 2. **Una sola nutricionista por persona**, y por lo tanto un solo
--    consultorio. Para cambiar, primero se da de baja.
-- 3. **Las cuentas profesionales son propias.** Una cuenta que ejerce de
--    profesional no se suma como paciente, y una que es paciente no pasa a
--    ser profesional ni entra a un consultorio. Una profesional está en un
--    solo consultorio.
-- 4. **El consultorio administra a sus pacientes.** La titular (y quien
--    administra) ve la lista de todos, entra a la ficha de cualquiera en modo
--    lectura, lo reasigna a otra profesional o lo da de baja, y suma o saca
--    profesionales. Escribirle al paciente sigue siendo de su profesional.
--
-- Y lo que pedía la ficha: una devolución puede ser **sobre una comida**
-- (`care_feedback.meal_id`), que es como se comenta una foto.

-- ── 1 · ¿Es una cuenta profesional? ──────────────────────────────────────
-- Profesional = plan Pro, miembro de un consultorio, o tiene código de
-- profesional (lo pidió desde el panel). Las tres cosas solo las tiene quien
-- ejerce.
create or replace function public.is_professional(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.account_plans
                  where user_id = p_user and plan = 'pro')
      or exists (select 1 from public.org_members where user_id = p_user)
      or exists (select 1 from public.profiles
                  where id = p_user and care_code is not null);
$$;

revoke all on function public.is_professional(uuid) from public;
grant execute on function public.is_professional(uuid) to authenticated;

-- ¿Tiene hoy una nutricionista? (como paciente)
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

revoke all on function public.has_active_professional(uuid) from public;

-- ── 2 · Una sola nutricionista por persona ───────────────────────────────
-- Si alguien quedó con dos (antes se podía), queda la más reciente.
update public.care_grants g
   set status = 'revoked', revoked_at = now()
 where g.status = 'accepted'
   and g.revoked_at is null
   and exists (
     select 1 from public.care_grants n
      where n.owner_id = g.owner_id
        and n.status = 'accepted'
        and n.revoked_at is null
        and n.accepted_at > g.accepted_at
   );

create unique index if not exists care_grants_one_active_per_owner
  on public.care_grants (owner_id)
  where status = 'accepted' and revoked_at is null;

-- El nombre de quien lo sigue hoy, para el mensaje de "ya tenés una".
create or replace function public.current_professional_name(p_user uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(p.display_name, 'otra nutricionista')
    from public.care_grants g
    join public.profiles p on p.id = g.professional_id
   where g.owner_id = p_user
     and g.status = 'accepted'
     and g.revoked_at is null
   limit 1;
$$;

revoke all on function public.current_professional_name(uuid) from public;

-- `grant_care_access` conserva la firma (la usa la app publicada) y suma las
-- dos reglas: una cuenta profesional no se suma, y quien ya tiene
-- nutricionista se da de baja antes de cambiar.
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

  if exists (
    select 1 from public.care_grants
     where owner_id = auth.uid() and professional_id <> professional
       and status = 'accepted' and revoked_at is null
  ) then
    raise exception 'ERR_CONFLICT' using hint = format(
      'Ya estás con %s. Date de baja primero para sumarte a otra nutricionista.',
      public.current_professional_name(auth.uid()));
  end if;

  -- Las categorías las pone el trigger de la migración 55: todo prendido.
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

  return grant_id;
end $$;

-- Pedir un código de profesional (lo hace el panel al entrar) siendo paciente
-- de alguien convertiría la cuenta en las dos cosas.
create or replace function public.ensure_care_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  result text;
begin
  if public.has_active_professional(auth.uid())
     and not exists (select 1 from public.profiles
                      where id = auth.uid() and care_code is not null) then
    raise exception 'ERR_VALIDATION' using hint =
      'Esta cuenta es de paciente. El panel se usa con una cuenta profesional propia.';
  end if;

  -- Un solo update: dos pestañas a la vez devuelven el mismo código (48).
  update public.profiles
     set care_code = coalesce(care_code, public.generate_care_code())
   where id = auth.uid()
  returning care_code into result;
  return result;
end $$;

-- ── 3 · Una profesional, un consultorio ──────────────────────────────────
delete from public.org_members m
 where exists (
   select 1 from public.org_members o
    where o.user_id = m.user_id and o.created_at < m.created_at
 );

create unique index if not exists org_members_one_org_per_user
  on public.org_members (user_id);

-- ¿Quien mira administra el consultorio de esta profesional?
create or replace function public.manages_professional(p_professional uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.org_members me
      join public.org_members them on them.org_id = me.org_id
     where me.user_id = auth.uid()
       and me.role in ('owner', 'admin')
       and them.user_id = p_professional
  );
$$;

revoke all on function public.manages_professional(uuid) from public;
grant execute on function public.manages_professional(uuid) to authenticated;

-- La titular **lee** las fichas de los pacientes del consultorio. Solo leer:
-- `has_any_care_access`, que es lo que piden las políticas de escritura
-- (devoluciones, informes), sigue siendo de la profesional del paciente.
create or replace function public.has_care_access(
  p_owner uuid,
  p_category text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.care_grants g
     where g.owner_id = p_owner
       and g.status = 'accepted'
       and g.revoked_at is null
       and (g.expires_at is null or g.expires_at > now())
       and (g.professional_id = auth.uid()
            or public.manages_professional(g.professional_id))
       and case p_category
             when 'meals'     then g.share_meals
             when 'photos'    then g.share_photos
             when 'body'      then g.share_body
             when 'wellbeing' then g.share_wellbeing
             else false
           end
  );
$$;

-- Los pacientes de todo el consultorio, con los números del tablero. Solo
-- para la titular y quien administra; a una profesional le devuelve vacío.
create or replace function public.org_patients()
returns table (
  patient_id        uuid,
  patient_name      text,
  birth_date        date,
  height_cm         numeric,
  tracking_since    date,
  professional_id   uuid,
  professional_name text,
  accepted_at       timestamptz,
  last_meal_date    date,
  days_logged_7     integer,
  avg_kcal_7        integer,
  target_kcal       integer,
  weight_first_30   numeric,
  weight_last_30    numeric
)
language sql
stable
security definer
set search_path = public
as $$
  with me as (
    select m.org_id
      from public.org_members m
     where m.user_id = auth.uid() and m.role in ('owner', 'admin')
  ),
  pros as (
    select m.user_id, p.display_name
      from public.org_members m
      join public.profiles p on p.id = m.user_id
     where m.org_id = (select org_id from me)
  ),
  pts as (
    select g.owner_id, g.professional_id, g.accepted_at,
           p.display_name, p.birth_date, p.height_cm,
           (now() at time zone coalesce(p.timezone,
              'America/Argentina/Buenos_Aires'))::date as today
      from public.care_grants g
      join public.profiles p on p.id = g.owner_id
     where g.professional_id in (select user_id from pros)
       and g.status = 'accepted'
       and g.revoked_at is null
       and (g.expires_at is null or g.expires_at > now())
  ),
  m as (
    select me.user_id, me.local_date, sum(me.total_kcal) as kcal
      from public.meals me
     where me.deleted_at is null
       and me.user_id in (select owner_id from pts)
       and me.local_date >= current_date - 45
     group by me.user_id, me.local_date
  ),
  w as (
    select wl.user_id, wl.weight_kg,
           row_number() over (partition by wl.user_id order by wl.local_date asc)  as first_rn,
           row_number() over (partition by wl.user_id order by wl.local_date desc) as last_rn
      from public.weight_logs wl
     where wl.deleted_at is null
       and wl.user_id in (select owner_id from pts)
       and wl.local_date >= current_date - 30
  ),
  goal as (
    select distinct on (go.user_id) go.user_id, go.base_calorie_target
      from public.goals go
     where go.user_id in (select owner_id from pts)
       and go.starts_on <= current_date
     order by go.user_id, go.starts_on desc
  ),
  first_day as (
    select x.user_id, min(x.d) as d from (
      select user_id, min(local_date) as d from public.meals
       where deleted_at is null and user_id in (select owner_id from pts) group by user_id
      union all
      select user_id, min(local_date) from public.activities
       where deleted_at is null and user_id in (select owner_id from pts) group by user_id
      union all
      select user_id, min(local_date) from public.weight_logs
       where deleted_at is null and user_id in (select owner_id from pts) group by user_id
    ) x group by x.user_id
  )
  select
    p.owner_id,
    p.display_name,
    p.birth_date,
    p.height_cm,
    (select d from first_day f where f.user_id = p.owner_id),
    p.professional_id,
    (select display_name from pros where user_id = p.professional_id),
    p.accepted_at,
    (select max(m.local_date) from m where m.user_id = p.owner_id),
    (select count(*)::int from m where m.user_id = p.owner_id
        and m.local_date > p.today - 7),
    (select round(avg(m.kcal))::int from m where m.user_id = p.owner_id
        and m.local_date > p.today - 7 and m.local_date < p.today),
    (select goal.base_calorie_target::int from goal where goal.user_id = p.owner_id),
    (select w.weight_kg from w where w.user_id = p.owner_id and w.first_rn = 1),
    (select w.weight_kg from w where w.user_id = p.owner_id and w.last_rn = 1)
  from pts p
  order by p.display_name;
$$;

revoke all on function public.org_patients() from public;
grant execute on function public.org_patients() to authenticated;

-- La baja la puede dar también quien administra el consultorio.
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
     and (professional_id = auth.uid()
          or public.manages_professional(professional_id))
     and revoked_at is null;
  get diagnostics n = row_count;
  if n = 0 then
    raise exception 'ERR_NOT_FOUND' using hint = 'No es un paciente tuyo.';
  end if;
  return n;
end;
$$;

-- Pasar un paciente a otra profesional del consultorio. El acceso viejo queda
-- revocado con fecha (como cualquier baja) y se abre uno nuevo: queda escrito
-- quién lo siguió y hasta cuándo.
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
   where owner_id = p_patient and status = 'accepted' and revoked_at is null;

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

revoke all on function public.reassign_patient(uuid, uuid) from public;
grant execute on function public.reassign_patient(uuid, uuid) to authenticated;

-- Sumar una profesional al consultorio, por el mail de su cuenta. La cuenta
-- tiene que existir, no ser paciente de nadie y no estar en otro consultorio.
-- Entra con plan Pro: la IA se la paga el consultorio.
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

  if target is null then
    raise exception 'ERR_NOT_FOUND' using hint =
      'No hay una cuenta de Ceres con ese mail. Pedile que se cree una.';
  end if;
  if exists (select 1 from public.org_members where user_id = target) then
    raise exception 'ERR_CONFLICT' using hint = 'Esa cuenta ya es parte de un consultorio.';
  end if;
  if public.has_active_professional(target) then
    raise exception 'ERR_VALIDATION' using hint =
      'Esa cuenta es de un paciente. Cada profesional usa una cuenta propia.';
  end if;

  insert into public.org_members (org_id, user_id, role)
  values (my_org, target, p_role);

  insert into public.account_plans (user_id, plan)
  values (target, 'pro')
  on conflict (user_id) do update set plan = 'pro', updated_at = now();

  return target;
end;
$$;

revoke all on function public.org_add_member(text, text) from public;
grant execute on function public.org_add_member(text, text) to authenticated;

-- Sacar a una profesional. Antes hay que reasignar o dar de baja a sus
-- pacientes: un paciente no queda colgado de alguien que ya no está.
create or replace function public.org_remove_member(p_user uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  n integer;
begin
  if not public.manages_professional(p_user) then
    raise exception 'ERR_FORBIDDEN' using hint = 'No es del consultorio.';
  end if;
  if exists (select 1 from public.org_members
              where user_id = p_user and role = 'owner') then
    raise exception 'ERR_VALIDATION' using hint = 'La titular no se puede sacar.';
  end if;

  select count(*) into n from public.care_grants
   where professional_id = p_user and status = 'accepted' and revoked_at is null;
  if n > 0 then
    raise exception 'ERR_CONFLICT' using hint = format(
      'Tiene %s %s. Reasignalos o dalos de baja primero.',
      n, case when n = 1 then 'paciente' else 'pacientes' end);
  end if;

  delete from public.org_members where user_id = p_user;
end;
$$;

revoke all on function public.org_remove_member(uuid) from public;
grant execute on function public.org_remove_member(uuid) to authenticated;

-- ── 4 · El alta desde el panel: invitaciones ─────────────────────────────
-- Por mail y no por un código del paciente: la nutricionista ya tiene el mail
-- de quien atiende. La invitación no dice si la cuenta existe —queda
-- pendiente igual, y si la persona se crea la cuenta con ese mail la ve al
-- entrar—, así que el panel no sirve para averiguar quién usa Ceres.
create table if not exists public.care_invites (
  id              uuid        primary key default extensions.gen_random_uuid(),
  professional_id uuid        not null
                    references public.profiles (id) on delete cascade,
  email           text        not null,
  status          text        not null default 'pending',
  created_at      timestamptz not null default now(),
  responded_at    timestamptz,
  constraint care_invites_status check (
    status in ('pending', 'accepted', 'declined', 'cancelled')),
  constraint care_invites_email check (
    email = lower(email) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$')
);

create unique index if not exists care_invites_one_pending
  on public.care_invites (professional_id, email)
  where status = 'pending';
create index if not exists care_invites_email_idx
  on public.care_invites (email) where status = 'pending';

alter table public.care_invites enable row level security;
grant select on public.care_invites to authenticated;

-- La profesional ve las suyas. El paciente las ve por `my_care_invites()`,
-- que además trae el nombre de quien invita. Nadie escribe directo: todo pasa
-- por las funciones de abajo.
drop policy if exists care_invites_read_own on public.care_invites;
create policy care_invites_read_own on public.care_invites
  for select to authenticated
  using (professional_id = (select auth.uid()));

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
  if target is not null and public.is_professional(target) then
    raise exception 'ERR_VALIDATION' using hint =
      'Es una cuenta profesional. Los pacientes se suman con una cuenta personal.';
  end if;
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

revoke all on function public.invite_patient(text) from public;
grant execute on function public.invite_patient(text) to authenticated;

create or replace function public.cancel_care_invite(p_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.care_invites
     set status = 'cancelled', responded_at = now()
   where id = p_id and professional_id = auth.uid() and status = 'pending';
$$;

revoke all on function public.cancel_care_invite(uuid) from public;
grant execute on function public.cancel_care_invite(uuid) to authenticated;

-- Lo que ve el paciente: las invitaciones pendientes a su mail, con quién
-- invita y de qué consultorio.
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
   order by i.created_at desc;
$$;

revoke all on function public.my_care_invites() from public;
grant execute on function public.my_care_invites() to authenticated;

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

revoke all on function public.accept_care_invite(uuid) from public;
grant execute on function public.accept_care_invite(uuid) to authenticated;

create or replace function public.decline_care_invite(p_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.care_invites
     set status = 'declined', responded_at = now()
   where id = p_id and status = 'pending'
     and email = (select lower(email) from auth.users where id = auth.uid());
$$;

revoke all on function public.decline_care_invite(uuid) from public;
grant execute on function public.decline_care_invite(uuid) to authenticated;

-- ── 5 · Los que se fueron ────────────────────────────────────────────────
-- Las bajas de los últimos 90 días de quien mira: para saber quién dejó de
-- estar y poder volver a invitarlo.
create or replace function public.care_discharged()
returns table (
  patient_id   uuid,
  patient_name text,
  accepted_at  timestamptz,
  revoked_at   timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select g.owner_id, p.display_name, g.accepted_at, g.revoked_at
    from public.care_grants g
    join public.profiles p on p.id = g.owner_id
   where g.professional_id = auth.uid()
     and g.status = 'revoked'
     and g.revoked_at > now() - interval '90 days'
   order by g.revoked_at desc;
$$;

revoke all on function public.care_discharged() from public;
grant execute on function public.care_discharged() to authenticated;

-- ── 6 · Comentar una comida ──────────────────────────────────────────────
-- Una devolución puede ir anclada a una comida (y por lo tanto a su foto).
-- Si la comida se borra de verdad, la devolución queda como del día.
alter table public.care_feedback
  add column if not exists meal_id uuid
    references public.meals (id) on delete set null;

create index if not exists care_feedback_meal_idx
  on public.care_feedback (meal_id) where meal_id is not null;

alter table public.care_feedback drop constraint if exists care_feedback_meal_kind;
alter table public.care_feedback add constraint care_feedback_meal_kind check (
  meal_id is null or kind = 'feedback'
);

grant insert (meal_id) on public.care_feedback to authenticated;

-- La comida tiene que ser del paciente al que se le escribe.
drop policy if exists care_feedback_write on public.care_feedback;
create policy care_feedback_write on public.care_feedback
  for insert to authenticated
  with check (
    author_id = (select auth.uid())
    and public.has_any_care_access(patient_id)
    and (meal_id is null or exists (
      select 1 from public.meals m
       where m.id = meal_id and m.user_id = patient_id
    ))
  );

-- `has_any_care_access` (escribir) queda solo para la profesional del
-- paciente: la titular lee la ficha, pero no le escribe a un paciente ajeno.

-- down
-- drop function if exists public.care_discharged();
-- drop function if exists public.decline_care_invite(uuid);
-- drop function if exists public.accept_care_invite(uuid);
-- drop function if exists public.my_care_invites();
-- drop function if exists public.cancel_care_invite(uuid);
-- drop function if exists public.invite_patient(text);
-- drop table if exists public.care_invites;
-- drop function if exists public.org_remove_member(uuid);
-- drop function if exists public.org_add_member(text, text);
-- drop function if exists public.reassign_patient(uuid, uuid);
-- drop function if exists public.org_patients();
-- drop index if exists public.org_members_one_org_per_user;
-- drop index if exists public.care_grants_one_active_per_owner;
-- alter table public.care_feedback drop column if exists meal_id;
-- (has_care_access, grant_care_access, ensure_care_code y discharge_patient
--  vuelven a sus versiones de las migraciones 32, 48 y 55)
