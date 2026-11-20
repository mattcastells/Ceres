import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/phosphor_icons.dart';
import '../../../data/remote/photo_storage_client.dart';
import '../../../domain/services/photo_sync_service.dart';
import '../../providers/auth_providers.dart';
import '../feedback/feedback.dart';
import 'photo_viewer.dart';

/// Muestra la foto de un registro, venga del bucket o del teléfono.
///
/// Los buckets son privados, así que una foto ya subida necesita una **URL
/// firmada** que dura una hora. Una que todavía no subió —porque se sacó sin
/// conexión— se lee del archivo local. Quien usa el widget no tiene que saber
/// cuál de las dos es.
class MealPhoto extends ConsumerStatefulWidget {
  const MealPhoto({
    required this.path,
    this.bucket = PhotoBucket.meal,
    this.height = 200,
    super.key,
  });

  final String? path;
  final PhotoBucket bucket;
  final double height;

  @override
  ConsumerState<MealPhoto> createState() => _MealPhotoState();
}

class _MealPhotoState extends ConsumerState<MealPhoto> {
  String? _url;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  @override
  void didUpdateWidget(MealPhoto old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _resolve();
  }

  Future<void> _resolve() async {
    final path = widget.path;
    if (path == null || path.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (!PhotoSyncService.isRemotePath(path)) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final url = await ref
        .read(photoSyncProvider)
        ?.viewUrl(bucket: widget.bucket, path: path);
    if (!mounted) return;
    setState(() {
      _url = url;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.path;

    if (path == null || path.isEmpty) return const SizedBox.shrink();

    if (_loading) {
      return SkeletonBlock(height: widget.height, width: double.infinity);
    }

    final Widget image;
    if (_url != null) {
      image = ZoomablePhoto(
        url: _url,
        child: Image.network(
          _url!,
          height: widget.height,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => _Unavailable(
            height: widget.height,
            message: 'No pudimos cargar la foto.',
          ),
        ),
      );
    } else if (!PhotoSyncService.isRemotePath(path) &&
        File(path).existsSync()) {
      image = ZoomablePhoto(
        file: File(path),
        child: Image.file(
          File(path),
          height: widget.height,
          width: double.infinity,
          fit: BoxFit.cover,
        ),
      );
    } else {
      // Ruta del bucket sin URL: la sesión venció o no hay conexión. Se dice,
      // en vez de dejar un recuadro roto sin explicación.
      image = _Unavailable(
        height: widget.height,
        message: 'La foto está guardada, pero ahora no hay conexión.',
      );
    }

    return ClipRRect(borderRadius: NmRadius.brMd, child: image);
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.height, required this.message});

  final double height;
  final String message;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return Container(
      height: height,
      width: double.infinity,
      color: nm.surfaceRaised,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(PhosphorIcons.imageBroken(), size: 28, color: nm.textMuted),
          const SizedBox(height: NmSpace.s2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: NmSpace.s4),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: nm.textMuted, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
