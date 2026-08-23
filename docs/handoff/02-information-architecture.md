# 02 — Information Architecture

## 1. Mapa de navegación

```
App
├─ Unauthenticated stack                     (sin sesión)
│  ├─ /splash
│  ├─ /welcome
│  ├─ /auth/sign-in
│  ├─ /auth/sign-up
│  ├─ /auth/forgot-password
│  └─ /auth/check-email
│
├─ Onboarding stack                          (sesión creada, profile_completed = false)
│  ├─ /onboarding/goal            paso 1 de 6 — objetivo (bajar / mantener / subir)
│  ├─ /onboarding/body            paso 2 de 6 — sexo, nacimiento, altura, peso
│  ├─ /onboarding/activity-level  paso 3 de 6 — nivel de actividad base
│  ├─ /onboarding/target          paso 4 de 6 — ritmo y objetivo calórico (calculado o manual)
│  ├─ /onboarding/exercise-credit paso 5 de 6 — crédito de ejercicio
│  └─ /onboarding/summary         paso 6 de 6 — resumen y confirmación
│
└─ Authenticated shell (bottom tab bar, 4 tabs + FAB central)
   ├─ tab 1  /home                Inicio
   ├─ tab 2  /history             Historial
   ├─ FAB    → sheet /add         Agregar
   ├─ tab 3  /progress            Progreso
   └─ tab 4  /profile             Perfil
```

### Jerarquía por tab

**Tab 1 — Inicio (`/home`)**
```
/home
├─ /home/daily-breakdown              (sheet)   desglose del cálculo del día
├─ /meal/:mealId                                detalle de comida
├─ /activity/:activityId                        detalle de actividad
├─ /home/date-picker                  (sheet)   cambiar día visible
└─ /home/rest-day                     (sheet)   marcar descanso planificado
```

**Tab 2 — Historial (`/history`)**
```
/history                                        lista de días
├─ /history/filters                   (sheet)   filtros
├─ /history/:date                               detalle de un día
│  ├─ /meal/:mealId
│  └─ /activity/:activityId
└─ /history/export                    (sheet)   exportar datos (CSV/JSON)
```

**Tab 3 — Progreso (`/progress`)**
```
/progress
├─ /progress/weight                             gráfico de peso ampliado
├─ /progress/calories                           gráfico de calorías ampliado
├─ /progress/activity                           sección de actividad
│  ├─ /progress/activity/chart                  minutos y kcal por día
│  └─ /progress/activity/categories             distribución por categoría
├─ /progress/measurements                       medidas corporales
└─ /progress/goals                              objetivos de actividad
   └─ /progress/goals/edit            (sheet)   crear / editar objetivo
```

**Tab 4 — Perfil (`/profile`)**
```
/profile
├─ /profile/body                                perfil corporal
├─ /profile/target                              objetivo calórico y macros
├─ /settings
│  ├─ /settings/exercise-credit                 crédito de ejercicio
│  ├─ /settings/units                           unidades (métrico / imperial)
│  ├─ /settings/appearance                      tema claro / oscuro / sistema
│  ├─ /settings/notifications
│  ├─ /settings/integrations                    lista de integraciones de salud
│  │  └─ /settings/integrations/:provider       detalle, permisos, desconectar, borrar datos
│  ├─ /settings/privacy                         exportar datos, eliminar cuenta
│  │  └─ /settings/privacy/delete-account       confirmación en 2 pasos
│  └─ /settings/about
├─ /profile/foods                               mis alimentos
├─ /profile/activities                          mis actividades personalizadas
├─ /profile/templates                           plantillas de ejercicio
└─ /profile/favorites                           favoritos (alimentos, comidas, actividades)
```

### Flujos modales (se abren sobre cualquier tab)

```
/add                                  (sheet)   menú principal de agregar
├─ Agregar comida        → /meal/new?slot=:slot
├─ Sacar foto            → /meal/photo/capture
├─ Escanear alimento     → /food/scan
├─ Agregar ejercicio     → /activity/add            (sheet secundario)
├─ Registrar peso        → /weight/new              (sheet)
└─ Registrar medida      → /measurement/new         (sheet)

/meal/new
├─ /food/search?target=meal&mealId=:id
│  └─ /food/:foodId?target=meal&mealId=:id          detalle + porción
├─ /food/new                                        crear alimento propio
└─ /meal/:mealId/edit

/meal/photo/capture   → /meal/photo/analyzing → /meal/photo/review → /meal/:mealId

/activity/add                         (sheet)   submenú de ejercicio
├─ Buscar actividad          → /activity/search
├─ Actividad reciente        → /activity/recent
├─ Actividad favorita        → /activity/favorites
├─ Crear actividad manual    → /activity/new?mode=custom
├─ Importar desde dispositivo→ /settings/integrations
├─ Entrenamiento de fuerza   → /activity/new?mode=strength
├─ Caminata o carrera        → /activity/new?mode=walk_run
├─ Actividad por duración    → /activity/new?mode=duration
└─ Actividad por distancia   → /activity/new?mode=distance

/activity/new  → (guardar) → /home  |  toast con "Ver detalle" → /activity/:id
/activity/:activityId
├─ /activity/:activityId/edit
└─ /activity/duplicate-review         (dialog)  resolución de duplicado
```

## 2. Tabla de rutas

| Ruta | Pantalla | Presentación | Auth | Parámetros |
| --- | --- | --- | --- | --- |
| `/splash` | Splash | full | no | — |
| `/welcome` | Bienvenida | full | no | — |
| `/auth/sign-in` | Iniciar sesión | full | no | `?email` |
| `/auth/sign-up` | Crear cuenta | full | no | — |
| `/auth/forgot-password` | Recuperar contraseña | full | no | — |
| `/auth/check-email` | Revisá tu correo | full | no | `?email`, `?intent=signup\|reset` |
| `/onboarding/:step` | Onboarding | full, wizard | sí | `step ∈ goal\|body\|activity-level\|target\|exercise-credit\|summary` |
| `/home` | Inicio | tab | sí | `?date=YYYY-MM-DD` (default hoy) |
| `/home/daily-breakdown` | Desglose diario | sheet | sí | `?date` |
| `/history` | Historial | tab | sí | `?from`, `?to`, `?filter` |
| `/history/:date` | Detalle del día | push | sí | `date=YYYY-MM-DD` |
| `/progress` | Progreso | tab | sí | `?range=7d\|30d\|90d\|365d` |
| `/progress/activity` | Progreso de actividad | push | sí | `?range` |
| `/progress/goals` | Objetivos de actividad | push | sí | — |
| `/profile` | Perfil | tab | sí | — |
| `/settings/**` | Configuración | push | sí | — |
| `/add` | Menú agregar | sheet | sí | — |
| `/meal/new` | Nueva comida | full modal | sí | `?slot=breakfast\|lunch\|dinner\|snack`, `?date` |
| `/meal/:mealId` | Detalle de comida | push | sí | — |
| `/meal/photo/capture` | Cámara | full modal | sí | `?slot`, `?date` |
| `/meal/photo/review` | Revisar análisis | full modal | sí | `?analysisId` |
| `/food/search` | Buscar alimento | full modal | sí | `?target`, `?mealId`, `?q` |
| `/food/:foodId` | Detalle de alimento | push | sí | `?target`, `?mealId` |
| `/food/new` | Crear alimento | full modal | sí | — |
| `/food/scan` | Escanear código | full modal | sí | — |
| `/activity/add` | Menú ejercicio | sheet | sí | — |
| `/activity/new` | Registrar actividad | full modal | sí | `?mode`, `?activityTypeId`, `?templateId`, `?date` |
| `/activity/search` | Buscar actividad | full modal | sí | `?q` |
| `/activity/:activityId` | Detalle de actividad | push | sí | — |
| `/weight/new` | Registrar peso | sheet | sí | `?date` |
| `/measurement/new` | Registrar medida | sheet | sí | `?date` |

## 3. Modales y bottom sheets

| Id | Tipo | Se abre desde | Contenido | Cierre |
| --- | --- | --- | --- | --- |
| `sheet.add` | bottom sheet, alto medio | FAB | 6 acciones (comida, foto, escanear, ejercicio, peso, medida) | tap fuera, swipe, Esc |
| `sheet.activity_add` | bottom sheet, alto medio | `sheet.add` | 9 acciones de ejercicio | ídem |
| `sheet.daily_breakdown` | bottom sheet, alto ~60 % | tarjeta de resumen en Inicio | desglose del cálculo + link a configuración de crédito | ídem |
| `sheet.date_picker` | bottom sheet | encabezado de Inicio | calendario mensual con densidad de registro | ídem |
| `sheet.portion` | bottom sheet | detalle de alimento | selector de porción y cantidad | ídem |
| `sheet.weight` | bottom sheet | `sheet.add`, Progreso | input de peso + fecha + nota | ídem |
| `sheet.filters` | bottom sheet | Historial | filtros de historial | ídem |
| `sheet.goal_edit` | bottom sheet | Objetivos de actividad | tipo, valor, período | ídem |
| `sheet.rest_day` | bottom sheet | Inicio → menú de la sección Actividad | marcar/desmarcar descanso planificado | ídem |
| `dialog.duplicate_activity` | dialog modal, no descartable por tap fuera | sincronización / guardado | comparación lado a lado, 3 acciones | solo botones |
| `dialog.override_calories` | dialog modal | detalle o registro de actividad | input de kcal + motivo opcional | botones + Esc |
| `dialog.delete_confirm` | dialog modal | cualquier detalle | confirmar borrado | botones + Esc |
| `dialog.permission_rationale` | dialog modal | antes del permiso del SO | por qué se pide cada permiso | botones |
| `dialog.low_target_warning` | dialog modal | objetivo manual < mínimo (RN-12) | advertencia + confirmar | botones |

Regla: un bottom sheet nunca abre otro bottom sheet en el mismo nivel — `sheet.add`
**reemplaza** su contenido por `sheet.activity_add` con animación lateral, para que
"volver" regrese al menú anterior y no cierre todo.

## 4. Navegación autenticada

- Shell persistente con `BottomTabBar` de 4 destinos + FAB central elevado.
- Cada tab conserva su propio stack de navegación y su posición de scroll.
- El FAB no es un tab: abre `sheet.add` sobre el tab activo y devuelve al mismo tab.
- Al guardar una comida o actividad desde cualquier punto, la app vuelve al tab desde el
  que se inició el flujo y muestra un snackbar con acción "Ver".
- Botón de retroceso de Android: cierra sheet → sale del stack del tab → vuelve al tab
  Inicio → segunda pulsación sale de la app.
- Estado de sesión expirada: cualquier respuesta 401 dispara refresh de token; si falla,
  se limpia la sesión y se navega a `/auth/sign-in` conservando la cola offline.

## 5. Navegación sin autenticación

- `/splash` decide: sin sesión → `/welcome`; con sesión y `profile_completed = false` →
  `/onboarding/goal`; con sesión completa → `/home`.
- `/welcome` ofrece "Crear cuenta", "Ya tengo cuenta" y "Probar sin cuenta" (modo demo,
  ver **D-15**: crea un usuario local anónimo, todo se guarda en la base local y puede
  migrarse al registrarse).
- El onboarding no se puede saltear, pero cada paso puede omitirse con "Después" salvo
  `body` (necesario para calcular BMR) — si se omite, el objetivo debe ingresarse manual.

## 6. Deep links futuros

Esquema reservado: `ceres://` y `https://app.ceres.io/`.

| Deep link | Destino |
| --- | --- |
| `ceres://home?date=2026-07-27` | Inicio en una fecha |
| `ceres://add/meal?slot=lunch` | Nueva comida |
| `ceres://add/activity?type=walking` | Registro rápido de actividad |
| `ceres://activity/:id` | Detalle de actividad |
| `ceres://progress?range=30d` | Progreso |
| `ceres://settings/integrations/:provider` | Integración de salud |

El MVP registra el esquema y resuelve las rutas, pero no publica Universal Links /
App Links (requiere dominio verificado, ver `18-implementation-roadmap.md`, fase 15).
