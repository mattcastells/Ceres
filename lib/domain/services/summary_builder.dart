import 'dart:math' as math;

import '../../core/utils/dates.dart';
import '../calculations/adherence.dart';
import '../calculations/moving_average.dart';
import '../calculations/rounding.dart';
import '../calculations/tracking_window.dart';
import '../enums/enums.dart';
import '../models/activity.dart';
import '../models/alcohol.dart';
import '../models/body.dart';
import '../models/day_marker.dart';
import '../models/goal.dart';
import '../models/meal.dart';
import '../models/summaries.dart';

/// Construcción de los agregados de lectura a partir de los registros crudos.
///
/// Son funciones puras: no tocan red, base ni framework de UI. Toda la
/// aritmética sale de `domain/calculations/`.
abstract final class SummaryBuilder {
  static List<Meal> mealsOn(List<Meal> meals, DateTime date) =>
      meals.where((m) => !m.isDeleted && isSameDay(m.localDate, date)).toList()
        ..sort((a, b) => a.eatenAt.compareTo(b.eatenAt));

  static List<Activity> activitiesOn(
    List<Activity> activities,
    DateTime date,
  ) =>
      activities
          .where((a) => !a.isDeleted && isSameDay(a.localDate, date))
          .toList()
        ..sort((a, b) => a.startedAt.compareTo(b.startedAt));

  /// El resumen de Inicio (S-06) y del detalle del día (S-22).
  static DailySummary daily({
    required DateTime date,
    required Goal goal,
    required List<Meal> allMeals,
    required List<Activity> allActivities,
    required List<WeightLog> weightLogs,
    required int creditPercentage,
    required bool creditEnabled,
    required bool isRestDay,
    DayMarker? sickMarker,
    List<AlcoholLog> alcoholLogs = const <AlcoholLog>[],
  }) {
    final meals = mealsOn(allMeals, date);
    final activities = activitiesOn(allActivities, date);
    final tragos = alcoholLogs
        .where((a) => !a.isDeleted && isSameDay(a.localDate, date))
        .toList();

    final consumed = meals.fold(0, (acc, m) => acc + m.totalKcal);
    final estimated = activities.fold(0, (acc, a) => acc + a.estimatedCalories);
    // Cada actividad conserva su porcentaje congelado (D-05): se suman las
    // aplicadas ya persistidas, no se recalcula el día entero.
    final applied = creditEnabled
        ? activities.fold(0, (acc, a) => acc + a.appliedCalories)
        : 0;

    final protein = meals.fold(0.0, (acc, m) => acc + m.totalProteinG);
    final carbs = meals.fold(0.0, (acc, m) => acc + m.totalCarbsG);
    final fat = meals.fold(0.0, (acc, m) => acc + m.totalFatG);

    final minutes = activities.fold(0, (acc, a) => acc + a.durationMinutes);
    final stepsValues = activities
        .map((a) => a.steps)
        .whereType<int>()
        .toList();

    return DailySummary(
      date: dateOnly(date),
      baseTarget: goal.baseCalorieTarget,
      consumedKcal: consumed,
      exerciseEstimatedKcal: estimated,
      exerciseAppliedKcal: applied,
      creditPercentage: creditPercentage,
      creditEnabled: creditEnabled,
      macros: MacroSet(
        protein: MacroProgress(current: protein, target: goal.proteinG),
        carbs: MacroProgress(current: carbs, target: goal.carbsG),
        fat: MacroProgress(current: fat, target: goal.fatG),
      ),
      meals: meals,
      activities: activities,
      activityTotals: ActivityTotals(
        minutes: minutes,
        sessions: activities.length,
        steps: stepsValues.isEmpty
            ? null
            : stepsValues.fold<int>(0, (acc, s) => acc + s),
      ),
      weight: _weightSnapshot(weightLogs, date),
      isRestDay: isRestDay,
      sickMarker: sickMarker,
      // `null` y no un día vacío: la tarjeta no aparece en vez de mostrar
      // "0 tragos", que es un dato que nadie pidió ver todos los días.
      alcohol: tragos.isEmpty ? null : AlcoholDay.group(tragos).first,
    );
  }

  static WeightSnapshot? _weightSnapshot(List<WeightLog> logs, DateTime date) {
    final sorted = <WeightLog>[...logs.where((w) => !w.isDeleted)]
      ..sort((a, b) => a.localDate.compareTo(b.localDate));
    final upToDate = sorted
        .where((w) => !w.localDate.isAfter(dateOnly(date)))
        .toList();
    if (upToDate.isEmpty) return null;
    final latest = upToDate.last;
    final previous = upToDate.length > 1 ? upToDate[upToDate.length - 2] : null;
    return WeightSnapshot(
      weightKg: latest.weightKg,
      deltaKg: previous == null
          ? 0
          : double.parse(
              (latest.weightKg - previous.weightKg).toStringAsFixed(1),
            ),
    );
  }

  /// Las filas-día del Historial (S-21), de la más reciente a la más vieja.
  static List<HistoryDay> history({
    required DateTime from,
    required DateTime to,
    required List<Meal> allMeals,
    required List<Activity> allActivities,
    required Goal Function(DateTime) goalFor,
    required bool Function(DateTime) isRestDay,
    bool creditEnabled = true,
    bool Function(DateTime)? isSickDay,
    List<AlcoholLog> alcoholLogs = const <AlcoholLog>[],
  }) {
    final days = <HistoryDay>[];
    var cursor = dateOnly(to);
    final start = dateOnly(from);

    // Una sola pasada por los tragos, no una por día: con un año de historial y
    // un filtro adentro del `while`, esto es cuadrático.
    final tragosPorDia = <String, double>{};
    for (final a in alcoholLogs) {
      if (a.isDeleted) continue;
      final k = isoDate(a.localDate);
      tragosPorDia[k] = (tragosPorDia[k] ?? 0) + a.standardDrinksTotal;
    }

    while (!cursor.isBefore(start)) {
      final meals = mealsOn(allMeals, cursor);
      final activities = activitiesOn(allActivities, cursor);
      final steps = activities.map((a) => a.steps).whereType<int>().toList();

      days.add(
        HistoryDay(
          date: cursor,
          consumedKcal: meals.fold(0, (acc, m) => acc + m.totalKcal),
          activityKcal: activities.fold(
            0,
            (acc, a) => acc + a.estimatedCalories,
          ),
          appliedKcal: creditEnabled
              ? activities.fold(0, (acc, a) => acc + a.appliedCalories)
              : 0,
          baseTarget: goalFor(cursor).baseCalorieTarget,
          exerciseMinutes: activities.fold(
            0,
            (acc, a) => acc + a.durationMinutes,
          ),
          activityCount: activities.length,
          steps: steps.isEmpty ? null : steps.fold<int>(0, (acc, s) => acc + s),
          isRestDay: isRestDay(cursor),
          hasRecords: meals.isNotEmpty || activities.isNotEmpty,
          isSickDay: isSickDay?.call(cursor) ?? false,
          standardDrinks: tragosPorDia[isoDate(cursor)] ?? 0,
        ),
      );
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return days;
  }

  /// El agregado de Progreso (S-23 y S-24).
  ///
  /// **El período del que se cuenta no es el que se pidió.** Es el que se
  /// solapa con el tiempo que la persona lleva usando la app: alguien que
  /// arrancó el 18 de agosto, mirando "los últimos 30 días" el 19, registró 2
  /// de 2 días y no 2 de 30. Todo lo que divide por una cantidad de días sale
  /// de [TrackingWindow] y no de `from`; ver `docs/contexto-diario.md`.
  ///
  /// Las series de los gráficos —calorías por día, actividad por día— **sí**
  /// arrancan en `from`, porque el eje X es el calendario y recortarlo movería
  /// las barras de lugar. Lo que cambia es qué se cuenta, no dónde se dibuja.
  static ProgressSummary progress({
    required DateTime from,
    required DateTime to,
    required List<Meal> allMeals,
    required List<Activity> allActivities,
    required List<WeightLog> weightLogs,
    required List<ActivityGoal> activityGoals,
    required Goal Function(DateTime) goalFor,
    required bool Function(DateTime) isRestDay,
    required bool creditEnabled,
    DateTime? trackingSince,
    List<DayMarker> markers = const <DayMarker>[],
    List<AlcoholLog> alcoholLogs = const <AlcoholLog>[],
  }) {
    final start = dateOnly(from);
    final end = dateOnly(to);
    final dayCount = daysBetween(start, end) + 1;

    final window = TrackingWindow(
      from: start,
      to: end,
      trackingSince: trackingSince,
    );

    final weightInRange =
        weightLogs
            .where(
              (w) =>
                  !w.isDeleted &&
                  !w.localDate.isBefore(start) &&
                  !w.localDate.isAfter(end),
            )
            .toList()
          ..sort((a, b) => a.localDate.compareTo(b.localDate));

    final weightPoints = weightInRange
        .map((w) => ChartPoint(w.localDate, w.weightKg))
        .toList();
    final seriesPoints = weightInRange
        .map((w) => SeriesPoint(w.localDate, w.weightKg))
        .toList();
    final movingAvg = movingAverage(
      seriesPoints,
      7,
    ).map((p) => ChartPoint(p.date, p.value)).toList();

    final calorieDays = <CaloriesDay>[];
    final activityByDay = <ActivityDayPoint>[];
    final adherenceDays = <AdherenceDay>[];
    var restDayCount = 0;

    for (var i = 0; i < dayCount; i++) {
      final day = start.add(Duration(days: i));
      final meals = mealsOn(allMeals, day);
      final activities = activitiesOn(allActivities, day);
      final goal = goalFor(day);
      final applied = creditEnabled
          ? activities.fold(0, (acc, a) => acc + a.appliedCalories)
          : 0;
      final consumed = meals.fold(0, (acc, m) => acc + m.totalKcal);

      calorieDays.add(
        CaloriesDay(
          date: day,
          consumed: consumed,
          target: goal.baseCalorieTarget,
          exerciseApplied: applied,
        ),
      );
      if (window.contains(day)) {
        adherenceDays.add(
          AdherenceDay(consumed: consumed, target: goal.baseCalorieTarget),
        );
      }
      activityByDay.add(
        ActivityDayPoint(
          date: day,
          minutes: activities.fold(0, (acc, a) => acc + a.durationMinutes),
          calories: activities.fold(0, (acc, a) => acc + a.estimatedCalories),
          sessions: activities.length,
        ),
      );
      // Los días de descanso se cuentan **dentro de la ventana efectiva**: un
      // "3 días de descanso" que incluyera días anteriores a la cuenta sería
      // contar como descanso el tiempo en que la app no existía.
      if (window.contains(day) && isRestDay(day)) restDayCount++;
    }

    final rangeActivities = allActivities
        .where(
          (a) =>
              !a.isDeleted &&
              !a.localDate.isBefore(start) &&
              !a.localDate.isAfter(end),
        )
        .toList();

    final byCategory = <ActivityCategory, int>{};
    final byType = <String, int>{};
    for (final a in rangeActivities) {
      final category = a.activityType?.category ?? ActivityCategory.other;
      byCategory[category] = (byCategory[category] ?? 0) + a.durationMinutes;
      final name = a.activityType?.displayName ?? 'Otras';
      byType[name] = (byType[name] ?? 0) + 1;
    }

    final totalMinutes = rangeActivities.fold(
      0,
      (acc, a) => acc + a.durationMinutes,
    );
    final activeDays = rangeActivities
        .map((a) => isoDate(a.localDate))
        .toSet()
        .length;

    String? mostFrequent;
    var mostFrequentCount = 0;
    byType.forEach((name, count) {
      if (count > mostFrequentCount) {
        mostFrequent = name;
        mostFrequentCount = count;
      }
    });

    final thisWeekStart = startOfIsoWeek(end);
    final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));
    final thisWeekMinutes = rangeActivities
        .where((a) => !a.localDate.isBefore(thisWeekStart))
        .fold(0, (acc, a) => acc + a.durationMinutes);
    final lastWeekMinutes = allActivities
        .where(
          (a) =>
              !a.isDeleted &&
              !a.localDate.isBefore(lastWeekStart) &&
              a.localDate.isBefore(thisWeekStart),
        )
        .fold(0, (acc, a) => acc + a.durationMinutes);

    final stepValues = rangeActivities
        .map((a) => a.steps)
        .whereType<int>()
        .toList();

    final firstWeight = weightInRange.isEmpty
        ? 0.0
        : weightInRange.first.weightKg;
    final lastWeight = weightInRange.isEmpty
        ? 0.0
        : weightInRange.last.weightKg;

    final marcasEnfermedad = <DayMarker>[
      for (final m in markers)
        if (!m.isDeleted &&
            m.kind == DayMarkerKind.sick &&
            !dateOnly(m.localDate).isBefore(start) &&
            !dateOnly(m.localDate).isAfter(end))
          m,
    ]..sort((a, b) => a.localDate.compareTo(b.localDate));

    final tragos = AlcoholDay.group(
      alcoholLogs.where(
        (a) =>
            !dateOnly(a.localDate).isBefore(start) &&
            !dateOnly(a.localDate).isAfter(end),
      ),
    );

    return ProgressSummary(
      from: start,
      to: end,
      days: dayCount,
      window: window,
      sickDays: marcasEnfermedad,
      alcoholDays: tragos,
      weightPoints: weightPoints,
      weightMovingAverage: movingAvg,
      weightDeltaKg: double.parse(
        (lastWeight - firstWeight).toStringAsFixed(1),
      ),
      trendKgPerWeek: weightTrendKgPerWeek(seriesPoints),
      calorieDays: calorieDays,
      averageConsumed: calorieDays.isEmpty
          ? 0
          : roundHalfUp(
              calorieDays.fold(0, (acc, d) => acc + d.consumed) /
                  math.max(1, calorieDays.where((d) => d.consumed > 0).length),
            ),
      adherencePct: adherencePct(adherenceDays),
      activityByDay: activityByDay,
      activityByCategory:
          byCategory.entries
              .map((e) => CategorySlice(category: e.key, minutes: e.value))
              .toList()
            ..sort((a, b) => b.minutes.compareTo(a.minutes)),
      activityTotals: ActivityPeriodTotals(
        minutes: totalMinutes,
        sessions: rangeActivities.length,
        avgDurationMinutes: rangeActivities.isEmpty
            ? 0
            : roundHalfUp(totalMinutes / rangeActivities.length),
        estimatedCalories: rangeActivities.fold(
          0,
          (acc, a) => acc + a.estimatedCalories,
        ),
        activeDays: activeDays,
        longestSessionMinutes: rangeActivities.isEmpty
            ? 0
            : rangeActivities
                  .map((a) => a.durationMinutes)
                  .reduce((a, b) => a > b ? a : b),
        restDays: restDayCount,
        mostFrequentTypeName: mostFrequent,
      ),
      // Minutos por semana sobre los días que **se podían** registrar. Con
      // `dayCount` —los 30 del calendario— alguien que arrancó hace cinco días
      // veía sus 90 minutos divididos por 4,3 semanas: 21 min/semana, cuando la
      // única semana que existió tuvo 90.
      weeklyAverageMinutes: window.effectiveDays == 0
          ? 0
          : roundHalfUp(totalMinutes / (window.effectiveDays / 7)),
      previousWeekDeltaMinutes: thisWeekMinutes - lastWeekMinutes,
      stepsAverage: stepValues.isEmpty
          ? null
          : roundHalfUp(
              stepValues.fold(0, (acc, s) => acc + s) / stepValues.length,
            ),
      goals: activityGoals
          .map(
            (g) => ActivityGoalProgress(
              goal: g,
              currentValue: _goalCurrentValue(
                goal: g,
                activities: allActivities,
                reference: end,
              ),
            ),
          )
          .toList(),
    );
  }

  /// Valor actual de un objetivo de actividad en su período (§18).
  static int _goalCurrentValue({
    required ActivityGoal goal,
    required List<Activity> activities,
    required DateTime reference,
  }) {
    final start = goal.period == GoalPeriod.week
        ? startOfIsoWeek(reference)
        : dateOnly(reference);
    final inPeriod = activities
        .where((a) => !a.isDeleted && !a.localDate.isBefore(start))
        .toList();

    return switch (goal.goalType) {
      ActivityGoalType.activeMinutes => inPeriod.fold(
        0,
        (acc, a) => acc + a.durationMinutes,
      ),
      ActivityGoalType.sessions => inPeriod.length,
      ActivityGoalType.steps =>
        inPeriod.map((a) => a.steps ?? 0).fold(0, (acc, s) => acc + s),
      ActivityGoalType.distance =>
        inPeriod.map((a) => a.distanceMeters ?? 0).fold(0, (acc, d) => acc + d),
      ActivityGoalType.strengthSessions =>
        inPeriod
            .where((a) => a.activityType?.category == ActivityCategory.strength)
            .length,
      ActivityGoalType.activeDays =>
        inPeriod.map((a) => isoDate(a.localDate)).toSet().length,
    };
  }

  /// Mensajes de consistencia con copy neutral (S-24, RN-14 y RN-15).
  static List<String> consistencyNotes(ProgressSummary p) {
    final notes = <String>[];
    final totals = p.activityTotals;

    if (totals.sessions == 0) {
      notes.add('Todavía no registraste actividad en este período.');
      return notes;
    }

    // Los días activos son del período entero, así que el "de los últimos"
    // también. Antes decía "13 de los últimos 7 días": contaba 30 y nombraba 7.
    final restSuffix = totals.restDays > 0
        ? ' (${totals.restDays} de descanso planificado)'
        : '';
    notes.add(
      'Te moviste ${totals.activeDays} de los últimos ${p.days} '
      'días$restSuffix.',
    );

    final thisWeek = p.activityByDay
        .where((d) => !d.date.isBefore(startOfIsoWeek(p.to)))
        .fold(0, (acc, d) => acc + d.minutes);
    final delta = p.previousWeekDeltaMinutes;
    final comparison = delta > 0
        ? '$delta más que la anterior'
        : delta < 0
        ? '${delta.abs()} menos que la anterior'
        : 'igual que la anterior';
    notes.add('Esta semana llevás $thisWeek min, $comparison.');
    return notes;
  }
}
