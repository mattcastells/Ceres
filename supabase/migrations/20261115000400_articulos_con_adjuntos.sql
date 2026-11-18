-- Migración 61 · Artículos con imágenes y videos.
--
-- Un artículo o una receta puede llevar hasta cinco adjuntos, en el orden en
-- que se muestran debajo del texto:
--
--   {"type": "image",   "path": "<author_id>/<uuid>.jpg"}   -- en `article-media`
--   {"type": "youtube", "id":   "<11 caracteres>"}          -- un video de YouTube
--
-- Los videos no se suben: se guarda solo el id, y la app muestra la miniatura
-- pública de YouTube y lo abre allá. Subir video propio sería otro producto
-- (transcodificación, almacenamiento, ancho de banda) para una demo.

-- ── 1 · La columna ───────────────────────────────────────────────────────
alter table public.care_articles
  add column if not exists media jsonb not null default '[]'::jsonb;

alter table public.care_articles drop constraint if exists care_articles_media_shape;
alter table public.care_articles add constraint care_articles_media_shape
  check (jsonb_typeof(media) = 'array' and jsonb_array_length(media) <= 5);

-- ── 2 · El bucket de las imágenes ────────────────────────────────────────
-- Privado: la app y el panel piden URLs firmadas, como con las fotos de
-- comidas. Hasta 5 MB por imagen, solo imágenes.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('article-media', 'article-media', false, 5242880,
        array['image/jpeg', 'image/png', 'image/webp', 'image/gif'])
on conflict (id) do update
   set public = excluded.public,
       file_size_limit = excluded.file_size_limit,
       allowed_mime_types = excluded.allowed_mime_types;

-- La profesional escribe en su carpeta (`<author_id>/...`).
drop policy if exists article_media_write on storage.objects;
create policy article_media_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'article-media'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists article_media_delete on storage.objects;
create policy article_media_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'article-media'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- Leen la autora y sus pacientes con un acceso vigente: la misma regla que
-- los artículos (`is_my_professional`, migración 53).
drop policy if exists article_media_read on storage.objects;
create policy article_media_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'article-media'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or public.is_my_professional(((storage.foldername(name))[1])::uuid)
    )
  );

-- down
-- drop policy if exists article_media_read on storage.objects;
-- drop policy if exists article_media_delete on storage.objects;
-- drop policy if exists article_media_write on storage.objects;
-- delete from storage.buckets where id = 'article-media';  (vaciarlo antes)
-- alter table public.care_articles drop constraint if exists care_articles_media_shape,
--   drop column if exists media;
