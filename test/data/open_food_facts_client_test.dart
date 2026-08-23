// El parser del catálogo externo, con respuestas fijas: los tests no salen a
// la red. Las respuestas son recortes reales de Open Food Facts.

import 'dart:convert';

import 'package:ceres/core/error/app_error.dart';
import 'package:ceres/data/remote/open_food_facts_client.dart';
import 'package:ceres/domain/enums/enums.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _product({
  required String code,
  required String name,
  String? brands,
  String? servingSize,
  double? kcal100,
  double proteins = 5,
  double carbs = 6.25,
  double fat = 3.15,
}) => jsonEncode(<String, dynamic>{
  'code': code,
  'product_name': name,
  if (brands != null) 'brands': brands,
  if (servingSize != null) 'serving_size': servingSize,
  'nutriments': <String, dynamic>{
    if (kcal100 != null) 'energy-kcal_100g': kcal100,
    'proteins_100g': proteins,
    'carbohydrates_100g': carbs,
    'fat_100g': fat,
    'sodium_100g': 0.05,
  },
});

OpenFoodFactsClient _clientReturning(String body, {int status = 200}) =>
    OpenFoodFactsClient(
      client: MockClient(
        (request) async => http.Response(
          body,
          status,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        ),
      ),
    );

void main() {
  group('búsqueda', () {
    test('mapea un producto y reescala los nutrientes a la porción', () async {
      final client = _clientReturning(
        '{"hits":[${_product(
          code: '7791337006355',
          name: 'Yogurisimo sabor Natural',
          brands: 'La serenisima',
          servingSize: '200 g',
          kcal100: 81.5,
          proteins: 7,
        )}]}',
      );

      final results = await client.search('yogur');
      expect(results, hasLength(1));

      final food = results.first;
      expect(food.id, 'off:7791337006355');
      expect(food.source, FoodSource.off);
      expect(food.brand, 'La serenisima');
      expect(food.barcode, '7791337006355');
      // 81,5 kcal por 100 g en una porción de 200 g.
      expect(food.servingSize, 200);
      expect(food.kcal, 163);
      expect(food.proteinG, closeTo(14, 0.001));
      // OFF publica el sodio en gramos: 0,05 g/100 g → 100 mg por porción.
      expect(food.sodiumMg, closeTo(100, 0.001));
    });

    test('descarta lo que no tiene calorías: no sirve para registrar', () async {
      final client = _clientReturning(
        '{"hits":[${_product(code: '1', name: 'Sin datos')}]}',
      );
      expect(await client.search('lo que sea'), isEmpty);
    });

    test('descarta lo que no tiene nombre', () async {
      final client = _clientReturning(
        '{"hits":[{"code":"2","nutriments":{"energy-kcal_100g":50}}]}',
      );
      expect(await client.search('lo que sea'), isEmpty);
    });

    test('se queda con la primera marca cuando vienen varias', () async {
      final client = _clientReturning(
        '{"hits":[${_product(
          code: '3',
          name: 'Galletitas',
          brands: 'Bagley, Arcor',
          kcal100: 450,
        )}]}',
      );
      expect((await client.search('galletitas')).first.brand, 'Bagley');
    });

    test('acepta la marca como lista, que es lo que manda el buscador', () async {
      final client = _clientReturning(
        '{"hits":[{"code":"5","product_name":"Calci Avena",'
        '"brands":["Santiveri","Calci Avena"],'
        '"nutriments":{"energy-kcal_100g":45}}]}',
      );
      expect((await client.search('avena')).first.brand, 'Santiveri');
    });

    test('no repite un producto que viene en las dos consultas', () async {
      // La búsqueda pide primero con filtro de país y después global: el
      // mismo código no puede aparecer dos veces.
      final client = _clientReturning(
        '{"hits":[${_product(code: '9', name: 'Avena', kcal100: 380)}]}',
      );
      final results = await client.search('avena');
      expect(results, hasLength(1));
    });
  });

  group('porción de referencia', () {
    Future<double> servingFor(String? raw) async {
      final client = _clientReturning(
        '{"hits":[${_product(
          code: '4',
          name: 'Producto',
          servingSize: raw,
          kcal100: 100,
        )}]}',
      );
      return (await client.search('x')).first.servingSize;
    }

    test('lee los formatos que publica OFF', () async {
      expect(await servingFor('200 g'), 200);
      expect(await servingFor('190.0g'), 190);
      expect(await servingFor('1 portion (140 g)'), 140);
      expect(await servingFor('250 ml'), 250);
    });

    test('cae a 100 g cuando el dato no sirve', () async {
      expect(await servingFor(null), 100);
      expect(await servingFor('una porción'), 100);
      // Un valor absurdo se descarta en lugar de arrastrar el error.
      expect(await servingFor('99999 g'), 100);
    });
  });

  group('código de barras', () {
    test('devuelve el alimento cuando el producto existe', () async {
      final client = _clientReturning(
        '{"status":1,"product":${_product(
          code: '7791337006355',
          name: 'Yogurisimo',
          servingSize: '200 g',
          kcal100: 81.5,
        )}}',
      );
      final food = await client.byBarcode('7791337006355');
      expect(food, isNotNull);
      expect(food!.kcal, 163);
    });

    test('devuelve null cuando el código no está cargado', () async {
      final client = _clientReturning(
        '{"code":"0000","status":0,"status_verbose":"product not found"}',
      );
      expect(await client.byBarcode('0000'), isNull);
    });
  });

  group('errores del proveedor', () {
    test('un 500 se traduce a un AppError explicable', () async {
      final client = _clientReturning('{}', status: 500);
      await expectLater(
        client.search('yogur'),
        throwsA(
          isA<AppError>().having(
            (e) => e.code,
            'code',
            ApiErrorCode.upstreamFailed,
          ),
        ),
      );
    });

    test('un 429 avisa que hay demasiadas consultas', () async {
      final client = _clientReturning('{}', status: 429);
      await expectLater(
        client.search('yogur'),
        throwsA(
          isA<AppError>().having(
            (e) => e.code,
            'code',
            ApiErrorCode.rateLimited,
          ),
        ),
      );
    });

    test('una respuesta ilegible no rompe la app', () async {
      final client = _clientReturning('no soy json');
      await expectLater(
        client.search('yogur'),
        throwsA(
          isA<AppError>().having(
            (e) => e.code,
            'code',
            ApiErrorCode.upstreamTimeout,
          ),
        ),
      );
    });
  });
}
