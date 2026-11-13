import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/formats.dart';
import '../../../domain/services/summary_builder.dart';
import '../../components/activity/activity_cards.dart';
import '../../components/charts/charts.dart';
import '../../components/feedback/feedback.dart';
import '../../components/plan/ad_banner.dart';
import '../../components/plan/ai_gate.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/plan_providers.dart';
import '../weight/weight_sheet.dart';

/// S-23 · Progreso. Muestra tendencia sin juicio de valor.
class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nm = context.nm;
    final range = ref.watch(progressRangeProvider);
    final progress = ref.watch(progressProvider);
    final units = ref.watch(unitSystemProvider);
    final cloud = ref.watch(isCloudEnabledProvider);
    final plan = ref.watch(planProvider);

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
          Wrap(
            spacing: NmSpace.s2,
            children: <Widget>[
              for (final option in ProgressRange.values)
                NmChip(
                  label: option.label,
                  selected: option == range,
                  semanticsInRadioGroup: true,
                  onTap: () =>
                      ref.read(progressRangeProvider.notifier).state = option,
                ),
            ],
          ),
          const SizedBox(height: NmSpace.s8),

          // El resumen semanal con IA. Arriba de los gráficos porque es la
          // lectura de todo lo de abajo; y solo con servidor, que es quien lo
          // arma.
          if (cloud) ...<Widget>[
            NmCard(
              padding: const EdgeInsets.symmetric(vertical: NmSpace.s2),
              child: NmListRow(
                title: 'Tu semana con IA',
                subtitle: 'Lo que salió bien, lo que se repite y algo para '
                    'probar',
                leading: Icon(PhosphorIcons.sparkle()),
                trailing: plan.includesAi
                    ? null
                    : const NmTag(
                        label: 'Premium',
                        variant: NmTagVariant.outline,
                      ),
                onTap: () {
                  if (!ensureAiAllowed(context, ref)) return;
                  context.push(Routes.weeklyReport);
                },
              ),
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
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              'Variación: '
                              '${Fmt.signedWeight(progress.weightDeltaKg, units)}',
                              style: NmTextStyles.from(
                                NmType.bodySm,
                                color: nm.text,
                              ).tnum,
                            ),
                          ),
                          if (progress.trendKgPerWeek != null)
                            Text(
                              'Tendencia: '
                              '${Fmt.signedWeight(progress.trendKgPerWeek!, units)}'
                              '/semana',
                              style: NmTextStyles.from(
                                NmType.caption,
                                color: nm.textMuted,
                              ).tnum,
                            ),
                        ],
                      ),
                    ],
                  )
                : EmptyState(
                    compact: true,
                    icon: PhosphorIcons.scales(),
                    title: 'Necesitamos unos días más',
                    body: 'Con al menos tres registros de peso podemos mostrar '
                        'una tendencia.',
                    primaryLabel: 'Registrar peso',
                    onPrimary: () => showWeightSheet(context),
                  ),
          ),

          const SizedBox(height: NmSpace.s8),

          // Calorías.
          NmSectionHeader(
            title: 'Calorías',
            action: 'Ampliar',
            onAction: () => context.push(Routes.progressCalories),
          ),
          NmCard(child: CaloriesChart(days: progress.calorieDays)),

          const SizedBox(height: NmSpace.s6),
          StatCardRow(
            children: <Widget>[
              StatCard(
                label: 'Promedio diario',
                value: Fmt.kcal(progress.averageConsumed),
                icon: PhosphorIcons.forkKnife(),
              ),
              StatCard(
                label: 'Adherencia',
                value: progress.adherencePct == null
                    ? '—'
                    : Fmt.percent(progress.adherencePct!),
                caption: progress.adherencePct == null
                    ? 'Con tres días de registro la mostramos'
                    : 'Días dentro de ±10 % del objetivo',
                icon: PhosphorIcons.target(),
              ),
            ],
          ),

          const SizedBox(height: NmSpace.s8),

          // Actividad.
          NmSectionHeader(
            title: 'Actividad',
            action: 'Ampliar',
            onAction: () => context.push(Routes.progressActivity),
          ),
          NmCard(child: ActivityHistoryChart(points: progress.activityByDay)),
          const SizedBox(height: NmSpace.s4),
          ConsistencyNote(lines: SummaryBuilder.consistencyNotes(progress)),

          const SizedBox(height: NmSpace.s8),
          NmCard(
            child: Column(
              children: <Widget>[
                NmListRow(
                  title: 'Historial',
                  subtitle: 'Todos tus días, uno por uno',
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
          // Abajo de todo y lejos del peso: el anuncio no puede quedar al
          // lado de un número del cuerpo de nadie. Solo en el plan gratis.
          const AdBanner(padding: EdgeInsets.only(top: NmSpace.s6)),
        ],
      ),
    );
  }
}
