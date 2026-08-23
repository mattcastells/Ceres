// Qué pasa cuando el documento guardado no se puede leer del todo.
//
// La versión anterior hacía `remove()` sobre el documento que no había podido
// interpretar: un solo registro con un campo raro y se perdía **todo** —
// comidas, peso, medidas, historial— sin copia y sin aviso. Estos tests son la
// reproducción de esa pérdida y el candado para que no vuelva.

import 'dart:convert';

import 'package:ceres/data/local/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _key = 'ceres.local_store.v1';
const String _quarantineKey = 'ceres.local_store.v1.quarantine';

/// Un documento con lo mínimo para parecerse a uno real.
Map<String, dynamic> _documento() => <String, dynamic>{
  'schemaVersion': 1,
  'profile': <String, dynamic>{
    'id': 'u1',
    'displayName': 'Matías',
    'biologicalSex': 'male',
    'activityLevel': 'moderate',
    'timezone': 'America/Argentina/Buenos_Aires',
    'unitSystem': 'metric',
    'themeMode': 'system',
    'locale': 'es',
    'exerciseCreditPercentage': 0,
    'exerciseCreditEnabled': true,
    'showNetCalories': false,
    'createdAt': '2026-07-01T10:00:00.000',
    'updatedAt': '2026-07-01T10:00:00.000',
  },
  'weightLogs': <dynamic>[
    <String, dynamic>{
      'id': 'w1',
      'weightKg': 82.5,
      'localDate': '2026-07-28',
      'loggedAt': '2026-07-28T09:00:00.000',
      'source': 'manual',
      'syncStatus': 'synced',
    },
    <String, dynamic>{
      'id': 'w2',
      'weightKg': 82.1,
      'localDate': '2026-07-29',
      'loggedAt': '2026-07-29T09:00:00.000',
      'source': 'manual',
      'syncStatus': 'synced',
    },
  ],
  'measurements': <dynamic>[
    <String, dynamic>{
      'id': 'm1',
      'metric': 'waist',
      'value': 84.0,
      'localDate': '2026-07-28',
    },
  ],
};

Future<LocalStore> _abrirCon(Map<String, dynamic> doc) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    _key: jsonEncode(doc),
  });
  return LocalStore.open();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('un documento sano se lee entero', () async {
    final store = await _abrirCon(_documento());

    expect(store.profile?.displayName, 'Matías');
    expect(store.weightLogs, hasLength(2));
    expect(store.measurements, hasLength(1));
    expect(store.lastRestore.isClean, isTrue);
  });

  group('un registro roto no se lleva puesto el documento', () {
    test('se saltea solo ese registro y el resto sobrevive', () async {
      final doc = _documento();
      // Le falta `weightKg`: antes esto tiraba y borraba todo.
      (doc['weightLogs'] as List<dynamic>).add(<String, dynamic>{
        'id': 'roto',
        'localDate': '2026-07-29',
        'loggedAt': '2026-07-29T10:00:00.000',
      });

      final store = await _abrirCon(doc);

      expect(store.weightLogs, hasLength(2), reason: 'los buenos siguen');
      expect(store.measurements, hasLength(1), reason: 'otra sección intacta');
      expect(store.profile, isNotNull);
      expect(store.lastRestore.skippedRecords, 1);
      expect(store.lastRestore.skippedBySection['weightLogs'], 1);
    });

    test('una sección entera con basura no toca a las demás', () async {
      final doc = _documento()..['meals'] = <dynamic>['esto no es un objeto'];

      final store = await _abrirCon(doc);

      expect(store.meals, isEmpty);
      expect(store.weightLogs, hasLength(2));
      expect(store.lastRestore.isClean, isFalse);
    });

    test('un valor desconocido en un enum no rompe nada', () async {
      // Una versión más nueva pudo escribir un objetivo o una métrica que
      // esta no conoce. Degradar está bien; perder el documento no.
      final doc = _documento();
      (doc['measurements'] as List<dynamic>).add(<String, dynamic>{
        'id': 'm2',
        'metric': 'metrica_del_futuro',
        'value': 12.0,
        'localDate': '2026-07-29',
      });

      final store = await _abrirCon(doc);

      expect(store.measurements, hasLength(2));
      expect(store.weightLogs, hasLength(2));
    });
  });

  group('nunca se borra lo que no se pudo leer', () {
    test('un JSON ilegible se aparta, no se elimina', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _key: '{ esto no es json',
      });

      final store = await LocalStore.open();

      expect(store.profile, isNull);
      expect(store.lastRestore.unreadableDocument, isTrue);
      expect(
        store.quarantinedDocument,
        '{ esto no es json',
        reason: 'la copia original tiene que quedar para recuperarla a mano',
      );

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(_quarantineKey),
        isNotNull,
        reason: 'antes acá se hacía remove() y no quedaba nada',
      );
    });

    test('una lectura parcial también deja copia antes de escribir', () async {
      final doc = _documento();
      (doc['weightLogs'] as List<dynamic>).add(<String, dynamic>{'id': 'roto'});

      final store = await _abrirCon(doc);

      expect(store.lastRestore.quarantined, isTrue);
      expect(store.quarantinedDocument, isNotNull);

      // Y lo apartado es el documento original completo, con los dos pesos
      // buenos adentro: es lo que permite recuperarlos.
      final apartado =
          jsonDecode(store.quarantinedDocument!) as Map<String, dynamic>;
      expect((apartado['weightLogs'] as List<dynamic>), hasLength(3));
    });

    test('persistir después de una lectura parcial no toca la copia apartada',
        () async {
      final doc = _documento();
      (doc['weightLogs'] as List<dynamic>).add(<String, dynamic>{'id': 'roto'});

      final store = await _abrirCon(doc);
      await store.persist();

      final apartado =
          jsonDecode(store.quarantinedDocument!) as Map<String, dynamic>;
      expect((apartado['weightLogs'] as List<dynamic>), hasLength(3));
    });
  });

  group('hasUserData', () {
    test('es false recién abierto sin nada', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = await LocalStore.open();
      expect(store.hasUserData, isFalse);
    });

    test('es true con un solo registro', () async {
      final store = await _abrirCon(_documento());
      expect(store.hasUserData, isTrue);
    });

    test('es false si el documento no se pudo leer', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _key: '{ roto',
      });
      final store = await LocalStore.open();
      // Y por eso el respaldo no va a subir: es el caso que borraba la nube.
      expect(store.hasUserData, isFalse);
    });
  });
}
