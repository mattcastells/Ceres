# 04 — Screen Specifications

Formato de cada ficha:

> **Ruta · Objetivo · Información mostrada · Acciones · Componentes · Datos requeridos ·
> Estados · Errores · Validaciones · Navegación entrada/salida · Eventos · Accesibilidad**

Estados comunes a toda pantalla que lee datos (no se repiten en cada ficha salvo que haya
particularidad): `loading` (skeleton, nunca spinner de pantalla completa),
`ready`, `empty`, `error` (mensaje + reintento), `offline` (banner superior no bloqueante).

---

## S-01 · Splash

- **Ruta:** `/splash` · **Objetivo:** decidir el destino inicial sin parpadeos.
- **Muestra:** logotipo Ceres centrado sobre `--color-bg`.
- **Acciones:** ninguna.
- **Componentes:** `BrandMark`.
- **Datos:** sesión en almacenamiento seguro, `profiles.profile_completed`.
- **Estados:** `checking` (≤ 1500 ms; si excede, se navega igual con datos locales).
- **Errores:** si falla la lectura de sesión → `/welcome`.
- **Salida:** `/welcome` · `/onboarding/goal` · `/home`.
- **Accesibilidad:** `Semantics(label: 'Ceres, cargando')`, sin animación si
  `reduce motion` está activo.

## S-02 · Bienvenida

- **Ruta:** `/welcome` · **Objetivo:** explicar la propuesta en una pantalla y ofrecer entrada.
- **Muestra:** título "Comida y movimiento, en un solo número honesto", 3 bullets
  (registro rápido · el cálculo a la vista · vos decidís cuánto suma el ejercicio),
  imagen tratada con `.lighten`.
- **Acciones:** "Crear cuenta" → `/auth/sign-up` · "Ya tengo cuenta" → `/auth/sign-in` ·
  "Probar sin cuenta" → crea sesión demo local y va a `/onboarding/goal`.
- **Componentes:** `Button(primary|secondary|ghost)`, `Illustration`.
- **Eventos:** `app_opened` (una vez por sesión fría).
- **Accesibilidad:** los tres botones son foco alcanzable en orden; contraste ≥ 4,5:1.

## S-03 · Iniciar sesión / S-04 · Crear cuenta

- **Rutas:** `/auth/sign-in`, `/auth/sign-up`
- **Objetivo:** autenticar con el mínimo de fricción.
- **Muestra:** campo email, campo contraseña con toggle de visibilidad, enlace
  "Olvidé mi contraseña" (solo sign-in), checkbox de términos (solo sign-up).
- **Acciones:** submit; alternar entre ambas pantallas; volver.
- **Componentes:** `TextField`, `PasswordField`, `Checkbox`, `Button(primary, block)`,
  `InlineError`, `FormErrorSummary`.
- **Datos:** ninguno previo. Servicio: `AuthService.signIn/signUp`.
- **Estados:** `idle`, `validating`, `submitting` (botón con spinner, campos deshabilitados),
  `error`.
- **Errores:** `ERR_INVALID_CREDENTIALS` "El correo o la contraseña no coinciden." ·
  `ERR_EMAIL_TAKEN` · `ERR_WEAK_PASSWORD` · `ERR_RATE_LIMITED` · `ERR_OFFLINE`
  (ver F-01). El error general se muestra arriba del formulario, no en un toast.
- **Validaciones:** ver F-01.
- **Navegación:** entrada `/welcome`; salida `/onboarding/goal` o `/home`.
- **Eventos:** `sign_in_succeeded`, `sign_up_succeeded`, `auth_failed{reason}`.
- **Accesibilidad:** `autofillHints` de email/password; el error se anuncia por lector de
  pantalla (`liveRegion: assertive`); toque mínimo 48×48.

## S-05 · Onboarding (6 pasos)

- **Ruta:** `/onboarding/:step` · **Objetivo:** obtener lo mínimo para calcular un objetivo.
- **Muestra:** `StepIndicator` "Paso N de 6", título, contenido del paso, botones
  "Continuar" y "Atrás"; en pasos opcionales, "Después".
- **Contenido por paso:** ver F-02.
- **Componentes:** `StepIndicator`, `OptionCardList`, `SegmentedControl`, `NumberField`,
  `DateField`, `HeightInput`, `WeightInput`, `ActivityLevelSelector`, `RateSelector`,
  `ExerciseCreditSelector`, `CalculationBreakdown`.
- **Datos requeridos:** ninguno de servidor. Al terminar: `ProfileService.completeOnboarding`.
- **Estados:** por paso — `idle`, `invalid`, `submitting` (último paso).
- **Errores:** validaciones de F-02; escritura fallida → guardado local + cola.
- **Navegación:** wizard lineal; el gesto de retroceso vuelve un paso; en el paso 1 pide
  confirmación para salir ("Vas a perder lo que cargaste").
- **Eventos:** `onboarding_started`, `onboarding_step_completed{step}`,
  `onboarding_completed{goal_type, target_kcal, credit_pct, method}`.
- **Accesibilidad:** el foco se mueve al título de cada paso al avanzar; el indicador de
  paso se expone como `Semantics(value: 'paso 3 de 6')`.

---

## S-06 · Inicio  ★ pantalla principal

- **Ruta:** `/home?date=YYYY-MM-DD` · **Objetivo:** responder en 2 segundos "¿cómo voy hoy?"
  y dar acceso a registrar.

**Información mostrada (de arriba hacia abajo)**

1. **Cabecera:** selector de día (`‹ Hoy ›`, tap abre `sheet.date_picker`), avatar → Perfil.
2. **`DailySummaryCard`** — la tarjeta principal. Muestra, **siempre por separado**:
   - Anillo de progreso con las kcal restantes al centro.
   - `Objetivo base` 2.100
   - `Consumido` −1.640
   - `Actividad` 240 kcal registradas *(≈ estimado)*
   - `Ajuste aplicado` +120 *(50 % del ejercicio)* — se oculta si el crédito es 0 %
   - `Objetivo ajustado` 2.220
   - **`Te quedan` 580 kcal**
   - Enlace "¿Cómo se calcula?" → `sheet.daily_breakdown`.
   Si el crédito es 0 %: la fila "Ajuste aplicado" se reemplaza por el texto tenue
   "El ejercicio no suma a tu presupuesto · Cambiar", enlazando a `/settings/exercise-credit`.
3. **`MacroBar`** — proteínas / carbohidratos / grasas consumidos vs objetivo.
4. **Comidas** — 4 secciones (Desayuno, Almuerzo, Cena, Snacks). Cada una con sus
   `MealListItem` y un botón "+" que abre `/meal/new?slot=…`.
5. **Actividad** — sección con `ActivityListItem` por actividad del día y un pie
   "Total: 45 min · ≈ 240 kcal estimadas". Botón "+" → `sheet.activity_add`.
   Menú de la sección: "Marcar día de descanso" → `sheet.rest_day`.
6. **Peso** — fila compacta con el último peso y su variación, o CTA si no hay registro hoy.

**Acciones:** cambiar de día; abrir desglose; abrir detalle de comida/actividad; agregar
en cada sección; swipe en un ítem → Editar / Duplicar / Eliminar; long-press en actividad →
menú con "Marcar como favorita".

**Componentes:** `DailySummaryCard`, `CalorieRing`, `MacroBar`, `MealSection`,
`MealListItem`, `ActivitySummaryCard`, `ActivityListItem`, `WeightRow`, `SyncStatusBadge`,
`DataOriginBadge`, `EmptyState`, `Fab`, `BottomTabBar`.

**Datos requeridos:** `DailySummary` para `date` (`SummaryService.getDailySummary(date)`),
que agrega: `goals` vigente, `meals` + `meal_items`, `activities`, `weight_logs`,
`profiles.exercise_credit_percentage`, `rest_days`.

**Estados:**
- `loading`: skeleton de la tarjeta + 2 filas fantasma.
- `empty` (día sin registros): la tarjeta muestra el objetivo completo disponible y un
  `EmptyState` con "Registrá tu primera comida" y "Registrá una actividad".
- `partial`: hay comidas pero no actividad → la sección Actividad muestra un CTA de una línea.
- `offline`: banner "Sin conexión — se va a sincronizar solo"; los ítems pendientes llevan
  `SyncStatusBadge(pending)`.
- `rest_day`: la sección Actividad muestra "Descanso planificado" y no sugiere registrar.
- `future_date`: solo lectura, sin botones de agregar salvo planificación (fuera de MVP:
  deshabilitados con tooltip).

**Errores:** falla de `getDailySummary` → se sirve la copia local y banner "Puede que falten
datos recientes · Reintentar". Nunca pantalla en blanco si hay datos locales.

**Validaciones:** `date` debe ser válida y ≥ fecha de alta del usuario.

**Navegación entrada:** post-onboarding, tab 1, deep link, retorno tras guardar.
**Navegación salida:** todas las rutas del §1 de IA.

**Eventos:** `home_viewed{date_offset}`, `daily_breakdown_opened`, `date_changed{direction}`.

**Accesibilidad:** el anillo tiene `Semantics(label: 'Te quedan 580 calorías de 2.220')`;
las filas del desglose se leen como pares etiqueta-valor; el orden de foco es
cabecera → tarjeta → macros → comidas → actividad → peso → FAB → tabs; el color nunca es el
único portador de significado (dentro/fuera del objetivo lleva también texto).

---

## S-07 · Desglose diario (sheet)

- **Ruta:** `/home/daily-breakdown` · **Objetivo:** hacer auditable el número principal.
- **Muestra:** las fórmulas con los valores del día:
  `objetivo ajustado = objetivo base + calorías de ejercicio aplicadas` y
  `calorías restantes = objetivo ajustado − calorías consumidas`, cada término con su valor.
  Debajo, `caloríasEjercicioAplicadas = caloríasEjercicioEstimadas × 0,50` con los números
  reales. Al pie, "Calorías netas: 1.520" con la nota de RN-11 y una explicación de por qué
  las estimaciones de ejercicio son inciertas.
- **Acciones:** "Cambiar cuánto suma el ejercicio" → `/settings/exercise-credit`; cerrar.
- **Componentes:** `FormulaRow`, `ValueRow`, `InfoNote`, `Button(ghost)`.
- **Datos:** el mismo `DailySummary` ya cargado (no hay fetch adicional).
- **Accesibilidad:** las fórmulas se exponen como texto plano legible, no como imagen.

---

## S-08 · Menú Agregar (sheet)

- **Ruta:** `/add` · **Objetivo:** un solo punto de entrada para los 6 tipos de registro.
- **Muestra:** 6 filas con ícono Phosphor, etiqueta y subtítulo:
  Agregar comida · Sacar foto de una comida · Escanear alimento · Agregar ejercicio ·
  Registrar peso · Registrar medida corporal.
- **Acciones:** cada fila navega; cerrar.
- **Componentes:** `ActionSheet`, `ActionRow`.
- **Estados:** "Escanear alimento" aparece deshabilitado con nota "Necesita conexión" si no
  hay red; "Sacar foto" queda habilitado (se encola, F-05).
- **Eventos:** `add_menu_opened`, `add_menu_action{action}`.
- **Accesibilidad:** el sheet toma el foco al abrir, lo devuelve al FAB al cerrar; se cierra
  con Escape / gesto; `Semantics(container: true, label: 'Agregar registro')`.

## S-09 · Menú Ejercicio (sheet)

- **Ruta:** `/activity/add` · **Objetivo:** cubrir las 9 formas de agregar ejercicio.
- **Muestra:** Buscar actividad · Actividad reciente · Actividad favorita · Crear actividad
  manual · Importar desde un dispositivo · Entrenamiento de fuerza · Caminata o carrera ·
  Actividad por duración · Actividad por distancia. Las primeras tres muestran un preview
  (chips con las 3 más recientes / favoritas).
- **Acciones:** navegar; "Atrás" vuelve a `sheet.add`.
- **Componentes:** `ActionSheet`, `ActionRow`, `ActivityChipRow`.
- **Estados:** "Actividad reciente" / "favorita" se ocultan si no hay ninguna.
  "Importar" muestra el estado de la integración (conectada / no conectada).
- **Datos:** `recent_activities` (últimas 5), `activities.is_favorite`,
  `health_integrations.status`.

---

## S-10 · Registro rápido de actividad  ★

- **Ruta:** `/activity/new?mode=…` · **Objetivo:** guardar una actividad en menos de 12 s.
- **Muestra:**
  - **Principales:** `ActivityTypeSelector` (chips + "Ver todas"), `DurationInput`
    (presets · deslizador 5–240 min · campo libre `hh:mm` hasta 24:00, D-22),
    `ActivityIntensitySelector`, fecha y hora, `ExerciseCaloriesEstimate`.
  - **`ExerciseCaloriesEstimate`** es la pieza central: `≈ 184 kcal` en grande,
    debajo "Estimado con MET 3,5 · tu peso 100 kg · 30 min", y un enlace
    "Ingresar otro valor" que abre `dialog.override_calories`.
  - **Opcionales (acordeón "Más detalles"):** distancia, pasos, FC promedio, FC máxima,
    notas, foto.
  - Nota permanente al pie: *"Las calorías de ejercicio son una estimación."*
- **Acciones:** guardar; guardar y agregar otra; cancelar; marcar como favorita;
  guardar como plantilla.
- **Componentes:** `ActivityTypeSelector`, `ActivityIntensitySelector`, `DurationInput`,
  `DistanceInput`, `NumberField`, `DateTimeField`, `ExerciseCaloriesEstimate`,
  `Accordion`, `PhotoPicker`, `Button(primary, block)`.
- **Datos requeridos:** `activity_types` (catálogo local), peso actual (S-07 de PRD),
  `recent_activities`.
- **Recálculo:** cualquier cambio en tipo, duración, intensidad o peso dispara
  `ExerciseCalculationService.calculateCaloriesFromMet` con debounce de 120 ms. Si el
  usuario ya sobrescribió el valor, el recálculo **no** pisa su número: muestra
  "El cálculo daría ≈ 210 kcal · usar este valor".
- **Estados:** `idle`, `dirty`, `saving`, `saved`, `override_active`,
  `duplicate_warning` (solapamiento detectado).
- **Errores y validaciones:** ver F-08.
- **Navegación:** entrada `sheet.activity_add`, chip de repetir, plantilla, duplicar.
  Salida: origen + snackbar "Actividad guardada · Ver".
- **Eventos:** `activity_created`, `activity_calories_edited` (si hubo override).
- **Accesibilidad:** cada chip de tipo es un `ToggleButton` con estado seleccionado
  anunciado; `DurationInput` acepta entrada por teclado además de la rueda; el valor
  estimado se anuncia como "aproximadamente 184 calorías, estimado".

## S-11 · Buscar actividad

- **Ruta:** `/activity/search` · **Objetivo:** encontrar un tipo entre los 15 del catálogo
  y los personalizados.
- **Muestra:** campo de búsqueda; lista agrupada por categoría (Cardio · Fuerza ·
  Movilidad · Deportes · Otras); cada fila con ícono, nombre y MET moderado de referencia.
- **Acciones:** seleccionar → `/activity/new?activityTypeId=…`; "Crear actividad
  personalizada".
- **Estados:** `empty` de búsqueda → "No encontramos esa actividad" + crear personalizada.
- **Datos:** `activity_types` (seed de `met-catalog.json` + propias del usuario).

## S-12 · Entrenamiento de fuerza

- **Ruta:** `/activity/new?mode=strength` · **Objetivo:** registrar una sesión de fuerza
  simple sin cerrar la puerta al seguimiento detallado.
- **Muestra:** nombre del entrenamiento (con sugerencias: "Tren superior", "Piernas",
  "Full body"), duración, intensidad, kcal estimadas, notas.
  Aviso al pie: *"Series y repeticiones llegan en una próxima versión."*
- **Datos:** MET por intensidad de `strength_training` (3,5 / 5,0 / 6,0).
- **Modelo:** se guarda como `activities` con `activity_type.slug = 'strength_training'` y
  `custom_name` = el nombre del entrenamiento. Las tablas `strength_exercises` y
  `strength_sets` existen en el esquema y quedan vacías en el MVP.

## S-13 · Detalle de actividad

- **Ruta:** `/activity/:id` · **Objetivo:** ver todo lo registrado y poder corregirlo.
- **Muestra:** tipo + nombre, fecha y hora, duración, intensidad, distancia, pasos, FC,
  notas, foto; bloque de calorías con `≈ valor`, `estimation_method` legible
  ("Estimado por MET 3,5" / "Informado por Health Connect" / "Corregido por vos"),
  `DataOriginBadge`, `SyncStatusBadge`; si hubo override, el valor original y
  "Restaurar el valor calculado"; pie con "Aporta +120 kcal a tu objetivo de hoy (50 %)".
- **Acciones:** editar · duplicar (elige fecha) · eliminar (con deshacer 8 s) ·
  marcar favorita · guardar como plantilla · editar calorías.
- **Errores:** actividad borrada en otro dispositivo → "Este registro ya no existe" + volver.
- **Eventos:** `activity_viewed`, `activity_duplicated`, `activity_deleted`.

## S-14 · Diálogo de duplicado

- **Ruta:** `dialog.duplicate_activity` · **Objetivo:** que el usuario decida, sin que el
  sistema borre nada por su cuenta.
- **Muestra:** dos columnas comparadas (Manual vs Health Connect) con tipo, horario, duración,
  distancia y calorías; las diferencias resaltadas.
- **Acciones:** "Son la misma — quedate con la importada" · "Son la misma — quedate con la
  mía" · "Son distintas — guardá las dos" · "Decidir después" (deja `sync_status = 'needs_review'`).
- **Resultado:** la descartada pasa a `deleted_at` con `deletion_reason = 'duplicate_merge'`
  (recuperable durante 30 días); se registra el par en `duplicate_resolutions`.
- **Accesibilidad:** no se cierra por tap fuera; el foco arranca en la primera opción; la
  comparación se lee como tabla con encabezados.

---

## S-15 · Nueva comida

- **Ruta:** `/meal/new?slot=…&date=…` · **Objetivo:** componer una comida a partir de ítems.
- **Muestra:** selector de slot, hora, lista de ítems agregados con kcal y porción,
  totales en vivo (kcal + macros), botón "Agregar alimento".
- **Acciones:** agregar / editar / quitar ítem; cambiar porción; guardar; guardar como
  favorita; descartar (con confirmación si hay cambios).
- **Componentes:** `SlotSelector`, `MealItemRow`, `MealTotalsBar`, `Button(primary, block)`.
- **Estados:** `empty` (sin ítems → botón de guardar deshabilitado con motivo visible),
  `dirty`, `saving`.
- **Errores y validaciones:** F-03 / F-07.

## S-16 · Buscar alimento

- **Ruta:** `/food/search` · **Objetivo:** encontrar el alimento en ≤ 3 interacciones.
- **Muestra:** campo con foco automático; pestañas Recientes / Favoritos / Mis alimentos
  antes de escribir; resultados agrupados Tuyos / Marcas / Genéricos, cada fila con
  `FoodResultRow` (nombre, marca, porción de referencia, kcal, badge de origen).
- **Acciones:** buscar, filtrar por pestaña, seleccionar, crear alimento, escanear código.
- **Estados:** `idle` (recientes), `searching` (skeleton de 6 filas), `results`,
  `empty`, `offline` (solo local), `degraded` (proveedor caído, solo cache).
- **Errores:** ver F-04.
- **Eventos:** `food_searched`, `food_selected{source, position}`.
- **Accesibilidad:** los resultados se anuncian con `liveRegion: polite` al cambiar
  ("12 resultados"); cada fila expone kcal y porción en su etiqueta semántica.

## S-17 · Detalle de alimento + porción

- **Ruta:** `/food/:id` · **Muestra:** nombre, marca, origen del dato (USDA / Open Food
  Facts / tuyo), tabla nutricional por 100 g y por porción, selector de porción y cantidad,
  total resultante en vivo.
- **Acciones:** agregar a la comida; marcar favorito; editar (solo alimentos propios);
  reportar dato incorrecto (crea una copia editable propia).
- **Validaciones:** cantidad > 0 y ≤ 10000.

## S-18 · Cámara

- **Ruta:** `/meal/photo/capture` · **Muestra:** visor, guía de encuadre, botón de disparo,
  acceso a galería, linterna, ayuda ("Cómo sacar una buena foto").
- **Estados:** `permission_pending`, `permission_denied` (pantalla explicativa + abrir
  ajustes + elegir de galería), `ready`, `captured` (previsualización).
- **Permisos:** cámara (obligatorio para esta pantalla), galería (opcional).
- **Eventos:** `photo_capture_started`, `photo_captured{source: camera|gallery}`.

## S-19 · Analizando

- **Ruta:** `/meal/photo/analyzing` · **Muestra:** la foto atenuada, skeleton de ítems y
  texto rotativo honesto ("Buscando alimentos…" → "Estimando porciones…" → "Casi listo").
- **Acciones:** cancelar (aborta la petición; la foto queda guardada como borrador).
- **Estados:** `analyzing`, `retrying` (un reintento automático), `failed`.
- **Accesibilidad:** `liveRegion` anuncia el cambio de fase; sin animación con
  `reduce motion` (se muestra texto estático).

## S-20 · Revisar análisis  ★

- **Ruta:** `/meal/photo/review` · **Objetivo:** que ningún dato de IA se guarde sin pasar
  por el ojo del usuario.
- **Muestra:** foto, banner `AiEstimateBanner` ("Estimación de IA — revisá antes de
  guardar"), lista de `AiItemRow` con nombre, cantidad editable, unidad, kcal y
  `ConfidenceBadge`; total; selector de slot.
- **Acciones:** editar cantidad/unidad, reemplazar por un alimento del catálogo, eliminar
  ítem, agregar ítem, cambiar slot, guardar, descartar.
- **Estados:** `ready`, `low_confidence` (≥ 1 ítem < 0,5 → los campos afectados con borde
  de atención y el botón de guardar dice "Guardar igual"), `saving`.
- **Errores:** ver F-05 / F-06.
- **Eventos:** `ai_result_corrected`, `meal_created{method: 'ai_photo'}`.
- **Accesibilidad:** el badge de confianza incluye texto ("confianza baja"), no solo color.

---

## S-21 · Historial

- **Ruta:** `/history` · **Muestra:** lista de días agrupada por mes; cada `DayRow` con
  fecha, kcal consumidas, kcal de actividad, kcal aplicadas, minutos de ejercicio,
  cantidad de actividades, pasos si hay, e indicador neutral dentro/fuera.
- **Acciones:** filtrar, buscar por rango, abrir un día, exportar.
- **`sheet.filters` — contenido exacto:**
  1. **Qué mostrar** (segmentado, single): Todo · Solo comidas · Solo ejercicio.
  2. **Origen de la actividad** (chips, multi): Manuales · Importadas. Sin selección = ambas.
  3. **Tipo de actividad** (chips, multi): los tipos con registros en el rango, más "Todos".
  4. **Rango de fechas** (chips, single + personalizado): 7 días · 30 días · 90 días ·
     Personalizado (abre selector de dos fechas; máx. 366 días, `from ≤ to`).
  5. **Solo días fuera del objetivo** (switch, off por defecto).
  Pie fijo con dos acciones: **Limpiar** (vuelve al default y no cierra) y **Aplicar**
  (cierra y recarga la lista). El encabezado del sheet muestra el conteo en vivo:
  "18 días coinciden".
- **Estado de los filtros:** se persisten en preferencias locales y se muestran como chips
  removibles debajo del título de Historial. Un filtro activo cambia el ícono del botón a
  su variante `fill` con un punto de acento.
- **Estados:** `loading` (10 filas skeleton), `ready`, `empty` (sin datos en el rango),
  `filtered_empty`, `offline`.
- **Datos:** `HistoryService.getDays({from, to, filters})` — paginado de 30.
- **Eventos:** `history_viewed`, `history_filtered{filters}`.

## S-22 · Detalle del día

- **Ruta:** `/history/:date` · **Muestra:** la misma `DailySummaryCard` que Inicio (modo
  solo lectura editable), comidas por slot, actividades, peso, medidas, y el pie de cálculo
  con objetivo base, ajuste y balance final.
- **Acciones:** editar cualquier registro, agregar registros a esa fecha, marcar descanso.
- **Estados:** `past_day` (edición permitida), `today` (idéntico a Inicio).

## S-23 · Progreso

- **Ruta:** `/progress?range=…` · **Objetivo:** mostrar tendencia sin juicio de valor.
- **Muestra:** selector de rango (7 d · 30 d · 90 d · 1 año); `WeightChart` con puntos y
  media móvil de 7 días; `CaloriesChart` (barras de consumo con línea de objetivo);
  tarjetas de resumen (promedio diario, adherencia, variación de peso, tendencia semanal);
  bloque de actividad (ver S-24); acceso a medidas y objetivos.
- **Acciones:** cambiar rango, registrar peso, abrir cada gráfico ampliado.
- **Estados:** `insufficient_data` (< 3 puntos → "Necesitamos unos días más de registro
  para mostrar una tendencia"), `ready`.
- **Accesibilidad:** cada gráfico tiene una alternativa textual accesible con los valores
  clave y una tabla de datos desplegable (`15-accessibility.md` §8).

## S-24 · Progreso de actividad

- **Ruta:** `/progress/activity` · **Muestra:**
  - `ActivityHistoryChart`: minutos por día (barras) + kcal estimadas (línea), con
    promedio semanal y comparación con la semana anterior.
  - `ActivityCategoryChart`: distribución del tiempo entre Caminata, Carrera, Fuerza,
    Ciclismo, Deportes y Otras (barras horizontales apiladas, no torta — legibilidad).
  - `ActiveMinutesCard`, `StepsSummaryCard`, y tarjetas con: sesiones realizadas,
    promedio de duración, kcal estimadas, actividad más frecuente, mayor duración
    registrada, días con actividad.
  - **Consistencia**, con copy neutral: "Registraste actividad durante 4 de los últimos 7
    días." · "Esta semana acumulaste 130 minutos de actividad." · "Caminaste 25 minutos más
    que la semana anterior."
- **Prohibido:** mensajes culpabilizantes, rachas rotas, castigo por descanso (RN-14, RN-15).
- **Datos:** `ProgressService.getActivityProgress({range})`.
- **Estados:** `empty` ("Todavía no registraste actividad en este período").

## S-25 · Objetivos de actividad

- **Ruta:** `/progress/goals` · **Muestra:** lista de `ActivityGoalCard` (minutos activos
  por semana · sesiones por semana · pasos diarios · distancia semanal · entrenamientos de
  fuerza por semana · días activos por semana), cada uno con progreso del período y estado
  activado/desactivado.
- **Acciones:** crear, editar, activar/desactivar, eliminar objetivo.
- **Reglas:** RN-09 — nunca alteran el objetivo calórico ni bloquean nada; el progreso se
  muestra separado del bloque calórico.
- **Estados:** `empty` ("Los objetivos de actividad son opcionales. Podés usar Ceres sin
  configurar ninguno.").

## S-26 · Medidas corporales

- **Ruta:** `/progress/measurements` · **Muestra:** series de cintura, cadera, pecho, brazo,
  muslo, cuello y % de grasa opcional; gráfico por medida seleccionada.
- **Acciones:** registrar medida, editar, eliminar.
- **Validaciones:** 10–300 cm por medida; % de grasa 3–70.

---

## S-27 · Perfil

- **Ruta:** `/profile` · **Muestra:** nombre/avatar, resumen del objetivo vigente, accesos a
  perfil corporal, objetivo, mis alimentos, mis actividades, plantillas, favoritos,
  configuración; versión de la app.
- **Acciones:** navegar; cerrar sesión (con confirmación si hay cola offline pendiente:
  "Tenés 3 registros sin sincronizar. Si cerrás sesión se pierden.").

## S-28 · Crédito de ejercicio

- **Ruta:** `/settings/exercise-credit` · **Objetivo:** que el usuario controle cuánto suma
  el ejercicio, entendiendo por qué.
- **Muestra:** título "Sumar las calorías del ejercicio a mi presupuesto diario"; radios
  **No sumar (recomendado)** · Sumar el 50 % · Sumar el 75 % · Sumar el 100 % ·
  Porcentaje personalizado (slider 0–100); texto explicativo exacto:
  *"Las calorías quemadas durante el ejercicio suelen sobreestimarse. Podés decidir cuánto
  de ese gasto agregar a tu presupuesto diario."*; ejemplo en vivo con los datos de hoy
  ("Con 240 kcal de actividad, hoy sumarías +120 kcal"); toggle "Desactivar completamente
  el ajuste por ejercicio".
- **Acciones:** elegir opción; desactivar; guardar (autoguardado con debounce 600 ms).
- **Efecto:** F-13 (aplica desde hoy en adelante; el historial no se reescribe).
- **Componentes:** `ExerciseCreditSelector`, `RadioGroup`, `Slider`, `Switch`, `InfoNote`,
  `LivePreviewRow`.
- **Eventos:** `exercise_credit_changed{from, to, disabled}`.

## S-29 · Integraciones de salud

- **Ruta:** `/settings/integrations` · **Muestra:** `HealthIntegrationCard` por proveedor
  (Health Connect (Android)) con estado, última sincronización,
  permisos concedidos y cantidad de registros importados.
- **Acciones:** conectar, sincronizar ahora, ver permisos, desconectar, borrar los datos
  importados (con confirmación que aclara que se borran solo los importados).
- **Estados:** `not_connected`, `connecting`, `connected`, `syncing`,
  `permission_denied`, `provider_unavailable`, `error{last_error}`.
- **Reglas:** solo se piden los permisos necesarios; cada uno se explica antes de pedirlo;
  la app funciona sin ninguna integración (RN-10).
- **Eventos:** `integration_connected`, `integration_disconnected`,
  `integration_sync_started`, `integration_sync_failed`.

## S-30 · Privacidad y datos

- **Ruta:** `/settings/privacy` · **Muestra:** exportar mis datos (JSON + CSV por correo),
  qué datos se guardan y dónde, política de privacidad, eliminar cuenta.
- **Acciones:** exportar (Edge Function `export-user-data`), eliminar cuenta (F-14).
- **Estados:** `export_pending` ("Te vamos a enviar el archivo por correo, puede tardar
  unos minutos").

## S-31 · Apariencia

- **Ruta:** `/settings/appearance` · **Muestra:** Claro / Oscuro / Según el sistema, y
  previsualización en vivo de la tarjeta principal.
- **Nota de implementación:** el tema oscuro es el canónico del sistema de diseño
  (Nocturne); el claro se deriva invirtiendo la rampa neutral y ajustando el acento a
  `--color-accent-600` para conservar contraste ≥ 4,5:1 en texto. Ver `06-design-tokens.md` §7.

---

## Matriz pantalla × estado

| Pantalla | loading | empty | error | offline | particular |
| --- | --- | --- | --- | --- | --- |
| Inicio | skeleton tarjeta + 2 filas | CTA doble | banner + datos locales | banner + badges | `rest_day`, `future_date` |
| Buscar alimento | 6 filas skeleton | crear/foto | banner reintentar | solo local | `degraded` |
| Revisar análisis | — | — | reintento + manual | encolado | `low_confidence` |
| Registro de actividad | — | — | inline | encolado | `override_active`, `duplicate_warning` |
| Historial | 10 filas | sin registros | reintentar | datos guardados | `filtered_empty` |
| Progreso | skeleton gráficos | sin datos | reintentar | datos guardados | `insufficient_data` |
| Integraciones | — | sin proveedores | error de sync | deshabilitado | `permission_denied` |


---

## S-32 · Perfil corporal

- **Ruta:** `/profile/body` · **Objetivo:** mantener al día los datos que alimentan BMR, TDEE
  y las estimaciones MET.
- **Muestra:** sexo biológico (con nota "se usa solo para la fórmula de metabolismo basal"),
  fecha de nacimiento y edad derivada, altura, peso actual (link al último registro), nivel
  de actividad con su descripción, e IMC calculado con un enlace "Qué significa" —
  **sin categoría moralizante en pantalla** (RN-14, `11-calculation-rules.md` §14).
- **Acciones:** editar cada campo (autoguardado con debounce de 600 ms), ir a registrar peso.
- **Componentes:** `SegmentedControl`, `DateField`, `HeightInput`, `WeightInput`,
  `ActivityLevelSelector`, `StatCard`, `InfoNote`.
- **Efecto:** cualquier cambio recalcula BMR y TDEE en vivo y muestra un aviso
  "Tu objetivo sugerido pasaría de 2.100 a 2.040 kcal · Actualizar objetivo", que **no** se
  aplica solo: el objetivo vigente solo cambia desde `/profile/target` (D-05).
- **Validaciones:** edad 13–100, altura 90–250 cm, peso 25–400 kg.
- **Estados:** `ready`, `saving`, `invalid`, `recalc_available`.
- **Eventos:** `profile_body_updated{field}`.

## S-33 · Objetivo y macros

- **Ruta:** `/profile/target` · **Objetivo:** que el usuario entienda y controle su objetivo.
- **Muestra:** el objetivo vigente y desde cuándo rige; el desglose del cálculo
  (BMR → × factor → TDEE → − déficit → objetivo) como filas legibles; selector de tipo de
  objetivo (bajar / mantener / subir); selector de ritmo (0,25 / 0,5 / 0,75 / 1 kg por
  semana, tope RN-13) con la fecha estimada de llegada al peso objetivo; alternativa
  "Ingresar manualmente"; tarjetas de macros con sus gramos y su porcentaje, editables.
- **Acciones:** cambiar tipo, ritmo o valor; volver al cálculo automático; guardar.
- **Componentes:** `CalculationBreakdown`, `RateSelector`, `NumberField`, `MacroEditor`,
  `Button`.
- **Efecto:** guardar cierra la fila vigente de `goals` e inserta una nueva desde hoy; el
  historial conserva los objetivos viejos (F-13, AC-16).
- **Validaciones:** 800–6000 kcal; por debajo del mínimo de RN-12 se pide confirmación en
  `dialog.low_target_warning`; los macros deben sumar el objetivo ±2 %.
- **Estados:** `ready`, `dirty`, `clamped`, `saving`.
- **Eventos:** `goal_updated`.

## S-34 · Mis alimentos, plantillas y favoritos

- **Rutas:** `/profile/foods`, `/profile/activities`, `/profile/templates`,
  `/profile/favorites` — una sola pantalla con cuatro pestañas.
- **Muestra:** listas de alimentos propios (nombre, marca, kcal por porción), actividades
  personalizadas (nombre, categoría, MET por intensidad), plantillas de ejercicio
  (`ExerciseTemplateCard`) y favoritos mezclados con su tipo.
- **Acciones:** crear, editar, duplicar, eliminar (soft delete con deshacer), usar una
  plantilla (crea el borrador de actividad precargado), quitar de favoritos.
- **Estados:** `empty` por pestaña, con un texto que explica cómo se llena
  ("Los alimentos que crees aparecen acá"), `loading`, `error`.
- **Validaciones:** las de `/food/new` y las del tipo de actividad personalizada
  (MET 0,9–23,0 por intensidad).
- **Eventos:** `custom_food_created`, `custom_activity_created`, `template_used`.

## S-35 · Privacidad y datos (detalle)

- **Ruta:** `/settings/privacy` · **Muestra:** qué datos se guardan y dónde (lista concreta,
  no genérica), con quién se comparten (Supabase, Gemini para las fotos, Sentry para
  errores), toggle "Compartir estadísticas de uso anónimas", exportar mis datos, política de
  privacidad, y la zona de eliminación de cuenta separada visualmente.
- **Acciones:** exportar (`export-user-data`, 202 + correo), abrir la política, eliminar
  cuenta (F-14), desactivar analítica.
- **Nota de plataforma:** esta ruta debe abrir **sin sesión iniciada** — Health Connect exige
  poder llegar a la política de privacidad desde su diálogo de permisos.
