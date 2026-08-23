// La tabla de composición de alimentos argentinos que viaja en el APK.
//
// Se extrajo de los PDF de ARGENFOODS (UNLu) con un parser, y un parser sobre
// tablas de PDF puede tener éxito con las columnas corridas: el primer intento
// dio "Aceite de oliva, 100 g de proteína". Un número así, cargado en el
// historial de alguien, es peor que no tener el alimento.
//
// Estos tests son el candado. No prueban el parser —ya corrió— sino **el
// archivo que se publica**, que es lo que termina en el teléfono.

import 'dart:convert';
import 'dart:io';

import 'package:ceres/domain/enums/enums.dart';
import 'package:ceres/domain/models/food.dart';
import 'package:flutter_test/flutter_test.dart';

List<Food> _cargar() {
  final raw = File('assets/data/argenfoods.json').readAsStringSync();
  return (jsonDecode(raw) as List<dynamic>)
      .map((e) => Food.fromJson(e as Map<String, dynamic>))
      .toList();
}

void main() {
  late List<Food> foods;

  setUpAll(() => foods = _cargar());

  test('el archivo tiene una cantidad razonable de alimentos', () {
    expect(foods.length, greaterThan(200));
  });

  test('todos declaran ARGENFOODS como fuente', () {
    for (final f in foods) {
      expect(f.source, FoodSource.argenfoods, reason: f.name);
    }
  });

  test('no hay ids repetidos', () {
    final ids = foods.map((f) => f.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
  });

  test('todos vienen expresados por 100 g', () {
    for (final f in foods) {
      expect(f.servingSize, 100, reason: f.name);
      expect(f.servingUnit, 'g', reason: f.name);
    }
  });

  group('los números cierran', () {
    test('las calorías coinciden con los macros (Atwater 4/4/9)', () {
      // Es el control que atrapó las columnas corridas. Si alguien regenera el
      // archivo con un parser roto, este test lo frena antes de publicarlo.
      for (final f in foods) {
        final esperado = 4 * f.proteinG + 4 * f.carbsG + 9 * f.fatG;
        final delta = (f.kcal - esperado).abs();
        expect(
          delta <= 20 || delta <= f.kcal * 0.1,
          isTrue,
          reason: '${f.name}: ${f.kcal} kcal declaradas contra '
              '${esperado.toStringAsFixed(0)} calculadas',
        );
      }
    });

    test('los macros de 100 g no suman más de 100 g', () {
      for (final f in foods) {
        expect(
          f.proteinG + f.carbsG + f.fatG,
          lessThanOrEqualTo(101),
          reason: f.name,
        );
      }
    });

    test('ningún valor es negativo ni absurdo', () {
      for (final f in foods) {
        expect(f.kcal, inInclusiveRange(0, 900), reason: f.name);
        expect(f.proteinG, inInclusiveRange(0, 100), reason: f.name);
        expect(f.carbsG, inInclusiveRange(0, 100), reason: f.name);
        expect(f.fatG, inInclusiveRange(0, 100), reason: f.name);
      }
    });
  });

  group('controles puntuales contra valores conocidos', () {
    Food buscar(String needle) => foods.firstWhere(
      (f) => f.name.toLowerCase().contains(needle.toLowerCase()),
      orElse: () => throw StateError('no está: $needle'),
    );

    test('el aceite es grasa pura', () {
      // El caso que delató el parser roto: daba proteína 100 y carbos 71.
      final aceite = buscar('Aceite de oliva');
      expect(aceite.kcal, greaterThan(850));
      expect(aceite.fatG, greaterThan(95));
      expect(aceite.proteinG, 0);
      expect(aceite.carbsG, 0);
    });

    test('el arroz crudo es casi todo carbohidrato', () {
      final arroz = buscar('Arroz, grano, blanco');
      expect(arroz.carbsG, greaterThan(70));
      expect(arroz.fatG, lessThan(2));
    });

    test('el pollo es proteína sin carbohidratos', () {
      final pollo = buscar('Pollo, asado al horno');
      expect(pollo.proteinG, greaterThan(20));
      expect(pollo.carbsG, 0);
    });

    test('una fruta tiene pocas calorías y nada de grasa', () {
      final manzana = buscar('Manzana, pulpa');
      expect(manzana.kcal, lessThan(100));
      expect(manzana.fatG, lessThan(2));
    });
  });
}
