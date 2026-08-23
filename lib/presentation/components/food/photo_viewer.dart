import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/local/gallery_saver.dart';
import '../system/overlays.dart';

/// Ver una foto en grande, con zoom, y bajarla a la galería.
///
/// La foto puede estar en dos lugares y el visor tiene que servir para los dos:
/// un archivo del teléfono mientras la comida no se guardó, o una URL firmada
/// del bucket una vez que subió. Quien abre el visor ya sabe cuál de las dos
/// tiene —lo averiguó para dibujar la miniatura—, así que lo pasa hecho en vez
/// de volver a resolverlo acá.
class PhotoViewer extends StatefulWidget {
  const PhotoViewer({this.file, this.url, super.key})
    : assert(file != null || url != null, 'El visor necesita una foto');

  /// La foto en el teléfono, cuando todavía no subió al bucket.
  final File? file;

  /// URL firmada del bucket, cuando ya está subida.
  final String? url;

  /// Abre el visor como pantalla completa sobre lo que haya.
  static Future<void> open(
    BuildContext context, {
    File? file,
    String? url,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (context) => PhotoViewer(file: file, url: url),
    ),
  );

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  bool _busy = false;

  /// `null` mientras no se sabe. Antes de Android 10 no hay manera de escribir
  /// en la galería sin pedir un permiso de almacenamiento que esta app no pide,
  /// así que ahí el botón no está y queda Compartir.
  bool? _canSave;

  @override
  void initState() {
    super.initState();
    _checkCanSave();
  }

  Future<void> _checkCanSave() async {
    final allowed = await const GallerySaver().canSave();
    if (mounted) setState(() => _canSave = allowed);
  }

  /// Los bytes de la foto, vengan del archivo o del bucket.
  ///
  /// Se piden solo cuando hace falta —guardar o compartir—: abrir el visor no
  /// tiene por qué descargar nada dos veces, `Image.network` ya la trae para
  /// mostrarla.
  Future<Uint8List> _bytes() async {
    final file = widget.file;
    if (file != null) {
      try {
        return await file.readAsBytes();
      } on FileSystemException {
        throw const AppError(
          code: ApiErrorCode.server,
          message: 'La foto ya no está en el teléfono.',
        );
      }
    }

    final http.Response response;
    try {
      response = await http
          .get(Uri.parse(widget.url!))
          .timeout(const Duration(seconds: 20));
    } on Exception {
      throw const AppError(
        code: ApiErrorCode.offline,
        message: 'No pudimos bajar la foto. Revisá tu conexión.',
      );
    }
    if (response.statusCode != 200) {
      throw const AppError(
        code: ApiErrorCode.upstreamFailed,
        message: 'No pudimos bajar la foto. Probá de nuevo en un rato.',
      );
    }
    return response.bodyBytes;
  }

  /// `ceres-20260729-201005.jpg`: ordenable y sin pisar la anterior.
  String get _fileName {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'ceres-${now.year}${two(now.month)}${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}${two(now.second)}.jpg';
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on AppError catch (error) {
      if (mounted) NmSnackbar.show(context, error.message);
    } on Object {
      if (mounted) {
        NmSnackbar.show(context, 'No pudimos usar la foto. Probá de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() => _run(() async {
    await const GallerySaver().save(await _bytes(), fileName: _fileName);
    if (mounted) NmSnackbar.show(context, 'Foto guardada en la galería');
  });

  Future<void> _share() => _run(() async {
    // Compartir necesita un archivo: el del teléfono si lo hay, y si la foto
    // vive en el bucket, una copia temporal que el sistema pueda leer.
    var path = widget.file?.path;
    if (path == null) {
      final dir = await getTemporaryDirectory();
      final copy = File('${dir.path}${Platform.pathSeparator}$_fileName');
      await copy.writeAsBytes(await _bytes(), flush: true);
      path = copy.path;
    }
    if (!mounted) return;
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(path, mimeType: 'image/jpeg')],
        subject: 'Foto de Ceres',
      ),
    );
  });

  @override
  Widget build(BuildContext context) {
    // Blanco sobre negro y no los colores del tema: una foto se mira contra
    // negro, y en modo claro el fondo de la app le cambiaría los colores a la
    // vista. Es la única pantalla que se sale del sistema, y por esto.
    const Color chrome = Colors.white;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: chrome,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Cerrar',
          icon: Icon(PhosphorIcons.x(), size: NmIconSize.lg),
        ),
        actions: <Widget>[
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: NmSpace.s4),
              child: Center(
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: chrome,
                  ),
                ),
              ),
            )
          else ...<Widget>[
            if (_canSave != false)
              IconButton(
                onPressed: _save,
                tooltip: 'Guardar en la galería',
                icon: Icon(PhosphorIcons.downloadSimple(), size: NmIconSize.lg),
              ),
            IconButton(
              onPressed: _share,
              tooltip: 'Compartir',
              icon: Icon(PhosphorIcons.shareNetwork(), size: NmIconSize.lg),
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: InteractiveViewer(
          maxScale: 5,
          child: Center(child: _Photo(file: widget.file, url: widget.url)),
        ),
      ),
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo({this.file, this.url});

  final File? file;
  final String? url;

  @override
  Widget build(BuildContext context) {
    if (file != null) return Image.file(file!, fit: BoxFit.contain);
    return Image.network(
      url!,
      fit: BoxFit.contain,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
      errorBuilder: (context, error, stack) => const Padding(
        padding: EdgeInsets.all(NmSpace.s6),
        child: Text(
          'No pudimos cargar la foto.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70),
        ),
      ),
    );
  }
}

/// Hace que una miniatura se pueda tocar para verla en grande.
///
/// El ícono de la esquina está porque nada dice que una imagen se pueda tocar:
/// sin él, la pantalla completa existe y nadie la encuentra.
class ZoomablePhoto extends StatelessWidget {
  const ZoomablePhoto({
    required this.child,
    this.file,
    this.url,
    super.key,
  });

  final Widget child;
  final File? file;
  final String? url;

  @override
  Widget build(BuildContext context) {
    if (file == null && url == null) return child;

    return Semantics(
      button: true,
      label: 'Ver la foto en grande',
      child: Stack(
        children: <Widget>[
          child,
          Positioned(
            top: NmSpace.s2,
            right: NmSpace.s2,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: const EdgeInsets.all(NmSpace.s2),
                child: Icon(
                  PhosphorIcons.arrowsOutSimple(),
                  size: NmIconSize.md,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => PhotoViewer.open(context, file: file, url: url),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
