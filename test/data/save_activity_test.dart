// Editar una actividad no puede perder lo que el formulario no muestra.
//
// El bug: `saveActivity` armaba un `Activity` nuevo desde el borrador. Al
// editar se perdían `externalSource`, `externalId`, `sourceUpdatedAt`, la foto
// y el dispositivo; las kcal que había medido el proveedor pasaban a ser las
// del MET; y a un día cerrado se le volvía a aplicar el porcentaje de ajuste de
// hoy, que es justo lo que D-05 prohíbe.

import 'package:ceres/core/config/feature_flags.dart';
import 'package:ceres/core/utils/dates.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/domain/enums/enums.dart';
import 'package:ceres/domain/models/activity.dart';
import 'package:ceres/domain/repositories/repositories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStore store;
  late LocalRepository repo;
  late String walkId;

  setUp(() async {
    FeatureFlags.seededDemoDataOverride = false;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = await LocalStore.open();
    repo = LocalRepository(store, onChanged: () {});
    await repo.logWeight(weightKg: 70, date: today());
    walkId = repo.typeBySlug('walking')!.id;
  });

  tearDown(() => FeatureFlags.seededDemoDataOverride = null);

  Activity existente({
    required DateTime day,
    EstimationMethod method = EstimationMethod.provider,
    int kcal = 321,
    int pct = 50,
    int? applied,
  }) {
    final startedAt = DateTime(day.year, day.month, day.day, 8);
    return Activity(
      id: 'a-1',
      activityTypeId: walkId,
      startedAt: startedAt,
      endedAt: startedAt.add(const Duration(minutes: 30)),
      localDate: dateOnly(day),
      durationMinutes: 30,
      intensity: Intensity.moderate,
      distanceMeters: 3000,
      estimatedCalories: kcal,
      appliedCalories: applied ?? (kcal * pct / 100).round(),
      exerciseCreditPercentage: pct,
      estimationMethod: method,
      sourceType: ActivitySourceType.imported,
      externalSource: 'apollo',
      externalId: 'ext-1',
      sourceUpdatedAt: DateTime(2026, 11, 1, 9),
      photoPath: 'uid/foto.jpg',
      deviceName: 'Amazfit Bip',
      createdAt: DateTime(2026, 11, 1, 9),
      updatedAt: DateTime(2026, 11, 1, 9),
    );
  }

  ActivityDraft borrador(
    Activity a, {
    int? duration,
    String? notes,
    int? overrideCalories,
  }) => ActivityDraft(
    id: a.id,
    activityTypeId: a.activityTypeId,
    startedAt: a.startedAt,
    durationMinutes: duration ?? a.durationMinutes,
    intensity: a.intensity,
    distanceMeters: a.distanceMeters,
    notes: notes,
    overrideCalories: overrideCalories,
  );

  test(
    'editar una nota conserva origen, foto, dispositivo y kcal medidas',
    () async {
      final a = existente(day: today());
      store.activities = <Activity>[...store.activities, a];

      final saved = await repo.saveActivity(borrador(a, notes: 'con el perro'));

      expect(saved.notes, 'con el perro');
      expect(saved.externalSource, 'apollo');
      expect(saved.externalId, 'ext-1');
      expect(saved.sourceUpdatedAt, a.sourceUpdatedAt);
      expect(saved.photoPath, 'uid/foto.jpg');
      expect(saved.deviceName, 'Amazfit Bip');
      expect(saved.sourceType, ActivitySourceType.imported);
      expect(saved.createdAt, a.createdAt);
      // Las del proveedor, no las del MET.
      expect(saved.estimatedCalories, 321);
      expect(saved.estimationMethod, EstimationMethod.provider);
    },
  );

  test('cambiar la duración recalcula por MET y lo dice', () async {
    final a = existente(day: today());
    store.activities = <Activity>[...store.activities, a];

    final saved = await repo.saveActivity(borrador(a, duration: 60));

    expect(saved.estimationMethod, EstimationMethod.metRecalculated);
    expect(saved.estimatedCalories, isNot(321));
    expect(saved.externalId, 'ext-1');
  });

  test(
    'corregir a mano guarda como original lo que había medido el proveedor',
    () async {
      final a = existente(day: today());
      store.activities = <Activity>[...store.activities, a];

      final saved = await repo.saveActivity(borrador(a, overrideCalories: 250));

      expect(saved.estimatedCalories, 250);
      expect(saved.estimationMethod, EstimationMethod.userOverride);
      expect(saved.originalCalories, 321);
    },
  );

  test('un día cerrado conserva su porcentaje congelado (D-05)', () async {
    final ayer = today().subtract(const Duration(days: 1));
    final a = existente(day: ayer);
    store.activities = <Activity>[...store.activities, a];
    await repo.setExerciseCredit(percentage: 100, enabled: true);

    final saved = await repo.saveActivity(borrador(a, notes: 'corrijo'));

    expect(saved.exerciseCreditPercentage, 50);
    expect(saved.appliedCalories, (321 * 0.5).round());
  });

  test('un día cerrado "sin ajuste" sigue sin ajuste', () async {
    final ayer = today().subtract(const Duration(days: 1));
    final a = existente(day: ayer, pct: 0, applied: 0);
    store.activities = <Activity>[...store.activities, a];
    await repo.setExerciseCredit(percentage: 100, enabled: true);

    final saved = await repo.saveActivity(borrador(a, notes: 'corrijo'));

    expect(saved.appliedCalories, 0);
  });

  test('hoy sí toma el ajuste vigente', () async {
    final a = existente(day: today());
    store.activities = <Activity>[...store.activities, a];
    await repo.setExerciseCredit(percentage: 100, enabled: true);

    final saved = await repo.saveActivity(borrador(a, notes: 'corrijo'));

    expect(saved.exerciseCreditPercentage, 100);
    expect(saved.appliedCalories, 321);
  });
}
