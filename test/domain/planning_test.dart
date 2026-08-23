import 'package:ceres/core/utils/dates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('se puede planificar hasta tres días adelante', () {
    final hoy = today();
    for (var d = 0; d <= maxPlanningDays; d++) {
      expect(
        isPlannable(hoy.add(Duration(days: d))),
        isTrue,
        reason: 'el día +$d tendría que poder planificarse',
      );
    }
  });

  test('el cuarto día ya queda afuera', () {
    expect(isPlannable(today().add(const Duration(days: 4))), isFalse);
  });

  test('el pasado siempre se puede cargar', () {
    expect(isPlannable(today().subtract(const Duration(days: 30))), isTrue);
  });
}
