import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/app_release.dart';
import '../../components/feedback/feedback.dart';
import '../../components/system/buttons.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/update_providers.dart';

/// Actualizar la app, de punta a punta y en un solo lugar.
///
/// Antes esto vivía repartido: el aviso de versión nueva mandaba a Configuración
/// → Actualizaciones, y ahí había que buscar el botón entre el número de
/// versión, la fecha, el changelog del release —o sea la lista de commits— y un
/// enlace a GitHub. Nada de eso ayuda a decidir: quien abre la app quiere
/// actualizarla o no quiere, y para eso alcanza con saber qué versión viene y
/// cuánto pesa.
///
/// Así que el diálogo **es** la actualización: acepta, baja y le pasa el APK al
/// instalador de Android sin cambiar de pantalla. Lo usan los dos caminos —el
/// aviso del arranque y la comprobación manual—, para que haya una sola versión
/// de la parte que puede fallar.
Future<void> showUpdateDialog(
  BuildContext context,
  UpdateAvailable available,
) => showNmDialog<void>(
  context: context,
  builder: (context) => UpdateDialog(available: available),
);

class UpdateDialog extends ConsumerStatefulWidget {
  const UpdateDialog({required this.available, super.key});

  final UpdateAvailable available;

  @override
  ConsumerState<UpdateDialog> createState() => _UpdateDialogState();
}

enum _Phase { idle, downloading, installing }

class _UpdateDialogState extends ConsumerState<UpdateDialog> {
  _Phase _phase = _Phase.idle;
  double _progress = 0;
  AppError? _error;

  /// `null` mientras no se sabe. El permiso de instalar es por app y no viene
  /// concedido: sin él el instalador se abre, se cierra y no pasa nada — que es
  /// exactamente lo que se vive como "el celular no me deja actualizar".
  bool? _canInstall;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshPermission());
  }

  Future<void> _refreshPermission() async {
    final allowed = await ref.read(updateServiceProvider).canInstall();
    if (!mounted) return;
    setState(() {
      _canInstall = allowed;
      if (allowed && _error?.code == ApiErrorCode.permissionDenied) {
        _error = null;
      }
    });
  }

  Future<void> _grant() async {
    try {
      await ref.read(updateServiceProvider).openInstallSettings();
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  Future<void> _update() async {
    // Bajar 25 MB para chocar contra un permiso que se podía pedir antes es
    // gastarle los datos a alguien al pedo.
    if (_canInstall == false) {
      await _grant();
      return;
    }

    setState(() {
      _phase = _Phase.downloading;
      _error = null;
      _progress = 0;
    });

    try {
      await ref
          .read(updateServiceProvider)
          .downloadAndInstall(
            widget.available.release,
            onProgress: (value) {
              if (!mounted) return;
              setState(() => _progress = value);
            },
          );
      if (!mounted) return;
      // A partir de acá manda el diálogo de Android; la app queda esperando.
      setState(() => _phase = _Phase.installing);
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _phase = _Phase.idle;
        if (error.code == ApiErrorCode.permissionDenied) _canInstall = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final release = widget.available.release;
    final bajando = _phase == _Phase.downloading;
    final instalando = _phase == _Phase.installing;
    final habilitado = _canInstall != false;

    final extra = <Widget>[
      if (_error != null)
        ErrorState(message: _error!.message, code: _error!.code.wire),

      if (!habilitado && !instalando)
        const InfoNote(
          tone: NmNoteTone.caution,
          text: 'Android todavía no tiene habilitada a Ceres para instalar '
              'apps. Se habilita una sola vez.',
        ),

      if (bajando) ...<Widget>[
        Semantics(
          value: '${(_progress * 100).round()} por ciento',
          child: ClipRRect(
            borderRadius: NmRadius.brSm,
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 6,
              backgroundColor: nm.surfaceRaised,
              valueColor: AlwaysStoppedAnimation<Color>(nm.accent),
            ),
          ),
        ),
        const SizedBox(height: NmSpace.s2),
        Text(
          'Descargando… ${(_progress * 100).round()} %',
          style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
        ),
      ],
    ];

    return PopScope(
      // Mientras baja no se cierra: la descarga seguiría viva sin nadie que
      // muestre el progreso ni el error.
      canPop: !bajando,
      child: NmDialog(
        title: instalando ? 'Descargada' : 'Hay una versión nueva',
        body: instalando
            ? 'Android está instalando. Cuando termine, volvé a abrir la app.'
            : '${widget.available.current} → ${release.version} · '
                  '${release.apkSizeLabel}',
        content: extra.isEmpty
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: extra,
              ),
        actions: instalando
            ? <Widget>[
                NmButton(
                  label: 'Listo',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ]
            : <Widget>[
                NmButton.ghost(
                  label: 'Ahora no',
                  onPressed: bajando
                      ? null
                      : () => Navigator.of(context).pop(),
                ),
                NmButton(
                  label: habilitado ? 'Actualizar' : 'Habilitar',
                  icon: PhosphorIcons.downloadSimple(),
                  loading: bajando,
                  onPressed: bajando ? null : _update,
                ),
              ],
      ),
    );
  }
}
