// El contexto del día: alcohol y días de enfermedad.
//
// Lo que se fija acá es sobre todo lo que **no** tiene que pasar: que marcar un
// día de enfermedad no le mueva un número a nadie, y que las calorías del
// alcohol no se cuelen en las de las comidas. Las dos features existen para dar
// contexto, y una que además corrija los cálculos sería la app opinando sobre
// una semana que no vio. Ver `docs/contexto-diario.md`.

import 'package:ceres/domain/calculations/alcohol.dart';
import 'package:ceres/domain/models/alcohol.dart';
import 'package:ceres/domain/models/day_marker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DateTime d(int y, int m, int day) => DateTime(y, m, day);

  AlcoholLog log({
    required DateTime date,
    required DrinkType type,
    double quantity = 1,
    int volumeMl = 500,
    double abvPct = 5,
    DateTime? deletedAt,
  }) => AlcoholLog(
    id: '$date-$type-$quantity',
    localDate: date,
    type: type,
    quantity: quantity,
    volumeMl: volumeMl,
    abvPct: abvPct,
    loggedAt: date,
    updatedAt: date,
    deletedAt: deletedAt,
  );

  group('unidades de bebida estándar', () {
    test('la UBE argentina son 10 g de etanol, no los 14 de EE.UU.', () {
      // 100 ml al 12,67 % ≈ 10 g de etanol ≈ 1 UBE.
      expect(gramosPorUBE, 10);
      expect(
        standardDrinks(volumeMl: 100, abvPct: 12.67),
        closeTo(1, 0.01),
      );
    });

    test('una lata de cerveza y una medida de whisky son comparables', () {
      // Es el punto entero de la unidad: en mililitros, 473 y 45 no se pueden
      // comparar, y un gráfico en mililitros diría que la cerveza es diez veces
      // más alcohol.
      final lata = standardDrinks(volumeMl: 473, abvPct: 5);
      final medida = standardDrinks(volumeMl: 45, abvPct: 40);

      expect(lata, closeTo(1.87, 0.02));
      expect(medida, closeTo(1.42, 0.02));
      expect((lata - medida).abs(), lessThan(0.6));
    });

    test('cero grados son cero tragos', () {
      expect(standardDrinks(volumeMl: 500, abvPct: 0), 0);
    });
  });

  group('calorías del alcohol', () {
    test('suma el etanol y los hidratos, que son la mitad de una cerveza', () {
      // Solo con el etanol, una lata daría ~131 kcal en vez de ~199, y el error
      // se acumularía justo en la bebida que más se toma.
      final soloEtanol = ethanolGrams(volumeMl: 473, abvPct: 5) * 7.1;
      final total = alcoholKcal(
        volumeMl: 473,
        abvPct: 5,
        type: DrinkType.beer,
      );

      expect(soloEtanol, closeTo(132, 2));
      expect(total, closeTo(200, 5));
    });

    test('un destilado no tiene hidratos, pero tiene calorías', () {
      final total = alcoholKcal(
        volumeMl: 45,
        abvPct: 40,
        type: DrinkType.spirits,
      );
      expect(total, closeTo(101, 3));
      expect(total, greaterThan(0));
    });

    test('alcohol sin calorías asociadas: 0 % da 0 kcal en un destilado', () {
      expect(
        alcoholKcal(volumeMl: 200, abvPct: 0, type: DrinkType.spirits),
        0,
      );
    });

    test('una bebida sin alcohol pero con azúcar sigue teniendo calorías', () {
      // El caso borde al revés: la cerveza sin alcohol no aporta etanol pero sí
      // hidratos, y devolver 0 escondería 30 kcal por lata.
      expect(
        alcoholKcal(volumeMl: 330, abvPct: 0, type: DrinkType.beer),
        greaterThan(0),
      );
    });
  });

  group('el consumo de un día', () {
    test('suma tipos distintos en la misma unidad', () {
      final dia = AlcoholDay.group(<AlcoholLog>[
        log(date: d(2026, 8, 15), type: DrinkType.wine, volumeMl: 150,
            abvPct: 13, quantity: 2),
        log(date: d(2026, 8, 15), type: DrinkType.beer, volumeMl: 473,
            abvPct: 5),
      ]);

      expect(dia, hasLength(1));
      expect(dia.first.standardDrinks, closeTo(5.0, 0.2));
      expect(dia.first.entries, hasLength(2));
    });

    test('lo borrado no cuenta', () {
      final dia = AlcoholDay.group(<AlcoholLog>[
        log(date: d(2026, 8, 15), type: DrinkType.beer),
        log(
          date: d(2026, 8, 15),
          type: DrinkType.wine,
          deletedAt: d(2026, 8, 16),
        ),
      ]);

      expect(dia.first.entries, hasLength(1));
    });

    test('los días vuelven ordenados, del más viejo al más nuevo', () {
      final dias = AlcoholDay.group(<AlcoholLog>[
        log(date: d(2026, 8, 20), type: DrinkType.beer),
        log(date: d(2026, 8, 3), type: DrinkType.wine),
        log(date: d(2026, 8, 11), type: DrinkType.cider),
      ]);

      expect(
        dias.map((x) => x.date).toList(),
        <DateTime>[d(2026, 8, 3), d(2026, 8, 11), d(2026, 8, 20)],
      );
    });

    test('sin nada, no hay días: no se inventa un cero', () {
      expect(AlcoholDay.group(const <AlcoholLog>[]), isEmpty);
    });

    test('media copa se puede registrar', () {
      final dia = AlcoholDay.group(<AlcoholLog>[
        log(
          date: d(2026, 8, 15),
          type: DrinkType.wine,
          volumeMl: 150,
          abvPct: 13,
          quantity: 0.5,
        ),
      ]);
      expect(dia.first.standardDrinks, closeTo(0.77, 0.05));
    });
  });

  group('las marcas del día', () {
    test('la severidad solo vive en los días de enfermedad', () {
      // La base lo hace cumplir con un `check`; el modelo no lo deja entrar por
      // la otra puerta, que es la de un documento local viejo o corrupto.
      final rest = DayMarker.fromJson(<String, dynamic>{
        'id': 'x',
        'localDate': '2026-08-15',
        'kind': 'rest',
        'severity': 3,
        'updatedAt': '2026-08-15T00:00:00.000',
      });

      expect(rest.kind, DayMarkerKind.rest);
      expect(rest.severity, isNull);
    });

    test('un día puede ser de descanso y de enfermedad a la vez', () {
      // Es el caso interesante y por eso el único de la tabla es (día, tipo) y
      // no el día solo.
      final marcas = <DayMarker>[
        DayMarker(
          id: 'a',
          localDate: d(2026, 8, 15),
          kind: DayMarkerKind.rest,
          updatedAt: d(2026, 8, 15),
        ),
        DayMarker(
          id: 'b',
          localDate: d(2026, 8, 15),
          kind: DayMarkerKind.sick,
          severity: SickSeverity.moderate,
          updatedAt: d(2026, 8, 15),
        ),
      ];

      expect(marcas.where((m) => m.kind == DayMarkerKind.rest), hasLength(1));
      expect(marcas.where((m) => m.kind == DayMarkerKind.sick), hasLength(1));
    });

    test('ida y vuelta por JSON conserva todo', () {
      final marca = DayMarker(
        id: 'a',
        localDate: d(2026, 8, 15),
        kind: DayMarkerKind.sick,
        severity: SickSeverity.severe,
        note: 'Fiebre',
        tags: const <String>['fiebre', 'garganta'],
        updatedAt: DateTime(2026, 8, 15, 10),
      );

      final vuelta = DayMarker.fromJson(marca.toJson());

      expect(vuelta.kind, DayMarkerKind.sick);
      expect(vuelta.severity, SickSeverity.severe);
      expect(vuelta.note, 'Fiebre');
      expect(vuelta.tags, <String>['fiebre', 'garganta']);
    });

    test('un tipo desconocido no rompe: cae en descanso', () {
      final marca = DayMarker.fromJson(<String, dynamic>{
        'id': 'x',
        'localDate': '2026-08-15',
        'kind': 'vacaciones',
        'updatedAt': '2026-08-15T00:00:00.000',
      });
      expect(marca.kind, DayMarkerKind.rest);
    });

    test('quitar la marca deja lápida, no la borra', () {
      final marca = DayMarker(
        id: 'a',
        localDate: d(2026, 8, 15),
        kind: DayMarkerKind.sick,
        updatedAt: d(2026, 8, 15),
      );
      final borrada = marca.copyWith(deletedAt: DateTime(2026, 8, 16));

      expect(borrada.isDeleted, isTrue);
      expect(borrada.id, marca.id);
    });
  });
}
