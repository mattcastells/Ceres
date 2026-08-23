import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../../core/error/app_error.dart';
import '../../domain/models/app_release.dart';

/// Lee los releases publicados en GitHub para saber si hay una versión nueva.
///
/// El repositorio es **público**, así que la API se consulta sin credenciales:
/// no hay ningún token embebido en el APK, que es justamente lo que no puede
/// haber en una app que cualquiera puede descompilar. El límite sin autenticar
/// es de 60 consultas por hora y por IP — de sobra para un chequeo manual.
///
/// > Si el repositorio pasara a privado, esto deja de funcionar y **no alcanza
/// > con agregarle un token acá**: habría que mover la consulta a una Edge
/// > Function que guarde el token del lado del servidor.
class GithubReleasesClient {
  GithubReleasesClient({
    http.Client? client,
    this.owner = defaultOwner,
    this.repo = defaultRepo,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String owner;
  final String repo;

  static const String defaultOwner = 'mattcastells';
  static const String defaultRepo = 'Ceres';

  static const String _host = 'api.github.com';

  /// Sufijo del asset que instala el updater.
  ///
  /// **Desde la 1.3.2 el release publica un solo APK**, justamente este. Los
  /// APK por ABI se dejaron de publicar porque `--split-per-abi` le suma un
  /// corrimiento por arquitectura al `versionCode` (`abi × 1000 + code`): quien
  /// tenía instalado el de su arquitectura recibía la actualización, la
  /// descargaba, y Android la rechazaba por downgrade. Si alguna vez vuelven,
  /// primero el updater tiene que elegir por arquitectura.
  static const String universalApkSuffix = '-universal.apk';

  static const Duration timeout = Duration(seconds: 10);

  /// Cuánto se espera **un trozo** de la descarga antes de darla por cortada.
  /// La descarga entera no lleva plazo: son 75 MB y pueden ser minutos.
  static const Duration stalled = Duration(seconds: 60);

  /// Devuelve el último release publicado, o `null` si el repositorio todavía
  /// no tiene ninguno.
  ///
  /// Ignora borradores y prereleases: `/releases/latest` ya los excluye.
  Future<AppRelease?> fetchLatest() async {
    final uri = Uri.https(_host, '/repos/$owner/$repo/releases/latest');

    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: <String, String>{
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
            'User-Agent': 'Ceres',
          })
          .timeout(timeout);
    } on Exception {
      throw const AppError(
        code: ApiErrorCode.offline,
        message:
            'No pudimos consultar si hay una versión nueva. Revisá tu conexión '
            'y probá de nuevo.',
      );
    }

    // Un repositorio sin releases responde 404, igual que uno inexistente.
    if (response.statusCode == 404) return null;

    if (response.statusCode == 403 || response.statusCode == 429) {
      throw const AppError(
        code: ApiErrorCode.rateLimited,
        message:
            'GitHub limitó las consultas por un rato. Probá de nuevo en unos '
            'minutos.',
      );
    }

    if (response.statusCode != 200) {
      throw AppError(
        code: ApiErrorCode.upstreamFailed,
        message:
            'GitHub respondió ${response.statusCode} al buscar actualizaciones.',
      );
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw const AppError(
        code: ApiErrorCode.upstreamFailed,
        message: 'GitHub devolvió una respuesta que no pudimos interpretar.',
      );
    }

    return _toRelease(body);
  }

  AppRelease? _toRelease(Map<String, dynamic> body) {
    final tag = body['tag_name'] as String?;
    if (tag == null) return null;

    final version = AppVersion.tryParse(tag);
    // Un tag que no es semver no se puede comparar: mejor callar que ofrecer
    // una actualización que quizá sea vieja.
    if (version == null) return null;

    final assets = body['assets'] as List<dynamic>? ?? <dynamic>[];
    Map<String, dynamic>? apk;
    for (final raw in assets) {
      final asset = raw as Map<String, dynamic>;
      final name = asset['name'] as String? ?? '';
      if (name.endsWith(universalApkSuffix)) {
        apk = asset;
        break;
      }
    }
    // Un release sin APK universal no es instalable desde la app.
    if (apk == null) return null;

    final url = apk['browser_download_url'] as String?;
    if (url == null) return null;
    final parsedUrl = Uri.tryParse(url);
    if (parsedUrl == null) return null;

    return AppRelease(
      version: version,
      tag: tag,
      notes: (body['body'] as String? ?? '').trim(),
      apkUrl: parsedUrl,
      apkSizeBytes: (apk['size'] as num?)?.toInt() ?? 0,
      // Viene como `sha256:<hex>` cuando la API lo trae; los releases viejos no
      // lo tienen y ahí queda nulo.
      apkSha256: switch (apk['digest']) {
        final String d when d.startsWith('sha256:') => d.substring(7),
        _ => null,
      },
      publishedAt:
          DateTime.tryParse(body['published_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }

  /// Descarga el APK **al archivo de [path]**, reportando el avance de 0 a 1.
  ///
  /// Va a disco a medida que llega, y no a una lista de bytes en memoria, por lo
  /// que costó exactamente todas las actualizaciones desde la 1.0.4: un
  /// `List<int>` de Dart no guarda un byte por elemento sino una palabra de 64
  /// bits, así que juntar el APK entero pedía **ocho veces su tamaño** de RAM
  /// —unos 600 MB para 75 MB de archivo—, más la copia que hace cada vez que la
  /// lista crece. Android mataba el proceso antes del final.
  ///
  /// En el teléfono se veía como una descarga clavada cerca del 80 %, que es
  /// justo donde el APK pasa de necesitar 512 MB a pedir 1 GB. La 1.0.3 (57 MB)
  /// todavía entraba; la 1.0.4 (73 MB) ya no. Nadie pudo actualizarse desde la
  /// app en el medio.
  Future<void> downloadApkTo(
    AppRelease release,
    String path, {
    void Function(double progress)? onProgress,
  }) async {
    final request = http.Request('GET', release.apkUrl)
      ..headers['User-Agent'] = 'Ceres';

    final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(timeout);
    } on Exception {
      throw const AppError(
        code: ApiErrorCode.offline,
        message: 'Se cortó la descarga. Revisá tu conexión y probá de nuevo.',
      );
    }

    if (response.statusCode != 200) {
      throw AppError(
        code: ApiErrorCode.upstreamFailed,
        message: 'La descarga falló con el código ${response.statusCode}.',
      );
    }

    // Para la barra alcanza con lo que diga la respuesta; `contentLength`
    // puede venir nulo y ahí el tamaño del asset es el plan B.
    final expected = response.contentLength ?? release.apkSizeBytes;
    final file = File(path);
    final sink = file.openWrite();
    var written = 0;

    try {
      // `addStream` y no un `await for`: así el archivo frena a la red cuando no
      // llega a escribir, en vez de acumular en memoria lo que no pudo bajar
      // todavía.
      //
      // El plazo es **por trozo**, no para la descarga entera: 75 MB con datos
      // móviles pueden tardar varios minutos sin que nada esté mal. Lo que no
      // puede pasar es esperar para siempre un byte que ya no va a llegar.
      await sink.addStream(
        response.stream.timeout(stalled).map((chunk) {
          written += chunk.length;
          if (onProgress != null && expected > 0) {
            onProgress((written / expected).clamp(0.0, 1.0));
          }
          return chunk;
        }),
      );
      await sink.flush();
      await sink.close();
    } on FileSystemException {
      await _discard(sink, file);
      throw const AppError(
        code: ApiErrorCode.server,
        message:
            'No pudimos guardar la actualización. Liberá espacio en el '
            'teléfono y probá de nuevo.',
      );
    } on Exception {
      await _discard(sink, file);
      throw const AppError(
        code: ApiErrorCode.offline,
        message: 'Se cortó la descarga. Revisá tu conexión y probá de nuevo.',
      );
    }

    // El control de integridad va contra el tamaño que declaró la API de
    // GitHub, no contra el `Content-Length` de la descarga: si un proxy corta
    // la respuesta y ajusta el header, comparar contra el header no detecta
    // nada. Instalar un APK truncado es peor que fallar.
    if (release.apkSizeBytes > 0 && written != release.apkSizeBytes) {
      // Y no se deja en el teléfono: un archivo a medias con nombre de APK es
      // una trampa para el próximo intento.
      await _discard(sink, file);
      throw const AppError(
        code: ApiErrorCode.upstreamFailed,
        message:
            'La descarga quedó incompleta. Probá de nuevo con mejor conexión.',
      );
    }

    // Y el contenido, cuando GitHub publica su digest.
    //
    // El tamaño solo dice que llegaron todos los bytes, no que sean los que
    // corresponden: un archivo del largo correcto y contenido distinto pasaba
    // el control anterior. Lo que de verdad impide instalar un APK ajeno es la
    // firma —Android rechaza cualquiera que no esté firmado con la misma
    // clave—, así que esto no reemplaza esa defensa: ataja lo que ella no ve,
    // que es la corrupción en el camino.
    final esperado = release.apkSha256;
    if (esperado != null) {
      final real = await _sha256Of(file);
      if (real != esperado.toLowerCase()) {
        await _discard(sink, file);
        throw const AppError(
          code: ApiErrorCode.upstreamFailed,
          message:
              'El archivo descargado no coincide con el publicado. Probá de '
              'nuevo.',
        );
      }
    }

    onProgress?.call(1);
  }

  /// Cierra y borra lo descargado a medias. Nada de esto puede tapar el error
  /// que nos trajo hasta acá, así que falla en silencio.
  /// SHA-256 en hexadecimal, leyendo el archivo de a pedazos.
  ///
  /// Por streaming y no con `readAsBytes`: juntar 75 MB en memoria para
  /// verificarlos sería repetir, en el último paso, justamente el error que
  /// dejó a todo el mundo sin poder actualizarse entre la 1.0.4 y la 1.5.0.
  static Future<String> _sha256Of(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  Future<void> _discard(IOSink sink, File file) async {
    try {
      await sink.close();
    } on Exception {
      // Ya venía fallando; cerrar es solo para no dejar el descriptor abierto.
    }
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Si no se puede borrar, el próximo intento lo sobrescribe igual.
    }
  }

  // `releasePage` se fue con el botón que la abría: la página del tag es el
  // changelog de commits, y la actualización se resuelve entera adentro de la
  // app (`update_dialog.dart`).
}
