# Estado — 1 de agosto de 2026

Dónde quedamos y cómo retomar. **La app está publicada y en uso**: `v1.11.0` en
GitHub, con sesión, respaldo y análisis de foto contra Supabase.

---

## Lo primero: hay una auditoría aplicada y sin publicar

El 1 de agosto se hizo una auditoría técnica completa y **se implementaron
todos los arreglos**, pero **no se publicó ninguna versión ni se aplicó nada al
proyecto real todavía**. Todo está en el árbol de trabajo, en verde:
**399 tests**, **85 pgTAP**, `analyze --fatal-infos` limpio, 32 migraciones
aplicando desde cero.

- El diagnóstico: [`docs/auditoria-2026-08-01.md`](docs/auditoria-2026-08-01.md)
- Qué se hizo y qué falta: [`docs/auditoria-handoff.md`](docs/auditoria-handoff.md)

Lo que encontró y ya está arreglado, en orden de gravedad:

1. **Cualquiera que conociera tu código de pal podía verte el día.** La política
   `pals_update` dejaba que **quien mandaba la solicitud se la aceptara solo**,
   y `is_pal_of` solo mira que el estado diga `accepted` — no quién lo puso. La
   víctima no tenía que hacer nada ni tener ninguna categoría prendida.
2. **"Eliminar mi cuenta" no eliminaba nada.** Hacía `signOut()` y borraba lo
   local: las tablas, las fotos, los respaldos y el usuario de Auth quedaban
   intactos, y volver a entrar restauraba todo. La política de privacidad
   publicada prometía lo contrario. Ahora lo hace de verdad una Edge Function.
3. **Una solicitud de pal pendiente abría el perfil entero**: `pal_code`, fecha
   de nacimiento, altura, sexo. RLS es por fila y el grant era sobre todas las
   columnas.
4. **Corregir una medida corporal rompía el push de medidas para siempre** en
   esa cuenta, y la pantalla volvía al valor viejo. Id nuevo en cada corrección
   contra un índice único que no se auto-reparaba.
5. **Los borrados no llegaban al servidor.** Solo el peso dejaba lápida. Borrar
   el sueño de una noche lo resucitaba en 30 segundos; las comidas borradas
   revivían enteras en un teléfono nuevo, con la foto ya purgada.
6. **Después de cada push, el servidor le ganaba a todo en la reconciliación**
   —el trigger de `updated_at` se movía aunque la fila no cambiara—, y las horas
   volvían en UTC: un almuerzo de 13:30 se mostraba 16:30.

**Antes de publicar** hay que aplicar las migraciones 28-32 al proyecto real y
desplegar `delete-account` con su secreto. El handoff tiene la lista completa.

---

## Lo próximo (por acá se arranca)

**La versión con el arreglo del updater hay que instalarla a mano una vez, en
todos los teléfonos.** El updater que está instalado —cualquiera de la 1.0.4 a
la 1.5.0— junta el APK entero en memoria y el sistema lo mata cerca del 80 % de
la barra (§13). No puede traerse su propio arreglo: hay que bajar el
`-universal.apk` del release desde el navegador. De ahí en más Configuración →
Actualizaciones funciona sin salir de la app.

Al que además nunca habilitó la instalación le va a faltar el permiso de §12,
que es otro problema y tiene su propio botón en la pantalla.

**Si un teléfono quedó sin datos, restaurar antes de cargar nada.**
Configuración → Respaldo en la nube → "Restaurar desde la nube". Desde la 1.3.1
un documento vacío ya no puede pisar la copia buena (§9), así que la copia
está a salvo mientras tanto; en versiones anteriores no lo estaba.

**Probar el análisis de foto en un teléfono de verdad.** Es lo único del
circuito que nunca se ejecutó: el emulador no tiene cámara, así que la subida al
bucket y la Edge Function de Gemini están escritas y verificadas contra el
servidor, pero sin una foto real de por medio.

**Probar Health Connect en un Samsung.** Configuración → Integraciones de salud
→ Conectar tiene que abrir Health Connect pidiendo los tres permisos (peso,
grasa corporal, sueño) y volver. La lógica de importación está probada con ocho
tests —incluido que sincronizar diez veces deje lo mismo que una— y el APK
declara los permisos, pero **el paso del permiso nunca se ejecutó**: en el
emulador `screencap` devuelve negro sobre la superficie Impeller, así que no hubo
forma de ver ni tocar la pantalla. Y el caso que importa es datos reales de
Samsung Health, que solo existe en un teléfono de verdad.

Del lado de Samsung Health hay que habilitar la sincronización a Health Connect;
del lado de Zepp, Perfil → vinculación de cuentas de terceros → Health Connect.

**Cambiar el nombre de la cuenta de prueba.** La migración
`20260801002100_display_name_no_email` ya está aplicada, así que ninguna cuenta
nueva vuelve a quedar con la parte del correo anterior a la arroba como nombre
visible. Las que ya existen conservan el que tengan —reescribirlas a ciegas le
borraría el nombre a quien sí lo puso—, y se cambian desde Perfil → tocar el
nombre.

**La base rechazaba lo que la app manda. Ya está arreglado del lado del
servidor** (migración `20260801002600_enum_constraints_al_dia`, aplicada y
verificada: los cinco valores que antes rechazaba ahora entran, probados con
`insert` + `rollback` contra el proyecto real).

Cuatro restricciones de valores fijos se habían quedado atrás de sus enums y
rechazaban cada fila. No se notó porque el síntoma no se parece a la causa:
`push` sube cada tabla con un solo `upsert`, así que una fila mala tiraba el lote
entero, y como las once tablas compartían un `try`, la excepción se llevaba
puestas todas las siguientes. El error terminaba en un `SyncFailed` que ninguna
pantalla mostraba. Resultado: **`public.meals` con cero filas** mientras los
teléfonos tenían meses de comidas.

| Restricción | Le faltaba | Posición en el push |
| --- | --- | --- |
| `goals_type` | `gain_muscle` | 2 de 11 |
| `body_measurements_metric` | los 7 pliegues, la bioimpedancia y 2 perímetros | 4 de 11 |
| `body_measurements_unit` | `mm`, `kg`, `index` (y el rango, que asumía cm/pct) | 4 de 11 |
| `meals_source` | `ai_text` | 9 de 11 |

**No se perdió nada**: está todo en los teléfonos y sube con el próximo registro
de cada persona. Para verificar, `docs/verificar-sincronizacion.md`.

Los conteos al momento de aplicar la migración, en el orden del push:

```
     6   profiles          1   water_logs        0   meals
     2   goals             1   sleep_logs        0   meal_items
     1   weight_logs       0   activity_goals    0   activities
     0   body_measurements 0   foods
```

**Ojo con leer de más en esos ceros.** `subir` sale temprano cuando la lista está
vacía, así que un 0 puede ser "falló" o "esa persona no cargó nada de eso" — y
que `water_logs` y `sleep_logs` tengan filas con `body_measurements` en 0 muestra
justamente eso: para esos usuarios las medidas estaban vacías, no fallando. Cada
teléfono empuja por su cuenta y rompe en el punto que le toca según lo que tenga
cargado. Lo único que estos números prueban sin ambigüedad es que **de `meals`
para abajo no hay una sola fila**, con seis perfiles y meses de uso.

Lo que falta para cerrarlo del todo: que un teléfono con la 1.11.0 registre algo
y los conteos dejen de dar 0. Eso no se puede verificar desde acá.

Lo que impide que vuelva a pasar es `test/data/enum_constraints_test.dart`, que
compara cada enum de Dart contra cada `check` de las migraciones y falla si se
separan. Además, ahora cada tabla del push tiene su propio `try` —una rota ya no
se lleva las que siguen— y el fallo se muestra en Configuración → Respaldo en la
nube, donde antes no se veía en ningún lado.

**Las tablas son la fuente de verdad de la cuenta**: al entrar se traen y se
reconcilian con lo local, y desde ahora **también al volver a la app** desde
segundo plano (`RelationalSyncService.refresh`, como mucho una consulta cada 30
segundos). Antes era solo al arrancar en frío, así que en el teléfono un cambio
hecho desde la web aparecía recién cuando Android mataba el proceso.

La reconciliación **no puede dejar menos registros de los que había**: es unión
por id, gana el más reciente, y ante empate o falta de fecha gana lo local
(`domain/services/document_merge.dart`, 15 tests). Lo único que hace desaparecer
algo es un borrado que alguien pidió y que llega con fecha más nueva.

El botón **Comparar** de Configuración → Respaldo en la nube se sacó. Existió
para comprobar que las tablas fueran de verdad la fuente de verdad mientras se
estaba dando vuelta; ya está comprobado, y lo que quedaba era una herramienta de
desarrollo con la ropa de una opción de configuración: dos columnas de números
para que quien usa la app decidiera si la diferencia estaba bien.

Para compilar con servidor hay que pasarle la config:

```bash
flutter run --dart-define-from-file=env/local.json
```

Sin ese archivo la app arranca en **modo local** y lo dice: no autentica contra
nadie y los datos no salen del teléfono. Es a propósito, para que un clon recién
bajado y `flutter test` funcionen sin credenciales.

⚠️ La `secret key` (`sb_secret_…`) no va nunca en la app, ni en el repo, ni en
un chat: saltea RLS por completo. Solo vive en los secretos de las Edge
Functions.

---

## Qué está hecho

### La app (Flutter, Android)

40 pantallas, el sistema de diseño Nocturne completo, animaciones y
accesibilidad según el handoff. **376 tests en verde**, `flutter analyze`
limpio, APK de release firmado y verificado en el emulador contra el proyecto
real.

Comidas, actividades con cálculo MET, peso, medidas, agua, historial, progreso
y objetivos. Hay un **widget** con el resumen del día
para la pantalla de inicio del teléfono. El catálogo consulta Open Food Facts (con prioridad a productos
argentinos) y el escáner lee el código de barras con la cámara. Recordatorios
locales de agua y de registro con horario configurable, sueño por noche y
planificación de comidas hasta tres días adelante.

**Objetivos.** Cuatro: bajar de peso, mantener, subir de peso y ganar músculo.
Elegir uno deja configurado el ritmo, las calorías, los macros y la actividad
semanal de una sola vez (`domain/calculations/goal_presets.dart` explica de
dónde sale cada número). Se elige al crear la cuenta y se cambia desde Perfil.
Las calorías del día se editan desde la propia tarjeta de Inicio, de a 50 kcal
o escribiendo el valor.

**Catálogo de alimentos.** Tres fuentes que no se pisan:

| Fuente | Qué cubre | Dónde vive |
| --- | --- | --- |
| **ARGENFOODS** (UNLu) | 252 alimentos argentinos verificados | dentro del APK, anda sin conexión |
| **Open Food Facts** | productos envasados, por código de barras | consulta directa, Argentina primero |
| **USDA** | alimentos genéricos y crudos | Edge Function `food-search` |

La tabla argentina se extrajo de los PDF de ARGENFOODS y **cada fila se valida
contra Atwater** (4/4/9) y contra la suma de componentes, en el parser y otra
vez en `test/data/argenfoods_catalog_test.dart`. No es paranoia: el primer
intento dio "aceite de oliva, 100 g de proteína" —las columnas corridas— y ese
número en el historial de alguien es peor que no tener el alimento.

**Comidas frecuentes y descripción por texto.** Lo que se repite aparece arriba
del "+" de cada slot para cargarlo de una. Y se puede escribir "dos empanadas
de carne y una coca": lo estima la Edge Function `analyze-meal-text`, que
comparte validación y cuota con la de foto.

**"¿Qué como?" — sugerencias para lo que queda del día.** ⚠️ *Prototipo: el ida y
vuelta contra el modelo real nunca se ejecutó. Ver abajo.*

Menú Agregar → "¿Qué como?" pide tres platos que entren en las calorías que
quedan, cada uno con sus ingredientes, sus macros y su receta. El presupuesto se
puede cambiar: "lo que me queda" es la pregunta de la noche, cuando lo que
importa es no pasarse, pero también se cocina al mediodía con el día entero por
delante y ahí el número que interesa es el del plato —"algo de 600"— y no el
saldo. Sin tocar nada sigue preguntando por el saldo. Elegir uno abre el
formulario de comida con todo puesto, para revisarlo antes de guardar: lo que el
modelo propuso es un punto de partida, y guardarlo sin mirar sería meter números
estimados sin que nadie los haya aceptado. Queda como `aiText`, que es lo que es.

Va arriba en el menú a propósito: describir y sacar una foto parten de que ya
sabés qué comiste, y esta parte de la pregunta anterior.

**Las cuatro formas de armar una comida viven juntas.** Buscar en el catálogo,
escanear un código, sacar una foto y describirla están las cuatro en la pantalla
de la comida. El menú "+" ofrece "Agregar comida" y lleva ahí: ninguna de las
cuatro es una entrada paralela —todas son formas de sumar ítems— y tenerlas
sueltas en el menú obligaba a elegir el método antes de empezar. El subtítulo de
esa fila las nombra, porque es la única pista de que están adentro.

El escáner no tiene botón propio ahí: vive dentro del buscador, y "Agregar
alimento" abre el buscador. Y adjuntar una foto a mano —la que no analiza nada—
es cosa de una comida que ya existe, así que aparece editando y no dando de
alta: competía con el botón que sí analiza y alargaba el camino corto.

**La foto se puede acompañar con una aclaración.** Entre la cámara y el análisis
hay un paso con un campo opcional. Es lo único que sube el techo de la foto: una
empanada se ve igual sea de carne, de humita o de jamón y queso, y el pollo
frito y el hervido son el mismo pollo desde arriba. El modelo elige el más
probable y se equivoca callado; quien la sacó sabe la respuesta.

Lo escrito llega a la Edge Function y va en el prompt **después de la imagen**,
con reglas explícitas: manda la foto, la aclaración sirve para lo que la foto no
puede mostrar —el relleno, la cocción, la marca— y no habilita inventar
alimentos que no están. Si dice una porción, se toma y sube la confianza: es un
dato que el modelo no podía medir. El campo vacío es una respuesta válida y deja
el análisis como era; si fuera obligatorio, el paso sería un peaje.

**La regla es una sola y no se le delega al modelo: ninguna opción puede pasarse
del presupuesto.** Se le pide en el prompt y después se suma de nuevo, en la
Edge Function `suggest-meals` y otra vez en el cliente. Una opción se descarta
**entera** si se pasa, si el total no es la suma de sus ingredientes, o si un
ingrediente no cierra por Atwater. Nada se corrige a mano: un plato al que le
arreglamos un ingrediente ya no es el que propuso el modelo, y la receta dejaría
de corresponderse con los números. Un plato de 800 kcal ofrecido a quien tiene
600 no es una sugerencia imprecisa — es la app diciéndole a alguien que puede
comer algo que no puede, con un número al lado que lo respalda.

Comparte la cuota diaria con las dos estimaciones. **No escribe en
`ai_analyses`**: esa tabla registra estimaciones de lo que alguien *comió*, y una
sugerencia no es eso. Con menos de 150 kcal ni se pregunta, y se dice por qué.

Lo verificado: la función responde y rechaza sin sesión con su código correcto,
la validación tiene 10 tests, y la app compila con servidor e instala. **Lo que
falta es lo que importa**: que el modelo devuelva opciones que pasen la
validación. No se pudo probar porque los toques sintéticos no llegan a la
superficie Flutter del emulador —la misma pared que Health Connect (§ arriba)— y
la única forma es un teléfono de verdad con el APK de servidor.

Ojo con un riesgo conocido si eso no anda: la validación de acá es **más dura**
que la de las dos estimaciones, que no chequea Atwater por ítem. Ya se aflojó una
vez por eso (Atwater al 25 %, piso de uso al 30 %). Si la pantalla dice siempre
"esta vez no salió nada", el sospechoso es ese, no el modelo.

**Medidas corporales.** Tres grupos, como los entrega una nutricionista:
perímetros en cm, pliegues cutáneos en mm y bioimpedancia. Se cargan todos
juntos por fecha, no de a uno. El peso y la altura quedan afuera a propósito:
tienen su propio registro y alimentan el cálculo de BMR.

**Alta guiada, obligatoria.** Crear la cuenta lleva a cinco pasos: sexo y fecha
de nacimiento, altura y peso, nivel de actividad, objetivo, y las calorías por
día. Recién después se entra a Inicio.

El quinto es el que cierra, y existe porque los cuatro anteriores no alcanzaban:
elegir "Bajar de peso" dejaba a la persona en Inicio con un objetivo que nunca
había visto, calculado con un ritmo de 0,5 kg por semana que tampoco había
elegido. Ahí se ve el número, se elige a qué ritmo ir —cada opción muestra las
calorías que deja, que es la única diferencia real entre ellas— y se puede
escribir otro para quien sigue un plan de un profesional. Un objetivo que no se
confirmó no es un objetivo: es una suposición con forma de cuenta.

**El ritmo es una fracción del gasto, no una cantidad de kilos.** Medio kilo por
semana son 550 kcal para cualquiera, y 550 kcal son el 21 % del gasto de una
persona de 2.600 y el 35 % del de una de 1.550: el mismo rótulo escondía dos
esfuerzos que no se parecen, y el segundo es el que hacía que la app le diera muy
poco a los cuerpos más chicos. Ahora se elige entre "un 10 % menos que tu gasto"
y "un 25 % menos", y los kilos por semana salen de ahí y se muestran como la
consecuencia que son. Como el gasto es metabolismo basal × nivel de actividad, la
fracción ya está leyendo el cuerpo y la semana de quien elige. El tope de 1 kg
por semana sigue mandando sobre los gastos más grandes.

**El objetivo lo puede proponer la IA.** En el mismo paso, al lado del número
calculado, con su explicación y un botón para usarlo. No se pide solo: gastar una
consulta de la cuota de alguien que iba a aceptar el calculado es cobrarle por
algo que no pidió. La Edge Function `suggest-calorie-target` **rehace la cuenta**
—metabolismo basal y gasto— con los datos crudos que recibe, y acota contra su
propio número lo que devuelve el modelo; si el techo viniera del teléfono, la
validación no estaría validando nada. Lo aceptado se guarda con `target_method =
'ai'`, que no es ni `calculated` ni `manual`: de dónde viene un número es parte
del número.

Antes se entraba directo y el resto se cargaba desde Perfil cuando se quisiera,
y así el primer número que veía alguien —"te quedan 1.096 kcal"— salía de un
objetivo de 2.000 puesto por defecto, no de ningún cálculo: sin nacimiento,
altura y peso no hay Mifflin-St Jeor. Un valor de referencia disfrazado de
cuenta es justo lo que el producto no hace (RN-03), y menos el primero.

Los tres que se exigen son los que **no tienen un valor por omisión honesto**;
el sexo biológico admite "Otro" y el nivel de actividad y el objetivo arrancan en
algo razonable, así que ahí un valor por defecto es una respuesta válida. Lo hace
cumplir el `redirect` del router (`needsOnboarding`), no la pantalla de alta: a
Inicio se llega por el alta, por iniciar sesión y por el splash de cualquier
arranque posterior, y ponerlo en uno solo dejaba los otros dos abiertos. Cada
paso se guarda al pasar al siguiente, así que cerrar la app a mitad de camino no
obliga a empezar de nuevo.

**No hay datos de ejemplo en ninguna compilación de verdad.** La siembra de
`data/mock/seed.dart` —los treinta días de "Camila"— quedó atada a
`FeatureFlags.seededDemoData`: solo en modo depuración y sin servidor
configurado. Un usuario nuevo entró y se encontró con ese historial, que además
sube a las tablas en cuanto se abre sesión, y ahí lo inventado y lo real quedan
en la misma cuenta sin forma de distinguirlos. Hay tres cerrojos, uno por camino
(`test/data/demo_seed_test.dart`): `LocalStore.seed` no hace nada si no está
permitido; al arrancar, un documento sembrado que quedó de una versión anterior
se borra; y entrar a una cuenta desde el modo de prueba arranca limpio en vez de
adoptar lo que hubiera.

Detalle completo: [`docs/estado-de-la-app.md`](docs/estado-de-la-app.md)

### El backend (Supabase)

Proyecto `ifincvqdsotorvmwzpos`, región **sa-east-1**, Postgres 17.6.

| | |
| --- | --- |
| Migraciones | 32 escritas; **27 aplicadas al proyecto real** — las 5 de la auditoría están sin aplicar |
| Tablas | 26, **todas con RLS** — se sumó `rate_limits` (migración 24) |
| Políticas | 83, más 5 de Storage |
| Buckets | 4 (3 de fotos + `backups`), privados, con política por prefijo |
| Pals | vínculo por código; `shared_days` sigue siendo la superficie compartida, ahora con fotos/agua/sueño/detalle de ejercicio opcionales, apagados por default y elegidos desde Perfil |
| Suite pgTAP | **85 de 85** en local (se suman 10 de consentimiento de Pals y 7 del contrato de sync); las 66 previas, también contra el proyecto real |

Detalle completo: [`supabase/README.md`](supabase/README.md)

#### Cuánto ocupa, y el único número que va a crecer

Al 31 de julio de 2026, en plan **Free**: la base usa **0,03 GB de 2 GB** y
Storage **~9 MB de 1 GB**. De la base, casi todo son extensiones y esquemas del
sistema —un proyecto Supabase recién creado arranca en 40-60 MB—; la tabla más
grande del proyecto es `public.activities`, con 128 kB. A razón de unas veinte
filas por persona por día, la base no es un problema que vayamos a tener.

**Storage sí.** Una foto son ~200 kB contra los ~200 bytes de la fila que la
nombra: mil veces más por registro. Se arreglaron tres cosas que la hacían
crecer más rápido de lo que le corresponde (`test/domain/photo_storage_test.dart`):

1. **Cada foto analizada con IA se guardaba dos veces.** Analizar sube la foto
   con un id al azar —la Edge Function la lee del bucket—, y después `saveMeal`
   la volvía a subir con el id de la comida, porque lo que llegaba ahí seguía
   siendo la ruta del archivo del teléfono. La primera copia no la referenciaba
   nadie: no se mostraba, no se borraba y no había forma de encontrarla. Ahora la
   ruta del bucket viaja de vuelta con el análisis y la comida apunta a esa copia.
2. **Descartar un análisis dejaba su foto en el servidor.** Es de lo más común
   cuando el número no convence. Ahora se borra al salir sin guardar.
3. **Borrar una comida no borraba su foto, nunca.** El borrado es suave y la
   lápida se queda —la reconciliación la necesita—, pero la foto no tiene por
   qué. `purgeDeletedPhotos` la saca del bucket un día después del borrado, con
   margen de sobra sobre la ventana de deshacer, y solo limpia la ruta cuando el
   borrado salió bien: al revés dejaría la foto en el bucket sin nada que la
   nombre.

Y una cuarta que era de tamaño, no de cantidad: **`image_picker` ignora
`imageQuality` cuando la imagen tiene canal alfa** y devuelve un PNG sin
comprimir. Desde la cámara no pasa; desde la galería sí, porque una captura de
pantalla suele traer alfa. Eran 1-3 MB en vez de 200 kB —entre 5 y 15 fotos
normales— y encima se subía con nombre `.jpg` y `content-type: image/jpeg`, así
que los bytes no eran lo que decían ser. `PhotoNormalizer` lo compone sobre
blanco y lo recodifica a JPEG; sobre blanco y no descartando el alfa, porque
descartarlo deja manchones negros donde había transparencia.

**No se bajó la calidad, y a propósito.** Es lo primero que uno piensa, y las
fotos no tienen margen: la miniatura ocupa el ancho entero de la pantalla —en un
teléfono de 1080 px se dibuja prácticamente 1:1—, el visor permite zoom hasta 5×
y desde ahí se guarda en la galería y se comparte. Bajar la resolución empeora la
vista de todos los días, no solo el zoom, y no se puede deshacer. Los cuatro
arreglos de arriba no cuestan un solo píxel.

Si al ritmo real el giga igual se acerca, el paso siguiente es **Pro, US$ 25 por
mes**: 100 GB de Storage, 8 GB de disco, 250 GB de egress y 100.000 usuarios
activos. Con 100 GB, al ritmo de hoy, el límite deja de existir.

### Distribución

Repositorio en [github.com/mattcastells/Ceres](https://github.com/mattcastells/Ceres),
público. CI en cada push y pull request: `analyze`, tests y la suite de RLS
contra un Postgres limpio. Última publicada: **v1.11.0**.

Publicar una versión es empujar un tag `v1.11.1`: el workflow compila el APK
firmado y crea el release. La app se actualiza desde **Configuración →
Actualizaciones**, sin pasar por Play Store.

**Y ahora avisa sola.** Al abrir la app se consulta si hay una versión nueva y,
si la hay, se ofrece; el que acepta va a la pantalla de siempre, con su permiso
de instalación y su barra de progreso. Nadie le avisa a nadie que salió una
versión cuando se distribuye por fuera de Play Store, y con la comprobación solo
manual el resultado fue gente corriendo versiones de meses atrás —incluida la
que tenía rota justamente la actualización.

Lo que se hace sin permiso es **preguntar**, no bajar: la consulta es un JSON de
unos kilobytes contra la API de releases; los 25 MB del APK siguen necesitando
que alguien los pida. Con tres frenos para que no se vuelva ruido: como mucho una
consulta cada 6 horas, "Ahora no" calla **esa** versión y no las que vengan, y si
la consulta falla no se dice nada porque no la pidió nadie
(`presentation/screens/settings/update_prompt.dart`).

Procedimiento completo: [`docs/releases.md`](docs/releases.md), condensado con
sus trampas en la skill [`.claude/skills/publicar`](.claude/skills/publicar/SKILL.md).

---

## Estado de la máquina

Todo esto quedó instalado y configurado; no hay que rehacerlo.

| Herramienta | Dónde |
| --- | --- |
| Android SDK | `%LOCALAPPDATA%\Android\Sdk` (platform-tools, android-36, build-tools 36) |
| Emulador | AVD `ceres` (Pixel 7, API 36) — `flutter emulators --launch ceres` |
| Keystore de release | `android/ceres-upload.jks` + `android/key.properties` |
| Supabase CLI | 2.110.0 (scoop) |
| Stack local | quedó **corriendo** en Docker — se apaga con `supabase stop` |

### 🔑 Respaldar antes que nada

`android/ceres-upload.jks` y `android/key.properties` están fuera de git a
propósito. **Si se pierde el keystore no se puede volver a publicar una
actualización de la app nunca más.** Copialos a un lugar seguro (gestor de
contraseñas, Drive privado) antes de seguir.

---

## Cosas que ya nos mordieron

Para no volver a perder tiempo con lo mismo:

1. **El APK de release no llevaba `android.permission.INTERNET`.** Flutter la
   inyecta sola en debug, así que el catálogo online andaba al desarrollar y
   habría estado muerto en el teléfono. Ya está en el manifest.
2. **`supabase db push --linked` no funciona desde esta máquina**: resuelve el
   host directo de Supabase, que es IPv6 puro, y acá no hay IPv6. Pero
   pasándole el *session pooler* con `--db-url` anda, sin Docker y sin
   `supabase login` — el comando exacto está en `supabase/README.md`. Sin
   Docker tira warnings de `failed to connect to the docker API`: son del
   caché opcional del catálogo, no de la migración. Confirmar siempre con
   `supabase migration list`.
3. **RLS sin `GRANT` no hace nada útil**: `authenticated` recibe *permission
   denied* y las políticas ni se evalúan. Los grants están en la migración 14.
4. **El compilador incremental de Kotlin** falla en Windows cuando el proyecto
   está en `D:` y el caché de pub en `C:`. Apagado en `android/gradle.properties`.
5. **Los sheets deben abrirse en el navigator raíz**, si no el FAB y la barra de
   tabs quedan por encima y tapan sus botones.
6. **El endpoint clásico de Open Food Facts devuelve 503 seguido.** Se usa el
   moderno (`search.openfoodfacts.org`).
7. **`flutter build apk` puede devolver un APK viejo**, y ni la duración del
   build ni `flutter clean` alcanzan para detectarlo o evitarlo: pasó con
   builds de 5 s, de 171 s, y con `flutter clean` de por medio. Gradle guarda
   estado en `android/.gradle` y en su daemon. Antes de verificar algo en el
   emulador:

   ```bash
   (cd android && ./gradlew --stop)
   rm -rf build .dart_tool android/.gradle android/app/build
   flutter pub get && flutter build apk --release ...
   ```

   Para confirmar que el APK es el del código, buscar un texto nuevo dentro de
   `libapp.so` (se extrae del APK, que es un zip). Es la única prueba que no
   miente.
8. **Los buckets restringen los MIME.** Los de fotos solo aceptan imágenes: el
   respaldo JSON necesitó su propio bucket.
9. **Una lectura fallida borraba todos los datos del teléfono.** `LocalStore`
   hacía `remove()` sobre el documento que no había podido interpretar: un
   solo registro con un campo raro y se perdía **todo** —comidas, peso,
   medidas, historial— sin copia y sin aviso. Encima la app quedaba
   indistinguible de un teléfono nuevo, así que el respaldo vacío que salía de
   ahí podía pisar la copia buena de la nube.

   Cuatro reglas que quedaron y no se negocian:

   - Lo que no se puede leer **se aparta, no se borra** (`quarantine`).
   - Cada registro se lee por separado: uno malo no se lleva puesto el resto.
   - **Un documento sin un solo registro no se sube nunca.** Es la última
     línea de defensa y no depende de que la puerta de `openAfterRestore`
     esté bien: esa puerta se abre igual cuando la descarga falla.
   - Una lectura fallida y un teléfono vacío **no se pueden ver igual**:
     `RestoreOutcome` los distingue y la app lo dice en Inicio.

   Corolario: cualquier acción que llame a `store.reset()` —el modo demo— tiene
   que preguntar antes si hay datos cargados.
10. **Todo `await` contra la red necesita timeout propio.** La subida de la
    foto al bucket no tenía, así que con señal mala el `Future` no terminaba
    nunca y el análisis por IA se quedaba girando para siempre en "Está
    tardando más de lo normal" — sin error, sin salida. Peor: `analyze()` se
    llamaba sin `try`, así que aunque hubiera fallado nadie lo habría
    mostrado. Una espera eterna es la peor forma de contar un fallo, porque no
    se distingue de estar por terminar. Ídem `openAfterRestore`, que se comía
    el error de descarga en silencio.
11. **Publicar APK por arquitectura rompió la actualización.**
    `--split-per-abi` le suma un corrimiento por ABI al `versionCode`
    (`abi × 1000 + code`): en la 1.3.1 el universal quedó en 11 y el de arm64
    en 2011. Como el updater baja **siempre el universal**, quien instaló el
    de su arquitectura recibía la actualización, la descargaba, y Android la
    rechazaba por downgrade. El diálogo dice "No se instaló la app" y nada
    más. Desde la 1.3.2 se publica un solo APK y el `versionCode` arranca en
    **5000**, por encima del 4011 que llegó a publicarse. Igualar los códigos
    desde `build.gradle.kts` **no funciona**: el plugin de Flutter los pisa
    después. Si vuelven los APK chicos, primero el updater tiene que elegir
    por arquitectura.
12. **`REQUEST_INSTALL_PACKAGES` en el manifest no alcanza para instalar.**
   Desde Android 8 el permiso solo habilita a *pedir*; quien autoriza es la
   persona, **por app instaladora**, en Ajustes → Apps → Ceres → Instalar
   apps desconocidas. Sin eso `startActivity` con el APK devuelve éxito y el
   sistema descarta la instalación sin decir nada: la app mostraba "Android
   está instalando" y el teléfono no instalaba nada. Ahora se consulta
   `canRequestPackageInstalls()` antes de bajar los 25 MB y hay un botón que
   lleva a la pantalla exacta. El instalador dejó de depender de `open_filex`
   (que no contempla ese chequeo) y vive en `MainActivity.kt` con su propio
   `FileProvider` (`${applicationId}.updates`).
13. **La descarga de la actualización se clavaba en el 78 %: era memoria, no
    red ni permiso.** El updater juntaba el APK entero en un `List<int>` antes
    de escribirlo. Un `List<int>` de Dart no guarda un byte por elemento sino
    una palabra de 64 bits: **ocho veces el tamaño del archivo**, más la copia
    que hace cada vez que la lista crece al doble. Para el APK de 75 MB eso son
    ~600 MB de lista y un pedido de 1 GB en la última duplicación. Android
    mataba el proceso ahí, y en el teléfono se veía como una barra que dejaba de
    moverse cerca del 80 % sin ningún error.

    Los números dicen cuándo se rompió: la lista duplica en potencias de dos,
    así que un APK de hasta 64 MiB terminaba pidiendo 512 MB y pasaba. La 1.0.3
    pesaba 57,5 MB y andaba; **la 1.0.4 pasó a 73 MB y no volvió a andar**.
    Todas las versiones desde entonces comparten ese código de descarga, así que
    **nadie pudo actualizarse desde la app entre la 1.0.4 y la 1.5.0** — y se
    atribuyó al permiso de §12, que es un problema real pero distinto.

    Desde ahora la descarga se escribe a disco a medida que llega
    (`downloadApkTo`, con `addStream` para que el archivo le ponga freno a la
    red) y el trozo que no llega tiene plazo propio. Corolario incómodo: **el
    arreglo no puede llegar por el updater**, porque el updater instalado es el
    roto. La versión que lo trae hay que bajarla del navegador una vez.
14. **Una lista de pals cacheada para toda la sesión se vivía como "las
    invitaciones no llegan".** `palsProvider` era un `FutureProvider` sin
    `autoDispose`: se resolvía una vez por sesión de app y no se volvía a pedir,
    ni saliendo de la pantalla y volviendo. Quien abría Pals antes de que le
    llegara una solicitud no la veía aparecer nunca, hasta cerrar y reabrir la
    app. Peor: al escribir el código de alguien que ya le había mandado una
    solicitud, el RPC devolvía `already` y la pantalla decía "ya tenés un
    vínculo con esa persona" **arriba de una lista vacía**, porque esa rama
    tampoco invalidaba el provider.

    Verificado contra la base antes de tocar nada: la fila `pending` estaba ahí,
    las policies la dejaban leer de los dos lados y `request_pal` en vivo es
    igual a la migración. Lo único que no se rehacía era la consulta. Ahora se
    relee al entrar, hay botón de actualizar, y Perfil muestra cuántas
    solicitudes quedaron sin responder.
15. **`ref.invalidate()` en `initState()` revienta si el widget se monta como
    raíz de una tab.** `PalsScreen` releía su lista al entrar así desde que se
    resolvió el punto 14, y anduvo bien mientras Pals era una pantalla que se
    empujaba desde Perfil. Al pasar a ser la raíz de la tab "Pals" (§ más abajo)
    empezó a tirar *"dependOnInheritedWidgetOfExactType() ... called before
    initState() completed"*: `ref.invalidate` pide el `ProviderContainer` por
    el árbol de widgets, y eso está prohibido mientras el propio `initState`
    del widget todavía no terminó — cosa que antes nunca pasaba porque un
    push crea su subárbol aparte, y que con una tab de `StatefulShellRoute` sí
    pasa. Se corrige con `WidgetsBinding.instance.addPostFrameCallback`
    alrededor del `invalidate`, no tocando la lógica. Corolario: cualquier
    pantalla que haga esto en `initState` y alguna vez pase a ser la raíz de
    una tab hay que revisarla por lo mismo.

---

## Hecho el 30 de julio de 2026

Pals ahora es una tab de la barra inferior (antes vivía escondida como una
fila de Perfil) y ahí mismo se ve organizado por categorías, igual que
Inicio: comida (con foto, si el otro la comparte), actividad (agregado
siempre, detalle si lo prende), agua y sueño — cada categoría apagada por
default y prendida desde Perfil → "Qué ven mis pals". Se puede mirar hasta
7 días atrás con el mismo selector de fecha que Inicio, acotado en las dos
puntas. Historial se mudó adentro de Progreso (ya no es una tab) para
hacerle lugar.

De paso: el peso de un día anterior ya se puede editar y borrar (con
deshacer) desde "Registros" en Progreso → Peso — antes ninguna fila ahí
tenía `onEdit` ni borrado, ni siquiera la de hoy. Se sacaron los mensajes de
"sin conexión" que nunca podían dispararse (no hay detección real desde que
se quitó el interruptor de desarrollo) y se corrigió la copia de Privacidad,
que seguía prometiendo que "todo vive en tu teléfono" con la nube ya
andando. Y una pasada de seguridad: los jobs de mantenimiento dejaron de ser
ejecutables por cualquier cuenta, `check_rate_limit` (atómico) reemplaza el
conteo manual de la cuota de IA y le puso cuota por primera vez a
`food-search` (que además nunca validaba el JWT, solo que el header
existiera), `android:allowBackup` pasó a `false`, y Gitleaks corre en cada
push.

### Una ronda de bugs reportados, el mismo día

Ocho, y tres eran el mismo error de fondo: **algo que no pasaba y no lo
decía**.

1. **"Registrar peso no funciona."** No era el sheet ni la navegación: un
   cambio de más de 3 kg contra el último registro mostraba un cartel y
   volvía sin escribir nada, esperando un segundo toque a "Guardar". Si en el
   medio se tocaba el campo —lo primero que hace cualquiera cuando algo no
   pasó— el aviso se reseteaba y el botón volvía a no hacer nada. Ahora es un
   diálogo con el botón que confirma al lado: un toque guarda, o pregunta.
   Nunca no hace nada.
2. **La estimación por texto.** `ai_analyses.photo_path` era `not null` y una
   estimación por texto no tiene foto, así que el insert fallaba **en
   silencio** (supabase-js devuelve el error, no lo lanza) en cada estimación.
   Ninguna quedó registrada nunca, y la función devolvía un `id` de una fila
   inexistente que la app guarda en `meals.ai_analysis_id`: la FK rechazaba
   esa comida y **ninguna comida cargada por descripción llegó a las tablas**.
   Migración 26, más un cinturón en `create_meal_with_items` (el registro de
   cómo se estimó no puede ser el motivo de que se pierda la comida). Ese RPC ya
   no existe —la migración 43 lo sacó porque no lo llamaba nadie— y la garantía
   quedó donde vive de verdad: la migración 34 sacó la FK de `meals` al
   análisis, así que una comida no puede depender de una fila de auditoría para
   existir. Del lado
   de la app, `_estimate()` solo capturaba `AppError` y un `TypeError` **no es
   una `Exception`**: cualquier respuesta con forma inesperada dejaba el botón
   girando para siempre. Y la entrada estaba escondida en el "+" de cada
   sección, así que quien entraba por el FAB no la encontraba nunca.
3. **"Agregar un ítem que falta"** en la revisión de la IA no hacía nada: los
   ítems vivían en una lista de la pantalla y el borrador se armaba recién al
   guardar, así que el buscador agregaba a `null` — y `addItem` sobre `null`
   no hace nada y no avisa. Ahora el borrador es la única lista y se abre al
   entrar. Un alimento del catálogo se distingue del estimado: lleva "Del
   catálogo" en vez de un badge de confianza, porque tiene una tabla
   nutricional detrás y no una estimación.
4. **Escanear.** El escáner no estaba donde se arma la comida, y desde el menú
   Agregar iba derecho a la cámara **sin comida abierta** (mismo `addItem`
   sobre `null`). Además el detalle de alimento cerraba **dos pantallas a
   ciegas**, asumiendo que entre el borrador y él hay exactamente una: con el
   escáner abierto desde el borrador, los dos pop se llevaban puesto el
   borrador. Ahora el detalle avisa "agregué" y cada pantalla intermedia se
   cierra sola.
5. Medidas corporales pasó de una fila de píldoras —donde había que elegir una
   métrica para ver su número y abrir un sheet para cargarla— a **campos con
   la última medida abajo**, que se guardan todos juntos. Las series salen por
   sheet. La regla de "campo en blanco = borrar el registro" quedó en un solo
   lugar (`MeasurementDraft`), porque ahora hay dos pantallas que cargan lo
   mismo.
6. El estado vacío se centraba dentro de **su propio** ancho, así que en "Mis
   cosas" —donde no hay botón que estire la columna— el bloque quedaba 60 px a
   la izquierda del eje. Arreglado en `EmptyState`, que es donde estaba.
7. Se sacó el "Buscar actualizaciones" de Acerca de: iba a la misma pantalla
   que la fila de arriba en Configuración.
8. El día de un pal quedó por categorías en orden fijo —comida, agua, deporte,
   sueño— con las comidas adentro por momento del día.

### Widget de la pantalla de inicio

El día completo sin abrir la app: los vasos de agua, las calorías restantes, lo
consumido contra el objetivo y las tres barras de macros. Detalle en
[`docs/estado-de-la-app.md`](docs/estado-de-la-app.md) §3; lo que importa acá es
que **el dato lleva su fecha y el widget la mira**: si lo guardado no es de hoy
no muestra nada de él —ni el número, ni las gotas, ni las barras—, dice "Abrí
Ceres para hoy". Un widget con el número de ayer no se distingue de uno al
día, y eso es la misma clase de mentira que la app no se permite en ningún otro
lado.

Verificado **puesto en la pantalla de inicio del emulador**, con captura de los
cuatro estados: con datos en tema claro y en oscuro, en cero, y con el dato de
otro día. Dos cosas que solo aparecieron ahí y que ningún test hubiera
atrapado: el título "CERES" se leía **"NUT"** —las ocho gotas no le dejaban
lugar, y el nombre de la app sobra en una pantalla de inicio donde la persona
puso el widget a propósito—, y el guion del estado sin datos, a 26 sp y en color
de acento, se leía como una raya de la interfaz en vez de como "acá iba un
número". Los dos se fueron.

Queda anotado que el widget **no se puede probar de verdad sin ponerlo**: se
agrega con un toque largo en la pantalla de inicio → Widgets → Ceres.

Desde la 1.9.0 los vasos de agua **se tocan**: la gota N deja el día en N vasos y
tocar la que ya está última baja a N−1, así el último toque se desanda sin abrir
la app. El toque **no escribe en la base**: anota fecha y delta de un lado y la
app lo aplica cuando corre. No es cautela de más — los datos viven en un único
documento JSON y un proceso de fondo que lo lea y lo reescriba puede pisar
comidas cargadas mientras tanto, que es exactamente cómo se perdieron los datos
de alguien una vez (§9). Se guarda el delta y no el total porque entre el toque y
la app puede haberse registrado agua desde la propia app: sumar deltas conserva
las dos cosas.

También se fue el "Comió X de Y" —es la misma cuenta que el número grande,
contada al revés— y con eso el widget pasó de 4×2 celdas a 4×1.

**Rediseñado de cero**, según
[`docs/handoff/23-widget-redesign-implementacion.md`](docs/handoff/23-widget-redesign-implementacion.md).
El pedido que lo desencadenó: *"está enorme, no tiene que ocupar más de una fila,
hay que distribuir mejor la data y que se adapte si el usuario lo agranda"*.

Se agrega como **una tira de 4×1** y de ahí adapta. Cuatro formas, elegidas por
tamaño (`CaloriesWidget.adaptive`): desde API 31 se mandan las cuatro y el
launcher usa la que entra —también mientras se redimensiona—; antes de eso se
decide con las opciones y se rehace en `onAppWidgetOptionsChanged`.

| Forma | Cuándo | Qué muestra |
| --- | --- | --- |
| `..._compact` | < 200 dp de ancho | número, palabra y el agua en texto |
| `..._wide` | ≥ 200 dp (**el default**) | número a la izquierda; tres macros y el rail de agua a la derecha |
| `..._oneui` | ≥ 110 dp de alto | macros en filas (etiqueta al lado de la barra) y una fila de extras |
| `..._tall` | ≥ 150 dp de alto | las ocho gotas tocables una por una, más consumido y racha |

Lo nuevo, además del reparto:

- **La barra del día**, calorías consumidas sobre el objetivo, del ancho de la
  tarjeta. Es la respuesta barata al anillo de Inicio, que RemoteViews no puede
  dibujar (no hay canvas). Sin objetivo cargado **se esconde entera**: una barra
  al 0 % es un número inventado con forma de cuenta.
- **El agua pasa a ser tocable de verdad.** Las ocho gotas de 10 dp eran un
  cuarto del mínimo recomendado; en los tamaños de una fila ahora hay un rail de
  40 × 44 dp con un solo `PendingIntent` (un toque suma, y al llegar a la meta
  vuelve a cero). Las gotas una por una siguen en el 4×2, donde el área entra.
- **Tipografía Inter**, la misma de la app, con cifras tabulares en el número
  para que no baile entre updates.
- **Los dos estados vacíos con el ícono de la app**, y con texto distinto:
  "todavía no hay nada" es una app recién instalada y "hay algo pero es de otro
  día" es un número que ya no vale.
- **Extras** —actividad, sueño, racha— donde hay alto. Cada uno se esconde solo
  si llega vacío; "Actividad 0 min" ocupa lo mismo que un dato y no es uno.

Las cuatro formas tienen **exactamente los mismos ids**, uno por uno: el código
que las llena es uno solo y no sabe cuál está dibujando, así que un id que exista
en una y no en otra sería una acción de `RemoteViews` perdida en silencio. Los que
una forma no usa quedan declarados en 0 dp.

**Dos números de la especificación se corrigieron contra el teléfono**, y las dos
correcciones dicen lo mismo: el diseño calculaba altos de fila usando el tamaño
del texto (11 sp) en vez del alto que ocupa (unos 14 dp).

1. El umbral de la forma de One UI se proponía en 90 dp para que un Samsung no
   cayera en `wide`. Puesto en el emulador, el widget mide 96 y esa forma
   necesita 108: se cortaban "kcal restantes" y la tercera barra de macro. El
   umbral subió a 110, que es donde entra. Elegir una forma antes de que entre es
   peor que el aire que se quería evitar.
2. La fila de gotas del 4×2 se especificaba en 48 dp fijos con una regla aparte
   para bajarla a 40 con metas grandes. Va con `weight`: `LinearLayout` saltea a
   los hijos en `gone`, así que seis gotas se llevan 53 dp cada una y ocho se
   llevan 40 — lo mismo, sin código y en todas las versiones de Android.

Verificado en el emulador en las cuatro formas y en el estado de dato viejo:
capturas en [`docs/handoff/widget-actual/`](docs/handoff/widget-actual/)
(`nm-widget-v2-*.png`).

---

## Comandos para retomar

```bash
# La app  (sin --dart-define-from-file arranca en modo local, sin servidor)
flutter emulators --launch ceres
flutter run  --dart-define-from-file=env/local.json
flutter test                              # 376 tests
flutter build apk --release --dart-define-from-file=env/local.json

# El backend
supabase start                            # stack local, Studio en :54323
supabase test db                          # suite de RLS
supabase stop
```

---

## Lo que queda

1. **Notificación de pal** ("X cargó su desayuno"): necesita push (FCM) y un
   disparador del lado del servidor. Los recordatorios locales ya están.
2. ~~**Dar vuelta la fuente de verdad.**~~ Hecho, y completo: las tablas mandan,
   se traen al entrar **y al volver a la app**, y se reconcilian con lo local
   (`document_merge.dart`). El documento pasó a ser la copia con la que trabaja
   cada dispositivo.

   Esto es además lo que **habilita la versión web** para quien tiene iPhone: un
   navegador arranca sin nada y se hidrata de las tablas, y desde la segunda
   visita reconcilia en vez de quedarse con su copia aislada. La app ya compila
   a web sin cambios (`flutter build web` verificado); lo que falta ahí es
   `flutter create . --platforms web`, guardas de plataforma en los siete
   archivos que usan APIs que no existen en el navegador —notificaciones,
   escáner, `path_provider`, `image_picker`—, recortar las fuentes y un
   `vercel.json` con el rewrite a `index.html` para que go_router no dé 404 al
   recargar.

**Health Connect ya no está descartado, pero solo entró la mitad segura.**
Estuvo afuera mientras la app la usaba una sola persona que cargaba todo a mano:
importar aportaba poco y traía riesgo de doble conteo. Con varios usuarios en
Samsung eso cambió, así que desde la 1.9.0 entran **peso, grasa corporal y
sueño** — las tres cosas que un aparato mide mejor que la memoria y que son una
por día o por noche, así que reimportar actualiza y no puede duplicar (D-16).

Lo que sigue afuera y por qué:

- **Sesiones de ejercicio.** Es lo único que puede duplicar de verdad. La
  maquinaria para resolverlo ya existe —`duplicate_score.dart`, el diálogo y el
  banner de "necesitan tu confirmación", todo construido para esta importación y
  nunca encendido—, así que es un paso concreto y no una incógnita. Pero es su
  propio paso.
- **Calorías activas.** El reloj las estima con su modelo y Ceres con MET;
  traer el número ajeno y mostrarlo como propio rompe RN-03.
- **Pasos.** En Ceres solo existen colgados de una actividad, así que
  importarlos obligaría a inventar actividades — y esas sí suman calorías.

**Zepp / Amazfit entra por el mismo camino, sin código nuestro.** No hay API
pública para leerle datos: Zepp no manda el historial a ningún servidor que se
pueda consultar. Pero el Zepp app **escribe a Health Connect** (Perfil →
vinculación de cuentas de terceros → Health Connect), así que alcanza con que la
persona habilite ese vínculo una vez. Lo mismo vale para Fitbit y Garmin.

**FatSecret se evaluó y no entró.** Su tier gratis (Basic, 5.000 llamadas/día)
trae **solo el dataset de Estados Unidos**, que es casi exactamente lo que ya da
la Edge Function de USDA. Los datos de fuera de EE.UU. —o sea, los argentinos—
están solo en Premier, que es pago. Y en cualquier tier el token OAuth 2.0 exige
pedirse desde una **IP en lista blanca** (hasta 15; rangos CIDR solo en
Premier), cosa que las Edge Functions no pueden dar porque su IP de salida es
dinámica: haría falta un host propio siempre encendido solo para eso. Costo y
una pieza más de infraestructura para duplicar una fuente que ya está.

---

## Resuelto: la tabla MET de carrera

`11-calculation-rules.md` §11 chocaba con el fixture T-15 de §20 para una
carrera de 10 km/h (11,0 contra 9,8). **Ganó el fixture.** Los cortes de la
tabla (6,5 / 8,0 / 9,7 / 11,3 km/h) son 4/5/6/7 mph convertidos — los anclajes
del Compendium of Physical Activities — y la columna de caminata ya asignaba a
cada tramo el MET de su borde *inferior*. La de carrera usaba el *superior*:
estaba corrida un renglón. Se corrigió la tabla, no la función.
