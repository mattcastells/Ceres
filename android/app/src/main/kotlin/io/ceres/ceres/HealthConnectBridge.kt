package io.ceres.ceres

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.BodyFatRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import java.time.Duration
import java.time.Instant
import java.time.ZoneId

/**
 * Lee del almacén de salud del teléfono lo que Ceres no mide por sí sola.
 *
 * Health Connect es el intermediario de Android entre apps de salud, y es la
 * única integración que hace falta: **Samsung Health escribe ahí**, y el Zepp
 * app también (Perfil → vinculación de cuentas → Health Connect). Zepp no tiene
 * API pública para leerle datos a nadie, así que este es el único camino que
 * existe para los Amazfit — y de paso llegan Fitbit, Garmin y cualquier otra que
 * sincronice.
 *
 * Solo tres tipos, y solo lectura: peso, grasa corporal y sueño. Los tres son
 * **uno por día o por noche** en Ceres y se sobreescriben al reimportar
 * (D-16), así que sincronizar dos veces no puede duplicar nada. Lo que sí podría
 * duplicar —las sesiones de ejercicio— queda para su propio paso, con la
 * revisión de duplicados que la app ya tiene prendida desde el primer día.
 */
object HealthConnectBridge {

    const val CHANNEL = "io.ceres.app/health"

    /**
     * Health Connect limita la lectura a los 30 días previos al permiso, salvo
     * que la app tenga el permiso de historial. No lo pedimos: 30 días alcanzan
     * para ponerse al día, y pedir el historial entero de la salud de alguien
     * para eso sería pedir de más.
     */
    private const val WINDOW_DAYS = 30L

    val PERMISSIONS: Set<String> = setOf(
        HealthPermission.getReadPermission(WeightRecord::class),
        HealthPermission.getReadPermission(BodyFatRecord::class),
        HealthPermission.getReadPermission(SleepSessionRecord::class),
    )

    /**
     * En qué estado está Health Connect en este teléfono.
     *
     * Son tres respuestas distintas y no se pueden confundir: "tu Android no lo
     * soporta" no tiene arreglo, "instalá Health Connect" sí, y "está listo"
     * habilita el resto. Devolverlas como una sola bandera haría que la app
     * ofreciera instalar algo imposible.
     */
    fun availability(context: Context): String =
        when (HealthConnectClient.getSdkStatus(context)) {
            HealthConnectClient.SDK_UNAVAILABLE -> "unsupported"
            HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> "update_required"
            else -> "available"
        }

    private fun client(context: Context): HealthConnectClient? =
        if (availability(context) == "available") {
            HealthConnectClient.getOrCreate(context)
        } else {
            null
        }

    suspend fun grantedPermissions(context: Context): Set<String> {
        val client = client(context) ?: return emptySet()
        return client.permissionController.getGrantedPermissions()
    }

    suspend fun hasAllPermissions(context: Context): Boolean =
        grantedPermissions(context).containsAll(PERMISSIONS)

    /**
     * Trae los registros de los últimos 30 días, ya reducidos a un valor por
     * día.
     *
     * La reducción va acá y no en Dart porque depende de la zona horaria del
     * teléfono: un pesaje a las 23:50 y otro a las 00:10 son de días distintos, y
     * eso solo lo sabe quien tiene el `ZoneId`. Se queda **el último de cada
     * día**, que es el criterio de la app para el peso (D-16).
     */
    suspend fun read(context: Context): Map<String, Any> {
        val client = client(context) ?: return emptyMap()

        val now = Instant.now()
        val range = TimeRangeFilter.between(
            now.minus(Duration.ofDays(WINDOW_DAYS)),
            now,
        )
        val zone = ZoneId.systemDefault()

        fun dayOf(instant: Instant): String =
            instant.atZone(zone).toLocalDate().toString()

        val weight = sortedMapOf<String, Double>()
        for (record in client.readRecords(
            ReadRecordsRequest(WeightRecord::class, range),
        ).records) {
            weight[dayOf(record.time)] = record.weight.inKilograms
        }

        val bodyFat = sortedMapOf<String, Double>()
        for (record in client.readRecords(
            ReadRecordsRequest(BodyFatRecord::class, range),
        ).records) {
            bodyFat[dayOf(record.time)] = record.percentage.value
        }

        // El sueño se atribuye al día en que se **despertó**, que es el criterio
        // de la app: la noche del jueves al viernes es el sueño del viernes.
        val sleep = sortedMapOf<String, Int>()
        for (record in client.readRecords(
            ReadRecordsRequest(SleepSessionRecord::class, range),
        ).records) {
            val minutes = Duration.between(record.startTime, record.endTime).toMinutes()
            if (minutes <= 0) continue
            val day = dayOf(record.endTime)
            // Varias sesiones en la misma noche —un despertar en el medio— se
            // suman: son la misma noche partida, no dos noches.
            sleep[day] = (sleep[day] ?: 0) + minutes.toInt()
        }

        return mapOf(
            "weightKg" to weight,
            "bodyFatPct" to bodyFat,
            "sleepMinutes" to sleep,
        )
    }
}
