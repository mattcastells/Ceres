import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/formats.dart';
import '../../../domain/enums/enums.dart';
import '../../../domain/models/activity.dart';
import '../../../domain/models/summaries.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../domain/services/summary_builder.dart';
import '../../components/activity/activity_cards.dart';
import '../../components/charts/charts.dart';
import '../../components/feedback/feedback.dart';
import '../../components/system/buttons.dart';
import '../../components/system/inputs.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';
import '../weight/measurement_draft.dart';
import '../weight/weight_sheet.dart';

const _uuid = Uuid();

/// Gráfico de peso ampliado.
class WeightChartScreen extends ConsumerWidget {
  const WeightChartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nm = context.nm;
    final progress = ref.watch(progressProvider);
    final units = ref.watch(unitSystemProvider);
    final repo = ref.watch(repositoryProvider);
    final logs = repo.weightLogs;

    return NmScreen(
      title: 'Peso',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          NmCard(
            child: WeightChart(
              id: 'weight-full',
              height: 240,
              points: progress.weightPoints,
              movingAverage: progress.weightMovingAverage,
            ),
          ),
          const SizedBox(height: NmSpace.s6),
          StatCardRow(
            children: <Widget>[
              StatCard(
                label: 'Variación',
                value:
                    '${Fmt.signedDecimal1(progress.weightDeltaKg)} '
                    '${Fmt.weightUnit(units)}',
              ),
              StatCard(
                label: 'Tendencia semanal',
                value: progress.trendKgPerWeek == null
                    ? '—'
                    : '${Fmt.signedDecimal1(progress.trendKgPerWeek!)} kg',
                caption: progress.trendKgPerWeek == null
                    ? 'Necesitamos unos días más de registro'
                    : null,
              ),
            ],
          ),
          const SizedBox(height: NmSpace.s8),
          const NmSectionHeader(title: 'Registros'),
          NmCard(
            padding: const EdgeInsets.symmetric(vertical: NmSpace.s1),
            child: Column(
              children: <Widget>[
                for (final log in logs.take(20))
                  Dismissible(
                    key: ValueKey<String>(log.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(
                        horizontal: NmSpace.s6,
                      ),
                      decoration: BoxDecoration(
                        color: nm.danger.withValues(alpha: 0.14),
                        borderRadius: NmRadius.brMd,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            PhosphorIcons.trash(),
                            size: NmIconSize.md,
                            color: nm.danger,
                          ),
                          const SizedBox(width: NmSpace.s2),
                          Text(
                            'Eliminar',
                            style: NmTextStyles.from(
                              NmType.caption,
                              color: nm.danger,
                            ),
                          ),
                        ],
                      ),
                    ),
                    confirmDismiss: (_) async {
                      final id = log.id;
                      await repo.deleteWeight(id);
                      if (context.mounted) {
                        NmSnackbar.show(
                          context,
                          'Registro eliminado',
                          actionLabel: 'Deshacer',
                          undo: true,
                          onAction: () => repo.restoreWeight(id),
                        );
                      }
                      return false;
                    },
                    child: _WeightLogRow(
                      day: friendlyDay(log.localDate),
                      value: Fmt.weightValue(log.weightKg, units),
                      unit: Fmt.weightUnit(units),
                      onEdit: () =>
                          showWeightSheet(context, date: log.localDate),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: NmSpace.s6),
          NmButton(
            label: 'Registrar peso',
            block: true,
            onPressed: () => showWeightSheet(context),
          ),
        ],
      ),
    );
  }
}

/// Una fila del historial de peso, en columnas fijas.
///
/// `ValueRow` sirve para pares etiqueta/valor sueltos, pero acá hay veinte
/// filas seguidas y lo que se lee es una tabla: si el número y la unidad
/// comparten una sola caja alineada a la derecha, el ancho del número corre la
/// unidad y las comas quedan cada una en su lugar. Por eso van en tres
/// columnas: fecha, número (derecha), unidad (izquierda, ancho fijo), y el
/// lápiz en su propia ranura para que el borde derecho sea una línea recta.
class _WeightLogRow extends StatelessWidget {
  const _WeightLogRow({
    required this.day,
    required this.value,
    required this.unit,
    required this.onEdit,
  });

  final String day;
  final String value;
  final String unit;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;

    return Semantics(
      label: '$day: $value $unit',
      button: true,
      onTapHint: 'Editar',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onEdit,
          borderRadius: NmRadius.brSm,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: NmSpace.s4,
              vertical: NmSpace.s3,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    day,
                    overflow: TextOverflow.ellipsis,
                    style: NmTextStyles.from(NmType.bodySm, color: nm.text),
                  ),
                ),
                const SizedBox(width: NmSpace.s3),
                ConstrainedBox(
                  // Piso, no ancho fijo: alinea los números de siempre sin
                  // recortar uno más largo si alguna vez aparece.
                  constraints: const BoxConstraints(minWidth: 56),
                  child: Text(
                    value,
                    textAlign: TextAlign.right,
                    style: NmTextStyles.from(NmType.bodySm, color: nm.text).tnum,
                  ),
                ),
                const SizedBox(width: NmSpace.s2),
                SizedBox(
                  width: 22,
                  child: Text(
                    unit,
                    style: NmTextStyles.from(
                      NmType.bodySm,
                      color: nm.textMuted,
                    ),
                  ),
                ),
                const SizedBox(width: NmSpace.s3),
                Icon(
                  PhosphorIcons.pencilSimple(),
                  size: NmIconSize.sm,
                  color: nm.isDark ? nm.accentText : nm.accent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Gráfico de calorías ampliado.
class CaloriesChartScreen extends ConsumerWidget {
  const CaloriesChartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(progressProvider);

    return NmScreen(
      title: 'Calorías',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          NmCard(
            child: CaloriesChart(
              id: 'calories-full',
              height: 240,
              days: progress.calorieDays,
            ),
          ),
          const SizedBox(height: NmSpace.s6),
          StatCardRow(
            children: <Widget>[
              StatCard(
                label: 'Promedio diario',
                value: Fmt.kcal(progress.averageConsumed),
              ),
              StatCard(
                label: 'Adherencia',
                value: progress.adherencePct == null
                    ? '—'
                    : Fmt.percent(progress.adherencePct!),
              ),
            ],
          ),
          const SizedBox(height: NmSpace.s4),
          const InfoNote(
            text: 'Los días sin registro no cuentan ni a favor ni en contra.',
          ),
        ],
      ),
    );
  }
}

/// S-24 · Progreso de actividad.
class ActivityProgressScreen extends ConsumerWidget {
  const ActivityProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(progressProvider);
    final totals = progress.activityTotals;

    if (totals.sessions == 0) {
      return NmScreen(
        title: 'Actividad',
        child: EmptyState(
          icon: PhosphorIcons.personSimpleRun(),
          title: 'Todavía no registraste actividad en este período',
          body: 'Cuando registres una, vas a ver acá los minutos, las '
              'sesiones y la distribución por categoría.',
        ),
      );
    }

    return NmScreen(
      title: 'Actividad',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          NmCard(
            child: ActivityHistoryChart(
              id: 'activity-full',
              height: 220,
              points: progress.activityByDay,
            ),
          ),
          const SizedBox(height: NmSpace.s6),
          StatCardRow(
            children: <Widget>[
              StatCard(
                label: 'Minutos activos',
                value: Fmt.duration(totals.minutes),
                caption: progress.previousWeekDeltaMinutes == 0
                    ? 'Igual que la semana anterior'
                    : '${Fmt.signed(progress.previousWeekDeltaMinutes)} min '
                          'vs. la semana anterior',
                icon: PhosphorIcons.timer(),
              ),
              if (progress.stepsAverage != null)
                StatCard(
                  label: 'Pasos promedio',
                  value: Fmt.steps(progress.stepsAverage!),
                  icon: PhosphorIcons.footprints(),
                )
              else
                const SizedBox.shrink(),
            ],
          ),
          const SizedBox(height: NmSpace.s6),
          const NmSectionHeader(title: 'Distribución por categoría'),
          NmCard(
            child: ActivityCategoryChart(slices: progress.activityByCategory),
          ),
          const SizedBox(height: NmSpace.s6),
          const NmSectionHeader(title: 'Resumen del período'),
          NmCard(
            child: Column(
              children: <Widget>[
                ValueRow(
                  label: 'Sesiones realizadas',
                  value: '${totals.sessions}',
                ),
                ValueRow(
                  label: 'Promedio de duración',
                  value: Fmt.duration(totals.avgDurationMinutes),
                ),
                ValueRow(
                  label: 'Calorías estimadas',
                  value: Fmt.estimatedKcal(totals.estimatedCalories),
                ),
                ValueRow(
                  label: 'Actividad más frecuente',
                  value: totals.mostFrequentTypeName ?? '—',
                ),
                ValueRow(
                  label: 'Mayor duración registrada',
                  value: Fmt.duration(totals.longestSessionMinutes),
                ),
                ValueRow(
                  label: 'Días con actividad',
                  value: '${totals.activeDays}',
                ),
                if (totals.restDays > 0)
                  ValueRow(
                    label: 'Descansos planificados',
                    value: '${totals.restDays}',
                    muted: true,
                  ),
              ],
            ),
          ),
          const SizedBox(height: NmSpace.s6),
          ConsistencyNote(lines: SummaryBuilder.consistencyNotes(progress)),
        ],
      ),
    );
  }
}

/// S-25 · Objetivos de actividad. Opcionales y sin consecuencias (RN-09).
class ActivityGoalsScreen extends ConsumerWidget {
  const ActivityGoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(progressProvider);
    final repo = ref.watch(repositoryProvider);

    return NmScreen(
      title: 'Objetivos de actividad',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          const InfoNote(
            text: 'Los objetivos de actividad nunca reducen tu objetivo '
                'calórico ni bloquean nada. Podés usar Ceres sin '
                'configurar ninguno.',
          ),
          const SizedBox(height: NmSpace.s6),
          if (progress.goals.isEmpty)
            EmptyState(
              icon: PhosphorIcons.target(),
              title: 'Sin objetivos configurados',
              body: 'Los objetivos de actividad son opcionales.',
              primaryLabel: 'Crear un objetivo',
              onPrimary: () => _showGoalSheet(context, ref, null),
            )
          else
            for (final goal in progress.goals)
              Padding(
                padding: const EdgeInsets.only(bottom: NmSpace.s3),
                child: ActivityGoalCard(
                  progress: goal,
                  onEdit: () => _showGoalSheet(context, ref, goal),
                  onToggle: (enabled) => repo.saveActivityGoal(
                    goal.goal.copyWith(enabled: enabled),
                  ),
                ),
              ),
          const SizedBox(height: NmSpace.s4),
          if (progress.goals.isNotEmpty)
            NmButton.secondary(
              label: 'Crear otro objetivo',
              block: true,
              onPressed: () => _showGoalSheet(context, ref, null),
            ),
        ],
      ),
    );
  }

  void _showGoalSheet(
    BuildContext context,
    WidgetRef ref,
    ActivityGoalProgress? existing,
  ) {
    var type = existing?.goal.goalType ?? ActivityGoalType.activeMinutes;
    var period = existing?.goal.period ?? GoalPeriod.week;
    final value = TextEditingController(
      text: (existing?.goal.targetValue ?? 150).toString(),
    );

    showNmSheet<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => NmSheet(
          title: existing == null ? 'Nuevo objetivo' : 'Editar objetivo',
          footer: Row(
            children: <Widget>[
              if (existing != null)
                NmButton.ghost(
                  label: 'Eliminar',
                  onPressed: () async {
                    await ref
                        .read(repositoryProvider)
                        .deleteActivityGoal(existing.goal.id);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
              const Spacer(),
              NmButton(
                label: 'Guardar',
                onPressed: () async {
                  final parsed = int.tryParse(value.text);
                  if (parsed == null || parsed <= 0) return;
                  await ref.read(repositoryProvider).saveActivityGoal(
                    ActivityGoal(
                      id: existing?.goal.id ?? _uuid.v4(),
                      goalType: type,
                      targetValue: parsed,
                      period: period,
                      startDate: existing?.goal.startDate ?? today(),
                    ),
                  );
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const NmSectionHeader(title: 'Tipo'),
              Wrap(
                spacing: NmSpace.s2,
                runSpacing: NmSpace.s2,
                children: <Widget>[
                  for (final option in ActivityGoalType.values)
                    NmChip(
                      label: option.label,
                      selected: option == type,
                      semanticsInRadioGroup: true,
                      onTap: () => setLocal(() => type = option),
                    ),
                ],
              ),
              const SizedBox(height: NmSpace.s6),
              NmNumberField(label: 'Valor objetivo', controller: value),
              const SizedBox(height: NmSpace.s6),
              const NmSectionHeader(title: 'Período'),
              NmSegmentedControl<GoalPeriod>(
                options: GoalPeriod.values
                    .map((p) => (p, p == GoalPeriod.day ? 'Día' : 'Semana'))
                    .toList(),
                value: period,
                onChanged: (v) => setLocal(() => period = v),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// S-26 · Medidas corporales.
class MeasurementsScreen extends ConsumerStatefulWidget {
  const MeasurementsScreen({super.key});

  @override
  ConsumerState<MeasurementsScreen> createState() => _MeasurementsScreenState();
}

/// Las medidas del grupo son **campos**, no una fila de píldoras.
///
/// Antes había que elegir una métrica con una píldora para ver su número, así
/// que las otras siete no se veían y para cargar cualquiera había que abrir un
/// sheet aparte. La planilla de una nutricionista no se lee de a una: se ve el
/// cuerpo entero y al lado lo que decía la vez pasada. Los campos hacen las dos
/// cosas —mostrar la última medida y dejar cargar la nueva— sin cambiar de
/// pantalla ni de selección.
class _MeasurementsScreenState extends ConsumerState<MeasurementsScreen> {
  MeasurementGroup _group = MeasurementGroup.perimeters;
  DateTime _date = today();

  final MeasurementDraft _draft = MeasurementDraft();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _draft.loadFrom(ref.read(repositoryProvider), _date));
    });
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final saved = await _draft.commit(ref.read(repositoryProvider), _date);
    if (!mounted) return;

    if (saved == null) {
      setState(() {
        _saving = false;
        final first = _draft.errors.keys.firstOrNull;
        if (first != null) _group = first.group;
      });
      return;
    }

    setState(() => _saving = false);
    NmSnackbar.show(
      context,
      saved == 1 ? 'Medida registrada' : '$saved medidas registradas',
    );
  }

  /// La última medida cargada de esa métrica, cualquiera sea su fecha.
  String _lastLabel(CeresRepositories repo, MeasurementMetric metric) {
    final entries = repo.measurements(metric);
    if (entries.isEmpty) return 'Sin registros';
    final last = entries.last;
    final value = '${Fmt.decimal1(last.value)} ${metric.unitLabel}'.trim();
    return 'Última: $value · ${friendlyDay(last.localDate)}';
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final repo = ref.watch(repositoryProvider);
    // Se lee para que la pantalla se redibuje al guardar desde el sheet.
    ref.watch(appRevisionProvider);

    final metrics = MeasurementMetric.inGroup(_group);
    final (foldSum, foldCount) = _draft.foldSum;
    final withHistory = MeasurementMetric.values
        .where((m) => repo.measurements(m).length >= 2)
        .toList();

    return NmScreen(
      title: 'Medidas corporales',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          NmSegmentedControl<MeasurementGroup>(
            options: const <(MeasurementGroup, String)>[
              (MeasurementGroup.perimeters, 'Perímetros'),
              (MeasurementGroup.skinfolds, 'Pliegues'),
              (MeasurementGroup.composition, 'Balanza'),
            ],
            value: _group,
            onChanged: (v) => setState(() => _group = v),
          ),
          const SizedBox(height: NmSpace.s3),
          Text(
            _group.help,
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
          ),
          const SizedBox(height: NmSpace.s5),

          for (final metric in metrics)
            Padding(
              padding: const EdgeInsets.only(bottom: NmSpace.s4),
              child: NmNumberField(
                label: metric.label,
                controller: _draft.controller(metric),
                decimals: 1,
                suffix: metric.unitLabel.isEmpty
                    ? 'índice'
                    : metric.unitLabel,
                helper: _lastLabel(repo, metric),
                error: _draft.errors[metric],
                onChanged: (_) => setState(() => _draft.errors.remove(metric)),
              ),
            ),

          if (_group == MeasurementGroup.skinfolds && foldCount >= 2) ...<Widget>[
            NmCard(
              raised: true,
              child: ValueRow(
                label: 'Sumatoria',
                caption: '$foldCount pliegues',
                value: '${Fmt.decimal1(foldSum)} mm',
                emphasis: true,
              ),
            ),
            const SizedBox(height: NmSpace.s4),
          ],

          NmDateField(
            label: 'Fecha',
            value: _date,
            lastDate: DateTime.now(),
            onChanged: (v) => setState(() {
              _date = v;
              _draft.loadFrom(repo, _date);
            }),
          ),
          const SizedBox(height: NmSpace.s5),
          NmButton(
            label: 'Guardar medidas',
            block: true,
            loading: _saving,
            onPressed: _save,
          ),

          if (withHistory.isNotEmpty) ...<Widget>[
            const SizedBox(height: NmSpace.s8),
            const NmSectionHeader(title: 'Series'),
            NmCard(
              padding: const EdgeInsets.symmetric(vertical: NmSpace.s1),
              child: Column(
                children: <Widget>[
                  for (final metric in withHistory)
                    NmListRow(
                      title: metric.longLabel,
                      subtitle:
                          '${repo.measurements(metric).length} registros',
                      trailing: Icon(
                        PhosphorIcons.caretRight(),
                        size: NmIconSize.md,
                        color: nm.textMuted,
                      ),
                      onTap: () => _showSeries(metric),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// La serie de una métrica: el gráfico y los últimos doce registros.
  ///
  /// Estaba en la pantalla, atada a la píldora elegida. Al pasar a campos ya no
  /// hay una métrica "elegida", así que la serie se pide por la que interesa en
  /// vez de ser el único número visible.
  void _showSeries(MeasurementMetric metric) {
    final entries = ref.read(repositoryProvider).measurements(metric);
    showNmSheet<void>(
      context: context,
      builder: (context) => NmSheet(
        title: metric.longLabel,
        subtitle: '${entries.length} registros',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            NmCard(
              child: WeightChart(
                id: 'measure-${metric.wire}',
                points: entries
                    .map((m) => ChartPoint(m.localDate, m.value))
                    .toList(),
                movingAverage: const <ChartPoint>[],
              ),
            ),
            const SizedBox(height: NmSpace.s5),
            NmCard(
              child: Column(
                children: <Widget>[
                  for (final entry in entries.reversed.take(12))
                    ValueRow(
                      label: friendlyDay(entry.localDate),
                      value: '${Fmt.decimal1(entry.value)} '
                              '${metric.unitLabel}'
                          .trim(),
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
