# 03 — User Flows

Cada flujo declara: **punto de entrada, pasos, validaciones, errores, resultado final y
estado persistido**. Los códigos de error (`ERR_*`) están definidos en
`09-api-contracts.md` §2. Los eventos entre corchetes son de `14-analytics-events.md`.

---

## F-01 — Crear cuenta

**Entrada:** `/welcome` → "Crear cuenta".

**Pasos**
1. `/auth/sign-up`: email, contraseña, checkbox de términos.
2. Submit → `AuthService.signUp({ email, password })` → Supabase Auth `signUp`.
3. Éxito → `/auth/check-email` (confirmación por correo activada).
4. El usuario abre el enlace → la app recibe el deep link `ceres://auth/callback` →
   sesión activa → `/onboarding/goal`. `[onboarding_started]`

**Validaciones**
- Email: regex RFC 5322 simplificada, ≤ 254 caracteres, trim + lowercase.
- Contraseña: 8–72 caracteres, al menos una letra y un número. Indicador de fuerza.
- Términos: obligatorio marcar.
- Submit deshabilitado hasta que todo sea válido; validación en `onBlur`, no en cada tecla.

**Errores**
| Situación | Código | Mensaje al usuario |
| --- | --- | --- |
| Email ya registrado | `ERR_EMAIL_TAKEN` | "Ya existe una cuenta con ese correo. ¿Querés iniciar sesión?" + botón |
| Contraseña débil (rechazo del servidor) | `ERR_WEAK_PASSWORD` | "La contraseña necesita al menos 8 caracteres, una letra y un número." |
| Sin conexión | `ERR_OFFLINE` | "No hay conexión. Necesitás internet para crear la cuenta." (sin reintento automático) |
| Rate limit | `ERR_RATE_LIMITED` | "Demasiados intentos. Probá de nuevo en unos minutos." |

**Resultado final:** sesión Supabase activa, fila en `auth.users`, fila en `profiles`
creada por trigger con `profile_completed = false`.

**Estado persistido:** `session` en almacenamiento seguro (Keychain / EncryptedSharedPreferences),
`profiles` en Postgres, réplica local en SQLite.

---

## F-02 — Completar onboarding

**Entrada:** primera sesión con `profile_completed = false`.

**Pasos**
1. **Objetivo** (`/onboarding/goal`): bajar de peso / mantener / subir de peso.
2. **Cuerpo** (`/onboarding/body`): sexo biológico, fecha de nacimiento, altura, peso actual.
3. **Nivel de actividad** (`/onboarding/activity-level`): sedentario 1,2 · ligero 1,375 ·
   moderado 1,55 · alto 1,725 · muy alto 1,9. Cada opción con una descripción concreta
   ("Sedentario: trabajo de oficina, poco movimiento fuera del día a día").
4. **Objetivo calórico** (`/onboarding/target`): muestra BMR, TDEE y el objetivo sugerido.
   Selector de ritmo (0,25 / 0,5 / 0,75 / 1 kg por semana) y opción "Ingresar manualmente".
5. **Crédito de ejercicio** (`/onboarding/exercise-credit`): 0 % (por defecto) / 50 / 75 /
   100 / personalizado, con el texto de RN-02 y la explicación:
   *"Las calorías quemadas durante el ejercicio suelen sobreestimarse. Podés decidir cuánto
   de ese gasto agregar a tu presupuesto diario."*
6. **Resumen** (`/onboarding/summary`): objetivo base, macros sugeridos, crédito elegido.
   Botón "Empezar". `[onboarding_completed]`

**Validaciones**
| Campo | Regla | Error |
| --- | --- | --- |
| Fecha de nacimiento | edad 13–100 | "Necesitás tener al menos 13 años para usar Ceres." |
| Altura | 90–250 cm | "Ingresá una altura entre 90 y 250 cm." |
| Peso | 25–400 kg | "Ingresá un peso entre 25 y 400 kg." |
| Objetivo manual | 800–6000 kcal | "Ingresá un objetivo entre 800 y 6000 kcal." |
| Objetivo manual < mínimo (RN-12) | confirmación | `dialog.low_target_warning` |
| Crédito personalizado | 0–100 % entero | "Elegí un valor entre 0 % y 100 %." |

**Errores:** escritura fallida → se guarda local y se encola (`ERR_OFFLINE` no bloquea el
onboarding; el perfil se sincroniza después).

**Resultado final:** `/home` con el resumen del día vacío y estado vacío educativo.

**Estado persistido:** `profiles` (sexo, nacimiento, altura, nivel de actividad, zona
horaria, unidades, `exercise_credit_percentage`, `profile_completed = true`),
`goals` (fila activa con `base_calorie_target`, macros, `rate_kg_per_week`, `goal_type`,
`starts_on`), `weight_logs` (primer registro con el peso del paso 2).

---

## F-03 — Agregar alimento manual

**Entrada:** FAB → `sheet.add` → "Agregar comida", o `/home` → botón "+" de un slot.

**Pasos**
1. `/meal/new?slot=lunch&date=2026-07-27` con la comida en borrador (aún sin persistir).
2. "Agregar alimento" → `/food/search`.
3. Sin resultados útiles → "Crear alimento" → `/food/new`: nombre, marca opcional, tamaño
   de porción + unidad, calorías, proteínas, carbohidratos, grasas; opcionales fibra,
   azúcares, sodio.
4. Guardar alimento → vuelve al detalle con la porción precargada → "Agregar a la comida".
5. Repetir para cada ítem. La cabecera muestra el total acumulado en vivo.
6. "Guardar comida" → `MealService.createMeal`. `[meal_created]` con `method: 'manual'`.

**Validaciones**
- Nombre del alimento: 1–120 caracteres, requerido.
- Porción: > 0, ≤ 10000, hasta 2 decimales.
- Calorías: 0–2000 por porción, entero.
- Macros: 0–500 g cada uno. Si `|kcal_declaradas − kcal_por_macros| > 20 %` y > 30 kcal,
  se muestra una advertencia no bloqueante: "Los macros no coinciden con las calorías
  (≈ N kcal). ¿Querés revisarlos?" (ver `11-calculation-rules.md` §5).
- La comida debe tener ≥ 1 ítem para guardarse.

**Errores**
| Situación | Comportamiento |
| --- | --- |
| Sin conexión | La comida se guarda local con `sync_status = 'pending'` y se muestra `SyncStatusBadge`. No se bloquea nada. |
| Conflicto de escritura (409) | Última escritura del usuario gana; se registra en el log de conflictos (`13-state-management.md` §9). |
| Falla de validación del servidor | Se marca el campo y se conserva el borrador. |

**Resultado final:** comida visible en Inicio dentro de su slot; el anillo de calorías se
actualiza de forma optimista.

**Estado persistido:** `meals`, `meal_items`, `foods` (si se creó uno propio),
`recent_foods` (upsert).

---

## F-04 — Buscar alimento

**Entrada:** `/meal/new` → "Agregar alimento", o `sheet.add` → "Escanear alimento" con
resultado sin match.

**Pasos**
1. `/food/search` con foco automático en el campo y teclado abierto.
2. Antes de escribir: pestañas **Recientes · Favoritos · Mis alimentos**.
3. Al escribir (debounce 350 ms, mínimo 2 caracteres):
   - Búsqueda local inmediata (SQLite: `foods` propios + `foods_cache`).
   - En paralelo `FoodSearchService.search(query)` → Edge Function `food-search` que
     consulta USDA FDC y Open Food Facts y fusiona resultados.
4. Resultados agrupados: "Tuyos" → "Marcas" → "Genéricos". Cada fila muestra nombre, marca,
   porción de referencia y kcal. `[food_searched]` con `{ query_length, result_count, source }`.
5. Tap → `/food/:foodId` con `sheet.portion` para elegir cantidad y unidad.
6. "Agregar" → vuelve a `/meal/new` con el ítem cargado.

**Validaciones:** cantidad > 0; unidad debe pertenecer a las porciones del alimento.

**Errores**
| Situación | Comportamiento |
| --- | --- |
| Sin resultados | Estado vacío con acciones "Crear alimento" y "Sacar una foto" |
| Timeout del proveedor (> 6 s) | Se muestran solo los resultados locales + banner "No pudimos consultar el catálogo online. Reintentar" |
| `ERR_RATE_LIMITED` de USDA | Igual que timeout; se sirve cache y se registra `integration_sync_failed` con `provider: 'usda'` |
| Offline | Solo resultados locales, banner permanente "Sin conexión — buscando solo en tus alimentos" |

**Resultado final:** ítem agregado al borrador de la comida.

**Estado persistido:** `foods_cache` (upsert del alimento externo), `recent_foods`.

---

## F-05 — Analizar foto

**Entrada:** `sheet.add` → "Sacar foto de una comida".

**Pasos**
1. `/meal/photo/capture`: permiso de cámara (con `dialog.permission_rationale` previo).
   Visor con guía "Encuadrá el plato completo desde arriba".
2. Disparo → previsualización → "Usar esta foto" / "Repetir".
3. Compresión a JPEG, lado mayor 1024 px, calidad 0,8. Subida a Storage
   `meal-photos/{user_id}/{uuid}.jpg`.
4. `/meal/photo/analyzing`: llamada a la Edge Function `analyze-meal-photo`. Skeleton
   animado + texto "Estimando lo que hay en el plato…". Cancelable.
5. Respuesta → `/meal/photo/review`. `[meal_photo_analyzed]` con
   `{ duration_ms, item_count, confidence_avg }`.

**Validaciones**
- Tamaño de archivo ≤ 8 MB tras comprimir.
- Cuota: 20 análisis por usuario por día (R-01). Al agotarse:
  "Llegaste al límite diario de análisis por foto. Podés registrar la comida a mano."
- Timeout de la función: 25 s.

**Errores**
| Situación | Código | Comportamiento |
| --- | --- | --- |
| Permiso de cámara denegado | `ERR_PERMISSION_DENIED` | Pantalla con explicación y botón "Abrir configuración"; alternativa "Elegir de la galería" |
| Sin conexión | `ERR_OFFLINE` | La foto se guarda local y se encola; tarjeta en Inicio "Foto pendiente de análisis" con acción de reintento |
| Gemini no devuelve JSON válido | `ERR_AI_INVALID_RESPONSE` | Un reintento automático; si vuelve a fallar → "No pudimos leer la foto. Podés cargar la comida a mano." con la foto ya adjunta |
| Gemini no reconoce comida | `ERR_AI_NO_FOOD` | "No encontramos comida en la foto." + "Sacar otra" / "Cargar a mano" |
| Cuota agotada | `ERR_QUOTA_EXCEEDED` | Mensaje de cuota, sin reintento |

**Resultado final:** un `ai_analyses` persistido y la pantalla de revisión abierta.

**Estado persistido:** archivo en Storage, fila en `ai_analyses`
(`status`, `model`, `prompt_version`, `raw_response`, `items`, `confidence`, `latency_ms`).

---

## F-06 — Corregir análisis

**Entrada:** `/meal/photo/review` tras F-05.

**Pasos**
1. Cabecera: foto + banner ámbar **"Estimación de IA — revisá antes de guardar"**.
2. Lista de ítems detectados. Cada uno con nombre, porción estimada, kcal y
   `ConfidenceBadge` (alta ≥ 0,75 · media 0,5–0,75 · baja < 0,5). Los de confianza baja
   aparecen con el campo de cantidad resaltado.
3. Acciones por ítem: editar cantidad, cambiar unidad, reemplazar por un alimento del
   catálogo (`/food/search?target=ai_item`), eliminar.
4. "Agregar ítem" para lo que la IA no vio.
5. Selector de slot (desayuno / almuerzo / cena / snack) — precargado según la hora.
6. "Guardar comida" → crea `meals` + `meal_items` con `source = 'ai_photo'`.
   Si algún valor cambió respecto del original → `[ai_result_corrected]` con
   `{ items_total, items_edited, items_removed, items_added, kcal_delta }`.

**Validaciones:** al menos un ítem; mismas reglas de cantidad/macros que F-03.

**Errores:** si el guardado falla, el borrador de revisión persiste local y se puede
retomar desde Inicio ("Análisis sin guardar").

**Resultado final:** comida creada, análisis vinculado (`meals.ai_analysis_id`).

**Estado persistido:** `meals`, `meal_items`, `ai_analyses.status = 'accepted'`,
`ai_analyses.corrections` (diff entre lo propuesto y lo guardado — insumo para mejorar el prompt).

---

## F-07 — Guardar comida

**Entrada:** `/meal/new` o `/meal/photo/review` con ≥ 1 ítem.

**Pasos**
1. Se calcula el total de la comida sumando los ítems (`11-calculation-rules.md` §4).
2. Escritura optimista: la comida aparece en Inicio de inmediato con
   `sync_status = 'pending'`.
3. `MealService.createMeal` → `POST /rest/v1/meals` + `meal_items` en una transacción RPC
   `create_meal_with_items` (idempotente por `meal.id` generado en cliente).
4. Éxito → `sync_status = 'synced'`, snackbar "Comida guardada · Ver".

**Validaciones:** `logged_at` no puede ser más de 24 h en el futuro; slot válido; suma de
ítems > 0 kcal.

**Errores**
| Situación | Comportamiento |
| --- | --- |
| 409 por `id` duplicado | Se considera éxito (idempotencia) y se marca `synced` |
| 5xx | Reintento con backoff exponencial (1 s, 4 s, 15 s, 60 s, luego cada 5 min) |
| Falla persistente > 24 h | Badge de error en la tarjeta + acción "Reintentar ahora" |

**Resultado final:** comida en el día, anillo y desglose actualizados.

**Estado persistido:** `meals`, `meal_items`, `recent_foods`, cola de sincronización.

---

## F-08 — Agregar ejercicio

**Entrada:** FAB → `sheet.add` → "Agregar ejercicio" → `sheet.activity_add`.

**Pasos (camino rápido, modo `duration`)**
1. `/activity/new?mode=duration`. Pantalla de **registro rápido** con 5 campos visibles:
   tipo, duración, intensidad, fecha/hora, calorías estimadas.
2. Tipo: `ActivityTypeSelector` — chips de las 4 actividades más usadas + "Ver todas".
3. Duración: `DurationInput` con presets 15 / 30 / 45 / 60 min y rueda para valores libres.
4. Intensidad: `ActivityIntensitySelector` — Suave / Moderada / Intensa (default: Moderada).
5. Cada cambio de tipo, duración, intensidad o peso corporal recalcula el gasto
   (`ExerciseCalculationService.calculateCaloriesFromMet`) y actualiza
   `ExerciseCaloriesEstimate`, que muestra **"≈ 184 kcal · estimado por MET 3,5"**.
6. Campos opcionales plegados: distancia, pasos, FC promedio, FC máxima, notas, foto.
7. "Guardar" → `ActivityService.createActivity`. `[activity_created]` con
   `{ activity_type, mode, estimation_method, duration_minutes, was_overridden }`.

**Sub-modos**
- `walk_run`: muestra distancia y pasos desplegados por defecto; si hay distancia y
  duración, ofrece "Calcular por ritmo" (ver `11-calculation-rules.md` §11).
- `distance`: distancia como campo primario, duración secundaria.
- `strength`: nombre del entrenamiento, duración, intensidad, kcal, notas (MVP).
- `custom`: permite crear un `activity_types` propio con su MET por intensidad.

**Validaciones**
| Campo | Regla | Error |
| --- | --- | --- |
| Tipo | requerido | "Elegí un tipo de actividad." |
| Duración | 1–1440 min | "La duración debe estar entre 1 y 1440 minutos." |
| Fecha/hora | no más de 24 h en el futuro; no antes de la fecha de alta | "No podés registrar actividad en el futuro." |
| Distancia | 0–500 000 m | "Revisá la distancia." |
| Pasos | 0–200 000 | "Revisá la cantidad de pasos." |
| FC promedio / máxima | 30–230 bpm; promedio ≤ máxima | "La frecuencia promedio no puede superar la máxima." |
| Calorías (override) | 1–10 000 | "Ingresá un valor entre 1 y 10 000 kcal." |
| Solapamiento con otra actividad | advertencia no bloqueante | "Ya tenés una actividad en ese horario. ¿Es otra distinta?" → `dialog.duplicate_activity` |

**Errores:** offline → guardado local + cola (idéntico a F-07).

**Resultado final:** actividad en la sección "Actividad" de Inicio; si el crédito de
ejercicio es > 0 %, el objetivo ajustado y las calorías restantes se recalculan y la
tarjeta principal anima el cambio.

**Estado persistido:** `activities` (con `estimated_calories`, `applied_calories`,
`exercise_credit_percentage` congelado, `estimation_method`, `source_type = 'manual'`),
`recent_activities`.

---

## F-09 — Importar ejercicio

**Entrada:** `/settings/integrations/:provider` → "Conectar", o sincronización automática
al abrir la app (máximo 1 vez cada 30 min, solo con la app en primer plano).

**Pasos**
1. `dialog.permission_rationale` explica **cada** permiso solicitado y para qué se usa.
2. `HealthIntegrationService.connect(provider)` → permiso nativo del SO.
3. `HealthSyncService.sync(provider)` — sincronización **incremental** desde
   `health_integrations.last_sync_at` (primera vez: 30 días hacia atrás).
4. Por cada sesión recibida:
   a. Se normaliza a `Activity` (mapeo de tipos en `12-external-integrations.md` §5.3).
   b. `DuplicateDetectionService.check(activity)` (RN-07).
   c. Sin coincidencia → insert con `source_type = 'imported'`, `external_source`,
      `external_id`, `estimation_method = 'provider'`.
   d. Coincidencia **exacta** (`external_source` + `external_id` ya existentes) → update si
      `source_updated_at` es más nuevo **y** `user_edited = false`; si `user_edited = true`,
      se omite y se registra en `sync_records.skipped_reason = 'user_edited'` (RN-06).
   e. Coincidencia **probable** (solapamiento temporal con una actividad manual) → se
      inserta con `sync_status = 'needs_review'` y se encola para `dialog.duplicate_activity`.
5. Fin → `last_sync_at`, `sync_cursor`, resumen: "Se importaron 4 actividades. 1 necesita
   tu confirmación." `[activity_imported]` por cada una (`{ provider, activity_type, had_calories }`).

**Validaciones:** se descartan sesiones de duración < 1 min o sin `started_at`. Si
`active_calories` es nulo o inválido → RN-05.

**Errores**
| Situación | Código | Comportamiento |
| --- | --- | --- |
| Permiso denegado | `ERR_PERMISSION_DENIED` | La integración queda `status = 'permission_denied'` con acción "Volver a intentar" |
| Health Connect no instalada (Android) | `ERR_PROVIDER_UNAVAILABLE` | Enlace a Play Store, sin bloquear la app |
| Error del proveedor | `ERR_SYNC_FAILED` | Se conserva `last_sync_at` anterior, badge de error en `HealthIntegrationCard`. `[integration_sync_failed]` |
| Sincronización parcial | — | Se guarda lo importado y `sync_cursor` avanza solo hasta el último ítem confirmado |

**Resultado final:** actividades importadas visibles con `DataOriginBadge = "Importado ·
Health Connect"`; las dudosas con badge "Revisar".

**Estado persistido:** `activities`, `health_integrations`, `sync_records`.

---

## F-10 — Corregir calorías de ejercicio

**Entrada:** `/activity/:id` → "Editar calorías", o desde el registro antes de guardar.

**Pasos**
1. `dialog.override_calories`: muestra el valor calculado, un input para el nuevo valor y
   un motivo opcional (chips: "Mi reloj marcó otra cosa" · "Me pareció mucho" ·
   "Me pareció poco" · "Otro").
2. Guardar → RN-04: `original_calories` = valor calculado (si aún era nulo),
   `estimated_calories` = nuevo, `estimation_method = 'user_override'`,
   `override_reason`, `user_edited = true`.
3. Se recalcula `applied_calories` con el porcentaje vigente y se actualiza el día.
   `[activity_calories_edited]` con `{ from, to, delta, reason, previous_method }`.
4. El detalle muestra: **"≈ 210 kcal · corregido por vos (cálculo original: 184 kcal)"**
   con acción "Restaurar el valor calculado".

**Validaciones:** 1–10 000 kcal, entero.

**Errores:** offline → cola. Conflicto con una importación posterior → RN-06 protege el valor.

**Resultado final:** actividad con valor corregido y trazabilidad completa.

**Estado persistido:** `activities` (`original_calories`, `estimated_calories`,
`estimation_method`, `override_reason`, `user_edited`, `updated_at`).

---

## F-11 — Registrar peso

**Entrada:** `sheet.add` → "Registrar peso", o Progreso → "Registrar peso".

**Pasos**
1. `sheet.weight`: input numérico grande precargado con el último peso, fecha (default hoy),
   nota opcional, foto de progreso opcional.
2. Guardar → `WeightService.log`. `[weight_logged]` con `{ delta_kg, days_since_last }`.
3. La hoja se cierra y Progreso muestra el punto nuevo con la media móvil de 7 días
   actualizada.

**Validaciones**
- Peso: 25–400 kg, 1 decimal. Si el cambio respecto del último registro es > 3 kg en < 3
  días → advertencia no bloqueante "Es un cambio grande, ¿lo confirmás?".
- Una sola entrada por fecha: registrar de nuevo el mismo día **actualiza** la existente
  (upsert por `(user_id, local_date)`) y avisa "Actualizamos el peso de hoy".

**Errores:** offline → cola.

**Resultado final:** punto nuevo en la serie; el peso pasa a ser el usado por las fórmulas
MET (S-07).

**Estado persistido:** `weight_logs`.

---

## F-12 — Consultar historial

**Entrada:** tab Historial.

**Pasos**
1. `/history`: lista invertida por fecha, agrupada por mes, con scroll infinito
   (páginas de 30 días).
2. Cada fila-día muestra: fecha, kcal consumidas, kcal de actividad, kcal aplicadas al
   objetivo, duración total de ejercicio, cantidad de actividades, pasos si existen, y un
   indicador de si quedó dentro / fuera del objetivo (neutral, sin color de castigo:
   punto lleno = dentro, punto hueco = fuera, gris = sin registro).
3. `sheet.filters`: solo comidas · solo ejercicio · manuales · importadas · tipo de
   actividad · rango de fechas.
4. Tap en un día → `/history/:date` con el detalle completo: comidas por slot, actividades,
   peso, objetivo base, ajuste por ejercicio y balance final.

**Validaciones:** rango de fechas ≤ 366 días y `from ≤ to`.

**Errores**
| Situación | Comportamiento |
| --- | --- |
| Offline | Se sirve lo que hay en SQLite; banner "Mostrando datos guardados" |
| Sin datos en el rango | Estado vacío "No hay registros en este período" + acción "Quitar filtros" |

**Resultado final:** el usuario ve cualquier día pasado; puede editar registros desde ahí.

**Estado persistido:** ninguno (lectura). Los filtros se guardan en preferencias locales.

---

## F-13 — Cambiar objetivo

**Entrada:** `/profile/target` → "Editar objetivo", o `/settings/exercise-credit`.

**Pasos (objetivo calórico)**
1. Se muestra el objetivo vigente, cómo fue calculado y desde cuándo rige.
2. El usuario cambia el tipo de objetivo, el ritmo o pasa a manual.
3. "Guardar" → se **cierra** la fila vigente de `goals` (`ends_on = ayer`) y se inserta una
   nueva (`starts_on = hoy`). Los días pasados conservan su objetivo histórico.
   `[goal_updated]` con `{ goal_type, previous_target, new_target, method }`.

**Pasos (crédito de ejercicio)**
1. `/settings/exercise-credit`: radios 0 / 50 / 75 / 100 / personalizado + slider.
2. Cambio → `profiles.exercise_credit_percentage`.
3. **Recálculo:** se recalculan las `applied_calories` de las actividades **del día en
   curso y los días futuros**. Los días cerrados conservan el porcentaje con el que fueron
   registrados (D-05). Se avisa: "Aplicamos el cambio desde hoy. Los días anteriores
   quedan como estaban."
4. Toggle "Desactivar el ajuste por ejercicio" → equivale a 0 % y oculta la fila "Ajuste"
   de la tarjeta principal.

**Validaciones:** objetivo 800–6000 kcal (RN-12 para el mínimo); crédito 0–100 %.

**Errores:** offline → cola; el objetivo se aplica local de inmediato.

**Resultado final:** el objetivo nuevo rige desde hoy; el historial no se reescribe.

**Estado persistido:** `goals` (nueva fila), `profiles`, `activities.applied_calories`
recalculadas del día en curso en adelante.

---

## F-14 — Eliminar cuenta

**Entrada:** `/settings/privacy` → "Eliminar mi cuenta".

**Pasos**
1. `/settings/privacy/delete-account` — paso 1: qué se borra (lista explícita: perfil,
   comidas, actividades, pesos, medidas, fotos, integraciones), qué es irreversible, y la
   oferta previa de **exportar los datos**.
2. Paso 2: reautenticación (contraseña o proveedor OAuth) y escribir la palabra `ELIMINAR`.
3. Confirmar → Edge Function `delete-account`:
   a. Marca `profiles.deletion_requested_at = now()`, cierra todas las sesiones.
   b. Revoca y borra las integraciones de salud.
   c. Encola un job que a los 7 días borra `auth.users` (cascada) y los objetos de Storage
      del usuario.
   d. Durante la gracia, iniciar sesión muestra "Tu cuenta se va a eliminar el DD/MM.
      ¿Querés cancelar la eliminación?".
4. Al confirmarse, correo de aviso y cierre de sesión.

**Validaciones:** reautenticación obligatoria (< 5 min de antigüedad); confirmación textual exacta.

**Errores**
| Situación | Código | Comportamiento |
| --- | --- | --- |
| Reautenticación fallida | `ERR_REAUTH_REQUIRED` | "No pudimos verificar tu identidad. Probá de nuevo." |
| Offline | `ERR_OFFLINE` | La operación **no** se encola: requiere conexión. Mensaje explícito. |
| Falla del job de borrado | — | Alerta interna (Sentry); se reintenta hasta 5 veces y luego escala a soporte |

**Resultado final:** sesión cerrada, datos programados para borrado definitivo.

**Estado persistido:** `profiles.deletion_requested_at`, `deletion_jobs`, y tras el plazo,
ausencia total de datos del usuario.
