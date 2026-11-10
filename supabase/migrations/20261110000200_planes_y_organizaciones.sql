-- 49 · Planes y organizaciones (escenario de demostración).
--
-- Lo que Ceres cobraría: un plan gratis sin IA, Premium con toda la IA, y Pro
-- para la profesional, cuyos pacientes reciben la IA pagada por ella. Y las
-- organizaciones: un consultorio con varias profesionales y un fondo de IA
-- mensual compartido.
--
-- **Nadie existente cambia de experiencia.** Una cuenta sin fila en
-- `account_plans` es Premium: así quedan las cuentas reales. Los planes se
-- asignan solo a las cuentas del escenario, y no los escribe ningún cliente
-- (no hay policy de escritura): los pone el script de la demo con la clave de
-- servicio, que es como los pondría un sistema de cobro.
--
-- Todo lo de esta migración se puede sacar con
-- `supabase/snippets/demo_quitar_tablas.sql` sin tocar nada anterior.

-- ── 1 · El plan de cada cuenta ───────────────────────────────────────────
create table if not exists public.account_plans (
  user_id     uuid        primary key
                references public.profiles (id) on delete cascade,
  plan        text        not null,
  updated_at  timestamptz not null default now(),
  constraint account_plans_plan check (plan in ('free', 'premium', 'pro'))
);

alter table public.account_plans enable row level security;
grant select on public.account_plans to authenticated;

drop policy if exists account_plans_read_own on public.account_plans;
create policy account_plans_read_own on public.account_plans
  for select to authenticated
  using (user_id = (select auth.uid()));

-- El plan **efectivo**, que es el que decide qué se puede usar:
--   · `premium` · sin fila (todas las cuentas reales) o Premium pagado.
--   · `pro`     · la profesional. Tiene la IA del panel y la propia.
--   · `patient` · plan gratis pero vinculado a una profesional Pro con un
--                 acceso vigente: la IA se la paga ella.
--   · `free`    · gratis y sin profesional Pro: sin IA y con anuncios.
create or replace function public.effective_plan()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when ap.plan is null or ap.plan = 'premium' then 'premium'
    when ap.plan = 'pro' then 'pro'
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

-- ── 2 · Organizaciones ───────────────────────────────────────────────────
create table if not exists public.organizations (
  id                uuid        primary key default extensions.gen_random_uuid(),
  name              text        not null,
  -- El fondo de IA del mes para los pacientes de todas sus profesionales.
  ai_monthly_quota  integer     not null default 1800,
  created_at        timestamptz not null default now(),
  constraint organizations_name_len check (char_length(name) between 1 and 120),
  constraint organizations_quota check (ai_monthly_quota >= 0)
);

create table if not exists public.org_members (
  org_id      uuid        not null
                references public.organizations (id) on delete cascade,
  user_id     uuid        not null
                references public.profiles (id) on delete cascade,
  role        text        not null default 'professional',
  created_at  timestamptz not null default now(),
  primary key (org_id, user_id),
  constraint org_members_role check (role in ('owner', 'admin', 'professional'))
);

create index if not exists org_members_user_idx on public.org_members (user_id);

alter table public.organizations enable row level security;
alter table public.org_members enable row level security;
grant select on public.organizations, public.org_members to authenticated;

-- ¿Es miembro de esta organización? `security definer` para que la policy de
-- `org_members` no se consulte a sí misma.
create or replace function public.is_org_member(p_org uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.org_members
     where org_id = p_org and user_id = auth.uid()
  );
$$;

revoke all on function public.is_org_member(uuid) from public;
grant execute on function public.is_org_member(uuid) to authenticated;

drop policy if exists organizations_read on public.organizations;
create policy organizations_read on public.organizations
  for select to authenticated
  using (public.is_org_member(id));

drop policy if exists org_members_read on public.org_members;
create policy org_members_read on public.org_members
  for select to authenticated
  using (public.is_org_member(org_id));

-- ── 3 · El tablero de la organización ────────────────────────────────────
-- Lo que ve una profesional de su consultorio: quiénes son, cuántos pacientes
-- tiene cada una y cuánto del fondo de IA se usó este mes.
--
-- **Agregado, nunca detalle.** La organización paga la IA de los pacientes,
-- pero eso no le abre sus datos: ve cuántos análisis se hicieron, no qué
-- comió nadie. Por eso es una función de definidor que devuelve conteos, y no
-- una policy que abra `ai_analyses`.
create or replace function public.my_organization()
returns table (
  org_id            uuid,
  org_name          text,
  ai_monthly_quota  integer,
  ai_used_month     integer,
  member_id         uuid,
  member_name       text,
  member_role       text,
  member_patients   integer
)
language sql
stable
security definer
set search_path = public
as $$
  with org as (
    select o.*
      from public.organizations o
      join public.org_members m on m.org_id = o.id
     where m.user_id = auth.uid()
     order by o.created_at
     limit 1
  ),
  members as (
    select m.user_id, m.role, p.display_name
      from public.org_members m
      join public.profiles p on p.id = m.user_id
     where m.org_id = (select id from org)
  ),
  patients as (
    select distinct g.owner_id, g.professional_id
      from public.care_grants g
     where g.professional_id in (select user_id from members)
       and g.status = 'accepted'
       and g.revoked_at is null
       and (g.expires_at is null or g.expires_at > now())
  ),
  month_start as (
    select date_trunc('month', now() at time zone 'America/Argentina/Buenos_Aires')
             at time zone 'America/Argentina/Buenos_Aires' as t
  ),
  used as (
    select (
      (select count(*) from public.ai_analyses a
        where a.user_id in (select owner_id from patients)
          and a.status <> 'failed'
          and a.created_at >= (select t from month_start))
      +
      (select count(*) from public.care_reports r
        where r.requested_by in (select user_id from members)
          and r.created_at >= (select t from month_start))
    )::int as n
  )
  select
    o.id, o.name, o.ai_monthly_quota, (select n from used),
    mb.user_id, mb.display_name, mb.role,
    (select count(*)::int from patients pt where pt.professional_id = mb.user_id)
  from org o
  cross join members mb
  order by case mb.role when 'owner' then 0 when 'admin' then 1 else 2 end,
           mb.display_name;
$$;

revoke all on function public.my_organization() from public;
grant execute on function public.my_organization() to authenticated;
