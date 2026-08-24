import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error/app_error.dart';
import '../../domain/enums/enums.dart';
import '../../domain/models/ai_calorie_target.dart';

/// Llama a la Edge Function `suggest-calorie-target`.
///
/// Le manda los datos **crudos** —sexo, edad, altura, peso, actividad— y no un
/// gasto ya calculado, a propósito: el servidor rehace la cuenta y acota la
/// respuesta del modelo contra su propio número. Si el techo de la validación
/// viniera de acá, la validación no estaría validando nada.
class CalorieTargetClient {
  CalorieTargetClient(this._functions);

  factory CalorieTargetClient.fromInstance() =>
      CalorieTargetClient(Supabase.instance.client.functions);

  final FunctionsClient _functions;

  static const String functionName = 'suggest-calorie-target';

  /// Más largo que el techo de la función, por lo mismo que en
  /// `GeminiAnalysisClient.timeout`: los 25 s de Gemini son por intento y la
  /// función puede intentar dos veces, así que 40 s de acá cortaban antes de
  /// que el servidor llegara a contestar. Este era el peor de los tres, y
  /// encima en el alta.
  ///
  /// `invoke` no trae timeout propio, y sin esto el paso del alta se queda
  /// girando para siempre — en la única pantalla de la que no se sale.
  static const Duration timeout = Duration(seconds: 60);

  Future<AiCalorieTarget> propose({
    required BiologicalSex sex,
    required int ageYears,
    required double heightCm,
    required double weightKg,
    required ActivityLevel activityLevel,
    required GoalType goalType,
    required int formulaTarget,
  }) async {
    final FunctionResponse response;
    try {
      response = await _functions
          .invoke(
            functionName,
            body: <String, dynamic>{
              'sex': sex.wire,
              'ageYears': ageYears,
              'heightCm': heightCm,
              'weightKg': weightKg,
              'activityLevel': activityLevel.wire,
              'goalType': goalType.wire,
              'formulaTarget': formulaTarget,
            },
          )
          .timeout(timeout);
    } on FunctionException catch (error) {
      throw _translate(error);
    } on TimeoutException {
      throw const AppError(
        code: ApiErrorCode.upstreamTimeout,
        message: 'La propuesta tardó demasiado. Podés seguir con el número '
            'calculado y cambiarlo después.',
      );
    } on Exception {
      throw const AppError(
        code: ApiErrorCode.offline,
        message: 'No pudimos pedir la propuesta: revisá tu conexión. El '
            'número calculado sirve igual.',
      );
    }

    return _read(response.data);
  }

  /// La forma de la respuesta la decide el servidor, así que acá se la trata
  /// como entrada y no como promesa. Un `as int` sobre un campo que no vino
  /// lanza un `TypeError`, que **no es una `Exception`**: se escapa de
  /// cualquier `on Exception` y deja el paso cargando para siempre.
  static AiCalorieTarget _read(Object? data) {
    if (data is! Map) throw _unreadable;

    final target = data['targetKcal'];
    final rationale = data['rationale'];
    if (target is! num || rationale is! String || rationale.trim().isEmpty) {
      throw _unreadable;
    }

    return AiCalorieTarget(
      targetKcal: target.round(),
      rationale: rationale.trim(),
      clamped: data['clamped'] == true,
      bmrKcal: (data['bmrKcal'] as num?)?.round() ?? 0,
      tdeeKcal: (data['tdeeKcal'] as num?)?.round() ?? 0,
    );
  }

  static const AppError _unreadable = AppError(
    code: ApiErrorCode.aiInvalidResponse,
    message: 'La propuesta vino con algo que no pudimos leer. Seguí con el '
        'número calculado.',
  );

  static AppError _translate(FunctionException error) {
    final details = error.details;
    final payload = details is Map ? details['error'] : null;
    final message = payload is Map ? payload['message'] : null;

    return AppError(
      code: ApiErrorCode.aiInvalidResponse,
      // El texto del servidor cuando lo hay: es el que sabe si fue la cuota,
      // el proveedor o una propuesta fuera de banda, y los tres mandan a hacer
      // cosas distintas.
      message: message is String && message.isNotEmpty
          ? message
          : 'No pudimos calcularlo con IA. Seguí con el número calculado.',
    );
  }
}
