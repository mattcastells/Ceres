-- 53 · El objetivo recomendado: calorías y macros que propone la profesional.
--
-- "La profesional fija el objetivo calórico y de macros." Fijarlo **no** es
-- escribir en `goals`: los datos del paciente siguen siendo de solo lectura
-- para ella (migración 32), y el objetivo es del paciente —lo usa la app para
-- todo el día, y su historial no se reescribe—. Lo que ella hace es
-- **recomendarlo**: una indicación con números, que el paciente ve en la app y
-- aplica con un toque. Aplicarlo lo hace la app, con la sesión del paciente,
-- cerrando el objetivo vigente y abriendo otro como hace siempre.
--
-- Por eso son columnas de `care_feedback` y no una tabla nueva: es una
-- indicación más —borrador privado hasta que se publica, borrado suave,
-- escritura solo con acceso vigente—, con cuatro números además del texto.
--
-- Contrato para la app:
--
--   · El objetivo recomendado vigente es la indicación publicada más reciente
--     con `target_kcal` no nulo:
--       select id, author_id, body, target_kcal, target_protein_g,
--              target_carbs_g, target_fat_g, published_at, applied_at
--         from care_feedback
--        where kind = 'indication' and target_kcal is not null
--          and published_at is not null and deleted_at is null
--        order by published_at desc limit 1
--   · Los macros pueden venir en null: la profesional fijó solo las calorías,
--     y la app reparte los macros como lo hace siempre.
--   · `body` ya trae los números escritos ("Objetivo recomendado: 1.600 kcal
--     por día…"), así que una versión de la app que no conoce las columnas lo
--     muestra igual como una indicación más.
--   · "Aplicar" = la app crea el objetivo nuevo y después llama a
--     `mark_care_target_applied(id)`, que deja constancia para la profesional.
alter table public.care_feedback
  add column if not exists target_kcal      integer,
  add column if not exists target_protein_g integer,
  add column if not exists target_carbs_g   integer,
  add column if not exists target_fat_g     integer,
  add column if not exists applied_at       timestamptz;

alter table public.care_feedback drop constraint if exists care_feedback_target_kind;
alter table public.care_feedback add constraint care_feedback_target_kind check (
  kind = 'indication'
  or (target_kcal is null and target_protein_g is null
      and target_carbs_g is null and target_fat_g is null)
);

-- Un macro sin calorías no es un objetivo: la app no tendría qué aplicar.
alter table public.care_feedback drop constraint if exists care_feedback_target_needs_kcal;
alter table public.care_feedback add constraint care_feedback_target_needs_kcal check (
  target_kcal is not null
  or (target_protein_g is null and target_carbs_g is null and target_fat_g is null)
);

-- Los mismos topes que `goals` (`goals_target_range`): un objetivo que la app
-- no podría guardar no se puede recomendar.
alter table public.care_feedback drop constraint if exists care_feedback_target_range;
alter table public.care_feedback add constraint care_feedback_target_range check (
  (target_kcal is null or target_kcal between 800 and 6000)
  and (target_protein_g is null or target_protein_g between 0 and 500)
  and (target_carbs_g is null or target_carbs_g between 0 and 1000)
  and (target_fat_g is null or target_fat_g between 0 and 400)
);

-- `applied_at` lo escribe solo el paciente, por función (como `read_at`).
alter table public.care_feedback drop constraint if exists care_feedback_applied_needs_target;
alter table public.care_feedback add constraint care_feedback_applied_needs_target check (
  applied_at is null or target_kcal is not null
);

-- `read_at` y `applied_at` son del paciente, y los escribe solo por función.
-- Hasta acá la profesional podía escribirlos en sus propias filas (RLS no
-- limita columnas): el panel nunca lo hizo, pero "leída" y "aplicado" no
-- pueden depender de una convención. Se pasa a permisos por columna: la
-- profesional escribe su texto, sus números y cuándo publica o borra; las dos
-- marcas del paciente quedan afuera.
revoke insert, update on public.care_feedback from authenticated;
grant insert (id, author_id, patient_id, kind, local_date, body, source, published_at,
              target_kcal, target_protein_g, target_carbs_g, target_fat_g)
  on public.care_feedback to authenticated;
grant update (kind, local_date, body, published_at, deleted_at,
              target_kcal, target_protein_g, target_carbs_g, target_fat_g)
  on public.care_feedback to authenticated;

-- El paciente avisa que aplicó el objetivo. Por función y no por policy por
-- la misma razón que `mark_care_feedback_read`: RLS no limita columnas, y una
-- policy de update le dejaría reescribir los números de su nutricionista.
-- Aplicar implica haberlo leído.
create or replace function public.mark_care_target_applied(p_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.care_feedback
     set applied_at = coalesce(applied_at, now()),
         read_at    = coalesce(read_at, now())
   where id = p_id
     and patient_id = auth.uid()
     and target_kcal is not null
     and published_at is not null
     and deleted_at is null;
$$;

revoke all on function public.mark_care_target_applied(uuid) from public;
grant execute on function public.mark_care_target_applied(uuid) to authenticated;
