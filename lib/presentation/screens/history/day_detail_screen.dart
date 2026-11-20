import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/formats.dart';
import '../../../core/utils/phosphor_icons.dart';
import '../../../domain/enums/enums.dart';
import '../../components/activity/activity_cards.dart';
import '../../components/charts/macro_bar.dart';
import '../../components/feedback/day_context.dart';
import '../../components/food/daily_summary_card.dart';
import '../../components/food/food_widgets.dart';
import '../../components/sleep/sleep_card.dart';
import '../../components/system/buttons.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../components/water/water_card.dart';
import '../../providers/app_providers.dart';
import '../home/add_to_slot_sheet.dart';
import '../home/alcohol_sheet.dart';
import '../home/daily_breakdown_sheet.dart';
import '../home/sick_day_sheet.dart';
import '../profile/calorie_target_sheet.dart';
import '../weight/weight_sheet.dart';

/// S-22 · Detalle del día. La misma tarjeta que Inicio, editable (D-20).
class DayDetailScreen extends ConsumerWidget {
  const DayDetailScreen({required this.date, super.key});

  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(dailySummaryProvider(date));
    final repo = ref.watch(repositoryProvider);
    final units = ref.watch(unitSystemProvider);
    final profile = ref.watch(profileProvider);

    return NmScreen(
      title: longDay(date),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          DailySummaryCard(
            summary: summary,
            onBreakdown: () => showDailyBreakdownSheet(context, summary),
            onEditTarget: () => showCalorieTargetSheet(context),
          ),
          const SizedBox(height: NmSpace.s6),
          NmCard(child: MacroBar(macros: summary.macros)),
          const SizedBox(height: NmSpace.s6),
          WaterCard(date: date),
          const SizedBox(height: NmSpace.s4),
          SleepCard(date: date),

          // Solo aparece el día que hay algo que contar. Ver `DayContextStrip`.
          if (summary.isSickDay || summary.alcohol != null) ...<Widget>[
            const SizedBox(height: NmSpace.s4),
            NmCard(
              child: DayContextStrip(
                sick: summary.sickMarker,
                alcohol: summary.alcohol,
                onTapSick: () => showSickDaySheet(context, date: date),
                onTapAlcohol: () => showAlcoholSheet(context, date: date),
              ),
            ),
          ],
          const SizedBox(height: NmSpace.s8),

          // Igual que en Inicio: una tarjeta con los cuatro momentos.
          const NmSectionHeader(title: 'Comidas'),
          MealsCard(
            sections: <Widget>[
              for (final slot in MealSlot.values)
                MealSection(
                  slot: slot,
                  meals: summary.mealsFor(slot),
                  onAdd: () =>
                      showAddToSlotSheet(context, slot: slot, date: date),
                  onOpenMeal: (meal) => context.push(Routes.meal(meal.id)),
                  onDeleteMeal: (meal) async {
                    await repo.deleteMeal(meal.id);
                    if (!context.mounted) return;
                    NmSnackbar.show(
                      context,
                      'Comida eliminada',
                      actionLabel: 'Deshacer',
                      undo: true,
                      onAction: () => repo.restoreMeal(meal.id),
                    );
                  },
                  onDuplicateMeal: (meal) async {
                    await repo.duplicateMeal(meal.id, date, meal.slot);
                    if (!context.mounted) return;
                    NmSnackbar.show(context, 'Comida duplicada');
                  },
                ),
            ],
          ),

          const SizedBox(height: NmSpace.s8),
          // Igual que en Inicio: el resumen, la lista y **siempre** el botón de
          // sumar otra. Acá el botón solo aparecía con el día vacío, así que
          // después de cargar una actividad no quedaba cómo cargar la segunda,
          // y las filas no tenían "Duplicar" ni "Favorita" como en Inicio.
          const NmSectionHeader(title: 'Actividad'),
          NmCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ActivitySummaryCard(
                  totals: summary.activityTotals,
                  estimatedCalories: summary.exerciseEstimatedKcal,
                  appliedCalories: summary.exerciseAppliedKcal,
                  creditPercentage: summary.effectiveCreditPercentage,
                  isRestDay: summary.isRestDay,
                ),
                if (summary.activities.isNotEmpty) ...<Widget>[
                  const SizedBox(height: NmSpace.s3),
                  const NmDivider(),
                ],
                for (final activity in summary.activities)
                  ActivityListItem(
                    activity: activity,
                    onTap: () => context.push(Routes.activity(activity.id)),
                    onEdit: () =>
                        context.push(Routes.activityEdit(activity.id)),
                    onDuplicate: () async {
                      await repo.duplicateActivity(activity.id, date);
                      if (!context.mounted) return;
                      NmSnackbar.show(context, 'Actividad duplicada');
                    },
                    onToggleFavorite: () => repo.toggleFavorite(activity.id),
                    onDelete: () async {
                      await repo.deleteActivity(activity.id);
                      if (!context.mounted) return;
                      NmSnackbar.show(
                        context,
                        'Actividad eliminada',
                        actionLabel: 'Deshacer',
                        undo: true,
                        onAction: () => repo.restoreActivity(activity.id),
                      );
                    },
                  ),
                if (!summary.isRestDay) ...<Widget>[
                  if (summary.activities.isNotEmpty)
                    const SizedBox(height: NmSpace.s2),
                  NmButton.ghost(
                    label: summary.activities.isEmpty
                        ? 'Agregar actividad'
                        : 'Agregar otra actividad',
                    icon: PhosphorIcons.plus(),
                    onPressed: () => context.push(
                      '${Routes.activityNew}?date=${isoDate(date)}',
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: NmSpace.s8),
          const NmSectionHeader(title: 'Peso'),
          NmCard(
            child: WeightRow(
              weightKg: summary.weight?.weightKg,
              deltaKg: summary.weight?.deltaKg,
              units: units,
              onLog: () => showWeightSheet(context, date: date),
            ),
          ),

          // "Cierre del día" repetía objetivo base, ajuste y balance, que ya
          // están en la tarjeta de arriba. Queda lo único que no estaba: las
          // netas, con la misma preferencia que en Inicio.
          if (profile.showNetCalories) ...<Widget>[
            const SizedBox(height: NmSpace.s6),
            NmCard(
              child: ValueRow(
                label: 'Calorías netas',
                caption: 'consumido − ejercicio',
                value: Fmt.kcal(summary.netKcal),
                muted: true,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
