// El bug reportado: no se podía editar ni borrar el peso de días anteriores.
//
// No era una fecha bloqueada en ningún lado —la causa real era que la lista
// de "Registros" nunca conectó `onEdit` ni un borrado a ninguna fila—, pero
// el contrato de fondo (editar/borrar/restaurar por fecha, cualquiera sea)
// es lo que hay que dejar probado para que no vuelva a regresionar en la capa
// de datos, sea cual sea la pantalla que la use.

import 'package:ceres/core/utils/dates.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalRepository repo;
  final hoy = today();
  final haceTresDias = hoy.subtract(const Duration(days: 3));

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = await LocalStore.open();
    repo = LocalRepository(store, onChanged: () {});
  });

  group('editar', () {
    test('registrar de nuevo sobre un día pasado actualiza, no duplica', () async {
      await repo.logWeight(weightKg: 80, date: haceTresDias);
      await repo.logWeight(weightKg: 79.5, date: haceTresDias);

      expect(repo.weightLogs, hasLength(1));
      expect(repo.weightOn(haceTresDias)?.weightKg, 79.5);
    });
  });

  group('borrar y restaurar', () {
    test('borrar un registro de hace 3 días lo saca de la lista', () async {
      final log = await repo.logWeight(weightKg: 80, date: haceTresDias);

      await repo.deleteWeight(log.id);

      expect(repo.weightLogs, isEmpty);
      expect(repo.weightOn(haceTresDias), isNull);
    });

    test('borrar no afecta el registro de otro día', () async {
      final viejo = await repo.logWeight(weightKg: 80, date: haceTresDias);
      await repo.logWeight(weightKg: 78, date: hoy);

      await repo.deleteWeight(viejo.id);

      expect(repo.weightLogs, hasLength(1));
      expect(repo.weightOn(hoy)?.weightKg, 78);
    });

    test('restaurar devuelve el registro borrado', () async {
      final log = await repo.logWeight(weightKg: 80, date: haceTresDias);
      await repo.deleteWeight(log.id);

      await repo.restoreWeight(log.id);

      expect(repo.weightLogs, hasLength(1));
      expect(repo.weightOn(haceTresDias)?.weightKg, 80);
    });

    test('el peso actual ignora un registro borrado', () async {
      await repo.logWeight(weightKg: 80, date: haceTresDias);
      final ultimo = await repo.logWeight(weightKg: 79, date: hoy);

      await repo.deleteWeight(ultimo.id);

      expect(repo.currentWeightKg, 80);
    });
  });

  // La base admite **un** peso por día y por persona. Con ids al azar, dos
  // dispositivos que registran el mismo día creaban dos filas para esa misma
  // clave: la segunda chocaba contra el índice único y el push de `weight_logs`
  // fallaba. Y no se arreglaba solo, porque la reconciliación une por id y
  // conserva las dos, así que volvía a fallar en cada intento.
  group('un peso por día, también entre dispositivos', () {
    Future<LocalRepository> dispositivoDe(String cuenta) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final repo = LocalRepository(await LocalStore.open(), onChanged: () {});
      await repo.signIn('ana@ceres.test', accountId: cuenta);
      return repo;
    }

    test('dos dispositivos de la misma cuenta generan el mismo id', () async {
      final telefono = await dispositivoDe('uuid-ana');
      final web = await dispositivoDe('uuid-ana');

      final desdeElTelefono = await telefono.logWeight(
        weightKg: 72,
        date: hoy,
      );
      final desdeLaWeb = await web.logWeight(weightKg: 71.5, date: hoy);

      // Mismo id: el upsert los hace converger en vez de chocar.
      expect(desdeLaWeb.id, desdeElTelefono.id);
    });

    test('días distintos no comparten id', () async {
      final repo = await dispositivoDe('uuid-ana');

      final a = await repo.logWeight(weightKg: 72, date: hoy);
      final b = await repo.logWeight(weightKg: 73, date: haceTresDias);

      expect(a.id, isNot(b.id));
    });

    test('el peso importado se distingue del cargado a mano', () async {
      // La columna `source` existe desde siempre y la base contempla
      // `'imported'`, pero `logWeight` no lo aceptaba: todo entraba como
      // `'manual'`. Sin eso no hay forma de deshacer una importación sin
      // llevarse puesto lo que la persona cargó.
      final repo = await dispositivoDe('uuid-ana');

      final aMano = await repo.logWeight(weightKg: 72, date: hoy);
      final importado = await repo.logWeight(
        weightKg: 71,
        date: hoy.subtract(const Duration(days: 1)),
        source: 'imported',
      );

      expect(aMano.source, 'manual');
      expect(importado.source, 'imported');
    });

    test('cuentas distintas no comparten id', () async {
      final ana = await dispositivoDe('uuid-ana');
      final bruno = await dispositivoDe('uuid-bruno');

      final deAna = await ana.logWeight(weightKg: 72, date: hoy);
      final deBruno = await bruno.logWeight(weightKg: 90, date: hoy);

      expect(deAna.id, isNot(deBruno.id));
    });
  });
}
