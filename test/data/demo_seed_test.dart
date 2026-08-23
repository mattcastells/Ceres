// Los datos de ejemplo no pueden llegar a una compilación de verdad.
//
// El caso real: alguien creó su cuenta y se encontró adentro con el historial
// de "Camila" —treinta días de comidas, un peso de 100 kg y dos actividades por
// día— que no era de nadie. Con la sesión abierta eso se reconcilia contra las
// tablas y sube, así que a partir de ahí los datos inventados y los reales
// viven en la misma cuenta y no se distinguen.
//
// Hay tres cerrojos y acá se prueban los tres, porque cada uno tapa un camino
// distinto: sembrar, arrancar con lo ya sembrado, y entrar a una cuenta desde
// una sesión de prueba.

import 'package:ceres/core/config/feature_flags.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/mock/seed.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<LocalRepository> _boot() async {
  final store = await LocalStore.open();
  return LocalRepository(store, onChanged: () {});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => FeatureFlags.seededDemoDataOverride = null);

  group('la siembra', () {
    test('no hace nada cuando no está permitida', () async {
      FeatureFlags.seededDemoDataOverride = false;
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final store = await LocalStore.open();
      store.seed();

      expect(store.profile, isNull);
      expect(store.meals, isEmpty);
      expect(store.weightLogs, isEmpty);
      expect(store.activities, isEmpty);
    });

    test('sigue andando mientras se desarrolla sin servidor', () async {
      FeatureFlags.seededDemoDataOverride = true;
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final store = await LocalStore.open();
      store.seed();

      expect(store.profile?.id, demoProfileId);
      expect(store.meals, isNotEmpty);
    });
  });

  group('un teléfono que ya tiene los datos sembrados', () {
    test('los pierde al arrancar una compilación que no puede sembrar', () async {
      // Un teléfono con la versión anterior: sembró y guardó.
      FeatureFlags.seededDemoDataOverride = true;
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final antes = await _boot();
      await antes.startDemoSession(seeded: true);
      expect(antes.store.meals, isNotEmpty);

      // La versión de ahora abre lo mismo.
      FeatureFlags.seededDemoDataOverride = false;
      final despues = await _boot();

      expect(despues.hasSession, isFalse);
      expect(despues.store.meals, isEmpty);
      expect(despues.store.weightLogs, isEmpty);
      expect(despues.hasUserData, isFalse);
    });

    test('un documento de verdad no se toca', () async {
      FeatureFlags.seededDemoDataOverride = false;
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final antes = await _boot();
      await antes.signIn('yo@ceres.test');
      await antes.logWeight(weightKg: 72, date: DateTime.now());

      final despues = await _boot();

      expect(despues.hasSession, isTrue);
      expect(despues.profile.email, 'yo@ceres.test');
      expect(despues.weightLogs, hasLength(1));
    });
  });

  group('entrar a una cuenta desde el modo de prueba', () {
    test('no se lleva puesto lo que había en la sesión anónima', () async {
      FeatureFlags.seededDemoDataOverride = true;
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final repo = await _boot();
      await repo.startDemoSession(seeded: true);
      expect(repo.allMeals, isNotEmpty, reason: 'la prueba parte de datos sembrados');

      // El camino que lo provocaba: probar sin cuenta y después entrar.
      await repo.signIn('elias@ceres.test');

      expect(repo.profile.email, 'elias@ceres.test');
      expect(repo.profile.isDemo, isFalse);
      expect(repo.profile.displayName, isNull, reason: 'ni el nombre de la demo');
      expect(repo.allMeals, isEmpty);
      expect(repo.allActivities, isEmpty);
      expect(repo.weightLogs, isEmpty);
      expect(repo.hasUserData, isFalse);
    });

    test('una sesión con cuenta sí conserva lo suyo al reentrar', () async {
      FeatureFlags.seededDemoDataOverride = false;
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final repo = await _boot();
      await repo.signIn('yo@ceres.test');
      await repo.logWeight(weightKg: 72, date: DateTime.now());

      await repo.signIn('yo@ceres.test');

      expect(repo.weightLogs, hasLength(1));
    });
  });

  // El mismo problema que el del modo de prueba, por otra puerta y con peor
  // final: acá los datos que se adoptan son de una persona de verdad. Se llega
  // cuando una sesión vence sin pasar por "cerrar sesión" —contraseña cambiada
  // en otro lado, refresh token invalidado— y en ese teléfono entra otra cuenta.
  group('entrar con otra cuenta en el mismo teléfono', () {
    test('arranca limpio en vez de adoptar lo de la persona anterior', () async {
      FeatureFlags.seededDemoDataOverride = false;
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final repo = await _boot();
      await repo.signIn('ana@ceres.test', accountId: 'uuid-ana');
      await repo.logWeight(weightKg: 72, date: DateTime.now());
      expect(repo.weightLogs, hasLength(1));

      await repo.signIn('bruno@ceres.test', accountId: 'uuid-bruno');

      // Lo que importa: el peso de Ana no queda dentro de la cuenta de Bruno,
      // porque desde ahí el push lo escribiría con **su** user_id.
      expect(repo.weightLogs, isEmpty);
      expect(repo.hasUserData, isFalse);
      expect(repo.profile.email, 'bruno@ceres.test');
    });

    test('la misma cuenta conserva lo suyo', () async {
      FeatureFlags.seededDemoDataOverride = false;
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final repo = await _boot();
      await repo.signIn('ana@ceres.test', accountId: 'uuid-ana');
      await repo.logWeight(weightKg: 72, date: DateTime.now());

      await repo.signIn('ana@ceres.test', accountId: 'uuid-ana');

      expect(repo.weightLogs, hasLength(1));
    });

    test('sin id de cuenta no se borra nada', () async {
      // Compilación sin servidor: no hay `auth.users.id` con qué comparar, así
      // que se conserva. Es el lado seguro; el otro sería borrarle los datos a
      // alguien por no tener con qué compararlos.
      FeatureFlags.seededDemoDataOverride = false;
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final repo = await _boot();
      await repo.signIn('ana@ceres.test');
      await repo.logWeight(weightKg: 72, date: DateTime.now());

      await repo.signIn('ana@ceres.test');

      expect(repo.weightLogs, hasLength(1));
    });
  });
}
