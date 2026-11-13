import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/formats.dart';
import '../../../core/utils/icons.dart';
import '../../../domain/enums/enums.dart';
import '../../../domain/models/activity.dart';
import '../../components/activity/badges.dart';
import '../../components/activity/exercise_calories_estimate.dart';
import '../../components/feedback/feedback.dart';
import '../../components/system/buttons.dart';
import '../../components/system/inputs.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';

/// S-11 · Buscar actividad. Devuelve el `activityTypeId` elegido.
class ActivitySearchScreen extends ConsumerStatefulWidget {
  const ActivitySearchScreen({super.key});

  @override
  ConsumerState<ActivitySearchScreen> createState() =>
      _ActivitySearchScreenState();
}

class _ActivitySearchScreenState extends ConsumerState<ActivitySearchScreen> {
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final types = ref.watch(activityTypesProvider);
    final query = _query.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? types
        : types
              .where((t) => t.displayName.toLowerCase().contains(query))
              .toList();

    final grouped = <ActivityCategory, List<ActivityType>>{};
    for (final type in filtered) {
      grouped.putIfAbsent(type.category, () => <ActivityType>[]).add(type);
    }

    return Scaffold(
      backgroundColor: nm.bg,
      appBar: const NmModalHeader(title: 'Buscar actividad'),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            Padding(
              padding: EdgeInsets.all(context.screenPadding),
              child: TextField(
                controller: _query,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Buscá una actividad',
                  prefixIcon: Icon(
                    PhosphorIcons.magnifyingGlass(),
                    size: NmIconSize.md,
                    color: nm.textMuted,
                  ),
                ),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? EmptyState(
                      icon: PhosphorIcons.magnifyingGlass(),
                      title: 'No encontramos esa actividad',
                      body: 'Podés crear una personalizada con tu propio MET.',
                      primaryLabel: 'Crear actividad personalizada',
                      onPrimary: () => context.pushReplacement(
                        '${Routes.activityNew}?mode=custom',
                      ),
                    )
                  : ListView(
                      padding: EdgeInsets.symmetric(
                        horizontal: context.screenPadding,
                      ),
                      children: <Widget>[
                        for (final entry in grouped.entries) ...<Widget>[
                          NmSectionHeader(title: entry.key.label),
                          for (final type in entry.value)
                            NmListRow(
                              title: type.displayName,
                              subtitle:
                                  'MET moderado ${Fmt.met(type.metFor(Intensity.moderate))}',
                              leading: Icon(
                                NmIcons.activity(type.iconName),
                                size: NmIconSize.lg,
                                color: nm.textMuted,
                              ),
                              onTap: () => context.pop(type.id),
                            ),
                          const SizedBox(height: NmSpace.s6),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// S-13 · Detalle de actividad. Ver todo lo registrado y poder corregirlo.
class ActivityDetailScreen extends ConsumerWidget {
  const ActivityDetailScreen({required this.activityId, super.key});

  final String activityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nm = context.nm;
    ref.watch(appRevisionProvider);
    final repo = ref.watch(repositoryProvider);
    final activity = repo.activityById(activityId);
    final profile = ref.watch(profileProvider);
    final units = ref.watch(unitSystemProvider);

    if (activity == null || activity.isDeleted) {
      return NmScreen(
        title: 'Actividad',
        child: ErrorState(
          message: 'Este registro ya no existe.',
          onRetry: () => context.pop(),
          retryLabel: 'Volver',
        ),
      );
    }

    return NmScreen(
      title: activity.displayName,
      actions: <Widget>[
        IconButton(
          tooltip: activity.isFavorite
              ? 'Quitar de favoritas'
              : 'Marcar como favorita',
          onPressed: () => repo.toggleFavorite(activity.id),
          icon: Icon(
            activity.isFavorite
                ? PhosphorIcons.star(PhosphorIconsStyle.fill)
                : PhosphorIcons.star(),
          ),
        ),
        IconButton(
          tooltip: 'Editar',
          onPressed: () => context.push(Routes.activityEdit(activity.id)),
          icon: Icon(PhosphorIcons.pencilSimple()),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          Row(
            children: <Widget>[
              // Igual que en la lista: "Manual" es lo esperado, no una marca.
              if (activity.origin != DataOrigin.manual) ...<Widget>[
                DataOriginBadge(
                  origin: activity.origin,
                  sourceLabel: activity.externalSource == null
                      ? null
                      : HealthProvider.healthConnect.label,
                ),
                const SizedBox(width: NmSpace.s2),
              ],
              SyncStatusBadge(status: activity.syncStatus, compact: false),
            ],
          ),
          const SizedBox(height: NmSpace.s4),
          Text(
            '${longDay(activity.localDate)} · ${timeOfDay(activity.startedAt)}',
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted).tnum,
          ),
          const SizedBox(height: NmSpace.s6),

          ExerciseCaloriesEstimate(
            calories: activity.estimatedCalories,
            method: activity.estimationMethod,
            metValue: activity.metValue,
            weightKg: activity.weightKgUsed,
            durationMinutes: activity.durationMinutes,
            originalCalories: activity.originalCalories,
            sourceLabel: activity.externalSource == null
                ? null
                : HealthProvider.healthConnect.label,
            onOverride: () => _openOverride(context, ref, activity),
            onRestore: activity.wasOverridden
                ? () => repo.restoreCalculatedCalories(activity.id)
                : null,
          ),

          const SizedBox(height: NmSpace.s6),
          NmCard(
            child: Column(
              children: <Widget>[
                ValueRow(
                  label: 'Duración',
                  value: Fmt.duration(activity.durationMinutes),
                ),
                ValueRow(
                  label: 'Intensidad',
                  value: activity.intensity.label,
                ),
                if (activity.distanceMeters != null)
                  ValueRow(
                    label: 'Distancia',
                    value: Fmt.distance(activity.distanceMeters!, units),
                  ),
                if (activity.steps != null)
                  ValueRow(
                    label: 'Pasos',
                    value: Fmt.steps(activity.steps!),
                  ),
                if (activity.averageHeartRate != null)
                  ValueRow(
                    label: 'FC promedio',
                    value: '${activity.averageHeartRate} bpm',
                  ),
                if (activity.maximumHeartRate != null)
                  ValueRow(
                    label: 'FC máxima',
                    value: '${activity.maximumHeartRate} bpm',
                  ),
                if (activity.deviceName != null)
                  ValueRow(
                    label: 'Dispositivo',
                    value: activity.deviceName!,
                    muted: true,
                  ),
              ],
            ),
          ),

          if (activity.notes != null) ...<Widget>[
            const SizedBox(height: NmSpace.s4),
            NmCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'NOTAS',
                    style: NmTextStyles.from(
                      NmType.overline,
                      color: nm.textMuted,
                    ),
                  ),
                  const SizedBox(height: NmSpace.s2),
                  Text(
                    activity.notes!,
                    style: NmTextStyles.from(NmType.bodySm, color: nm.text),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: NmSpace.s4),
          InfoNote(
            text: profile.effectiveCreditPercentage == 0
                ? 'Con tu configuración, el ejercicio no suma a tu objetivo.'
                : 'Aporta +${Fmt.integer(activity.appliedCalories)} kcal a tu '
                      'objetivo de ese día '
                      '(${activity.exerciseCreditPercentage} %).',
          ),

          const SizedBox(height: NmSpace.s6),
          Wrap(
            spacing: NmSpace.s2,
            runSpacing: NmSpace.s2,
            children: <Widget>[
              NmButton.secondary(
                label: 'Duplicar hoy',
                onPressed: () async {
                  await repo.duplicateActivity(activity.id, today());
                  if (!context.mounted) return;
                  NmSnackbar.show(context, 'Actividad duplicada hoy');
                },
              ),
              NmButton(
                label: 'Eliminar',
                variant: NmButtonVariant.danger,
                onPressed: () async {
                  final confirmed = await confirmDelete(
                    context,
                    title: '¿Eliminar la actividad?',
                    body: 'Podés deshacer durante unos segundos.',
                  );
                  if (!confirmed || !context.mounted) return;
                  await repo.deleteActivity(activity.id);
                  if (!context.mounted) return;
                  context.pop();
                  NmSnackbar.show(
                    context,
                    'Actividad eliminada',
                    actionLabel: 'Deshacer',
                    undo: true,
                    onAction: () => repo.restoreActivity(activity.id),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// F-10 · Corregir calorías. Conserva el valor original (RN-04).
  Future<void> _openOverride(
    BuildContext context,
    WidgetRef ref,
    Activity activity,
  ) async {
    final controller = TextEditingController(
      text: activity.estimatedCalories.toString(),
    );
    String? reason = activity.overrideReason;

    final result = await showNmDialog<(int, String?)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => NmDialog(
          // Mismo título y texto que en el formulario: se abre desde el mismo
          // botón, "Ingresar otro valor".
          title: 'Ingresar otro valor',
          body: 'El valor calculado es '
              '${Fmt.integer(activity.originalCalories ?? activity.estimatedCalories)} '
              'kcal y queda guardado aparte.',
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              NmNumberField(
                label: 'Calorías',
                controller: controller,
                suffix: 'kcal',
                autofocus: true,
              ),
              const SizedBox(height: NmSpace.s4),
              Wrap(
                spacing: NmSpace.s2,
                runSpacing: NmSpace.s2,
                children: <Widget>[
                  for (final option in const <String>[
                    'Mi reloj marcó otra cosa',
                    'Me pareció mucho',
                    'Me pareció poco',
                    'Otro',
                  ])
                    NmChip(
                      label: option,
                      selected: reason == option,
                      onTap: () => setLocal(() => reason = option),
                    ),
                ],
              ),
            ],
          ),
          actions: <Widget>[
            NmButton.ghost(
              label: 'Cancelar',
              onPressed: () => Navigator.of(context).pop(),
            ),
            NmButton(
              label: 'Guardar',
              onPressed: () {
                final value = int.tryParse(controller.text);
                if (value == null || value < 1 || value > 10000) return;
                Navigator.of(context).pop((value, reason));
              },
            ),
          ],
        ),
      ),
    );

    controller.dispose();
    if (result == null) return;
    await ref
        .read(repositoryProvider)
        .overrideCalories(activity.id, result.$1, result.$2);
  }
}
