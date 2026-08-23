package io.ceres.ceres

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import java.util.Calendar

/**
 * El widget de calorías restantes de la pantalla de inicio del teléfono.
 *
 * Un widget lo dibuja el launcher, en su proceso y con la app cerrada, así que
 * no puede preguntarle nada a Dart: lo único que hay es un dato guardado. La
 * app lo escribe cuando cambia algo (canal `io.ceres.app/widget`) y acá se
 * lee.
 *
 * **La regla que manda es no mentir.** El dato guardado tiene la fecha del día
 * al que pertenece, y si esa fecha no es hoy el widget no muestra nada de él:
 * dice que hay que abrir la app. Un widget que no se actualizó desde ayer
 * mostrando "te quedan 1.234 kcal" es peor que uno vacío, porque no se
 * distingue de uno al día — es la misma regla por la que la app nunca presenta
 * una estimación como si fuera una medición.
 *
 * Implementa `docs/handoff/23-widget-redesign-implementacion.md`.
 */
class CaloriesWidget : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        render(context, manager, appWidgetIds)
    }

    /**
     * Lo redibuja cuando alguien lo agranda o lo achica.
     *
     * Hace falta solo antes de API 31: de ahí en adelante el widget se manda con
     * las cuatro formas adentro y el launcher elige sola la que entra, sin
     * despertar a nadie.
     */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, manager, appWidgetId, newOptions)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            render(context, manager, intArrayOf(appWidgetId))
        }
    }

    /**
     * Tocar el agua anota un vaso y redibuja.
     *
     * No escribe en la base de la app **a propósito**: los datos viven en un
     * único documento JSON y un proceso de fondo que lo lea y lo reescriba puede
     * pisar comidas cargadas mientras tanto. Acá solo se anota la intención
     * —fecha y delta— y la app la aplica cuando corre, que es la única que sabe
     * escribir ese documento.
     */
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_SET_WATER) {
            val target = intent.getIntExtra(EXTRA_GLASSES, -1)
            if (target >= 0) CaloriesWidgetStore.queueWater(context, target)
            refresh(context)
            return
        }
        super.onReceive(context, intent)
    }

    /** Las cuatro formas del widget. Cambia el reparto, no la información. */
    private enum class Shape { COMPACT, WIDE, ONEUI, TALL }

    companion object {

        private const val ACTION_SET_WATER = "io.ceres.app.SET_WATER"
        private const val EXTRA_GLASSES = "glasses"

        /**
         * Las gotas que hay dibujadas en el layout. RemoteViews no puede crear
         * vistas, así que este número es un techo del XML, no una decisión: por
         * eso al lado va la cuenta exacta, que sí puede pasar de ocho.
         */
        private val DROPS = intArrayOf(
            R.id.nm_widget_drop_1,
            R.id.nm_widget_drop_2,
            R.id.nm_widget_drop_3,
            R.id.nm_widget_drop_4,
            R.id.nm_widget_drop_5,
            R.id.nm_widget_drop_6,
            R.id.nm_widget_drop_7,
            R.id.nm_widget_drop_8,
        )

        /** Piso: abajo de esto no entra ni el número. */
        private const val MIN_DP = 110f

        /** Abajo de esto, forma angosta: los macros no entran sin cortarse. */
        private const val WIDE_DP = 200f

        /**
         * A partir de acá entra la forma de tres filas de macro.
         *
         * El rediseño proponía 90 dp, para que un Samsung no cayera en `wide` y
         * quedara con aire. **No sobrevivió a la prueba en el teléfono**: puesto
         * en un Pixel, el widget mide 96 dp y con el umbral en 90 elegía esta
         * forma, que necesita 108 — se cortaban "kcal restantes" y la tercera
         * barra de macro.
         *
         * Elegir una forma antes de que entre es peor que el aire que se quería
         * evitar: `wide` con alto de sobra centra su contenido y se lee bien,
         * mientras que un layout cortado pierde dos de los seis datos. El umbral
         * va donde la forma **entra**, no donde uno querría que entrara.
         */
        private const val ONEUI_DP = 110f

        /** De acá para arriba son dos filas de verdad. */
        private const val TALL_DP = 150f

        /**
         * Redibuja los widgets que haya puestos. Sin ninguno no hace nada, que
         * es el caso de casi todo el mundo: nadie tiene por qué pagar el costo
         * de un widget que no puso.
         */
        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context) ?: return
            val ids = manager.getAppWidgetIds(
                ComponentName(context, CaloriesWidget::class.java),
            )
            if (ids.isEmpty()) return
            render(context, manager, ids)
        }

        private fun render(
            context: Context,
            manager: AppWidgetManager,
            appWidgetIds: IntArray,
        ) {
            val state = CaloriesWidgetStore.read(context)
            val fresh = state != null && state.date == todayIso()

            for (id in appWidgetIds) {
                manager.updateAppWidget(id, adaptive(context, manager, id, state, fresh))
            }
        }

        /**
         * El widget dibujado en la forma que corresponde al tamaño que tiene.
         *
         * Desde API 31 se mandan las cuatro y el launcher elige —también
         * mientras la persona lo redimensiona, sin volver a llamarnos—; antes de
         * eso se elige acá con el tamaño que dejó el launcher en las opciones, y
         * hay que estar atento a que cambie ([onAppWidgetOptionsChanged]).
         */
        private fun adaptive(
            context: Context,
            manager: AppWidgetManager,
            appWidgetId: Int,
            state: CaloriesWidgetState?,
            fresh: Boolean,
        ): RemoteViews {
            fun build(shape: Shape): RemoteViews {
                val views = RemoteViews(context.packageName, layoutOf(shape))
                if (fresh) {
                    renderDay(context, views, state!!, shape)
                } else {
                    renderEmpty(views, state, shape)
                }
                views.setOnClickPendingIntent(R.id.nm_widget_root, openApp(context))
                return views
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                return RemoteViews(
                    mapOf(
                        SizeF(MIN_DP, 40f) to build(Shape.COMPACT),
                        SizeF(WIDE_DP, 40f) to build(Shape.WIDE),
                        SizeF(WIDE_DP, ONEUI_DP) to build(Shape.ONEUI),
                        SizeF(WIDE_DP, TALL_DP) to build(Shape.TALL),
                    ),
                )
            }

            val options = manager.getAppWidgetOptions(appWidgetId)
            val ancho = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
            val alto = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
            return build(
                when {
                    ancho < WIDE_DP -> Shape.COMPACT
                    alto >= TALL_DP -> Shape.TALL
                    alto >= ONEUI_DP -> Shape.ONEUI
                    else -> Shape.WIDE
                },
            )
        }

        private fun layoutOf(shape: Shape): Int = when (shape) {
            Shape.COMPACT -> R.layout.nm_widget_calories_compact
            Shape.WIDE -> R.layout.nm_widget_calories_wide
            Shape.ONEUI -> R.layout.nm_widget_calories_oneui
            Shape.TALL -> R.layout.nm_widget_calories_tall
        }

        private fun renderDay(
            context: Context,
            views: RemoteViews,
            state: CaloriesWidgetState,
            shape: Shape,
        ) {
            views.setViewVisibility(R.id.nm_widget_day, View.VISIBLE)
            views.setViewVisibility(R.id.nm_widget_empty, View.GONE)

            views.setTextViewText(R.id.nm_widget_value, state.value)
            views.setTextViewText(R.id.nm_widget_label, state.label)

            // ── La barra del día ──────────────────────────────────────────
            // Sin objetivo cargado se esconde entera. Una barra al 0 % sería un
            // número inventado con forma de cuenta, que es justo lo que el
            // producto no hace: pasarse tampoco la pone roja, se queda al 100 %
            // y lo que cambia es la palabra del número.
            if (state.caloriesPercent < 0) {
                views.setViewVisibility(R.id.nm_widget_calories_bar, View.GONE)
            } else {
                views.setViewVisibility(R.id.nm_widget_calories_bar, View.VISIBLE)
                views.setProgressBar(
                    R.id.nm_widget_calories_bar,
                    100,
                    state.caloriesPercent,
                    false,
                )
            }

            renderWater(context, views, state, shape)
            renderMacros(views, state, shape)
            renderExtras(views, state, shape)
        }

        /**
         * El agua, que se degrada en tres pasos y no cae nunca: es la única
         * interacción que tiene el widget.
         *
         * En los tamaños de una fila las ocho gotas se resumen en un rail de
         * 40 × 44 dp con **un solo** `PendingIntent`. No es una simplificación
         * visual: las gotas de antes medían 10 dp, un cuarto del mínimo táctil
         * recomendado, y errarle era lo normal.
         */
        private fun renderWater(
            context: Context,
            views: RemoteViews,
            state: CaloriesWidgetState,
            shape: Shape,
        ) {
            // Lo guardado más lo que se tocó y todavía no se aplicó: el número
            // que se ve es siempre el que la persona tocó, no uno a medio
            // camino.
            val glasses = (state.waterGlasses + CaloriesWidgetStore.pendingWater(context, state.date))
                .coerceIn(0, state.waterMax)

            views.setViewVisibility(R.id.nm_widget_water_count, View.VISIBLE)
            views.setTextViewText(
                R.id.nm_widget_water_count,
                "$glasses/${state.waterGoal}",
            )

            if (shape == Shape.TALL) {
                // Las ocho gotas, tocables una por una. Se dibujan
                // `max(meta, tomados)` y no más: ocho gotas fijas con una meta
                // de cinco dirían que faltan tres que nadie se propuso.
                views.setViewVisibility(R.id.nm_widget_water_pill, View.VISIBLE)
                val visible = maxOf(state.waterGoal, glasses)
                for ((index, dropId) in DROPS.withIndex()) {
                    val nth = index + 1
                    if (nth > visible) {
                        views.setViewVisibility(dropId, View.GONE)
                        continue
                    }
                    views.setViewVisibility(dropId, View.VISIBLE)
                    views.setImageViewResource(
                        dropId,
                        if (nth <= glasses) {
                            R.drawable.nm_widget_drop_full
                        } else {
                            R.drawable.nm_widget_drop_empty
                        },
                    )
                    // Tocar la gota N deja el día en N vasos, salvo que ya esté
                    // en N: ahí baja a N−1, y así el último toque se puede
                    // desandar sin abrir la app.
                    views.setOnClickPendingIntent(
                        dropId,
                        setWaterIntent(context, if (nth == glasses) nth - 1 else nth),
                    )
                }
                return
            }

            // El resto de las formas usan una sola gota. Las otras siete están
            // declaradas en el XML en 0 dp; se esconden igual, porque una vista
            // de 0 dp sigue existiendo para el árbol.
            for ((index, dropId) in DROPS.withIndex()) {
                views.setViewVisibility(
                    dropId,
                    if (index == 0 && shape != Shape.COMPACT) View.VISIBLE else View.GONE,
                )
            }

            if (shape == Shape.COMPACT) {
                // Sin lugar para un área táctil de verdad. Una gota de 20 dp sin
                // área es peor que ninguna: acá el widget solo abre la app y el
                // agua se cuenta en texto.
                views.setViewVisibility(R.id.nm_widget_water_pill, View.GONE)
                return
            }

            views.setViewVisibility(R.id.nm_widget_water_pill, View.VISIBLE)
            views.setImageViewResource(
                DROPS[0],
                if (glasses > 0) {
                    R.drawable.nm_widget_drop_full
                } else {
                    R.drawable.nm_widget_drop_empty
                },
            )
            // Un toque suma un vaso; llegando a la meta, el siguiente vuelve a
            // cero. Es la misma forma de desandar que tienen las gotas una por
            // una, con un solo intent en vez de ocho.
            views.setOnClickPendingIntent(
                R.id.nm_widget_water_pill,
                setWaterIntent(context, if (glasses >= state.waterGoal) 0 else glasses + 1),
            )
        }

        /** Los macros: los primeros en irse cuando falta ancho, y se van los tres juntos. */
        private fun renderMacros(
            views: RemoteViews,
            state: CaloriesWidgetState,
            shape: Shape,
        ) {
            if (shape == Shape.COMPACT) {
                views.setViewVisibility(R.id.nm_widget_macros, View.GONE)
                return
            }
            views.setViewVisibility(R.id.nm_widget_macros, View.VISIBLE)
            views.setTextViewText(R.id.nm_widget_protein_label, state.proteinLabel)
            views.setProgressBar(R.id.nm_widget_protein_bar, 100, state.proteinPercent, false)
            views.setTextViewText(R.id.nm_widget_carbs_label, state.carbsLabel)
            views.setProgressBar(R.id.nm_widget_carbs_bar, 100, state.carbsPercent, false)
            views.setTextViewText(R.id.nm_widget_fat_label, state.fatLabel)
            views.setProgressBar(R.id.nm_widget_fat_bar, 100, state.fatPercent, false)
        }

        /**
         * Actividad, sueño y racha. Solo donde hay alto de sobra.
         *
         * Cada campo que llega vacío se esconde solo, y con los tres vacíos se
         * esconde la fila entera: una fila de tres huecos ocupa el mismo alto
         * que una con datos y no dice nada.
         */
        private fun renderExtras(
            views: RemoteViews,
            state: CaloriesWidgetState,
            shape: Shape,
        ) {
            fun texto(id: Int, value: String) {
                views.setViewVisibility(id, if (value.isEmpty()) View.GONE else View.VISIBLE)
                views.setTextViewText(id, value)
            }

            // El consumido contra el objetivo, y la racha, viven en el 4×2.
            if (shape == Shape.TALL) {
                texto(R.id.nm_widget_intake, state.intakeLabel)
                texto(R.id.nm_widget_extra_streak, state.streakLabel)
                views.setViewVisibility(R.id.nm_widget_extras, View.GONE)
                return
            }

            views.setViewVisibility(R.id.nm_widget_intake, View.GONE)

            if (shape != Shape.ONEUI) {
                views.setViewVisibility(R.id.nm_widget_extras, View.GONE)
                return
            }

            val vacio = state.activityLabel.isEmpty() &&
                state.sleepLabel.isEmpty() &&
                state.streakLabel.isEmpty()
            views.setViewVisibility(
                R.id.nm_widget_extras,
                if (vacio) View.GONE else View.VISIBLE,
            )
            texto(R.id.nm_widget_extra_activity, state.activityLabel)
            texto(R.id.nm_widget_extra_sleep, state.sleepLabel)
            texto(R.id.nm_widget_extra_streak, state.streakLabel)
        }

        /**
         * El dato no es de hoy, o no hay ninguno.
         *
         * Se esconde **todo** lo que sería de otro día —el número, las gotas, las
         * barras, los extras— y no solo el número grande. Media tarjeta con los
         * macros de ayer al lado de un hueco se lee como si el hueco fuera el
         * problema y el resto estuviera bien.
         *
         * Los dos casos se distinguen a propósito: "todavía no hay nada" es una
         * app recién instalada y "hay algo pero es de otro día" es un número que
         * ya no vale. Confundirlos manda a buscar el problema al lugar
         * equivocado.
         */
        private fun renderEmpty(
            views: RemoteViews,
            state: CaloriesWidgetState?,
            shape: Shape,
        ) {
            views.setViewVisibility(R.id.nm_widget_day, View.GONE)
            views.setViewVisibility(R.id.nm_widget_empty, View.VISIBLE)

            val hadData = state != null
            views.setTextViewText(
                R.id.nm_widget_empty_title,
                if (hadData) "Abrí Ceres para ver hoy" else "Registrá tu primera comida",
            )

            // En 2×1 cae el detalle: entra el ícono y el título, nada más.
            val detalle = if (hadData) state!!.staleLabel else "Después el día aparece acá"
            if (shape == Shape.COMPACT || detalle.isEmpty()) {
                views.setViewVisibility(R.id.nm_widget_empty_detail, View.GONE)
            } else {
                views.setViewVisibility(R.id.nm_widget_empty_detail, View.VISIBLE)
                views.setTextViewText(R.id.nm_widget_empty_detail, detalle)
            }
        }

        /**
         * El intent que deja el día en [glasses] vasos.
         *
         * El `requestCode` es el propio número: sin eso, `getBroadcast` devuelve
         * el mismo `PendingIntent` para todas las gotas —los extras no entran en
         * la comparación— y las ocho terminarían haciendo lo que pidió la
         * primera.
         */
        private fun setWaterIntent(context: Context, glasses: Int): PendingIntent {
            val intent = Intent(context, CaloriesWidget::class.java)
                .setAction(ACTION_SET_WATER)
                .putExtra(EXTRA_GLASSES, glasses)
            return PendingIntent.getBroadcast(
                context,
                glasses,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        /**
         * Tocar el widget abre la app. `FLAG_IMMUTABLE` es obligatorio desde
         * API 31 y acá además es lo correcto: nadie tiene que poder cambiarle el
         * destino a este intent.
         */
        private fun openApp(context: Context): PendingIntent {
            val intent = Intent(context, MainActivity::class.java)
                .setAction(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_LAUNCHER)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            return PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        /**
         * El día de hoy en la zona del teléfono, en el mismo formato que manda
         * Dart (`isoDate`). Se compara texto y no fechas a propósito: es la
         * única forma de que las dos puntas no puedan discrepar por husos ni por
         * horarios de verano.
         */
        fun todayIso(): String {
            val now = Calendar.getInstance()
            return "%04d-%02d-%02d".format(
                now.get(Calendar.YEAR),
                now.get(Calendar.MONTH) + 1,
                now.get(Calendar.DAY_OF_MONTH),
            )
        }
    }
}

/**
 * Lo que el widget muestra, tal como lo dejó la app.
 *
 * Los textos vienen ya formateados desde Dart: el separador de miles y las
 * palabras ("kcal restantes", "P 120/140", "Actividad 42 min") salen del mismo
 * lugar que los de Inicio. Acá no se formatea nada porque dos formateadores
 * terminan diciendo cosas distintas del mismo número. Los que sí son números son
 * cuentas —vasos y porcentajes—, porque de eso se decide *cuánto dibujar*.
 *
 * Los campos que pueden faltar llegan vacíos, no nulos: una cadena vacía esconde
 * su vista y el layout se acomoda solo.
 */
data class CaloriesWidgetState(
    val date: String,
    val value: String,
    val label: String,
    /** 0–100, o **−1 cuando no hay objetivo cargado**: ahí la barra no se dibuja. */
    val caloriesPercent: Int,
    val waterGlasses: Int,
    val waterGoal: Int,
    val waterMax: Int,
    val proteinLabel: String,
    val proteinPercent: Int,
    val carbsLabel: String,
    val carbsPercent: Int,
    val fatLabel: String,
    val fatPercent: Int,
    val intakeLabel: String,
    val activityLabel: String,
    val sleepLabel: String,
    val streakLabel: String,
    /** "Lo último guardado es del miércoles". Vacío si la app no lo mandó. */
    val staleLabel: String,
)

/**
 * El dato del widget, en sus propias preferencias.
 *
 * Archivo aparte del de Flutter (`FlutterSharedPreferences`) a propósito: leer
 * el almacenamiento interno de un plugin ataría el widget a un detalle de
 * implementación que puede cambiar con una actualización de dependencias, y el
 * síntoma sería un widget que deja de actualizarse sin que nada falle.
 */
object CaloriesWidgetStore {

    private const val PREFS = "nm_widget"
    private const val KEY_DATE = "date"

    /**
     * Los toques de agua que la app todavía no aplicó, como `fecha:delta`
     * separados por coma. Se guarda el **delta** y no el total porque entre el
     * toque y la app puede haberse registrado agua desde la propia app: sumar
     * deltas conserva las dos cosas, mientras que guardar un total pisaría una.
     */
    private const val KEY_PENDING = "pendingWater"

    fun write(context: Context, state: CaloriesWidgetState) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_DATE, state.date)
            .putString("value", state.value)
            .putString("label", state.label)
            .putInt("caloriesPercent", state.caloriesPercent)
            .putInt("waterGlasses", state.waterGlasses)
            .putInt("waterGoal", state.waterGoal)
            .putInt("waterMax", state.waterMax)
            .putString("proteinLabel", state.proteinLabel)
            .putInt("proteinPercent", state.proteinPercent)
            .putString("carbsLabel", state.carbsLabel)
            .putInt("carbsPercent", state.carbsPercent)
            .putString("fatLabel", state.fatLabel)
            .putInt("fatPercent", state.fatPercent)
            .putString("intakeLabel", state.intakeLabel)
            .putString("activityLabel", state.activityLabel)
            .putString("sleepLabel", state.sleepLabel)
            .putString("streakLabel", state.streakLabel)
            .putString("staleLabel", state.staleLabel)
            .apply()
    }

    fun read(context: Context): CaloriesWidgetState? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val date = prefs.getString(KEY_DATE, null) ?: return null
        fun texto(key: String) = prefs.getString(key, "") ?: ""
        return CaloriesWidgetState(
            date = date,
            value = prefs.getString("value", "—") ?: "—",
            label = texto("label"),
            // Por omisión −1: un documento de una versión anterior no traía el
            // campo, y dibujar una barra al 0 % sería inventar el dato.
            caloriesPercent = prefs.getInt("caloriesPercent", -1),
            waterGlasses = prefs.getInt("waterGlasses", 0),
            waterGoal = prefs.getInt("waterGoal", 0),
            waterMax = prefs.getInt("waterMax", 40),
            proteinLabel = texto("proteinLabel"),
            proteinPercent = prefs.getInt("proteinPercent", 0),
            carbsLabel = texto("carbsLabel"),
            carbsPercent = prefs.getInt("carbsPercent", 0),
            fatLabel = texto("fatLabel"),
            fatPercent = prefs.getInt("fatPercent", 0),
            intakeLabel = texto("intakeLabel"),
            activityLabel = texto("activityLabel"),
            sleepLabel = texto("sleepLabel"),
            streakLabel = texto("streakLabel"),
            staleLabel = texto("staleLabel"),
        )
    }

    // ── Toques de agua pendientes ──────────────────────────────────────────

    /** Cuántos vasos se tocaron para [date] y todavía no se aplicaron. */
    fun pendingWater(context: Context, date: String): Int =
        readPending(context)[date] ?: 0

    /**
     * Anota que el día [date] tiene que quedar en [target] vasos.
     *
     * Se guarda contra el total que el widget está mostrando, así que el delta
     * que queda es exactamente lo que hay que sumarle a lo registrado.
     */
    fun queueWater(context: Context, target: Int) {
        val state = read(context) ?: return
        if (state.date != CaloriesWidget.todayIso()) return

        val pending = readPending(context).toMutableMap()
        val shown = (state.waterGlasses + (pending[state.date] ?: 0))
            .coerceIn(0, state.waterMax)
        val delta = target.coerceIn(0, state.waterMax) - shown
        if (delta == 0) return

        val next = (pending[state.date] ?: 0) + delta
        if (next == 0) pending.remove(state.date) else pending[state.date] = next
        writePending(context, pending)
    }

    /** Devuelve los pendientes y los borra: la app se los lleva para aplicarlos. */
    fun drainPending(context: Context): Map<String, Int> {
        val pending = readPending(context)
        if (pending.isNotEmpty()) writePending(context, emptyMap())
        return pending
    }

    private fun readPending(context: Context): Map<String, Int> {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_PENDING, null)
        if (raw.isNullOrEmpty()) return emptyMap()
        return raw.split(',').mapNotNull { chunk ->
            val parts = chunk.split(':')
            val delta = parts.getOrNull(1)?.toIntOrNull()
            if (parts.size == 2 && delta != null) parts[0] to delta else null
        }.toMap()
    }

    private fun writePending(context: Context, pending: Map<String, Int>) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(
                KEY_PENDING,
                pending.entries.joinToString(",") { "${it.key}:${it.value}" },
            )
            .apply()
    }
}
