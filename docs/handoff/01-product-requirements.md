# 01 — Product Requirements

## 1. Objetivo del producto

Ceres permite a una persona **registrar lo que come, lo que se mueve y cuánto pesa**, y
ver en una sola pantalla si ese día está dentro de su objetivo calórico — con la honestidad
de mostrar el cálculo completo en vez de un único número mágico.

El diferencial no es tener más funciones que un contador de calorías clásico, sino:

1. **Transparencia del cálculo.** Objetivo base, comida, actividad, ajuste aplicado y
   balance final se muestran por separado y siempre.
2. **Honestidad sobre las estimaciones.** Las calorías quemadas nunca se presentan como
   medición. Se etiquetan como estimadas y se indica el método (MET, importado, manual).
3. **Registro rápido.** Agregar una comida o una actividad no debe tomar más de 15
   segundos en el camino feliz.
4. **Tono neutral.** Sin culpa, sin rachas rotas, sin castigo por días de descanso.

## 2. Público objetivo

- **Primario:** adultos de 25 a 50 años que ya intentaron llevar un registro alimentario y
  abandonaron por fricción o por sentirse juzgados. Buscan bajar o mantener peso con un
  déficit moderado.
- **Secundario:** personas que entrenan de forma regular (3–5 sesiones semanales) y quieren
  ver alimentación y gasto en el mismo lugar, sin adoptar una app de gimnasio completa.
- **No es el público:** atletas de rendimiento, pacientes con condiciones clínicas que
  requieren supervisión, ni personas con trastornos de la conducta alimentaria — para este
  último grupo el producto aplica salvaguardas (ver §6, reglas RN-12 y RN-13).

## 3. Problemas que resuelve

| Problema | Cómo lo resuelve Ceres |
| --- | --- |
| Registrar comida es lento y tedioso | Foto + IA, buscador con recientes/favoritos, duplicar comida anterior |
| No se entiende de dónde sale "te quedan X calorías" | Desglose permanente: base + ejercicio aplicado − consumido |
| Las apps regalan calorías por ejercicio y sabotean el déficit | Crédito de ejercicio configurable, **0 % por defecto** (D-02) |
| El ejercicio importado se duplica con el manual | Motor de deduplicación explícito (`DuplicateDetectionService`) |
| Las apps culpabilizan | Copy neutral, días de descanso planificados, sin rachas punitivas |
| El usuario no sabe si el número es real o inventado | `DataOriginBadge` + `estimation_method` visibles en cada registro |

## 4. Alcance del MVP

Las 33 funcionalidades obligatorias, agrupadas:

**Cuenta y configuración**
1. Onboarding (6 pasos).
2. Perfil corporal (sexo biológico, fecha de nacimiento, altura, peso, nivel de actividad).
3. Objetivo calórico calculado (Mifflin-St Jeor → TDEE → déficit) o ingresado manualmente.
4. Configuración del crédito de ejercicio (0 / 50 / 75 / 100 / personalizado).
5. Perfil y Configuración.
6. Mocks de autenticación (email + contraseña contra Supabase Auth; en modo demo, local).

**Alimentación**
7. Inicio con resumen diario.
8. Registro manual de alimentos.
9. Buscador de alimentos (USDA FDC + Open Food Facts + alimentos propios).
10. Registro mediante foto e IA (Gemini).
11. Revisión y corrección de la estimación de IA antes de guardar.
12. Historial de comidas.
13. Favoritos y recientes de alimentos y comidas.

**Actividad**
14. Registro manual de ejercicio (rápido y detallado).
15. Catálogo de actividades con valores MET configurables.
16. Estimación por MET.
17. Actividades recientes y favoritas, plantillas, duplicar sesión.
18. Resumen diario de actividad.
19. Historial de ejercicio con filtros.
20. Registro de entrenamiento de fuerza (versión simple, modelo preparado para series).
21. Objetivos opcionales de actividad.

**Cuerpo y progreso**
22. Registro de peso.
23. Registro de medidas corporales.
24. Gráficos semanales y mensuales.
25. Gráficos de peso, calorías y actividad.

**Plataforma**
26. Mocks de persistencia y datos simulados realistas.
27. Manejo de errores tipificado.
28. Estados vacíos en todas las listas.
29. Estados sin conexión con cola de escritura.
30. Prevención básica de duplicados.
31. Interfaces preparadas para Health Connect (lectura real detrás de flag).
32. Modo claro y modo oscuro.
33. Documentación completa de handoff (este directorio).

## 5. Fuera del MVP (versiones posteriores)

- Seguimiento de gimnasio completo: ejercicios individuales, series, repeticiones, peso,
  descanso, volumen, récords personales, rutinas reutilizables. **El modelo de datos ya lo
  soporta** (ver `07-data-model.md`, tablas `strength_exercises` y `strength_sets`,
  marcadas como *fase 2 — crear la migración, no la UI*).
- Escaneo de código de barras en tiempo real con cámara (el MVP incluye la pantalla y el
  contrato; la implementación usa entrada manual de EAN si la cámara no está disponible).
- Cálculo de gasto por frecuencia cardíaca con fórmula propia (**explícitamente excluido**,
  ver RN-08).
- Recetas compuestas con escalado de porciones, listas de compra, planes de comida.
- Social, desafíos, coaching, notificaciones push de marketing.
- Web app. Deep links (las rutas ya están nombradas para soportarlos, ver
  `02-information-architecture.md` §6).

## 6. Reglas de negocio

| ID | Regla |
| --- | --- |
| RN-01 | El objetivo calórico diario **base** nunca se modifica automáticamente por el ejercicio registrado. El ejercicio produce un `adjusted_target` derivado, que se muestra junto al base, nunca en lugar de él. |
| RN-02 | `applied_exercise_calories = round(estimated_calories × exercise_credit_percentage)`. El porcentaje es del perfil, se congela en el registro (`activities.exercise_credit_percentage`) al momento de guardar y se recalcula para todas las actividades del día cuando el usuario cambia la configuración. |
| RN-03 | Las calorías de una actividad **siempre** se muestran con el prefijo "≈" y con `estimation_method` visible. Nunca se muestran como valor exacto. |
| RN-04 | Si el usuario sobrescribe las calorías, se conserva `original_calories` (el valor calculado), se guarda `estimated_calories` (el corregido), `estimation_method = 'user_override'` y opcionalmente `override_reason`. El valor original nunca se pierde. |
| RN-05 | Una actividad importada nunca se recalcula automáticamente, salvo que su valor sea inválido (nulo, ≤ 0, o > 1500 kcal/h de duración). En ese caso se recalcula por MET y se marca `estimation_method = 'met_recalculated'`. |
| RN-06 | Ninguna sincronización sobrescribe un registro que el usuario editó manualmente (`user_edited = true`) sin confirmación explícita. |
| RN-07 | Dos actividades son **candidatas a duplicado** si comparten `activity_type_id` y sus intervalos `[started_at, ended_at]` se solapan ≥ 60 % del más corto, o si comparten `(external_source, external_id)`. Ver algoritmo en `11-calculation-rules.md` §12. |
| RN-08 | El MVP **no** implementa una fórmula propia de calorías por frecuencia cardíaca. Se consume el valor calculado por el proveedor (Health Connect / wearable). La FC se guarda solo como dato descriptivo. |
| RN-09 | Los objetivos de actividad son opcionales y **nunca** reducen el objetivo calórico ni bloquean funcionalidad. Incumplirlos no genera ninguna consecuencia en el modelo. |
| RN-10 | El usuario puede usar toda la app sin conectar ningún servicio externo. Ninguna pantalla obligatoria depende de Health Connect, Health Connect, Gemini, USDA u Open Food Facts. |
| RN-11 | Las calorías netas (`consumidas − aplicadas`) se muestran solo en Progreso y en el detalle del día, nunca como representación única del balance diario. |
| RN-12 | El objetivo calórico calculado se clamplea a un mínimo de **1200 kcal** (perfil femenino) / **1500 kcal** (perfil masculino). Si el cálculo cae por debajo, se muestra el mínimo con una nota explicativa. Un objetivo manual por debajo del mínimo requiere una confirmación explícita y muestra una advertencia. |
| RN-13 | El déficit configurable está limitado a **1 kg/semana** (≈ 1100 kcal/día). No existe una opción "agresiva" por encima de ese valor. |
| RN-14 | El copy nunca usa lenguaje de culpa, moralización de alimentos ("comida chatarra", "pecado", "trampa"), ni rachas que se "rompen". Los mensajes de consistencia son descriptivos (ver `04-screen-specifications.md`, pantalla Progreso). |
| RN-15 | Un día puede marcarse como **descanso planificado**; en ese caso los objetivos de actividad de esa jornada se consideran cumplidos por diseño y no cuentan como día sin actividad. |
| RN-16 | Todo registro del usuario es editable y borrable. El borrado es soft delete con posibilidad de deshacer durante 8 segundos (snackbar). |
| RN-17 | La eliminación de cuenta borra de forma definitiva todos los datos del usuario y los archivos de su bucket dentro de las 24 h, y es irreversible tras un período de gracia de 7 días. |
| RN-18 | Un alimento creado por el usuario es privado (RLS por `user_id`). Los alimentos de catálogos externos se cachean en una tabla pública de solo lectura. |

## 7. Limitaciones conocidas

- La estimación de porciones a partir de una foto tiene un error típico de ±25 %. La UI lo
  declara y obliga a pasar por la pantalla de revisión antes de guardar.
- Los valores MET son promedios poblacionales; no consideran composición corporal,
  eficiencia mecánica ni altitud.
- La deduplicación entre proveedores es heurística; ante duda pide confirmación en vez de
  decidir sola.
- USDA FDC y Open Food Facts tienen cobertura despareja de productos de Latinoamérica.
  Mitigación: alimentos propios y "recientes" con prioridad en el buscador.
- Sin conexión no se puede buscar en catálogos externos ni analizar fotos; la foto queda
  encolada y se analiza al recuperar conexión.

## 8. Suposiciones

| ID | Suposición |
| --- | --- |
| S-01 | Un solo usuario por cuenta; no hay perfiles compartidos ni cuentas familiares. |
| S-02 | El usuario tiene un teléfono con iOS 16+ o Android 10+ (Health Connect requiere Android 10+ con la app instalada). |
| S-03 | El backend es Supabase (Postgres + Auth + Storage + Edge Functions). No hay servidor propio. |
| S-04 | El análisis de foto se ejecuta en una Edge Function; la clave de Gemini nunca vive en el cliente. |
| S-05 | El volumen esperado es < 50k usuarios en el primer año; no se requiere sharding ni cache distribuida. |
| S-06 | El idioma inicial es español; la app se estructura con i18n desde el día uno pero se entrega solo `es`. |
| S-07 | El peso corporal usado en las fórmulas MET es el último `weight_logs` registrado; si no hay ninguno, el del perfil. |

## 9. Riesgos

| ID | Riesgo | Impacto | Mitigación |
| --- | --- | --- | --- |
| R-01 | Costo variable de Gemini por análisis de foto | Alto | Cuota de 20 análisis/día por usuario, compresión a 1024 px lado mayor, cache por hash de imagen |
| R-02 | Rechazo de permisos de salud | Medio | La app funciona completa sin integraciones (RN-10); el pedido de permiso se hace en contexto, no en el onboarding |
| R-03 | Doble conteo de actividad daña la confianza | Alto | `DuplicateDetectionService` + `DuplicateActivityDialog` + restricción única en base |
| R-04 | Datos de catálogos externos incorrectos | Medio | El usuario puede corregir cualquier valor; se marca el origen del dato |
| R-05 | Rate limit de USDA (1000 req/h por clave) | Medio | Cache de resultados en `foods_cache` por 30 días, debounce de 350 ms, búsqueda local primero |
| R-06 | Divergencia entre reloj del dispositivo y servidor | Bajo | `local_date` calculada en cliente y guardada explícitamente; el servidor no la recalcula |
| R-07 | Uso por parte de personas con TCA | Alto | RN-12, RN-13, RN-14; sin métricas de "perfección"; ocultar calorías netas por defecto |

## 10. Criterios de éxito

| Métrica | Objetivo a 90 días |
| --- | --- |
| Onboarding completado / iniciado | ≥ 70 % |
| Usuarios con ≥ 3 días de registro en la primera semana | ≥ 45 % |
| Tiempo mediano para registrar una comida por buscador | ≤ 15 s |
| Tiempo mediano para registrar una actividad (registro rápido) | ≤ 12 s |
| Corrección de resultados de IA (`ai_result_corrected` / `meal_photo_analyzed`) | ≤ 40 % — por encima indica que el modelo o el prompt necesitan trabajo |
| Duplicados confirmados por el usuario / actividades importadas | ≤ 2 % |
| Crash-free sessions | ≥ 99,5 % |
| Retención D30 | ≥ 22 % |
