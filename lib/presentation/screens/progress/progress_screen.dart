import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/formats.dart';
import '../../../core/utils/phosphor_icons.dart';
import '../../../domain/services/summary_builder.dart';
import '../../components/activity/activity_cards.dart';
import '../../components/charts/charts.dart';
import '../../components/feedback/feedback.dart';
import '../../components/system/buttons.dart';
import '../../components/system/inputs.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_providers.dart';
import '../weight/weight_sheet.dart';

/// S-23 · Progreso. Muestra tendencia sin juicio de valor.
class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(progressRangeProvider);
    final progress = ref.watch(progressProvider);
    final units = ref.watch(unitSystemProvider);
    final cloud = ref.watch(isCloudEnabledProvider);

    return NmScreen(
      title: 'Progreso',
      actions: <Widget>[
        IconButton(
          tooltip: 'Registrar peso',
          onPressed: () => showWeightSheet(context),
          icon: Icon(PhosphorIcons.scales()),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s2),
          NmSegmentedControl<ProgressRange>(
            options: <(ProgressRange, String)>[
              for (final option in ProgressRange.values) (option, option.label),
            ],
            value: range,
            onChanged: (option) =>
                ref.read(progressRangeProvider.notifier).set(option),
          ),
          const SizedBox(height: NmSpace.s6),

          // El reporte con IA del período elegido. Arriba de los gráficos
          // porque es la lectura de todo lo de abajo; y solo con servidor, que
          // es quien lo arma, y con su flag.
          if (cloud && FeatureFlags.aiProgressReport) ...<Widget>[
            NmButton(
              label: 'Generar reporte',
              icon: PhosphorIcons.sparkle(),
              block: true,
              onPressed: () => context.push(Routes.weeklyReport),
            ),
            const SizedBox(height: NmSpace.s8),
          ],

          // Peso.
          NmSectionHeader(
            title: 'Peso',
            action: 'Ampliar',
            onAction: () => context.push(Routes.progressWeight),
          ),
          NmCard(
            child: progress.hasEnoughWeightData
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      WeightChart(
                        points: progress.weightPoints,
                        movingAverage: progress.weightMovingAverage,
                      ),
                      const SizedBox(height: NmSpace.s3),
                      _ChartFooter(
                        left:
                            'Variación: '
                            '${Fmt.signedWeight(progress.weightDeltaKg, units)}',
                        right: progress.trendKgPerWeek == null
                            ? null
                            : 'Tendencia: '
                                  '${Fmt.signedWeight(progress.trendKgPerWeek!, units)}'
                                  '/semana',
                      ),
                    ],
                  )
                : EmptyState(
                    compact: true,
                    icon: PhosphorIcons.scales(),
                    title: 'Necesitamos unos días más',
                    body:
                        'Con al menos tres registros de peso podemos mostrar '
                        'una tendencia.',
                    primaryLabel: 'Registrar peso',
                    onPrimary: () => showWeightSheet(context),
                  ),
          ),

          const SizedBox(height: NmSpace.s8),

          // Calorías: misma forma que el peso, el gráfico y una línea con los
          // dos números que importan.
          NmSectionHeader(
            title: 'Calorías',
            action: 'Ampliar',
            onAction: () => context.push(Routes.progressCalories),
          ),
          NmCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                CaloriesChart(days: progress.calorieDays),
                const SizedBox(height: NmSpace.s3),
                _ChartFooter(
                  left: 'Promedio: ${Fmt.kcal(progress.averageConsumed)}',
                  right: progress.adherencePct == null
                      ? null
                      : 'Adherencia: ${Fmt.percent(progress.adherencePct!)}',
                ),
              ],
            ),
          ),

          const SizedBox(height: NmSpace.s8),

          // Actividad.
          NmSectionHeader(
            title: 'Actividad',
            action: 'Ampliar',
            onAction: () => context.push(Routes.progressActivity),
          ),
          NmCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ActivityHistoryChart(points: progress.activityByDay),
                if (progress.activityTotals.sessions > 0) ...<Widget>[
                  const SizedBox(height: NmSpace.s3),
                  _ChartFooter(
                    left:
                        'Total: '
                        '${Fmt.duration(progress.activityTotals.minutes)}',
                    right: Fmt.estimatedKcal(
                      progress.activityTotals.estimatedCalories,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: NmSpace.s8),
          const NmSectionHeader(title: 'Reporte'),
          ConsistencyNote(lines: SummaryBuilder.consistencyNotes(progress)),

          const SizedBox(height: NmSpace.s8),
          NmCard(
            child: Column(
              children: <Widget>[
                NmListRow(
                  title: 'Historial',
                  subtitle: 'Todos tus días',
                  leading: Icon(PhosphorIcons.clockCounterClockwise()),
                  onTap: () => context.push(Routes.progressHistory),
                ),
                const NmDivider(),
                NmListRow(
                  title: 'Medidas corporales',
                  subtitle: 'Perímetros, pliegues y balanza',
                  leading: Icon(PhosphorIcons.ruler()),
                  onTap: () => context.push(Routes.progressMeasurements),
                ),
                const NmDivider(),
                NmListRow(
                  title: 'Objetivos de actividad',
                  subtitle: 'Opcionales',
                  leading: Icon(PhosphorIcons.target()),
                  onTap: () => context.push(Routes.progressGoals),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// La línea de abajo de cada gráfico: un dato a la izquierda y otro, más
/// tenue, a la derecha. La misma en peso, calorías y actividad.
class _ChartFooter extends StatelessWidget {
  const _ChartFooter({required this.left, this.right});

  final String left;
  final String? right;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            left,
            style: NmTextStyles.from(NmType.bodySm, color: nm.text).tnum,
          ),
        ),
        if (right != null)
          Text(
            right!,
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted).tnum,
          ),
      ],
    );
  }
}
