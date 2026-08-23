// El título de una comida resume lo que tiene adentro. Antes era el nombre del
// primer ítem cargado, así que una milanesa con puré y ensalada se llamaba
// "Puré de papa" si el puré había entrado primero — y dos comidas distintas
// quedaban con el mismo nombre por compartir el primer ingrediente.

import 'package:ceres/core/utils/dates.dart';
import 'package:ceres/domain/calculations/meal_title.dart';
import 'package:ceres/domain/enums/enums.dart';
import 'package:ceres/domain/models/meal.dart';
import 'package:flutter_test/flutter_test.dart';

MealItem _item(String name) => MealItem(
  id: name,
  name: name,
  quantity: 1,
  unit: 'porcion',
  kcal: 100,
  proteinG: 5,
  carbsG: 10,
  fatG: 3,
  position: 0,
);

Meal _meal({required List<String> items, String? name}) => Meal(
  id: 'm1',
  slot: MealSlot.lunch,
  eatenAt: DateTime(2026, 8, 12, 13),
  localDate: dateOnly(DateTime(2026, 8, 12)),
  name: name,
  items: <MealItem>[for (final i in items) _item(i)],
  source: MealSource.manual,
  createdAt: DateTime(2026, 8, 12),
  updatedAt: DateTime(2026, 8, 12),
);

void main() {
  group('MealTitle', () {
    test('un solo ítem se llama como ese ítem', () {
      expect(MealTitle.fromNames(<String>['Milanesa']), 'Milanesa');
    });

    test('dos ítems se unen con "y"', () {
      expect(
        MealTitle.fromNames(<String>['Milanesa', 'Puré de papa']),
        'Milanesa y puré de papa',
      );
    });

    test('de tres para arriba se cuenta la cola', () {
      expect(
        MealTitle.fromNames(<String>[
          'Milanesa',
          'Puré de papa',
          'Ensalada',
          'Pan',
        ]),
        'Milanesa, puré de papa y 2 más',
      );
    });

    test('la aclaración del catálogo no entra en el título', () {
      expect(
        MealTitle.fromNames(<String>['Arroz blanco, cocido sin sal']),
        'Arroz blanco',
      );
      expect(MealTitle.fromNames(<String>['Pan (integral)']), 'Pan');
    });

    test('el mismo alimento repetido se nombra una vez', () {
      expect(
        MealTitle.fromNames(<String>['Pan', 'pan', 'Queso']),
        'Pan y queso',
      );
    });

    test('sin nombres útiles devuelve vacío', () {
      expect(MealTitle.fromNames(<String>['', '   ']), '');
    });

    test('un título largo se corta y no crece sin límite', () {
      final title = MealTitle.fromNames(<String>['a' * 200, 'b' * 200]);
      expect(title.length, lessThanOrEqualTo(MealTitle.maxLength));
    });
  });

  group('Meal.title', () {
    test('sin nombre propio se deriva de los ítems', () {
      expect(
        _meal(items: <String>['Milanesa', 'Puré de papa']).title,
        'Milanesa y puré de papa',
      );
    });

    test('el nombre propio gana sobre la derivación', () {
      expect(
        _meal(items: <String>['Milanesa'], name: 'Cumpleaños de Ana').title,
        'Cumpleaños de Ana',
      );
    });

    test('un nombre en blanco no gana: se deriva igual', () {
      expect(_meal(items: <String>['Milanesa'], name: '  ').title, 'Milanesa');
    });

    test('una comida sin ítems se llama como su momento del día', () {
      expect(_meal(items: <String>[]).title, MealSlot.lunch.label);
    });

    test('agregar un ítem actualiza el título derivado', () {
      final meal = _meal(items: <String>['Milanesa']);
      final conPure = meal.copyWith(
        items: <MealItem>[...meal.items, _item('Puré de papa')],
      );
      expect(conPure.title, 'Milanesa y puré de papa');
    });
  });
}
