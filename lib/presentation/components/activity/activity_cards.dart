import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/motion.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/formats.dart';
import '../../../core/utils/icons.dart';
import '../../../domain/calculations/adherence.dart';
import '../../../domain/enums/enums.dart';
import '../../../domain/models/activity.dart';
import '../../../domain/models/summaries.dart';
import '../system/buttons.dart';
import '../system/surfaces.dart';
import 'badges.dart';

/// Fila de una actividad en Inicio, Historial o detalle del día.
///
/// Swipe izquierda → Eliminar; swipe derecha → Duplicar; long-press → menú.
/// Las acciones de swipe se exponen también en el menú, porque el swipe no es
/// accesible por lector de pantalla (05-component-library §1).
class ActivityListItem extends StatelessWidget {
  const ActivityListItem({
    required this.activity,
    this.showDate = false,
    this.dense = false,
    this.readOnly = false,
    this.onTap,
    this.onEdit,
    this.onDuplicate,
    this.onDelete,
    this.onToggleFavorite,
    this.onReview,
    super.key,
  });

  final Activity activity;
  final bool showDate;
  final bool dense;
  final bool readOnly;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final type = activity.activityType;

    final row = Semantics(
      button: onTap != null,
      label:
          '${activity.displayName}, ${Fmt.duration(activity.durationMinutes)}, '
          'aproximadamente ${Fmt.integer(activity.estimatedCalories)} calorías '
          'estimadas',
      customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
        if (onEdit != null)
          const CustomSemanticsAction(label: 'Editar'): onEdit!,
        if (onDuplicate != null)
          const CustomSemanticsAction(label: 'Duplicar'): onDuplicate!,
        if (onDelete != null)
          const CustomSemanticsAction(label: 'Eliminar'): onDelete!,
        if (onToggleFavorite != null)
          const CustomSemanticsAction(label: 'Marcar como favorita'):
              onToggleFavorite!,
      },
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          onLongPress: readOnly ? null : () => _openMenu(context),
          borderRadius: NmRadius.brMd,
          highlightColor: nm.hoverNeutral,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: NmSpace.s3,
              vertical: dense ? NmSpace.s2 : NmSpace.s3,
            ),
            child: Row(
              children: <Widget>[
                Container(
                  height: 40,
                  width: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: nm.surfaceRaised,
                    borderRadius: NmRadius.brMd,
                  ),
                  child: Icon(
                    NmIcons.activity(type?.iconName),
                    size: NmIconSize.lg,
                    color: nm.text,
                  ),
                ),
                const SizedBox(width: NmSpace.s4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              activity.displayName,
                              overflow: TextOverflow.ellipsis,
                              style: NmTextStyles.from(
                                NmType.body,
                                color: nm.text,
                              ),
                            ),
                          ),
                          if (activity.isFavorite) ...<Widget>[
                            const SizedBox(width: NmSpace.s2),
                            Icon(
                              PhosphorIcons.star(PhosphorIconsStyle.fill),
                              size: 13,
                              color: nm.accent,
                            ),
                          ],
                        ],
                      ),
                      Text(
                        <String>[
                          if (showDate) shortDay(activity.localDate),
                          timeOfDay(activity.startedAt),
                          Fmt.duration(activity.durationMinutes),
                          activity.intensity.label,
                        ].join(' · '),
                        style: NmTextStyles.from(
                          NmType.caption,
                          color: nm.textMuted,
                        ).tnum,
                      ),
                      // "Manual" es el caso normal y no aporta nada verlo en
                      // cada fila: solo se marca lo que vino de afuera. Si no
                      // queda nada que marcar, tampoco va la fila vacía.
                      if (activity.origin != DataOrigin.manual ||
                          activity.syncStatus != SyncStatus.synced) ...<Widget>[
                        const SizedBox(height: NmSpace.s1),
                        Wrap(
                          spacing: NmSpace.s2,
                          runSpacing: NmSpace.s1,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: <Widget>[
                            if (activity.origin != DataOrigin.manual)
                              DataOriginBadge(
                                origin: activity.origin,
                                sourceLabel: activity.externalSource == null
                                    ? null
                                    : HealthProvider.healthConnect.label,
                              ),
                            SyncStatusBadge(
                              status: activity.syncStatus,
                              onRetry: onReview,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: NmSpace.s3),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      Fmt.estimatedKcal(activity.estimatedCalories),
                      style: NmTextStyles.from(
                        NmType.bodySm,
                        color: nm.text,
                      ).tnum,
                    ),
                    if (activity.appliedCalories > 0)
                      Text(
                        '+${Fmt.integer(activity.appliedCalories)} aplicadas',
                        style: NmTextStyles.from(
                          NmType.micro,
                          color: nm.textMuted,
                        ).tnum,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (readOnly || onDelete == null) return row;

    return Dismissible(
      key: ValueKey<String>(activity.id),
      background: _SwipeBackground(
        icon: PhosphorIcons.copySimple(),
        label: 'Duplicar',
        alignment: Alignment.centerLeft,
        color: nm.accent,
      ),
      secondaryBackground: _SwipeBackground(
        icon: PhosphorIcons.trash(),
        label: 'Eliminar',
        alignment: Alignment.centerRight,
        color: nm.danger,
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onDuplicate?.call();
          return false;
        }
        onDelete?.call();
        return false;
      },
      child: row,
    );
  }

  void _openMenu(BuildContext context) {
    final nm = context.nm;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: nm.surface,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (onEdit != null)
              NmListRow(
                title: 'Editar',
                leading: Icon(PhosphorIcons.pencilSimple()),
                onTap: () {
                  Navigator.of(context).pop();
                  onEdit!();
                },
              ),
            if (onDuplicate != null)
              NmListRow(
                title: 'Duplicar',
                leading: Icon(PhosphorIcons.copySimple()),
                onTap: () {
                  Navigator.of(context).pop();
                  onDuplicate!();
                },
              ),
            if (onToggleFavorite != null)
              NmListRow(
                title: activity.isFavorite
                    ? 'Quitar de favoritas'
                    : 'Marcar como favorita',
                leading: Icon(PhosphorIcons.star()),
                onTap: () {
                  Navigator.of(context).pop();
                  onToggleFavorite!();
                },
              ),
            if (onDelete != null)
              NmListRow(
                title: 'Eliminar',
                leading: Icon(PhosphorIcons.trash(), color: nm.danger),
                onTap: () {
                  Navigator.of(context).pop();
                  onDelete!();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.icon,
    required this.label,
    required this.alignment,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Alignment alignment;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    alignment: alignment,
    padding: const EdgeInsets.symmetric(horizontal: NmSpace.s6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: NmRadius.brMd,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: NmIconSize.md, color: color),
        const SizedBox(width: NmSpace.s2),
        Text(label, style: NmTextStyles.from(NmType.caption, color: color)),
      ],
    ),
  );
}

/// Resumen de la actividad del día para Inicio (S-06 §5).
class ActivitySummaryCard extends StatelessWidget {
  const ActivitySummaryCard({
    required this.totals,
    required this.estimatedCalories,
    required this.appliedCalories,
    required this.creditPercentage,
    this.isRestDay = false,
    super.key,
  });

  final ActivityTotals totals;
  final int estimatedCalories;
  final int appliedCalories;
  final int creditPercentage;

  /// Solo lo dice: el descanso se marca y se desmarca en "Cómo estuvo el día".
  /// Acá había un "Quitar" que hacía lo mismo que el checkbox de abajo, en la
  /// misma pantalla. Lo mismo con el "Agregar" chico de la derecha: quien usa
  /// esta tarjeta ya tiene su "Agregar actividad" debajo de la lista.
  final bool isRestDay;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;

    if (isRestDay) {
      return Row(
        children: <Widget>[
          Icon(PhosphorIcons.bed(), size: NmIconSize.md, color: nm.textMuted),
          const SizedBox(width: NmSpace.s2),
          Expanded(
            child: Text(
              'Descanso planificado',
              style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
            ),
          ),
        ],
      );
    }

    // Sin actividad no dice nada: la tarjeta queda con su "Agregar actividad"
    // y el total aparece cuando se carga la primera.
    if (totals.sessions == 0) return const SizedBox.shrink();

    return Semantics(
      label:
          'Actividad del día: ${totals.minutes} minutos, aproximadamente '
          '${Fmt.integer(estimatedCalories)} calorías estimadas, '
          '${totals.sessions} ${totals.sessions == 1 ? 'sesión' : 'sesiones'}',
      child: ExcludeSemantics(
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'Total: ${Fmt.duration(totals.minutes)} · '
                    '${Fmt.estimatedKcal(estimatedCalories)} estimadas',
                    style: NmTextStyles.from(
                      NmType.bodySm,
                      color: nm.text,
                    ).tnum,
                  ),
                  if (creditPercentage > 0)
                    Text(
                      'Aportan +${Fmt.integer(appliedCalories)} kcal a tu '
                      'objetivo ($creditPercentage %)',
                      style: NmTextStyles.from(
                        NmType.caption,
                        color: nm.textMuted,
                      ).tnum,
                    ),
                  if (totals.steps != null)
                    Text(
                      '${Fmt.steps(totals.steps!)} pasos',
                      style: NmTextStyles.from(
                        NmType.caption,
                        color: nm.textMuted,
                      ).tnum,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta de una métrica con comparación neutral.
/// Fila de [StatCard] parejas.
///
/// Un `Row` común alinea al centro, así que dos tarjetas con distinta cantidad
/// de texto —una con leyenda y la otra sin— quedan de distinto alto y con los
/// bordes corridos. Acá se estiran todas a la más alta y el contenido arranca
/// arriba, que es lo que se espera de una grilla.
class StatCardRow extends StatelessWidget {
  const StatCardRow({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var i = 0; i < children.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: NmSpace.s3),
          Expanded(child: children[i]),
        ],
      ],
    ),
  );
}

class StatCard extends StatelessWidget {
  const StatCard({
    required this.label,
    required this.value,
    this.caption,
    this.icon,
    this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return NmCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: NmIconSize.sm, color: nm.textMuted),
                const SizedBox(width: NmSpace.s2),
              ],
              Expanded(
                child: Text(
                  label,
                  style: NmTextStyles.from(
                    NmType.overline,
                    color: nm.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: NmSpace.s2),
          Text(
            value,
            style: NmTextStyles.from(NmType.h3, color: nm.text).tnum,
          ),
          if (caption != null) ...<Widget>[
            const SizedBox(height: NmSpace.s1),
            Text(
              caption!,
              style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// Mensajes de consistencia con copy neutral (S-24, RN-14).
class ConsistencyNote extends StatelessWidget {
  const ConsistencyNote({required this.lines, super.key});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return NmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'CONSISTENCIA',
            style: NmTextStyles.from(NmType.overline, color: nm.textMuted),
          ),
          const SizedBox(height: NmSpace.s3),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: NmSpace.s2),
              child: Text(
                line,
                style: NmTextStyles.from(NmType.bodySm, color: nm.text),
              ),
            ),
        ],
      ),
    );
  }
}

/// Objetivo de actividad. **Nunca** muestra estados de fracaso (RN-14).
class ActivityGoalCard extends StatelessWidget {
  const ActivityGoalCard({
    required this.progress,
    this.onEdit,
    this.onToggle,
    super.key,
  });

  final ActivityGoalProgress progress;
  final VoidCallback? onEdit;
  final ValueChanged<bool>? onToggle;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final goal = progress.goal;
    final pct = activityGoalProgressPct(
      currentValue: progress.currentValue,
      targetValue: goal.targetValue,
    );
    final unitLabel = switch (goal.goalType) {
      ActivityGoalType.activeMinutes => 'min',
      ActivityGoalType.steps => 'pasos',
      ActivityGoalType.distance => 'm',
      _ => '',
    };

    return NmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                NmIcons.activityGoal(goal.goalType),
                size: NmIconSize.md,
                color: nm.textMuted,
              ),
              const SizedBox(width: NmSpace.s2),
              Expanded(
                child: Text(
                  '${goal.goalType.label} ${goal.period.label}',
                  style: NmTextStyles.from(NmType.h4, color: nm.text),
                ),
              ),
              if (onToggle != null)
                Switch(value: goal.enabled, onChanged: onToggle),
            ],
          ),
          const SizedBox(height: NmSpace.s3),
          Text(
            '${Fmt.integer(progress.currentValue)} / '
            '${Fmt.integer(goal.targetValue)} $unitLabel',
            style: NmTextStyles.from(NmType.body, color: nm.text).tnum,
          ),
          const SizedBox(height: NmSpace.s2),
          ClipRRect(
            borderRadius: BorderRadius.circular(NmRadius.full),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: goal.enabled ? pct / 100 : 0),
              duration: context.motion.move(NmMotion.chart),
              curve: NmMotion.ease,
              builder: (context, value, _) => Stack(
                children: <Widget>[
                  Container(height: 6, color: nm.divider),
                  FractionallySizedBox(
                    widthFactor: value,
                    child: Container(height: 6, color: nm.accent),
                  ),
                ],
              ),
            ),
          ),
          if (onEdit != null) ...<Widget>[
            const SizedBox(height: NmSpace.s2),
            Align(
              alignment: Alignment.centerLeft,
              child: NmButton.ghost(label: 'Editar', onPressed: onEdit),
            ),
          ],
        ],
      ),
    );
  }
}

/// Plantilla de ejercicio: muestra las kcal que estimaría con el peso actual.
class ExerciseTemplateCard extends StatelessWidget {
  const ExerciseTemplateCard({
    required this.template,
    required this.typeName,
    required this.estimatedCalories,
    this.onUse,
    this.onDelete,
    super.key,
  });

  final ExerciseTemplate template;
  final String typeName;
  final int? estimatedCalories;
  final VoidCallback? onUse;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return NmCard(
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  template.name,
                  style: NmTextStyles.from(NmType.h4, color: nm.text),
                ),
                const SizedBox(height: NmSpace.s1),
                Text(
                  '$typeName · ${Fmt.duration(template.defaultDurationMinutes)}'
                  ' · ${template.defaultIntensity.label}',
                  style: NmTextStyles.from(
                    NmType.caption,
                    color: nm.textMuted,
                  ).tnum,
                ),
                if (estimatedCalories != null)
                  Text(
                    Fmt.estimatedKcal(estimatedCalories!),
                    style: NmTextStyles.from(
                      NmType.caption,
                      color: nm.textMuted,
                    ).tnum,
                  ),
              ],
            ),
          ),
          if (onUse != null) NmButton.ghost(label: 'Usar', onPressed: onUse),
          if (onDelete != null)
            NmIconButton(
              icon: PhosphorIcons.trash(),
              onPressed: onDelete,
              tooltip: 'Eliminar plantilla',
              size: NmIconSize.md,
            ),
        ],
      ),
    );
  }
}
