import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/local/photo_normalizer.dart';
import '../system/buttons.dart';
import '../system/overlays.dart';
import 'meal_photo.dart';
import 'photo_viewer.dart';

/// Adjuntar una foto a la comida que se está registrando.
///
/// La foto es un recuerdo de lo que comiste, no una fuente de datos: no dispara
/// ningún análisis ni cambia los ítems. Para que la IA estime, está "Sacar foto
/// de una comida" en el menú Agregar.
class MealPhotoField extends StatefulWidget {
  const MealPhotoField({
    required this.path,
    required this.onChanged,
    this.emptyLabel = 'Agregar una foto',
    super.key,
  });

  final String? path;

  /// `null` cuando se quita la foto.
  final void Function(String? path) onChanged;

  /// Qué dice el botón cuando todavía no hay foto.
  final String emptyLabel;

  @override
  State<MealPhotoField> createState() => _MealPhotoFieldState();
}

class _MealPhotoFieldState extends State<MealPhotoField> {
  final ImagePicker _picker = ImagePicker();
  bool _busy = false;

  Future<void> _pick(ImageSource source) async {
    setState(() => _busy = true);
    try {
      // Mismo tamaño que el análisis por IA: 1024 px del lado mayor y calidad
      // 80 dejan la foto en ~200 kB, muy por debajo del límite del bucket.
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      // Salvo cuando no: si la imagen traía alfa, `imageQuality` se ignoró y lo
      // que hay es un PNG sin comprimir de varios MB (`PhotoNormalizer`).
      final path = file == null
          ? null
          : await PhotoNormalizer.toJpeg(file.path);
      if (!mounted) return;
      setState(() => _busy = false);
      if (path != null) widget.onChanged(path);
    } on Object {
      if (!mounted) return;
      setState(() => _busy = false);
      NmSnackbar.show(
        context,
        'No pudimos abrir la cámara. Revisá los permisos en Ajustes.',
      );
    }
  }

  Future<void> _choose() async {
    final source = await showNmSheet<ImageSource>(
      context: context,
      builder: (context) => NmSheet(
        title: 'Foto de la comida',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ActionRow(
              icon: PhosphorIcons.camera(),
              label: 'Sacar una foto',
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ActionRow(
              icon: PhosphorIcons.image(),
              label: 'Elegir de la galería',
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _pick(source);
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.path;

    if (path == null || path.isEmpty) {
      return NmButton.secondary(
        label: widget.emptyLabel,
        block: true,
        icon: PhosphorIcons.camera(),
        loading: _busy,
        onPressed: _choose,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Mientras no se guarde, la foto es un archivo local; después de
        // guardar pasa a ser una ruta del bucket. `MealPhoto` resuelve las dos.
        if (File(path).existsSync())
          ClipRRect(
            borderRadius: NmRadius.brMd,
            child: ZoomablePhoto(
              file: File(path),
              child: Image.file(
                File(path),
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          )
        else
          MealPhoto(path: path, height: 180),
        const SizedBox(height: NmSpace.s2),
        Row(
          children: <Widget>[
            NmButton.ghost(label: 'Cambiar', onPressed: _choose),
            const Spacer(),
            NmButton.ghost(
              label: 'Quitar',
              onPressed: () => widget.onChanged(null),
            ),
          ],
        ),
      ],
    );
  }
}
