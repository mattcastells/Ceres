// La importación desde Health Connect: peso, grasa corporal y sueño.
//
// Lo que hay que dejar probado no es que importe —eso se ve— sino que **no
// pueda duplicar**. Health Connect fue descartado durante meses justamente por
// el riesgo de doble conteo, y la única razón por la que ahora entra es que
// estas tres cosas son una por día o por noche y volver a registrarlas actualiza
// el registro que ya estaba (D-16). Si eso alguna vez deja de ser cierto, acá se
// tiene que ver.

import 'package:ceres/core/utils/dates.dart';
import 'package:ceres/data/local/health_connect_gateway.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/domain/enums/enums.dart';
import 'package:ceres/domain/models/sleep.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Un Health Connect de mentira: devuelve lo que se le ponga, sin plataforma
/// nativa de por medio.
class _FakeHealthConnect extends HealthConnectGateway {
  _FakeHealthConnect({
    required this.snapshot,
    this.granted = true,
    this.state = HealthConnectAvailability.available,
  });

  final HealthConnectSnapshot snapshot;
  final bool granted;
  final HealthConnectAvailability state;
  int reads = 0;

  @override
  Future<HealthConnectAvailability> availability() async => state;

  @override
  Future<bool> hasPermissions() async => granted;

  @override
  Future<bool> requestPermissions() async => granted;

  @override
  Future<HealthConnectSnapshot> read() async {
    reads++;
    return snapshot;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final hoy = today();
  final ayer = hoy.subtract(const Duration(days: 1));

  Future<LocalRepository> boot(HealthConnectGateway health) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = await LocalStore.open();
    return LocalRepository(store, onChanged: () {}, health: health);
  }

  final snapshot = HealthConnectSnapshot(
    weightKg: <DateTime, double>{ayer: 81.2, hoy: 80.8},
    bodyFatPct: <DateTime, double>{hoy: 22.4},
    sleepMinutes: <DateTime, int>{ayer: 431, hoy: 402},
  );

  test('importa peso, grasa y sueño de los días que trae', () async {
    final repo = await boot(_FakeHealthConnect(snapshot: snapshot));

    final result = await repo.sync();

    expect(result.imported, 5);
    expect(result.updated, 0);
    // Nada de esto puede duplicar, así que no hay nada que mandar a revisar.
    expect(result.duplicates, isEmpty);

    expect(repo.weightOn(hoy)?.weightKg, 80.8);
    expect(repo.weightOn(ayer)?.weightKg, 81.2);
    expect(
      repo.measurementsOn(hoy)[MeasurementMetric.bodyFatPct]?.value,
      22.4,
    );
    expect(repo.sleepOn(hoy)?.minutes, 402);
  });

  test('sincronizar diez veces deja lo mismo que sincronizar una', () async {
    final health = _FakeHealthConnect(snapshot: snapshot);
    final repo = await boot(health);

    for (var i = 0; i < 10; i++) {
      await repo.sync();
    }

    expect(health.reads, 10);
    // Un registro por día y por métrica, no diez.
    expect(repo.weightLogs.length, 2);
    expect(repo.measurements(MeasurementMetric.bodyFatPct).length, 1);
    expect(repo.sleepLogs.length, 2);
  });

  test('la segunda pasada cuenta como corrección, no como importación', () async {
    final repo = await boot(_FakeHealthConnect(snapshot: snapshot));

    await repo.sync();
    final again = await repo.sync();

    // Son dos cosas distintas y la pantalla las dice por separado.
    expect(again.imported, 0);
    expect(again.updated, 5);
  });

  test('no pisa la calidad de sueño que puso la persona', () async {
    final repo = await boot(_FakeHealthConnect(snapshot: snapshot));

    await repo.logSleep(
      date: hoy,
      minutes: 300,
      quality: SleepQuality.bad,
      notes: 'me desperté a las 4',
    );
    await repo.sync();

    // La duración la mide el reloj, así que manda la importada.
    expect(repo.sleepOn(hoy)?.minutes, 402);
    // La calidad y la nota son de la persona: Health Connect no las mide de una
    // forma que se pueda traducir sin inventar, así que se conservan.
    expect(repo.sleepOn(hoy)?.quality, SleepQuality.bad);
    expect(repo.sleepOn(hoy)?.notes, 'me desperté a las 4');
  });

  test('sin permisos no lee nada y lo dice', () async {
    final health = _FakeHealthConnect(snapshot: snapshot, granted: false);
    final repo = await boot(health);

    final result = await repo.sync();

    expect(health.reads, 0);
    expect(result.imported, 0);
    expect(repo.integration.status, IntegrationStatus.error);
    expect(repo.integration.lastError, isNotNull);
  });

  test('sin Health Connect en el teléfono, conectar explica por qué', () async {
    final repo = await boot(
      _FakeHealthConnect(
        snapshot: snapshot,
        state: HealthConnectAvailability.unsupported,
      ),
    );

    await repo.connect();

    expect(repo.integration.status, IntegrationStatus.error);
    // "No lo soporta tu Android" y "actualizá Health Connect" se arreglan de
    // formas distintas, así que no pueden decir lo mismo.
    expect(repo.integration.lastError, contains('Android 9'));
  });

  test('con Health Connect viejo, manda a actualizarlo', () async {
    final repo = await boot(
      _FakeHealthConnect(
        snapshot: snapshot,
        state: HealthConnectAvailability.updateRequired,
      ),
    );

    await repo.connect();

    expect(repo.integration.lastError, contains('Actualizá'));
  });

  test('conectar con permiso deja la integración lista', () async {
    final repo = await boot(_FakeHealthConnect(snapshot: snapshot));

    await repo.connect();

    expect(repo.integration.status, IntegrationStatus.connected);
    expect(repo.integration.permissions, <String>[
      'Weight',
      'BodyFat',
      'SleepSession',
    ]);
    expect(repo.integration.lastError, isNull);
  });
}
