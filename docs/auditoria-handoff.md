# Handoff — arreglos de la auditoría del 1 de agosto de 2026

**Estado: todo implementado y verificado. Nada publicado todavía.**

El informe con la evidencia de cada hallazgo está en
[`auditoria-2026-08-01.md`](auditoria-2026-08-01.md). Acá quedó lo que se hizo,
cómo se verificó y lo único que falta, que necesita una decisión o un teléfono.

## Cómo quedó

| | Antes | Ahora |
| --- | --- | --- |
| Tests de Flutter | 376 | **399** |
| Suite pgTAP | 66 | **85** |
| Migraciones | 27 | **32** |
| `flutter analyze --fatal-infos` | limpio | limpio |
| Edge Functions | 4 | **5** (`delete-account`) |

Las cinco migraciones nuevas aplican desde cero contra un Postgres limpio
(`supabase db reset`), que es como las corre CI.

---

# Etapa 1 · Crítico e inmediato (seguridad y privacidad) — ✅

## 1.1 · `pals_update`: quien pedía el vínculo podía aceptárselo solo ✅

`supabase/migrations/20260801002700_pals_consent.sql`

- La política ahora deja actualizar **solo al destinatario**, **solo desde
  `pending`** y **solo hacia `accepted`/`blocked`**. El solicitante perdió el
  UPDATE: cancelar ya era DELETE.
- Trigger `pals_guard_identity`: un vínculo no puede cambiar de personas. Hacía
  falta porque el `with check` mira la fila resultante y no la anterior, así que
  el destinatario podía aceptar reescribiendo `requester_id` y meter a un
  tercero que nunca lo pidió.
- Deshacer un bloqueo pasa a ser borrar la fila. No existía como gesto en la app.

**Verificado**: 4 casos nuevos en `supabase/tests/pals_consent_test.sql` —
A no puede aceptar su propia solicitud, no ve el día de B mientras esté
pendiente, no puede reapuntar la solicitud a un tercero, y B sí puede aceptar.

## 1.2 · El perfil entero se abría a pals y a solicitudes pendientes ✅

Misma migración.

- `profiles_pal_read` **borrada**. Se reemplaza por la vista `pal_profiles`, de
  dos columnas (`id`, `display_name`), con `security_barrier`.
- `PalsClient.list()` ahora hace dos consultas en vez de un join embebido:
  PostgREST solo embebe atravesando una FK y una vista no la tiene.
- Se conservó a propósito que el nombre se vea con la solicitud pendiente: sin
  él, "Ana quiere ser tu pal" no se puede decidir. Lo que cambió es que ahora es
  **solo** el nombre.

**Efecto lateral que atajó la suite**: cerrar `profiles` rompía las políticas de
agua, sueño y fotos, que preguntaban por el toggle con un `exists` sobre
`profiles` evaluado bajo RLS. Se reemplazó por `pal_shares(owner, categoría)`,
`security definer`, con las dos condiciones en un solo lugar. De paso las de
agua y sueño se acotaron a la ventana de 7 días que la de fotos ya tenía, y el
cast a uuid de la política de fotos quedó detrás de una comprobación de forma.

**Verificado**: `columns_are` sobre la vista, más los dos casos de perfil
cerrado / nombre visible. `pals_sharing_test.sql` sigue en verde.

## 1.3 · "Eliminar mi cuenta" no eliminaba nada ✅

- **Edge Function nueva**: `supabase/functions/delete-account/index.ts`. Borra
  los objetos de los cuatro buckets por prefijo y después el usuario de Auth; la
  cascada desde `profiles` limpia las 26 tablas. Si Storage falla, **aborta y no
  toca la cuenta**: un borrado a medias sobre datos de salud no es una opción.
- `AuthGateway.deleteAccount()`, implementado contra la función (con timeout de
  60 s) y como no-op en la compilación sin servidor.
- La pantalla llama al servidor **antes** de limpiar el teléfono, con estado de
  carga y mensaje de error. Al revés, un fallo dejaba a la persona sin sus datos
  y con la cuenta viva.
- El texto de la pantalla y `PRIVACY_POLICY.md` dicen lo que pasa: borrado
  inmediato, sin gracia de 7 días.

**Verificado**: `test/presentation/delete_account_test.dart`, 2 casos. El
segundo es el que importa: si el servidor no pudo borrar, la comida y la sesión
locales siguen ahí.

## 1.4 · Actions de CI sin pin ✅

- Las nueve referencias van clavadas a su commit, con la versión en el
  comentario al lado.
- `permissions: contents: read` a nivel workflow en `ci.yml`.
- `.github/dependabot.yml` para que los pins no envejezcan.

---

# Etapa 2 · Integridad de datos — ✅

## 2.1 · Editar una medida rompía el push para siempre ✅

- `logMeasurement` reutiliza el id del mismo día y métrica, como ya hacían
  `logWeight` y `logSleep`.
- `BodyMeasurement` gana `updatedAt` y `deletedAt`; borrar deja lápida.
- **Repara las cuentas ya rotas**: `document_merge` colapsa las medidas que
  comparten métrica y día, y le deja al ganador **el id que el servidor ya
  conoce**, así el push siguiente actualiza esa fila en su lugar en vez de
  chocar contra el índice único.
- De paso: `_timestampFields` nombraba `loggedAt` para las medidas, un campo que
  el modelo nunca tuvo.

**Verificado**: 4 casos en `measurements_test.dart` + 6 en
`document_merge_test.dart`.

## 2.2 · Un solo contrato de borrado ✅

- Migración 29: `sleep_logs.deleted_at`, y `purge_soft_deleted` pasa a incluirla
  (con el `revoke` que la recreación de la función devolvía).
- El push manda las lápidas de comidas, actividades, sueño y medidas; antes las
  filtraba con `if (!isDeleted)` y el borrado se quedaba en el teléfono.
- El pull las trae, así que un borrado hecho en otro dispositivo llega.
- `purge_soft_deleted` deja de ser un no-op perpetuo sobre `meals` y
  `activities`.

## 2.3 · El push dejó de ganarle al merge por default ✅

- Migración 30: `set_updated_at` solo mueve la fecha **si la fila cambió de
  verdad** (comparando `to_jsonb(new) - 'updated_at'` contra el viejo). El push
  reescribe todas las filas en cada corrida, así que el servidor quedaba siempre
  "más nuevo" y su copia reemplazaba a la local en cada vuelta.
- El pull convierte los `timestamptz` a hora local: un almuerzo de 13:30 se
  mostraba 16:30 en cuanto la reconciliación lo traía de vuelta.
- `ai_analysis_id` viaja en las dos direcciones; antes se perdía en silencio.

**Verificado**: `supabase/tests/sync_contract_test.sql`, 7 casos. Incluye que un
cliente **no** puede retrodatar una fila sin cambiarle nada.

## 2.4 · Entrar con otra cuenta en el mismo teléfono ✅

`LocalStore.accountId` guarda el `auth.users.id`; `signIn` arranca limpio si no
coincide. Antes, una sesión vencida sin cerrar dejaba que la persona siguiente
se llevara las comidas y los pesos de la anterior — y que el push los escribiera
en **su** cuenta.

**Verificado**: 3 casos en `demo_seed_test.dart`, incluido que sin id de cuenta
(compilación sin servidor) no se borra nada.

## 2.5 · Timeouts ✅

`cloud_backup_client`, `pals_client` y `supabase_auth_gateway` tenían **cero**;
ahora todos los `await` de red del proyecto tienen plazo propio. Además:

- `PhotoStorageClient.remove` **lanza** cuando no hay conexión y trata el 404
  como éxito. Antes se tragaba el `SocketException`, así que la purga creía
  haber borrado, limpiaba `photoPath`, y la foto quedaba huérfana para siempre.
- El splash tiene un tope global de 8 s, que es la promesa que su comentario
  hacía desde siempre sin que nada la cumpliera.

**Verificado**: 2 casos nuevos en `photo_storage_test.dart` contra el cliente
real, no contra el doble.

## 2.6 · Los fallos que no se ven ✅

- `backupStateProvider` siembra el estado actual antes del stream: "Al día"
  después de un fallo era la misma clase de mentira que costó meses de `meals`
  vacíos.
- `myPalCodeProvider` pasa a `autoDispose`: cacheaba el **error**, así que abrir
  Pals una vez sin conexión dejaba el código en "…" toda la sesión.
- Aceptar y quitar un pal tienen try/catch con mensaje.

---

# Etapa 3 · Mediano plazo — ✅

| | Qué se hizo |
| --- | --- |
| 3.1 Restaurar | El diálogo dice lo que pasa: con servidor, la copia **se combina** con la cuenta y no se pierde lo posterior. Se eligió eso antes que forzar el borrado remoto: restaurar no debería poder borrar lo que se cargó en otro dispositivo. |
| 3.2 Paginación | `traer()` pagina de a 500 ordenando por `id`; `meal_items` se pide de a 200 comidas en vez de una URL con todos los uuids. |
| 3.3 Cerrar sesión | Drena el push y el respaldo antes de cerrar. Los comentarios que decían "se usa al cerrar sesión" pasaron a ser ciertos. |
| 3.4 El día | `refreshOnResume()` vuelve a hoy si la elección tiene más de 4 h, que es la regla que el comentario describía y nadie implementaba. |
| 3.5 Borrador | "Cargar a mano" tras un fallo de análisis adjunta la foto al borrador abierto en vez de reemplazarlo y dejar un spinner sin salida. |
| 3.6 Ids | uuid v5 derivado de `(cuenta, colección, fecha[, métrica])` para las tablas de uno-por-día: dos dispositivos convergen en vez de chocar. |
| 3.7 Errores | `on Object` en Sugerencias; `try/finally` en `openAfterPull` para que un `Error` no deje el dispositivo sin escribir el resto de la sesión. |
| 3.8 UX | "por 100 g" solo si la porción se mide en peso o volumen; media móvil y línea de objetivo salen del tema (eran invisibles en claro, 1,06:1); el calendario habilita los 3 días de planificación usando `isPlannable`. |

**Verificado**: 3 casos de ids determinísticos en `weight_test.dart`.

---

# Etapa 4 · Limpieza — ✅

- **Borrado**: `lib/core/result.dart` entero (`Result`/`Ok`/`Err`/`Page`, cero
  usos), `offlineProvider`, `pendingCountProvider`, `ChartSession.reset()`, las
  rutas `/profile/templates` y `/profile/favorites` con su `initialTab`.
- **Conservado con el comentario corregido**: `PendingReviewBanner` y la
  maquinaria de duplicados, que esperan la importación de sesiones de ejercicio.
  Su doc decía que era "visible sobre cualquier tab" y no se monta en ningún lado.
- **SQL** (migración 31): seis índices que duplicaban a un `unique`, y las
  extensiones `uuid-ossp` y `pg_trgm`, sin un solo uso en el repo.
- **Comentarios corregidos** (los ocho del informe): la fecha que "se resetea",
  el splash de 1500 ms, los filtros de Historial "persistidos", "se usa al
  cerrar sesión", "es lo único del perfil que se abre", "aceptar lo hace quien
  recibe", "el documento sigue siendo la fuente de verdad", "la red todavía no
  participa". Más el APK por ABI que ya no se publica.
- **Contadores**: 31 migraciones y 83 pgTAP en `README`, `releases.md` y
  `ci.yml`. `docs/releases.md` ya no dice que el chequeo de updates sea manual.
- **Config**: las 4 variables de las Edge Functions en `.env.local.example`,
  `supabase/.branches/` ignorado y destrackeado, `min_sdk_android` alineado en 26.

---

# Etapa 5 · La brecha de la auditoría: los cálculos — ✅ sin hallazgos

Era lo que había quedado sin revisar. Se verificaron **a mano, con valores
conocidos**, los 13 archivos de `lib/domain/calculations/`:

- **Mifflin-St Jeor**: 80 kg / 180 cm / 30 a / varón → 1780. Correcto, y el
  caso `unspecified` es el promedio exacto de las dos variantes.
- **Ajuste calórico**: 7700 kcal/kg ÷ 7 = 1100 kcal por kg/semana. 0,5 kg/semana
  → 550 kcal/día. ✓
- **MET**: `MET × 3,5 × kg ÷ 200 × min`. El ejemplo canónico del propio archivo
  (100 kg, MET 3,5, 30 min → 184) da exacto.
- **Tabla MET de carrera**: los cortes 8,0 / 9,7 / 11,3 / 12,9 km/h son 5/6/7/8
  mph y cada tramo lleva el MET de su borde inferior. Una carrera de 10 km/h da
  **9,8**, que es lo que resolvió el conflicto con el fixture T-15.
- **Macros**: 4/4/9 cierra exacto (2000 kcal / 70 kg → 112 g P + 56 g G + 262 g
  C = 2000). El escalonado cuando los carbos caen por debajo de 50 nunca
  devuelve un macro negativo.
- **Edad**: cumple años el mismo día del cumpleaños; un 29 de febrero cumple el
  1 de marzo en año no bisiesto.
- **Divisiones por cero**: todas guardadas (`targetValue <= 0`,
  `durationMinutes <= 0`, `denominator == 0`, `adjustedTarget <= 0`).
- **BMI, adherencia, media móvil y regresión de tendencia**: correctos.

Una observación, no un bug: el piso de RN-12 es el mínimo por sexo
(1200/1500/1350) y **no** el BMR, así que con un TDEE bajo y el ritmo al máximo
el objetivo puede quedar por debajo del metabolismo basal. Es la regla escrita
del producto; si se quiere cambiar, es una decisión y no una corrección.

---

# Etapa 6 · Los bajos, que son los que se notan usando la app — ✅

La primera tanda cerró lo crítico y lo alto. Esta cierra los **bajos** del
informe, que no son menos importantes para quien usa la app: dos de ellos eran
crashes.

## Crashes y mensajes que mentían

| | Qué pasaba | Qué se hizo |
| --- | --- | --- |
| Deep link a una plantilla | `firstWhere(..., orElse: () => templates.first)` lanzaba `StateError` con cero plantillas, y con un id inexistente hidrataba **otra** plantilla en silencio | Busca sin `orElse` y, si no está, no hidrata nada |
| Objetivo manual en "0" | `macroTargets` lanza con cero, así que tipear ese carácter tiraba la pantalla | El preview usa el extremo del rango; guardar valida aparte |
| "Guardar objetivo" fuera de rango | `return` mudo: se tocaba y no pasaba nada | Dice el rango en un snackbar |
| Doble-tap | "Guardar alimento" y "Y otra" creaban **dos** registros | `loading` + guarda temprana en los dos |
| Búsqueda sin conexión | Cada fuente tenía su `catchError` a lista vacía, así que decía "No encontramos ese alimento" y el botón "Reintentar" era inalcanzable | Si fallan **las dos**, lanza y la pantalla ofrece reintentar |
| Cancelar la cámara | Cualquier fallo decía "No pudimos abrir la cámara" y mandaba a revisar un permiso que estaba bien | Solo `PlatformException` es permiso; el resto tiene su propio mensaje |
| "X agregada" | El snackbar se pedía con el `context` del sheet ya cerrado y se perdía según la carrera | El messenger se toma antes del `pop` |

## Fugas

- **Foto huérfana al cancelar el análisis.** Analizar sube la foto con un id al
  azar; si el modelo fallaba o alguien cancelaba, esa copia quedaba en el bucket
  sin que nada la nombrara. `analyze` ahora entrega la ruta apenas sube
  (`onUploaded`) y la pantalla la borra al salir por cualquiera de las tres
  puertas.
- **Los APK descargados se acumulaban**: solo se borraba el del mismo nombre, así
  que quedaban 75 MB por versión en un directorio que Android no limpia. Ahora se
  barren todos los `ceres-*.apk` antes de bajar.
- **El peso de Health Connect entraba como `'manual'`.** `logWeight` acepta
  `source` y la importación manda `'imported'`.
- **`PalPublisher` perdía el cambio** que llegaba durante una publicación: salía
  por `_publishing` sin marcar nada. Ahora reprograma, como hacen el respaldo y
  el sync.
- **La cuarentena sobrevivía al cierre de sesión**, así que la siguiente persona
  en ese teléfono podía verla y exportarla. Se limpia en `signOut`.
- **Los objetivos no desempataban en el merge**: el dispositivo con el objetivo
  viejo abierto le ganaba al que ya lo había cerrado y lo des-cerraba en el
  servidor. `Goal` gana `updatedAt`.

## Servidor (migración 32)

- **`rate_limits` ya no crece sin techo.** `check_rate_limit` valida el bucket
  contra una allowlist —`ai_analysis`, `food_search`, `pal_request`, los tres
  que existen— y hay un job diario que barre lo de más de una semana. Antes
  cualquier cuenta podía llamar la función con un nombre distinto cada vez.
- **Un `display_name` largo ya no tumba el alta.** `handle_new_user` trunca a 80
  en vez de dejar que el `check` aborte el insert en `auth.users`, que fallaba
  con "Database error saving new user".
- **`anon` pierde el EXECUTE por omisión** sobre las funciones del esquema, y lo
  que `authenticated` necesita queda explícito. Hoy todas fallaban seguro; esto
  cierra la posibilidad de que la próxima función nazca abierta.

## Release y dependencias

- **El tag corre CI entero**: hasta acá el release repetía `analyze` y
  `flutter test` pero no los jobs de Edge Functions ni de base, así que una
  migración rota o una función que no parsea se publicaban igual.
- **El updater verifica el sha256** contra el `digest` que GitHub ya publicaba y
  nadie leía. Por streaming, no cargando 75 MB en memoria — que es exactamente
  el error que dejó a todos sin actualizar entre la 1.0.4 y la 1.5.0.
- **`connect-client` pasa de `1.1.0-alpha07` a `1.1.0` estable.** Una alpha en
  el build que se publica es un contrato que el proveedor puede cambiar sin
  aviso. Verificado que resuelve en el classpath de release.

---

# Lo único que queda

## Necesita una decisión tuya

1. **Los placeholders legales.** `PRIVACY_POLICY.md:12-13` y
   `TERMS_OF_SERVICE.md:80` siguen con `[insert legal name / entity]` y
   `[insert contact email]`. No los completé porque no me corresponde
   inventarlos, y están linkeados desde el README de un repo público.
2. **`uploads/`**: el mismo PDF dos veces, byte a byte, sin que nada lo
   referencie. Antes de borrarlo conviene confirmar que no tiene datos
   personales en el texto ni en los metadatos; si los tuviera, sacarlo del HEAD
   no alcanza.
3. **`create_meal_with_items` y `get_daily_summary`**: siguen existiendo y no
   los llama nadie. O la app los adopta o se borran; los dejé porque borrar un
   RPC es más difícil de deshacer que decidirlo con calma.

## Necesita el proyecto real

Antes de publicar, contra `ifincvqdsotorvmwzpos`:

1. **Aplicar las migraciones 28 a 31** con el session pooler y `--db-url` (ver
   `supabase/README.md`), y confirmar con `supabase migration list`.
2. **Desplegar `delete-account`** y darle el secreto: `supabase secrets set` con
   la secret key. Sin eso la función contesta 503 y la pantalla lo dice.
3. **Medidas duplicadas**: `select user_id, metric, local_date, count(*) from
   body_measurements group by 1,2,3 having count(*) > 1`. Con el colapso del
   merge se reparan solas al reconciliar, pero conviene saber a cuántas cuentas
   alcanzó.
4. **"Max rows"** (Settings → API): la paginación ya no depende de ese valor,
   pero saberlo cierra la última incógnita del informe.
5. **Auth** (Providers → Email): `config.toml` dice contraseñas de 6 sin
   requisitos y sin confirmación de correo, y eso solo gobierna el stack local.

## Necesita un teléfono

Lo de siempre, sin cambios: el análisis de foto con una foto real, Health
Connect en un Samsung, y el widget puesto en una pantalla de inicio. Además,
de esta tanda:

- **Borrar una cuenta de prueba de punta a punta** y confirmar que volver a
  entrar con ese correo crea una cuenta nueva y vacía.
- **Aceptar y quitar un pal** contra el proyecto real, que es lo que toca la
  política nueva.
- **La hora de una comida** después de que la reconciliación la traiga de
  vuelta: tiene que decir 13:30 y no 16:30.
