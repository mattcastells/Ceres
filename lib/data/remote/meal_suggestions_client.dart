import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error/app_error.dart';
import '../../domain/enums/enums.dart';
import '../../domain/models/meal_suggestion.dart';

/// Llama a la Edge Function `suggest-meals`.
///
/// Igual que las de estimación: la app no habla con Gemini, le pasa el
/// presupuesto a la función y la clave nunca baja al teléfono.
class MealSuggestionsClient {
  MealSuggestionsClient(this._functions);

  factory MealSuggestionsClient.fromInstance() =>
      MealSuggestionsClient(Supabase.instance.client.functions);

  final FunctionsClient _functions;

  static const String functionName = 'suggest-meals';

  /// Más largo que el techo de la función, por lo mismo que en
  /// `GeminiAnalysisClient.timeout`: los 25 s de Gemini son por intento y la
  /// función puede intentar dos veces, así que 45 s de acá cortaban antes de
  /// que el servidor llegara a contestar. La función ahora se corta a los 38 s
  /// y contesta; esto le da lugar de sobra.
  ///
  /// Sin timeout propio, una función que muere deja la pantalla girando para
  /// siempre, sin error y sin forma de salir.
  static const Duration timeout = Duration(seconds: 60);

  /// Abajo de esto ni se pregunta.
  ///
  /// Está repetido del lado del servidor a propósito: el servidor tiene que
  /// defenderse igual de un cliente viejo, y el cliente no tiene por qué gastar
  /// un viaje —ni una unidad de cuota— para que le contesten que no.
  static const int minBudgetKcal = 150;

  /// Cuánto de la nota libre viaja. Lo mismo que acepta la columna y que deja
  /// entrar el servidor: un texto largo se lleva puesto el prompt entero.
  static const int maxNoteLength = 200;

  /// Tres comidas que entran en [remainingKcal] y que esta persona **puede
  /// comer**.
  ///
  /// [restrictions] son los `wire` de `DietaryFlag` y [restrictionsNote] lo que
  /// escribió a mano. Van al servidor porque el filtro tiene que estar de los
  /// dos lados: el prompt se lo pide al modelo y la función descarta lo que
  /// igual se cuele. Un plato con queso ofrecido a alguien con alergia a la
  /// leche no es una sugerencia imprecisa.
  Future<List<MealSuggestion>> suggest({
    required int remainingKcal,
    MealSlot? slot,
    int? remainingProteinG,
    List<String> restrictions = const <String>[],
    String? restrictionsNote,
  }) async {
    final nota = restrictionsNote?.trim() ?? '';
    final FunctionResponse response;
    try {
      response = await _functions
          .invoke(
            functionName,
            body: <String, dynamic>{
              'remainingKcal': remainingKcal,
              if (slot != null) 'slot': slot.label,
              if (remainingProteinG != null && remainingProteinG > 0)
                'remainingProteinG': remainingProteinG,
              if (restrictions.isNotEmpty) 'restrictions': restrictions,
              if (nota.isNotEmpty)
                'restrictionsNote': nota.length > maxNoteLength
                    ? nota.substring(0, maxNoteLength)
                    : nota,
            },
          )
          .timeout(timeout);
    } on FunctionException catch (error) {
      throw _translate(error);
    } on TimeoutException {
      throw const AppError(
        code: ApiErrorCode.upstreamTimeout,
        message: 'Las sugerencias tardaron demasiado. Probá de nuevo.',
      );
    } on Exception {
      throw const AppError(
        code: ApiErrorCode.offline,
        message: 'No pudimos pedir sugerencias: revisá tu conexión.',
      );
    }

    return parse(response.data, budgetKcal: remainingKcal);
  }

  /// Lee la respuesta y **vuelve a comprobar el presupuesto**.
  ///
  /// El servidor ya descarta lo que no entra; esto lo hace de nuevo del lado del
  /// teléfono. No es desconfianza del código de al lado: es que este es el
  /// último lugar antes de que un número llegue a los ojos de alguien, y la
  /// regla —"nunca sugerir algo que no entra"— es de las que no se delegan.
  /// Público para poder probarlo sin servidor de por medio.
  static List<MealSuggestion> parse(
    dynamic data, {
    required int budgetKcal,
  }) {
    if (data is! Map) return const <MealSuggestion>[];
    final raw = data['options'];
    if (raw is! List) return const <MealSuggestion>[];

    final out = <MealSuggestion>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final option = MealSuggestion.fromJson(Map<String, dynamic>.from(entry));
      if (option == null) continue;
      if (option.kcal > budgetKcal) continue;

      // Y que el total sea de verdad la suma de sus partes. Si no lo es, uno de
      // los dos números miente y no hay forma de saber cuál: se descarta.
      final suma = option.items.fold<int>(0, (acc, i) => acc + i.kcal);
      if ((suma - option.kcal).abs() > 40) continue;
      if (suma > budgetKcal) continue;

      out.add(option);
    }
    return out;
  }

  static AppError _translate(FunctionException error) {
    final details = error.details;
    String? code;
    String? message;

    if (details is Map && details['error'] is Map) {
      final inner = details['error'] as Map;
      code = inner['code'] as String?;
      message = inner['message'] as String?;
    }

    final apiCode = ApiErrorCode.values.firstWhere(
      (c) => c.wire == code,
      orElse: () => ApiErrorCode.upstreamFailed,
    );

    return AppError(
      code: apiCode,
      message: message ?? 'No pudimos traer sugerencias. Probá de nuevo.',
    );
  }
}
