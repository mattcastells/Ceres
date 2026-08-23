import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/error/app_error.dart';

/// Baja una foto de la app a la galería del teléfono.
///
/// Del otro lado del canal está `GallerySaver.kt`, que la inserta con
/// `MediaStore`. Se hace así y no con un plugin porque desde Android 10 eso **no
/// pide ningún permiso**: la app puede dejar en la galería lo que ella misma
/// produjo. El manifest saca a propósito los permisos de lectura de fotos, y
/// pedir uno de escritura para bajar una imagen iría contra lo que la pantalla
/// de Privacidad promete.
///
/// Antes de Android 10 no hay manera sin ese permiso, así que [canSave] devuelve
/// `false` y la pantalla ofrece compartir la foto.
class GallerySaver {
  const GallerySaver();

  static const MethodChannel _channel = MethodChannel(
    'io.ceres.app/gallery',
  );

  /// `false` antes de Android 10 y en cualquier plataforma sin el canal.
  Future<bool> canSave() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('canSave') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Guarda [bytes] como una imagen nueva de la galería.
  Future<void> save(Uint8List bytes, {required String fileName}) async {
    final String result;
    try {
      result =
          await _channel.invokeMethod<String>('save', <String, dynamic>{
            'bytes': bytes,
            'fileName': fileName,
          }) ??
          'unknown';
    } on PlatformException {
      throw _cannot;
    } on MissingPluginException {
      throw _cannot;
    }

    if (result == 'ok') return;

    throw AppError(
      code: ApiErrorCode.server,
      message: switch (result) {
        'unsupported' =>
          'Tu versión de Android no deja guardar directo en la galería. '
              'Compartí la foto y elegí dónde guardarla.',
        'insert_failed' =>
          'La galería no aceptó la foto. Puede ser falta de espacio.',
        'write_failed' =>
          'No pudimos terminar de guardar la foto. Liberá espacio y probá de '
              'nuevo.',
        _ => 'No pudimos guardar la foto en la galería.',
      },
    );
  }

  static const AppError _cannot = AppError(
    code: ApiErrorCode.server,
    message:
        'No pudimos guardar la foto en la galería. Probá compartirla y '
        'elegir dónde guardarla.',
  );
}
