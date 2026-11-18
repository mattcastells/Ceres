-- Migración 59 · El tablero del equipo, con actividad, descanso, agua y sueño.
--
-- La tarjeta de cada paciente mostraba comidas, calorías, peso y devoluciones
-- sin leer. La profesional pidió ver también lo que la persona carga de su
-- día: actividad física, días de descanso, agua y sueño. Las devoluciones sin
-- leer salen de la tarjeta (siguen en la ficha), pero la columna se queda: la
-- usa el análisis del equipo.
--
-- Todo lo nuevo es de los **últimos 7 días** y va con la categoría
-- "bienestar" del permiso (`share_wellbeing`), la misma que ya protege esas
-- tablas (políticas `*_care_read`): sin ella, las columnas vuelven `null` y la
-- tarjeta dice que no lo comparte.
--
-- Cambia el tipo de retorno, así que hay que borrar la función antes de
-- recrearla (`create or replace` no deja agregar columnas a `returns table`).
-- El cuerpo es el de `20261110000100_devoluciones_e_informes`, más las CTE
-- `a`, `dm`, `wa` y `sl`.

drop function if exists public.care_overview();

create function public.care_overview()
returns table (
  patient_id           uuid,
  patient_name         text,
  share_meals          boolean,
  share_body           boolean,
  share_wellbeing      boolean,
  share_photos         boolean,
  tracking_since       date,
  last_meal_date       date,
  days_logged_7        integer,
  days_logged_14       integer,
  avg_kcal_7           integer,
  target_kcal          integer,
  weight_first_30      numeric,
  weight_last_30       numeric,
  unread_feedback      integer,
  -- Nuevas (bienestar, últimos 7 días contando hoy salvo el agua):
  activity_sessions_7  integer,
  activity_minutes_7   integer,
  rest_days_7          integer,
  water_avg_7          numeric,  -- vasos por día, sobre los días con registro
  water_days_7         integer,
  sleep_avg_7          integer,  -- minutos por noche, sobre las noches con registro
  sleep_days_7         integer
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
  ),
  -- Las cuatro de bienestar traen 8 días para cubrir cualquier zona horaria;
  -- el corte fino lo hace cada columna contra el `today` de quien mira.
  a as (
    select ac.user_id, ac.local_date, ac.duration_minutes
      from public.activities ac
     where ac.deleted_at is null
       and ac.user_id in (select patient_id from pts)
       and ac.local_date >= (select min(today) from pts) - 8
  ),
  dm as (
    select distinct d.user_id, d.local_date
      from public.day_markers d
     where d.deleted_at is null
       and d.kind = 'rest'
       and d.user_id in (select patient_id from pts)
       and d.local_date >= (select min(today) from pts) - 8
  ),
  wa as (
    select x.user_id, x.local_date, x.glasses
      from public.water_logs x
     where x.user_id in (select patient_id from pts)
       and x.glasses > 0
       and x.local_date >= (select min(today) from pts) - 8
  ),
  sl as (
    select s.user_id, s.local_date, s.minutes
      from public.sleep_logs s
     where s.deleted_at is null
       and s.user_id in (select patient_id from pts)
       and s.minutes > 0
       and s.local_date >= (select min(today) from pts) - 8
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
        and f.deleted_at is null),
    -- Actividad: sesiones y minutos de la semana, hoy incluido.
    case when p.share_wellbeing then
      (select count(*)::int from a where a.user_id = p.patient_id
          and a.local_date > p.today - 7) end,
    case when p.share_wellbeing then
      (select coalesce(sum(a.duration_minutes), 0)::int from a
        where a.user_id = p.patient_id and a.local_date > p.today - 7) end,
    -- Días marcados como descanso.
    case when p.share_wellbeing then
      (select count(*)::int from dm where dm.user_id = p.patient_id
          and dm.local_date > p.today - 7) end,
    -- Agua: hoy afuera, como las calorías, porque el día no terminó.
    case when p.share_wellbeing then
      (select round(avg(wa.glasses), 1) from wa where wa.user_id = p.patient_id
          and wa.local_date > p.today - 8 and wa.local_date < p.today) end,
    case when p.share_wellbeing then
      (select count(*)::int from wa where wa.user_id = p.patient_id
          and wa.local_date > p.today - 8 and wa.local_date < p.today) end,
    -- Sueño: va en el día en que se despertó, así que hoy ya está completo.
    case when p.share_wellbeing then
      (select round(avg(sl.minutes))::int from sl where sl.user_id = p.patient_id
          and sl.local_date > p.today - 7) end,
    case when p.share_wellbeing then
      (select count(*)::int from sl where sl.user_id = p.patient_id
          and sl.local_date > p.today - 7) end
  from pts p
  order by p.patient_name;
$$;

revoke all on function public.care_overview() from public;
grant execute on function public.care_overview() to authenticated;

-- down
-- drop function if exists public.care_overview();
-- (y recrear la de `20261110000100_devoluciones_e_informes`)
