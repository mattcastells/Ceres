import 'package:ceres/core/utils/dates.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/domain/enums/enums.dart';
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

  group('catálogo de métricas', () {
    test('los identificadores de almacenamiento son únicos', () {
      final wires = MeasurementMetric.values.map((m) => m.wire).toList();
      expect(wires.toSet(), hasLength(wires.length));
    });

    test('los perímetros históricos conservan su identificador', () {
      // Renombrar una etiqueta está bien; cambiar el `wire` dejaría huérfanas
      // las medidas ya guardadas en el teléfono de alguien.
      for (final wire in const <String>[
        'waist',
        'hip',
        'chest',
        'arm',
        'thigh',
        'neck',
        'body_fat_pct',
      ]) {
        expect(
          MeasurementMetric.values.any((m) => m.wire == wire),
          isTrue,
          reason: 'falta $wire',
        );
      }
    });

    test('cada grupo tiene su unidad', () {
      for (final m in MeasurementMetric.inGroup(MeasurementGroup.perimeters)) {
        expect(m.unit, 'cm');
      }
      for (final m in MeasurementMetric.inGroup(MeasurementGroup.skinfolds)) {
        expect(m.unit, 'mm');
      }
      expect(MeasurementMetric.folds, hasLength(7));
    });

    test('los rangos son coherentes', () {
      for (final m in MeasurementMetric.values) {
        expect(m.min, lessThan(m.max), reason: m.wire);
      }
    });

    test('la grasa visceral es un índice, sin unidad visible', () {
      expect(MeasurementMetric.visceralFat.unitLabel, '');
      expect(MeasurementMetric.bodyFatPct.unitLabel, '%');
      expect(MeasurementMetric.tricepsFold.unitLabel, 'mm');
    });

    test('el músculo en % y en kg se distinguen en las listas', () {
      expect(MeasurementMetric.musclePct.label, MeasurementMetric.muscleKg.label);
      expect(
        MeasurementMetric.musclePct.longLabel,
        isNot(MeasurementMetric.muscleKg.longLabel),
      );
    });

    test('un identificador desconocido no rompe la lectura', () {
      expect(MeasurementMetric.fromWire('lo_que_sea'), MeasurementMetric.waist);
    });
  });

  group('registro', () {
    test('se cargan varias métricas del mismo día', () async {
      await repo.logMeasurement(
        metric: MeasurementMetric.waist,
        value: 84,
        date: hoy,
      );
      await repo.logMeasurement(
        metric: MeasurementMetric.tricepsFold,
        value: 12.5,
        date: hoy,
      );
      await repo.logMeasurement(
        metric: MeasurementMetric.visceralFat,
        value: 7,
        date: hoy,
      );

      final delDia = repo.measurementsOn(hoy);
      expect(delDia, hasLength(3));
      expect(delDia[MeasurementMetric.tricepsFold]?.value, 12.5);
      expect(delDia[MeasurementMetric.tricepsFold]?.unit, 'mm');
    });

    test('volver a cargar la misma métrica el mismo día actualiza', () async {
      await repo.logMeasurement(
        metric: MeasurementMetric.waist,
        value: 84,
        date: hoy,
      );
      await repo.logMeasurement(
        metric: MeasurementMetric.waist,
        value: 83,
        date: hoy,
      );

      expect(repo.measurements(MeasurementMetric.waist), hasLength(1));
      expect(repo.measurementsOn(hoy)[MeasurementMetric.waist]?.value, 83);
    });

    test('un día sin medidas devuelve el mapa vacío', () {
      expect(repo.measurementsOn(hoy), isEmpty);
    });

    test('la serie de una métrica queda ordenada por fecha', () async {
      await repo.logMeasurement(
        metric: MeasurementMetric.calf,
        value: 37,
        date: hoy,
      );
      await repo.logMeasurement(
        metric: MeasurementMetric.calf,
        value: 36,
        date: hoy.subtract(const Duration(days: 7)),
      );

      final serie = repo.measurements(MeasurementMetric.calf);
      expect(serie.map((m) => m.value).toList(), <double>[36, 37]);
    });
  });

  // Del lado de la base hay un índice único sobre `(user_id, metric,
  // local_date)`. Todo lo de este grupo existe para que el documento local no
  // pueda contradecirlo: cuando lo contradecía, el push de medidas fallaba
  // entero y volvía a fallar en cada intento posterior, para siempre.
  group('una fila por métrica y día', () {
    test('corregir una medida conserva el id', () async {
      await repo.logMeasurement(
        metric: MeasurementMetric.waist,
        value: 84,
        date: hoy,
      );
      final primera = repo.measurementsOn(hoy)[MeasurementMetric.waist]!;

      await repo.logMeasurement(
        metric: MeasurementMetric.waist,
        value: 82,
        date: hoy,
      );
      final corregida = repo.measurementsOn(hoy)[MeasurementMetric.waist]!;

      expect(corregida.id, primera.id, reason: 'un id nuevo choca en la base');
      expect(corregida.value, 82);
      expect(repo.allMeasurements.where((m) => m.metric == MeasurementMetric.waist),
          hasLength(1));
    });

    test('corregir deja una marca de tiempo más nueva', () async {
      await repo.logMeasurement(
        metric: MeasurementMetric.hip,
        value: 95,
        date: hoy,
      );
      final antes = repo.measurementsOn(hoy)[MeasurementMetric.hip]!.updatedAt;
      expect(antes, isNotNull);

      await Future<void>.delayed(const Duration(milliseconds: 2));
      await repo.logMeasurement(
        metric: MeasurementMetric.hip,
        value: 94,
        date: hoy,
      );
      final despues = repo.measurementsOn(hoy)[MeasurementMetric.hip]!.updatedAt;

      // Sin esto, la reconciliación no puede saber cuál de las dos versiones
      // es la buena y se queda con la del servidor: el número corregido se
      // pierde.
      expect(despues!.isAfter(antes!), isTrue);
    });

    test('borrar deja lápida en vez de sacar la fila', () async {
      await repo.logMeasurement(
        metric: MeasurementMetric.chest,
        value: 100,
        date: hoy,
      );
      final medida = repo.measurementsOn(hoy)[MeasurementMetric.chest]!;

      await repo.deleteMeasurement(medida.id);

      // No se ve por ningún lado...
      expect(repo.measurementsOn(hoy), isEmpty);
      expect(repo.measurements(MeasurementMetric.chest), isEmpty);
      expect(repo.allMeasurements, isEmpty);
      // ...pero la lápida sigue en el documento, que es lo que hace que el
      // borrado llegue al servidor en vez de quedarse en este teléfono.
      final crudas = repo.store.measurements;
      expect(crudas, hasLength(1));
      expect(crudas.single.isDeleted, isTrue);
    });

    test('volver a cargar una medida borrada revive la misma fila', () async {
      await repo.logMeasurement(
        metric: MeasurementMetric.thigh,
        value: 55,
        date: hoy,
      );
      final original = repo.measurementsOn(hoy)[MeasurementMetric.thigh]!;
      await repo.deleteMeasurement(original.id);

      await repo.logMeasurement(
        metric: MeasurementMetric.thigh,
        value: 54,
        date: hoy,
      );

      final revivida = repo.measurementsOn(hoy)[MeasurementMetric.thigh]!;
      expect(revivida.id, original.id);
      expect(revivida.isDeleted, isFalse);
      expect(repo.store.measurements, hasLength(1));
    });
  });
}
