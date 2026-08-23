// El respaldo es hoy la única red de seguridad: si el archivo no vuelve a
// entrar completo, se pierde el historial.

import 'package:ceres/core/error/app_error.dart';
import 'package:ceres/core/utils/dates.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<LocalRepository> _boot({required bool seeded}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final store = await LocalStore.open();
  if (seeded) store.seed();
  return LocalRepository(store, onChanged: () {});
}

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  test('exportar e importar deja los mismos registros', () async {
    final origin = await _boot(seeded: true);
    final before = origin.daily(today());
    final json = origin.exportJson();

    // Una instalación nueva y vacía.
    final destination = await _boot(seeded: false);
    expect(destination.daily(today()).meals, isEmpty);

    final summary = await destination.importJson(json);
    final after = destination.daily(today());

    expect(after.meals.length, before.meals.length);
    expect(after.activities.length, before.activities.length);
    expect(after.consumedKcal, before.consumedKcal);
    expect(after.baseTarget, before.baseTarget);
    expect(destination.profile.id, origin.profile.id);
    expect(summary.meals, greaterThan(0));
    expect(summary.activities, greaterThan(0));
  });

  test('el resumen se puede ver antes de reemplazar nada', () async {
    final origin = await _boot(seeded: true);
    final json = origin.exportJson();

    final destination = await _boot(seeded: false);
    final preview = destination.inspectBackup(json);

    expect(preview.meals, greaterThan(0));
    // Inspeccionar no toca lo que hay cargado.
    expect(destination.daily(today()).meals, isEmpty);
  });

  test('un archivo ajeno se rechaza con un mensaje entendible', () async {
    final repo = await _boot(seeded: false);

    await expectLater(
      () => repo.importJson('{"otra":"app"}'),
      throwsA(
        isA<AppError>().having(
          (e) => e.message,
          'message',
          contains('no es un respaldo de Ceres'),
        ),
      ),
    );
    await expectLater(
      () => repo.importJson('esto no es json'),
      throwsA(isA<AppError>()),
    );
  });

  test('un respaldo de una versión más nueva no se aplica a ciegas', () async {
    final repo = await _boot(seeded: false);

    await expectLater(
      () => repo.importJson('{"profile":null,"schemaVersion":99}'),
      throwsA(
        isA<AppError>().having(
          (e) => e.message,
          'message',
          contains('versión más nueva'),
        ),
      ),
    );
  });
}
