// Los 20 casos de 11-calculation-rules.md §20 más los límites y errores que
// pide cada sección. Estos tests corren **antes** de escribir una pantalla
// (decisions.md §4, paso 6).

import 'package:ceres/core/error/app_error.dart';
import 'package:ceres/domain/calculations/adherence.dart';
import 'package:ceres/domain/calculations/bmr.dart';
import 'package:ceres/domain/calculations/calorie_target.dart';
import 'package:ceres/domain/calculations/daily_balance.dart';
import 'package:ceres/domain/calculations/duplicate_score.dart';
import 'package:ceres/domain/calculations/exercise_credit.dart';
import 'package:ceres/domain/calculations/macros.dart';
import 'package:ceres/domain/calculations/met_calories.dart';
import 'package:ceres/domain/calculations/moving_average.dart';
import 'package:ceres/domain/calculations/pace_met.dart';
import 'package:ceres/domain/calculations/rounding.dart';
import 'package:ceres/domain/calculations/tdee.dart';
import 'package:ceres/domain/enums/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('§1 · BMR — Mifflin-St Jeor', () {
    test('T-01 · F, 30 a, 165 cm, 70 kg → 1420', () {
      expect(
        bmrMifflinStJeor(
          weightKg: 70,
          heightCm: 165,
          ageYears: 30,
          sex: BiologicalSex.female,
        ),
        1420,
      );
    });

    test('T-02 · M, 40 a, 180 cm, 90 kg → 1830', () {
      expect(
        bmrMifflinStJeor(
          weightKg: 90,
          heightCm: 180,
          ageYears: 40,
          sex: BiologicalSex.male,
        ),
        1830,
      );
    });

    test('sin especificar es el promedio de ambas fórmulas', () {
      final male = bmrMifflinStJeor(
        weightKg: 80,
        heightCm: 175,
        ageYears: 35,
        sex: BiologicalSex.male,
      );
      final female = bmrMifflinStJeor(
        weightKg: 80,
        heightCm: 175,
        ageYears: 35,
        sex: BiologicalSex.female,
      );
      final unspecified = bmrMifflinStJeor(
        weightKg: 80,
        heightCm: 175,
        ageYears: 35,
        sex: BiologicalSex.unspecified,
      );
      expect(unspecified, ((male + female) / 2).round());
    });

    test('los límites del rango son válidos', () {
      expect(
        () => bmrMifflinStJeor(
          weightKg: 25,
          heightCm: 90,
          ageYears: 13,
          sex: BiologicalSex.female,
        ),
        returnsNormally,
      );
      expect(
        () => bmrMifflinStJeor(
          weightKg: 400,
          heightCm: 250,
          ageYears: 100,
          sex: BiologicalSex.male,
        ),
        returnsNormally,
      );
    });

    test('fuera de rango lanza CalculationError con el campo ofensor', () {
      expect(
        () => bmrMifflinStJeor(
          weightKg: 24,
          heightCm: 165,
          ageYears: 30,
          sex: BiologicalSex.female,
        ),
        throwsA(
          isA<CalculationError>().having((e) => e.field, 'field', 'weightKg'),
        ),
      );
      expect(
        () => bmrMifflinStJeor(
          weightKg: 70,
          heightCm: 89,
          ageYears: 30,
          sex: BiologicalSex.female,
        ),
        throwsA(
          isA<CalculationError>().having((e) => e.field, 'field', 'heightCm'),
        ),
      );
      expect(
        () => bmrMifflinStJeor(
          weightKg: 70,
          heightCm: 165,
          ageYears: 12,
          sex: BiologicalSex.female,
        ),
        throwsA(
          isA<CalculationError>().having((e) => e.field, 'field', 'ageYears'),
        ),
      );
    });
  });

  group('§2 · TDEE', () {
    test('T-03 · 1420 × light (1,375) → 1953', () {
      expect(tdee(bmr: 1420, activityLevel: ActivityLevel.light), 1953);
    });

    test('cada nivel usa su factor documentado', () {
      expect(ActivityLevel.sedentary.factor, 1.200);
      expect(ActivityLevel.light.factor, 1.375);
      expect(ActivityLevel.moderate.factor, 1.550);
      expect(ActivityLevel.high.factor, 1.725);
      expect(ActivityLevel.veryHigh.factor, 1.900);
    });
  });

  group('§3 · Objetivo calórico', () {
    test('T-04 · TDEE 1953, bajar 0,5 kg/sem → 1403', () {
      final r = calorieTarget(
        tdee: 1953,
        goalType: GoalType.lose,
        rateKgPerWeek: 0.5,
        sex: BiologicalSex.female,
      );
      expect(r.target, 1403);
      expect(r.clamped, isFalse);
    });

    test('T-05 · clamp RN-12: TDEE 1400, bajar 1 kg/sem, F → 1200 + flag', () {
      final r = calorieTarget(
        tdee: 1400,
        goalType: GoalType.lose,
        rateKgPerWeek: 1.0,
        sex: BiologicalSex.female,
      );
      expect(r.target, 1200);
      expect(r.clamped, isTrue);
      expect(r.uncappedTarget, 300);
    });

    test('el superávit se aplica al 50 % (D-04): 2600 + 0,25 kg/sem → 2738', () {
      final r = calorieTarget(
        tdee: 2600,
        goalType: GoalType.gain,
        rateKgPerWeek: 0.25,
        sex: BiologicalSex.male,
      );
      expect(r.target, 2738);
    });

    test('mantener no ajusta', () {
      final r = calorieTarget(
        tdee: 2100,
        goalType: GoalType.maintain,
        rateKgPerWeek: 0,
        sex: BiologicalSex.unspecified,
      );
      expect(r.target, 2100);
    });

    test('el ritmo tiene tope de 1 kg/semana (RN-13)', () {
      expect(
        () => calorieTarget(
          tdee: 2600,
          goalType: GoalType.lose,
          rateKgPerWeek: 1.5,
          sex: BiologicalSex.male,
        ),
        throwsA(isA<CalculationError>()),
      );
    });

    test('los ajustes diarios de la tabla §3', () {
      expect(CalorieTargetRules.dailyAdjustment(0.25).round(), 275);
      expect(CalorieTargetRules.dailyAdjustment(0.50).round(), 550);
      expect(CalorieTargetRules.dailyAdjustment(0.75).round(), 825);
      expect(CalorieTargetRules.dailyAdjustment(1.00).round(), 1100);
    });
  });

  group('§8 · MET ★', () {
    test('T-06 · MET 3,5 · 100 kg · 30 min → 184 (ejemplo canónico)', () {
      expect(
        calculateCaloriesFromMet(met: 3.5, weightKg: 100, durationMinutes: 30),
        184,
      );
    });

    test('T-07 · MET 9,8 · 60 kg · 45 min → 463', () {
      expect(
        calculateCaloriesFromMet(met: 9.8, weightKg: 60, durationMinutes: 45),
        463,
      );
    });

    test('duración mínima de 1 minuto', () {
      expect(
        calculateCaloriesFromMet(met: 3.5, weightKg: 100, durationMinutes: 1),
        6,
      );
    });

    test('MET fuera de rango lanza CalculationError', () {
      expect(
        () => calculateCaloriesFromMet(
          met: 0.5,
          weightKg: 100,
          durationMinutes: 30,
        ),
        throwsA(isA<CalculationError>().having((e) => e.field, 'field', 'met')),
      );
      expect(
        () => calculateCaloriesFromMet(
          met: 24,
          weightKg: 100,
          durationMinutes: 30,
        ),
        throwsA(isA<CalculationError>()),
      );
    });

    test('peso inválido no calcula', () {
      expect(
        () =>
            calculateCaloriesFromMet(met: 3.5, weightKg: 0, durationMinutes: 30),
        throwsA(
          isA<CalculationError>().having((e) => e.field, 'field', 'weightKg'),
        ),
      );
    });

    test('la duración admite hasta 1440 min y no más (D-22)', () {
      expect(
        () => calculateCaloriesFromMet(
          met: 3.5,
          weightKg: 80,
          durationMinutes: 1440,
        ),
        returnsNormally,
      );
      expect(
        () => calculateCaloriesFromMet(
          met: 3.5,
          weightKg: 80,
          durationMinutes: 1441,
        ),
        throwsA(isA<CalculationError>()),
      );
    });
  });

  group('§10 · Gasto informado por un proveedor (RN-05)', () {
    test('nulo o ≤ 0 es inválido', () {
      expect(
        providerCaloriesAreValid(activeCalories: null, durationMinutes: 30),
        isFalse,
      );
      expect(
        providerCaloriesAreValid(activeCalories: 0, durationMinutes: 30),
        isFalse,
      );
    });

    test('más de 1500 kcal/hora es inválido', () {
      expect(
        providerCaloriesAreValid(activeCalories: 800, durationMinutes: 30),
        isFalse,
      );
      expect(
        providerCaloriesAreValid(activeCalories: 700, durationMinutes: 30),
        isTrue,
      );
    });
  });

  group('§13 · Crédito de ejercicio y balance ★', () {
    test('T-08 · 240 kcal al 50 % → 120', () {
      expect(
        calculateAppliedExerciseCalories(
          estimatedCalories: 240,
          creditPercentage: 50,
        ),
        120,
      );
    });

    test('T-09 · 240 kcal al 0 % → 0 (default D-02)', () {
      expect(
        calculateAppliedExerciseCalories(
          estimatedCalories: 240,
          creditPercentage: 0,
        ),
        0,
      );
      expect(ExerciseCreditOptions.defaultPercentage, 0);
    });

    test('desactivado devuelve 0 aunque el porcentaje sea alto', () {
      expect(
        calculateAppliedExerciseCalories(
          estimatedCalories: 240,
          creditPercentage: 100,
          creditEnabled: false,
        ),
        0,
      );
    });

    test('T-10 · objetivo ajustado 2100 + 120 → 2220', () {
      expect(
        calculateAdjustedCalorieTarget(
          baseTarget: 2100,
          appliedExerciseCalories: 120,
        ),
        2220,
      );
    });

    test('T-11 · restantes 2220 − 1640 → 580', () {
      expect(
        calculateRemainingCalories(adjustedTarget: 2220, consumedKcal: 1640),
        580,
      );
    });

    test('T-12 · netas 1640 − 120 → 1520', () {
      expect(
        calculateNetCalories(consumedKcal: 1640, appliedExerciseCalories: 120),
        1520,
      );
    });

    test('el ejemplo del brief completo, con crédito 50 % y 100 %', () {
      final at50 = computeDailyBalance(
        baseTarget: 2100,
        consumedKcal: 1640,
        exerciseEstimatedKcal: 240,
        creditPercentage: 50,
        creditEnabled: true,
      );
      expect(at50.exerciseAppliedKcal, 120);
      expect(at50.adjustedTarget, 2220);
      expect(at50.remainingKcal, 580);
      expect(at50.netKcal, 1520);
      expect(at50.showsAdjustmentRow, isTrue);

      final at100 = computeDailyBalance(
        baseTarget: 2100,
        consumedKcal: 1640,
        exerciseEstimatedKcal: 240,
        creditPercentage: 100,
        creditEnabled: true,
      );
      expect(at100.adjustedTarget, 2340);
      expect(at100.remainingKcal, 700);
    });

    test('con crédito 0 % la fila de ajuste no se muestra (D-02)', () {
      final b = computeDailyBalance(
        baseTarget: 2100,
        consumedKcal: 1640,
        exerciseEstimatedKcal: 240,
        creditPercentage: 0,
        creditEnabled: true,
      );
      expect(b.exerciseAppliedKcal, 0);
      expect(b.adjustedTarget, 2100);
      expect(b.showsAdjustmentRow, isFalse);
    });

    test('las restantes pueden ser negativas: "Te pasaste por N kcal"', () {
      final b = computeDailyBalance(
        baseTarget: 2000,
        consumedKcal: 2120,
        exerciseEstimatedKcal: 0,
        creditPercentage: 0,
        creditEnabled: true,
      );
      expect(b.isOverBudget, isTrue);
      expect(b.overBudgetKcal, 120);
    });
  });

  group('§4 · Calorías por macros', () {
    test('T-13 · 46,5 P · 0 C · 5,4 G → 235', () {
      expect(kcalFromMacros(proteinG: 46.5, carbsG: 0, fatG: 5.4), 235);
    });

    test('fibra y alcohol suman cuando están presentes', () {
      expect(
        kcalFromMacros(
          proteinG: 0,
          carbsG: 0,
          fatG: 0,
          fiberG: 10,
          alcoholG: 10,
        ),
        90,
      );
    });

    test('§5 · la inconsistencia necesita superar los dos umbrales', () {
      expect(
        macrosAreInconsistent(
          declaredKcal: 100,
          proteinG: 0,
          carbsG: 0,
          fatG: 0,
        ),
        isTrue,
      );
      expect(
        macrosAreInconsistent(
          declaredKcal: 235,
          proteinG: 46.5,
          carbsG: 0,
          fatG: 5.4,
        ),
        isFalse,
      );
      // Delta de 25 kcal: supera el 20 % pero no los 30 kcal absolutos.
      expect(
        macrosAreInconsistent(
          declaredKcal: 100,
          proteinG: 0,
          carbsG: 0,
          fatG: 13.9,
        ),
        isFalse,
      );
    });
  });

  group('§14 · IMC', () {
    test('T-14 · 70 kg · 165 cm → 25,7', () {
      expect(bmi(weightKg: 70, heightCm: 165), 25.7);
    });
  });

  group('§11 · Estimación por ritmo', () {
    test('T-15 · 5000 m en 30 min corriendo (10 km/h)', () {
      final met = estimateMetFromPace(
        distanceMeters: 5000,
        durationMinutes: 30,
        typeSlug: 'running',
      );
      // 10 km/h cae en el tramo [9,7 – 11,3), anclado en 9,7 km/h (6 mph) → 9,8.
      expect(met, 9.8);
    });

    test('la tabla de caminata, tramo por tramo', () {
      double? walk(int meters, int minutes) => estimateMetFromPace(
        distanceMeters: meters,
        durationMinutes: minutes,
        typeSlug: 'walking',
      );
      expect(walk(1500, 30), 2.8); // 3 km/h
      expect(walk(2500, 30), 3.5); // 5 km/h
      expect(walk(3000, 30), 4.3); // 6 km/h
      expect(walk(3500, 30), 5.0); // 7 km/h
    });

    test('la tabla de carrera, tramo por tramo', () {
      double? run(int meters, int minutes) => estimateMetFromPace(
        distanceMeters: meters,
        durationMinutes: minutes,
        typeSlug: 'running',
      );
      expect(run(3500, 30), 6.0); // 7 km/h
      expect(run(4500, 30), 8.3); // 9 km/h
      expect(run(5000, 30), 9.8); // 10 km/h
      expect(run(6000, 30), 11.0); // 12 km/h
      expect(run(7000, 30), 12.8); // 14 km/h
    });

    test('los bordes de cada tramo de carrera pertenecen al tramo que abren', () {
      double? runAt(double kmh) => estimateMetFromPace(
        distanceMeters: (kmh * 1000).round(),
        durationMinutes: 60,
        typeSlug: 'running',
      );
      expect(runAt(8.0), 8.3); // 5 mph
      expect(runAt(9.7), 9.8); // 6 mph
      expect(runAt(11.3), 11.0); // 7 mph
      expect(runAt(12.9), 12.8);
    });

    test('una velocidad > 45 km/h se descarta por incoherente', () {
      expect(
        estimateMetFromPace(
          distanceMeters: 50000,
          durationMinutes: 30,
          typeSlug: 'running',
        ),
        isNull,
      );
    });
  });

  group('§12 · Detección de duplicados ★', () {
    final start = DateTime(2026, 7, 27, 8);

    test('T-16 · mismo tipo, solape 100 %, kcal 176 vs 184 → ≥ 0,85', () {
      final a = DuplicateInput(
        activityTypeId: 'walking',
        startedAt: start,
        durationMinutes: 30,
        estimatedCalories: 184,
      );
      final b = DuplicateInput(
        activityTypeId: 'walking',
        startedAt: start,
        durationMinutes: 30,
        estimatedCalories: 176,
      );
      final score = duplicateScore(a, b);
      expect(score.score, greaterThanOrEqualTo(0.85));
      expect(score.isProbableDuplicate, isTrue);
    });

    test('T-17 · distinto tipo, sin solape → < 0,60', () {
      final a = DuplicateInput(
        activityTypeId: 'walking',
        startedAt: start,
        durationMinutes: 30,
        estimatedCalories: 184,
      );
      final b = DuplicateInput(
        activityTypeId: 'cycling',
        startedAt: start.add(const Duration(hours: 2)),
        durationMinutes: 60,
        estimatedCalories: 500,
      );
      final score = duplicateScore(a, b);
      expect(score.score, lessThan(0.60));
      expect(score.isProbableDuplicate, isFalse);
      expect(score.isSuspicious, isFalse);
    });

    test('mismo external_source + external_id es duplicado exacto', () {
      final a = DuplicateInput(
        activityTypeId: 'walking',
        startedAt: start,
        durationMinutes: 30,
        estimatedCalories: 184,
        externalSource: 'health_connect',
        externalId: 'abc',
      );
      final b = DuplicateInput(
        activityTypeId: 'running',
        startedAt: start.add(const Duration(hours: 3)),
        durationMinutes: 60,
        estimatedCalories: 500,
        externalSource: 'health_connect',
        externalId: 'abc',
      );
      expect(duplicateScore(a, b).score, 1.0);
    });

    test('más de 4 h de diferencia no se comparan', () {
      final a = DuplicateInput(
        activityTypeId: 'walking',
        startedAt: start,
        durationMinutes: 30,
        estimatedCalories: 184,
      );
      final b = DuplicateInput(
        activityTypeId: 'walking',
        startedAt: start.add(const Duration(hours: 5)),
        durationMinutes: 30,
        estimatedCalories: 184,
      );
      expect(duplicateScore(a, b).score, 0);
    });
  });

  group('§15 · Media móvil y tendencia', () {
    test('T-18 · 7 puntos, ventana 7 → la media exacta', () {
      final base = DateTime(2026, 7, 1);
      final points = <SeriesPoint>[
        for (var i = 0; i < 7; i++)
          SeriesPoint(base.add(Duration(days: i)), 70 + i.toDouble()),
      ];
      final avg = movingAverage(points, 7);
      expect(avg.last.value, closeTo(73, 0.0001));
      // El primer punto no genera media (mínimo 2 valores en la ventana).
      expect(avg.length, 6);
      expect(avg.first.value, closeTo(70.5, 0.0001));
    });

    test('la tendencia necesita al menos 3 puntos', () {
      final base = DateTime(2026, 7, 1);
      expect(
        weightTrendKgPerWeek(<SeriesPoint>[
          SeriesPoint(base, 80),
          SeriesPoint(base.add(const Duration(days: 1)), 79.8),
        ]),
        isNull,
      );
    });

    test('una bajada constante da una pendiente semanal negativa', () {
      final base = DateTime(2026, 7, 1);
      final points = <SeriesPoint>[
        for (var i = 0; i < 14; i++)
          SeriesPoint(base.add(Duration(days: i)), 80 - i * 0.1),
      ];
      final trend = weightTrendKgPerWeek(points);
      expect(trend, isNotNull);
      expect(trend!, lessThan(0));
      expect(trend, closeTo(-0.7, 0.15));
    });
  });

  group('§16 · Adherencia', () {
    test('T-19 · 10 días, 7 dentro de ±10 % → 70', () {
      final days = <AdherenceDay>[
        for (var i = 0; i < 7; i++)
          const AdherenceDay(consumed: 2000, target: 2000),
        for (var i = 0; i < 3; i++)
          const AdherenceDay(consumed: 2600, target: 2000),
      ];
      expect(adherencePct(days), 70);
    });

    test('con menos de 3 días con registro no se muestra el porcentaje', () {
      expect(
        adherencePct(const <AdherenceDay>[
          AdherenceDay(consumed: 2000, target: 2000),
          AdherenceDay(consumed: 2000, target: 2000),
        ]),
        isNull,
      );
    });

    test('los días sin registro no cuentan ni a favor ni en contra (RN-14)', () {
      final days = <AdherenceDay>[
        const AdherenceDay(consumed: 2000, target: 2000),
        const AdherenceDay(consumed: 2000, target: 2000),
        const AdherenceDay(consumed: 2000, target: 2000),
        const AdherenceDay(consumed: 0, target: 2000),
        const AdherenceDay(consumed: 0, target: 2000),
      ];
      expect(adherencePct(days), 100);
    });
  });

  group('§19 · Objetivos de macros', () {
    test('T-20 · 1403 kcal, 70 kg, bajar → P 140 · G 39 · C 123', () {
      final m = macroTargets(
        targetKcal: 1403,
        weightKg: 70,
        goalType: GoalType.lose,
      );
      expect(m.proteinG, 140);
      expect(m.fatG, 39);
      expect(m.carbsG, 123);
    });

    test('mantener usa 1,6 g/kg de proteína', () {
      final m = macroTargets(
        targetKcal: 2100,
        weightKg: 70,
        goalType: GoalType.maintain,
      );
      expect(m.proteinG, 112);
    });

    test('nunca devuelve un macro negativo', () {
      final m = macroTargets(
        targetKcal: 900,
        weightKg: 120,
        goalType: GoalType.lose,
      );
      expect(m.proteinG, greaterThan(0));
      expect(m.carbsG, greaterThanOrEqualTo(0));
      expect(m.fatG, greaterThanOrEqualTo(0));
    });
  });

  group('§18 · Progreso de un objetivo de actividad', () {
    test('el progreso se topea en 100 %', () {
      expect(activityGoalProgressPct(currentValue: 200, targetValue: 150), 100);
      expect(activityGoalProgressPct(currentValue: 12, targetValue: 150), 8);
    });
  });

  group('Transversales · redondeo', () {
    test('round_half_up redondea el medio hacia arriba', () {
      expect(roundHalfUp(183.75), 184);
      expect(roundHalfUp(0.5), 1);
      expect(roundHalfUp(1.5), 2);
      expect(roundHalfUp(2.5), 3);
      expect(roundHalfUp(-0.5), 0);
      expect(roundHalfUp(-1.5), -1);
    });

    test('roundTo respeta los decimales pedidos', () {
      expect(roundTo(25.7123, 1), 25.7);
      expect(roundTo(3.456, 2), 3.46);
    });
  });
}
