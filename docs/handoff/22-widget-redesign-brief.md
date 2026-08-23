# Brief para rediseñar el widget de pantalla de inicio

Para quien diseñe. Lo que sigue es el material con el que se cuenta, las reglas
del producto y —sobre todo— **qué se puede y qué no se puede dibujar**, porque el
widget no lo dibuja Flutter: lo dibuja el launcher de Android con una API que
tiene límites duros. Un diseño hecho sin conocerlos sale lindo y no se puede
implementar.

---

## 1. Qué es

Un widget de la pantalla de inicio de Android para **Ceres**, una app de
registro de comida, actividad y peso. Muestra el resumen del día.

- Lo dibuja **el launcher, en su proceso, con la app cerrada**. No puede consultar
  nada: lee un dato que la app dejó escrito la última vez que corrió.
- **Tocar el widget abre la app.** Tocar una gota de agua registra un vaso **sin
  abrir la app** — es la única interacción que existe hoy y la única función de la
  app que se usa sin entrar.
- Los teléfonos reales son Samsung (One UI) y Pixel. La app se distribuye fuera de
  Play Store.

## 2. Qué está mal hoy

Palabras textuales de quien lo usa, sobre la versión actual:

> "Está enorme el widget, necesitamos que no ocupe más de una fila horizontal,
> tenemos que distribuir mejor la data, y que se adapte si el usuario lo agranda."

Y antes, sobre la versión anterior:

> "Es un cuadrado gordo grande y la info no está bien distribuida, queda feo y es
> incómodo de usar."

Capturas en [`widget-actual/`](widget-actual/), tomadas del emulador Pixel 7 con
datos reales:

| Archivo | Qué es |
| --- | --- |
| `nm-widget-anterior-cuadrado.png` | **el que motivó todo esto**: 4×2, el número perdido en el medio |
| `nm-widget-actual-ancho.png` | 4×1, el estado de hoy y el default |
| `nm-widget-actual-angosto.png` | 2×1, se caen gotas y macros |
| `nm-widget-actual-alto.png` | 4×2 de la versión intermedia, ya sin estirar pero con aire de sobra |

## 3. El material: qué datos hay

Esto es **todo** lo que el widget recibe hoy. Los textos llegan **ya formateados
desde la app** a propósito: el separador de miles y las palabras salen del mismo
lugar que los de la pantalla de Inicio, así que no pueden desincronizarse.

| Campo | Tipo | Ejemplo | Nota |
| --- | --- | --- | --- |
| `date` | texto | `2026-07-31` | El día al que pertenece el dato. Ver §4. |
| `value` | texto | `1.096` | El número grande. Ya formateado. |
| `label` | texto | `kcal restantes` | O `kcal de más` si se pasó, o `Sin objetivo configurado`. |
| `waterGlasses` | número | `1` | Vasos tomados. |
| `waterGoal` | número | `6` | Meta del día. **Puede ser mayor que 8.** |
| `waterMax` | número | `40` | Tope defensivo. |
| `proteinLabel` | texto | `P 51/196` | Gramos comidos / objetivo. |
| `proteinPercent` | número | `26` | 0–100, ya recortado. Para dibujar. |
| `carbsLabel` / `carbsPercent` | | `C 89/178` / `50` | |
| `fatLabel` / `fatPercent` | | `G 37/56` / `66` | |

**Qué se podría agregar sin costo**, si el diseño lo pide (la app ya tiene estos
números y solo hay que sumarlos al mensaje): calorías consumidas y objetivo por
separado, peso de hoy, minutos de actividad, sesiones de ejercicio, horas de
sueño de anoche, vasos en mililitros, racha de días registrados.

**Qué no hay**: nada por comida (el widget no sabe qué se comió), nada de pals,
nada de historial. Traer eso implicaría trabajo de la app, no del widget.

## 4. Las reglas que el producto no negocia

1. **El widget no miente.** El dato guardado lleva su fecha; si no es la de hoy no
   se muestra **nada** de él —ni el número, ni las gotas, ni las barras— y en su
   lugar dice "abrí Ceres". Un widget con el número de ayer no se distingue de
   uno al día, y eso es peor que uno vacío. **Hay que diseñar ese estado**, y
   también el de "todavía sin datos" (app recién instalada), que es distinto.
2. **Ningún número inventado.** Si no hay objetivo cargado, el widget lo dice; no
   muestra un valor por omisión disfrazado de cuenta.
3. **El exceso se cuenta, no se reta.** Pasarse del objetivo cambia la palabra
   (`kcal de más`), no el tono. Nada de rojo de alarma ni de íconos de
   advertencia.

## 5. Restricciones técnicas — leer antes de dibujar

El widget se construye con **RemoteViews**. Es una API de 2008 y es rígida.

**Solo existen estas vistas.** `LinearLayout`, `RelativeLayout`, `FrameLayout`,
`GridLayout`, `TextView`, `ImageView`, `ImageButton`, `Button`, `ProgressBar`,
`Chronometer`, `AnalogClock`, `ViewFlipper`, `ListView`, `GridView`, `StackView`.
**No hay** `ConstraintLayout`, ni vistas propias, ni Compose.

**No hay bucles.** El código no puede crear ni repetir vistas: todo lo que se
repite tiene que estar escrito una por una en el XML. Por eso hay exactamente
ocho gotas de agua dibujadas, y por eso al lado va la cuenta en texto — la meta
puede ser mayor que ocho y las gotas solas no podrían decirlo.

**No se puede dibujar libremente.** Esto es lo que más suele romper un diseño:

- ❌ **Un anillo de progreso** como el de la pantalla de Inicio **no se puede**.
  No hay canvas. Las alternativas son las tres feas: (a) que la app genere un
  bitmap y lo mande —posible, pero solo se actualiza cuando la app corre y ocupa
  memoria del launcher—; (b) 36 imágenes fijas, una por cada 10 %; (c) no usarlo.
- ✅ **Barras de progreso**: sí, con `ProgressBar` y un drawable por color.
- ✅ **Íconos**: sí, como `ImageView` con un vector estático.
- ❌ Degradados dinámicos, sombras propias, blur, formas que dependan del dato.
- ✅ Fondo con color sólido y esquinas redondeadas (hoy: 16 dp).

**Colores**: tienen que ser recursos, con su variante clara y oscura. El tintado
en tiempo de ejecución no se comporta igual en todos los launchers, así que cada
color fijo va en su propio archivo.

**Tipografía**: la app usa **Inter** (Regular / Medium / SemiBold) y los archivos
ya están en el repo. Hoy el widget usa la del sistema; pasar a Inter es copiar
tres archivos. **Si el diseño la quiere, se puede.**

**Tamaños de texto**: fijos por layout, pero se pueden cambiar por código, así que
puede haber un tamaño distinto por cada tamaño de widget. Ojo: el texto escala con
la preferencia de tamaño de letra del sistema, que llega hasta 200 %.

**Toques**: cualquier vista puede tener uno. Hoy: todo el widget → abre la app;
cada gota → registra ese número de vasos. El área táctil mínima recomendada es
48 dp, y las gotas de hoy miden 10 — es una deuda conocida.

**Nada de animación, nada de scroll, nada de estado.** El widget se redibuja
entero cada vez.

**Adaptarse al tamaño sí se puede**, y es la herramienta principal: desde Android
12 se mandan varios layouts juntos y el launcher elige el que entra, al vuelo,
incluso mientras la persona lo redimensiona. **Diseñar por tamaño es gratis; todo
lo demás es caro.**

## 6. Los tamaños para los que hay que diseñar

En dp (densidad independiente). El widget hoy está fijado a **una fila de alto y
no se puede estirar verticalmente** — eso viene del pedido y conviene mantenerlo
salvo que el diseño argumente lo contrario.

| Caso | Caja aproximada | Frecuencia |
| --- | --- | --- |
| 4×1 en Pixel | **340 × 72 dp** | el default |
| 4×1 en One UI (Samsung) | **340 × 110 dp** | el teléfono real de los usuarios |
| 2×1 achicado | **160 × 72 dp** | quien lo quiere chico |
| 5×1 o pantalla ancha | **430 × 72 dp** | poco |

La diferencia entre 72 y 110 dp de alto en la misma "fila" es real y ya rompió el
diseño anterior: lo que se pensó para una tira quedó con un agujero en el medio en
el Samsung. **Conviene que el diseño diga qué hacer con esos 38 dp de más.**

## 7. Tokens del sistema de diseño

Salen de `docs/handoff/design-tokens.json`. El widget tiene que verse de la misma
app que la pantalla de Inicio.

| Rol | Claro | Oscuro |
| --- | --- | --- |
| Superficie (fondo del widget) | `#FFFFFF` | `#232532` |
| Texto | `#1B1C26` | `#E9E9ED` |
| Texto atenuado | `#1B1C26` al 58 % | `#E9E9ED` al 55 % |
| Acento (el número grande) | `#796CBF` | `#9184D9` |
| Riel de una barra vacía | `#1B1C26` al 12 % | `#E9E9ED` al 16 % |
| Agua | `#3C6EA8` | `#7FA8D9` |
| Proteínas | `#968AE0` | igual |
| Carbohidratos | `#5B9BD5` | igual |
| Grasas | `#D9A441` | igual |

Radio del fondo: **16 dp**. El widget sigue el tema del sistema, como el launcher.

## 8. Qué necesitamos de vuelta

No hace falta nada pixel-perfect. Hacen falta **decisiones**:

1. **Un layout por cada tamaño** de la tabla de §6, con las cajas anotadas:
   espaciados en dp, tamaño de texto y qué es cada cosa (texto / barra / ícono).
2. **Orden de prioridad de la información**: qué se cae primero cuando hay menos
   ancho, y qué no se cae nunca. Hoy la decisión es "las gotas y los macros se van
   enteros antes que mostrarse cortados"; se puede discutir.
3. **Qué hacer con el alto extra de One UI**: repartir, centrar, o meter un dato
   más de la lista de §3.
4. **Los dos estados vacíos** de §4 ("dato de otro día" y "todavía sin datos").
5. **Claro y oscuro**, aunque sea el mismo layout con otros tokens.
6. Si el diseño necesita algo de §5 marcado con ❌, decirlo explícitamente y
   nosotros evaluamos el costo — a veces vale la pena, pero tiene que ser una
   decisión y no una sorpresa a mitad de la implementación.

## 9. Cosas que ya probamos y no funcionaron

Para no repetirlas:

- **Un cuadrado de 4×2.** El pedido original que lo desencadenó todo. El número
  queda perdido en el medio y sobra pantalla.
- **El nombre "CERES" en la primera fila.** Las ocho gotas no le dejaban lugar
  y se leía **"NUT"**. Además, el nombre sobra en una pantalla donde la persona
  puso el widget a propósito.
- **Un "—" grande cuando no hay dato.** A 26 sp y en color de acento se leía como
  una raya de la interfaz, no como "acá iba un número". Ahora se esconde.
- **"Comió 1.714 de 2.000".** Es la misma cuenta que el número grande contada al
  revés, y ocupaba una línea entera. Se sacó. (Si el diseño la quiere de vuelta en
  el tamaño grande, es defendible: ahí hay lugar.)
- **Seis datos peleando por 160 dp.** Las gotas se cortan al medio y "P 51/196"
  queda en "P 5…".
