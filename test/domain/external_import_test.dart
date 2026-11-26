// Importar el historial de otra app a partir del bloque que devuelve una IA.
//
// El parser se prueba con lo que las IA hacen de verdad —bloque de código,
// partes, comas de más, la plantilla sin completar— y el importador contra el
// repositorio local, sin servidor.

import 'package:ceres/core/utils/dates.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/domain/enums/enums.dart';
import 'package:ceres/domain/models/user_profile.dart';
import 'package:ceres/domain/services/external_import.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final DateTime _now = DateTime(2026, 11, 26, 10);

const String _block = '''
Acá tenés tu historial:

```
===GYMSPOT===
{
 "v": 1,
 "fuente": "ChatGPT",
 "perfil": {"nombre": "Julián", "sexo": "m", "edad": 29, "altura_cm": 178,
   "objetivo": "volumen", "lesiones": ["hombro derecho"]},
 "plan": {"kcal": 2800, "proteina_g": 160, "carbos_g": 340, "grasas_g": 85},
 "pesajes": [
  {"fecha": "2026-10-01", "kg": 74.5, "aprox": false},
  {"fecha": "2026-11-01", "kg": "75,8", "aprox": true},
  {"fecha": "2026-12-15", "kg": 77, "aprox": false},
  {"fecha": "AAAA-MM-DD", "kg": null, "aprox": false},
 ],
 "medidas": [{"fecha": "2026-11-01", "grasa_pct": 16.5, "masa_muscular_kg": null,
   "agua_kg": 40, "cintura_cm": 82, "pecho_cm": null, "brazo_cm": 36,
   "muslo_cm": null}],
 "entrenos": [{"fecha": "2026-11-20", "titulo": "Pecho y tríceps",
   "ejercicios": [
     {"nombre": "Press banca plano", "series": [
       {"reps": 8, "kg": 60}, {"reps": 8, "kg": 60}, {"reps": 8, "kg": 60},
       {"reps": 8, "kg": 60}, {"reps": 6, "kg": 70}]},
     {"nombre": "Fondos", "series": [{"reps": 12, "kg": null}, {"reps": 10, "kg": null}]}
   ],
   "cardio": [{"nombre": "Cinta", "min": 15}], "notas": null, "aprox": false}],
 "records": [{"ejercicio": "Sentadilla", "kg": 120, "reps": 1, "fecha": "2026-10-10"}],
 "rutina": {"nombre": "PPL", "dias": [{"nombre": "Empuje", "ejercicios": []}]},
 "dias_nutricion": [{"fecha": "2026-11-20", "kcal": 2750, "proteina_g": 150,
   "carbos_g": 330, "grasas_g": 80}],
 "comidas": [{"nombre": "Avena con banana", "porcion": "1 bowl", "kcal": 420,
   "proteina_g": 15, "carbos_g": 70, "grasas_g": 9}],
 "suplementos": [{"nombre": "Creatina", "marca": null, "dosis": "5 g"}],
 "deportes": [
   {"fecha": "2026-11-22", "deporte": "Fútbol", "min": 60, "intensidad": "alta"},
   {"fecha": "2026-11-23", "deporte": "Pádel", "min": null, "intensidad": "moderada"}
 ],
 "objetivos": [{"tipo": "peso", "titulo": "Llegar a 80 kg", "ejercicio": null,
   "valor": 80, "fecha_limite": null}]
}
===FIN===
```
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('lectura del bloque', () {
    test('lee todo lo que Ceres guarda y cuenta lo que no', () {
      final data = ExternalImport.parse(_block, now: _now);

      expect(data.source, 'ChatGPT');
      expect(data.profile.name, 'Julián');
      expect(data.profile.sex, BiologicalSex.male);
      expect(data.profile.heightCm, 178);
      expect(data.plan!.kcal, 2800);
      expect(data.plan!.hasMacros, isTrue);
      expect(data.targetWeightKg, 80);

      // La fecha futura se descarta; la plantilla vacía no cuenta como
      // descartada; la coma decimal se lee.
      expect(data.weights.map((w) => w.kg), <double>[74.5, 75.8]);
      expect(data.discarded, 1); // el peso futuro

      // `agua_kg` no tiene métrica en Ceres.
      expect(
        data.measurements.map((m) => m.metric),
        containsAll(<MeasurementMetric>[
          MeasurementMetric.bodyFatPct,
          MeasurementMetric.waist,
          MeasurementMetric.arm,
        ]),
      );
      expect(data.measurements, hasLength(3));

      expect(data.workouts, hasLength(2));
      final gym = data.workouts.firstWhere(
        (a) => a.slug == 'strength_training',
      );
      expect(gym.customName, 'Pecho y tríceps');
      expect(gym.minutes, 21); // 7 series × 3 min
      expect(
        gym.notes,
        contains('Press banca plano: 4×8 · 60 kg, 1×6 · 70 kg'),
      );
      expect(gym.notes, contains('Fondos: 1×12, 1×10'));
      expect(data.workouts.last.slug, 'walking');

      expect(data.sports, hasLength(2));
      final futbol = data.sports.first;
      expect(futbol.slug, 'sports');
      expect(futbol.customName, 'Fútbol');
      expect(futbol.intensity, Intensity.vigorous);
      expect(futbol.notes, isNull);

      // El pádel vino sin minutos: se estima lo habitual y la nota lo dice.
      final padel = data.sports.last;
      expect(padel.customName, 'Pádel');
      expect(padel.minutes, 60);
      expect(padel.notes, contains('Duración estimada'));

      expect(data.nutritionDays.single.kcal, 2750);
      expect(data.foods.single.servingSize, 1);
      expect(data.foods.single.servingUnit, 'bowl');

      expect(data.records, 1);
      expect(data.routineDays, 1);
      expect(data.supplements, 1);
    });

    test('lo que falta se estima en vez de descartarse', () {
      const text = '''
===CERES===
{"v": 1,
 "perfil": {"edad": 30},
 "plan": {"kcal": null, "proteina_g": 150, "carbos_g": 250, "grasas_g": 70},
 "dias_nutricion": [
   {"fecha": "2026-11-10", "kcal": 2000, "proteina_g": 120, "carbos_g": null, "grasas_g": null},
   {"fecha": "2026-11-11", "kcal": null, "proteina_g": 100, "carbos_g": 200, "grasas_g": 50},
   {"fecha": "2026-11-12", "kcal": null, "proteina_g": 100, "carbos_g": null, "grasas_g": null}
 ],
 "comidas": [{"nombre": "Tostado", "porcion": null, "kcal": 400,
   "proteina_g": null, "carbos_g": null, "grasas_g": null}],
 "entrenos": [{"fecha": "2026-11-20", "titulo": "Piernas", "ejercicios": [],
   "cardio": [{"nombre": "Bici", "min": null}]}],
 "objetivos": [{"tipo": "peso", "titulo": "Llegar a 72,5 kg", "valor": null}]
}
===FIN===''';
      final data = ExternalImport.parse(text, now: _now);

      // Edad 30 → nacida hace treinta años y medio.
      expect(data.profile.birthDate, DateTime(1996, 5, 28));

      // Plan sin calorías: salen de los macros (150·4 + 250·4 + 70·9).
      expect(data.plan!.kcal, 2230);

      // Proteína dada: lo que queda (1520 kcal) se reparte 50/30 entre
      // carbohidratos y grasas.
      final day = data.nutritionDays.first;
      expect(day.kcal, 2000);
      expect(day.proteinG, 120);
      expect(day.carbsG, closeTo(1520 * 0.625 / 4, 0.1));
      expect(day.fatG, closeTo(1520 * 0.375 / 9, 0.1));
      expect(day.estimated, isTrue);

      // Sin calorías pero con los tres macros: la cuenta es exacta.
      expect(data.nutritionDays[1].kcal, 1650);

      // Sin calorías y con macros incompletos no hay de dónde sacarlas.
      expect(data.nutritionDays, hasLength(2));
      expect(data.discarded, 1);

      // Un alimento con calorías y nada más: 20/50/30.
      final food = data.foods.single;
      expect(food.proteinG, 20);
      expect(food.carbsG, 50);
      expect(food.fatG, closeTo(13.3, 0.05));

      // Entreno sin series y cardio sin minutos: lo habitual de cada tipo.
      expect(data.workouts.first.minutes, 60);
      expect(data.workouts.last.slug, 'cycling');
      expect(data.workouts.last.minutes, 45);

      // El peso objetivo estaba en el título.
      expect(data.targetWeightKg, 72.5);
      expect(data.estimated, greaterThanOrEqualTo(7));
    });

    test('junta las partes pegadas una debajo de la otra', () {
      const text = '''
PARTE 1 de 2
===CERES===
{"v": 1, "pesajes": [{"fecha": "2026-01-01", "kg": 80}]}
===FIN===
PARTE 2 de 2
===CERES===
{"v": 1, "pesajes": [{"fecha": "2026-02-01", "kg": 79}]}
===FIN===
''';
      final data = ExternalImport.parse(text, now: _now);
      expect(data.weights, hasLength(2));
    });

    test('sin bloque reconocible avisa en vez de importar nada', () {
      expect(
        () => ExternalImport.parse('no tengo datos tuyos', now: _now),
        throwsA(isA<ExternalImportFormatException>()),
      );
    });

    test('el pedido lleva la fecha de hoy y los marcadores de Ceres', () {
      final prompt = externalImportPrompt(DateTime(2026, 11, 26));
      expect(prompt, contains('Hoy es 2026-11-26'));
      expect(prompt, contains('===CERES==='));
      expect(prompt, contains('===FIN==='));
    });
  });

  group('importación', () {
    late LocalRepository repo;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = await LocalStore.open();
      store.profile = UserProfile.empty('persona');
      repo = LocalRepository(store, onChanged: () {});
    });

    test(
      'la vista previa no escribe y coincide con lo que se importa',
      () async {
        final data = ExternalImport.parse(_block, now: _now);
        final importer = ExternalImporter(repo);

        final preview = await importer.preview(data);
        expect(repo.weightLogs, isEmpty);

        final report = await importer.apply(data);
        expect(report.total, preview.total);
        expect(report.weights, 2);
        expect(report.measurements, 3);
        expect(report.workouts, 2);
        expect(report.sports, 2);
        expect(report.nutritionDays, 1);
        expect(report.foods, 1);
        expect(report.planApplied, isFalse);

        expect(repo.weightOn(DateTime(2026, 11, 1))!.weightKg, 75.8);
        expect(repo.profile.heightCm, 178);
        expect(repo.profile.biologicalSex, BiologicalSex.male);
        final day = DateTime(2026, 11, 20);
        expect(repo.activitiesOn(day), hasLength(2));
        expect(repo.mealsOn(day).single.totalKcal, 2750);
        expect(repo.ownFoods().single.name, 'Avena con banana');
      },
    );

    test('importar dos veces no duplica', () async {
      final data = ExternalImport.parse(_block, now: _now);
      await ExternalImporter(repo).apply(data);
      final second = await ExternalImporter(repo).apply(data);

      expect(second.total, 0);
      expect(second.alreadyThere, greaterThan(0));
      expect(repo.weightLogs, hasLength(2));
      expect(repo.activitiesOn(DateTime(2026, 11, 20)), hasLength(2));
    });

    test('lo cargado en Ceres gana sobre lo de afuera', () async {
      await repo.logWeight(weightKg: 73, date: DateTime(2026, 10, 1));
      final data = ExternalImport.parse(_block, now: _now);
      await ExternalImporter(repo).apply(data);

      expect(repo.weightOn(DateTime(2026, 10, 1))!.weightKg, 73);
    });

    test('el plan solo se aplica si se pide', () async {
      final data = ExternalImport.parse(_block, now: _now);
      await ExternalImporter(
        repo,
      ).apply(data, options: const ExternalImportOptions(usePlan: true));

      final goal = repo.goalFor(today());
      expect(goal.baseCalorieTarget, 2800);
      expect(goal.proteinG, 160);
      expect(goal.targetWeightKg, 80);
      expect(goal.targetMethod, TargetMethod.manual);
    });
  });
}
