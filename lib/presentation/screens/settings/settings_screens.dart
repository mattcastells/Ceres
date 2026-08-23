import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/error/app_error.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/formats.dart';
import '../../../domain/enums/enums.dart';
import '../../components/activity/activity_inputs.dart';
import '../../components/brand/brand_mark.dart';
import '../../components/charts/calorie_ring.dart';
import '../../components/system/buttons.dart';
import '../../components/system/inputs.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/update_providers.dart';
import '../activity/duplicate_dialog.dart';

/// Configuración (raíz).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final repo = ref.watch(repositoryProvider);

    return NmScreen(
      title: 'Configuración',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          NmCard(
            padding: const EdgeInsets.symmetric(vertical: NmSpace.s2),
            child: Column(
              children: <Widget>[
                NmListRow(
                  title: 'Crédito de ejercicio',
                  subtitle: profile.effectiveCreditPercentage == 0
                      ? 'El ejercicio no suma a tu presupuesto'
                      : 'Suma el ${profile.effectiveCreditPercentage} %',
                  leading: Icon(PhosphorIcons.personSimpleRun()),
                  onTap: () => context.push(Routes.exerciseCredit),
                ),
                const NmDivider(indent: NmSpace.s6),
                NmListRow(
                  title: 'Unidades',
                  subtitle: profile.unitSystem.label,
                  leading: Icon(PhosphorIcons.ruler()),
                  onTap: () => context.push(Routes.units),
                ),
                const NmDivider(indent: NmSpace.s6),
                NmListRow(
                  title: 'Apariencia',
                  subtitle: profile.themeMode.label,
                  leading: Icon(PhosphorIcons.palette()),
                  onTap: () => context.push(Routes.appearance),
                ),
                const NmDivider(indent: NmSpace.s6),
                NmListRow(
                  title: 'Recordatorios',
                  leading: Icon(PhosphorIcons.bell()),
                  onTap: () => context.push(Routes.notifications),
                ),
                const NmDivider(indent: NmSpace.s6),
                if (repo.isPlatformSupported)
                  NmListRow(
                    title: 'Integraciones de salud',
                    subtitle: 'Health Connect',
                    leading: Icon(PhosphorIcons.heartbeat()),
                    onTap: () => context.push(Routes.integrations),
                  ),
                if (repo.isPlatformSupported)
                  const NmDivider(indent: NmSpace.s6),
                NmListRow(
                  title: 'Tu informe',
                  subtitle: 'Un PDF con tus promedios y tu evolución',
                  leading: Icon(PhosphorIcons.filePdf()),
                  onTap: () => context.push(Routes.report),
                ),
                const NmDivider(indent: NmSpace.s6),
                NmListRow(
                  title: 'Privacidad y datos',
                  leading: Icon(PhosphorIcons.shieldCheck()),
                  onTap: () => context.push(Routes.privacy),
                ),
                const NmDivider(indent: NmSpace.s6),
                NmListRow(
                  title: 'Respaldo en la nube',
                  subtitle: ref.watch(isCloudEnabledProvider)
                      ? 'Se guarda solo cada vez que registrás algo'
                      : 'Esta compilación no tiene servidor',
                  leading: Icon(PhosphorIcons.cloudArrowUp()),
                  onTap: () => context.push(Routes.cloudBackup),
                ),
                const NmDivider(indent: NmSpace.s6),
                NmListRow(
                  title: 'Actualizaciones',
                  subtitle: 'Buscar una versión nueva',
                  leading: Icon(PhosphorIcons.downloadSimple()),
                  onTap: () => context.push(Routes.updates),
                ),
                const NmDivider(indent: NmSpace.s6),
                NmListRow(
                  title: 'Acerca de Ceres',
                  leading: Icon(PhosphorIcons.info()),
                  onTap: () => context.push(Routes.about),
                ),
              ],
            ),
          ),
          const SizedBox(height: NmSpace.s8),
          const NmSectionHeader(title: 'Avanzado'),
          NmCard(
            child: Column(
              children: <Widget>[
                NmSwitchRow(
                  title: 'Mostrar calorías netas',
                  subtitle: 'Consumidas menos aplicadas, en Inicio',
                  value: profile.showNetCalories,
                  onChanged: repo.setShowNetCalories,
                ),
                const NmDivider(),
                NmListRow(
                  title: 'Meta de agua',
                  subtitle:
                      '${profile.waterGoalGlasses} vasos de '
                      '${profile.glassSizeMl} ml por día',
                  leading: Icon(PhosphorIcons.drop()),
                  onTap: () => context.push(Routes.water),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// S-28 · Crédito de ejercicio. ★
class ExerciseCreditScreen extends ConsumerStatefulWidget {
  const ExerciseCreditScreen({super.key});

  @override
  ConsumerState<ExerciseCreditScreen> createState() =>
      _ExerciseCreditScreenState();
}

class _ExerciseCreditScreenState extends ConsumerState<ExerciseCreditScreen> {
  bool _changed = false;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final summary = ref.watch(todaySummaryProvider);
    final repo = ref.watch(repositoryProvider);

    return NmScreen(
      title: 'Crédito de ejercicio',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          Text(
            'Sumar las calorías del ejercicio a mi presupuesto diario',
            style: NmTextStyles.from(NmType.h3, color: context.nm.text),
          ),
          const SizedBox(height: NmSpace.s6),
          ExerciseCreditSelector(
            value: profile.exerciseCreditPercentage,
            enabled: profile.exerciseCreditEnabled,
            previewEstimatedCalories: summary.exerciseEstimatedKcal,
            onChanged: (value) {
              setState(() => _changed = true);
              repo.setExerciseCredit(
                percentage: value,
                enabled: profile.exerciseCreditEnabled,
              );
            },
            onToggleEnabled: (enabled) {
              setState(() => _changed = true);
              repo.setExerciseCredit(
                percentage: profile.exerciseCreditPercentage,
                enabled: enabled,
              );
            },
          ),
          if (_changed) ...<Widget>[
            const SizedBox(height: NmSpace.s6),
            const InfoNote(
              tone: NmNoteTone.info,
              text: 'Aplicamos el cambio desde hoy. Los días anteriores '
                  'quedan como estaban.',
            ),
          ],
        ],
      ),
    );
  }
}

/// S-31 · Apariencia, con previsualización en vivo.
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final summary = ref.watch(todaySummaryProvider);
    final repo = ref.watch(repositoryProvider);

    return NmScreen(
      title: 'Apariencia',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          for (final mode in ThemeModeSetting.values)
            Padding(
              padding: const EdgeInsets.only(bottom: NmSpace.s2),
              child: NmRadioRow<ThemeModeSetting>(
                title: mode.label,
                value: mode,
                groupValue: profile.themeMode,
                onChanged: repo.setThemeMode,
              ),
            ),
          const SizedBox(height: NmSpace.s6),
          const NmSectionHeader(title: 'Previsualización'),
          NmCard(
            child: Column(
              children: <Widget>[
                Center(
                  child: CalorieRing(
                    consumed: summary.consumedKcal,
                    adjustedTarget: summary.adjustedTarget,
                    remaining: summary.remainingKcal,
                    size: 140,
                  ),
                ),
                const SizedBox(height: NmSpace.s4),
                ValueRow(
                  label: 'Objetivo base',
                  value: Fmt.kcal(summary.baseTarget),
                ),
                ValueRow(
                  label: 'Consumido',
                  value: '−${Fmt.kcal(summary.consumedKcal)}',
                ),
              ],
            ),
          ),
          const SizedBox(height: NmSpace.s4),
          const InfoNote(
            text: 'El tema oscuro es el canónico del sistema de diseño; el '
                'claro se deriva invirtiendo la rampa neutral y bajando el '
                'acento un paso para conservar el contraste.',
          ),
        ],
      ),
    );
  }
}

/// Unidades.
class UnitsScreen extends ConsumerWidget {
  const UnitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final repo = ref.watch(repositoryProvider);

    return NmScreen(
      title: 'Unidades',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          for (final system in UnitSystem.values)
            Padding(
              padding: const EdgeInsets.only(bottom: NmSpace.s2),
              child: NmRadioRow<UnitSystem>(
                title: system.label,
                value: system,
                groupValue: profile.unitSystem,
                onChanged: repo.setUnitSystem,
              ),
            ),
          const SizedBox(height: NmSpace.s4),
          const InfoNote(
            text: 'La conversión es solo de presentación: por dentro todo se '
                'guarda en kilos, centímetros y metros.',
          ),
        ],
      ),
    );
  }
}

/// Notificaciones (fuera del MVP: se declara y se explica).
/// S-29 · Integraciones de salud. Solo en Android (D-21).
class IntegrationsScreen extends ConsumerStatefulWidget {
  const IntegrationsScreen({super.key});

  @override
  ConsumerState<IntegrationsScreen> createState() => _IntegrationsScreenState();
}

class _IntegrationsScreenState extends ConsumerState<IntegrationsScreen> {
  bool _syncing = false;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final repo = ref.watch(repositoryProvider);
    final integration = ref.watch(integrationProvider);
    final pending = ref.watch(pendingReviewsProvider);

    if (!repo.isPlatformSupported || !FeatureFlags.healthConnectSync) {
      return NmScreen(
        title: 'Integraciones de salud',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: NmSpace.s4),
            InfoNote(
              tone: NmNoteTone.caution,
              text: repo.isPlatformSupported
                  ? 'Esta compilación tiene la importación apagada '
                        '(`NM_HEALTH_SYNC=false`).'
                  : 'Health Connect está disponible solo en Android.',
            ),
            const SizedBox(height: NmSpace.s6),
            const InfoNote(
              text: 'Ceres funciona completo con registro manual: ninguna '
                  'pantalla obligatoria depende de una integración externa.',
            ),
          ],
        ),
      );
    }

    return NmScreen(
      title: 'Integraciones de salud',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          NmCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      PhosphorIcons.heartbeat(),
                      size: NmIconSize.lg,
                      color: nm.text,
                    ),
                    const SizedBox(width: NmSpace.s3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            'Health Connect',
                            style: NmTextStyles.from(
                              NmType.h4,
                              color: nm.text,
                            ),
                          ),
                          Text(
                            integration.status.label,
                            style: NmTextStyles.from(
                              NmType.caption,
                              color: nm.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    NmTag(
                      label: integration.isConnected
                          ? 'Conectada'
                          : 'Sin conectar',
                      variant: integration.isConnected
                          ? NmTagVariant.success
                          : NmTagVariant.outline,
                    ),
                  ],
                ),
                const SizedBox(height: NmSpace.s4),
                if (integration.lastSyncAt != null)
                  ValueRow(
                    label: 'Última sincronización',
                    value:
                        '${friendlyDay(integration.lastSyncAt!)} · '
                        '${timeOfDay(integration.lastSyncAt!)}',
                    muted: true,
                  ),
                ValueRow(
                  label: 'Registros importados',
                  value: '${integration.importedCount}',
                  muted: true,
                ),
                if (integration.permissions.isNotEmpty) ...<Widget>[
                  const SizedBox(height: NmSpace.s3),
                  Wrap(
                    spacing: NmSpace.s2,
                    runSpacing: NmSpace.s2,
                    children: <Widget>[
                      for (final permission in integration.permissions)
                        NmTag(
                          label: permission,
                          variant: NmTagVariant.neutral,
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: NmSpace.s4),
                if (!integration.isConnected)
                  NmButton(
                    label: 'Conectar',
                    block: true,
                    onPressed: () async {
                      final accepted = await showNmDialog<bool>(
                        context: context,
                        builder: (context) => NmDialog(
                          title: 'Qué permisos pedimos',
                          body:
                              'Sesiones de ejercicio, calorías activas, pasos, '
                              'distancia y frecuencia cardíaca. Solo lectura: '
                              'Ceres no escribe nada en tu historial de '
                              'salud.',
                          actions: <Widget>[
                            NmButton.ghost(
                              label: 'Ahora no',
                              onPressed: () =>
                                  Navigator.of(context).pop(false),
                            ),
                            NmButton(
                              label: 'Conectar',
                              onPressed: () => Navigator.of(context).pop(true),
                            ),
                          ],
                        ),
                      );
                      if (accepted != true) return;
                      await repo.connect();
                    },
                  )
                else
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: NmButton(
                          label: 'Sincronizar ahora',
                          loading: _syncing,
                          block: true,
                          onPressed: () async {
                            setState(() => _syncing = true);
                            final result = await repo.sync();
                            if (!context.mounted) return;
                            setState(() => _syncing = false);
                            NmSnackbar.show(
                              context,
                              result.duplicates.isEmpty
                                  ? 'Se importaron ${result.imported} '
                                        'actividades.'
                                  : 'Se importaron ${result.imported} '
                                        'actividades. '
                                        '${result.duplicates.length} '
                                        'necesitan tu confirmación.',
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: NmSpace.s2),
                      NmButton.secondary(
                        label: 'Desconectar',
                        onPressed: repo.disconnect,
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (pending.isNotEmpty) ...<Widget>[
            const SizedBox(height: NmSpace.s6),
            const NmSectionHeader(title: 'Necesitan tu confirmación'),
            for (final candidate in pending)
              Padding(
                padding: const EdgeInsets.only(bottom: NmSpace.s2),
                child: NmCard(
                  onTap: () => showDuplicateDialog(context, ref, candidate),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        PhosphorIcons.warning(),
                        size: NmIconSize.md,
                        color: nm.caution,
                      ),
                      const SizedBox(width: NmSpace.s3),
                      Expanded(
                        child: Text(
                          '${candidate.incoming.displayName} · '
                          '${timeOfDay(candidate.incoming.startedAt)} '
                          'se parece a un registro tuyo',
                          style: NmTextStyles.from(
                            NmType.bodySm,
                            color: nm.text,
                          ),
                        ),
                      ),
                      NmButton.ghost(
                        label: 'Revisar',
                        onPressed: () =>
                            showDuplicateDialog(context, ref, candidate),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: NmSpace.s6),
          const InfoNote(
            text: 'Usamos las calorías activas del proveedor, no el total: el '
                'total incluye el metabolismo basal, que ya está dentro de tu '
                'objetivo.',
          ),
          const SizedBox(height: NmSpace.s4),
          if (integration.importedCount > 0)
            NmButton(
              label: 'Borrar los datos importados',
              variant: NmButtonVariant.danger,
              block: true,
              onPressed: () async {
                final confirmed = await confirmDelete(
                  context,
                  title: '¿Borrar lo importado?',
                  body: 'Se borran solo las actividades importadas desde '
                      'Health Connect. Tus registros manuales quedan intactos.',
                  confirmLabel: 'Borrar importados',
                );
                if (!confirmed) return;
                await repo.deleteImported();
              },
            ),
        ],
      ),
    );
  }
}

/// S-30 y S-35 · Privacidad y datos.
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nm = context.nm;
    final cloudEnabled = ref.watch(isCloudEnabledProvider);

    return NmScreen(
      title: 'Privacidad y datos',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          const NmSectionHeader(title: 'Qué guardamos'),
          NmCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final item in const <String>[
                  'Tu perfil corporal y tu objetivo calórico',
                  'Las comidas y sus ítems',
                  'Las actividades, con su método de estimación',
                  'Los pesos y las medidas corporales',
                  'Las fotos de comida que saques',
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: NmSpace.s1),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          PhosphorIcons.checkCircle(),
                          size: NmIconSize.sm,
                          color: nm.textMuted,
                        ),
                        const SizedBox(width: NmSpace.s2),
                        Expanded(
                          child: Text(
                            item,
                            style: NmTextStyles.from(
                              NmType.bodySm,
                              color: nm.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: NmSpace.s6),
          InfoNote(
            text: cloudEnabled
                ? 'Tus datos se guardan en Supabase a medida que registrás '
                      'algo; las fotos se analizan con Gemini.'
                : 'Esta compilación no tiene servidor: todo vive solo en tu '
                      'teléfono y no sale de acá.',
          ),
          const SizedBox(height: NmSpace.s3),
          // El micrófono es el único permiso que no deja rastro en la lista de
          // arriba, y por eso se explica acá: cada permiso que pedimos tiene
          // que poder justificarse en esta pantalla.
          const InfoNote(
            text: 'El micrófono se usa solo mientras dictás una comida, y lo '
                'transcribe tu propio teléfono: no guardamos el audio ni lo '
                'mandamos a ningún lado.',
          ),
          const SizedBox(height: NmSpace.s6),
          const NmSectionHeader(title: 'Respaldo'),
          InfoNote(
            tone: cloudEnabled ? NmNoteTone.info : NmNoteTone.caution,
            text: cloudEnabled
                ? 'Ya tenés respaldo automático en la nube (Configuración → '
                      'Respaldo en la nube). Este archivo es una copia '
                      'portátil adicional, para llevarte los datos a mano.'
                : 'Sin servidor, este archivo es tu único respaldo: si '
                      'perdés el teléfono, perdés el historial. Guardalo '
                      'cada tanto en Drive o mandátelo por correo.',
          ),
          const SizedBox(height: NmSpace.s4),
          const _BackupActions(),
          const SizedBox(height: NmSpace.s8),
          Container(
            padding: const EdgeInsets.all(NmSpace.s4),
            decoration: BoxDecoration(
              borderRadius: NmRadius.brMd,
              border: Border.all(color: nm.danger.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Eliminar la cuenta',
                  style: NmTextStyles.from(NmType.h4, color: nm.danger),
                ),
                const SizedBox(height: NmSpace.s2),
                Text(
                  'Se borran el perfil, las comidas, las actividades, los '
                  'pesos, las medidas, las fotos y los respaldos, del teléfono '
                  'y del servidor. Es inmediato y no se puede deshacer.',
                  style: NmTextStyles.from(
                    NmType.caption,
                    color: nm.textMuted,
                  ),
                ),
                const SizedBox(height: NmSpace.s4),
                NmButton(
                  label: 'Eliminar mi cuenta',
                  variant: NmButtonVariant.danger,
                  onPressed: () => context.push(Routes.deleteAccount),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Exportar e importar el respaldo JSON.
class _BackupActions extends ConsumerStatefulWidget {
  const _BackupActions();

  @override
  ConsumerState<_BackupActions> createState() => _BackupActionsState();
}

class _BackupActionsState extends ConsumerState<_BackupActions> {
  bool _busy = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(repositoryProvider);
      final json = repo.exportJson();
      final directory = await getTemporaryDirectory();
      final name = 'ceres-respaldo-${isoDate(DateTime.now())}.json';
      final file = File('${directory.path}/$name');
      await file.writeAsString(json);

      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path, mimeType: 'application/json')],
          fileNameOverrides: <String>[name],
          subject: 'Respaldo de Ceres',
        ),
      );
    } on Object {
      if (!mounted) return;
      NmSnackbar.show(context, 'No pudimos generar el archivo de respaldo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    const typeGroup = XTypeGroup(
      label: 'Respaldo de Ceres',
      extensions: <String>['json'],
      mimeTypes: <String>['application/json'],
    );

    final file = await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
    if (file == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final repo = ref.read(repositoryProvider);
      final json = await file.readAsString();
      final preview = repo.inspectBackup(json);

      if (!mounted) return;
      setState(() => _busy = false);

      // Importar reemplaza todo: se dice con los números a la vista.
      final confirmed = await showNmDialog<bool>(
        context: context,
        builder: (context) => NmDialog(
          title: '¿Reemplazar todo con este respaldo?',
          body: 'El archivo trae ${preview.description}. Lo que tengas '
              'cargado ahora se pierde y no se puede deshacer.',
          actions: <Widget>[
            NmButton.ghost(
              label: 'Cancelar',
              onPressed: () => Navigator.of(context).pop(false),
            ),
            NmButton(
              label: 'Reemplazar',
              variant: NmButtonVariant.danger,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      setState(() => _busy = true);
      final summary = await repo.importJson(json);
      if (!mounted) return;
      NmSnackbar.show(context, 'Restauramos ${summary.description}.');
    } on AppError catch (error) {
      if (!mounted) return;
      NmSnackbar.show(context, error.message);
    } on Object {
      if (!mounted) return;
      NmSnackbar.show(context, 'No pudimos leer ese archivo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      NmButton.secondary(
        label: 'Exportar mis datos',
        block: true,
        icon: PhosphorIcons.arrowUp(),
        loading: _busy,
        onPressed: _export,
      ),
      const SizedBox(height: NmSpace.s3),
      NmButton.secondary(
        label: 'Importar un respaldo',
        block: true,
        icon: PhosphorIcons.arrowDown(),
        onPressed: _busy ? null : _import,
      ),
    ],
  );
}

/// F-14 · Eliminar cuenta, confirmación en dos pasos.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final TextEditingController _confirm = TextEditingController();
  int _step = 1;
  bool _busy = false;

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  /// Borra primero del servidor y **recién después** limpia el teléfono.
  ///
  /// El orden no es cosmético. Al revés —o como estaba antes, que era solo
  /// `signOut` y nada más—, la persona se queda sin sus datos locales y con la
  /// cuenta viva en el servidor: lo peor de los dos mundos. Si el borrado falla
  /// no se toca nada y se dice qué pasó.
  Future<void> _delete() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(authGatewayProvider).deleteAccount();
      await ref.read(repositoryProvider).signOut();
      if (!mounted) return;
      context.go(Routes.welcome);
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      NmSnackbar.show(context, error.message);
    } on Object {
      if (!mounted) return;
      setState(() => _busy = false);
      NmSnackbar.show(
        context,
        'No pudimos borrar la cuenta. Probá de nuevo en un rato.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canDelete = _confirm.text.trim().toUpperCase() == 'ELIMINAR';

    return NmScreen(
      title: 'Eliminar cuenta',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          StepIndicator(current: _step, total: 2),
          const SizedBox(height: NmSpace.s6),
          if (_step == 1) ...<Widget>[
            const InfoNote(
              tone: NmNoteTone.caution,
              text: 'Antes de borrar todo, podés exportar tus datos.',
            ),
            const SizedBox(height: NmSpace.s6),
            NmButton.secondary(
              label: 'Exportar mis datos primero',
              block: true,
              // El respaldo vive en Privacidad, de donde se llega acá.
              onPressed: () => context.pop(),
            ),
            const SizedBox(height: NmSpace.s3),
            NmButton(
              label: 'Entiendo, continuar',
              block: true,
              onPressed: () => setState(() => _step = 2),
            ),
          ] else ...<Widget>[
            Text(
              'Escribí ELIMINAR para confirmar.',
              style: NmTextStyles.from(
                NmType.bodySm,
                color: context.nm.textMuted,
              ),
            ),
            const SizedBox(height: NmSpace.s4),
            NmTextField(
              label: 'Confirmación',
              controller: _confirm,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: NmSpace.s6),
            NmButton(
              label: 'Eliminar definitivamente',
              variant: NmButtonVariant.danger,
              block: true,
              loading: _busy,
              onPressed: canDelete ? _delete : null,
            ),
          ],
        ],
      ),
    );
  }
}

/// Acerca de.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nm = context.nm;
    final version = ref.watch(installedVersionLabelProvider);
    return NmScreen(
      title: 'Acerca de',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s8),
          const Center(child: BrandWordmark(markSize: 40)),
          const SizedBox(height: NmSpace.s6),
          Text(
            'Ceres muestra el cálculo completo del día en vez de un único '
            'número mágico, y nunca presenta una estimación como si fuera una '
            'medición.',
            style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
          ),
          const SizedBox(height: NmSpace.s6),
          NmCard(
            child: Column(
              children: <Widget>[
                // Sale del paquete instalado, no de una constante: una versión
                // escrita a mano queda desactualizada al primer release.
                ValueRow(
                  label: 'Versión',
                  value: version.maybeWhen(
                    data: (value) => value,
                    orElse: () => '—',
                  ),
                ),
                const ValueRow(
                  label: 'Sistema de diseño',
                  value: 'Nocturne 1.0.0',
                ),
              ],
            ),
          ),
          // Acá había un "Buscar actualizaciones" que empujaba a la misma
          // pantalla que Configuración → Actualizaciones, la fila de arriba de
          // "Acerca de Ceres". Dos puertas a lo mismo, a un toque de
          // distancia, hacen dudar de si son lo mismo. Las actualizaciones
          // tienen su sección; esta pantalla dice qué versión hay instalada.
        ],
      ),
    );
  }
}
