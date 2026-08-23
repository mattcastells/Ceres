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
import '../../components/system/nm_screen.dart';
import '../../components/system/surfaces.dart';
import '../../providers/update_providers.dart';
import 'update_dialog.dart';

/// Buscar actualizaciones (Configuración → Actualizaciones).
///
/// Ceres se distribuye por fuera de Play Store, así que el aviso de versión
/// nueva lo da la app: consulta los releases del repositorio, y si hay una
/// posterior a la instalada ofrece bajarla e instalarla.
///
/// Al abrir la app se consulta sola y, si hay algo nuevo, avisa con un toast
/// (`update_prompt.dart`); acá se puede comprobar cuando se quiera. Lo que
/// **nunca** arranca solo es la descarga: bajar 25 MB con datos móviles sin
/// haberlo pedido no es una decisión que le toque tomar al software.
///
/// Esta pantalla no baja nada por sí sola: de eso se ocupa [showUpdateDialog],
/// el mismo que abre el aviso del arranque. Acá quedó lo que es propio de la
/// pantalla —qué versión hay instalada y el botón de comprobar—, y se fueron el
/// changelog del release y el enlace a GitHub. Eran la lista de commits del tag
/// puesta delante de alguien que ya decidió actualizar o no.
class UpdatesScreen extends ConsumerStatefulWidget {
  const UpdatesScreen({super.key});

  @override
  ConsumerState<UpdatesScreen> createState() => _UpdatesScreenState();
}

enum _Phase { idle, checking, checked }

class _UpdatesScreenState extends ConsumerState<UpdatesScreen>
    with WidgetsBindingObserver {
  _Phase _phase = _Phase.idle;
  UpdateStatus? _status;
  AppError? _error;

  /// `null` mientras no se sabe. Se consulta al entrar y cada vez que la app
  /// vuelve del frente, que es justo cuando se vuelve de Ajustes.
  bool? _canInstall;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshPermission();
  }

  Future<void> _refreshPermission() async {
    final allowed = await ref.read(updateServiceProvider).canInstall();
    if (!mounted) return;
    setState(() {
      _canInstall = allowed;
      // Si el permiso era lo que faltaba, el cartel de error ya no aplica.
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

  Future<void> _check() async {
    setState(() {
      _phase = _Phase.checking;
      _error = null;
      _status = null;
    });

    try {
      final current = await ref.read(installedVersionProvider.future);
      final status = await ref
          .read(updateServiceProvider)
          .check(current: current);
      if (!mounted) return;
      setState(() {
        _status = status;
        _phase = _Phase.checked;
      });
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _phase = _Phase.idle;
      });
    }
  }

  /// El diálogo se ocupa de bajar e instalar, y también del permiso: es el
  /// mismo que abre el aviso del arranque, así que la parte que puede fallar
  /// tiene una sola versión.
  Future<void> _install(UpdateAvailable available) async {
    await showUpdateDialog(context, available);
    if (mounted) await _refreshPermission();
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final installed = ref.watch(installedVersionLabelProvider);

    return NmScreen(
      title: 'Actualizaciones',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          NmCard(
            child: ValueRow(
              label: 'Versión instalada',
              value: installed.maybeWhen(
                data: (value) => value,
                orElse: () => '—',
              ),
            ),
          ),
          const SizedBox(height: NmSpace.s4),

          if (_error != null) ...<Widget>[
            ErrorState(
              message: _error!.message,
              code: _error!.code.wire,
              onRetry: _phase == _Phase.idle ? _check : null,
            ),
            const SizedBox(height: NmSpace.s4),
          ],

          // El permiso es por app y no viene concedido: sin esto el instalador
          // se abre, se cierra y no pasa nada, que es exactamente lo que se
          // vive como "el celular no me deja actualizar".
          if (_canInstall == false) ...<Widget>[
            const InfoNote(
              tone: NmNoteTone.caution,
              text:
                  'Android todavía no tiene habilitada a Ceres para '
                  'instalar apps. Sin ese permiso la actualización se descarga '
                  'pero el instalador se cierra solo.',
            ),
            const SizedBox(height: NmSpace.s3),
            NmButton.secondary(
              label: 'Permitir instalar desde Ceres',
              icon: PhosphorIcons.gear(),
              onPressed: _grant,
            ),
            const SizedBox(height: NmSpace.s4),
          ],

          switch (_phase) {
            _Phase.checking => const _Busy(label: 'Buscando actualizaciones…'),
            _ => _Result(
              status: _status,
              canInstall: _canInstall != false,
              onCheck: _check,
              onInstall: _install,
            ),
          },

          const SizedBox(height: NmSpace.s6),
          Text(
            'La primera vez hay que habilitar a Ceres en Ajustes → Apps → '
            'Ceres → Instalar apps desconocidas. Después, Android pide '
            'confirmación en cada actualización.',
            style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
          ),
        ],
      ),
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      const NmSpinner(size: 20),
      const SizedBox(width: NmSpace.s3),
      Text(
        label,
        style: NmTextStyles.from(NmType.bodySm, color: context.nm.textMuted),
      ),
    ],
  );
}

class _Result extends StatelessWidget {
  const _Result({
    required this.status,
    required this.canInstall,
    required this.onCheck,
    required this.onInstall,
  });

  final UpdateStatus? status;
  final bool canInstall;
  final VoidCallback onCheck;
  final void Function(UpdateAvailable) onInstall;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;

    return switch (status) {
      null => NmButton(label: 'Buscar actualizaciones', onPressed: onCheck),

      UpToDate() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(PhosphorIcons.checkCircle(), size: 20, color: nm.success),
              const SizedBox(width: NmSpace.s2),
              Text('Estás al día', style: NmTextStyles.from(NmType.body)),
            ],
          ),
          const SizedBox(height: NmSpace.s4),
          NmButton.secondary(label: 'Buscar de nuevo', onPressed: onCheck),
        ],
      ),

      NoReleasesYet() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const InfoNote(
            text:
                'Todavía no hay ninguna versión publicada.',
          ),
          const SizedBox(height: NmSpace.s4),
          NmButton.secondary(label: 'Buscar de nuevo', onPressed: onCheck),
        ],
      ),

      final UpdateAvailable available => _Available(
        available: available,
        canInstall: canInstall,
        onInstall: onInstall,
      ),
    };
  }
}

/// Hay versión nueva: qué versión, cuánto pesa y el botón.
///
/// Nada más. Acá estuvieron la fecha de publicación, el cuerpo del release —la
/// lista de commits del tag— y un enlace a GitHub, y ninguna de las tres ayuda
/// a decidir: quien entra a esta pantalla ya sabe si quiere actualizar. Lo que
/// necesita saber es qué le va a bajar y cuánto va a ocupar.
class _Available extends StatelessWidget {
  const _Available({
    required this.available,
    required this.canInstall,
    required this.onInstall,
  });

  final UpdateAvailable available;
  final bool canInstall;
  final void Function(UpdateAvailable) onInstall;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final release = available.release;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const NmTag(label: 'Versión nueva', variant: NmTagVariant.accent),
            const SizedBox(width: NmSpace.s2),
            Text(
              '${available.current} → ${release.version}',
              style: NmTextStyles.from(NmType.body),
            ),
          ],
        ),
        const SizedBox(height: NmSpace.s3),
        Text(
          release.apkSizeLabel,
          style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
        ),
        const SizedBox(height: NmSpace.s5),
        NmButton(
          label: canInstall ? 'Actualizar' : 'Habilitar la instalación',
          icon: PhosphorIcons.downloadSimple(),
          onPressed: () => onInstall(available),
        ),
      ],
    );
  }
}
