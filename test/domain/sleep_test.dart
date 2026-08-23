import 'package:ceres/core/utils/dates.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/domain/enums/enums.dart';
import 'package:ceres/domain/models/sleep.dart';
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

  test('un día sin registro devuelve null', () {
    expect(repo.sleepOn(hoy), isNull);
  });

  test('registrar de nuevo el mismo día actualiza, no duplica', () async {
    await repo.logSleep(
      date: hoy,
      minutes: 420,
      quality: SleepQuality.ok,
    );
    await repo.logSleep(
      date: hoy,
      minutes: 480,
      quality: SleepQuality.good,
    );

    expect(repo.sleepLogs, hasLength(1));
    expect(repo.sleepOn(hoy)!.minutes, 480);
    expect(repo.sleepOn(hoy)!.quality, SleepQuality.good);
  });

  test('el id se conserva al actualizar', () async {
    await repo.logSleep(date: hoy, minutes: 420, quality: SleepQuality.ok);
    final first = repo.sleepOn(hoy)!.id;

    await repo.logSleep(date: hoy, minutes: 500, quality: SleepQuality.ok);
    expect(repo.sleepOn(hoy)!.id, first);
  });

  test('valores imposibles se recortan', () async {
    // 40 minutos o 30 horas son un error de carga, no una noche.
    await repo.logSleep(date: hoy, minutes: 40, quality: SleepQuality.ok);
    expect(repo.sleepOn(hoy)!.minutes, SleepLog.minMinutes);

    await repo.logSleep(date: hoy, minutes: 1800, quality: SleepQuality.ok);
    expect(repo.sleepOn(hoy)!.minutes, SleepLog.maxMinutes);
  });

  test('cada día lleva su propia noche', () async {
    final ayer = hoy.subtract(const Duration(days: 1));
    await repo.logSleep(date: hoy, minutes: 420, quality: SleepQuality.ok);
    await repo.logSleep(date: ayer, minutes: 300, quality: SleepQuality.bad);

    expect(repo.sleepOn(hoy)!.minutes, 420);
    expect(repo.sleepOn(ayer)!.minutes, 300);
    expect(repo.sleepLogs, hasLength(2));
  });

  test('la duración se muestra en horas y minutos', () {
    SleepLog log(int minutes) => SleepLog(
      id: 'x',
      localDate: hoy,
      minutes: minutes,
      quality: SleepQuality.ok,
      loggedAt: hoy,
    );
    expect(log(480).label, '8 h');
    expect(log(450).label, '7 h 30');
  });

  test('sobrevive a guardar y volver a leer', () async {
    await repo.logSleep(
      date: hoy,
      minutes: 465,
      quality: SleepQuality.great,
    );
    repo.store.restoreDocument(repo.store.toDocument());

    expect(repo.sleepOn(hoy)!.minutes, 465);
    expect(repo.sleepOn(hoy)!.quality, SleepQuality.great);
  });

  test('un respaldo viejo sin sueño no rompe nada', () async {
    final document = repo.store.toDocument()..remove('sleepLogs');
    repo.store.restoreDocument(document);
    expect(repo.sleepLogs, isEmpty);
  });

  // ── Dos noches para el mismo día ───────────────────────────────────────
  //
  // `sleep_logs` tiene la misma clave única por día que `water_logs`, y la
  // reconciliación une por id: dos ids distintos para la misma noche dejan las
  // dos filas en el documento y el servidor rechaza la subida entera.
  //
  // La migración del borrado suave daba por sentado que esto no podía pasar
  // —"`logSleep` reutiliza el id de la noche que ya existe"—, y es cierto
  // mientras la fila esté en este teléfono. Deja de serlo cuando la que existe
  // está en el servidor con otro id.
  group('un día con dos noches', () {
    test('la reparación deja una sola, la de carga más reciente', () async {
      repo.store.sleepLogs = <SleepLog>[
        SleepLog(
          id: 'id-del-servidor',
          localDate: hoy,
          minutes: 300,
          quality: SleepQuality.poor,
          loggedAt: DateTime.now().subtract(const Duration(hours: 5)),
        ),
        SleepLog(
          id: 'id-local',
          localDate: hoy,
          minutes: 465,
          quality: SleepQuality.great,
          loggedAt: DateTime.now(),
        ),
      ];

      await repo.repararRegistrosViejos();

      expect(repo.store.sleepLogs, hasLength(1));
      expect(repo.sleepOn(hoy)!.minutes, 465);
      expect(repo.sleepOn(hoy)!.quality, SleepQuality.great);
    });

    test('una sola noche por día no se toca', () async {
      await repo.logSleep(date: hoy, minutes: 420, quality: SleepQuality.ok);
      final antes = repo.store.sleepLogs.single.id;

      await repo.repararRegistrosViejos();

      expect(repo.store.sleepLogs, hasLength(1));
      expect(repo.store.sleepLogs.single.id, antes);
    });
  });

  // ── Una noche con un id que no es de esta cuenta ───────────────────────
  //
  // La versión del literal `'local'` generaba el **mismo** uuid para el mismo
  // día en dos teléfonos distintos, y la primera cuenta que sincronizó se quedó
  // con él. Desde que el upsert resuelve por día, esa fila ajena ya no da un
  // error de RLS sino uno de clave primaria:
  //
  //   duplicate key value violates unique constraint "sleep_logs_pkey"
  //
  // El `ON CONFLICT (user_id, local_date)` no la encuentra —no es de esta
  // cuenta—, así que Postgres intenta insertar y la primary key, que no sabe de
  // RLS, lo rechaza. Y una tabla que el servidor rechaza no sube **ninguna** de
  // sus filas: el respaldo queda trabado con el error en pantalla.
  group('un id que no deriva de esta cuenta', () {
    // El id esperado no se puede escribir en el test: sale de `_dailyId`, que es
    // privado. Se lo pide a `logSleep`, que es quien lo genera de verdad.
    Future<String> idDelDia(DateTime dia) async {
      await repo.logSleep(date: dia, minutes: 420, quality: SleepQuality.ok);
      final id = repo.store.sleepLogs.single.id;
      repo.store.sleepLogs = <SleepLog>[];
      return id;
    }

    test('la reparación lo regenera a partir del día', () async {
      final esperado = await idDelDia(hoy);
      repo.store.sleepLogs = <SleepLog>[
        SleepLog(
          id: '0eb1f4c2-0000-4000-8000-000000000000',
          localDate: hoy,
          minutes: 420,
          quality: SleepQuality.ok,
          loggedAt: DateTime.now(),
        ),
      ];

      await repo.repararRegistrosViejos();

      expect(repo.store.sleepLogs.single.id, esperado);
    });

    test('regenerar el id conserva la noche entera, lápida incluida', () async {
      await idDelDia(hoy);
      repo.store.sleepLogs = <SleepLog>[
        SleepLog(
          id: '0eb1f4c2-0000-4000-8000-000000000000',
          localDate: hoy,
          minutes: 400,
          quality: SleepQuality.good,
          loggedAt: DateTime.now(),
          notes: 'me desperté dos veces',
          deletedAt: DateTime.now(),
        ),
      ];

      await repo.repararRegistrosViejos();

      final fila = repo.store.sleepLogs.single;
      expect(fila.id, isNot('0eb1f4c2-0000-4000-8000-000000000000'));
      expect(fila.minutes, 400);
      expect(fila.quality, SleepQuality.good);
      expect(fila.notes, 'me desperté dos veces');
      // Sin esto, regenerar el id revive una noche borrada: la lápida se
      // quedaría en la fila vieja y el servidor nunca se enteraría.
      expect(fila.isDeleted, isTrue);
      // Y tiene que volver a salir: el id cambió, así que la fila del servidor
      // todavía no sabe nada de esto.
      expect(fila.syncStatus, SyncStatus.pending);
    });

    test('dos noches ajenas del mismo día terminan en una sola', () async {
      final esperado = await idDelDia(hoy);
      repo.store.sleepLogs = <SleepLog>[
        SleepLog(
          id: '0eb1f4c2-0000-4000-8000-000000000000',
          localDate: hoy,
          minutes: 300,
          quality: SleepQuality.poor,
          loggedAt: DateTime.now().subtract(const Duration(hours: 5)),
        ),
        SleepLog(
          id: '0eb1f4c2-0000-4000-8000-000000000001',
          localDate: hoy,
          minutes: 465,
          quality: SleepQuality.great,
          loggedAt: DateTime.now(),
        ),
      ];

      await repo.repararRegistrosViejos();

      expect(repo.store.sleepLogs, hasLength(1));
      expect(repo.store.sleepLogs.single.id, esperado);
      expect(repo.sleepOn(hoy)!.minutes, 465);
    });
  });
}
