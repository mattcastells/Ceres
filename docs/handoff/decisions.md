# Decisiones, simulaciones y próximos pasos

Este documento cierra el handoff: qué se decidió y por qué, qué está simulado, qué no
existe todavía, y los pasos exactos para empezar a desarrollar.

---

## 1. Registro de decisiones

Formato: **decisión · motivo · consecuencia**. Todas son consistentes en todo el producto;
cambiar una implica actualizar los documentos que la citan.

### D-01 · Stack: Flutter como implementación primaria, React Native documentada como alternativa
**Motivo:** un solo lenguaje para UI y lógica, rendimiento consistente en listas y gráficos,
y `drift` para la base local offline. El handoff mantiene los contratos en TypeScript
(`10-types-and-interfaces.ts`) para que la alternativa sea real y no teórica.
**Consecuencia:** `19-project-structure.md` describe ambas estructuras; los fixtures de
cálculo (`calculation_cases.json`) son compartidos para que ambas implementaciones sean
verificablemente equivalentes.

### D-02 · El crédito de ejercicio por defecto es **0 %**
**Motivo:** el brief pide "una opción conservadora". Además, el factor de nivel de actividad
del TDEE ya incorpora el ejercicio habitual: sumar el ejercicio registrado encima es doble
conteo. Y las estimaciones de gasto se sobreestiman sistemáticamente.
**Consecuencia:** en Inicio, si el crédito es 0 %, la fila "Ajuste aplicado" no se muestra y
en su lugar aparece "El ejercicio no suma a tu presupuesto · Cambiar". El onboarding
explica la opción y permite elegir otra desde el primer día. RN-02, AC-04.

### D-03 · BMR con Mifflin-St Jeor
**Motivo:** menor error medio que Harris-Benedict en población general; Katch-McArdle
exigiría % de grasa corporal, que no pedimos en el onboarding.
**Consecuencia:** `11-calculation-rules.md` §1; el % de grasa queda como medida opcional en
Progreso, sin entrar en el cálculo.

### D-04 · El superávit para ganar peso se aplica al 50 % del equivalente calórico
**Motivo:** un superávit completo (7700 kcal por kg) asume que todo el aumento es tejido; en
la práctica una parte grande sería grasa. Medio superávit es la recomendación habitual para
ganancia de masa magra.
**Consecuencia:** ganar 0,25 kg/semana sobre un TDEE de 2600 da 2738 kcal, no 2875.

### D-05 · El porcentaje de crédito se **congela** en cada actividad
**Motivo:** el historial tiene que ser reproducible. Si el usuario cambia el crédito hoy, los
días cerrados no pueden cambiar de balance retroactivamente.
**Consecuencia:** `activities.exercise_credit_percentage`; al cambiar la configuración se
recalcula solo el día en curso y los futuros, con aviso explícito. F-13, AC-04, test I-05.

### D-06 · Los valores MET viven en la base, no en el código
**Motivo:** el brief lo exige y permite corregir valores sin publicar una versión.
**Consecuencia:** tabla `activity_types` con seed en `met-catalog.json` y migración con
`on conflict (slug) do update`. Un lint prohíbe literales MET en `presentation/`.

### D-07 · La deduplicación nunca borra sola
**Motivo:** un falso positivo que borra un entrenamiento destruye la confianza en el
producto; un falso negativo solo genera una revisión.
**Consecuencia:** score con umbrales 0,60 / 0,85, `needs_review`, y el diálogo de comparación
como única vía de resolución. `duplicate_resolutions` guarda cada decisión para poder
recalibrar el umbral con datos reales. RN-07, AC-09.

### D-08 · Escritura optimista con reversión selectiva
**Motivo:** el usuario no debe perder un registro por un problema de red.
**Consecuencia:** los errores reintentables (5xx, timeout, offline) **no** revierten: el
registro queda pendiente. Solo los errores de validación o permiso revierten, con aviso.
`13-state-management.md` §7.

### D-09 · `local_date` se calcula en el cliente y se persiste
**Motivo:** el "día" de un usuario depende de su zona horaria; recalcularlo en el servidor
con la zona del servidor rompería los días en viajes y cambios de horario.
**Consecuencia:** columna `local_date` en todas las tablas con dimensión temporal, más
`timezone` en el perfil. El servidor nunca la recalcula.

### D-10 · Modo oscuro canónico, claro derivado
**Motivo:** el sistema de diseño (Nocturne) está definido en oscuro; el claro se deriva
invirtiendo la rampa neutral y bajando el acento un paso para conservar el contraste.
**Consecuencia:** ambos temas se entregan y se testean, pero el oscuro es la referencia de
diseño. `06-design-tokens.md` §1 y §7.

### D-11 · Totales de comida desnormalizados
**Motivo:** Inicio necesita leer el día en una sola consulta; recalcular sumando ítems en
cada render es caro en listas largas.
**Consecuencia:** `meals.total_*` mantenidos por trigger, que es la **única** vía de
escritura de esos campos.

### D-12 · Se usa `ActiveCaloriesBurned`, no `TotalCaloriesBurned`
**Motivo:** el total incluye el metabolismo basal, que ya está dentro del objetivo calórico:
sumarlo sería doble conteo grosero.
**Consecuencia:** si un proveedor solo entrega el total, se descarta y se recalcula por MET
marcando `met_recalculated`. `12-external-integrations.md` §6, RN-05.

### D-21 · Health Connect es la única integración de salud; Apple HealthKit queda fuera de alcance
**Motivo:** decisión de producto. Mantener dos integraciones de salud duplica el trabajo de
adaptadores, de permisos, de declaraciones en las tiendas y de pruebas en dispositivo, sin
aportar nada al núcleo del producto (que funciona completo con registro manual, RN-10).
**Consecuencia:** `HealthProvider` es un enum de un solo valor (`health_connect`); la
pantalla de integraciones y su tab de configuración **solo se muestran en Android**; en iOS
la app funciona completa con registro manual y sin ninguna sección de integraciones. La
arquitectura no se cierra: sumar HealthKit, Garmin o Strava después es agregar un valor al
enum y un adaptador en `data/native/`, sin tocar dominio ni UI.

### D-22 · La duración de una actividad no tiene tope práctico en la UI
**Motivo:** una salida larga en bici, un trekking o un torneo pasan holgadamente las dos
horas. Un tope bajo obliga a partir la sesión en varios registros y ensucia el historial.
**Consecuencia:** el campo acepta de 1 a 1440 minutos (el límite del modelo, un día). La UI
combina presets, un deslizador de 5 a 240 minutos con paso de 5 y un **campo libre en
`hh:mm`** que llega hasta 24:00. Por encima de 4 horas se muestra una nota neutral pidiendo
confirmar la duración, sin bloquear.

### D-13 · El MVP **lee** de Health Connect, no escribe
**Motivo:** escribir exige permisos adicionales, revisión más estricta en las tiendas y
plantea el riesgo de contaminar el historial de salud del usuario con estimaciones nuestras.
**Consecuencia:** solo permisos de lectura; la escritura queda documentada como fase 2.

### D-14 · Sin sincronización en segundo plano en el MVP
**Motivo:** `BGTaskScheduler` / `WorkManager` consumen batería, agregan permisos y su
ejecución no está garantizada. Sincronizar al abrir la app y cada 15 min con la app en
primer plano cubre el caso de uso real.
**Consecuencia:** la tarjeta de integración muestra siempre `last_sync_at` para que quede
claro cuán fresco es el dato.

### D-15 · Modo demo sin cuenta
**Motivo:** bajar la fricción de la primera experiencia; la barrera del registro es la
principal caída del embudo en apps de este tipo.
**Consecuencia:** usuario local anónimo con toda la app funcionando contra la base local;
al registrarse, los datos se migran a la cuenta. Se avisa que sin cuenta no hay respaldo.

### D-16 · Un peso por día (upsert), no varios
**Motivo:** el peso oscila durante el día; varias mediciones diarias ensucian la tendencia
sin aportar información.
**Consecuencia:** unique `(user_id, local_date)`; registrar de nuevo actualiza y avisa.

### D-17 · El exceso calórico no se pinta de rojo
**Motivo:** RN-14. El color de error convierte un dato en un juicio.
**Consecuencia:** el arco excedente usa `accent-700` y el texto dice "Te pasaste por N kcal".
`danger` queda reservado para errores del sistema y acciones destructivas.

### D-18 · Cuota de 20 análisis de foto por día
**Motivo:** acotar el costo variable de Gemini (R-01) sin molestar al uso normal (un usuario
registra 3–6 comidas por día).
**Consecuencia:** contador visible en la pantalla de cámara a partir del 15.º análisis, y
mensaje claro al agotarse con la alternativa manual.

### D-19 · Idioma: español rioplatense, código en inglés
**Motivo:** el brief y el usuario están en español; el código en inglés mantiene la
convención de la industria y evita mezclas.
**Consecuencia:** i18n desde el día uno con un solo idioma entregado.

### D-20 · El historial es editable
**Motivo:** la gente registra tarde y se equivoca. Un historial de solo lectura empuja a
registrar mal o a abandonar.
**Consecuencia:** cualquier registro pasado puede editarse o borrarse; los objetivos
históricos, en cambio, no se reescriben (D-05 y §F-13).

---

## 2. Funcionalidades simuladas en el prototipo

`Ceres.dc.html` es un prototipo navegable de alta fidelidad. Lo que **simula**:

| Área | Cómo está simulado | Qué es real en el prototipo |
| --- | --- | --- |
| Autenticación | No existe; se entra directo | — |
| Persistencia | Estado en memoria; se pierde al recargar | Las mutaciones sí se reflejan en toda la UI |
| Datos | Un día sembrado con 3 comidas y 2 actividades, 30 días de historial generados | Los totales se recalculan de verdad |
| Cálculo MET | **Real**: la fórmula está implementada | Cambiar tipo/duración/intensidad recalcula |
| Crédito de ejercicio | **Real**: el ajuste y el balance se recalculan | Cambiar el porcentaje actualiza Inicio |
| Búsqueda de alimentos | Catálogo local de ~20 alimentos | El filtrado y el agregado a la comida |
| Análisis de foto | Resultado fijo tras 1,2 s simulados | La pantalla de revisión y la corrección de ítems |
| Sincronización de salud | Botón que "importa" 3 actividades, una duplicada | El diálogo de duplicado y su resolución |
| Gráficos | Datos generados | La forma, los ejes y los estados |
| Offline | No simulado | Los badges de estado sí se muestran |

## 3. Todavía no implementado (ni en el prototipo ni en el MVP)

- Ejercicios, series, repeticiones, peso, descanso, volumen, récords y rutinas de fuerza
  (tablas creadas y vacías; sin UI).
- Escaneo de código de barras con cámara (pantalla y contrato definidos; entrada manual de EAN).
- Escritura hacia Health Connect (D-13).
- Recetas compuestas, listas de compra, planes de comida.
- Notificaciones push y recordatorios.
- Web app, widgets de pantalla de inicio, complicaciones de reloj.
- Multi-idioma (solo `es` entregado).
- Universal Links / App Links verificados (esquema `ceres://` sí resuelto).
- Sincronización en segundo plano (D-14).

## 4. Pasos exactos para empezar el desarrollo

1. **Leer** `00-index.md`, luego `01-product-requirements.md` y este documento. Las
   decisiones D-02, D-05, D-06, D-07 y D-12 son las que más fácil se implementan mal.
2. **Crear el proyecto Supabase** `ceres-dev` en la región `sa-east-1`. Guardar
   `SUPABASE_URL`, `ANON_KEY` y `SERVICE_ROLE_KEY` en el gestor de secretos.
3. **Aplicar las migraciones** en el orden de `08-supabase-plan.md` §1. Verificar que el
   seed de `activity_types` cargó los 15 tipos de `met-catalog.json`.
4. **Correr la suite pgTAP de RLS** (`supabase/tests/rls_test.sql`) y no avanzar hasta que
   los 10 casos estén en verde. Esto es lo que hace segura a la `ANON_KEY` en el cliente.
5. **Crear el proyecto móvil** con la estructura de `19-project-structure.md` §1 y el
   generador de tokens (`tool/gen_tokens.dart`) a partir de `design-tokens.json`.
6. **Implementar `domain/calculations/` primero, con sus tests.** Los 20 casos de
   `11-calculation-rules.md` §20 deben pasar **antes** de escribir una sola pantalla. Es la
   parte del producto donde un error es invisible y caro.
7. **Levantar la app en modo `mock`** (sin ninguna variable de entorno) con las pantallas
   esqueleto de la fase 2, y recorrer los 14 flujos de `03-user-flows.md` para validar la
   navegación.
8. **Seguir el roadmap** de `18-implementation-roadmap.md`, fase por fase. Cada fase tiene
   su DoD; no se pasa a la siguiente sin cumplirlo.
9. **Verificar contra los criterios de aceptación** de `17-acceptance-criteria.md` al cerrar
   cada fase. AC-02, AC-04 y AC-09 son los que definen si el producto hace lo que promete.
10. **Antes de publicar**, ejecutar el checklist de accesibilidad
    (`15-accessibility.md` §11) y las declaraciones de privacidad de las tiendas
    (`18-implementation-roadmap.md`, fase 15).

## 5. Cómo pedirle a otra IA que lo desarrolle

> Desarrollá la aplicación siguiendo exactamente el handoff que está en `docs/handoff/`.
> Empezá por `00-index.md`. Respetá las decisiones de `decisions.md` sin reinterpretarlas:
> si algo parece ambiguo, la decisión ya está tomada y documentada. Implementá primero
> `domain/calculations/` con sus tests (`11-calculation-rules.md` §20) y recién después la
> interfaz. No inventes reglas de negocio que no estén en `01-product-requirements.md` §6.

Todo lo necesario está dentro de este proyecto: no hace falta la conversación original.
