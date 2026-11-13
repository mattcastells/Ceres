import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/formats.dart';
import '../../../domain/models/summaries.dart';
import '../../components/system/buttons.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';

/// S-07 · Desglose diario. Hace auditable el número principal.
///
/// Las fórmulas se exponen como texto plano legible, no como imagen.
Future<void> showDailyBreakdownSheet(
  BuildContext context,
  DailySummary summary,
) => showNmSheet<void>(
  context: context,
  expand: true,
  builder: (context) => _DailyBreakdownSheet(summary: summary),
);

class _DailyBreakdownSheet extends ConsumerWidget {
  const _DailyBreakdownSheet({required this.summary});

  final DailySummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nm = context.nm;
    final balance = summary.balance;
    final profile = ref.watch(profileProvider);

    return NmSheet(
      title: '¿Cómo se calcula?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          FormulaRow(
            expression: 'Objetivo = objetivo base + ejercicio',
            values:
                '${Fmt.integer(summary.adjustedTarget)} = '
                '${Fmt.integer(summary.baseTarget)} + '
                '${Fmt.integer(summary.exerciseAppliedKcal)}',
          ),
          const SizedBox(height: NmSpace.s3),
          FormulaRow(
            expression: 'Te quedan = objetivo − consumido',
            values:
                '${Fmt.integer(summary.remainingKcal)} = '
                '${Fmt.integer(summary.adjustedTarget)} − '
                '${Fmt.integer(summary.consumedKcal)}',
          ),
          const SizedBox(height: NmSpace.s3),
          FormulaRow(
            expression: 'Ejercicio = actividad estimada × '
                '${Fmt.decimal2(summary.creditPercentage / 100)}',
            values:
                '${Fmt.integer(summary.exerciseAppliedKcal)} = '
                '${Fmt.integer(summary.exerciseEstimatedKcal)} × '
                '${Fmt.decimal2(summary.creditPercentage / 100)}',
          ),
          const SizedBox(height: NmSpace.s6),
          NmCard(
            child: Column(
              children: <Widget>[
                ValueRow(
                  label: 'Objetivo base',
                  value: Fmt.kcal(summary.baseTarget),
                ),
                ValueRow(
                  label: 'Consumido',
                  value: '−${Fmt.kcal(summary.consumedKcal)}',
                ),
                ValueRow(
                  label: 'Actividad estimada',
                  value: Fmt.estimatedKcal(summary.exerciseEstimatedKcal),
                ),
                ValueRow(
                  label: 'Ajuste aplicado',
                  caption: '${summary.creditPercentage} %',
                  value: '+${Fmt.kcal(summary.exerciseAppliedKcal)}',
                ),
                const NmDivider(),
                ValueRow(
                  label: balance.isOverBudget ? 'Te pasaste por' : 'Te quedan',
                  value: Fmt.kcal(summary.remainingKcal.abs()),
                  emphasis: true,
                  valueColor: balance.isOverBudget ? nm.overBudget : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: NmSpace.s6),
          if (profile.showNetCalories)
            ValueRow(
              label: 'Calorías netas',
              caption: 'consumido − ejercicio',
              value: Fmt.kcal(summary.netKcal),
              muted: true,
            )
          else
            InfoNote(
              text: 'Calorías netas (consumido − ejercicio): '
                  '${Fmt.kcal(summary.netKcal)}.',
            ),
          const SizedBox(height: NmSpace.s4),
          const InfoNote(
            tone: NmNoteTone.caution,
            text: 'Las calorías de ejercicio son una estimación: los valores '
                'MET son promedios poblacionales y no consideran composición '
                'corporal ni eficiencia mecánica.',
          ),
          const SizedBox(height: NmSpace.s6),
          NmButton.secondary(
            label: 'Cambiar cuánto suma el ejercicio',
            block: true,
            onPressed: () {
              Navigator.of(context).pop();
              context.push(Routes.exerciseCredit);
            },
          ),
        ],
      ),
    );
  }
}
