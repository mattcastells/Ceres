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
import '../../../domain/enums/enums.dart';
import '../../components/activity/activity_cards.dart';
import '../../components/charts/macro_bar.dart';
import '../../components/feedback/day_context_card.dart';
import '../../components/feedback/feedback.dart';
import '../../components/food/daily_summary_card.dart';
import '../../components/food/food_widgets.dart';
import '../../components/sleep/sleep_card.dart';
import '../../components/system/buttons.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../components/water/alcohol_card.dart';
import '../../components/water/water_card.dart';
import '../../providers/app_providers.dart';
import '../profile/calorie_target_sheet.dart';
import '../weight/weight_sheet.dart';
import 'add_sheet.dart';
import 'add_to_slot_sheet.dart';
import 'alcohol_sheet.dart';
import 'daily_breakdown_sheet.dart';
import 'date_picker_sheet.dart';
import 'sick_day_sheet.dart';

/// S-06 · Inicio. ★ La pantalla principal.
///
/// Responde en dos segundos "¿cómo voy hoy?" mostrando el cálculo completo:
/// objetivo base, consumido, actividad, ajuste aplicado, objetivo ajustado y
/// restantes, siempre por separado (RN-01).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // Duración mínima visible del estado de carga: 400 ms (21-motion §4.1).
    Future<void>.delayed(NmMotion.loadingMinVisible, () {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final date = ref.watch(selectedDateProvider);
    final summary = ref.watch(dailySummaryProvider(date));
    final profile = ref.watch(profileProvider);
    final units = ref.watch(unitSystemProvider);
    final repo = ref.read(repositoryProvider);
    final isFutureDate = isFuture(date);
    final restoreMessage = ref.watch(restoreOutcomeProvider).message;

    return Scaffold(
      backgroundColor: nm.bg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _Header(date: date),
            Expanded(
              child: RefreshIndicator(
                color: nm.accent,
                backgroundColor: nm.surface,
                onRefresh: () async {
                  await repo.flushQueue();
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    context.screenPadding,
                    NmSpace.s3,
                    context.screenPadding,
                    NmSpace.s12 * 2,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: NmLayout.contentMaxWidth,
                      ),
                      child: LoadingSwitcher(
                        loading: _loading,
                        skeleton: const _HomeSkeleton(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            // Un día futuro es un plan, no un registro. Sin
                            // decirlo, el anillo de un día planificado se lee
                            // igual que el de uno ya comido.
                            if (isFutureDate) ...<Widget>[
                              const InfoNote(
                                text: 'Estás planificando un día que todavía '
                                    'no llegó.',
                              ),
                              const SizedBox(height: NmSpace.s5),
                            ],
                            // No pudimos leer lo guardado. Mostrar la app
                            // vacía y callarse es lo que hace que alguien
                            // registre encima y recién ahí se dé cuenta.
                            if (restoreMessage != null) ...<Widget>[
                              InfoNote(
                                tone: NmNoteTone.caution,
                                text: restoreMessage,
                                action: 'Traer mi respaldo',
                                onAction: () =>
                                    context.push(Routes.cloudBackup),
                              ),
                              const SizedBox(height: NmSpace.s5),
                            ],
                            // Sin datos corporales el objetivo es un número de
                            // referencia, no un cálculo (RN-03).
                            if (profile.birthDate == null ||
                                profile.heightCm == null) ...<Widget>[
                              InfoNote(
                                text:
                                    'Este objetivo es genérico. Cargá tus '
                                    'datos y se calcula con ellos.',
                                action: 'Cargar',
                                onAction: () =>
                                    context.push(Routes.profileBody),
                              ),
                              const SizedBox(height: NmSpace.s5),
                            ],
                            DailySummaryCard(
                              summary: summary,
                              onBreakdown: () =>
                                  showDailyBreakdownSheet(context, summary),
                              onEditTarget: () =>
                                  showCalorieTargetSheet(context),
                            ),
                            const SizedBox(height: NmSpace.s6),
                            NmCard(child: MacroBar(macros: summary.macros)),
                            const SizedBox(height: NmSpace.s6),
                            WaterCard(date: date),
                            const SizedBox(height: NmSpace.s4),
                            // Debajo del agua: es la otra mitad de "qué
                            // tomaste", y juntas se leen de una.
                            AlcoholCard(
                              date: date,
                              onTap: () =>
                                  showAlcoholSheet(context, date: date),
                            ),
                            const SizedBox(height: NmSpace.s4),
                            SleepCard(date: date),
                            const SizedBox(height: NmSpace.s8),

                            if (summary.isEmpty && !isFutureDate) ...<Widget>[
                              EmptyState(
                                icon: PhosphorIcons.forkKnife(),
                                title: 'Todavía no registraste nada',
                                body: 'Empezá por lo que tengas más a mano: '
                                    'una comida o una actividad.',
                                primaryLabel: 'Registrá tu primera comida',
                                onPrimary: () => showAddSheet(context),
                                secondaryLabel: 'Registrá una actividad',
                                onSecondary: () => showAddSheet(
                                  context,
                                  activityFirst: true,
                                ),
                              ),
                              const SizedBox(height: NmSpace.s8),
                            ],

                            // Comidas: 4 secciones por slot, sin encabezado
                            // propio — cada slot ya se nombra solo.
                            for (final slot in MealSlot.values)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: NmSpace.s4,
                                ),
                                child: MealSection(
                                  slot: slot,
                                  meals: summary.mealsFor(slot),
                                  // Los días futuros dentro de la ventana se
                                  // pueden cargar: es la planificación.
                                  onAdd: () => showAddToSlotSheet(
                                    context,
                                    slot: slot,
                                    date: date,
                                  ),
                                  onOpenMeal: (meal) =>
                                      context.push(Routes.meal(meal.id)),
                                  onDeleteMeal: (meal) async {
                                    await repo.deleteMeal(meal.id);
                                    if (!context.mounted) return;
                                    NmSnackbar.show(
                                      context,
                                      'Comida eliminada',
                                      actionLabel: 'Deshacer',
                                      undo: true,
                                      onAction: () =>
                                          repo.restoreMeal(meal.id),
                                    );
                                  },
                                  onDuplicateMeal: (meal) async {
                                    await repo.duplicateMeal(
                                      meal.id,
                                      date,
                                      meal.slot,
                                    );
                                    if (!context.mounted) return;
                                    NmSnackbar.show(context, 'Comida duplicada');
                                  },
                                ),
                              ),

                            const SizedBox(height: NmSpace.s6),

                            // Actividad.
                            //
                            // El "Marcar descanso" que vivía en este
                            // encabezado se fue a "Cómo estuvo el día", abajo,
                            // junto al día de enfermedad. Son la misma clase de
                            // cosa —una marca sobre el día, que no suma ni
                            // resta nada— y tenerlas en dos lugares distintos
                            // de la misma pantalla obligaba a acordarse de cuál
                            // estaba dónde. Acá quedó de cuando el descanso era
                            // un asunto solo de actividad.
                            const NmSectionHeader(title: 'Actividad'),
                            NmCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  ActivitySummaryCard(
                                    totals: summary.activityTotals,
                                    estimatedCalories:
                                        summary.exerciseEstimatedKcal,
                                    appliedCalories:
                                        summary.exerciseAppliedKcal,
                                    creditPercentage:
                                        profile.effectiveCreditPercentage,
                                    isRestDay: summary.isRestDay,
                                    onRestDay: () =>
                                        repo.setRestDay(date, false),
                                    onAdd: () => showAddSheet(
                                      context,
                                      activityFirst: true,
                                    ),
                                  ),
                                  if (summary.activities.isNotEmpty) ...<Widget>[
                                    const SizedBox(height: NmSpace.s3),
                                    const NmDivider(),
                                  ],
                                  for (var i = 0;
                                      i < summary.activities.length;
                                      i++)
                                    StaggeredItem(
                                      index: i,
                                      child: ActivityListItem(
                                        activity: summary.activities[i],
                                        onTap: () => context.push(
                                          Routes.activity(
                                            summary.activities[i].id,
                                          ),
                                        ),
                                        onEdit: () => context.push(
                                          Routes.activityEdit(
                                            summary.activities[i].id,
                                          ),
                                        ),
                                        onDuplicate: () async {
                                          await repo.duplicateActivity(
                                            summary.activities[i].id,
                                            date,
                                          );
                                          if (!context.mounted) return;
                                          NmSnackbar.show(
                                            context,
                                            'Actividad duplicada',
                                          );
                                        },
                                        onToggleFavorite: () =>
                                            repo.toggleFavorite(
                                              summary.activities[i].id,
                                            ),
                                        onDelete: () async {
                                          final id = summary.activities[i].id;
                                          await repo.deleteActivity(id);
                                          if (!context.mounted) return;
                                          NmSnackbar.show(
                                            context,
                                            'Actividad eliminada',
                                            actionLabel: 'Deshacer',
                                            undo: true,
                                            onAction: () =>
                                                repo.restoreActivity(id),
                                          );
                                        },
                                      ),
                                    ),
                                  // El botón de sumar vive acá abajo **siempre**
                                  // que el día no sea de descanso, no solo
                                  // cuando la lista está vacía.
                                  //
                                  // Estaba condicionado a `activities.isEmpty`,
                                  // y el resumen de arriba también esconde su
                                  // "Agregar" apenas hay una sesión: o sea que
                                  // después de cargar el primer ejercicio la
                                  // tarjeta se quedaba sin ninguna forma de
                                  // sumar otro, y había que salir al "+" de la
                                  // barra y volver a entrar por el mismo camino
                                  // que se acababa de recorrer. Cargar dos
                                  // actividades en un día no es el caso raro:
                                  // una caminata y una entrada de gimnasio ya
                                  // son dos.
                                  if (!summary.isRestDay) ...<Widget>[
                                    const SizedBox(height: NmSpace.s2),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: NmButton.ghost(
                                        // "Otra" cuando ya hay una: el botón
                                        // dice qué va a pasar, y de paso deja
                                        // claro que no reemplaza a la que está.
                                        label: summary.activities.isEmpty
                                            ? 'Agregar actividad'
                                            : 'Agregar otra actividad',
                                        icon: PhosphorIcons.plus(),
                                        onPressed: () => showAddSheet(
                                          context,
                                          activityFirst: true,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            const SizedBox(height: NmSpace.s8),

                            // Peso.
                            const NmSectionHeader(title: 'Peso'),
                            NmCard(
                              child: WeightRow(
                                weightKg: summary.weight?.weightKg,
                                deltaKg: summary.weight?.deltaKg,
                                units: units,
                                onLog: () =>
                                    showWeightSheet(context, date: date),
                              ),
                            ),

                            if (profile.showNetCalories) ...<Widget>[
                              const SizedBox(height: NmSpace.s6),
                              NmCard(
                                child: ValueRow(
                                  label: 'Calorías netas',
                                  caption: 'consumidas − aplicadas',
                                  value: Fmt.kcal(summary.netKcal),
                                  muted: true,
                                ),
                              ),
                            ],

                            // Abajo de todo: no es un registro del día, es lo
                            // que lo explica. Arriba competiría por atención
                            // con los números que sí son del día.
                            const SizedBox(height: NmSpace.s8),
                            const NmSectionHeader(title: 'Cómo estuvo el día'),
                            DayContextCard(
                              date: date,
                              onTapSick: () =>
                                  showSickDaySheet(context, date: date),
                              onTapRest: () => showRestDaySheet(context, date),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cabecera: selector de día y avatar.
class _Header extends ConsumerWidget {
  const _Header({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nm = context.nm;
    final controller = ref.read(selectedDateProvider.notifier);
    // Se puede mirar hasta tres días adelante para dejar comidas planificadas.
    final canGoForward = date.difference(today()).inDays < maxPlanningDays;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        context.screenPadding,
        NmSpace.s3,
        context.screenPadding,
        NmSpace.s2,
      ),
      child: Row(
        children: <Widget>[
          NmIconButton(
            icon: PhosphorIcons.caretLeft(),
            onPressed: () => controller.shift(-1),
            tooltip: 'Día anterior',
            size: NmIconSize.md,
          ),
          Expanded(
            child: InkWell(
              onTap: () => showDatePickerSheet(context),
              borderRadius: NmRadius.brMd,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: NmSpace.s2),
                child: Column(
                  children: <Widget>[
                    Text(
                      friendlyDay(date),
                      textAlign: TextAlign.center,
                      style: NmTextStyles.from(NmType.h3, color: nm.text),
                    ),
                    Text(
                      longDay(date),
                      textAlign: TextAlign.center,
                      style: NmTextStyles.from(
                        NmType.caption,
                        color: nm.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          NmIconButton(
            icon: PhosphorIcons.caretRight(),
            onPressed: canGoForward ? () => controller.shift(1) : null,
            tooltip: 'Día siguiente',
            size: NmIconSize.md,
          ),
        ],
      ),
    );
  }
}

/// Skeleton de Inicio: tarjeta + 2 filas fantasma (21-motion §4.2).
class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      DailySummarySkeleton(),
      SizedBox(height: NmSpace.s6),
      SkeletonList(rows: 2),
    ],
  );
}

/// `sheet.rest_day` — marcar o quitar el descanso planificado (RN-15).
Future<void> showRestDaySheet(BuildContext context, DateTime date) =>
    showNmSheet<void>(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final repo = ref.watch(repositoryProvider);
          final isRest = repo.isRestDay(date);
          return NmSheet(
            title: 'Día de descanso',
            subtitle: friendlyDay(date),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const InfoNote(
                  text: 'Un día de descanso planificado no cuenta como día sin '
                      'actividad y no cambia tu objetivo calórico.',
                ),
                const SizedBox(height: NmSpace.s6),
                NmButton(
                  label: isRest
                      ? 'Quitar el descanso planificado'
                      : 'Marcar como descanso planificado',
                  block: true,
                  onPressed: () async {
                    await repo.setRestDay(date, !isRest);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
