// La barrera del repositorio: con un plan sin IA, ningún pedido de IA sale.
//
// Es la segunda de tres (botones, repositorio, servidor). Existe para lo que
// no pasa por un botón —un enlace, una pantalla que reintenta sola—, y lo que
// se prueba es que frena **antes** de cualquier otra cosa: antes de mirar si
// hay servidor, antes de subir una foto, antes de validar los datos. Un 402
// que llega después de subir la foto es una foto subida para nada.

import 'package:ceres/core/error/app_error.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/domain/enums/enums.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Matcher get _planRequired => throwsA(
  isA<AppError>().having((e) => e.code, 'code', ApiErrorCode.planRequired),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = await LocalStore.open();
    repo = LocalRepository(store, onChanged: () {});
  });

  test('sin enlazar el plan, la IA está permitida (modo local)', () async {
    // En modo local `analyze` devuelve el resultado fijo de siempre: que
    // conteste es la prueba de que la barrera no se metió.
    final analysis = await repo.analyze(photoPath: '/tmp/foto.jpg');
    expect(analysis.items, isNotEmpty);
  });

  group('con un plan sin IA', () {
    setUp(() => repo.aiAllowed = () => false);

    test('analizar una foto', () {
      expect(repo.analyze(photoPath: '/tmp/foto.jpg'), _planRequired);
    });

    test('describir por texto', () {
      expect(repo.analyzeText(description: 'dos empanadas'), _planRequired);
    });

    test('recalcular', () {
      expect(
        repo.recalculate(items: const [], instruction: 'le falta el pan'),
        _planRequired,
      );
    });

    test('¿Qué como?', () {
      // Con un presupuesto que igual sería rechazado por bajo: el plan va
      // primero, porque es el motivo real.
      expect(repo.suggestMeals(remainingKcal: 50), _planRequired);
    });

    test('el objetivo calórico con IA', () {
      expect(
        repo.proposeCalorieTarget(
          weightKg: 70,
          goalType: GoalType.maintain,
          formulaTarget: 2000,
        ),
        _planRequired,
      );
    });
  });

  test('el plan se lee en cada pedido, no una vez', () async {
    var allowed = false;
    repo.aiAllowed = () => allowed;
    await expectLater(repo.analyze(photoPath: '/tmp/a.jpg'), _planRequired);

    // La compra simulada cambia el plan en el acto: el próximo pedido pasa.
    allowed = true;
    final analysis = await repo.analyze(photoPath: '/tmp/a.jpg');
    expect(analysis.items, isNotEmpty);
  });
}
