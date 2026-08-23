// Que el agregado de Progreso divida por los días que se podían registrar.
//
// El test de `tracking_window_test.dart` fija la regla; este fija que
// `SummaryBuilder.progress` la **use**, que es donde se rompía: la ventana
// existía en el informe en PDF desde hacía meses y ninguna otra métrica la
// miraba. Ver `docs/contexto-diario.md`.

import 'package:ceres/domain/calculations/alcohol.dart';
import 'package:ceres/domain/enums/enums.dart';
import 'package:ceres/domain/models/activity.dart';
import 'package:ceres/domain/models/alcohol.dart';
import 'package:ceres/domain/models/body.dart';
import 'package:ceres/domain/models/day_marker.dart';
import 'package:ceres/domain/models/goal.dart';
import 'package:ceres/domain/models/meal.dart';
import 'package:ceres/domain/services/summary_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DateTime d(int y, int m, int day) => DateTime(y, m, day);

  final goal = Goal(
    id: 'g',
    goalType: GoalType.lose,
    rateKgPerWeek: 0.5,
    baseCalorieTarget: 2000,
    targetMethod: TargetMethod.calculated,
    proteinG: 120,
    carbsG: 220,
    fatG: 65,
    macroMethod: 'default',
    startsOn: d(2026, 1, 1),
  );

  Meal comida(DateTime day, int kcal) => Meal(
    id: 'm-$day-$kcal',
    slot: MealSlot.lunch,
    eatenAt: day,
    localDate: day,
    source: MealSource.manual,
    createdAt: day,
    updatedAt: day,
    items: <MealItem>[
      MealItem(
        id: 'i-$day-$kcal',
        name: 'Algo',
        quantity: 1,
        unit: 'porción',
        kcal: kcal,
        proteinG: 10,
        carbsG: 20,
        fatG: 5,
        position: 0,
      ),
    ],
  );

  group('el período efectivo manda sobre el calendario', () {
    test('cuenta creada a mitad de mes: 3 de 3, no 3 de 30', () {
      // Empezó el 18, mira los 30 días que terminan el 20.
      final meals = <Meal>[
        comida(d(2026, 8, 18), 1800),
        comida(d(2026, 8, 19), 1900),
        comida(d(2026, 8, 20), 2100),
      ];

      final p = SummaryBuilder.progress(
        from: d(2026, 7, 22),
        to: d(2026, 8, 20),
        allMeals: meals,
        allActivities: const <Activity>[],
        weightLogs: const <WeightLog>[],
        activityGoals: const <ActivityGoal>[],
        goalFor: (_) => goal,
        isRestDay: (_) => false,
        creditEnabled: false,
        trackingSince: d(2026, 8, 18),
      );

      // El rótulo del período no cambia: sigue siendo el de 30 días.
      expect(p.days, 30);
      // El denominador sí.
      expect(p.window.effectiveDays, 3);
      expect(p.window.startedMidPeriod, isTrue);
      expect(p.window.coveragePct(3), 100);
    });

    test('sin la ventana, el promedio semanal miente por cinco', () {
      // 90 minutos en los tres días que existieron. Con los 30 del calendario,
      // eso daba 21 min/semana; con los 3 reales, 210.
      final acts = <Activity>[
        for (final day in <DateTime>[
          d(2026, 8, 18),
          d(2026, 8, 19),
          d(2026, 8, 20),
        ])
          Activity(
            id: 'a-$day',
            activityTypeId: 'walking',
            startedAt: day,
            localDate: day,
            durationMinutes: 30,
            intensity: Intensity.moderate,
            estimatedCalories: 100,
            appliedCalories: 0,
            exerciseCreditPercentage: 0,
            estimationMethod: EstimationMethod.met,
            sourceType: ActivitySourceType.manual,
            createdAt: day,
            updatedAt: day,
          ),
      ];

      final p = SummaryBuilder.progress(
        from: d(2026, 7, 22),
        to: d(2026, 8, 20),
        allMeals: const <Meal>[],
        allActivities: acts,
        weightLogs: const <WeightLog>[],
        activityGoals: const <ActivityGoal>[],
        goalFor: (_) => goal,
        isRestDay: (_) => false,
        creditEnabled: false,
        trackingSince: d(2026, 8, 18),
      );

      expect(p.activityTotals.minutes, 90);
      expect(p.weeklyAverageMinutes, 210);
    });

    test('sin ningún dato no se divide por cero', () {
      final p = SummaryBuilder.progress(
        from: d(2026, 8, 1),
        to: d(2026, 8, 30),
        allMeals: const <Meal>[],
        allActivities: const <Activity>[],
        weightLogs: const <WeightLog>[],
        activityGoals: const <ActivityGoal>[],
        goalFor: (_) => goal,
        isRestDay: (_) => false,
        creditEnabled: false,
      );

      expect(p.window.isEmpty, isTrue);
      expect(p.weeklyAverageMinutes, 0);
      expect(p.adherencePct, isNull);
      expect(p.averageConsumed, 0);
    });

    test('los días de descanso anteriores a la cuenta no se cuentan', () {
      final p = SummaryBuilder.progress(
        from: d(2026, 7, 22),
        to: d(2026, 8, 20),
        allMeals: <Meal>[comida(d(2026, 8, 18), 1800)],
        allActivities: const <Activity>[],
        weightLogs: const <WeightLog>[],
        activityGoals: const <ActivityGoal>[],
        goalFor: (_) => goal,
        // Todo el calendario marcado: sin la ventana serían 30.
        isRestDay: (_) => true,
        creditEnabled: false,
        trackingSince: d(2026, 8, 18),
      );

      expect(p.activityTotals.restDays, 3);
    });

    test('la serie del gráfico sigue arrancando en el día pedido', () {
      // El eje X es el calendario: recortarlo movería las barras de lugar y el
      // gráfico contradiría al calendario de adherencia de al lado.
      final p = SummaryBuilder.progress(
        from: d(2026, 8, 1),
        to: d(2026, 8, 20),
        allMeals: <Meal>[comida(d(2026, 8, 18), 1800)],
        allActivities: const <Activity>[],
        weightLogs: const <WeightLog>[],
        activityGoals: const <ActivityGoal>[],
        goalFor: (_) => goal,
        isRestDay: (_) => false,
        creditEnabled: false,
        trackingSince: d(2026, 8, 18),
      );

      expect(p.calorieDays.first.date, d(2026, 8, 1));
      expect(p.calorieDays, hasLength(20));
    });
  });

  group('el contexto viaja con el agregado', () {
    test('los días de enfermedad del período llegan ordenados', () {
      final p = SummaryBuilder.progress(
        from: d(2026, 8, 1),
        to: d(2026, 8, 20),
        allMeals: <Meal>[comida(d(2026, 8, 5), 1800)],
        allActivities: const <Activity>[],
        weightLogs: const <WeightLog>[],
        activityGoals: const <ActivityGoal>[],
        goalFor: (_) => goal,
        isRestDay: (_) => false,
        creditEnabled: false,
        trackingSince: d(2026, 8, 1),
        markers: <DayMarker>[
          DayMarker(
            id: 'b',
            localDate: d(2026, 8, 12),
            kind: DayMarkerKind.sick,
            updatedAt: d(2026, 8, 12),
          ),
          DayMarker(
            id: 'a',
            localDate: d(2026, 8, 10),
            kind: DayMarkerKind.sick,
            updatedAt: d(2026, 8, 10),
          ),
          // Fuera del período: no entra.
          DayMarker(
            id: 'c',
            localDate: d(2026, 7, 30),
            kind: DayMarkerKind.sick,
            updatedAt: d(2026, 7, 30),
          ),
          // De descanso: no es enfermedad.
          DayMarker(
            id: 'd',
            localDate: d(2026, 8, 11),
            kind: DayMarkerKind.rest,
            updatedAt: d(2026, 8, 11),
          ),
        ],
      );

      expect(p.sickDays.map((m) => m.id).toList(), <String>['a', 'b']);
    });

    test('las calorías del alcohol no se suman a las de las comidas', () {
      // Es la propiedad que hace útil la feature: si se sumaran ahí, la semana
      // en que el peso no bajó se vería como "comió de más" en vez de "tomó".
      final p = SummaryBuilder.progress(
        from: d(2026, 8, 1),
        to: d(2026, 8, 20),
        allMeals: <Meal>[comida(d(2026, 8, 15), 1800)],
        allActivities: const <Activity>[],
        weightLogs: const <WeightLog>[],
        activityGoals: const <ActivityGoal>[],
        goalFor: (_) => goal,
        isRestDay: (_) => false,
        creditEnabled: false,
        trackingSince: d(2026, 8, 1),
        alcoholLogs: <AlcoholLog>[
          AlcoholLog(
            id: 'x',
            localDate: d(2026, 8, 15),
            type: DrinkType.beer,
            quantity: 3,
            volumeMl: 473,
            abvPct: 5,
            loggedAt: d(2026, 8, 15),
            updatedAt: d(2026, 8, 15),
          ),
        ],
      );

      expect(p.averageConsumed, 1800);
      expect(p.drinkingDays, 1);
      expect(p.totalStandardDrinks, closeTo(5.6, 0.2));
      expect(p.alcoholKcal, greaterThan(500));
    });
  });
}
