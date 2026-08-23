# Widget de pantalla de inicio — especificación de implementación

Respuesta al brief `22-widget-redesign-brief.md`, con las variantes ya elegidas.
Esto reemplaza al documento de decisiones anterior: acá está todo lo que hace
falta para escribir el código, con las cajas en dp y sin nada por adivinar.

Referencia visual: `Widget Ceres.dc.html` (mocks a 2×, cada uno con su tira de
medidas debajo).

**Nada de esto necesita una vista, un layout ni una capacidad que RemoteViews no
tenga.** El anillo de la pantalla de Inicio se evaluó y se descarta; el porqué
está en §10, para que no vuelva a discutirse a mitad de camino.

---

## 0. Qué hay que construir

1. Cuatro layouts nuevos (`compact`, `wide`, `oneui`, `tall`) con **un solo juego
   de ids** — §3.
2. Un `ProgressBar` nuevo: **la barra del día**, calorías consumidas sobre el
   objetivo, del ancho del widget. Es la única forma nueva del rediseño; todo el
   resto es reordenar lo que ya existe — §1.
3. El agua pasa de ocho gotas de 10 dp a **un rail tocable de 40 × 44 dp** en los
   tamaños de una fila. Las gotas una por una vuelven donde hay ancho (5×1) o
   alto (4×2) — §5.
4. Tipografía **Inter** — §8.
5. Cinco campos nuevos en el mensaje que manda la app, todos opcionales — §9.
6. Los dos estados vacíos, con ícono — §6.

---

## 1. La barra del día

Una `ProgressBar` horizontal de 6 dp (5 dp en el 4×2), `match_parent`, apoyada
abajo de la tarjeta, con `caloriesPercent`. Cuesta un `ProgressBar` y un
drawable.

Va al mismo grosor que las barras de macro a propósito: es la misma clase de
dato, y a 4 dp se leía como una línea de la interfaz y no como un dato.

Dos reglas sobre ella:

- **Sin objetivo cargado se esconde entera.** Una barra al 0 % es un número
  inventado disfrazado de cuenta (§4.2 del brief).
- **Pasarse no la pone roja.** Se queda al 100 %, con el mismo color de acento.
  Lo que cambia es la palabra del número (`kcal de más`), y nada más (§4.3).

---

## 2. Orden de prioridad

Qué se cae primero cuando falta ancho, de lo que nunca cae a lo primero que se va:

1. **El número y su palabra** (`value` + `label`). No cae nunca; no baja de 22 sp.
2. **La barra del día** (`caloriesPercent`). Sobrevive hasta los 160 dp: 6 dp de
   alto no le compiten a nada.
3. **El agua.** Se degrada en tres pasos, no cae: gotas tocables (5×1, 4×2) →
   rail tocable (4×1, One UI) → cuenta en texto (2×1). Es la única interacción
   que tiene el widget.
4. **Los macros.** Los primeros en irse, y se van **los tres juntos**.
5. **Los extras** (actividad · sueño · racha). Solo donde hay alto de sobra.

Regla que ordena todo: **nada se muestra cortado**. Si un bloque no entra
completo, no entra.

---

## 3. Los layouts

### Dos anatomías, una por alto

En **72 dp** la etiqueta del macro va **arriba** de su barra (tres columnas): es
la única forma de que entren tres macros, el agua y la barra del día sin cortar
nada. En **110 dp** va **al lado** (tres filas): se lee como una unidad y
aprovecha el alto que hay.

Los ids son los mismos en las dos. Lo único que cambia es la orientación del
`LinearLayout` de cada macro y los tamaños de texto.

> La anatomía de filas también entra en 72 dp, y quedó dibujada como alternativa
> (`alt` en el documento visual) por si se prefiere una sola anatomía para todos
> los tamaños. Se gana coherencia y se pierde margen: la etiqueta queda a 60 dp
> fijos en vez de estirarse con la columna. **Este documento implementa la mezcla
> (columnas en 72, filas en 110).** Si se elige la otra, el único cambio es que
> `wide` usa el layout de `oneui` sin su última fila.

### Reglas comunes a los cuatro

- Fondo `nm_widget_bg`: color sólido + esquinas de **16 dp**.
- Tipografía **Inter**: `@font/inter_medium` en el número, `@font/inter_regular`
  en todo el resto.
- Todo texto numérico lleva `maxLines="1"` y `ellipsize="end"`.
- **El mismo juego de ids en los cuatro**, incluidas las ocho gotas y el bloque
  de macros. Los que un layout no usa quedan declarados en 0 dp; el código los
  esconde. El código que llena el widget es uno solo y no sabe cuál está
  dibujando: un id que exista en uno y no en otro es una acción de `RemoteViews`
  perdida en silencio.
- **Nunca `wrap_content` en la columna del número**: el número cambia de ancho y
  los macros bailarían de un update al otro.

---

### 3.1 `nm_widget_calories_compact` — 2×1 · 160 × 72 dp

```
padding 9 arriba / 10 abajo / 10 a los lados
┌──────────────────────────────┐
│ 1.096                  1/6   │  valor 22sp/500 tnum · agua 10sp/400 muted
│ kcal restantes               │  etiqueta 10sp/400
│                              │
│ ▬▬▬▬▬▬▬▬▬▬▬▬▬░░░░░░░░░░░░░   │  barra del día 6dp r3 · match_parent
└──────────────────────────────┘
```

| Elemento | Valor |
| --- | --- |
| `nm_widget_value` | 22 sp / 500 / tnum / accent |
| `nm_widget_water_count` | 10 sp / 400 / muted · `gravity="end"`, misma línea del valor, `baselineAligned` |
| `nm_widget_label` | 10 sp / 400 / text · `maxLines="2"` |
| `nm_widget_calories_bar` | 6 dp, radio 3, `match_parent`, `layout_marginTop="6dp"` |

Caen los macros y el rail, enteros. **El agua pierde el toque**: es el único
tamaño donde el widget solo abre la app. No hay 48 dp para un target y una gota de
20 dp sin área es peor que ninguna.

---

### 3.2 `nm_widget_calories_wide` — 4×1 · 340 × 72 dp · **el default**

Sirve también para 5×1 (430 dp); lo único que cambia ahí es el agua (ver abajo).

```
padding 9 arriba / 10 abajo / 12 a los lados · gap 10 entre bloques
┌────────────────────────────────────────────────────────────────┐
│                P 51/196   C 89/178   G 37/56       ╭──────╮    │
│ 1.096          ▬▬░░░░░░   ▬▬▬▬░░░░   ▬▬▬▬▬▬░░      │  💧  │    │
│ kcal restantes                                     │ 1/6  │    │
│                                                    ╰──────╯    │
│ ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬░░░░░░░░░░░░░░░░░░░░░░░░   │
└────────────────────────────────────────────────────────────────┘
```

Estructura: un `LinearLayout` vertical con dos hijos — la fila de contenido
(`gravity="center_vertical"`) y la barra del día.

| Bloque | Ancho | Detalle |
| --- | --- | --- |
| Número | **84 dp fija** | valor 26 sp / 500 / tnum / accent · etiqueta 11 sp / 400 / text, `maxLines="2"` |
| Macros | `weight="1"` | tres columnas verticales con `weight="1"`, `marginStart="7dp"` entre ellas |
| ↳ cada macro | | etiqueta 10 sp / 400 / muted + `ProgressBar` 6 dp radio 3, `marginTop="3dp"` |
| Rail de agua | **40 dp** × 44 dp | fondo `nm_widget_water_pill` (r 7 dp) · gota 18 dp + cuenta 11 sp / 400 / muted, centradas |
| Barra del día | `match_parent` | 6 dp radio 3, `marginTop="6dp"` |

**La cuenta del ancho, que es la que define si esto entra o no** (es el error que
§9 del brief pide no repetir):

```
340 − 24 (padding)                        = 316 dp
316 − 84 (número) − 40 (rail) − 20 (gaps) = 172 dp para los tres macros
172 − 14 (2 gaps de 7)                    =  52 dp por columna
"P 51/196" en Inter Regular 10 sp tnum    ≈  42,5 dp  → 9,5 dp de sobra
```

Por eso la columna del número es 84 dp y no 100: con 100 el sobrante quedaba en
5 dp y cualquier retoque de tamaño mandaba la etiqueta a `ellipsize`, que es
exactamente el "P 5…" que ya falló. Si en algún teléfono igual ellipsiza, el
ajuste es **bajar el gap interno de macros a 4 dp**, nunca subir `maxLines`.

**El toque del agua**: el rail entero (40 × 44 dp) es el área táctil. Un toque =
un vaso más; al llegar a la meta, el toque siguiente vuelve a 0. Es la misma
lógica de desandar que hoy tiene la gota N, con **un solo `PendingIntent`** en vez
de ocho.

**En 5×1 (430 dp)** el rail se abre en las gotas de la meta: hasta 8 gotas de
16 dp en caja de 18 × 44 dp cada una, con la cuenta al final. Los 90 dp de más
van a las gotas, no a los macros — los macros ya entran en 52. Con meta > 8 se
dibujan 8 y manda la cuenta de al lado, igual que hoy.

---

### 3.3 `nm_widget_calories_oneui` — 4×1 en One UI · 340 × 110 dp

Los 38 dp de más compran dos cosas, no aire: la anatomía de filas y una fila de
extras.

```
padding 10 arriba / 11 abajo / 12 a los lados · gap 12 entre las tres filas
┌────────────────────────────────────────────────────────────────┐
│                P 51/196  ▬▬▬░░░░░░░░░░░           ╭───────╮    │
│ 1.096          C 89/178  ▬▬▬▬▬▬░░░░░░░░           │   💧  │    │
│ kcal restantes G 37/56   ▬▬▬▬▬▬▬▬░░░░░░           │  1/6  │    │
│                                                   ╰───────╯    │
│ ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬░░░░░░░░░░░░░░░░░░░░░░░░░   │
│ Actividad 42 min      Sueño 7,2 h      Racha 12 días           │
└────────────────────────────────────────────────────────────────┘
```

| Bloque | Ancho | Detalle |
| --- | --- | --- |
| Número | **118 dp fija** | valor 28 sp / 500 / tnum · etiqueta 12 sp / 400 |
| Macros | `weight="1"` | tres filas horizontales, `marginTop="6dp"` entre ellas |
| ↳ cada fila | | etiqueta **65 dp fija** 11 sp / 400 / muted + `ProgressBar` `weight="1"` 6 dp radio 3, `marginStart="6dp"` |
| Rail de agua | **52 dp** × 56 dp | r 8 dp · gota 22 dp + cuenta 12 sp |
| Barra del día | `match_parent` | 6 dp radio 3 |
| Extras | | tres `TextView` 11 sp / 400 / muted; los dos primeros `weight="1"`, el último `wrap_content` |

Alto: 110 − 21 de padding = **89 dp**. Fila de contenido 45 (tres filas de macro
de 11 + 2 gaps de 6) + 12 + barra 6 + 12 + extras 13 = 88. Los gaps de 12 dp son
donde se va el alto extra, y por eso son 12 y no 6.

**Los extras no repiten el agua** — la cuenta ya está en el rail —, así que con
tres campos cada uno tiene ~100 dp y ninguno se corta. Cada campo que llega vacío
se esconde solo; con los tres vacíos se esconde la fila y el resto se centra.

Se descartaron las otras dos respuestas al alto extra: **repartir** (el `wide` con
tipos más grandes) paga los 38 dp en aire y en un número de 32 sp, que con la
preferencia de letra del sistema al 200 % es el primer texto que se corta; y
**centrar** es el agujero del medio que ya rompió el diseño anterior, prolijo.

---

### 3.4 `nm_widget_calories_tall` — 4×2 opcional · 340 × 150 dp

El único tamaño donde el mínimo táctil entra de verdad: gotas de 22 dp en cajas
de **48 × 48 dp fijas, sin `weight`**, tocables una por una como hoy.

```
padding 10 · gap 4 entre filas
┌────────────────────────────────────────────────────────────────┐
│ 1.096                                        1.714 de 2.810    │
│ kcal restantes                                  Agua 1 de 6    │
│                                               Racha 12 días    │
│ ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬░░░░░░░░░░░░░░░░░░░░░░░░░   │
│ P 51/196        C 89/178        G 37/56                        │
│ ▬▬▬░░░░░░░      ▬▬▬▬▬░░░░░      ▬▬▬▬▬▬▬░░░                     │
│ ╭────╮                                                         │
│ │ 💧 │  ◌    ◌    ◌    ◌    ◌                                  │
│ ╰────╯                                                         │
└────────────────────────────────────────────────────────────────┘
```

| Fila | Detalle |
| --- | --- |
| 1 | valor 28 sp + etiqueta 12 sp a la izquierda · a la derecha tres líneas de 11 sp / muted: consumido de objetivo, agua, racha |
| 2 | barra del día 5 dp radio 2,5 · `match_parent` |
| 3 | tres macros en columnas (`weight 1`, gap 9 dp): etiqueta 11 sp + barra 5 dp |
| 4 | las ocho gotas: 22 dp dibujadas, caja 48 × 48 dp fija |

**La cuenta de agua va arriba y no al final de las gotas.** 320 dp de ancho útil
menos 6 × 48 de gotas y 6 de gap dejan 26 dp, y "1 de 6 vasos" necesita 33: al
lado, o se corta o le come dp a las cajas — y las cajas de 48 son la única razón
de que este tamaño exista, así que no se negocian.

Ojo con la meta alta: 8 gotas de 48 son 8 × 48 + 7 = 391 dp, más que los 320
disponibles. **Con meta ≥ 7 las cajas bajan a 40 dp** (7 × 40 + 6 = 286) y la
cuenta de arriba pasa a ser la que manda. Es un `setViewLayoutWidth` /
`setViewLayoutHeight` por gota (API 31+) o, más simple, dos variantes del layout.

Alto: 150 − 20 de padding = **130 dp**; la pila mide 128 (43 del bloque del número
+ 5 de la barra + 20 de los macros + 48 de las gotas + 3 gaps de 4). Por eso el
número es 28 sp y no 32: con 32 la fila de gotas se sale de la tarjeta y lo
primero que se pierde es la barra del día.

Vuelve el "1.714 de 2.810" que §9 del brief había sacado: en este alto hay lugar y
no le quita la línea a nadie.

Pide dos cambios en `nm_widget_calories_info.xml`:
`resizeMode="horizontal|vertical"` y `maxResizeHeight="200dp"`.

---

## 4. Elegir el layout (Kotlin)

```kotlin
private const val MIN_DP  = 110f   // piso: abajo de esto no entra ni el número
private const val WIDE_DP = 200f   // abajo de esto, forma angosta
private const val ONEUI_DP = 90f   // una fila de One UI ronda los 110 dp
private const val TALL_DP = 150f   // de acá para arriba son dos filas de verdad

RemoteViews(
    mapOf(
        SizeF(MIN_DP,  40f)      to build(R.layout.nm_widget_calories_compact, detail = false),
        SizeF(WIDE_DP, 40f)      to build(R.layout.nm_widget_calories_wide),
        SizeF(WIDE_DP, ONEUI_DP) to build(R.layout.nm_widget_calories_oneui),
        SizeF(WIDE_DP, TALL_DP)  to build(R.layout.nm_widget_calories_tall),
    ),
)
```

El umbral de One UI en 90 dp y no en 110 a propósito: los 110 dp nominales de una
celda de One UI varían por launcher y por versión, y un widget que cae en `wide`
en un Samsung deja 38 dp de aire — que es el bug que estamos arreglando.

Abajo de API 31 se elige a mano con `OPTION_APPWIDGET_MIN_WIDTH` /
`MIN_HEIGHT`, como hoy, y hay que seguir redibujando en
`onAppWidgetOptionsChanged`.

`updatePeriodMillis` queda en 30 min: no está para traer datos, está para que el
widget se dé cuenta solo de que cambió el día.

---

## 5. El agua, en detalle

| Tamaño | Cómo se muestra | Toque |
| --- | --- | --- |
| 2×1 | cuenta en texto (`1/6`) | ninguno (solo abre la app) |
| 4×1 | rail 40 × 44: gota llena + cuenta | +1 vaso; al llegar a la meta, vuelve a 0 |
| One UI | rail 52 × 56 | igual |
| 5×1 | hasta 8 gotas de 16 dp, caja 18 × 44 + cuenta | el vaso N, como hoy |
| 4×2 | hasta 8 gotas de 22 dp, caja 48 × 48; cuenta arriba | el vaso N, como hoy |

Las ocho gotas siguen declaradas una por una en los cuatro layouts (RemoteViews no
puede crear vistas). Se dibujan `max(waterGoal, glasses)` y no más: ocho gotas
fijas con una meta de cinco dirían que faltan tres que nadie se propuso.

La mecánica de `pendingWater` no cambia: el widget anota la intención y la app la
aplica cuando corre. En el rail, el target es `glasses + 1`, o `0` si ya está en la
meta; el `requestCode` del `PendingIntent` sigue siendo el número de vasos.

---

## 6. Estados vacíos

Los dos llevan el **ícono de la app a 28 dp** (el mismo `ic_launcher`, sin
recortar). Es lo que separa "este widget está esperando algo" de "esta app se
rompió", y es el único lugar donde aparece la marca: en el estado normal no va.

Se esconde **todo** lo que sería de otro día: número, gotas, cuenta, macros, barra
del día y extras.

| Caso | Título 13 sp / 500 | Detalle 11 sp / 400 muted |
| --- | --- | --- |
| Dato de otro día | Abrí Ceres para ver hoy | Lo último guardado es del miércoles |
| Todavía sin datos | Registrá tu primera comida | Después el día aparece acá |

El día viejo se nombra con palabra, no con fecha ISO: la app manda `staleLabel` ya
formateado, como todo el resto. Si no llega, el detalle se esconde y queda solo el
título.

En 2×1 cae el detalle: ícono + "Abrí Ceres".

Los dos casos son distintos a propósito: "no hay nada todavía" y "hay algo pero es
viejo" mandan a buscar el problema a lugares distintos.

---

## 7. Recursos

### Colores

Nuevo, en `values/nm_widget.xml` y `values-night/nm_widget.xml`:

| Nombre | Claro | Oscuro | Para qué |
| --- | --- | --- | --- |
| `nm_widget_water_fill` | `#143C6EA8` | `#1F7FA8D9` | fondo del rail de agua (water al 8 % / 12 %) |

El resto ya existe y no cambia: `nm_widget_surface`, `_text`, `_text_muted`,
`_accent`, `_track`, `_water`.

Los tres colores de macro siguen hardcodeados en su drawable e iguales en los dos
temas. **Manda el código, no la tabla del brief**: los `nm_widget_bar_*.xml`
tienen `#968AE0` (proteínas, `intake`), `#7FA8D9` (carbohidratos, `running`) y
`#D9B46A` (grasas, `sports`) — los mismos que usa `MacroBar` en Inicio vía
`NmChartColors`. La §7 del brief lista `#5B9BD5` y `#D9A441` para carbohidratos y
grasas: están desactualizados y **no se tocan**, cambiarlos desincronizaría el
widget de la pantalla de Inicio, que es justo lo que hay que evitar.

### Drawables nuevos

- `nm_widget_bar_calories.xml` — igual a `nm_widget_bar_protein.xml`, con
  `@color/nm_widget_accent` en el `progress` y radio 3 dp. **Este sí va por
  recurso y no por hex**: el acento cambia entre temas.
- `nm_widget_water_pill.xml` — rectángulo `nm_widget_water_fill`, radio 7 dp
  (8 dp en la variante de One UI, o el mismo si se prefiere un archivo).

---

## 8. Tipografía

Copiar de `assets/fonts/` a `android/app/src/main/res/font/`:

```
Inter-Regular.ttf   → inter_regular.ttf
Inter-Medium.ttf    → inter_medium.ttf
Inter-SemiBold.ttf  → inter_semibold.ttf
```

`android:fontFamily="@font/inter_medium"` en el número,
`@font/inter_regular` en todo el resto. SemiBold no se usa en el widget; se copia
igual para no dejar la familia incompleta.

El número lleva siempre cifras tabulares (`android:fontFeatureSettings="tnum"`):
sin eso las cifras bailan de un update al otro.

Los tamaños de texto son fijos por layout (§3). El texto escala hasta 200 % con la
preferencia del sistema, así que `maxLines` y `ellipsize="end"` se mantienen en
todos los `TextView`.

---

## 9. Cambios en el mensaje que manda la app

Cinco campos nuevos, todos **ya formateados desde Dart** como el resto, todos
**opcionales**: si faltan, la vista que los usa se esconde y el layout se acomoda.

| Campo | Tipo | Ejemplo | Dónde se usa |
| --- | --- | --- | --- |
| `caloriesPercent` | número 0–100 | `61` | barra del día, los cuatro layouts |
| `activityLabel` | texto | `Actividad 42 min` | extras (One UI) |
| `sleepLabel` | texto | `Sueño 7,2 h` | extras (One UI) |
| `streakLabel` | texto | `Racha 12 días` | extras (One UI) y 4×2 |
| `staleLabel` | texto | `Lo último guardado es del miércoles` | estado "dato de otro día" |

El 4×2 usa además el consumido contra el objetivo. Si no se quiere sumar otro
campo, se puede armar con lo que ya llega; si se suma, que venga formateado desde
la app como el resto (`intakeLabel` = `1.714 de 2.810`).

`caloriesPercent` va recortado 0–100 del lado de la app, igual que los de macro:
del lado del widget solo se dibuja. Los textos **no se formatean en Kotlin**: dos
formateadores terminan diciendo cosas distintas del mismo número.

En `CaloriesWidgetStore` son cinco `putString`/`putInt` más con sus lecturas por
omisión vacías. La mecánica no cambia: `pendingWater`, la comparación de fecha por
texto y el `updatePeriodMillis` quedan como están.

---

## 10. Lo que no se construye: el anillo

Se evaluó y se descarta.

- **Bitmap generado por la app** — rompe §4.1 del brief. El bitmap queda congelado
  hasta que la app corra, y un anillo de ayer sobre un número de hoy es
  exactamente la mentira que la regla prohíbe.
- **36 imágenes fijas** — 36 vectores por densidad y un `when` de 36 ramas para un
  gráfico que dice lo mismo que el número que tiene al lado.
- **En 340 dp no entra**: el anillo se come la columna de macros.

La barra del día de §1 da la misma lectura por el precio de un `ProgressBar`. Si
más adelante quieren revisarlo, el costo está acá y no hace falta reconstruirlo de
memoria.

---

## 11. Checklist

**Recursos**

- [ ] Tres Inter en `res/font/` y declaradas en los cuatro layouts.
- [ ] `nm_widget_water_fill` en `values/` y `values-night/`.
- [ ] `nm_widget_bar_calories.xml` (acento por recurso) y
      `nm_widget_water_pill.xml`.

**Layouts**

- [ ] Reescribir `compact` y `wide`; agregar `oneui`; agregar `tall` si se aprueba
      el 4×2.
- [ ] Verificar que los cuatro declaran **el mismo juego de ids**, incluidas las
      ocho gotas y el bloque de macros.
- [ ] Ids nuevos: `nm_widget_calories_bar`, `nm_widget_extras`,
      `nm_widget_extra_activity`, `nm_widget_extra_sleep`,
      `nm_widget_extra_streak`, `nm_widget_intake`, `nm_widget_water_pill`,
      `nm_widget_empty_icon`, `nm_widget_empty_detail`.

**Código**

- [ ] `RemoteViews(mapOf(...))` con los cuatro `SizeF` de §4, y la rama pre-API 31.
- [ ] El toque del rail: un solo `PendingIntent`, target `glasses + 1`, o `0` si ya
      está en la meta.
- [ ] Estados vacíos con ícono y las dos copias de §6.
- [ ] Objetivo ausente: esconder el número **y** la barra del día.
- [ ] `caloriesPercent` y los cuatro textos nuevos en `CaloriesWidgetStore` y en el
      canal de Dart.

**Verificación en el teléfono**

- [ ] Que "P 51/196" entre en una línea en los cuatro layouts. Si ellipsiza, bajar
      el gap interno de macros a 4 dp — nunca subir `maxLines`.
- [ ] Preferencia de letra del sistema al 200 %, en 160 dp y en 340 dp.
- [ ] Un Samsung real: que caiga en `oneui` y no en `wide`.
- [ ] Redimensionar de 2 a 5 celdas sin reiniciar el launcher.
- [ ] Pasada la medianoche sin abrir la app: que aparezca el estado "dato de otro
      día" y que no quede ni una barra del día anterior.
- [ ] Meta de 10 vasos: que las gotas sean 8 y que la cuenta diga `3/10`.
