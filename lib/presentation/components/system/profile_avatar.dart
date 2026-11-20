import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/phosphor_icons.dart';
import '../../../data/local/photo_normalizer.dart';
import '../../../data/remote/photo_storage_client.dart';
import '../../../domain/services/photo_sync_service.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_providers.dart';
import 'overlays.dart';

/// La foto de perfil, o la inicial si no hay.
///
/// La foto puede estar en el teléfono (recién elegida, todavía sin subir) o
/// en el bucket, que es privado: ahí hace falta una URL firmada. Quien usa el
/// widget no tiene que saber cuál de las dos es.
class ProfileAvatar extends ConsumerStatefulWidget {
  const ProfileAvatar({
    required this.path,
    required this.initial,
    this.size = 52,
    this.onTap,
    super.key,
  });

  final String? path;
  final String initial;
  final double size;

  /// Con esto se muestra el botoncito de cámara y el avatar se puede tocar.
  final VoidCallback? onTap;

  @override
  ConsumerState<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends ConsumerState<ProfileAvatar> {
  String? _url;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  @override
  void didUpdateWidget(ProfileAvatar old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _resolve();
  }

  Future<void> _resolve() async {
    final path = widget.path;
    if (path == null || !PhotoSyncService.isRemotePath(path)) {
      if (mounted) setState(() => _url = null);
      return;
    }
    final url = await ref
        .read(photoSyncProvider)
        ?.viewUrl(bucket: PhotoBucket.progress, path: path);
    if (mounted) setState(() => _url = url);
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final path = widget.path;
    final size = widget.size;

    ImageProvider? image;
    if (_url != null) {
      image = NetworkImage(_url!);
    } else if (path != null &&
        !PhotoSyncService.isRemotePath(path) &&
        File(path).existsSync()) {
      image = FileImage(File(path));
    }

    final circle = Container(
      height: size,
      width: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: nm.accentFill,
        shape: BoxShape.circle,
        image: image == null
            ? null
            : DecorationImage(image: image, fit: BoxFit.cover),
      ),
      child: image != null
          ? null
          : Text(
              widget.initial,
              style: NmTextStyles.from(NmType.h3, color: nm.accentOnFill),
            ),
    );

    if (widget.onTap == null) return circle;

    return Semantics(
      button: true,
      label: image == null
          ? 'Agregar foto de perfil'
          : 'Cambiar foto de perfil',
      child: GestureDetector(
        onTap: widget.onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            circle,
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                height: 22,
                width: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: nm.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: nm.surface, width: 2),
                ),
                child: Icon(
                  PhosphorIcons.camera(PhosphorIconsStyle.fill),
                  size: 11,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sacar, elegir o quitar la foto de perfil.
Future<void> showProfilePhotoSheet(BuildContext context, WidgetRef ref) async {
  final hasPhoto = ref.read(profileProvider).avatarPath != null;
  final choice = await showNmSheet<String>(
    context: context,
    builder: (context) => NmSheet(
      title: 'Foto de perfil',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ActionRow(
            icon: PhosphorIcons.camera(),
            label: 'Sacar una foto',
            onTap: () => Navigator.of(context).pop('camera'),
          ),
          ActionRow(
            icon: PhosphorIcons.image(),
            label: 'Elegir de la galería',
            onTap: () => Navigator.of(context).pop('gallery'),
          ),
          if (hasPhoto)
            ActionRow(
              icon: PhosphorIcons.trash(),
              label: 'Quitar la foto',
              onTap: () => Navigator.of(context).pop('remove'),
            ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;

  final repo = ref.read(repositoryProvider);
  if (choice == 'remove') {
    await repo.setProfilePhoto(null);
    return;
  }

  try {
    // Chica a propósito: se ve en un círculo de 52 px. 512 px de lado y
    // calidad 85 la dejan en unos 40 kB.
    final file = await ImagePicker().pickImage(
      source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
      preferredCameraDevice: CameraDevice.front,
    );
    if (file == null) return;
    final path = await PhotoNormalizer.toJpeg(file.path);
    await repo.setProfilePhoto(path);
  } on Object {
    if (!context.mounted) return;
    NmSnackbar.show(
      context,
      'No pudimos abrir la cámara. Revisá los permisos en Ajustes.',
    );
  }
}
