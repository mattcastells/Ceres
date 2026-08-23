// Sugerencias de comida: que ninguna se pase del presupuesto.
//
// Es la única promesa de la feature. "Te quedan 600 kcal, comé esto" con un
// plato de 800 no es una sugerencia imprecisa: es la app diciéndole a alguien
// que puede comer algo que no puede, con un número al lado que lo respalda.
//
// La comprobación está en dos lados —la Edge Function y el cliente— y esto
// prueba el segundo, que es el último antes de que el número llegue a los ojos
// de alguien. Duplicarla es a propósito: el servidor tiene que defenderse de un
// cliente viejo, y el cliente de un servidor que cambió.

import 'package:ceres/data/remote/meal_suggestions_client.dart';
import 'package:ceres/domain/models/meal_suggestion.dart';
import 'package:flutter_test/flutter_test.dart';

/// Un ingrediente que cierra por Atwater, para no pelear con esa validación
/// cuando lo que se prueba es otra cosa.
Map<String, dynamic> item({required String name, required int kcal}) =>
    <String, dynamic>{
      'name': name,
      'quantity': 100,
      'unit': 'g',
      'kcal': kcal,
      'proteinG': kcal / 8,
      'carbsG': kcal / 8,
      'fatG': kcal / 18,
    };

Map<String, dynamic> option({
  required String name,
  required int kcal,
  List<Map<String, dynamic>>? items,
  List<String>? steps,
}) => <String, dynamic>{
  'name': name,
  'kcal': kcal,
  'proteinG': 20,
  'carbsG': 30,
  'fatG': 10,
  'items': items ??
      <Map<String, dynamic>>[
        item(name: 'Uno', kcal: kcal ~/ 2),
        item(name: 'Otro', kcal: kcal - kcal ~/ 2),
      ],
  'steps': steps ?? <String>['Cortar todo', 'Cocinar diez minutos'],
};

Map<String, dynamic> respuesta(List<Map<String, dynamic>> options) =>
    <String, dynamic>{'options': options};

void main() {
  group('el presupuesto', () {
    test('una opción que se pasa no llega a la pantalla', () {
      final out = MealSuggestionsClient.parse(
        respuesta(<Map<String, dynamic>>[
          option(name: 'Entra', kcal: 500),
          option(name: 'No entra', kcal: 800),
        ]),
        budgetKcal: 600,
      );

      expect(out.map((o) => o.name), <String>['Entra']);
    });

    test('justo en el límite entra', () {
      final out = MealSuggestionsClient.parse(
        respuesta(<Map<String, dynamic>>[option(name: 'Justo', kcal: 600)]),
        budgetKcal: 600,
      );

      expect(out, hasLength(1));
      expect(out.single.kcal, 600);
    });

    test('el total mentiroso no pasa por la suma de los ingredientes', () {
      // El modelo dice 500 —que entra— pero sus ingredientes suman 900. Uno de
      // los dos números miente y no hay forma de saber cuál, así que se
      // descarta entera en vez de mostrar el que conviene.
      final out = MealSuggestionsClient.parse(
        respuesta(<Map<String, dynamic>>[
          option(
            name: 'Miente',
            kcal: 500,
            items: <Map<String, dynamic>>[
              item(name: 'Uno', kcal: 450),
              item(name: 'Otro', kcal: 450),
            ],
          ),
        ]),
        budgetKcal: 600,
      );

      expect(out, isEmpty);
    });

    test('ninguna que entre deja la lista vacía, no un error', () {
      final out = MealSuggestionsClient.parse(
        respuesta(<Map<String, dynamic>>[
          option(name: 'Grande', kcal: 900),
          option(name: 'Más grande', kcal: 1200),
        ]),
        budgetKcal: 600,
      );

      expect(out, isEmpty);
    });
  });

  group('lo que no es una sugerencia', () {
    test('sin ingredientes no se muestra', () {
      final out = MealSuggestionsClient.parse(
        respuesta(<Map<String, dynamic>>[
          option(name: 'Solo un título', kcal: 400, items: <Map<String, dynamic>>[]),
        ]),
        budgetKcal: 600,
      );

      expect(out, isEmpty);
    });

    test('sin receta tampoco', () {
      // Sin pasos es una lista de ingredientes, no un plato. La feature promete
      // la receta; media promesa no se muestra.
      final out = MealSuggestionsClient.parse(
        respuesta(<Map<String, dynamic>>[
          option(name: 'Sin pasos', kcal: 400, steps: <String>[]),
        ]),
        budgetKcal: 600,
      );

      expect(out, isEmpty);
    });

    test('una respuesta que no se entiende no rompe: da vacío', () {
      expect(MealSuggestionsClient.parse(null, budgetKcal: 600), isEmpty);
      expect(MealSuggestionsClient.parse('cualquier cosa', budgetKcal: 600), isEmpty);
      expect(
        MealSuggestionsClient.parse(<String, dynamic>{}, budgetKcal: 600),
        isEmpty,
      );
      expect(
        MealSuggestionsClient.parse(
          <String, dynamic>{'options': 'no es una lista'},
          budgetKcal: 600,
        ),
        isEmpty,
      );
    });

    test('una opción rota no se lleva puestas a las buenas', () {
      final out = MealSuggestionsClient.parse(
        <String, dynamic>{
          'options': <dynamic>[
            'esto no es un objeto',
            option(name: 'Buena', kcal: 400),
          ],
        },
        budgetKcal: 600,
      );

      expect(out.map((o) => o.name), <String>['Buena']);
    });
  });

  group('lo que sí llega', () {
    test('trae ingredientes y pasos completos', () {
      final out = MealSuggestionsClient.parse(
        respuesta(<Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'Milanesa de pollo con ensalada',
            'kcal': 520,
            'proteinG': 45.4,
            'carbsG': 30.2,
            'fatG': 22.1,
            'minutes': 25,
            'items': <Map<String, dynamic>>[
              item(name: 'Pechuga de pollo', kcal: 260),
              item(name: 'Pan rallado', kcal: 160),
              item(name: 'Ensalada mixta', kcal: 100),
            ],
            'steps': <String>[
              'Aplastar la pechuga y salpimentar',
              'Pasar por huevo y pan rallado',
              'Horno 20 minutos a 200 grados',
            ],
          },
        ]),
        budgetKcal: 600,
      );

      expect(out, hasLength(1));
      final o = out.single;
      expect(o.name, 'Milanesa de pollo con ensalada');
      expect(o.items, hasLength(3));
      expect(o.items.first.name, 'Pechuga de pollo');
      expect(o.steps, hasLength(3));
      expect(o.minutes, 25);
      // Cuánto del día ocupa, para la barra.
      expect(o.fractionOf(600), closeTo(0.866, 0.01));
    });

    test('la fracción nunca se pasa de uno ni se va abajo de cero', () {
      const o = MealSuggestion(
        name: 'x',
        kcal: 900,
        proteinG: 0,
        carbsG: 0,
        fatG: 0,
        items: <SuggestedItem>[],
        steps: <String>[],
      );
      expect(o.fractionOf(600), 1.0);
      // Sin presupuesto no hay fracción que dibujar, y dividir por cero daría
      // infinito: la barra quedaría llena justo cuando no hay nada.
      expect(o.fractionOf(0), 0.0);
    });
  });
}
