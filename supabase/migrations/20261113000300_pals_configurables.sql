-- 54 · Pals: todo se elige, el peso entra como opción y los días se escuchan
-- en vivo.
--
-- Hasta acá la comida y el total de actividad se compartían siempre, sin
-- interruptor, y el peso no se compartía nunca. Ahora:
--
-- - Comida y actividad tienen su interruptor. Arrancan **prendidos**: es lo
--   que cualquier cuenta ya venía compartiendo, y apagarlos de golpe le
--   vaciaría la pantalla a todos los pals existentes.
-- - El peso se puede compartir (apagado por default, como el resto de las
--   opciones). Las medidas siguen fuera: no hay caso de uso entre pals.
-- - La base limpia lo que no se comparte **antes de guardarlo**. Hasta acá la
--   garantía de comida y fotos la daba la app al armar el día; un cliente
--   viejo o con un bug podía publicar de más. Ahora no importa qué mande.
-- - `shared_days` entra en la publicación de Realtime, para que la app pueda
--   avisar "Tomás cargó el almuerzo" en el momento. Realtime respeta RLS:
--   cada quien recibe solo los días de sus pals.

-- ── Qué prende cada quien ─────────────────────────────────────────────────
alter table public.profiles
  add column if not exists pal_share_meals    boolean not null default true,
  add column if not exists pal_share_activity boolean not null default true,
  add column if not exists pal_share_weight   boolean not null default false;

-- ── Lo nuevo del día publicado ────────────────────────────────────────────
-- `meals_shared` y `activity_shared` existen para que el pal distinga "no
-- comió nada todavía" de "no comparte la comida". Los pone la base, no la app.
-- `weight_kg` es el último peso registrado hasta ese día, y `weight_date`,
-- de cuándo es: con pesajes semanales, "el peso del martes" casi nunca existe.
alter table public.shared_days
  add column if not exists meals_shared    boolean not null default true,
  add column if not exists activity_shared boolean not null default true,
  add column if not exists weight_kg       numeric(6,2),
  add column if not exists weight_date     date;

alter table public.shared_days
  add constraint shared_days_weight_range
    check (weight_kg is null or weight_kg between 25 and 400);

-- ── Una sola función responde "¿comparte esto?" ──────────────────────────
create or replace function public.pal_shares(p_owner uuid, p_category text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_pal_of(p_owner)
     and exists (
       select 1 from public.profiles p
        where p.id = p_owner
          and case p_category
                when 'meals'           then p.pal_share_meals
                when 'photos'          then p.pal_share_meals and p.pal_share_photos
                when 'activity'        then p.pal_share_activity
                when 'activity_detail' then p.pal_share_activity and p.pal_share_activity_detail
                when 'water'           then p.pal_share_water
                when 'sleep'           then p.pal_share_sleep
                when 'weight'          then p.pal_share_weight
                else false
              end
     );
$$;

grant execute on function public.pal_shares(uuid, text) to authenticated;

-- ── La base limpia el día antes de guardarlo ─────────────────────────────
-- `security definer` porque lee el perfil del dueño, que RLS no deja ver a
-- nadie más; acá quien escribe es siempre el dueño, pero el trigger también
-- corre cuando lo dispara el de `profiles` de abajo.
create or replace function public.sanitize_shared_day()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  p public.profiles%rowtype;
begin
  select * into p from public.profiles where id = new.user_id;
  if not found then
    return new;
  end if;

  new.meals_shared := p.pal_share_meals;
  if not p.pal_share_meals then
    new.meals := '[]'::jsonb;
  elsif not p.pal_share_photos then
    new.meals := coalesce(
      (select jsonb_agg(e - 'photoPath') from jsonb_array_elements(new.meals) e),
      '[]'::jsonb
    );
  end if;

  new.activity_shared := p.pal_share_activity;
  if not p.pal_share_activity then
    new.activity_minutes := 0;
    new.activity_count := 0;
    new.activities := '[]'::jsonb;
  elsif not p.pal_share_activity_detail then
    new.activities := '[]'::jsonb;
  end if;

  if not p.pal_share_water then
    new.water_glasses := null;
  end if;
  if not p.pal_share_sleep then
    new.sleep_minutes := null;
    new.sleep_quality := null;
  end if;
  if not p.pal_share_weight then
    new.weight_kg := null;
    new.weight_date := null;
  end if;

  return new;
end;
$$;

revoke execute on function public.sanitize_shared_day() from public, anon, authenticated;

drop trigger if exists shared_days_sanitize on public.shared_days;
create trigger shared_days_sanitize
  before insert or update on public.shared_days
  for each row execute function public.sanitize_shared_day();

-- ── Apagar algo limpia también lo que ya estaba publicado ────────────────
-- Sin esto, apagar "Comida" dejaba visibles los últimos 7 días hasta que la
-- app volviera a publicar cada uno. Tocar las filas alcanza: el trigger de
-- arriba hace el resto. Prender no restaura nada (lo borrado ya no está): eso
-- lo hace la app, que vuelve a publicar en cuanto cambia una preferencia.
create or replace function public.resanitize_shared_days()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.shared_days
     set updated_at = updated_at
   where user_id = new.id;
  return new;
end;
$$;

revoke execute on function public.resanitize_shared_days() from public, anon, authenticated;

drop trigger if exists profiles_resanitize_shared_days on public.profiles;
create trigger profiles_resanitize_shared_days
  after update of pal_share_meals, pal_share_photos, pal_share_activity,
                  pal_share_activity_detail, pal_share_water, pal_share_sleep,
                  pal_share_weight
  on public.profiles
  for each row
  when (
    old.pal_share_meals            is distinct from new.pal_share_meals
    or old.pal_share_photos        is distinct from new.pal_share_photos
    or old.pal_share_activity      is distinct from new.pal_share_activity
    or old.pal_share_activity_detail is distinct from new.pal_share_activity_detail
    or old.pal_share_water         is distinct from new.pal_share_water
    or old.pal_share_sleep         is distinct from new.pal_share_sleep
    or old.pal_share_weight        is distinct from new.pal_share_weight
  )
  execute function public.resanitize_shared_days();

-- ── Realtime ──────────────────────────────────────────────────────────────
-- La publicación la crea la plataforma; en una base sin Realtime (la de los
-- tests) no existe y no hay nada que agregar.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'shared_days'
     )
  then
    alter publication supabase_realtime add table public.shared_days;
  end if;
end;
$$;

-- down
-- alter publication supabase_realtime drop table public.shared_days;
-- drop trigger if exists profiles_resanitize_shared_days on public.profiles;
-- drop function if exists public.resanitize_shared_days();
-- drop trigger if exists shared_days_sanitize on public.shared_days;
-- drop function if exists public.sanitize_shared_day();
-- alter table public.shared_days
--   drop constraint if exists shared_days_weight_range,
--   drop column if exists weight_date,
--   drop column if exists weight_kg,
--   drop column if exists activity_shared,
--   drop column if exists meals_shared;
-- alter table public.profiles
--   drop column if exists pal_share_weight,
--   drop column if exists pal_share_activity,
--   drop column if exists pal_share_meals;
