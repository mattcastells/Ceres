// Una cuenta nueva no entra a Inicio hasta tener los datos con los que la app
// calcula.
//
// Sin fecha de nacimiento, altura y peso no hay Mifflin-St Jeor, así que el
// número grande de Inicio —"te quedan 1.096 kcal"— salía de un objetivo de
// 2.000 puesto por defecto y no de ninguna cuenta. Un valor de referencia
// disfrazado de cálculo es exactamente lo que el producto no hace.
//
// El que decide es `needsOnboarding`, y el que lo hace cumplir es el `redirect`
// del router. Acá se prueba el primero: es donde vive la regla.

import 'package:ceres/core/config/feature_flags.dart';
import 'package:ceres/core/utils/dates.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/domain/enums/enums.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<LocalRepository> _boot() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final store = await LocalStore.open();
  return LocalRepository(store, onChanged: () {});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FeatureFlags.seededDemoDataOverride = false);
  tearDown(() => FeatureFlags.seededDemoDataOverride = null);

  test('sin sesión no hay nada que completar', () async {
    final repo = await _boot();
    expect(repo.hasSession, isFalse);
    expect(repo.needsOnboarding, isFalse);
  });

  test('una cuenta recién creada tiene que completar', () async {
    final repo = await _boot();
    await repo.signIn('elias@ceres.test');

    expect(repo.hasSession, isTrue);
    expect(repo.needsOnboarding, isTrue);
  });

  test('los tres datos son necesarios, y ninguno alcanza solo', () async {
    final repo = await _boot();
    await repo.signIn('elias@ceres.test');

    await repo.updateProfile(
      repo.profile.copyWith(birthDate: DateTime(1990, 4, 12)),
    );
    expect(repo.needsOnboarding, isTrue, reason: 'falta la altura y el peso');

    await repo.updateProfile(repo.profile.copyWith(heightCm: 178));
    expect(repo.needsOnboarding, isTrue, reason: 'falta el peso');

    await repo.logWeight(weightKg: 82, date: today());
    expect(repo.needsOnboarding, isFalse);
  });

  test('el sexo biológico no es un requisito: "Otro" es una respuesta', () async {
    final repo = await _boot();
    await repo.signIn('elias@ceres.test');
    await repo.updateProfile(
      repo.profile.copyWith(
        birthDate: DateTime(1990, 4, 12),
        heightCm: 178,
        biologicalSex: BiologicalSex.unspecified,
      ),
    );
    await repo.logWeight(weightKg: 82, date: today());

    // Si esto pidiera un sexo distinto de "sin especificar", quien elija "Otro"
    // quedaría encerrado en el alta para siempre: es el valor que se guarda.
    expect(repo.needsOnboarding, isFalse);
  });

  test('borrar el último peso vuelve a pedir el dato', () async {
    final repo = await _boot();
    await repo.signIn('elias@ceres.test');
    await repo.updateProfile(
      repo.profile.copyWith(birthDate: DateTime(1990, 4, 12), heightCm: 178),
    );
    final log = await repo.logWeight(weightKg: 82, date: today());
    expect(repo.needsOnboarding, isFalse);

    await repo.deleteWeight(log.id);

    // Sin peso no hay BMR ni cálculo MET: el estado es el mismo que el de una
    // cuenta nueva, y la app tiene que decirlo en vez de seguir mostrando un
    // número que ya no tiene de dónde salir.
    expect(repo.needsOnboarding, isTrue);
  });

  test('sobrevive a cerrar y volver a abrir la app', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final antes = LocalRepository(await LocalStore.open(), onChanged: () {});
    await antes.signIn('elias@ceres.test');
    await antes.updateProfile(
      antes.profile.copyWith(birthDate: DateTime(1990, 4, 12), heightCm: 178),
    );
    await antes.logWeight(weightKg: 82, date: today());

    final despues = LocalRepository(await LocalStore.open(), onChanged: () {});

    expect(despues.needsOnboarding, isFalse);
  });
}
