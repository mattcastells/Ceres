# 08 — Supabase Plan

Proyecto Supabase con Postgres 15, Auth, Storage, Edge Functions (Deno) y pg_cron.
Tres entornos: `dev`, `staging`, `prod` — proyectos separados, mismas migraciones.

## 1. Migraciones

```
supabase/migrations/
  20260801000100_extensions.sql          uuid-ossp, pgcrypto, btree_gist, pg_trgm, pg_cron
  20260801000200_profiles.sql            profiles + trigger de alta desde auth.users
  20260801000300_goals.sql               goals + constraint de exclusión por rango
  20260801000400_foods.sql               foods, foods_cache, recent_foods
  20260801000500_meals.sql               meals, meal_items, trigger recalc_meal_totals
  20260801000600_ai_analyses.sql         ai_analyses
  20260801000700_activity_types.sql      activity_types
  20260801000701_seed_activity_types.sql seed desde met-catalog.json (upsert por slug)
  20260801000800_activities.sql          activities + índices + índice único externo
  20260801000900_activity_goals.sql      activity_goals, exercise_templates, rest_days
  20260801001000_body.sql                weight_logs, body_measurements
  20260801001100_health.sql              health_integrations, sync_records, duplicate_resolutions
  20260801001200_strength_phase2.sql     strength_exercises, strength_sets (vacías)
  20260801001300_audit.sql               audit_log + triggers en activities/goals/profiles
  20260801001400_rls.sql                 RLS de todas las tablas
  20260801001500_views_rpc.sql           vistas activas + RPC (create_meal_with_items, get_daily_summary)
  20260801001600_jobs.sql                pg_cron: purga de soft deletes, borrado de cuentas, limpieza de cache
```

Reglas: idempotentes, con `-- down` comentado, nunca se editan una vez aplicadas en `prod`.

## 2. Row Level Security

RLS **activado en todas las tablas**. Patrón por defecto:

```sql
alter table public.activities enable row level security;

create policy "activities_select_own" on public.activities
  for select using (auth.uid() = user_id);

create policy "activities_insert_own" on public.activities
  for insert with check (auth.uid() = user_id);

create policy "activities_update_own" on public.activities
  for update using (auth.uid() = user_id)
             with check (auth.uid() = user_id);

-- El borrado físico se prohíbe: la app hace soft delete vía update.
create policy "activities_no_hard_delete" on public.activities
  for delete using (false);
```

Casos particulares:

```sql
-- meal_items: la pertenencia se resuelve por la comida padre
create policy "meal_items_own" on public.meal_items
  for all using (exists (
    select 1 from public.meals m
    where m.id = meal_items.meal_id and m.user_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.meals m
    where m.id = meal_items.meal_id and m.user_id = auth.uid()
  ));

-- activity_types: los del sistema los lee cualquiera autenticado; los propios, su dueño
create policy "activity_types_read" on public.activity_types
  for select using (is_system or user_id = auth.uid());
create policy "activity_types_write_own" on public.activity_types
  for insert with check (user_id = auth.uid() and not is_system);

-- foods_cache: lectura para autenticados, escritura solo con service_role
create policy "foods_cache_read" on public.foods_cache
  for select to authenticated using (true);
-- (sin policy de insert: solo la Edge Function con service_role puede escribir)

-- audit_log: el usuario puede leer su propio log; nadie puede escribirlo desde el cliente
create policy "audit_read_own" on public.audit_log
  for select using (auth.uid() = user_id);
```

**Verificación obligatoria:** el test `rls_test.sql` (fase 13 del roadmap) intenta, con el
JWT del usuario A, leer/escribir/borrar filas del usuario B en **cada** tabla y espera 0
filas o error en todos los casos.

## 3. Buckets de Storage

| Bucket | Público | Ruta | Límite | Política |
| --- | --- | --- | --- | --- |
| `meal-photos` | no | `{user_id}/{meal_or_analysis_id}.jpg` | 8 MB, `image/jpeg\|png\|heic` | lectura/escritura solo del dueño (prefijo = `auth.uid()`) |
| `activity-photos` | no | `{user_id}/{activity_id}.jpg` | 8 MB | ídem |
| `progress-photos` | no | `{user_id}/{weight_log_id}.jpg` | 8 MB | ídem |
| `avatars` | no | `{user_id}/avatar.jpg` | 2 MB | ídem; se sirve con URL firmada de 1 h |
| `exports` | no | `{user_id}/{export_id}.zip` | 50 MB | escritura solo `service_role`; lectura del dueño; TTL 7 días |

```sql
create policy "own_folder_rw" on storage.objects
  for all to authenticated
  using (bucket_id = 'meal-photos' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'meal-photos' and (storage.foldername(name))[1] = auth.uid()::text);
```

Las imágenes nunca se sirven públicas: la app pide una **URL firmada** de 1 hora.

## 4. Edge Functions

| Función | Método | Auth | Qué hace |
| --- | --- | --- | --- |
| `analyze-meal-photo` | POST | JWT de usuario | Descarga la foto del bucket, llama a Gemini con el prompt versionado, valida contra `gemini-output-schema.json`, persiste `ai_analyses`, devuelve los ítems. Aplica la cuota de 20/día. |
| `food-search` | GET | JWT | Consulta `foods_cache`; si falta, USDA FDC y Open Food Facts en paralelo con timeout de 4 s; fusiona, deduplica por nombre+marca, cachea y devuelve. |
| `food-detail` | GET | JWT | Detalle nutricional por `(source, external_id)`; cachea. |
| `barcode-lookup` | GET | JWT | Open Food Facts por EAN; fallback USDA; cachea. |
| `sync-health` | POST | JWT | Recibe el lote normalizado que el cliente leyó de Health Connect, aplica deduplicación server-side, escribe `activities` y `sync_records`, devuelve el resumen y los candidatos a duplicado. |
| `export-user-data` | POST | JWT | Genera JSON + CSV de todas las tablas del usuario, lo sube a `exports` y envía el enlace firmado por correo. |
| `delete-account` | POST | JWT + reautenticación | Marca `deletion_requested_at`, revoca sesiones, encola `deletion_jobs`. |
| `cron-purge` | — | `service_role` | Invocada por pg_cron: purga soft deletes > 30 días, cache vencida, ejecuciones de borrado de cuenta vencidas. |

Todas devuelven el sobre de error de `09-api-contracts.md` §2 y registran en Sentry con el
`request_id` propagado desde el cliente.

**Ejemplo — `analyze-meal-photo` (esqueleto):**

```ts
// supabase/functions/analyze-meal-photo/index.ts
import { createClient } from "jsr:@supabase/supabase-js@2";

const PROMPT_VERSION = "v5";
const DAILY_QUOTA = 20;

Deno.serve(async (req) => {
  const auth = req.headers.get("Authorization");
  if (!auth) return err(401, "ERR_UNAUTHENTICATED");

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { global: { headers: { Authorization: auth } } },
  );

  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return err(401, "ERR_UNAUTHENTICATED");

  const { photoPath, analysisId, requestId } = await req.json();

  const { count } = await supabase.from("ai_analyses")
    .select("id", { count: "exact", head: true })
    .eq("user_id", user.id)
    .gte("created_at", startOfDayUtc());
  if ((count ?? 0) >= DAILY_QUOTA) return err(429, "ERR_QUOTA_EXCEEDED");

  // … descarga de Storage, llamada a Gemini con responseSchema,
  //    validación, persistencia en ai_analyses, respuesta.
});
```

## 5. Secretos

Se cargan con `supabase secrets set`. **Ninguno vive en el cliente.**

| Secreto | Usado por |
| --- | --- |
| `GEMINI_API_KEY` | `analyze-meal-photo` |
| `USDA_API_KEY` | `food-search`, `food-detail` |
| `OPEN_FOOD_FACTS_USER_AGENT` | `food-search`, `barcode-lookup` |
| `SUPABASE_SERVICE_ROLE_KEY` | todas las funciones |
| `SENTRY_DSN_FUNCTIONS` | todas |
| `RESEND_API_KEY` | `export-user-data`, avisos de borrado |

## 6. Triggers

| Trigger | Tabla | Qué hace |
| --- | --- | --- |
| `on_auth_user_created` | `auth.users` | Inserta la fila en `profiles` |
| `set_updated_at` | todas | `updated_at = now()` |
| `recalc_meal_totals` | `meal_items` | Recalcula `meals.total_*` en insert/update/delete |
| `recalc_applied_calories` | `activities` | Si cambia `estimated_calories` o `exercise_credit_percentage`, recalcula `applied_calories` |
| `track_recent_food` | `meal_items` | Upsert en `recent_foods` |
| `track_recent_activity` | `activities` | Upsert en `recent_activities` |
| `audit_changes` | `activities`, `goals`, `profiles` | Escribe `audit_log` con el diff |
| `guard_hard_delete` | tablas de contenido | Lanza excepción ante un `DELETE` físico desde el cliente |

## 7. Jobs (pg_cron)

| Job | Frecuencia | Qué hace |
| --- | --- | --- |
| `purge_soft_deleted` | diario 03:00 UTC | Borra definitivamente lo marcado hace > 30 días y sus objetos de Storage |
| `process_account_deletions` | diario 03:15 UTC | Ejecuta los borrados cuyo período de gracia de 7 días venció |
| `expire_food_cache` | semanal | Borra `foods_cache` con `expires_at < now()` |
| `trim_recents` | semanal | Deja las 50 entradas más recientes por usuario |
| `purge_audit_log` | mensual | Borra `audit_log` de más de 180 días |
| `purge_exports` | diario | Borra objetos de `exports` de más de 7 días |

## 8. Rate limiting

Aplicado en las Edge Functions con una tabla `rate_limits (user_id, bucket, window_start, count)`
y ventana deslizante:

| Operación | Límite |
| --- | --- |
| `analyze-meal-photo` | 20 / día y 5 / minuto por usuario |
| `food-search` | 60 / minuto por usuario |
| `sync-health` | 4 / hora por usuario y proveedor |
| `export-user-data` | 2 / día por usuario |
| `delete-account` | 3 / día por usuario |

Excedido → HTTP 429 con `ERR_RATE_LIMITED` y cabecera `Retry-After`.

## 9. Backups

- Backups automáticos diarios de Supabase con retención de 7 días en `prod` (plan Pro) y
  **PITR de 7 días**.
- Volcado lógico semanal (`pg_dump`) a almacenamiento externo, cifrado, retención 90 días.
- Storage: replicación gestionada por Supabase; los objetos de `meal-photos` se consideran
  reconstruibles (el usuario puede volver a subir), los de `exports` son efímeros.
- **Prueba de restauración trimestral** obligatoria a un proyecto `restore-test`, con
  checklist firmado.

## 10. Eliminación de cuenta

1. `delete-account` marca `profiles.deletion_requested_at`, revoca refresh tokens
   (`auth.admin.signOut(userId, 'global')`) e inserta en `deletion_jobs`.
2. Durante 7 días el usuario puede cancelar iniciando sesión.
3. `process_account_deletions` ejecuta:
   `delete from auth.users where id = :user_id` (cascada a todas las tablas por FK) y
   borra los prefijos `{user_id}/` de los 5 buckets.
4. Se conserva **únicamente** un registro anonimizado en `deletion_audit`
   (`hash(user_id)`, `requested_at`, `completed_at`) por obligación de trazabilidad.
5. Correo de confirmación al finalizar.

## 11. Exportación de datos

`export-user-data` genera un ZIP con:
`profile.json`, `goals.csv`, `meals.csv`, `meal_items.csv`, `foods.csv`, `activities.csv`,
`weight_logs.csv`, `body_measurements.csv`, `activity_goals.csv`, `integrations.json`,
`README.txt` (diccionario de columnas y unidades). Las fotos se incluyen como enlaces
firmados de 7 días, no como binarios, para acotar el tamaño.
