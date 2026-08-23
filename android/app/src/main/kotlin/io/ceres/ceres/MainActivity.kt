package io.ceres.ceres

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import androidx.health.connect.client.PermissionController
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlinx.coroutines.launch

/**
 * Instalación del APK de una actualización.
 *
 * Se hace acá y no con un plugin genérico de "abrir archivo" porque Android
 * exige un paso que ningún plugin de ese tipo contempla: desde Android 8 la
 * autorización para instalar apps **no la da el manifest**, la da la persona
 * app por app (`REQUEST_INSTALL_PACKAGES` solo habilita a pedirla). Sin ese
 * permiso `startActivity` igual devuelve éxito y el sistema descarta la
 * instalación: la app cree que todo salió bien y el teléfono no instala nada.
 * Por eso `install` chequea primero y devuelve `permission_required` para que
 * la app pueda mandar a Ajustes.
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "io.ceres.app/installer"
        const val WIDGET_CHANNEL = "io.ceres.app/widget"
        const val APK_MIME = "application/vnd.android.package-archive"
        const val REQ_HEALTH_PERMISSIONS = 7301
    }

    /** La llamada de Dart que espera el resultado del pedido de permisos. */
    private var pendingPermissionResult: MethodChannel.Result? = null

    /**
     * El pedido de permisos de Health Connect en Android 9–13, donde Health
     * Connect es una app aparte y el permiso se concede en **su** pantalla.
     *
     * `registerForActivityResult` sería más lindo y **no está**:
     * `FlutterActivity` hereda de `android.app.Activity`, no de
     * `ComponentActivity`, así que no trae la API nueva ni `lifecycleScope`.
     * Cambiar la clase base a `FlutterFragmentActivity` los traería, y también
     * cambiaría la actividad de la que dependen la cámara, el escáner y el
     * selector de fotos — no vale la pena arriesgar eso por azúcar sintáctica.
     * El contrato se usa igual: solo se crea el intent y se parsea el resultado
     * a mano.
     *
     * ⚠️ Y hasta acá llega: **en Android 14+ este contrato no crea un intent de
     * actividad**, así que lanzarlo con `startActivityForResult` reventaba la
     * app. Ver `requestHealthPermissions`.
     */
    private val healthContract = PermissionController.createRequestPermissionResultContract()

    /**
     * Para las llamadas `suspend` del puente. Propio y no `lifecycleScope`, por
     * lo mismo de arriba; se cancela con la actividad para no dejar corrutinas
     * hablándole a una pantalla que ya no está.
     */
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    /** Contesta una sola vez: un `Result` respondido dos veces tira. */
    private fun replyPermissions(granted: Boolean) {
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
    }

    /**
     * Pide los permisos de Health Connect, por el camino que corresponda.
     *
     * **Acá estaba el crash.** Hasta Android 13, Health Connect es una app
     * aparte y el permiso se concede en su pantalla: ahí el contrato de androidx
     * crea un intent de verdad y `startActivityForResult` es correcto.
     *
     * Desde Android 14 Health Connect es parte del sistema y sus permisos son
     * permisos de ejecución comunes (`android.permission.health.*`). El contrato
     * lo sabe y delega en `ActivityResultContracts.RequestMultiplePermissions`,
     * cuyo `createIntent` **no devuelve un intent que resuelva a ninguna
     * actividad**: devuelve uno con una acción interna de androidx
     * (`…contract.action.REQUEST_PERMISSIONS`) que `ComponentActivity`
     * intercepta en su registro para convertirla en un pedido de permisos.
     * `FlutterActivity` no tiene ese registro, así que el intent salía tal cual
     * a `startActivityForResult`, no lo resolvía nadie y saltaba
     * `ActivityNotFoundException` — sin `try` de por medio, la excepción subía
     * por el handler del canal y **se llevaba puesta la app entera**. Que es lo
     * que se veía: tocar "Conectar" y que la app se cerrara al instante.
     *
     * En 14+ entonces se piden como lo que son, con `requestPermissions`, y la
     * respuesta llega por [onRequestPermissionsResult].
     */
    private fun requestHealthPermissions() {
        val permissions = HealthConnectBridge.PERMISSIONS
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                requestPermissions(permissions.toTypedArray(), REQ_HEALTH_PERMISSIONS)
            } else {
                startActivityForResult(
                    healthContract.createIntent(this, permissions),
                    REQ_HEALTH_PERMISSIONS,
                )
            }
        } catch (_: Exception) {
            // Sin pantalla de permisos no hay permiso, y eso es un "no", no un
            // motivo para cerrar la app: la de Integraciones muestra que faltan
            // y deja reintentar.
            replyPermissions(false)
        }
    }

    @Deprecated("Sin ComponentActivity no hay otra forma; ver healthContract.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_HEALTH_PERMISSIONS) return
        val granted = try {
            healthContract.parseResult(resultCode, data)
        } catch (_: Exception) {
            emptySet()
        }
        replyPermissions(granted.containsAll(HealthConnectBridge.PERMISSIONS))
    }

    /**
     * La respuesta del pedido de permisos de Android 14+.
     *
     * El permiso lo concede Health Connect igual —el sistema lleva a su
     * pantalla— pero la respuesta vuelve por acá y no por `onActivityResult`.
     * Se exige el conjunto completo: con el sueño sin permiso, importar solo el
     * peso sería media sincronización sin decirlo.
     */
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQ_HEALTH_PERMISSIONS) return
        val concedidos = permissions.filterIndexed { i, _ ->
            grantResults.getOrNull(i) == PackageManager.PERMISSION_GRANTED
        }.toSet()
        replyPermissions(concedidos.containsAll(HealthConnectBridge.PERMISSIONS))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstall" -> result.success(canRequestInstalls())
                    "openInstallSettings" -> result.success(openInstallSettings())
                    "install" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("no_path", "Falta la ruta del APK.", null)
                        } else {
                            result.success(install(path))
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // Bajar a la galería la foto de una comida. Canal aparte porque no
        // tiene nada que ver con instalar el APK de una actualización.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, GallerySaver.CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canSave" -> result.success(GallerySaver.canSave())
                    "save" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val fileName = call.argument<String>("fileName")
                        if (bytes == null || fileName == null) {
                            result.error("no_image", "Falta la foto a guardar.", null)
                        } else {
                            result.success(GallerySaver.save(this, bytes, fileName))
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // Widget de la pantalla de inicio. Canal aparte, igual que los otros
        // dos: lo único que comparten es el proceso.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "publish" -> {
                        val date = call.argument<String>("date")
                        if (date == null) {
                            result.error("no_date", "Falta la fecha del dato.", null)
                        } else {
                            CaloriesWidgetStore.write(
                                this,
                                CaloriesWidgetState(
                                    date = date,
                                    value = call.argument<String>("value") ?: "—",
                                    label = call.argument<String>("label") ?: "",
                                    // −1 y no 0: sin objetivo la barra del día no
                                    // se dibuja, en vez de dibujarse vacía.
                                    caloriesPercent = call.argument<Int>("caloriesPercent") ?: -1,
                                    waterGlasses = call.argument<Int>("waterGlasses") ?: 0,
                                    waterGoal = call.argument<Int>("waterGoal") ?: 0,
                                    waterMax = call.argument<Int>("waterMax") ?: 40,
                                    proteinLabel = call.argument<String>("proteinLabel") ?: "",
                                    proteinPercent = call.argument<Int>("proteinPercent") ?: 0,
                                    carbsLabel = call.argument<String>("carbsLabel") ?: "",
                                    carbsPercent = call.argument<Int>("carbsPercent") ?: 0,
                                    fatLabel = call.argument<String>("fatLabel") ?: "",
                                    fatPercent = call.argument<Int>("fatPercent") ?: 0,
                                    intakeLabel = call.argument<String>("intakeLabel") ?: "",
                                    activityLabel = call.argument<String>("activityLabel") ?: "",
                                    sleepLabel = call.argument<String>("sleepLabel") ?: "",
                                    streakLabel = call.argument<String>("streakLabel") ?: "",
                                    staleLabel = call.argument<String>("staleLabel") ?: "",
                                ),
                            )
                            CaloriesWidget.refresh(this)
                            result.success(null)
                        }
                    }
                    // Los vasos que se tocaron en el widget mientras la app no
                    // corría. El widget no escribe en la base —el documento es
                    // uno y reescribirlo de a dos procesos pisa datos—, así que
                    // los anota y la app se los lleva acá.
                    "drainPendingWater" ->
                        result.success(CaloriesWidgetStore.drainPending(this))
                    else -> result.notImplemented()
                }
            }

        // Health Connect. Todo lo de acá es `suspend`, así que cada llamada
        // corre en el scope de la actividad y contesta cuando termina.
        //
        // ⚠️ **Nada de este handler puede dejar escapar una excepción.** Lo que
        // se tira adentro de un `MethodCallHandler` sube por el hilo principal y
        // cierra el proceso, y lo que se tira adentro de un `scope.launch` sin
        // `try` va derecho al manejador por defecto y hace lo mismo. El puente
        // habla con un servicio de otro proceso que puede no estar, estar viejo
        // o negarse a atender: todas esas son respuestas, no fallas de la app.
        // Del lado de Dart `HealthConnectGateway` ya trata cada `PlatformException`
        // como "no se pudo", así que contestar con error es exactamente lo que
        // hace falta para que la pantalla lo diga en vez de desaparecer.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HealthConnectBridge.CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "availability" -> try {
                        result.success(HealthConnectBridge.availability(this))
                    } catch (error: Exception) {
                        result.error("availability_failed", error.message, null)
                    }
                    "hasPermissions" -> scope.launch {
                        try {
                            result.success(
                                HealthConnectBridge.hasAllPermissions(this@MainActivity),
                            )
                        } catch (error: Exception) {
                            result.error("permissions_failed", error.message, null)
                        }
                    }
                    // El permiso lo concede Health Connect, no la app: hasta
                    // Android 13 en su propia pantalla y desde Android 14 como
                    // permiso de ejecución. En los dos casos la respuesta llega
                    // por un callback y no de vuelta de esta llamada.
                    "requestPermissions" -> {
                        // Un pedido encima de otro dejaría al primero esperando
                        // para siempre: se lo cierra con un "no".
                        replyPermissions(false)
                        pendingPermissionResult = result
                        requestHealthPermissions()
                    }
                    "read" -> scope.launch {
                        try {
                            result.success(HealthConnectBridge.read(this@MainActivity))
                        } catch (error: Exception) {
                            // Un fallo de lectura no puede quedar en silencio: la
                            // pantalla de Integraciones muestra el motivo.
                            result.error("read_failed", error.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Antes de API 26 el permiso del manifest alcanzaba. */
    private fun canRequestInstalls(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            packageManager.canRequestPackageInstalls()

    /**
     * La pantalla de "Instalar apps desconocidas" es por app: se abre ya
     * filtrada en Ceres para que no haya que buscarla en una lista larga.
     */
    private fun openInstallSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false

        val targeted = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:$packageName"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

        // Algunas ROMs no aceptan el filtro por paquete; ahí va la lista
        // completa, y como último recurso la ficha de la app.
        val fallbacks = listOf(
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName"),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )

        for (intent in listOf(targeted) + fallbacks) {
            try {
                startActivity(intent)
                return true
            } catch (_: ActivityNotFoundException) {
                continue
            }
        }
        return false
    }

    private fun install(path: String): String {
        val file = File(path)
        if (!file.exists()) return "missing_file"
        if (!canRequestInstalls()) return "permission_required"

        val uri: Uri = try {
            FileProvider.getUriForFile(this, "$packageName.updates", file)
        } catch (_: IllegalArgumentException) {
            return "unshareable_file"
        }

        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, APK_MIME)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

        return try {
            startActivity(intent)
            "ok"
        } catch (_: ActivityNotFoundException) {
            "no_installer"
        }
    }
}
