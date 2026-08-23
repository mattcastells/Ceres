import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/error/app_error.dart';
import '../../domain/services/update_service.dart';

/// Instala el APK descargado delegando en el instalador de paquetes de
/// Android.
///
/// La app **no instala nada por su cuenta**: elige dónde va el archivo —lo
/// escribe la descarga, a medida que baja— y le pide al sistema que lo abra.
/// Android muestra su propio diálogo de confirmación con el nombre y los
/// permisos, y ahí la persona decide.
///
/// Eso exige dos cosas distintas, y confundirlas fue el motivo de que la
/// actualización se descargara sin instalarse nunca:
///
/// 1. `REQUEST_INSTALL_PACKAGES` en el manifest. Solo habilita a **pedir**.
/// 2. Que la persona haya marcado a Ceres como origen confiable en
///    Ajustes → Apps → Ceres → Instalar apps desconocidas. Es por app
///    instaladora, no global: por eso otras apps sí pueden instalar y esta no.
///
/// Sin el punto 2, lanzar el intent igual "funciona" —el sistema no devuelve
/// error— y el instalador se cierra sin hacer nada. Por eso [canInstall] se
/// consulta antes y [openInstallSettings] lleva directo a la pantalla donde se
/// habilita.
class AndroidApkInstaller implements ApkInstaller {
  const AndroidApkInstaller();

  static const MethodChannel _channel = MethodChannel(
    'io.ceres.app/installer',
  );

  @override
  Future<bool> canInstall() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('canInstall') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> openInstallSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('openInstallSettings');
    } on PlatformException {
      throw const AppError(
        code: ApiErrorCode.server,
        message:
            'No pudimos abrir Ajustes. Buscá Apps → Ceres → Instalar apps '
            'desconocidas y habilitalo a mano.',
      );
    }
  }

  @override
  Future<String> stagingPath(String fileName) async {
    // El directorio de soporte es privado de la app y el FileProvider de
    // `nm_update_paths.xml` lo expone; la carpeta de descargas exigiría
    // permisos de almacenamiento que no queremos pedir.
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');

    try {
      // Los APK de versiones anteriores también se van.
      //
      // Antes solo se borraba el archivo del **mismo nombre**, así que cada
      // actualización dejaba el suyo: `ceres-1.9.0.apk`,
      // `ceres-1.10.0.apk`… a 75 MB cada uno, en el directorio de soporte,
      // que Android no limpia solo. Tres actualizaciones eran un cuarto de giga
      // ocupado por instaladores que ya se usaron.
      await for (final entry in dir.list()) {
        if (entry is! File) continue;
        final name = entry.path.split(Platform.pathSeparator).last;
        if (name.startsWith('ceres-') && name.endsWith('.apk')) {
          await entry.delete();
        }
      }
      // Y el que se va a escribir, por si no matcheaba el patrón de arriba.
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      throw const AppError(
        code: ApiErrorCode.server,
        message:
            'No pudimos preparar la descarga. Liberá espacio en el teléfono y '
            'probá de nuevo.',
      );
    }

    return file.path;
  }

  @override
  Future<void> install(String path) async {
    final String result;
    try {
      result =
          await _channel.invokeMethod<String>(
            'install',
            <String, dynamic>{'path': path},
          ) ??
          'unknown';
    } on PlatformException {
      throw const AppError(
        code: ApiErrorCode.server,
        message:
            'No pudimos abrir el instalador. Descargá el APK desde GitHub e '
            'instalalo a mano.',
      );
    }

    if (result == 'ok') return;

    throw AppError(
      code: result == 'permission_required'
          ? ApiErrorCode.permissionDenied
          : ApiErrorCode.server,
      message: switch (result) {
        'permission_required' =>
          'Android necesita tu permiso para instalar apps desde Ceres.',
        'no_installer' =>
          'Este teléfono no puede abrir el instalador de paquetes. Descargá '
              'el APK desde GitHub e instalalo a mano.',
        'missing_file' =>
          'La actualización descargada no quedó en el teléfono. Probá de '
              'nuevo.',
        _ =>
          'No pudimos abrir el instalador. Descargá el APK desde GitHub e '
              'instalalo a mano.',
      },
    );
  }
}
