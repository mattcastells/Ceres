// Que ninguna métrica cuente como incumplimiento un día anterior al primero
// que la persona registró.
//
// Este test existe por un número que se veía perfectamente bien estando mal.
// Alguien que instalaba la app el 18 abría el panel el 19 y leía:
//
//   Días con comidas: 1 de 30 · 29 sin registrar
//
// Los 29 no eran huecos: eran días en los que no tenía la app. El error no
// rompe nada, no tira ninguna excepción, y solo se nota si uno sabe cuándo
// empezó esa persona — que es exactamente la información que la pantalla no
// tenía.
//
// La regla que se prueba acá vale para toda métrica temporal, y el punto de
// tenerla en un solo lugar es que se pruebe una sola vez.
// Ver `docs/contexto-diario.md`.

import 'package:ceres/domain/calculations/tracking_window.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DateTime d(int y, int m, int day) => DateTime(y, m, day);

  group('el período efectivo', () {
    test('sin recorte, es el período pedido', () {
      final w = TrackingWindow(
        from: d(2026, 8, 1),
        to: d(2026, 8, 30),
        trackingSince: d(2026, 3, 15),
      );

      expect(w.effectiveFrom, d(2026, 8, 1));
      expect(w.effectiveDays, 30);
      expect(w.startedMidPeriod, isFalse);
    });

    test('cuenta creada a mitad de mes: arranca el día que arrancó ella', () {
      // El caso del enunciado: empezó el 18, mira el mes.
      final w = TrackingWindow(
        from: d(2026, 8, 1),
        to: d(2026, 8, 30),
        trackingSince: d(2026, 8, 18),
      );

      expect(w.effectiveFrom, d(2026, 8, 18));
      expect(w.effectiveDays, 13);
      expect(w.startedMidPeriod, isTrue);
    });

    test('cuenta creada a mitad de semana', () {
      // Semana del lunes 17 al domingo 23; empezó el jueves 20.
      final w = TrackingWindow(
        from: d(2026, 8, 17),
        to: d(2026, 8, 23),
        trackingSince: d(2026, 8, 20),
      );

      expect(w.effectiveDays, 4);
      // 4 de 4, no 4 de 7: no faltó ni un día.
      expect(w.coveragePct(4), 100);
      expect(w.coveragePct(2), 50);
    });

    test('sin ningún dato, no hay días que contar y no se divide por cero', () {
      final w = TrackingWindow(
        from: d(2026, 8, 1),
        to: d(2026, 8, 30),
      );

      expect(w.effectiveDays, 0);
      expect(w.isEmpty, isTrue);
      expect(w.startedMidPeriod, isFalse);
      // `null` y no 0: un porcentaje sobre cero días no es cero por ciento, es
      // una pregunta sin sentido, y un 0 % en pantalla se lee como reproche.
      expect(w.coveragePct(0), isNull);
      expect(w.days, isEmpty);
    });

    test('empezó después del final del período: cero, nunca negativo', () {
      // "La semana pasada" de alguien que empezó ayer.
      final w = TrackingWindow(
        from: d(2026, 8, 1),
        to: d(2026, 8, 7),
        trackingSince: d(2026, 8, 18),
      );

      expect(w.effectiveDays, 0);
      expect(w.coveragePct(0), isNull);
      expect(w.contains(d(2026, 8, 3)), isFalse);
    });

    test('un solo día: el período efectivo es 1, no 0', () {
      final w = TrackingWindow(
        from: d(2026, 8, 19),
        to: d(2026, 8, 19),
        trackingSince: d(2026, 8, 19),
      );

      expect(w.effectiveDays, 1);
      expect(w.contains(d(2026, 8, 19)), isTrue);
    });

    test('el cambio de mes no pierde ni suma un día', () {
      final w = TrackingWindow(
        from: d(2026, 7, 28),
        to: d(2026, 8, 3),
        trackingSince: d(2026, 7, 30),
      );

      expect(w.effectiveFrom, d(2026, 7, 30));
      expect(w.effectiveDays, 5); // 30, 31, 1, 2, 3
      expect(w.days.first, d(2026, 7, 30));
      expect(w.days.last, d(2026, 8, 3));
    });

    test('el cambio de año tampoco', () {
      final w = TrackingWindow(
        from: d(2025, 12, 28),
        to: d(2026, 1, 3),
        trackingSince: d(2025, 12, 31),
      );

      expect(w.effectiveDays, 4); // 31, 1, 2, 3
      expect(w.days.first, d(2025, 12, 31));
      expect(w.days.last, d(2026, 1, 3));
    });

    test('un año bisiesto cuenta el 29 de febrero', () {
      final w = TrackingWindow(
        from: d(2028, 2, 27),
        to: d(2028, 3, 1),
        trackingSince: d(2028, 2, 27),
      );

      expect(w.effectiveDays, 4); // 27, 28, 29, 1
    });

    test('el cambio de hora no corre el conteo', () {
      // En Argentina hoy no hay, pero `daysBetween` redondea justamente para
      // esto y el test lo fija: entre dos fechas con cambio de horario median
      // 23 h, y sin redondeo eso da 0,958 días.
      final w = TrackingWindow(
        from: d(2026, 3, 20),
        to: d(2026, 3, 30),
        trackingSince: d(2026, 3, 22),
      );

      expect(w.effectiveDays, 9);
    });

    test('la hora del trackingSince no cambia nada: se compara por día', () {
      final w = TrackingWindow(
        from: d(2026, 8, 1),
        to: d(2026, 8, 30),
        trackingSince: DateTime(2026, 8, 18, 23, 59),
      );

      expect(w.effectiveFrom, d(2026, 8, 18));
      expect(w.effectiveDays, 13);
      expect(w.contains(d(2026, 8, 18)), isTrue);
    });

    test('contains excluye lo anterior al inicio y lo posterior al fin', () {
      final w = TrackingWindow(
        from: d(2026, 8, 1),
        to: d(2026, 8, 30),
        trackingSince: d(2026, 8, 18),
      );

      expect(w.contains(d(2026, 8, 17)), isFalse);
      expect(w.contains(d(2026, 8, 18)), isTrue);
      expect(w.contains(d(2026, 8, 30)), isTrue);
      expect(w.contains(d(2026, 8, 31)), isFalse);
    });
  });

  group('el primer día registrado', () {
    test('es el más viejo de todos', () {
      expect(
        earliestTrackedDay(<DateTime>[
          d(2026, 8, 20),
          d(2026, 8, 3),
          d(2026, 8, 11),
        ]),
        d(2026, 8, 3),
      );
    });

    test('sin nada, es null y no una fecha inventada', () {
      expect(earliestTrackedDay(const <DateTime>[]), isNull);
    });

    test('descarta la hora', () {
      expect(
        earliestTrackedDay(<DateTime>[DateTime(2026, 8, 3, 21, 30)]),
        d(2026, 8, 3),
      );
    });
  });
}
