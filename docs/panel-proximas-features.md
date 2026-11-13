# Qué más le serviría a la nutricionista

Análisis, no implementación. La pregunta que ordena todo esto es la que se hace
alguien diez minutos antes de una consulta:

> ¿Qué pasó en las últimas semanas, y qué tengo que preguntar hoy?

Lo que sigue sale de mirar **lo que ya guardamos** y no de una lista de features
de productos parecidos. Cada propuesta dice qué problema resuelve, qué datos
necesita, cómo se vería y qué cuesta.

La prioridad está al final.

**Estado (noviembre de 2026):** §1, §2, §3 y §4 están en la ficha (Resumen y
Comidas, `backoffice/lib/analysis.ts`); §5 es la tarjeta "Cintura / altura" de
Cuerpo y §6 la línea de días muy por debajo del basal del Resumen (menos del
85 % del basal, para no avisar por un día de déficit normal). Quedan §7, §8 y
§9.

---

## Lo que hoy la pantalla no contesta

El panel contesta bien tres preguntas: *¿está registrando?*, *¿cuánto come?* y
*¿cómo viene el peso?*. Las que quedan afuera, en orden de cuánto se extrañan:

1. **¿Los números cierran?** Hay un objetivo de 2.000 y un promedio de 1.700,
   pero el peso no se movió en tres semanas. Una de las dos cosas está mal y la
   pantalla no ayuda a decidir cuál.
2. **¿Qué come, concretamente?** Hay promedios de macros y una galería de fotos,
   pero no la lista de lo que se repite. "¿Qué desayunás?" hoy se pregunta y se
   contesta de memoria, teniendo el dato medido a un clic.
3. **¿A qué hora come?** Todos los `logged_at` están guardados y no se usa
   ninguno. La ventana de alimentación y los horarios son la mitad de una
   consulta y hoy no se ven.
4. **¿Esta semana comparada con cuál?** El período es un bloque de 30 o 90 días.
   Una consulta piensa en semanas: "la primera semana bien, la segunda se cayó".

---

## Las propuestas

### 1 · Balance energético estimado contra peso real

**El problema.** Es la pregunta clínica número uno y hoy hay que hacerla a mano
en un papel. Si el registro dice un déficit de 500 kcal/día durante 4 semanas,
eso son ~2 kg esperados. Si la balanza dice −0,3 kg, no es que "no funcionó": es
que **falta comida sin registrar**, y esa es una conversación completamente
distinta a "hay que bajar más las calorías". Sin este cruce, el riesgo real es
recortar el objetivo de alguien que ya come menos de lo que anota.

**Qué necesita.** Todo está guardado: `goals.tdee_kcal` y `goals.bmr_kcal` los
escribe la app al crear el objetivo, `meals.total_kcal` por día,
`activities.estimated_calories`, y `weight_logs` para el cambio observado.
No hace falta portar ninguna fórmula al panel — que es justamente lo que lo
vuelve barato y lo que evita que el teléfono y la web calculen distinto.

**Cómo se vería.** Una tarjeta con tres números y una frase:

```
Déficit registrado    ≈ 480 kcal/día        sobre 26 días con registro
Cambio esperado       −1,8 kg
Cambio medido         −0,4 kg               ← la brecha es el dato
```

Y debajo, en texto y sin color de alarma: *"La diferencia suele venir de
comidas sin registrar antes que de metabolismo. Vale mirar los fines de
semana."* Nada de semáforos: es una hipótesis a chequear en la consulta, no un
diagnóstico, y el panel no califica.

**Valor.** Muy alto. Es el cruce que hoy se hace de memoria y con más error.
**Esfuerzo.** Bajo-medio. Una tarjeta y aritmética sobre datos que ya llegan.

---

### 2 · Horarios de comida y ventana de alimentación

**El problema.** La hora de cada comida está guardada desde el primer día y no
se usa en ninguna pantalla de análisis. Con eso se contesta: a qué hora arranca
el día, a qué hora termina, cuánto dura la ventana, y —lo más útil— **cuánto
varía**. Alguien que come de 8 a 21 todos los días y alguien que un día arranca
a las 8 y otro a las 14 tienen el mismo promedio y son dos casos distintos.

**Qué necesita.** Nada nuevo: `meals.eaten_at` y `slot`.

El dato es bueno y la razón por la que no se usaba era el nombre: la columna se
llamaba `logged_at` —"cuándo se cargó"— cuando en realidad guarda la hora que la
persona eligió en el formulario, con el botón "Cambiar hora". Con ese nombre
parecía un dato de auditoría. La migración 44 la renombró a `eaten_at`, así que
esta feature ya no tiene nada que resolver antes de empezar.

**Cómo se vería.** Una tira horizontal por día, 0 a 24 h, con un punto por
comida coloreado por momento. Treinta tiras apiladas muestran de un vistazo la
forma del día y sus corrimientos. Es el mismo criterio del calendario de
adherencia: la forma antes que el número.

**Valor.** Alto.
**Esfuerzo.** Bajo.

---

### 3 · Los alimentos que se repiten

**El problema.** "¿Qué desayunás normalmente?" se contesta de memoria en la
consulta, teniendo la respuesta medida. Los `meal_items` tienen el nombre de
cada cosa: contarlos da la lista real de lo que come esta persona, ordenada por
cuánto aporta.

**Qué necesita.** `meal_items.name` y `kcal`, agrupados. Nada nuevo.

**Cómo se vería.** Una tabla corta en la pestaña de Comidas: alimento, cuántas
veces, kcal totales que aportó en el período, y en qué momento aparece. Quince
filas. Es donde se ve que el 18 % de las calorías del mes vienen del pan.

**Un cuidado.** Los nombres vienen de tres catálogos y del modelo, así que "Pan
integral" y "Pan lactal integral" son dos filas. Se agrupa por **nombre
normalizado** y no por un id de alimento: `meal_items` no guarda ninguno, y a
propósito —el ítem es un snapshot de lo que se comió ese día, y la migración 43
sacó las dos claves foráneas que apuntaban al catálogo justamente porque un
snapshot con puntero al original es una contradicción—. Y no inventar una
categorización automática, que sería una capa de adivinanza arriba de un dato
bueno.

**Valor.** Muy alto: convierte el panel en algo que la consulta no puede
conseguir de otra forma.
**Esfuerzo.** Bajo.

---

### 4 · Semana contra semana

**El problema.** El período es un bloque; la consulta piensa en semanas. "Las
dos primeras bien y después se cayó" hoy hay que deducirlo mirando un gráfico de
barras de treinta días.

**Qué necesita.** Nada nuevo. Es una reagrupación de lo que ya se calcula.

**Cómo se vería.** Una tabla de 4–8 filas, una por semana ISO: días con
registro, promedio de kcal, proteínas/día, minutos de actividad, peso al cierre,
y las marcas de contexto de esa semana (enfermedad, alcohol). La semana
incompleta —la primera y la última— se marca como tal, con el mismo criterio que
la ventana efectiva: no se compara media semana contra una entera sin decirlo.

**Valor.** Alto. Es la vista con la que se habla.
**Esfuerzo.** Bajo.

---

### 5 · Cintura/altura, en vez de darle todo el peso al IMC

**El problema.** El IMC ya está y ya va sin color, por buenas razones. Pero la
relación **cintura/altura** es mejor indicador de riesgo cardiometabólico, se
calcula con dos datos que ya tenemos, y —a diferencia del IMC— no confunde
músculo con grasa. Hoy la cintura está en la pestaña de Cuerpo como una tarjeta
suelta y no se cruza con nada.

**Qué necesita.** `body_measurements` (waist) y `profiles.height_cm`. Nada nuevo.

**Cómo se vería.** Un número más en "Dónde está hoy", con su referencia (0,5) al
lado y sin color, exactamente como el IMC. Y la relación cintura/cadera cuando
las dos medidas existan.

**Valor.** Medio-alto, y es de lo más barato de la lista.
**Esfuerzo.** Muy bajo.

---

### 6 · Días por debajo del metabolismo basal

**El problema.** Un día registrado con 900 kcal casi nunca es un día de 900
kcal: es un día a medio anotar. Hoy ese día baja el promedio y **empeora** la
lectura de todo el período, y no hay nada que lo señale.

**Qué necesita.** `goals.bmr_kcal` y el total por día. Nada nuevo.

**Cómo se vería.** Una línea en el resumen: *"3 días registrados por debajo del
metabolismo basal (1.480 kcal). Suelen ser días a medio anotar más que días de
ayuno; el promedio de arriba los incluye."* Sin excluirlos del cálculo
automáticamente —eso sería la app decidiendo qué datos son verdad— pero
diciéndolo.

**Valor.** Alto: protege de la conclusión equivocada.
**Esfuerzo.** Bajo.

---

### 7 · Los días con X contra los días sin X

**El problema.** Ahora que hay alcohol y días de enfermedad, la pregunta natural
es si mueven algo. Pero con 30 días **no hay potencia estadística para una
correlación**, y publicar un coeficiente sería darle cara de hallazgo a un
número que rebota con un solo día distinto.

**Qué necesita.** Lo nuevo de esta iteración más lo que ya está.

**Cómo se vería.** Comparaciones de dos columnas, con el n a la vista:

```
                      Con alcohol (4 días)   Sin alcohol (22 días)
kcal del día                    2.420                     1.680
Sueño esa noche                6 h 10                    7 h 20
Actividad al día siguiente     12 min                    38 min
```

Y una línea que diga que con cuatro días esto es una observación, no un
resultado. Es el mismo compromiso que ya tiene la app con la adherencia, que
devuelve `null` con menos de tres días.

**Valor.** Medio-alto, y crece con los meses de uso.
**Esfuerzo.** Medio.

---

### 8 · Una vista de consulta imprimible

**El problema.** La profesional prepara la consulta en el panel y después
necesita algo para tener al lado mientras habla, o para archivar. Hoy imprimir
la ficha sale mal: seis pestañas de las que solo se imprime una.

**Qué necesita.** Lo que ya está, más una hoja de estilos de impresión y una
ruta que renderice todo desplegado. El teléfono ya arma un informe equivalente
(`ReportBuilder`), así que **lo importante es que las dos digan lo mismo**: es
otra oportunidad de que dos números que se llaman igual no coincidan.

**Cómo se vería.** `?print=1`, todas las pestañas desplegadas, sin chrome, con
las notas de la profesional al final.

**Valor.** Medio-alto.
**Esfuerzo.** Medio.

---

### 9 · Un alta de contexto más rica (síntomas, ánimo, ciclo)

`day_markers.tags` ya está preparado para esto sin tocar el esquema. Antes de
usarlo conviene que alguien lo pida: una lista de síntomas que nadie completa es
peso muerto en el formulario de carga, y el modelo ya soporta agregarla el día
que haga falta.

**Valor.** Depende de si se usa.
**Esfuerzo.** Bajo (por el modelo), alto (por el diseño de la carga).

---

## Prioridad

**High value / low effort** — lo que yo haría primero, en este orden:

1. **Los alimentos que se repiten** (§3) — lo que más agrega por lo que menos
   cuesta.
2. **Semana contra semana** (§4).
3. **Días por debajo del basal** (§6).
4. **Cintura/altura** (§5).

**High value / medium effort:**

5. **Balance energético contra peso real** (§1) — la de más valor de todas; va
   quinta solo porque las cuatro de arriba son casi gratis.
6. **Horarios y ventana de alimentación** (§2) — con la decisión previa sobre la
   hora real de la comida.
7. **Vista imprimible** (§8).

**Nice to have:**

8. **Días con X contra días sin X** (§7) — mejor cuando haya tres o cuatro meses
   de datos.
9. **Síntomas y ánimo** (§9) — cuando alguien los pida.

---

## Lo que **no** propongo, y por qué

- **Un score de "qué tan bien va".** Un número que resume adherencia, peso y
  actividad en 0–100 es exactamente lo que esta pantalla decidió no hacer: la
  app muestra distancias, no notas. Y un score que baja porque la persona
  estuvo enferma es peor que no tener score.
- **Alertas automáticas por correo.** "Hace 4 días que no registra" suena útil y
  convierte el panel en un sistema de vigilancia. Si se hace, que lo prenda la
  paciente y no la profesional.
- **Predicción de peso a 12 semanas.** La tendencia a 7 días ya está y es
  honesta. Una proyección larga sobre 30 días de datos es una línea inventada
  con cara de dato.
- **Notificar al paciente lo que anota la profesional.** Las notas son de quien
  las escribe, a pedido explícito del dueño de la cuenta. Ver
  `docs/contexto-diario.md`.
