import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/phosphor_icons.dart';
import '../../../data/remote/cloud_backup_client.dart';
import '../../../domain/services/cloud_backup_service.dart';
import '../../../domain/services/relational_sync_service.dart';
import '../../components/feedback/feedback.dart';
import '../../components/system/buttons.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_providers.dart';

/// Respaldo en la nube (Configuración → Respaldo en la nube).
///
/// La copia sube sola cada vez que cambia algo; esta pantalla existe para
/// mirarla, forzarla y —lo importante— **restaurarla en un teléfono nuevo**.
class CloudBackupScreen extends ConsumerStatefulWidget {
  const CloudBackupScreen({super.key});

  @override
  ConsumerState<CloudBackupScreen> createState() => _CloudBackupScreenState();
}

class _CloudBackupScreenState extends ConsumerState<CloudBackupScreen> {
  CloudBackupInfo? _remote;
  bool _loading = true;
  bool _restoring = false;
  AppError? _error;

  // Acá vivía "Este dispositivo y el servidor": un botón de Comparar que traía
  // la cuenta de filas de cada tabla y la ponía al lado de la local. Existió
  // para comprobar que las tablas fueran de verdad la fuente de verdad, cuando
  // recién se estaba pasando a eso. Ya está comprobado, y lo que quedaba era
  // una pantalla que le pedía a quien usa la app que interpretara dos columnas
  // de números y decidiera si la diferencia estaba bien — una herramienta de
  // desarrollo con la ropa de una opción de configuración.

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final service = ref.read(cloudBackupProvider);
    if (service == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final info = await service.remoteInfo();
      if (!mounted) return;
      setState(() {
        _remote = info;
        _loading = false;
        _error = null;
      });
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _backupNow() async {
    final service = ref.read(cloudBackupProvider);
    if (service == null) return;
    setState(() => _error = null);
    await service.flush();
    await _load();
  }

  /// Elegir de qué copia restaurar.
  ///
  /// Con una sola copia esto sería un botón; con historial es una decisión, y
  /// la fecha es justamente el dato que permite tomarla ("lo perdí ayer a la
  /// tarde, traeme la de la mañana").
  Future<void> _pickAndRestore() async {
    final service = ref.read(cloudBackupProvider);
    if (service == null) return;

    setState(() {
      _restoring = true;
      _error = null;
    });

    final List<CloudBackupInfo> copias;
    try {
      copias = await service.versions();
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() {
        _restoring = false;
        _error = error;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _restoring = false);

    if (copias.isEmpty) {
      setState(
        () => _error = const AppError(
          code: ApiErrorCode.notFound,
          message: 'No hay ninguna copia guardada todavía.',
        ),
      );
      return;
    }

    // Con una sola copia no hay nada que elegir: se va derecho a confirmar.
    final elegida = copias.length == 1
        ? copias.first
        : await showNmSheet<CloudBackupInfo>(
            context: context,
            builder: (context) => NmSheet(
              title: 'Elegí qué copia traer',
              subtitle: 'De la más nueva a la más vieja',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final copia in copias)
                    ActionRow(
                      icon: copia.isLatest
                          ? PhosphorIcons.cloudCheck()
                          : PhosphorIcons.clockCounterClockwise(),
                      label:
                          '${longDay(copia.updatedAt)} '
                          '${timeOfDay(copia.updatedAt)}',
                      subtitle: copia.isLatest
                          ? 'La última · ${copia.sizeLabel}'
                          : copia.sizeLabel,
                      onTap: () => Navigator.of(context).pop(copia),
                    ),
                ],
              ),
            ),
          );

    if (elegida == null || !mounted) return;
    await _restore(elegida);
  }

  Future<void> _restore(CloudBackupInfo copia) async {
    final service = ref.read(cloudBackupProvider);
    if (service == null) return;

    // Qué hace restaurar, de verdad.
    //
    // El texto prometía que lo posterior a la copia "se pierde", y desde que
    // las tablas son la fuente de verdad eso dejó de ser cierto: la copia
    // reemplaza el documento de este teléfono, pero la reconciliación siguiente
    // —como mucho 30 segundos después— lo une con lo que hay en la cuenta y
    // devuelve todo lo que la copia no tenía.
    //
    // Se elige contar eso en vez de forzar el borrado remoto: "restaurar" no
    // debería poder borrar de la cuenta lo que se cargó en otro dispositivo, y
    // quien viene acá busca recuperar algo que perdió, no perder algo más.
    final conServidor = ref.read(relationalSyncProvider) != null;
    final confirmed = await showNmDialog<bool>(
      context: context,
      builder: (context) => NmDialog(
        title: '¿Traer la copia del ${longDay(copia.updatedAt)}?',
        body: conServidor
            ? 'Se trae esa copia (${copia.sizeLabel}) y se combina con lo que '
                  'ya hay en tu cuenta: lo que falte acá se recupera y no se '
                  'borra nada de lo que registraste después.'
            : 'Se reemplaza todo lo que tenés en este teléfono por esa copia '
                  '(${copia.sizeLabel}). Lo que hayas registrado acá después '
                  'de esa fecha se pierde.',
        actions: <Widget>[
          NmButton.ghost(
            label: 'Cancelar',
            onPressed: () => Navigator.of(context).pop(false),
          ),
          NmButton(
            label: conServidor ? 'Traer' : 'Reemplazar',
            variant: conServidor
                ? NmButtonVariant.primary
                : NmButtonVariant.danger,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _restoring = true;
      _error = null;
    });

    try {
      final json = await service.restore(path: copia.path);
      if (json == null) {
        if (!mounted) return;
        setState(() {
          _restoring = false;
          _error = const AppError(
            code: ApiErrorCode.notFound,
            message: 'No hay ninguna copia guardada todavía.',
          );
        });
        return;
      }
      await ref.read(repositoryProvider).importJson(json);
      if (!mounted) return;
      setState(() => _restoring = false);
      NmSnackbar.show(context, 'Listo: se restauró la copia de la nube.');
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() {
        _restoring = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final state = ref.watch(backupStateProvider).value;

    if (state is BackupUnavailable) {
      return NmScreen(
        title: 'Respaldo en la nube',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: NmSpace.s4),
            InfoNote(text: state.reason, tone: NmNoteTone.caution),
            const SizedBox(height: NmSpace.s4),
            Text(
              'Tus datos siguen guardados en este teléfono. Podés exportarlos '
              'a un archivo desde Configuración → Privacidad.',
              style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
            ),
          ],
        ),
      );
    }

    return NmScreen(
      title: 'Respaldo en la nube',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),

          NmCard(
            child: Column(
              children: <Widget>[
                ValueRow(label: 'Estado', value: _statusLabel(state)),
                ValueRow(
                  label: 'Última copia',
                  value: _loading
                      ? '…'
                      : _remote == null
                      ? 'Todavía ninguna'
                      : '${longDay(_remote!.updatedAt)} '
                            '${timeOfDay(_remote!.updatedAt)}',
                ),
                if (_remote != null)
                  ValueRow(label: 'Tamaño', value: _remote!.sizeLabel),
              ],
            ),
          ),

          // El error puede venir de esta pantalla o del último intento
          // automático: si el estado dice "falló" y no se muestra el motivo,
          // no hay forma de saber qué pasó.
          if (_error != null || state is BackupFailed) ...<Widget>[
            const SizedBox(height: NmSpace.s4),
            Builder(
              builder: (context) {
                final error =
                    _error ?? (state as BackupFailed).error;
                return ErrorState(
                  message: error.message,
                  code: error.code.wire,
                );
              },
            ),
          ],

          // El caso que borraba los datos: teléfono sin nada y una copia con
          // todo. Antes se subía el vacío y se perdía la copia; ahora se para
          // y se explica cuál es el movimiento correcto.
          if (state is BackupHeldEmpty) ...<Widget>[
            const SizedBox(height: NmSpace.s4),
            const InfoNote(
              tone: NmNoteTone.caution,
              text: 'No estamos subiendo nada porque este teléfono no tiene '
                  'registros. Si tu copia de la nube sí los tiene, traela con '
                  '"Restaurar desde la nube": subir esto la borraría.',
            ),
          ],

          // ── La escritura en las tablas ──────────────────────────────────
          // Acá vivía el botón de Comparar. Lo que hace falta en su lugar no es
          // una herramienta para auditar a mano: es que un fallo **se vea**.
          // Cuatro restricciones desactualizadas rechazaron cada fila durante
          // meses y la app no lo dijo en ningún lado.
          _SyncStatus(state: ref.watch(syncStateProvider).value),

          const SizedBox(height: NmSpace.s6),
          NmButton.secondary(
            label: 'Respaldar ahora',
            block: true,
            icon: PhosphorIcons.cloudArrowUp(),
            loading: state is BackupUploading,
            onPressed: _backupNow,
          ),
          const SizedBox(height: NmSpace.s3),
          // Siempre habilitado. Antes se apagaba cuando el listado no
          // encontraba nada, y ese listado puede fallar por mil motivos que
          // no son "no hay copia": ahí el único camino de recuperación
          // desaparecía sin decir por qué. Si de verdad no hay nada, lo dice
          // al tocarlo, que es una respuesta y no un botón muerto.
          NmButton.secondary(
            label: 'Restaurar desde la nube',
            block: true,
            icon: PhosphorIcons.cloudArrowDown(),
            loading: _restoring,
            onPressed: _pickAndRestore,
          ),

          const SizedBox(height: NmSpace.s6),
          Text(
            'La copia sube sola cada vez que registrás algo.',
            style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
          ),
        ],
      ),
    );
  }

  String _statusLabel(BackupState? state) => switch (state) {
    BackupUploading() => 'Subiendo…',
    BackupFailed() => 'Falló, se reintenta',
    BackupHeldEmpty() => 'En pausa',
    _ => 'Al día',
  };
}

/// Cómo viene la escritura en las tablas.
///
/// El respaldo JSON y las tablas son dos caminos distintos con dos estados
/// distintos, y hasta ahora esta pantalla solo mostraba el primero. El segundo
/// —el que guarda cada comida como fila— podía estar fallando en todas las
/// subidas sin que nada lo dijera: así se perdieron meses de datos.
///
/// Cuando anda, esto ocupa una línea gris. Cuando no, dice qué tabla falló y
/// por qué, que es lo que hace falta para arreglarlo.
class _SyncStatus extends StatelessWidget {
  const _SyncStatus({required this.state});

  final SyncState? state;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final current = state;
    if (current == null) return const SizedBox.shrink();

    if (current is SyncFailed) {
      return Padding(
        padding: const EdgeInsets.only(top: NmSpace.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ErrorState(
              message: current.error.message,
              code: current.error.code.wire,
            ),
            const SizedBox(height: NmSpace.s2),
            Text(
              // Lo importante que la persona necesita saber, y que es verdad:
              // el dato está en el teléfono. Lo que falta es que llegue.
              'Tus datos están en este teléfono y se reintenta con cada '
              'cambio. Si esto no se va, mostrale este mensaje a quien '
              'mantiene la app.',
              style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
            ),
          ],
        ),
      );
    }

    final texto = switch (current) {
      SyncRunning() => 'Guardando en la base…',
      SyncIdle(:final lastPush) when lastPush != null =>
        'Última escritura en la base: ${timeOfDay(lastPush)}',
      _ => null,
    };
    if (texto == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: NmSpace.s3),
      child: Text(
        texto,
        style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
      ),
    );
  }
}
