-- Migración 58 · La foto de perfil del paciente, en el panel.
--
-- La app sube la foto de perfil a `progress-photos/{id}/perfil.jpg` y guarda
-- la ruta en `profiles.avatar_path`. El panel no la podía mostrar por dos
-- motivos: `care_patients` no traía la ruta, y ninguna política de Storage
-- dejaba a la profesional leer ese bucket.
--
-- Lo que se abre es **solo la foto de perfil**, no el bucket: las fotos de
-- progreso (cuerpo) viven en el mismo bucket y siguen detrás de la categoría
-- "cuerpo" del permiso. La foto de perfil se muestra con cualquier vínculo
-- vigente, sin categoría: es la cara de la persona en la lista, como el
-- nombre, que tampoco depende de qué compartió.

-- ── 1 · La vista, con la ruta ───────────────────────────────────────────
-- Igual a la de `20260819000200_care_contexto_y_tracking`, más `avatar_path` al final (`create or
-- replace view` solo deja agregar columnas al final).
create or replace view public.care_patients
with (security_barrier = true) as
  select
    g.id            as grant_id,
    g.owner_id      as patient_id,
    p.display_name  as patient_name,
    p.biological_sex,
    p.birth_date,
    p.height_cm,
    p.unit_system,
    g.share_meals,
    g.share_photos,
    g.share_body,
    g.share_wellbeing,
    g.accepted_at,
    g.expires_at,
    public.tracking_since(g.owner_id) as tracking_since,
    p.avatar_path
  from public.care_grants g
  join public.profiles p on p.id = g.owner_id
 where g.professional_id = (select auth.uid())
   and g.status = 'accepted'
   and g.revoked_at is null
   and (g.expires_at is null or g.expires_at > now());

grant select on public.care_patients to authenticated;

-- ── 2 · ¿Esta ruta es la foto de perfil de alguien que sigo? ───────────
-- `security definer` porque la profesional no puede leer `profiles` ajenos
-- (la política de Storage corre con sus permisos). Compara contra la ruta
-- guardada, no contra un nombre fijo: si la app algún día cambia dónde la
-- guarda, la política sigue valiendo y nunca abre otra foto del bucket.
-- Quien administra un consultorio la ve igual que la ficha (migración 56).
create or replace function public.care_avatar_visible(p_name text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.profiles p
      join public.care_grants g on g.owner_id = p.id
     where p.avatar_path = p_name
       and g.status = 'accepted'
       and g.revoked_at is null
       and (g.expires_at is null or g.expires_at > now())
       and (g.professional_id = auth.uid()
            or public.manages_professional(g.professional_id))
  );
$$;

-- La usa una política de Storage, que corre como quien consulta: necesita
-- `execute` para `authenticated` (como `has_care_access`).
revoke all on function public.care_avatar_visible(text) from public;
grant execute on function public.care_avatar_visible(text) to authenticated;

drop policy if exists progress_photos_care_avatar on storage.objects;
create policy progress_photos_care_avatar on storage.objects
  for select to authenticated
  using (
    bucket_id = 'progress-photos'
    and public.care_avatar_visible(name)
  );

-- down
-- drop policy if exists progress_photos_care_avatar on storage.objects;
-- drop function if exists public.care_avatar_visible(text);
-- (y volver a la vista de `20260819000200`, sin `avatar_path`: hace falta
-- `drop view` + `create view`, porque `create or replace` no saca columnas)
