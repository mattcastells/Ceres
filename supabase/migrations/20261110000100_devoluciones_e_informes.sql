-- 48 · Devoluciones de la profesional, informes con IA y el tablero del equipo.
--
-- Hasta acá el vínculo profesional-paciente era de una sola vía: la
-- profesional miraba y nada volvía. Esta migración agrega la vuelta —lo que
-- ella le escribe al paciente— y lo que necesitan los informes con IA. De paso
-- cierra cuatro bordes que encontró la auditoría de noviembre.
--
-- Lo que **no** cambia: los datos del paciente siguen siendo de solo lectura
-- para la profesional. Lo único que ella escribe son textos propios
-- (`care_feedback`) e informes propios (`care_reports`).

-- ── 1 · `care_notes` se va ───────────────────────────────────────────────
-- Las notas privadas (migración 42) no las lee ni las escribe nadie desde
-- agosto. Lo que cubrían —"una nota mía sobre este paciente que él no ve"— lo
-- cubre ahora un borrador de `care_feedback` que nunca se publica.
drop table if exists public.care_notes cascade;

-- ── 2 · "¿Tiene algún acceso vigente?" ───────────────────────────────────
-- Lo preguntaban cuatro OR repetidos en cada política que lo necesitaba. Una
-- sola función: si mañana aparece una quinta categoría, se agrega en un lugar.
create or replace function public.has_any_care_access(p_owner uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.care_grants g
     where g.professional_id = auth.uid()
       and g.owner_id = p_owner
       and g.status = 'accepted'
       and g.revoked_at is null
       and (g.expires_at is null or g.expires_at > now())
       and (g.share_meals or g.share_photos or g.share_body or g.share_wellbeing)
  );
$$;

revoke all on function public.has_any_care_access(uuid) from public;
grant execute on function public.has_any_care_access(uuid) to authenticated;

-- ── 3 · Lo que la profesional le escribe al paciente ─────────────────────
-- Dos tipos:
--   · `feedback`: una devolución sobre un día, una comida o la semana.
--   · `indication`: una indicación que sigue vigente ("sumá proteína en el
--     desayuno") y que el paciente ve en Inicio hasta que ella la saque.
--
-- **Mientras no se publica, es privada.** Un borrador —escrito a mano o
-- propuesto por la IA— lo ve solo quien lo escribe. Es la regla de las viejas
-- notas privadas, que siguen existiendo así: un borrador que nunca se publica.
create table if not exists public.care_feedback (
  id            uuid        primary key default extensions.gen_random_uuid(),
  author_id     uuid        not null
                  references public.profiles (id) on delete cascade,
  patient_id    uuid        not null
                  references public.profiles (id) on delete cascade,
  kind          text        not null default 'feedback',
  -- Con fecha = anclada a ese día. Sin fecha = sobre el seguimiento en general.
  local_date    date,
  body          text        not null,
  -- Quién lo escribió primero. La IA propone un borrador; lo que se publica lo
  -- revisó la profesional, y esta columna deja constancia de dónde salió.
  source        text        not null default 'manual',
  published_at  timestamptz,
  read_at       timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,

  constraint care_feedback_kind check (kind in ('feedback', 'indication')),
  constraint care_feedback_source check (source in ('manual', 'ai_draft')),
  constraint care_feedback_body_len check (char_length(body) between 1 and 4000),
  constraint care_feedback_no_self check (author_id <> patient_id)
);

create index if not exists care_feedback_patient_idx
  on public.care_feedback (patient_id, published_at desc)
  where deleted_at is null;
create index if not exists care_feedback_author_idx
  on public.care_feedback (author_id, patient_id, created_at desc)
  where deleted_at is null;

drop trigger if exists care_feedback_set_updated_at on public.care_feedback;
create trigger care_feedback_set_updated_at
  before update on public.care_feedback
  for each row execute function public.set_updated_at();

alter table public.care_feedback enable row level security;

grant select, insert, update, delete on public.care_feedback to authenticated;

-- Quien escribe ve todo lo suyo. El paciente ve **solo lo publicado** y no
-- borrado: un borrador no es una devolución.
drop policy if exists care_feedback_read on public.care_feedback;
create policy care_feedback_read on public.care_feedback
  for select to authenticated
  using (
    author_id = (select auth.uid())
    or (
      patient_id = (select auth.uid())
      and published_at is not null
      and deleted_at is null
    )
  );

-- Escribir exige un acceso vigente: revocar corta la escritura.
drop policy if exists care_feedback_write on public.care_feedback;
create policy care_feedback_write on public.care_feedback
  for insert to authenticated
  with check (
    author_id = (select auth.uid())
    and public.has_any_care_access(patient_id)
  );

-- Editar, publicar o borrar (suave) lo propio, también con acceso vigente.
-- Revocado, lo escrito se sigue viendo pero ya no se toca.
drop policy if exists care_feedback_update on public.care_feedback;
create policy care_feedback_update on public.care_feedback
  for update to authenticated
  using (author_id = (select auth.uid()))
  with check (
    author_id = (select auth.uid())
    and public.has_any_care_access(patient_id)
  );

-- Borrar de verdad no: el borrado es `deleted_at`, que el paciente deja de ver
-- en el próximo refresco y que `purge_soft_deleted` limpia a los 30 días.
drop policy if exists care_feedback_no_hard_delete on public.care_feedback;
create policy care_feedback_no_hard_delete on public.care_feedback
  for delete to authenticated
  using (false);

-- El paciente marca como leída una devolución. Va por función y no por una
-- policy de update porque RLS no limita columnas: una policy que lo dejara
-- actualizar `read_at` lo dejaría reescribir el texto de su nutricionista.
create or replace function public.mark_care_feedback_read(p_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.care_feedback
     set read_at = coalesce(read_at, now())
   where id = p_id
     and patient_id = auth.uid()
     and published_at is not null
     and deleted_at is null;
$$;

revoke all on function public.mark_care_feedback_read(uuid) from public;
grant execute on function public.mark_care_feedback_read(uuid) to authenticated;

-- ── 4 · Informes con IA ──────────────────────────────────────────────────
-- Se guardan para no regenerarlos (y pagarlos) cada vez que alguien abre la
-- pantalla. Los escribe la Edge Function `care-report` **con la sesión de
-- quien lo pide**: no hay clave de servicio, y RLS decide igual que siempre.
--
--   · `patient_weekly`: lo pide el paciente sobre sí mismo.
--   · `professional`:   lo pide la profesional sobre un paciente.
--   · `team`:           lo pide la profesional sobre todo su equipo
--                       (`patient_id` en null).
create table if not exists public.care_reports (
  id              uuid        primary key default extensions.gen_random_uuid(),
  requested_by    uuid        not null
                    references public.profiles (id) on delete cascade,
  patient_id      uuid
                    references public.profiles (id) on delete cascade,
  kind            text        not null,
  period_from     date        not null,
  period_to       date        not null,
  content         jsonb       not null,
  model           text        not null,
  prompt_version  text        not null,
  tokens_in       integer,
  tokens_out      integer,
  tokens_thinking integer,
  latency_ms      integer,
  created_at      timestamptz not null default now(),

  constraint care_reports_kind check (
    kind in ('patient_weekly', 'professional', 'team')),
  constraint care_reports_period check (period_from <= period_to),
  constraint care_reports_shape check (
    (kind = 'team' and patient_id is null)
    or (kind = 'patient_weekly' and patient_id = requested_by)
    or (kind = 'professional' and patient_id is not null
        and patient_id <> requested_by))
);

create index if not exists care_reports_lookup_idx
  on public.care_reports (requested_by, kind, patient_id, created_at desc);

alter table public.care_reports enable row level security;

grant select, insert on public.care_reports to authenticated;

-- Cada informe lo ve quien lo pidió. El informe que la profesional pide sobre
-- un paciente es material de trabajo de ella, como lo eran sus notas: si
-- quiere que el paciente sepa algo, se lo escribe en una devolución.
drop policy if exists care_reports_read on public.care_reports;
create policy care_reports_read on public.care_reports
  for select to authenticated
  using (requested_by = (select auth.uid()));

drop policy if exists care_reports_write on public.care_reports;
create policy care_reports_write on public.care_reports
  for insert to authenticated
  with check (
    requested_by = (select auth.uid())
    and (
      (kind = 'patient_weekly' and patient_id = (select auth.uid()))
      or (kind = 'professional' and public.has_any_care_access(patient_id))
      or (kind = 'team' and patient_id is null)
    )
  );

-- ── 5 · La limpieza diaria, con la tabla nueva ───────────────────────────
-- El cuerpo sale de la definición vigente (migración 44), con `care_feedback`
-- en el lugar de `care_notes`.
create or replace function public.purge_soft_deleted()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.meals
   where deleted_at is not null and deleted_at < now() - interval '30 days';
  delete from public.activities
   where deleted_at is not null and deleted_at < now() - interval '30 days';
  delete from public.weight_logs
   where deleted_at is not null and deleted_at < now() - interval '30 days';
  delete from public.body_measurements
   where deleted_at is not null and deleted_at < now() - interval '30 days';
  delete from public.sleep_logs
   where deleted_at is not null and deleted_at < now() - interval '30 days';
  delete from public.foods
   where deleted_at is not null and deleted_at < now() - interval '30 days';
  delete from public.exercise_templates
   where deleted_at is not null and deleted_at < now() - interval '30 days';
  delete from public.day_markers
   where deleted_at is not null and deleted_at < now() - interval '30 days';
  delete from public.alcohol_logs
   where deleted_at is not null and deleted_at < now() - interval '30 days';
  delete from public.care_feedback
   where deleted_at is not null and deleted_at < now() - interval '30 days';

  perform public.purge_shared_days();
end;
$$;

revoke execute on function public.purge_soft_deleted() from public, anon, authenticated;

-- ── 6 · Cuotas: dos buckets nuevos y el día de quien pide ────────────────
-- Los informes tienen su propia cuota: no deberían comerse los análisis de
-- comida del día, ni al revés.
--
-- Y el día es el **de la persona**, no el de UTC. Con `current_date` la cuota
-- se renovaba a las 21:00 en Argentina: quien sacaba fotos a la noche las
-- contaba en el día siguiente.
create or replace function public.check_rate_limit(p_bucket text, p_max integer)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_count integer;
  today         date;
begin
  if p_bucket not in (
    'ai_analysis', 'food_search', 'pal_request', 'care_report', 'weekly_report'
  ) then
    raise exception 'Bucket de cuota desconocido: %', p_bucket
      using errcode = 'check_violation';
  end if;

  select (now() at time zone coalesce(
            (select timezone from public.profiles where id = auth.uid()),
            'America/Argentina/Buenos_Aires'))::date
    into today;

  insert into public.rate_limits (user_id, bucket, day, count)
  values (auth.uid(), p_bucket, today, 1)
  on conflict (user_id, bucket, day)
    do update set count = rate_limits.count + 1
  returning count into current_count;

  return current_count <= p_max;
end;
$$;

grant execute on function public.check_rate_limit(text, integer) to authenticated;

-- ── 7 · El código del profesional: sin carrera y con el prefijo nuevo ────
-- Dos llamadas simultáneas (dos pestañas) generaban dos códigos y la segunda
-- pisaba a la primera: una pantalla quedaba mostrando un código que ya no
-- valía. Ahora gana el primero que escribe y los dos devuelven ese.
--
-- Los códigos nuevos empiezan con `CE-` (Ceres). Los `NT-` que ya existen
-- siguen funcionando: la búsqueda es por el texto completo.
create or replace function public.generate_care_code()
returns text
language plpgsql
as $$
declare
  alphabet constant text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  code text;
begin
  loop
    code := 'CE-';
    for _ in 1..6 loop
      code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.profiles where care_code = code);
  end loop;
  return code;
end $$;

create or replace function public.ensure_care_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  result text;
begin
  update public.profiles
     set care_code = coalesce(care_code, public.generate_care_code())
   where id = auth.uid()
  returning care_code into result;
  return result;
end $$;

revoke all on function public.ensure_care_code() from public;
grant execute on function public.ensure_care_code() to authenticated;

-- ── 8 · `care_grants`: el dueño elige categorías y nada más ──────────────
-- La policy de update dejaba al dueño cambiar cualquier columna, incluido
-- `professional_id`: podía aparecer en la lista de alguien que nunca le dio su
-- código. Y el insert directo salteaba `grant_care_access`, que es donde se
-- traduce el código. Ahora conceder es solo por la función, y el update
-- directo alcanza solo a las categorías (lo que usa la app).
revoke insert, update on public.care_grants from authenticated;
grant update (share_meals, share_photos, share_body, share_wellbeing)
  on public.care_grants to authenticated;

-- ── 9 · Cuánto se cachea de cada análisis ────────────────────────────────
-- Gemini cachea solo el prefijo repetido del prompt (la tabla SARA 2) y lo
-- cobra a una fracción. Sin esta columna no hay forma de saber si pasa.
alter table public.ai_analyses
  add column if not exists tokens_cached integer;

-- ── 10 · El tablero del equipo ───────────────────────────────────────────
-- Una fila por paciente con lo que la profesional mira primero: cuándo cargó
-- por última vez, cuántos días de los últimos 7 y 14, cómo viene el peso y el
-- promedio de calorías contra su objetivo.
--
-- `security invoker`: corre con los permisos de quien llama, así que cada
-- número sale solo de las categorías concedidas. Un paciente que no comparte
-- comidas aparece con esos campos en null, no en cero.
--
-- Reemplaza la consulta sin paginar de la lista de pacientes, que se cortaba
-- en silencio a partir de unos 25 pacientes activos.
create or replace function public.care_overview()
returns table (
  patient_id       uuid,
  patient_name     text,
  share_meals      boolean,
  share_body       boolean,
  share_wellbeing  boolean,
  share_photos     boolean,
  tracking_since   date,
  last_meal_date   date,
  days_logged_7    integer,
  days_logged_14   integer,
  avg_kcal_7       integer,
  target_kcal      integer,
  weight_first_30  numeric,
  weight_last_30   numeric,
  unread_feedback  integer
)
language sql
stable
security invoker
set search_path = public
as $$
  with pts as (
    select cp.patient_id, cp.patient_name, cp.share_meals, cp.share_body,
           cp.share_wellbeing, cp.share_photos, cp.tracking_since,
           (now() at time zone coalesce(pr.timezone,
              'America/Argentina/Buenos_Aires'))::date as today
      from public.care_patients cp
      -- El perfil propio se lee por la policy de dueño: solo la zona horaria.
      left join public.profiles pr on pr.id = (select auth.uid())
  ),
  m as (
    select me.user_id, me.local_date, sum(me.total_kcal) as kcal
      from public.meals me
     where me.deleted_at is null
       and me.user_id in (select patient_id from pts)
       and me.local_date >= (select min(today) from pts) - 60
     group by me.user_id, me.local_date
  ),
  w as (
    select wl.user_id, wl.local_date, wl.weight_kg,
           row_number() over (partition by wl.user_id order by wl.local_date asc)  as first_rn,
           row_number() over (partition by wl.user_id order by wl.local_date desc) as last_rn
      from public.weight_logs wl
     where wl.deleted_at is null
       and wl.user_id in (select patient_id from pts)
       and wl.local_date >= (select min(today) from pts) - 30
  ),
  g as (
    select distinct on (go.user_id) go.user_id, go.base_calorie_target
      from public.goals go
     where go.user_id in (select patient_id from pts)
       and go.starts_on <= (select max(today) from pts)
     order by go.user_id, go.starts_on desc
  )
  select
    p.patient_id,
    p.patient_name,
    p.share_meals,
    p.share_body,
    p.share_wellbeing,
    p.share_photos,
    p.tracking_since,
    case when p.share_meals then
      (select max(m.local_date) from m where m.user_id = p.patient_id) end,
    case when p.share_meals then
      (select count(*)::int from m where m.user_id = p.patient_id
          and m.local_date > p.today - 7) end,
    case when p.share_meals then
      (select count(*)::int from m where m.user_id = p.patient_id
          and m.local_date > p.today - 14) end,
    case when p.share_meals then
      (select round(avg(m.kcal))::int from m where m.user_id = p.patient_id
          and m.local_date > p.today - 7 and m.local_date < p.today) end,
    case when p.share_meals then
      (select g.base_calorie_target::int from g where g.user_id = p.patient_id) end,
    case when p.share_body then
      (select w.weight_kg from w where w.user_id = p.patient_id and w.first_rn = 1) end,
    case when p.share_body then
      (select w.weight_kg from w where w.user_id = p.patient_id and w.last_rn = 1) end,
    (select count(*)::int from public.care_feedback f
      where f.author_id = (select auth.uid())
        and f.patient_id = p.patient_id
        and f.published_at is not null
        and f.read_at is null
        and f.deleted_at is null)
  from pts p
  order by p.patient_name;
$$;

revoke all on function public.care_overview() from public;
grant execute on function public.care_overview() to authenticated;
