import 'package:ceres/core/utils/dates.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/domain/calculations/calorie_target.dart';
import 'package:ceres/domain/calculations/goal_presets.dart';
import 'package:ceres/domain/calculations/macros.dart';
import 'package:ceres/domain/enums/enums.dart';
import 'package:ceres/domain/models/activity.dart';
import 'package:ceres/domain/models/user_profile.dart';
import 'package:ceres/domain/services/goal_planner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Perfil con lo justo para que Mifflin-St Jeor tenga con qué trabajar.
UserProfile _profileConDatos() => UserProfile.empty('u1').copyWith(
  biologicalSex: BiologicalSex.male,
  birthDate: DateTime(1990, 1, 1),
  heightCm: 178,
  activityLevel: ActivityLevel.moderate,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('presets', () {
    test('cada tipo de objetivo tiene el suyo y ninguno se repite', () {
      expect(GoalPreset.all, hasLength(GoalType.values.length));
      for (final type in GoalType.values) {
        expect(GoalPreset.of(type).goalType, type);
      }
    });

    test('ningún ritmo supera el tope de 1 kg por semana (RN-13)', () {
      for (final preset in GoalPreset.all) {
        expect(
          preset.rateKgPerWeek,
          lessThanOrEqualTo(CalorieTargetRules.maxRateKgPerWeek),
        );
      }
    });

    test('mantener no tiene ritmo', () {
      expect(GoalPreset.maintain.rateKgPerWeek, 0);
    });

    test('bajar y ganar músculo piden más proteína', () {
      expect(GoalPreset.lose.proteinGPerKg, 2.0);
      expect(GoalPreset.gainMuscle.proteinGPerKg, 2.0);
      expect(GoalPreset.maintain.proteinGPerKg, 1.6);
      expect(GoalPreset.gain.proteinGPerKg, 1.6);
    });

    test('los macros usan el mismo g/kg que el preset', () {
      for (final preset in GoalPreset.all) {
        final macros = macroTargets(
          targetKcal: 2400,
          weightKg: 80,
          goalType: preset.goalType,
        );
        expect(macros.proteinG, preset.proteinTargetG(80));
      }
    });
  });

  group('objetivo calórico por tipo', () {
    const tdeeValue = 2500;

    int targetOf(GoalType type) {
      final preset = GoalPreset.of(type);
      return calorieTarget(
        tdee: tdeeValue,
        goalType: type,
        rateKgPerWeek: preset.rateKgPerWeek,
        sex: BiologicalSex.male,
      ).target;
    }

    test('bajar resta el ajuste completo', () {
      expect(targetOf(GoalType.lose), tdeeValue - 550);
    });

    test('mantener deja el gasto tal cual', () {
      expect(targetOf(GoalType.maintain), tdeeValue);
    });

    test('subir de peso aplica medio superávit (D-04)', () {
      // 0,25 kg/semana ≈ 275 kcal, la mitad ≈ 138.
      expect(targetOf(GoalType.gain), tdeeValue + 138);
    });

    test('ganar músculo aplica el superávit entero', () {
      expect(targetOf(GoalType.gainMuscle), tdeeValue + 275);
    });

    test('ganar músculo queda por encima de subir de peso', () {
      expect(targetOf(GoalType.gainMuscle), greaterThan(targetOf(GoalType.gain)));
    });
  });

  group('GoalPace', () {
    test('el mismo ritmo pide el mismo esfuerzo a cuerpos distintos', () {
      // El punto entero del cambio. Medio kilo por semana son 550 kcal para
      // cualquiera: el 21 % del gasto de una persona de 2.600 y el 35 % del de
      // una de 1.550. La fracción es la misma para las dos, y los kilos por
      // semana pasan a ser lo que difiere.
      const fraccion = 0.20;
      for (final gasto in <int>[1550, 2600]) {
        final r = calorieTargetForPace(
          tdee: gasto,
          goalType: GoalType.lose,
          fractionOfTdee: fraccion,
          sex: BiologicalSex.male,
        );
        expect(
          (gasto - r.target.uncappedTarget) / gasto,
          closeTo(fraccion, 0.005),
          reason: 'gasto $gasto',
        );
      }

      // Y el ritmo semanal sale distinto, que es lo correcto: el cuerpo más
      // grande puede sostener más kilos con el mismo porcentaje.
      double ritmo(int gasto) => calorieTargetForPace(
        tdee: gasto,
        goalType: GoalType.lose,
        fractionOfTdee: fraccion,
        sex: BiologicalSex.male,
      ).rateKgPerWeek;
      expect(ritmo(2600), greaterThan(ritmo(1550)));
    });

    test('ningún ritmo supera el tope de 1 kg por semana (RN-13)', () {
      // Sobre un gasto muy grande, una fracción chica se pasa del kilo. El
      // tope sigue mandando, y el objetivo se calcula desde el ritmo topeado.
      final r = calorieTargetForPace(
        tdee: 6000,
        goalType: GoalType.lose,
        fractionOfTdee: 0.25,
        sex: BiologicalSex.male,
      );
      expect(r.rateKgPerWeek, CalorieTargetRules.maxRateKgPerWeek);
      expect(r.target.uncappedTarget, 6000 - 1100);
    });

    test('el ritmo guardado y el objetivo no pueden discrepar', () {
      // El ritmo se guarda con dos decimales, que es lo que acepta la columna.
      // Si el objetivo se calculara desde la fracción sin redondear, el número
      // mostrado y el guardado se separarían.
      for (final gasto in <int>[1400, 1953, 2417, 3050]) {
        for (final pace in GoalPace.values) {
          final r = calorieTargetForPace(
            tdee: gasto,
            goalType: GoalType.lose,
            fractionOfTdee: pace.fractionFor(GoalType.lose),
            sex: BiologicalSex.male,
          );
          expect(
            r.target.uncappedTarget,
            gasto - CalorieTargetRules.dailyAdjustment(r.rateKgPerWeek).round(),
            reason: '$gasto · ${pace.label}',
          );
          expect(
            (r.rateKgPerWeek * 100) % 1,
            closeTo(0, 1e-9),
            reason: 'dos decimales',
          );
        }
      }
    });

    test('bajar es más exigente que subir, y subir de peso más suave que ganar '
        'músculo (D-04)', () {
      for (final pace in GoalPace.values) {
        expect(
          pace.fractionFor(GoalType.lose),
          greaterThan(pace.fractionFor(GoalType.gainMuscle)),
        );
        // D-04, ahora dicho donde se lee: `gain` es la mitad de `gain_muscle`.
        expect(
          pace.fractionFor(GoalType.gain),
          closeTo(pace.fractionFor(GoalType.gainMuscle) / 2, 0.0001),
        );
      }
      expect(GoalPace.steady.fractionFor(GoalType.maintain), 0);
    });

    test('ninguna fracción pasa el techo del 30 %', () {
      for (final goalType in GoalType.values) {
        for (final pace in GoalPace.values) {
          expect(
            pace.fractionFor(goalType),
            lessThanOrEqualTo(CalorieTargetRules.maxFractionOfTdee),
            reason: '${goalType.label} · ${pace.label}',
          );
        }
      }
    });

    test('un ritmo viejo en kilos vuelve al ritmo que le corresponde', () {
      // Todo lo guardado antes de este cambio trae kilos por semana. Sin la
      // vuelta, esas pantallas abrirían sin nada marcado.
      const gasto = 2750; // 0,50 kg/sem ≈ 550 kcal ≈ 20 % de este gasto.
      expect(
        GoalPace.nearestForRate(
          rateKgPerWeek: 0.5,
          goalType: GoalType.lose,
          tdee: gasto,
        ),
        GoalPace.firm,
      );
      // Sin gasto no hay fracción que calcular: queda el de arranque.
      expect(
        GoalPace.nearestForRate(
          rateKgPerWeek: 0.5,
          goalType: GoalType.lose,
          tdee: 0,
        ),
        GoalPace.steady,
      );
    });

    test('un ritmo viejo desmedido se recorta al techo', () {
      // 1 kg/semana sobre un gasto de 1.550 es el 71 %. La pantalla de quien lo
      // tenga guardado tiene que abrir, no explotar.
      expect(
        fractionOfTdeeForRate(rateKgPerWeek: 1, tdee: 1550),
        CalorieTargetRules.maxFractionOfTdee,
      );
    });

    test('bajando y subiendo no dicen lo mismo', () {
      expect(
        GoalPace.fastest.detailFor(GoalType.lose),
        isNot(GoalPace.fastest.detailFor(GoalType.gainMuscle)),
      );
      expect(GoalPace.steady.detailFor(GoalType.maintain), isEmpty);
      expect(
        GoalPace.firm.shareLabelFor(GoalType.lose),
        '20 % menos que tu gasto',
      );
      expect(
        GoalPace.gentle.shareLabelFor(GoalType.gain),
        '2,5 % más que tu gasto',
      );
    });
  });

  group('GoalPlanner', () {
    test('con datos corporales el objetivo queda calculado', () {
      final goal = GoalPlanner.build(
        preset: GoalPreset.lose,
        profile: _profileConDatos(),
        weightKg: 82,
        current: null,
      );

      expect(goal.goalType, GoalType.lose);
      expect(goal.targetMethod, TargetMethod.calculated);
      expect(goal.bmrKcal, isNotNull);
      expect(goal.tdeeKcal, isNotNull);

      // El déficit de arranque es el 15 % de **su** gasto. Antes era medio kilo
      // por semana —550 kcal— para todo el mundo: el 21 % de un gasto de 2.600
      // y el 35 % de uno de 1.550.
      expect(
        (goal.tdeeKcal! - goal.baseCalorieTarget) / goal.tdeeKcal!,
        closeTo(0.15, 0.005),
      );
      // Los kilos por semana quedan guardados, pero como consecuencia.
      expect(goal.rateKgPerWeek, greaterThan(0));
      expect(
        goal.baseCalorieTarget,
        goal.tdeeKcal! -
            CalorieTargetRules.dailyAdjustment(goal.rateKgPerWeek).round(),
      );
      expect(goal.startsOn, today());
    });

    test('sin datos corporales conserva el número y lo marca manual (RN-03)', () {
      final planned = GoalPlanner.build(
        preset: GoalPreset.gainMuscle,
        profile: UserProfile.empty('u1'),
        weightKg: null,
        current: null,
      );

      expect(planned.targetMethod, TargetMethod.manual);
      expect(planned.bmrKcal, isNull);
      // El tipo y el ritmo sí se guardan: es lo que se pudo saber.
      expect(planned.goalType, GoalType.gainMuscle);
      expect(planned.rateKgPerWeek, 0.25);
    });

    test('el ritmo elegido pisa al del preset, y sale de su gasto', () {
      final goal = GoalPlanner.build(
        preset: GoalPreset.lose,
        profile: _profileConDatos(),
        weightKg: 82,
        current: null,
        pace: GoalPace.gentle,
      );

      // Sin esto, quien elige el ritmo suave en el alta terminaba con el
      // "Sostenido" de la tarjeta: un déficit el doble del que aceptó.
      final esperado = calorieTargetForPace(
        tdee: goal.tdeeKcal!,
        goalType: GoalType.lose,
        fractionOfTdee: GoalPace.gentle.fractionFor(GoalType.lose),
        sex: _profileConDatos().biologicalSex,
      );
      expect(goal.rateKgPerWeek, esperado.rateKgPerWeek);
      expect(goal.baseCalorieTarget, esperado.target.target);

      // Y el déficit es el 10 % del gasto, no un número fijo de kilos.
      expect(
        (goal.tdeeKcal! - goal.baseCalorieTarget) / goal.tdeeKcal!,
        closeTo(0.10, 0.005),
      );
    });

    test('mantener no acepta un ritmo', () {
      final goal = GoalPlanner.build(
        preset: GoalPreset.maintain,
        profile: _profileConDatos(),
        weightKg: 82,
        current: null,
        pace: GoalPace.fastest,
      );

      // Un objetivo que dice "mantener" y resta calorías es dos cosas
      // distintas a la vez.
      expect(goal.rateKgPerWeek, 0);
      expect(goal.baseCalorieTarget, goal.tdeeKcal);
    });

    test('el objetivo de la IA no se confunde con el calculado ni con el escrito', () {
      final goal = GoalPlanner.build(
        preset: GoalPreset.lose,
        profile: _profileConDatos(),
        weightKg: 82,
        current: null,
        manualTarget: 1850,
        manualMethod: TargetMethod.ai,
      );

      // De dónde viene un número es parte del número (RN-03): sin un método
      // propio, la única pista de por qué el objetivo no coincide con la
      // fórmula sería ninguna.
      expect(goal.baseCalorieTarget, 1850);
      expect(goal.targetMethod, TargetMethod.ai);
    });

    test('el número escrito a mano gana, y se marca como tal', () {
      final goal = GoalPlanner.build(
        preset: GoalPreset.lose,
        profile: _profileConDatos(),
        weightKg: 82,
        current: null,
        manualTarget: 1900,
      );

      expect(goal.baseCalorieTarget, 1900);
      expect(goal.targetMethod, TargetMethod.manual);
      // El BMR y el TDEE se guardan igual: son hechos del cuerpo, y sirven
      // para explicar después cuánto se apartó el número elegido.
      expect(goal.bmrKcal, isNotNull);
      expect(goal.tdeeKcal, isNotNull);
    });

    test('el objetivo nunca baja del mínimo saludable (RN-12)', () {
      final goal = GoalPlanner.build(
        preset: GoalPreset.lose,
        profile: _profileConDatos().copyWith(
          biologicalSex: BiologicalSex.female,
          activityLevel: ActivityLevel.sedentary,
          heightCm: 150,
        ),
        weightKg: 45,
        current: null,
      );

      expect(
        goal.baseCalorieTarget,
        greaterThanOrEqualTo(
          CalorieTargetRules.minimumFor(BiologicalSex.female),
        ),
      );
    });

    test('los objetivos de actividad salen del preset y no se duplican', () {
      final goals = GoalPlanner.activityGoals(
        GoalPreset.gainMuscle,
        existing: const <ActivityGoal>[],
      );

      expect(goals, hasLength(2));
      expect(
        goals.firstWhere((g) => g.goalType == ActivityGoalType.activeMinutes)
            .targetValue,
        150,
      );
      expect(
        goals
            .firstWhere((g) => g.goalType == ActivityGoalType.strengthSessions)
            .targetValue,
        4,
      );
      expect(goals.every((g) => g.period == GoalPeriod.week), isTrue);
    });

    test('reusa el id del objetivo de actividad que ya existía', () {
      final previos = GoalPlanner.activityGoals(
        GoalPreset.maintain,
        existing: const <ActivityGoal>[],
      );
      final nuevos = GoalPlanner.activityGoals(
        GoalPreset.lose,
        existing: previos,
      );

      expect(
        nuevos.map((g) => g.id).toSet(),
        previos.map((g) => g.id).toSet(),
      );
      expect(
        nuevos.firstWhere((g) => g.goalType == ActivityGoalType.activeMinutes)
            .targetValue,
        200,
      );
    });
  });

  group('guardar el objetivo', () {
    late LocalRepository repo;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = await LocalStore.open();
      repo = LocalRepository(store, onChanged: () {});
      await repo.signIn('yo@ceres.test');
    });

    test('cambiar de objetivo cierra el anterior y deja uno solo vigente',
        () async {
      await repo.saveGoal(
        GoalPlanner.build(
          preset: GoalPreset.lose,
          profile: _profileConDatos(),
          weightKg: 82,
          current: repo.currentGoalOrNull,
        ),
      );
      await repo.saveGoal(
        GoalPlanner.build(
          preset: GoalPreset.gainMuscle,
          profile: _profileConDatos(),
          weightKg: 82,
          current: repo.currentGoalOrNull,
        ),
      );

      expect(repo.currentGoalOrNull?.goalType, GoalType.gainMuscle);
      expect(repo.goalFor(today()).goalType, GoalType.gainMuscle);
    });
  });
}
