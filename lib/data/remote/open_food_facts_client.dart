import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/error/app_error.dart';
import '../../domain/enums/enums.dart';
import '../../domain/models/food.dart';

/// Cliente de Open Food Facts (12-external-integrations.md §4).
///
/// Es la única fuente de catálogo que no necesita clave: la API es pública y
/// solo pide identificarse con un `User-Agent` propio, como manda su política
/// de uso. El dominio `ar.` prioriza productos del país.
///
/// USDA FoodData Central queda para cuando exista la Edge Function
/// `food-search`: su clave no puede vivir en el cliente.
class OpenFoodFactsClient {
  OpenFoodFactsClient({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  static const String _userAgent = 'Ceres/1.0 (Android)';

  /// Búsqueda por texto: el servicio moderno de OFF. El `cgi/search.pl`
  /// clásico devuelve 503 con frecuencia y no sirve para una app.
  static const String _searchHost = 'search.openfoodfacts.org';

  /// Consulta por código: la API de producto sigue viviendo acá.
  static const String _worldHost = 'world.openfoodfacts.org';

  /// Los productos cargados en Argentina van primero: son los que alguien
  /// tiene realmente en la alacena.
  static const String _countryFilter = 'countries_tags:"en:argentina"';

  /// Timeout del proveedor: pasados 6 s se sirven solo los resultados locales
  /// y se muestra el banner de reintento (F-04).
  static const Duration timeout = Duration(seconds: 6);

  static const String _fields =
      'code,product_name,product_name_es,brands,serving_size,nutriments';

  /// Busca primero entre los productos de Argentina y, si vuelve con poco,
  /// completa con el catálogo global.
  Future<List<Food>> search(String query, {int limit = 20}) async {
    final local = await _searchWith('$query $_countryFilter', limit);
    if (local.length >= 5) return local;

    final global = await _searchWith(query, limit);
    final byId = <String, Food>{for (final food in local) food.id: food};
    for (final food in global) {
      byId.putIfAbsent(food.id, () => food);
    }
    return byId.values.toList();
  }

  Future<List<Food>> _searchWith(String query, int limit) async {
    final uri = Uri.https(_searchHost, '/search', <String, String>{
      'q': query,
      'page_size': '$limit',
      'fields': _fields,
      'langs': 'es',
    });

    final body = _decode(await _get(uri));
    final hits = body['hits'] as List<dynamic>? ?? <dynamic>[];

    return hits
        .map((raw) => _toFood(raw as Map<String, dynamic>))
        .whereType<Food>()
        .toList();
  }

  /// Búsqueda por código de barras (EAN). Usa el dominio mundial: un producto
  /// puede estar cargado en cualquier país.
  Future<Food?> byBarcode(String ean) async {
    final uri = Uri.https(_worldHost, '/api/v2/product/$ean.json', <String,
        String>{'fields': _fields});

    final body = _decode(await _get(uri));
    if (body['status'] != 1) return null;

    final product = body['product'] as Map<String, dynamic>?;
    return product == null ? null : _toFood(product);
  }

  /// Una respuesta ilegible no puede llegar como excepción cruda a la UI:
  /// se traduce al mismo error que un fallo del proveedor.
  Map<String, dynamic> _decode(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } on Object {
      throw const AppError(
        code: ApiErrorCode.upstreamTimeout,
        message: 'No pudimos leer la respuesta del catálogo online. Reintentar',
      );
    }
  }

  Future<String> _get(Uri uri) async {
    try {
      final response = await _client
          .get(uri, headers: const <String, String>{'User-Agent': _userAgent})
          .timeout(timeout);

      if (response.statusCode == 429) {
        throw const AppError(
          code: ApiErrorCode.rateLimited,
          message: 'El catálogo online está recibiendo muchas consultas. '
              'Probá de nuevo en un rato.',
        );
      }
      if (response.statusCode != 200) {
        throw const AppError(
          code: ApiErrorCode.upstreamFailed,
          message: 'No pudimos consultar el catálogo online.',
        );
      }
      return utf8.decode(response.bodyBytes);
    } on AppError {
      rethrow;
    } on Object {
      throw const AppError(
        code: ApiErrorCode.upstreamTimeout,
        message: 'No pudimos consultar el catálogo online. Reintentar',
      );
    }
  }

  /// Convierte un producto de OFF en un [Food].
  ///
  /// OFF publica los nutrientes **por 100 g**; el modelo guarda los valores
  /// por porción de referencia, así que se reescalan.
  Food? _toFood(Map<String, dynamic> product) {
    final code = product['code'] as String?;
    final name =
        (product['product_name_es'] as String?)?.trim().isNotEmpty ?? false
        ? (product['product_name_es'] as String).trim()
        : (product['product_name'] as String?)?.trim();
    if (code == null || name == null || name.isEmpty) return null;
    // Hay fichas donde el nombre es el propio código de barras: no le dice
    // nada a nadie, así que no se ofrece.
    if (RegExp(r'^\d+$').hasMatch(name)) return null;

    final nutriments = product['nutriments'] as Map<String, dynamic>?;
    if (nutriments == null) return null;

    final kcal100 = _num(nutriments['energy-kcal_100g']);
    // Sin calorías no sirve para registrar: se descarta antes de mostrarlo.
    if (kcal100 == null || kcal100 <= 0) return null;

    final servingGrams = _parseServingGrams(product['serving_size'] as String?);
    final factor = servingGrams / 100;

    // `brands` viene como lista en el buscador y como texto separado por comas
    // en la API de producto.
    final brand = switch (product['brands']) {
      final List<dynamic> list when list.isNotEmpty =>
        list.first.toString().trim(),
      final String text when text.trim().isNotEmpty =>
        text.split(',').first.trim(),
      _ => null,
    };

    return Food(
      id: 'off:$code',
      name: name,
      brand: brand == null || brand.isEmpty ? null : brand,
      barcode: code,
      source: FoodSource.off,
      externalId: code,
      servingSize: servingGrams,
      servingUnit: 'g',
      kcal: (kcal100 * factor).round(),
      proteinG: (_num(nutriments['proteins_100g']) ?? 0) * factor,
      carbsG: (_num(nutriments['carbohydrates_100g']) ?? 0) * factor,
      fatG: (_num(nutriments['fat_100g']) ?? 0) * factor,
      fiberG: _scaled(nutriments['fiber_100g'], factor),
      sugarG: _scaled(nutriments['sugars_100g'], factor),
      // OFF publica el sodio en gramos.
      sodiumMg: _scaled(nutriments['sodium_100g'], factor * 1000),
      portions: <FoodPortion>[
        FoodPortion(label: 'Porción (${servingGrams.round()} g)', grams: servingGrams),
        const FoodPortion(label: '100 g', grams: 100),
      ],
    );
  }

  static double? _num(Object? value) => switch (value) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s),
    _ => null,
  };

  static double? _scaled(Object? value, double factor) {
    final parsed = _num(value);
    return parsed == null ? null : parsed * factor;
  }

  /// `"1 portion (140 g)"` · `"200 g"` · `"190.0g"` → gramos.
  /// Sin dato utilizable, la porción de referencia son 100 g.
  static double _parseServingGrams(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 100;

    final match = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*(g|gr|ml)\b',
      caseSensitive: false,
    ).allMatches(raw).lastOrNull;

    final value = match == null
        ? null
        : double.tryParse(match.group(1)!.replaceAll(',', '.'));

    if (value == null || value <= 0 || value > 2000) return 100;
    return value;
  }

  void dispose() => _client.close();
}

extension _LastOrNull<T> on Iterable<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
