import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error/app_error.dart';

/// Una copia guardada en la nube, sin bajarla entera.
class CloudBackupInfo {
  const CloudBackupInfo({
    required this.updatedAt,
    required this.sizeBytes,
    required this.path,
    this.isLatest = false,
  });

  final DateTime updatedAt;
  final int sizeBytes;

  /// Ruta completa dentro del bucket, para poder bajar **esta** copia.
  final String path;

  /// Si es la copia que se sobrescribe en cada respaldo.
  final bool isLatest;

  String get sizeLabel {
    const kb = 1024;
    if (sizeBytes >= kb * kb) {
      return '${(sizeBytes / (kb * kb)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / kb).ceil()} kB';
  }
}

/// Sube y baja el documento del usuario a Storage.
///
/// Es el **mismo JSON** que exporta Configuración → Privacidad, dentro de un
/// bucket privado. La política por prefijo que ya protege las fotos lo protege
/// igual: nadie más puede leerlo.
///
/// ## Por qué hay historial
///
/// Hasta la 1.4.2 existía **un solo** `backup.json` y cada respaldo lo pisaba.
/// Eso convertía al respaldo en un punto único de falla: bastaba una subida
/// mala para que la copia buena dejara de existir, sin vuelta atrás. Ya vimos
/// de cerca lo que es depender de un archivo así.
///
/// Ahora cada subida escribe dos objetos:
///
/// - `{uid}/backup.json` — la última. Se mantiene con ese nombre exacto porque
///   las versiones anteriores de la app solo saben buscar ahí, y una versión
///   vieja tiene que poder seguir restaurando.
/// - `{uid}/history/backup-<fecha>.json` — la copia fechada, que **no se pisa
///   nunca**.
///
/// Del historial se conservan las [historyLimit] más recientes. No es un
/// sistema de versiones: es una red para que un error no borre lo único que
/// quedaba.
///
/// Sigue sin ser sincronización relacional contra las 24 tablas. Para eso hay
/// que mover el motor de datos entero, y esto es lo que hace que mientras
/// tanto no se pierda nada.
class CloudBackupClient {
  CloudBackupClient(this._storage);

  factory CloudBackupClient.fromInstance() =>
      CloudBackupClient(Supabase.instance.client.storage);

  final SupabaseStorageClient _storage;

  /// Bucket propio: los de fotos restringen los MIME a imágenes y rechazan el
  /// JSON. Tiene la misma política por prefijo.
  static const String bucket = 'backups';
  static const String fileName = 'backup.json';
  static const String historyFolder = 'history';

  /// Cuántas copias fechadas se conservan.
  ///
  /// Diez cubre varios días de uso normal sin que el bucket crezca sin freno:
  /// el documento pesa decenas de kB, así que el historial entero es menos de
  /// un megabyte.
  static const int historyLimit = 10;

  /// Ningún `await` contra la red puede quedar sin plazo propio.
  ///
  /// Los clientes de Supabase no traen uno, así que sin esto un socket que
  /// acepta la conexión y no contesta —señal mala, no "sin señal"— deja el
  /// `Future` sin terminar nunca. En este cliente eso tenía consecuencias que
  /// duraban toda la sesión: `CloudBackupService.flush` se queda con
  /// `_uploading = true` para siempre y **la app deja de respaldar en
  /// silencio**, y el splash espera `openAfterRestore`, así que se puede quedar
  /// clavado en el logo. Una espera eterna es la peor forma de contar un fallo,
  /// porque no se distingue de estar por terminar.
  static const Duration timeout = Duration(seconds: 30);

  /// El documento entero, que puede pesar cientos de kB con años de historial.
  static const Duration uploadTimeout = Duration(seconds: 60);

  String _pathFor(String userId) => '$userId/$fileName';

  String _historyPathFor(String userId, DateTime at) {
    // Nombre ordenable alfabéticamente: así el listado se ordena solo y no
    // depende de que Storage devuelva fechas confiables.
    final stamp = at
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('-', '')
        .split('.')
        .first;
    return '$userId/$historyFolder/backup-$stamp.json';
  }

  /// Sube el documento: pisa la copia "última" y agrega una fechada.
  ///
  /// Si la copia fechada fallara, la última igual queda subida: perder una
  /// entrada del historial es molesto, no respaldar es grave.
  Future<void> upload({
    required String userId,
    required String documentJson,
    DateTime? at,
  }) async {
    final bytes = Uint8List.fromList(utf8.encode(documentJson));

    try {
      await _storage
          .from(bucket)
          .uploadBinary(
            _pathFor(userId),
            bytes,
            fileOptions: const FileOptions(
              contentType: 'application/json',
              // Sin esto el segundo respaldo falla con "ya existe": lo que
              // queremos es justamente pisar el anterior.
              upsert: true,
            ),
          )
          .timeout(uploadTimeout);
    } on StorageException catch (error) {
      throw _translate(error);
    } on TimeoutException {
      throw _slow;
    } on Exception {
      throw _offline;
    }

    try {
      await _storage
          .from(bucket)
          .uploadBinary(
            _historyPathFor(userId, at ?? DateTime.now()),
            bytes,
            fileOptions: const FileOptions(
              contentType: 'application/json',
              upsert: true,
            ),
          )
          .timeout(uploadTimeout);
      await _pruneHistory(userId);
    } on Object {
      // El historial es la red, no el respaldo. Que falle no puede convertir
      // una subida buena en un error de cara a la persona.
    }
  }

  /// Deja solo las [historyLimit] copias más recientes.
  Future<void> _pruneHistory(String userId) async {
    final copies = await _listHistory(userId);
    if (copies.length <= historyLimit) return;

    final sobran = copies.sublist(historyLimit).map((c) => c.path).toList();
    try {
      await _storage.from(bucket).remove(sobran).timeout(timeout);
    } on Object {
      // Que no se pueda podar no rompe nada: solo ocupa un poco más.
    }
  }

  /// Devuelve el documento guardado, o `null` si nunca se respaldó.
  ///
  /// Con [path] baja una copia concreta del historial; sin él, la última.
  Future<String?> download(String userId, {String? path}) async {
    try {
      final bytes = await _storage
          .from(bucket)
          .download(path ?? _pathFor(userId))
          .timeout(uploadTimeout);
      return utf8.decode(bytes);
    } on StorageException catch (error) {
      if (_isNotFound(error)) return null;
      throw _translate(error);
    } on TimeoutException {
      throw _slow;
    } on Exception {
      throw _offline;
    }
  }

  /// Metadatos de la última copia, sin descargarla.
  Future<CloudBackupInfo?> info(String userId) async {
    try {
      final files = await _storage
          .from(bucket)
          .list(path: userId, searchOptions: const SearchOptions(limit: 100))
          .timeout(timeout);

      for (final file in files) {
        // `endsWith` y no `==`: según la versión, Storage devuelve el nombre
        // relativo a la carpeta o la ruta completa. Comparar por igualdad hacía
        // que nunca matcheara y la pantalla concluyera que no había copia.
        if (!file.name.endsWith(fileName)) continue;
        if (file.name.contains(historyFolder)) continue;
        return CloudBackupInfo(
          updatedAt: _updatedAt(file),
          sizeBytes: _size(file),
          path: _pathFor(userId),
          isLatest: true,
        );
      }
      return null;
    } on StorageException catch (error) {
      if (_isNotFound(error)) return null;
      throw _translate(error);
    } on TimeoutException {
      throw _slow;
    } on Exception {
      throw _offline;
    }
  }

  /// Todas las copias disponibles, de la más nueva a la más vieja.
  ///
  /// La primera es la última subida; después van las fechadas. Es lo que
  /// permite volver a un día anterior si la copia de hoy quedó mal.
  Future<List<CloudBackupInfo>> listVersions(String userId) async {
    final latest = await info(userId);
    final history = await _listHistory(userId);
    return <CloudBackupInfo>[?latest, ...history];
  }

  Future<List<CloudBackupInfo>> _listHistory(String userId) async {
    try {
      final files = await _storage
          .from(bucket)
          .list(
            path: '$userId/$historyFolder',
            searchOptions: const SearchOptions(limit: 100),
          )
          .timeout(timeout);

      final copies = <CloudBackupInfo>[
        for (final file in files)
          if (file.name.endsWith('.json'))
            CloudBackupInfo(
              updatedAt: _updatedAt(file),
              sizeBytes: _size(file),
              path: '$userId/$historyFolder/${file.name.split('/').last}',
            ),
      ]..sort((a, b) => b.path.compareTo(a.path));
      return copies;
    } on Object {
      // Sin historial la app sigue con la última copia, que es el caso de
      // cualquiera que venga de una versión anterior.
      return const <CloudBackupInfo>[];
    }
  }

  static int _size(FileObject file) =>
      (file.metadata?['size'] as num?)?.toInt() ?? 0;

  static DateTime _updatedAt(FileObject file) =>
      (DateTime.tryParse(file.updatedAt ?? file.createdAt ?? '') ??
              DateTime.now())
          .toLocal();

  static bool _isNotFound(StorageException error) =>
      error.statusCode == '404' ||
      error.error == 'not_found' ||
      error.message.toLowerCase().contains('not found');

  static const AppError _offline = AppError(
    code: ApiErrorCode.offline,
    message: 'Sin conexión: el respaldo va a subir cuando vuelva internet.',
  );

  /// Se distingue de [_offline] a propósito: "no hay señal" y "hay señal pero
  /// no contesta" se arreglan distinto, y decir la primera cuando pasa la
  /// segunda manda a mirar el lugar equivocado.
  static const AppError _slow = AppError(
    code: ApiErrorCode.upstreamTimeout,
    message:
        'El respaldo tardó demasiado. Se reintenta con el próximo cambio; si '
        'sigue igual, revisá tu conexión.',
  );

  static AppError _translate(StorageException error) {
    if (error.statusCode == '401' || error.statusCode == '403') {
      return const AppError(
        code: ApiErrorCode.unauthenticated,
        message: 'Tu sesión venció. Volvé a entrar para seguir respaldando.',
      );
    }
    if (error.statusCode == '413') {
      return const AppError(
        code: ApiErrorCode.validation,
        message:
            'El respaldo superó el límite de 8 MB. Exportalo a un archivo '
            'desde Privacidad.',
      );
    }
    return AppError(
      code: ApiErrorCode.server,
      message: 'El respaldo falló (${error.message}). Se reintenta solo.',
    );
  }
}
