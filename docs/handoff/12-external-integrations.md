# 12 — External Integrations

Para cada integración: finalidad, autenticación, variables de entorno, límites, errores,
reintentos, cache, privacidad, mocks y estrategia de reemplazo.

---

## 1. Google Gemini — análisis de foto de comida

**Finalidad.** Estimar qué alimentos hay en una foto de un plato y en qué cantidad, para
prellenar la pantalla de revisión (F-05/F-06). **Nunca** guarda directo: el usuario revisa.

**Autenticación.** API key en el servidor. La llamada la hace **exclusivamente** la Edge
Function `analyze-meal-photo`. La clave nunca llega al cliente.

**Variables.** `GEMINI_API_KEY` (secreto de Edge Functions),
`GEMINI_MODEL` (default `gemini-3.6-flash`), `GEMINI_THINKING_LEVEL` (default `medium`),
`GEMINI_PROMPT_VERSION`.

**Techos de tiempo.** Cada llamada al proveedor se corta a los 30 s y los intentos
juntos a los 50 s (`GEMINI_BUDGET_MS`), después de lo cual la función contesta
`ERR_UPSTREAM_TIMEOUT` (504) y lo registra en `ai_analyses`. Los clientes esperan 60 s: el
techo del servidor tiene que ser **más chico** que el del cliente, o la app corta antes de
que el servidor llegue a contestar y el fallo no queda registrado en ningún lado.

**Reintentos.** Un corte por cuelgue **se reintenta** (hasta 3 intentos, los que entren en el
presupuesto): en `ai_analyses` los intentos que fallan no tardan, se cuelgan —vuelven con
`tokens_in` en `null`, sin un byte— y el siguiente contesta en 5 o 15 s. Un 429 no se
reintenta nunca (la cuota es del proyecto entero) y un JSON ilegible a `temperature: 0`
tampoco (es determinista: trae lo mismo). La política vive probada en
`_shared/estimation.test.ts`, que corre en CI.

**Contrato.** Se pide salida estructurada con `responseMimeType: application/json` y
`responseSchema` = `gemini-output-schema.json`. La respuesta se valida contra el schema
antes de persistir; si no valida → `ERR_AI_INVALID_RESPONSE`.

Prompt (v3), resumido — vive versionado en `supabase/functions/analyze-meal-photo/prompts/v3.txt`:

> Sos un asistente de estimación nutricional. Analizá la foto y devolvé los alimentos
> visibles. Para cada uno estimá la cantidad en gramos o mililitros usando referencias
> visuales (tamaño del plato, cubiertos, mano). Si no podés estimar con confianza, bajá el
> valor de `confidence`. No inventes alimentos que no se ven. No devuelvas texto fuera del
> JSON. Si no hay comida, devolvé `items: []`.

**Límites.** 20 análisis/día y 5/min por usuario (tabla `rate_limits`); imagen ≤ 8 MB,
1024 px lado mayor; timeout 25 s.

**Errores y reintentos.** JSON inválido → 1 reintento automático con `temperature: 0`.
5xx del proveedor → hasta 2 reintentos con backoff 1 s / 4 s. Agotado → `ERR_AI_INVALID_RESPONSE`
y camino manual con la foto ya adjunta.

**Cache.** Por `sha256` de los bytes de la imagen: si el mismo usuario reanaliza la misma
foto dentro de 24 h, se devuelve el análisis guardado sin consumir cuota.

**Privacidad.** La foto se sube a un bucket privado del usuario. Se envía a Gemini solo el
binario, sin identificadores personales. Se declara en la política de privacidad que las
fotos de comida se procesan con un proveedor de IA. El usuario puede borrar la foto en
cualquier momento; borrar la comida borra la foto y el análisis.

**Mock.** `FakeAiAnalysisService` devuelve un análisis fijo de 3 ítems con confianzas
0,82 / 0,44 / 0,67 tras 1,2 s simulados, y variantes para los caminos de error
(`no_food`, `invalid_json`, `quota`). Se activa con `APP_ENVIRONMENT=mock`.

**Reemplazo.** Toda la lógica está detrás de `AiAnalysisService`. Cambiar de proveedor
implica: nueva Edge Function con el mismo contrato de salida, nuevo `promptVersion`, y
correr el set de 40 fotos de referencia (`test/fixtures/meal-photos/`) comparando error
medio de kcal. No requiere tocar la app.

---

## 2. USDA FoodData Central

**Finalidad.** Catálogo nutricional genérico (alimentos sin marca, cortes, preparaciones).

**Autenticación.** API key por query string (`api_key`). Solo desde la Edge Function.

**Variables.** `USDA_API_KEY`.

**Endpoints usados.** `POST /v1/foods/search` (query, `dataType=Foundation,SR Legacy,Branded`,
`pageSize=25`) y `GET /v1/food/{fdcId}`.

**Límites.** 1000 req/hora por clave (R-05). Mitigación: cache de 30 días, debounce de
350 ms, búsqueda local primero, `pageSize` acotado.

**Errores.** 429 → se sirve cache + `meta.degraded = true`. 5xx / timeout > 4 s →
`ERR_UPSTREAM_TIMEOUT`, la búsqueda devuelve solo lo local. Nunca bloquea la pantalla.

**Reintentos.** 1 reintento a los 800 ms; después se degrada.

**Cache.** `foods_cache` con `expires_at = now() + 30 días`; refresco perezoso al abrir el
detalle de un alimento vencido.

**Privacidad.** Solo se envía el término de búsqueda. No se envían datos del usuario.

**Mock.** `assets/mock/usda_search.json` con 40 alimentos reales de ejemplo.

**Reemplazo.** Detrás de `FoodSearchService`. Alternativas evaluadas: Nutritionix (de pago),
Edamam (licencia restrictiva). Si se cambia, se mantiene el shape de `Food`.

---

## 3. Open Food Facts

**Finalidad.** Productos envasados con marca y código de barras — mejor cobertura de
Latinoamérica que USDA.

**Autenticación.** Sin clave. **Obligatorio** enviar un `User-Agent` identificatorio:
`Ceres/1.0 (contacto@ceres.app)`.

**Variables.** `OPEN_FOOD_FACTS_USER_AGENT`.

**Endpoints.** `GET /cgi/search.pl?search_terms=…&json=1&page_size=25` y
`GET /api/v2/product/{barcode}.json`.

**Límites.** Sin cuota formal; la política pide uso razonable — 10 req/s máximo desde
nuestra función, con cache agresiva.

**Errores.** Producto sin datos nutricionales → se descarta del resultado (no se muestra un
alimento con kcal desconocidas). 404 en barcode → "No encontramos ese producto" + crear
alimento con el EAN precargado.

**Cache.** Igual que USDA, `foods_cache` con `source = 'off'`.

**Privacidad.** Solo el término o el EAN. Sin datos del usuario.

**Mock.** `assets/mock/off_barcode.json`.

**Calidad de datos.** Los datos son colaborativos y pueden estar mal. Toda fila de resultado
muestra el badge de origen y el usuario puede corregir cualquier valor creando su copia.

---

## 4. Supabase

**Finalidad.** Auth, Postgres, Storage, Edge Functions, cron. Es el backend completo.

**Autenticación.** Cliente: `SUPABASE_URL` + `SUPABASE_ANON_KEY` + JWT del usuario.
Servidor: `SUPABASE_SERVICE_ROLE_KEY`, **nunca** en el cliente.

**Límites.** Plan Pro: 8 GB de base, 100 GB de Storage, 2 M invocaciones de función/mes.
Alerta a partir del 70 % de cualquiera.

**Errores.** Mapeo de PostgREST a códigos propios: `23505` → `ERR_CONFLICT`,
`23514` → `ERR_VALIDATION`, `42501` → `ERR_FORBIDDEN`, `PGRST116` → `ERR_NOT_FOUND`,
`401/403` → `ERR_UNAUTHENTICATED`/`ERR_FORBIDDEN`.

**Reintentos.** Solo lecturas y escrituras idempotentes, con el backoff de
`09-api-contracts.md` §2. Un 401 dispara un refresh de token y **un** reintento.

**Cache.** Ver `13-state-management.md`.

**Privacidad.** Región de datos: `sa-east-1` (São Paulo) para reducir latencia y mantener
los datos en la región. RLS en todas las tablas. Sin acceso de terceros.

**Mock.** `MockSupabaseClient` sobre la base SQLite local: la app corre completa sin red
con `APP_ENVIRONMENT=mock`, incluyendo auth simulada.

**Reemplazo.** Los repositorios están detrás de interfaces (`10-types-and-interfaces.ts`).
Migrar a otro backend implica reimplementar la capa `data/remote/`, no el dominio ni la UI.

---

## 5. Android Health Connect

**Finalidad.** Importar sesiones de ejercicio, energía activa, pasos, distancia, peso y
frecuencia cardíaca, con consentimiento.

> **Alcance (D-21):** Health Connect es la **única** integración de salud del producto. El
> soporte de Apple HealthKit quedó fuera de alcance por decisión de producto. En iOS la app
> funciona completa con registro manual y no ofrece integración de salud; la pantalla de
> integraciones solo aparece en Android.

**Autenticación.** Permisos de Health Connect declarados en el manifiesto y solicitados en
tiempo de ejecución. No hay claves ni tokens.

**Configuración.** `androidx.health.connect:connect-client`; `minSdk 26` con Health Connect
instalada (Android 14+ la trae de fábrica); declaración de la actividad
`ACTION_SHOW_PERMISSIONS_RATIONALE` apuntando a la política de privacidad.

**Tipos leídos (solo lectura, MVP):**

| Record de Health Connect | Uso |
| --- | --- |
| `ExerciseSessionRecord` | Sesiones → `activities` |
| `ActiveCaloriesBurnedRecord` | `estimated_calories` de la sesión |
| `StepsRecord` | `activityTotals.steps` (no crea actividad) |
| `DistanceRecord` | `distance_meters` |
| `WeightRecord` | `weight_logs` importados |
| `HeartRateRecord` | `average/maximum_heart_rate` |
| `TotalCaloriesBurnedRecord` | **No se usa como gasto de actividad** (ver D-12) |

> `TotalCaloriesBurnedRecord` incluye el metabolismo basal, que ya está dentro del objetivo
> calórico: usarlo sería doble conteo. Se usa `ActiveCaloriesBurnedRecord`. Si solo existe el
> total, se descarta y se recalcula por MET (RN-05). — decisión **D-12**.

**Escritura:** el MVP **no** escribe en Health Connect (D-13). Queda documentado como fase 2.

**Mapeo de tipos** (`ExerciseSessionRecord.exerciseType` → `activity_types.slug`):

```
EXERCISE_TYPE_WALKING → walking
EXERCISE_TYPE_RUNNING, EXERCISE_TYPE_RUNNING_TREADMILL → running
EXERCISE_TYPE_BIKING, EXERCISE_TYPE_BIKING_STATIONARY → cycling
EXERCISE_TYPE_SWIMMING_POOL, EXERCISE_TYPE_SWIMMING_OPEN_WATER → swimming
EXERCISE_TYPE_STRENGTH_TRAINING, EXERCISE_TYPE_WEIGHTLIFTING → strength_training
EXERCISE_TYPE_HIGH_INTENSITY_INTERVAL_TRAINING, EXERCISE_TYPE_CALISTHENICS → functional_training
EXERCISE_TYPE_YOGA → yoga            EXERCISE_TYPE_PILATES → pilates
EXERCISE_TYPE_HIKING → hiking        EXERCISE_TYPE_ELLIPTICAL → elliptical
EXERCISE_TYPE_ROWING, EXERCISE_TYPE_ROWING_MACHINE → rowing
EXERCISE_TYPE_STAIR_CLIMBING, EXERCISE_TYPE_STAIR_CLIMBING_MACHINE → stairs
EXERCISE_TYPE_DANCING → dancing
EXERCISE_TYPE_SOCCER, _BASKETBALL, _TENNIS, _VOLLEYBALL, … → sports
EXERCISE_TYPE_OTHER_WORKOUT y cualquier otro → custom
    (conservando el título original de la sesión en custom_name)
```

**Límites.** Ventana de lectura máxima de 30 días por consulta; paginación por `pageToken`
(persistido en `sync_cursor`); lotes de 200 registros; primera sincronización 30 días hacia
atrás. Rate limit del sistema por app.

**Errores.**

| Situación | Código | Comportamiento |
| --- | --- | --- |
| App de Health Connect no instalada | `ERR_PROVIDER_UNAVAILABLE` | Enlace a Play Store; el resto de la app funciona igual |
| Permisos denegados | `ERR_PERMISSION_DENIED` | Integración en `permission_denied` con acción "Volver a intentar" |
| Permisos revocados desde el sistema | `ERR_PERMISSION_DENIED` | La siguiente sync cambia el estado sin romper nada |
| Error de lectura del proveedor | `ERR_SYNC_FAILED` | Se conserva el cursor anterior, badge de error en la tarjeta |

**Reintentos.** La sincronización manual reintenta 1 vez; la automática espera al siguiente
ciclo (30 min).

**Privacidad.** Los datos de salud no salen del dispositivo sin consentimiento explícito; se
suben a Supabase solo los que el usuario acepta importar, y se pueden borrar con "Borrar los
datos importados". Prohibido enviarlos a analíticas (`14-analytics-events.md` §4). Health
Connect exige que la política de privacidad sea accesible desde el diálogo de permisos: la
ruta `/settings/privacy` debe abrirse sin sesión.

**Mock.** `FakeHealthProvider` devuelve 6 sesiones de una semana, una de ellas duplicada a
propósito con una manual, para ejercitar `DuplicateActivityDialog`.

**Reemplazo.** Todo está detrás de `HealthIntegrationService` y `HealthSyncService`, con
`HealthProvider` como enum de un solo valor. Agregar otro proveedor (Garmin, Strava, o
HealthKit si algún día se retoma) es sumar un valor al enum y un adaptador en
`data/native/`; no cambia ni el dominio ni la UI.

---

## 6. Sentry (observabilidad)

**Finalidad.** Crash reporting y trazas de las Edge Functions.
**Variables.** `SENTRY_DSN` (cliente), `SENTRY_DSN_FUNCTIONS` (servidor).
**Privacidad.** `sendDefaultPii = false`. Se envía `user.id` (uuid) y nunca email, peso,
kcal ni contenido de comidas. Los breadcrumbs de red se filtran para no incluir bodies.
**Muestreo.** 100 % de errores, 10 % de trazas de performance.

---

## 7. Reglas comunes a todas las integraciones

1. **Solo los permisos necesarios**, pedidos en contexto y no en el onboarding.
2. **Explicar cada permiso** antes de mostrar el diálogo del sistema
   (`dialog.permission_rationale`).
3. **La app funciona sin conectar nada** (RN-10).
4. **Se puede desconectar** en cualquier momento, sin perder los datos ya importados salvo
   que el usuario lo pida.
5. **Se pueden borrar los datos importados** de un proveedor, con confirmación que aclara
   que los registros manuales no se tocan.
6. **Se guarda `last_sync_at`** y se muestra en la tarjeta de la integración.
7. **Los errores de sincronización se informan**, con el motivo en lenguaje claro y acción
   de reintento.
8. **Se evitan duplicados** siempre (RN-07, §12 de calculation-rules).
9. **La sincronización es incremental** por ancla/cursor, nunca completa.
10. **No se sobrescribe un registro manual** ni uno editado sin confirmación (RN-06).
