-- 52 · Artículos y recetas de la profesional para su equipo.
--
-- Lo que la profesional publica para todos sus pacientes a la vez: una nota
-- corta ("Cómo armar una vianda") o una receta. No es una devolución —esa va a
-- una persona y vive en `care_feedback`—: un artículo es de la profesional y lo
-- lee todo su equipo.
--
-- Las reglas son las de `care_feedback`, para que no haya dos maneras de
-- pensar lo mismo:
--
--   · **Mientras no se publica, es privado.** Un borrador lo ve solo quien lo
--     escribe.
--   · **Borrar es `deleted_at`.** No hay `DELETE`; la limpieza diaria lo purga
--     a los 30 días.
--   · **Lo lee quien le dio acceso.** Un paciente ve los artículos publicados
--     de cada profesional con la que tiene un acceso vigente; si corta el
--     acceso, deja de verlos. El acceso no necesita ninguna categoría prendida:
--     leer lo que escribió la nutricionista no le abre a ella ningún dato.
--
-- Contrato para la app (lectura, con la sesión del paciente):
--
--   select id, author_id, kind, title, body, tag, published_at
--     from care_articles
--    where published_at is not null and deleted_at is null
--    order by published_at desc
--
-- RLS ya filtra por profesional vinculada; el nombre de la autora sale de
-- `care_professionals`, como en las devoluciones.

create table if not exists public.care_articles (
  id            uuid        primary key default extensions.gen_random_uuid(),
  author_id     uuid        not null
                  references public.profiles (id) on delete cascade,
  kind          text        not null default 'article',
  title         text        not null,
  -- Texto plano o markdown simple (párrafos, `- ` listas, `**negrita**`).
  body          text        not null,
  -- Una etiqueta opcional para agrupar ("Desayunos", "Vianda").
  tag           text,
  published_at  timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,

  constraint care_articles_kind check (kind in ('article', 'recipe')),
  constraint care_articles_title_len check (char_length(btrim(title)) between 1 and 140),
  constraint care_articles_body_len check (char_length(body) between 1 and 20000),
  constraint care_articles_tag_len check (tag is null or char_length(btrim(tag)) between 1 and 40)
);

create index if not exists care_articles_author_idx
  on public.care_articles (author_id, created_at desc)
  where deleted_at is null;
create index if not exists care_articles_published_idx
  on public.care_articles (author_id, published_at desc)
  where published_at is not null and deleted_at is null;

drop trigger if exists care_articles_set_updated_at on public.care_articles;
create trigger care_articles_set_updated_at
  before update on public.care_articles
  for each row execute function public.set_updated_at();

alter table public.care_articles enable row level security;

grant select, insert, update on public.care_articles to authenticated;

-- ¿Esta profesional es mía? El espejo de `has_any_care_access`, visto desde el
-- paciente. `security definer` porque la policy de `care_grants` ya filtra por
-- dueño y no conviene que una policy dependa de otra.
create or replace function public.is_my_professional(p_professional uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.care_grants g
     where g.owner_id = auth.uid()
       and g.professional_id = p_professional
       and g.status = 'accepted'
       and g.revoked_at is null
       and (g.expires_at is null or g.expires_at > now())
  );
$$;

revoke all on function public.is_my_professional(uuid) from public;
grant execute on function public.is_my_professional(uuid) to authenticated;

-- Quien escribe ve todo lo suyo. Un paciente ve lo publicado y no borrado de
-- sus profesionales vigentes.
drop policy if exists care_articles_read on public.care_articles;
create policy care_articles_read on public.care_articles
  for select to authenticated
  using (
    author_id = (select auth.uid())
    or (
      published_at is not null
      and deleted_at is null
      and public.is_my_professional(author_id)
    )
  );

drop policy if exists care_articles_insert on public.care_articles;
create policy care_articles_insert on public.care_articles
  for insert to authenticated
  with check (author_id = (select auth.uid()));

-- Editar, publicar, despublicar o borrar (suave) lo propio.
drop policy if exists care_articles_update on public.care_articles;
create policy care_articles_update on public.care_articles
  for update to authenticated
  using (author_id = (select auth.uid()))
  with check (author_id = (select auth.uid()));

-- Borrar de verdad no: el borrado es `deleted_at`, igual que en
-- `care_feedback`. La policy cierra el `DELETE` aunque algún grant lo abra.
drop policy if exists care_articles_no_hard_delete on public.care_articles;
create policy care_articles_no_hard_delete on public.care_articles
  for delete to authenticated
  using (false);

-- ── La limpieza diaria, con la tabla nueva ───────────────────────────────
-- El cuerpo sale de la definición vigente (migración 48), con `care_articles`
-- al final de la lista.
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
  delete from public.care_articles
   where deleted_at is not null and deleted_at < now() - interval '30 days';

  perform public.purge_shared_days();
end;
$$;

revoke execute on function public.purge_soft_deleted() from public, anon, authenticated;
