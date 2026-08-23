# Ceres — Handoff de desarrollo

Este directorio es la **especificación completa** de Ceres: una aplicación móvil de
registro de alimentación, actividad física y peso corporal.

Está escrito para que un equipo — humano o una IA desarrolladora — pueda implementar la
aplicación **sin acceso a la conversación original** y sin reinterpretar decisiones de
producto. Todo lo ambiguo fue decidido, documentado y justificado en
[`decisions.md`](./decisions.md).

> ⚠️ **Esto es la especificación original, no el estado actual.**
>
> La app se construyó a partir de acá y desde entonces cambió: hay tablas que se
> agregaron, otras que se sacaron por no leerlas nadie, y decisiones que se
> revisaron con datos reales. Este directorio **no se actualiza** — es el punto
> de partida, y reescribirlo borraría el porqué de cada divergencia.
>
> Para lo que hay hoy:
>
> - **El esquema**: `supabase/migrations/`, en orden. Cada migración explica qué
>   cambia y por qué.
> - **El estado del producto**: [`../estado-de-la-app.md`](../estado-de-la-app.md)
>   y [`../../ESTADO.md`](../../ESTADO.md).
> - **Las decisiones posteriores**: los `docs/*.md` sueltos, como
>   [`../contexto-diario.md`](../contexto-diario.md).
>
> Lo único de este directorio que **sí** es fuente viva es
> [`design-tokens.json`](./design-tokens.json), de donde salen los tokens de la
> app y del panel.

## Cómo leer este handoff

| Orden | Documento | Para qué sirve |
| --- | --- | --- |
| 1 | [`01-product-requirements.md`](./01-product-requirements.md) | Qué es el producto, alcance del MVP, reglas de negocio |
| 2 | [`02-information-architecture.md`](./02-information-architecture.md) | Mapa de navegación y rutas |
| 3 | [`03-user-flows.md`](./03-user-flows.md) | Los 14 flujos obligatorios paso a paso |
| 4 | [`04-screen-specifications.md`](./04-screen-specifications.md) | Ficha de cada pantalla |
| 5 | [`05-component-library.md`](./05-component-library.md) | Componentes reutilizables y sus props |
| 6 | [`06-design-tokens.md`](./06-design-tokens.md) | Tokens (+ `design-tokens.json`, `design-tokens.ts`) |
| 7 | [`07-data-model.md`](./07-data-model.md) | Tablas, columnas, índices, ERD |
| 8 | [`08-supabase-plan.md`](./08-supabase-plan.md) | Migraciones, RLS, buckets, Edge Functions |
| 9 | [`09-api-contracts.md`](./09-api-contracts.md) | Contratos de cada endpoint / función |
| 10 | [`10-types-and-interfaces.ts`](./10-types-and-interfaces.ts) | Contrato de tipos de referencia |
| 11 | [`11-calculation-rules.md`](./11-calculation-rules.md) | Todas las fórmulas, con ejemplos y tests |
| 12 | [`12-external-integrations.md`](./12-external-integrations.md) | Gemini, USDA, OFF, Supabase, Health Connect, Health Connect |
| 13 | [`13-state-management.md`](./13-state-management.md) | Estado, cache, offline, conflictos |
| 14 | [`14-analytics-events.md`](./14-analytics-events.md) | Eventos analíticos y su payload |
| 15 | [`15-accessibility.md`](./15-accessibility.md) | Requisitos de accesibilidad |
| 16 | [`16-test-plan.md`](./16-test-plan.md) | Plan de testing por capa |
| 17 | [`17-acceptance-criteria.md`](./17-acceptance-criteria.md) | Given / When / Then por funcionalidad |
| 18 | [`18-implementation-roadmap.md`](./18-implementation-roadmap.md) | 15 fases con entregables y DoD |
| 19 | [`19-project-structure.md`](./19-project-structure.md) | Estructura de carpetas Flutter y React Native |
| 20 | [`20-environment-variables.md`](./20-environment-variables.md) | Variables de entorno y dónde vive cada una |
| 21 | [`21-motion-and-loading.md`](./21-motion-and-loading.md) | **Movimiento, spinners, skeletons y entrada de gráficos** — qué se anima, cuánto dura y qué se muestra mientras se espera |
| 22 | [`22-widget-redesign-brief.md`](./22-widget-redesign-brief.md) | **Brief para rediseñar el widget de la pantalla de inicio** — va en la dirección contraria a los demás: es un pedido *hacia* diseño, con los datos disponibles y los límites duros de RemoteViews |
| 23 | [`23-widget-redesign-implementacion.md`](./23-widget-redesign-implementacion.md) | **La respuesta al 22**: las cuatro formas del widget con sus cajas en dp, el orden de prioridad de la información y por qué no hay anillo. Implementado en la 1.11.0, con dos números corregidos contra el teléfono (§ del propio documento y `CaloriesWidget.ONEUI_DP`) |

Anexos:

- [`decisions.md`](./decisions.md) — registro de decisiones (ADR corto), funcionalidades
  simuladas, elementos no implementados y **pasos exactos para empezar a desarrollar**.
- [`met-catalog.json`](./met-catalog.json) — catálogo de actividades y valores MET (seed de `activity_types`).
- [`gemini-output-schema.json`](./gemini-output-schema.json) — JSON Schema de salida del análisis de foto.
- [`design-tokens.json`](./design-tokens.json) / [`design-tokens.ts`](./design-tokens.ts) — tokens en formato código.

## Prototipo de referencia

`Ceres.dc.html` en la raíz del proyecto es un **prototipo navegable de alta fidelidad**
que muestra las pantallas principales con datos simulados. Es la fuente de verdad visual;
esta carpeta es la fuente de verdad funcional. Ante una discrepancia, gana la
documentación (y hay que corregir el prototipo).

## Convenciones del handoff

- **Idioma:** documentación y copy de la UI en español rioplatense (voseo). Identificadores
  de código, nombres de tablas, columnas, eventos y tipos en inglés `snake_case` /
  `camelCase` según corresponda.
- **Unidades canónicas de almacenamiento:** energía en `kcal` (entero), peso en `kg`
  (numeric(6,2)), distancia en `meters` (entero), duración en `minutes` (entero),
  longitud corporal en `cm`. La conversión a unidades imperiales es de presentación.
- **Fechas:** todo timestamp se guarda en UTC (`timestamptz`). El "día" del usuario se
  resuelve con `local_date` (`date`) calculada en el cliente con la zona horaria del perfil.
  Ver decisión **D-09**.
- **Identificadores:** `uuid v4` generado en el cliente para permitir escritura offline
  y sincronización idempotente.
- **Borrado:** soft delete (`deleted_at`) en todas las tablas de contenido del usuario.
- **Prohibido en implementación:** frases como "agregar lógica correspondiente" o
  "manejar errores". Cada pantalla lista sus errores concretos en
  `04-screen-specifications.md` y cada endpoint los suyos en `09-api-contracts.md`.
