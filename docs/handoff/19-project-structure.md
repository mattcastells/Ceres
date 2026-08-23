# 19 — Project Structure

Arquitectura en tres capas — **presentación / dominio / datos** — con dependencias que
apuntan siempre hacia adentro: la presentación conoce al dominio, el dominio no conoce a
nadie, los datos implementan las interfaces del dominio.

```
presentation  ──►  domain  ◄──  data
```

Reglas duras:

- `domain/` **no importa** Flutter/React Native, ni Supabase, ni HTTP, ni SQLite.
- `presentation/` **no importa** nada de `data/`: solo interfaces de `domain/`.
- Las fórmulas viven en `domain/calculations/`, son funciones puras y se testean solas.
- Un lint de capas (`import_lint` / `eslint-plugin-boundaries`) falla el build si se viola.

---

## 1. Flutter

```
ceres/
├─ lib/
│  ├─ main.dart
│  ├─ app.dart                          MaterialApp, tema, router, providers raíz
│  ├─ bootstrap.dart                    init de Supabase, Sentry, base local, flags
│  │
│  ├─ core/
│  │  ├─ theme/
│  │  │  ├─ tokens.dart                 GENERADO desde design-tokens.json — no editar
│  │  │  ├─ app_theme.dart              ThemeData claro y oscuro
│  │  │  └─ text_styles.dart
│  │  ├─ router/
│  │  │  ├─ app_router.dart             go_router con todas las rutas de la IA
│  │  │  └─ routes.dart                 constantes de ruta tipadas
│  │  ├─ l10n/                          arb + generados
│  │  ├─ error/
│  │  │  ├─ app_error.dart              ApiErrorCode, AppError, CalculationError
│  │  │  └─ error_mapper.dart           Postgres/HTTP → AppError
│  │  ├─ result.dart                    Result<T> (ok | error)
│  │  ├─ analytics/
│  │  ├─ permissions/
│  │  ├─ connectivity/
│  │  └─ utils/                         fechas, formatos, conversión de unidades
│  │
│  ├─ domain/
│  │  ├─ models/                        UserProfile, Goal, Meal, Activity, …
│  │  ├─ enums/
│  │  ├─ calculations/                  ★ funciones puras, 100 % de cobertura
│  │  │  ├─ bmr.dart
│  │  │  ├─ tdee.dart
│  │  │  ├─ calorie_target.dart
│  │  │  ├─ macros.dart
│  │  │  ├─ met_calories.dart
│  │  │  ├─ exercise_credit.dart
│  │  │  ├─ daily_balance.dart
│  │  │  ├─ pace_met.dart
│  │  │  ├─ duplicate_score.dart
│  │  │  ├─ moving_average.dart
│  │  │  └─ adherence.dart
│  │  ├─ repositories/                  interfaces (abstract class)
│  │  │  ├─ profile_repository.dart
│  │  │  ├─ meal_repository.dart
│  │  │  ├─ activity_repository.dart
│  │  │  ├─ food_repository.dart
│  │  │  ├─ health_repository.dart
│  │  │  └─ summary_repository.dart
│  │  ├─ services/                      interfaces de servicio (ver 10-types)
│  │  └─ usecases/                      un caso de uso = una intención del usuario
│  │     ├─ complete_onboarding.dart
│  │     ├─ create_meal.dart
│  │     ├─ analyze_meal_photo.dart
│  │     ├─ create_activity.dart
│  │     ├─ override_activity_calories.dart
│  │     ├─ change_exercise_credit.dart
│  │     ├─ sync_health_provider.dart
│  │     ├─ resolve_duplicate_activity.dart
│  │     ├─ log_weight.dart
│  │     └─ get_daily_summary.dart
│  │
│  ├─ data/
│  │  ├─ local/
│  │  │  ├─ database.dart               Drift
│  │  │  ├─ tables/                     espejo del esquema Postgres
│  │  │  ├─ daos/
│  │  │  ├─ migrations/
│  │  │  └─ sync_queue.dart
│  │  ├─ remote/
│  │  │  ├─ supabase_client.dart
│  │  │  ├─ dto/                        DTOs + fromJson/toJson
│  │  │  ├─ api/                        un archivo por superficie de API
│  │  │  └─ edge_functions/
│  │  ├─ native/
│  │  │  └─ health_connect_adapter.dart   (única integración de salud, D-21)
│  │  ├─ repositories/                  implementaciones (local-first + sync)
│  │  ├─ services/                      implementaciones de servicio
│  │  └─ mock/                          Fake* con datos simulados realistas
│  │
│  └─ presentation/
│     ├─ shell/                         tab bar, FAB, scaffold autenticado
│     ├─ components/                    la biblioteca de 05-component-library.md
│     │  ├─ system/                     Button, TextField, Card, Tag, Dialog, …
│     │  ├─ activity/                   ActivitySummaryCard, ExerciseCaloriesEstimate, …
│     │  ├─ food/
│     │  ├─ charts/
│     │  └─ feedback/                   EmptyState, ErrorState, Skeleton, OfflineBanner
│     └─ screens/
│        ├─ auth/                       {screen}.dart + {screen}_controller.dart
│        ├─ onboarding/
│        ├─ home/
│        ├─ meal/
│        ├─ food/
│        ├─ photo/
│        ├─ activity/
│        ├─ weight/
│        ├─ history/
│        ├─ progress/
│        ├─ profile/
│        └─ settings/
│
├─ assets/
│  ├─ icons/                            Phosphor (subset usado)
│  ├─ images/
│  └─ mock/                             usda_search.json, off_barcode.json, seed.json
│
├─ test/
│  ├─ domain/                           unitarios de cálculo (los 20 casos + generados)
│  ├─ data/
│  ├─ presentation/                     widget tests
│  ├─ golden/                           48 goldens
│  └─ fixtures/
│     ├─ calculation_cases.json         compartido con la implementación RN
│     └─ meal-photos/                   40 fotos de referencia
├─ integration_test/
├─ supabase/
│  ├─ migrations/
│  ├─ functions/
│  ├─ tests/                            pgTAP (RLS)
│  └─ seed.sql
├─ tool/
│  ├─ gen_tokens.dart                   design-tokens.json → tokens.dart
│  └─ gen_sqlite_schema.dart            migraciones → esquema local
├─ docs/handoff/                        esta documentación
├─ analysis_options.yaml                incluye las reglas de capas y de tokens
└─ pubspec.yaml
```

**Dependencias Flutter recomendadas:** `flutter_riverpod`, `go_router`, `drift`,
`supabase_flutter`, `freezed` + `json_serializable`, `intl`, `fl_chart`,
`phosphor_flutter`, `image_picker`, `camera`, `flutter_secure_storage`,
`connectivity_plus`, `health` (o adaptadores propios), `sentry_flutter`, `posthog_flutter`,
`mocktail`, `golden_toolkit`, `patrol`.

**Convención de pantalla:** cada carpeta de `screens/` contiene `x_screen.dart` (solo UI),
`x_controller.dart` (estado, Riverpod `Notifier`) y `x_state.dart` (freezed). El controlador
llama casos de uso, nunca repositorios directamente.

---

## 2. React Native (alternativa)

```
ceres/
├─ src/
│  ├─ app/                              expo-router: layouts y rutas espejo de la IA
│  │  ├─ (auth)/                        sign-in, sign-up, forgot-password
│  │  ├─ (onboarding)/[step].tsx
│  │  ├─ (tabs)/                        home, history, progress, profile + _layout
│  │  ├─ meal/                          new, [id], photo/{capture,analyzing,review}
│  │  ├─ food/                          search, [id], new, scan
│  │  ├─ activity/                      new, search, [id], add
│  │  ├─ settings/
│  │  └─ _layout.tsx
│  │
│  ├─ theme/
│  │  ├─ tokens.ts                      GENERADO — no editar
│  │  ├─ theme.ts
│  │  └─ ThemeProvider.tsx
│  │
│  ├─ domain/
│  │  ├─ models/                        tipos de 10-types-and-interfaces.ts
│  │  ├─ calculations/                  ★ mismas funciones puras, mismos fixtures
│  │  ├─ repositories/                  interfaces
│  │  ├─ services/
│  │  └─ usecases/
│  │
│  ├─ data/
│  │  ├─ local/                         WatermelonDB / expo-sqlite, DAOs, syncQueue
│  │  ├─ remote/                        supabaseClient, dto, api, edgeFunctions
│  │  ├─ native/                        healthConnect.ts
│  │  ├─ repositories/
│  │  └─ mock/
│  │
│  ├─ components/
│  │  ├─ system/  activity/  food/  charts/  feedback/
│  │
│  ├─ hooks/                            useDailySummary, useActivityForm, useSyncStatus
│  ├─ store/                            Zustand: session, preferences, connectivity
│  ├─ query/                            TanStack Query: claves e invalidaciones
│  ├─ i18n/
│  └─ utils/
│
├─ assets/
├─ __tests__/                           unit, components, integration
├─ e2e/                                 Detox
├─ supabase/                            idéntico al de Flutter
├─ scripts/gen-tokens.ts
└─ package.json
```

**Dependencias RN recomendadas:** `expo`, `expo-router`, `zustand`,
`@tanstack/react-query`, `@supabase/supabase-js`, `@nozbe/watermelondb` o `expo-sqlite`,
`react-native-svg` + `victory-native`, `phosphor-react-native`, `expo-camera`,
`expo-image-manipulator`, `expo-secure-store`, `@react-native-community/netinfo`,
`react-native-health` + `react-native-health-connect`, `@sentry/react-native`,
`posthog-react-native`, `jest`, `@testing-library/react-native`, `detox`, `msw`.

---

## 3. Separación de responsabilidades

| Capa | Contiene | No contiene |
| --- | --- | --- |
| **Presentación** | Widgets/componentes, controladores de pantalla, formateo para mostrar | Reglas de negocio, fórmulas, SQL, HTTP |
| **Dominio** | Modelos, enums, cálculos, casos de uso, interfaces | Framework de UI, cliente HTTP, ORM |
| **Datos** | Repositorios, DAOs, DTOs, clientes de API, adaptadores nativos, mocks | Decisiones de negocio |
| **Servicios** | Contratos de `10-types-and-interfaces.ts`; implementación en datos | — |
| **Modelos** | Inmutables, sin lógica de persistencia | Métodos que llamen a la red |
| **Repositorios** | Local-first: leen de SQLite, escriben local + encolan | Formateo para la UI |
| **Casos de uso** | Una intención del usuario, orquestan repos + cálculos + analítica | Estado de UI |
| **Componentes** | Presentación pura por props | Acceso a repositorios |
| **Utilidades** | Fechas, unidades, formatos, validadores | Estado global |
| **Tests** | Espejo de la estructura de `lib/` / `src/` | — |
| **Configuración** | Flavors/entornos, flags, variables públicas | Secretos |

## 4. Convenciones de nombres

| Elemento | Convención | Ejemplo |
| --- | --- | --- |
| Archivo Dart | `snake_case.dart` | `exercise_credit.dart` |
| Archivo TS | `camelCase.ts` / `PascalCase.tsx` | `exerciseCredit.ts`, `ActivityCard.tsx` |
| Clase / componente | `PascalCase` | `ActivitySummaryCard` |
| Caso de uso | verbo + sustantivo | `CreateActivity`, `SyncHealthProvider` |
| Tabla / columna | `snake_case` plural / singular | `activities.estimated_calories` |
| Evento analítico | `snake_case` en pasado | `activity_created` |
| Ruta | kebab en la URL, constante en código | `/settings/exercise-credit` → `Routes.exerciseCredit` |
| Test | `<unidad>_test.dart` / `<unidad>.test.ts` | `met_calories_test.dart` |

## 5. Entornos (flavors)

`dev` · `staging` · `prod` · `mock`. Cada uno con su `APP_ENVIRONMENT`, su proyecto
Supabase (salvo `mock`, que no usa red), su DSN de Sentry y su clave de analítica.
`mock` corre la app entera contra `data/mock/` con datos simulados realistas — es el modo en
el que se desarrolla la UI y en el que corren los tests de widget.
