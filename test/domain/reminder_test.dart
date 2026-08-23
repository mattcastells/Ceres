import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/domain/models/reminder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Reminder', () {
    test('arranca apagado: una app que notifica sola se desinstala', () {
      for (final kind in ReminderKind.values) {
        expect(Reminder.byDefault(kind).enabled, isFalse);
      }
    });

    test('el agua repite y la comida no', () {
      expect(Reminder.byDefault(ReminderKind.water).times.length, 3);
      expect(Reminder.byDefault(ReminderKind.meals).times.length, 1);
    });

    test('los horarios quedan ordenados y sin repetidos', () {
      final r = Reminder.byDefault(ReminderKind.meals)
          .copyWith(times: <ReminderTime>[])
          .withTimeAdded(const ReminderTime(22, 0))
          .withTimeAdded(const ReminderTime(8, 30))
          .withTimeAdded(const ReminderTime(22, 0));

      expect(r.times.map((t) => t.label), <String>['08:30', '22:00']);
    });

    test('hay un tope de horarios', () {
      var r = Reminder.byDefault(ReminderKind.water)
          .copyWith(times: <ReminderTime>[]);
      for (var h = 0; h < 20; h++) {
        r = r.withTimeAdded(ReminderTime(h, 0));
      }
      expect(r.times.length, Reminder.maxTimes);
    });

    test('cada horario tiene un id propio y estable', () {
      // Los ids se usan para cancelar y reprogramar: si dos coincidieran, un
      // recordatorio pisaría al otro.
      final ids = <int>{};
      for (final kind in ReminderKind.values) {
        for (var h = 0; h < 24; h++) {
          for (final m in <int>[0, 30]) {
            ids.add(ReminderTime(h, m).idFor(kind));
          }
        }
      }
      expect(ids.length, ReminderKind.values.length * 24 * 2);

      expect(
        const ReminderTime(9, 15).idFor(ReminderKind.water),
        const ReminderTime(9, 15).idFor(ReminderKind.water),
      );
    });

    test('sobrevive a guardar y volver a leer', () {
      final original = Reminder.byDefault(ReminderKind.water)
          .copyWith(enabled: true)
          .withTimeAdded(const ReminderTime(7, 45));

      final restored = Reminder.fromJson(original.toJson());
      expect(restored.kind, ReminderKind.water);
      expect(restored.enabled, isTrue);
      expect(restored.times.map((t) => t.label), contains('07:45'));
    });
  });

  group('persistencia', () {
    late LocalRepository repo;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = await LocalStore.open();
      repo = LocalRepository(store, onChanged: () {});
    });

    test('guardar uno no toca el otro', () async {
      await repo.saveReminder(
        repo.reminderFor(ReminderKind.water).copyWith(enabled: true),
      );

      expect(repo.reminderFor(ReminderKind.water).enabled, isTrue);
      expect(repo.reminderFor(ReminderKind.meals).enabled, isFalse);
      expect(repo.reminders, hasLength(ReminderKind.values.length));
    });

    test('un respaldo viejo sin recordatorios no rompe nada', () async {
      // El documento de una versión anterior no trae la clave: los que falten
      // se completan apagados en vez de dejar la lista vacía.
      final document = repo.store.toDocument()..remove('reminders');
      repo.store.restoreDocument(document);

      expect(repo.store.reminders, hasLength(ReminderKind.values.length));
      expect(repo.reminderFor(ReminderKind.meals).enabled, isFalse);
    });
  });
}
