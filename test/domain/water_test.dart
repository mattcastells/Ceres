import 'package:ceres/core/utils/dates.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/domain/models/water.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalRepository repo;
  final hoy = today();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = await LocalStore.open();
    repo = LocalRepository(store, onChanged: () {});
  });

  test('un día sin registro cuenta cero, no null', () {
    expect(repo.glassesOn(hoy), 0);
  });

  test('sumar vasos crea el registro del día', () async {
    await repo.addGlasses(hoy, 1);
    await repo.addGlasses(hoy, 1);
    expect(repo.glassesOn(hoy), 2);
    expect(repo.waterLogs, hasLength(1));
  });

  test('restar no baja de cero', () async {
    await repo.addGlasses(hoy, 1);
    await repo.addGlasses(hoy, -5);
    expect(repo.glassesOn(hoy), 0);
  });

  test('restar sin registro previo no crea un día vacío', () async {
    await repo.addGlasses(hoy, -1);
    expect(repo.waterLogs, isEmpty);
  });

  test('no se pasa del tope defensivo', () async {
    await repo.addGlasses(hoy, 999);
    expect(repo.glassesOn(hoy), WaterLog.maxGlasses);
  });

  test('cada día lleva su propia cuenta', () async {
    final ayer = hoy.subtract(const Duration(days: 1));
    await repo.addGlasses(hoy, 3);
    await repo.addGlasses(ayer, 7);
    expect(repo.glassesOn(hoy), 3);
    expect(repo.glassesOn(ayer), 7);
    expect(repo.waterLogs, hasLength(2));
  });

  test('cambiar el tamaño del vaso no reescribe el historial', () async {
    await repo.addGlasses(hoy, 4);
    await repo.setWaterGoal(glasses: 10, glassSizeMl: 500);

    // Los vasos registrados siguen siendo 4: lo que cambia es el equivalente
    // en ml que se muestra, no el dato guardado.
    expect(repo.glassesOn(hoy), 4);
    expect(repo.profile.waterGoalGlasses, 10);
    expect(repo.profile.glassSizeMl, 500);
  });

  test('la meta y el vaso quedan dentro de límites razonables', () async {
    await repo.setWaterGoal(glasses: 0, glassSizeMl: 5);
    expect(repo.profile.waterGoalGlasses, 1);
    expect(repo.profile.glassSizeMl, 50);

    await repo.setWaterGoal(glasses: 500, glassSizeMl: 99999);
    expect(repo.profile.waterGoalGlasses, WaterLog.maxGlasses);
    expect(repo.profile.glassSizeMl, 1000);
  });

  test('el registro sobrevive a guardar y volver a leer', () async {
    await repo.addGlasses(hoy, 5);
    final document = repo.store.toDocument();

    repo.store.restoreDocument(document);
    expect(repo.store.waterLogs, hasLength(1));
    expect(repo.store.waterLogs.first.glasses, 5);
  });

  // ── Dos filas para el mismo día ────────────────────────────────────────
  //
  // El estado que producía `duplicate key value violates unique constraint
  // "water_logs_one_per_day"`. No lo arma la app sola: la reconciliación une
  // las listas **por id**, así que cuando la fila del servidor y la local
  // tenían ids distintos para el mismo día, las dos quedaban en el documento.
  // Y no era solo un problema al subir — `glassesOn` devuelve la primera que
  // encuentra, o sea que la app podía estar mostrando la vieja.
  group('un día con dos registros', () {
    void sembrarDuplicado() {
      repo.store.waterLogs = <WaterLog>[
        WaterLog(
          id: 'id-del-servidor',
          localDate: hoy,
          glasses: 2,
          updatedAt: DateTime.now().subtract(const Duration(hours: 3)),
        ),
        WaterLog(
          id: 'id-local',
          localDate: hoy,
          glasses: 7,
          updatedAt: DateTime.now(),
        ),
      ];
    }

    test('la reparación deja uno solo y se queda con el más reciente', () async {
      sembrarDuplicado();
      await repo.repararRegistrosViejos();

      expect(repo.store.waterLogs, hasLength(1));
      expect(repo.store.waterLogs.single.glasses, 7);
      expect(repo.glassesOn(hoy), 7);
    });

    test('correrla dos veces deja lo mismo que una', () async {
      sembrarDuplicado();
      await repo.repararRegistrosViejos();
      final despuesDeUna = repo.store.waterLogs.single;

      await repo.repararRegistrosViejos();
      expect(repo.store.waterLogs, hasLength(1));
      expect(repo.store.waterLogs.single.id, despuesDeUna.id);
      expect(repo.store.waterLogs.single.glasses, despuesDeUna.glasses);
    });

    test('días distintos no se juntan', () async {
      final ayer = hoy.subtract(const Duration(days: 1));
      repo.store.waterLogs = <WaterLog>[
        WaterLog(id: 'a', localDate: ayer, glasses: 3, updatedAt: DateTime.now()),
        WaterLog(id: 'b', localDate: hoy, glasses: 5, updatedAt: DateTime.now()),
      ];
      await repo.repararRegistrosViejos();

      expect(repo.store.waterLogs, hasLength(2));
      expect(repo.glassesOn(ayer), 3);
      expect(repo.glassesOn(hoy), 5);
    });
  });
}
