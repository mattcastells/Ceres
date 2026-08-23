import '../../data/remote/github_releases_client.dart';
import '../models/app_release.dart';

/// Instala un APK ya descargado. La implementación real depende de la
/// plataforma; se inyecta para poder probar el servicio sin tocar Android.
abstract interface class ApkInstaller {
  /// Si el sistema tiene a esta app habilitada como origen de instalación.
  ///
  /// Es un permiso que se concede **por app instaladora** desde Android 8, no
  /// algo que alcance con declarar en el manifest. Mientras sea `false` el
  /// instalador se abre y se cierra sin instalar nada.
  Future<bool> canInstall();

  /// Abre la pantalla de Ajustes donde se habilita a esta app.
  Future<void> openInstallSettings();

  /// Ruta donde dejar el APK, ya libre de lo que haya quedado de un intento
  /// anterior.
  ///
  /// La decide el instalador y no quien descarga porque tiene que caer en el
  /// directorio que el `FileProvider` expone: desde otro lado, Android no puede
  /// leer el archivo que le pasamos.
  Future<String> stagingPath(String fileName);

  /// Le pide al sistema que abra el instalador de paquetes con ese archivo.
  ///
  /// Devuelve cuando el diálogo del sistema quedó a la vista: si la persona
  /// confirma o cancela ya no es asunto de la app, porque a partir de ahí el
  /// proceso lo maneja Android.
  Future<void> install(String path);
}

/// Decide si hay que actualizar y, si la persona acepta, baja e instala.
///
/// **La descarga es siempre manual; la comprobación ya no.** Acá decía que no
/// había chequeo automático al abrir la app, por no salir a internet sin que
/// nadie lo pida. La distribución por fuera de Play Store le puso precio a esa
/// postura: nadie avisa que salió una versión, así que había que acordarse de
/// entrar a Configuración → Actualizaciones, y el resultado fue gente corriendo
/// versiones de meses atrás —incluida la que tenía rota justamente la
/// actualización— sin enterarse.
///
/// La distinción que importa es entre preguntar y bajar. [check] es un JSON de
/// unos kilobytes y ahora se hace sola al abrir (`update_prompt.dart`, con su
/// intervalo y su "ahora no"); [downloadAndInstall] son 25 MB y sigue
/// necesitando que alguien lo pida.
class UpdateService {
  const UpdateService({
    required GithubReleasesClient client,
    required ApkInstaller installer,
  }) : _client = client,
       _installer = installer;

  final GithubReleasesClient _client;
  final ApkInstaller _installer;

  /// Compara la versión instalada contra el último release.
  ///
  /// Si la instalada es **posterior** a la publicada devuelve [UpToDate]: eso
  /// pasa en un build local hecho después del último tag, y ofrecerle a quien
  /// desarrolla que "actualice" hacia atrás no tendría sentido.
  Future<UpdateStatus> check({required AppVersion current}) async {
    final release = await _client.fetchLatest();
    if (release == null) return NoReleasesYet(current);

    if (release.version > current) {
      return UpdateAvailable(current: current, release: release);
    }
    return UpToDate(current);
  }

  /// Si Android ya tiene a Ceres habilitada como origen de instalación.
  Future<bool> canInstall() => _installer.canInstall();

  /// Lleva a la pantalla de Ajustes donde se habilita.
  Future<void> openInstallSettings() => _installer.openInstallSettings();

  /// Baja el APK a disco y abre el instalador.
  ///
  /// El archivo se escribe mientras se descarga, sin juntarlo en memoria: ver
  /// [GithubReleasesClient.downloadApkTo], que explica por qué eso rompió todas
  /// las actualizaciones desde la 1.0.4.
  Future<void> downloadAndInstall(
    AppRelease release, {
    void Function(double progress)? onProgress,
  }) async {
    final path = await _installer.stagingPath(
      'ceres-${release.version}.apk',
    );
    await _client.downloadApkTo(release, path, onProgress: onProgress);
    await _installer.install(path);
  }

  // `releasePage` se fue con el botón de "Ver en GitHub". Mandaba a la página
  // del tag, que es el changelog de commits que la pantalla de actualizaciones
  // ya no muestra: quien entra ahí quiere actualizar, no leer el historial del
  // repositorio.
}
