# Panel de seguimiento

La web que usa un profesional —una nutricionista— para ver el día a día de
quien le dio acceso desde la app.

## Lo que hay que entender antes de tocarlo

**No hay service-role key en este proyecto, y no puede haberla.** Esa clave
saltea RLS por completo: en un frontend, o en una variable de entorno de Vercel
que cualquiera con acceso al proyecto puede leer, es una llave maestra a los
datos de todos. El panel entra con la **publishable key** y la sesión de quien
mira, y lo que puede ver lo decide Postgres a partir de `care_grants`.

Eso significa que **este código no es lo que protege los datos**. Si mañana una
consulta de acá pide de más, la base devuelve vacío. Las garantías viven en
`supabase/migrations/20260803000100_care_access.sql` y están probadas en
`supabase/tests/care_access_test.sql`, que corre en CI contra una base limpia.

Los **datos del paciente** son de solo lectura. No hay una sola política de
escritura sobre ellos para el profesional, así que no es una convención de la
interfaz: es que la base no tiene por dónde.

**El panel no escribe nada.** Hubo una pestaña de notas propias de la profesional
(`care_notes`, migración 42) y se sacó en agosto de 2026 porque no se usaba; la
tabla, sus políticas y sus tests (`supabase/tests/care_contexto_test.sql`)
siguen en la base, sin pantalla que los use. Si algún día vuelve, las dos reglas
que tenía eran: las lee solo quien las escribió —el paciente no las ve, ni en la
app ni por API—, y revocar el acceso no las borra pero corta la escritura.

## El período efectivo, que es de donde salen todos los denominadores

Los períodos salen del calendario —"los últimos 30 días"— pero **lo que se
cuenta no es el calendario**. Alguien que empezó a usar la app el 18 aparecía,
el 19, con "1 de 30 días · 29 sin registrar", y ninguno de esos 29 era un
incumplimiento.

`lib/tracking.ts` calcula la ventana efectiva **una vez por pantalla** y todo lo
demás deriva de ahí: días con comidas, rachas, huecos, porcentajes por día de
semana, minutos por semana. La fecha de inicio la trae el servidor en
`care_patients.tracking_since`, porque el panel solo consulta el período elegido
y no puede saber sola si la persona empezó antes.

Es la misma fórmula que usa la app (`lib/domain/calculations/tracking_window.dart`)
y la misma que devuelve `public.tracking_since()`. **Las tres tienen que decir lo
mismo**: si el informe en PDF que genera el teléfono y esta pantalla contaran
distinto, estarían discutiendo sobre dos números que se llaman igual.
Ver [`docs/contexto-diario.md`](../docs/contexto-diario.md).

## Cómo se conceden los accesos

1. La profesional entra al panel y ve su código (`NT-XXXXXX`) arriba de todo.
   Lo crea `ensure_care_code` la primera vez y después devuelve siempre el
   mismo.
2. El paciente lo carga en la app, en **Perfil → Mi nutricionista**, y elige qué
   categorías prende: comidas, fotos, peso y medidas, actividad/agua/sueño.
3. El paciente puede cambiar qué ve o cortar el acceso cuando quiera, desde la
   misma pantalla.

Una categoría apagada no es lo mismo que un día sin registros, y el panel lo
dice: donde no hay permiso muestra "no está compartido" y no un vacío.

## Correrlo

```bash
cd backoffice
npm install
npm run dev
```

Y abrís **http://localhost:3000**.

### La primera vez: el `.env.local`

Hacen falta dos variables. Son **las mismas dos que ya usa la app** en
`env/local.json`, así que en vez de copiarlas a mano conviene generarlas desde
ahí — un valor tipeado mal da un error de login que no dice que el problema es
la clave:

```bash
# desde backoffice/
URL=$(node -p "require('../env/local.json').SUPABASE_URL")
KEY=$(node -p "require('../env/local.json').SUPABASE_PUBLISHABLE_KEY")
printf 'NEXT_PUBLIC_SUPABASE_URL=%s\nNEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=%s\n' "$URL" "$KEY" > .env.local
```

Si no tenés `env/local.json`, salen del dashboard → Settings → API Keys:

| Variable | Qué va |
| --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | La Project URL |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | La publishable key (`sb_publishable_…`) |

Las dos son públicas por diseño: viajan al navegador igual que en la app.
`.env.local` está en `.gitignore`.

### Antes de subir un cambio

```bash
npm run typecheck
npm test          # node --test, sin dependencias
npm run build
```

`npm test` corre `lib/*.test.ts` con el runner de Node, que lee TypeScript
directo desde la 22. No hay Vitest ni Jest a propósito: lo único que se prueba
acá es aritmética pura —la ventana efectiva—, y un runner entero para eso es más
peso del que resuelve. Lo que sí necesita es que los imports de esos archivos
nombren la extensión (`'./format.ts'`), porque Node resuelve ESM por ruta exacta
y sin bundler.

⚠️ **No corras `npm run build` con `npm run dev` levantado.** Los dos escriben en
`.next/`, y el build de producción le pisa los chunks al de desarrollo. El
síntoma no dice nada de eso: la página muere con un
`Runtime TypeError: a[d] is not a function` adentro del runtime de webpack, que
parece un bug del código y no lo es. Si pasa:

```bash
rm -rf .next && npm run dev
```

y recargá el navegador **forzado** (`Ctrl+Shift+R`): la pestaña se queda con el
bundle roto en memoria aunque el servidor ya esté sano.

### Si entrás y no ves ningún paciente

Es lo esperado hasta que alguien te dé acceso. El circuito completo es:

1. Entrás al panel → arriba aparece tu código `NT-XXXXXX`
2. El paciente lo carga en la app: **Perfil → Mi nutricionista → Dar acceso con
   un código**
3. Recargás el panel

Si la cuenta es nueva y **no puede entrar**, fijate que esté confirmada:
Authentication → Users. Una cuenta creada desde el dashboard nace confirmada;
una creada por la API queda esperando el mail de verificación.

## Desplegarlo en Vercel

El plan gratuito alcanza. Al importar el repo hay que apuntar **Root Directory**
a `backoffice/`, porque el repositorio es el de la app y este proyecto vive en
una subcarpeta. Las dos variables de arriba se cargan en Project Settings →
Environment Variables.

Después del primer deploy, agregá la URL de Vercel en Supabase → Authentication
→ URL Configuration → Redirect URLs. Sin eso el login entra pero la sesión no
vuelve a la app.

## La lista de pacientes

Cada ficha de la lista trae **la última semana en siete puntitos**. Es la
pregunta con la que se abre esta pantalla cuando hay más de tres pacientes
—quién dejó de registrar— y antes había que entrar a cada uno para enterarse.
Son siete puntos y no un "hace 3 días" porque el número no distingue a quien
carga salteado de quien dejó de cargar el martes, que es lo que cambia de qué
se habla en la consulta.

Sale de **una sola consulta** para todos los pacientes, acotada a siete días y
a dos columnas (`user_id, local_date`). Una por paciente sería una cascada que
crece con la cartera, y traer las comidas enteras sería bajar el detalle de
cada ítem para dibujar siete cuadraditos. Si esa consulta falla, la lista se
muestra igual sin la semana: no saber quién dejó de registrar es peor que la
lista completa, pero es mucho mejor que no poder entrar a ninguna ficha.

## Cómo está armada la ficha del paciente

**El fetch y el armado están separados.** `app/paciente/[id]/page.tsx` solo
consulta; `components/patient-view.tsx` es una función pura de los datos que no
sabe de Supabase. Eso es lo que permite renderizar la ficha con datos de
ejemplo para mirar el diseño sin una sesión —una ruta de veinte líneas que
llama a `PatientView` con un objeto armado a mano— en vez de mantener una
maqueta HTML parecida que se desincroniza al primer cambio. `PatientsList`
está partido igual y por lo mismo.

Una ficha son 30 días de comidas, o 365, y en una sola tira eso es imposible de
leer. La pantalla se reparte en **seis pestañas**, en el orden en que se usan
en una consulta: Resumen, Día a día, Hábitos, Comidas, Fotos, Cuerpo. **Cuatro
de ellas son exactamente las cuatro categorías con las que se concede el
permiso** (`share_wellbeing`, `share_meals`, `share_photos`, `share_body`): así
"esta pestaña está apagada" y "esto no me lo compartieron" son la misma frase.

Por eso el contexto del día —enfermedad, descanso, alcohol— entró en
`share_wellbeing` en vez de estrenar una quinta categoría, que habría roto la
correspondencia para agregar un interruptor que nadie pidió. La categoría que el
paciente no comparte **no se esconde**: la pestaña queda con un punto ámbar y
adentro dice qué falta y dónde se prende. Una pestaña ausente se leería como
"esto no existe" en vez de "esto no me lo dieron".

El Resumen es **un tablero de pocas tarjetas** (`Kpi` en `components/stat.tsx`):
cada una dice tres cosas —el número, una línea de contexto y una mini-visual:
la pista contra el objetivo, los puntos de los últimos catorce días, una
sparkline (`components/spark.tsx`)—. Fue primero una fila de fichas de un
número, después dieciséis fichas en cuatro grupos, y las dos eran una pared
que había que leer entera para armarse la imagen. La sparkline es la única
excepción a "el SVG se dibuja al ancho real de la caja": no tiene texto que se
deforme, así que un `viewBox` estirado está bien y se ahorra un observer por
tarjeta. No reemplaza a un gráfico —no se lee un valor de ahí—: dice la forma
al lado del número que sí se lee. Los dos gráficos grandes siguen debajo.

Tres decisiones que conviene no deshacer sin querer:

- **Cambiar de pestaña no vuelve al servidor.** Todo se pide una sola vez en
  `page.tsx` y las seis llegan renderizadas; `components/tabs.tsx` solo cambia
  cuál está visible, y deja la pestaña en la URL con `replaceState` para que
  recargar caiga donde uno estaba. Si cada pestaña fuera una navegación, ir de
  "Comidas" a "Cuerpo" volvería a pedir comidas, peso y medidas y a firmar de
  nuevo las URLs de todas las fotos para mostrar algo que ya estaba en la
  página. El período **sí** navega, porque ahí cambian los datos.
- **Los paneles inactivos se ocultan con `hidden`, no se desmontan.** Lo que
  alguien abrió sigue abierto al volver.
- **Los colapsables son `<details>` nativos**, sin estado de React. Abren sin
  JavaScript, el teclado y el lector de pantalla ya saben qué son, y el Ctrl+F
  del navegador entra igual en lo cerrado. Como efecto de borde, la pantalla
  carga liviana: las fotos son `loading="lazy"` adentro de un `<details>`
  cerrado, así que el navegador no baja una imagen por comida hasta que alguien
  abre esa comida.

El día a día es **un calendario** (`components/day-calendar.tsx`): un mes por
bloque, del más reciente al más viejo, una celda por día, y el día se abre en
un modal. Antes era una lista de filas colapsables, una por día con registro.
Servía para leer de corrido pero no para ubicarse: "¿qué pasó el fin de semana
del 15?" era bajar contando, y un hueco de tres días no se veía porque los días
sin registro no tenían fila. En el calendario el hueco es una celda con el
número solo entre dos llenas, y el sábado está debajo del sábado anterior.

Es **una grilla de verdad**: siete columnas separadas por rayas verticales
finas, y la celda no tiene borde ni sombra propios. La primera versión eran
cartas —una por día, con borde y sombra— y las rayas pintadas en el hueco entre
cartas: dos sistemas visuales encimados, y la raya a tres píxeles del borde de
la carta se leía como un borde doble. Lo que se toca se nota al pasar por
encima, no con un marco.

Cada celda con registro dice lo que se pregunta primero sin abrirla: las
calorías —en ámbar si se pasó—, las cuatro rayitas de los momentos, y el agua,
el sueño y la actividad en una línea. Un punto arriba a la derecha si el día
tuvo enfermedad o alcohol. El modal (`components/day-detail.tsx`) trae los
totales, la distancia al objetivo, el reparto por momento y los macros —los
mismos cuadros de la pestaña Comidas, para un solo día—, las comidas con sus
ítems y fotos, y la actividad, el agua y el sueño de ese día. Las flechas pasan
al día con registro anterior o siguiente. Solo se dibujan las semanas que tocan
el período, y el calendario arranca donde arrancó la persona, no donde arranca
el período: los días anteriores al primer registro no son huecos y no aparecen.

La cabecera es **fija** y mide siempre lo mismo: leyendo el 12 de julio hay que
poder seguir viendo de quién es la ficha, su contexto y qué período está puesto.
Hubo un modo compacto —al bajar escondía la línea de contexto y achicaba el
nombre— y se sacó en agosto de 2026: esa línea es justo lo que uno quiere
seguir viendo, y los 45 px que se ganaban no valían la maquinaria.

⚠️ Si el modo compacto vuelve, hay una trampa que ya costó una tarde: una
cabecera `sticky` que cambia de alto **acorta el documento y se come el
scroll** —medido: documento 619, pantalla 561, y el máximo de scroll pasaba de
58 px a 13 en cuanto uno bajaba—. La compensación tiene que ser CSS, en el mismo
cálculo de layout que el cambio de clase; con un efecto de React, incluso
`useLayoutEffect`, el navegador ya recortó la posición del scroll y devolverle
el alto no la devuelve. La solución completa está en el historial de git
(`.topbar.is-compact + .page` y `--topbar-delta`).

**Lo que se abre, se abre en unos 200 ms y no de golpe**: el cuerpo de un
colapsable, el modal y su fondo, la pestaña que entra; las barras de los
gráficos crecen desde el piso y las pistas de reparto desde la izquierda. Está
todo junto al final de `globals.css`, bajo "Movimiento", y se apaga entero con
`prefers-reduced-motion`. El cierre del modal es inmediato: animar el cierre de
un `<dialog>` nativo requiere demorar el `close()`, y no vale lo que cuesta.

### La pestaña de fotos

`share_photos` era la única categoría de permiso sin pestaña propia: las fotos
existían nada más que adentro del día a día, de a una y a dos clics. Puestas
todas juntas contestan otra pregunta —veintiocho desayunos uno al lado del otro
dicen de un vistazo que siempre es lo mismo, que el fin de semana cambia, que
hay tres días con la misma milanesa— y para eso hay que poder comparar sin
abrir nada.

- **La grilla es solo la foto.** Cualquier número al lado de cada una convierte
  la comparación de imágenes en lectura. Los números están a un clic.
- **Cuadraditos chicos y recortados con `cover`.** Con `contain`, cada celda
  deja franjas de fondo de distinto grosor según la proporción de la foto, y el
  ojo lee las franjas antes que la comida. En el modal sí va `contain`: ahí la
  foto es lo que se está mirando y recortarla escondería el borde del plato.
- **La fecha va encima de la foto**, no debajo: abajo, cada celda mediría el
  alto de la imagen más una línea de texto y la grilla dejaría de ser cuadrada.
- **El orden de los grupos es fijo** —desayuno, almuerzo, cena, snacks—, no por
  cantidad: un orden que cambia entre pacientes obliga a leer los títulos para
  saber dónde mirar.
- **El modal es un `<dialog>` nativo.** Escape, el foco atrapado adentro y el
  fondo inerte ya vienen resueltos por el navegador, y hechos a mano son tres de
  los cuatro errores clásicos de accesibilidad de un modal. El cuarto —dónde cae
  el foco al abrir— se resuelve con `autoFocus` sobre la caja: sin eso,
  `showModal()` se lo da al primer control que encuentra, que es la flecha de
  "anterior".

### El período de un año, y las dos trampas que traía

- **PostgREST devuelve mil filas y corta.** No falla, no avisa, y no hay nada en
  la respuesta que lo diga. Con 7, 30 o 90 días no se notaba —90 días de cuatro
  comidas son 360—, pero un año pasa las dos mil: la ficha habría mostrado medio
  año largo como si fuera el año entero, con los promedios y el conteo de días
  calculados sobre lo que llegó. `fetchMeals` pagina de a mil con un orden total
  (`local_date`, `logged_at`, `id`) para que las páginas no se pisen. Un dato
  faltante que se ve igual de bien que uno completo es peor que un error.
- **El día a día viaja como datos, no como HTML.** Cuando era una lista de
  `<details>`, cada día mandaba la tabla de ítems de cada comida ya renderizada
  —la ficha del año pesaba 4,5 MB en crudo— y por eso se cortaba en 120 días.
  El calendario es un Client Component que recibe **una bolsa por día con
  registro** (`DayBundle`) y dibuja el modal en el navegador, así que lo que
  viaja es el JSON de las comidas, bastante más liviano que la tabla, y ya no
  hay corte: el año entero se puede abrir día por día. Si alguna vez vuelve a
  pesar, lo que hay que recortar es el detalle de los ítems de los días viejos,
  no los días.

Las fotos también se firman **de a 400 y en paralelo**: un año fotografiando
cada comida junta más de mil rutas, y eso en un solo pedido es un cuerpo enorme
que además tarda todo lo que tarda el más lento.

### El día lo define el huso, no el servidor

La app guarda `local_date`: la fecha que era **para quien registró**. El panel
tiene que preguntar por ese mismo día, y por eso `lib/format.ts` calcula "hoy"
en `America/Argentina/Buenos_Aires` y no con `new Date().toISOString()`, que es
la fecha en UTC. Con UTC, en Buenos Aires a partir de las 21:00 "hoy" pasaba a
ser mañana: el período terminaba en un día que todavía no existe y "días con
comidas de 30" contaba uno de más. Desplegado al este de Greenwich el error se
da vuelta y es peor, porque la comida de esta noche queda afuera. Si algún día
hay pacientes en otro huso, eso sale del perfil y no de una constante.

### El contexto del día

Enfermedad, descanso y alcohol. Se abren con `share_wellbeing` y aparecen en
cuatro lugares:

- una banda de 3 px al pie del gráfico de actividad, que es el hueco que más se
  parece a abandono y el que más seguido tiene explicación;
- un punto en el casillero del día en el calendario, y el detalle arriba de
  todo al abrirlo, porque el día en que la persona estuvo en cama y no registró
  nada tiene que explicarse antes de leer el resto;
- la tarjeta "Alcohol y enfermedad" del Resumen, que está **siempre, también en
  cero**: antes era una sección que aparecía solo si había algo, y una semana
  limpia no se distinguía de una semana sin compartir;
- la franja de contexto debajo de las tres cartas de Hábitos: los números
  siempre, y el gráfico de tragos por día solo si hubo alcohol. Fue una cuarta
  carta de la misma altura que las otras, y en un período sin nada que contar
  era un cuadro vacío con una frase en el medio; la franja mide lo que tiene
  que decir.

Tres reglas que conviene no deshacer:

- **No cambia ningún cálculo.** Un día de enfermedad no baja el objetivo, no se
  saltea del promedio y no se descuenta de la adherencia. La sección lo dice con
  todas las letras. Una app que "perdona" un día es una app opinando sobre una
  semana que no vio.
- **La marca va debajo del eje, no como color de la barra.** Teñir la barra
  cambiaría lo que la barra mide: un día de enfermedad con 20 minutos de
  caminata sigue siendo 20 minutos. Y va debajo y no encima porque el día
  interesante es justamente el que **no tiene** barra.
- **Las calorías del alcohol van aparte de las comidas.** Sumarlas ahí
  escondería de dónde salieron, que es justo el dato que se busca cuando el peso
  no baja y las comidas estaban bien. El alcohol se cuenta en **UBE de 10 g**
  —la del Ministerio de Salud, no los 14 g de EE.UU.—, que es lo único con lo que
  se pueden sumar una cerveza y un whisky.

## El look and feel

Los tokens están copiados de `docs/handoff/design-tokens.json` a variables CSS
en `app/globals.css`. Se copian y no se importan porque el JSON vive en el repo
de la app y una build de Vercel con Root Directory en `backoffice/` no lo ve. Si
los tokens cambian, se actualizan ahí.

El chrome del panel —cabecera, pestañas, colapsables— está más abajo en ese
mismo archivo y **no inventa ningún color**: lo que necesita sale de los tokens
con `color-mix`, así que un token que cambia lo arrastra solo y no hay una
segunda paleta que mantener sincronizada a mano.

**Una cosa sobre los gráficos.** La paleta de Ceres es pastel y toda en una
banda de luminosidad estrecha: los tres colores de macros (`#9184d9`, `#7fa8d9`,
`#d9b46a`) no se distinguen lo suficiente entre sí ni siquiera con visión de
color normal —ΔE 9.6 entre proteínas y carbohidratos, cuando el piso es 15—.
Por eso acá **no hay ningún gráfico que dependa de distinguir tres colores de
marca**: los de peso y calorías son de una serie sola, y los macros van como
columnas con su nombre. Es lo que permite mantener la identidad sin publicar un
gráfico que no se puede leer.

El único color que codifica algo es el ámbar del día que se pasó del objetivo,
y se sostiene solo: la barra ámbar está **sobre** la línea punteada y la
violeta debajo, así que la posición dice lo mismo que el color. En claro el
ámbar sale de `--chart-over`, que es `caution` aclarado contra la carta: el
token está elegido para que un texto tenga contraste sobre blanco, y como
relleno de una barra ese mostaza pesa el doble que el violeta de al lado y
exagera el día que se pasó.

### Cuatro cosas de los gráficos que cuesta ver y son fáciles de deshacer

- **En los gráficos de barras, el eje X son los días con registro, uno al lado
  del otro.** Esto se decidió dos veces en sentidos opuestos, así que conviene
  saber por qué quedó así. Primero el eje era la posición; después pasó a ser
  el calendario del período, porque siete días sueltos de un mes se dibujaban
  pegados y se leían como una semana seguida. Y en agosto de 2026 volvió a la
  posición, a pedido: con el período de noventa días de alguien que empezó hace
  treinta, el eje calendario era dos tercios de gráfico en blanco y las barras
  apretadas en la punta derecha. Lo que hace tolerable la vuelta es que **quién
  dejó de registrar y cuándo ahora lo muestra el calendario del día a día**, que
  es el lugar donde los huecos se ven; el gráfico contesta "cuánto" y el
  calendario "qué días". Los extremos del eje son el primer y el último día con
  datos, y el globito dice de qué fecha es cada barra. Las bandas de contexto
  —enfermedad, alcohol— le agregan su día al eje aunque no tenga barra, que es
  justo el día que hay que poder explicar.
- **Peso y medidas siguen siendo un eje de tiempo**, porque ahí la pendiente es
  todo lo que se mira y cinco pesajes de una semana y uno de un mes después no
  pueden quedar equidistantes. Lo que cambió es que el eje va del primer al
  último registro y no de punta a punta del período: la proporción entre fechas
  se mantiene (`diasEntre` en `lib/format.ts`) y el blanco de antes del primer
  pesaje no se dibuja.
- **El día sin registro sigue sin ser una barra en cero.** Cero diría que comió
  cero, que no es lo que pasó. Simplemente no está.
- **El SVG se dibuja al ancho real de la caja** (`lib/chart.ts`,
  `useChartWidth`), no en un `viewBox` fijo estirado con `width="100%"`. Un
  `viewBox` fijo escala **también el texto**: la misma etiqueta de 11 px salía
  de 16 px en una carta a todo lo ancho y de 7 px en una de dos columnas, y ahí
  los ejes de "Cintura" y de "Agua" quedaban ilegibles. El observer devuelve 0
  mientras la pestaña está oculta —`display: none` mide cero— y ese cero se
  ignora a propósito; vuelve a disparar con la medida buena al mostrarse.
- **Los ejes terminan en un número redondo y el que menos aire deje**
  (`ejeLindo`). Con `max * 1.1` las etiquetas salían `1.018` y `2.035`. Y entre
  dos pasos redondos se elige el más ajustado: para un máximo de 2.050 kcal, el
  paso de 1.000 termina en 3.000 y deja un tercio del gráfico en blanco con las
  barras aplastadas contra el piso.
- **Las barras tienen ancho máximo.** En el período de 7 días son cinco barras
  repartiéndose mil píxeles: sin el tope de 56 px cada una queda de 190 px de
  ancho, que son bloques y no un gráfico de barras.

**Una medida corporal no es un gráfico de barras.** Un perímetro es una
posición en una escala, no una magnitud que se acumule: la barra desde cero de
una cintura de 88 cm y la de una de 85 cm miden 97 % lo mismo, así que se
dibujaban tres bloques idénticos y los 3 cm —todo lo que se quería ver— caían
adentro del error de lectura. Van como tarjeta: el valor de hoy, la variación
del período y una línea con el eje recortado, que ahí sí se puede recortar
porque no se compara el largo de nada contra cero.

## Lo que la pantalla no califica

El panel muestra distancias, no notas. Es fácil deshacerlo sin querer, así que
conviene saber dónde estaba el error antes:

- **Quedarse por debajo del objetivo no es un logro.** El día a día pintaba de
  verde un "−693 vs objetivo". En una consulta eso no es haberla sacado barata:
  es sub-registro o una restricción, que es justamente de lo que la profesional
  tiene que enterarse. La distancia va en el color del texto y el único acento
  es el ámbar de haberse pasado.
- **El IMC va con su categoría y sin color.** No distingue músculo de grasa, y
  pintar de rojo el 26 de alguien que entrena sería un diagnóstico que esta
  pantalla no está en condiciones de dar.
- **La variación de una medida tampoco lleva verde ni rojo.** Que la cintura
  baje es bueno en un plan de descenso y malo en uno de ganancia de masa, y el
  panel no sabe cuál de los dos está mirando.
- **El calendario del día a día no califica el día.** El casillero con registro
  y el vacío se distinguen por el borde —lleno contra punteado—, no por un
  color: no hay verde de "registró" ni rojo de "faltó". Los únicos colores son
  el ámbar de las calorías del día que se pasó del objetivo, que es el mismo del
  gráfico, y los dos puntos de contexto —enfermedad y alcohol—, que son los
  mismos de las bandas de Hábitos.
