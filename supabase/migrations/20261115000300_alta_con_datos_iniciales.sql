-- Migración 60 · Dar de alta con los datos iniciales cargados por la
-- nutricionista.
--
-- Hasta acá había dos caminos para sumar un paciente: el código (la persona
-- lo carga en la app) y la invitación por mail (migración 56), donde la
-- persona completa sus datos sola. Esta suma el tercero: la profesional hace
-- la primera consulta, completa el formulario y la invitación sale con eso.
--
-- Lo que carga se separa en dos, porque no es para los mismos ojos:
--
-- - `intake`: lo que pide el onboarding de la app (sexo, nacimiento, altura,
--   peso, actividad, objetivo, calorías, restricciones). La persona lo ve al
--   abrir la invitación y la app lo **propone** en el onboarding: lo revisa y
--   lo confirma ella. Nada se escribe en su cuenta sin que acepte.
-- - `anamnesis`: lo clínico (motivo de consulta, patologías, medicación,
--   antecedentes). Es de la profesional: el paciente no lo recibe nunca
--   (`my_care_invites` no lo devuelve). Se queda en la invitación, que solo
--   lee quien la mandó (`care_invites_read_own`), y al aceptar la invitación
--   anota de qué paciente es (`patient_id`): la ficha la muestra desde ahí.
--
--   No se copia a un borrador de `care_feedback` (lo que reemplazó a
--   `care_notes` en la migración 48) a propósito: un borrador está a un clic
--   de "Publicar", y la anamnesis no puede llegarle al paciente por error.

-- ── 1 · Las columnas ─────────────────────────────────────────────────────
alter table public.care_invites
  add column if not exists patient_name text,
  add column if not exists intake       jsonb,
  add column if not exists anamnesis    jsonb,
  -- Quién aceptó. `on delete set null`: si la cuenta se borra, la anamnesis
  -- sigue siendo de la profesional, pero ya no se puede atar a nadie.
  add column if not exists patient_id   uuid
    references public.profiles (id) on delete set null;

create index if not exists care_invites_patient_idx
  on public.care_invites (professional_id, patient_id)
  where patient_id is not null;

alter table public.care_invites drop constraint if exists care_invites_name_len;
alter table public.care_invites add constraint care_invites_name_len
  check (patient_name is null or char_length(patient_name) between 1 and 80);

alter table public.care_invites drop constraint if exists care_invites_intake_obj;
alter table public.care_invites add constraint care_invites_intake_obj
  check (intake is null or jsonb_typeof(intake) = 'object');

alter table public.care_invites drop constraint if exists care_invites_anamnesis_obj;
alter table public.care_invites add constraint care_invites_anamnesis_obj
  check (anamnesis is null
         or (jsonb_typeof(anamnesis) = 'object'
             and pg_column_size(anamnesis) <= 16000));

-- ── 2 · Invitar, ahora con datos ─────────────────────────────────────────
-- Cambia la firma: se borra la de un argumento para que no queden dos
-- sobrecargas (PostgREST no sabría a cuál llamar). Los nuevos argumentos
-- tienen default, así que `invite_patient(p_email)` sigue andando.
--
-- Volver a invitar a un mail con una invitación pendiente la actualiza con
-- los datos nuevos en vez de rechazarla: corregir un número de la anamnesis
-- no debería obligar a cancelar y empezar de nuevo.
drop function if exists public.invite_patient(text);

create or replace function public.invite_patient(
  p_email     text,
  p_name      text  default null,
  p_intake    jsonb default null,
  p_anamnesis jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email  text := lower(trim(p_email));
  v_name   text := nullif(trim(coalesce(p_name, '')), '');
  target   uuid;
  existing uuid;
begin
  if not public.is_professional(auth.uid()) then
    raise exception 'ERR_FORBIDDEN' using hint = 'Solo una cuenta profesional da de alta pacientes.';
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'ERR_VALIDATION' using hint = 'Revisá el mail.';
  end if;
  if p_intake is not null and jsonb_typeof(p_intake) <> 'object' then
    raise exception 'ERR_VALIDATION' using hint = 'Los datos iniciales no tienen el formato esperado.';
  end if;
  if p_anamnesis is not null and jsonb_typeof(p_anamnesis) <> 'object' then
    raise exception 'ERR_VALIDATION' using hint = 'La anamnesis no tiene el formato esperado.';
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
    update public.care_invites
       set patient_name = coalesce(v_name, patient_name),
           intake       = coalesce(p_intake, intake),
           anamnesis    = coalesce(p_anamnesis, anamnesis)
     where id = existing;
    return existing;
  end if;

  insert into public.care_invites (professional_id, email, patient_name, intake, anamnesis)
  values (auth.uid(), v_email, v_name, p_intake, p_anamnesis)
  returning id into existing;
  return existing;
end;
$$;

revoke all on function public.invite_patient(text, text, jsonb, jsonb) from public;
grant execute on function public.invite_patient(text, text, jsonb, jsonb) to authenticated;

-- ── 3 · Lo que ve el paciente: los datos de la app, nunca la anamnesis ───
-- Cambia el tipo de retorno: hay que borrarla antes.
drop function if exists public.my_care_invites();

create function public.my_care_invites()
returns table (
  id                uuid,
  professional_id   uuid,
  professional_name text,
  org_name          text,
  created_at        timestamptz,
  intake            jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  select i.id, i.professional_id, p.display_name, o.name, i.created_at, i.intake
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

revoke all on function public.my_care_invites() from public;
grant execute on function public.my_care_invites() to authenticated;

-- ── 4 · Aceptar: la invitación anota quién la aceptó ──────────────────────
-- Igual a la de `20261114000200_ajustes_de_la_revision`, más el paso final.
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

  -- `patient_id` ata la invitación (y su anamnesis) a quien la aceptó: la
  -- ficha de la profesional la busca por ahí.
  update public.care_invites
     set status = 'accepted', responded_at = now(), patient_id = auth.uid()
   where id = inv.id;

  return grant_id;
end;
$$;

-- down
-- Volver a las funciones de `20261114000200_ajustes_de_la_revision` (drop de
-- las nuevas firmas primero) y:
-- alter table public.care_invites drop column if exists patient_name,
--   drop column if exists intake, drop column if exists anamnesis,
--   drop column if exists patient_id;
