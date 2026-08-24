import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error/app_error.dart';
import '../../domain/enums/enums.dart';
import '../../domain/models/ai_analysis.dart';
import '../../domain/models/meal.dart';

/// Llama a la Edge Function `analyze-meal-photo`.
///
/// La app **no habla con Gemini**: le pasa a la función la ruta de la foto ya
/// subida al bucket y la función hace el resto. La clave de Gemini vive en los
/// secretos del proyecto y nunca baja al teléfono — una clave dentro de un APK
/// es una clave regalada.
class GeminiAnalysisClient {
  GeminiAnalysisClient(this._functions);

  factory GeminiAnalysisClient.fromInstance() =>
      GeminiAnalysisClient(Supabase.instance.client.functions);

  final FunctionsClient _functions;

  static const String functionName = 'analyze-meal-photo';

  /// La hermana por texto: misma validación y misma cuota, sin foto.
  static const String textFunctionName = 'analyze-meal-text';

  /// Tiene que ser **más largo** que el techo de la función, no parecido.
  ///
  /// Acá estaba el bug que llenaba la pantalla de "El análisis tardó
  /// demasiado". La función se corta a los 25 s contra Gemini, sí, pero eso es
  /// **por intento** y puede intentar dos veces: 50 s de servidor contra 45 s
  /// de acá. O sea que cualquier análisis que necesitara un segundo intento
  /// terminaba en el mensaje de demora aunque el servidor hubiera contestado
  /// bien un rato después — la foto y la cuota gastadas, el resultado tirado.
  ///
  /// Hoy la función tiene un presupuesto total propio y contesta ella un
  /// `ERR_UPSTREAM_TIMEOUT`; esto le da lugar de sobra para llegar a hablar
  /// primero. El timeout de acá deja de ser lo normal y vuelve a ser lo que
  /// tiene que ser: la red que se cortó de verdad.
  ///
  /// 90 s y no 60 para que el servidor pueda darse **tres** intentos contra el
  /// proveedor —30 + 30 + 18— en vez de dos y medio. Con el razonamiento en
  /// `medium` una respuesta buena tarda entre 9 y 25 s, así que un intento
  /// necesita 30 s; y los que fallan se cuelgan y se llevan los 30 enteros, que
  /// es lo que hace que el tercero valga la pena.
  ///
  /// Nadie va a esperar 90 s mirando: la pantalla de análisis tiene frases que
  /// no se terminan nunca, hechas justamente para esto, y las salidas —cargar a
  /// mano, volver— están siempre a la vista.
  ///
  /// ⚠️ **Subir el presupuesto del servidor antes que esto rompe la app.** El
  /// techo del servidor tiene que quedar siempre por debajo del de acá: al
  /// revés, el teléfono corta primero, la cuota queda gastada y el fallo no se
  /// registra en ningún lado. Por eso el servidor sigue en 50 s hasta que esta
  /// versión esté instalada, y recién ahí sube por `GEMINI_BUDGET_MS`.
  ///
  /// `invoke` **no trae timeout propio**: sin esto, una función que muere deja
  /// la pantalla girando para siempre, sin error y sin forma de salir.
  static const Duration timeout = Duration(seconds: 90);

  /// Estima una comida a partir de una descripción escrita.
  ///
  /// Es lo que el catálogo de productos envasados no puede contestar: "dos
  /// empanadas de carne" no tiene código de barras.
  Future<AiAnalysis> analyzeText({required String description}) async {
    final response = await _invoke(
      textFunctionName,
      <String, dynamic>{'description': description},
      timeoutMessage:
          'La estimación tardó demasiado. Probá de nuevo o cargá la comida '
          'a mano.',
      offlineMessage: 'No pudimos estimar la comida: revisá tu conexión.',
    );
    return _toAnalysis(response.data, photoPath: null);
  }

  /// Vuelve a estimar una comida **que ya existe**, a partir de lo que tiene
  /// cargado y de una corrección escrita.
  ///
  /// Es la diferencia entre corregir y empezar de nuevo: hasta ahora, cambiar
  /// un peso que la IA estimó mal obligaba a sacar la foto otra vez y rehacer
  /// la comida entera. Acá van los ítems actuales, la foto —la que ya tenía o
  /// una nueva— y la frase de la persona ("le falta el pan", "la milanesa
  /// pesaba 200 g"), y vuelve la comida completa ya corregida.
  ///
  /// Sin [photoPath] pregunta por texto: una comida cargada a mano también se
  /// puede corregir así.
  Future<AiAnalysis> recalculate({
    required List<MealItem> items,
    required String instruction,
    String? photoPath,
  }) async {
    final hint = instruction.trim();
    final byPhoto = photoPath != null && photoPath.isNotEmpty;

    final response = await _invoke(
      byPhoto ? functionName : textFunctionName,
      <String, dynamic>{
        if (byPhoto) 'photoPath': photoPath,
        if (hint.isNotEmpty) 'description': hint,
        'currentItems': <Map<String, dynamic>>[
          for (final item in items)
            <String, dynamic>{
              'name': item.name,
              'quantity': item.quantity,
              'unit': item.unit,
              'kcal': item.kcal,
              'proteinG': item.proteinG,
              'carbsG': item.carbsG,
              'fatG': item.fatG,
            },
        ],
      },
      timeoutMessage:
          'El recálculo tardó demasiado. La comida quedó como estaba: probá '
          'de nuevo.',
      offlineMessage:
          'No pudimos recalcular la comida: revisá tu conexión. La comida '
          'quedó como estaba.',
    );

    return _toAnalysis(response.data, photoPath: byPhoto ? photoPath : null);
  }

  /// Analiza una foto **ya subida al bucket**.
  ///
  /// [description] es lo que la persona aclaró sobre la foto, si aclaró algo.
  /// Va vacía o nula la mayoría de las veces y entonces ni se manda: la foto
  /// sola tiene que seguir funcionando igual.
  Future<AiAnalysis> analyze({
    required String photoPath,
    String? description,
  }) async {
    final hint = description?.trim() ?? '';
    final response = await _invoke(
      functionName,
      <String, dynamic>{
        'photoPath': photoPath,
        if (hint.isNotEmpty) 'description': hint,
      },
      timeoutMessage:
          'El análisis tardó demasiado. La foto quedó guardada: cargá la '
          'comida a mano o probá de nuevo.',
      offlineMessage:
          'No pudimos analizar la foto: revisá tu conexión. La foto ya está '
          'guardada, podés cargar la comida a mano.',
    );

    return _toAnalysis(response.data, photoPath: photoPath);
  }

  /// La llamada, con el mismo tratamiento de fallos para las tres puertas.
  ///
  /// Lo único que cambia entre analizar, describir y recalcular es qué decirle
  /// a la persona cuando se cae: el resto —el timeout propio, la traducción
  /// del error de la función, la red— tiene que ser idéntico, y la forma de
  /// que siga siéndolo es que sea el mismo código.
  Future<FunctionResponse> _invoke(
    String name,
    Map<String, dynamic> body, {
    required String timeoutMessage,
    required String offlineMessage,
  }) async {
    try {
      return await _functions.invoke(name, body: body).timeout(timeout);
    } on FunctionException catch (error) {
      throw _translate(error);
    } on TimeoutException {
      throw AppError(
        code: ApiErrorCode.upstreamTimeout,
        message: timeoutMessage,
      );
    } on Exception {
      throw AppError(code: ApiErrorCode.offline, message: offlineMessage);
    }
  }

  /// Misma forma de respuesta para foto y texto: una sola lectura.
  ///
  /// Todo lo que no cierre sale como [ApiErrorCode.aiInvalidResponse] y no como
  /// un error de casteo. Un `as String` sobre un campo que no vino lanza un
  /// `TypeError`, que **no es una `Exception`**: se escapa de cualquier
  /// `on AppError` y de cualquier `on Exception`, y la pantalla que lo pidió se
  /// queda cargando para siempre. La forma de la respuesta la decide el
  /// servidor, así que acá se la trata como entrada, no como promesa.
  static AiAnalysis _toAnalysis(Object? data, {required String? photoPath}) {
    if (data is! Map) throw _unreadable;

    final id = data['id'];
    if (id is! String || id.isEmpty) throw _unreadable;

    final rawItems = data['items'];
    if (rawItems != null && rawItems is! List) throw _unreadable;

    // El título es opcional a propósito: una función todavía no desplegada, o
    // una respuesta del modelo sin el campo, no puede tumbar un análisis que
    // por lo demás está bien. Cuando no viene, la app arma el título con
    // `MealTitle` a partir de los ítems.
    final rawTitle = data['title'];
    final title = rawTitle is String && rawTitle.trim().isNotEmpty
        ? rawTitle.trim()
        : null;

    return AiAnalysis(
      id: id,
      photoPath: photoPath,
      title: title,
      status: AiAnalysisStatus.completed,
      model: data['model'] as String? ?? 'gemini',
      promptVersion: data['promptVersion'] as String? ?? 'v3',
      latencyMs: (data['latencyMs'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.now(),
      items: <AiAnalysisItem>[
        for (final raw in (rawItems as List<dynamic>?) ?? <dynamic>[])
          _toItem(raw),
      ],
    );
  }

  static const AppError _unreadable = AppError(
    code: ApiErrorCode.aiInvalidResponse,
    message:
        'El análisis devolvió algo que no pudimos leer. Cargá la comida a '
        'mano.',
  );

  static AiAnalysisItem _toItem(Object? raw) {
    if (raw is! Map) throw _unreadable;

    final name = raw['name'];
    final quantity = raw['quantity'];
    final unit = raw['unit'];
    final kcal = raw['kcal'];
    if (name is! String || quantity is! num || unit is! String || kcal is! num) {
      throw _unreadable;
    }

    // Los macros y la confianza se completan en cero si faltan: un ítem con
    // nombre y calorías ya es útil, y perderlo entero por un macro ausente
    // sería peor que mostrarlo con un cero visible que la persona corrige.
    return AiAnalysisItem(
      name: name,
      quantity: quantity.toDouble(),
      unit: unit,
      kcal: kcal.round(),
      proteinG: (raw['proteinG'] as num?)?.toDouble() ?? 0,
      carbsG: (raw['carbsG'] as num?)?.toDouble() ?? 0,
      fatG: (raw['fatG'] as num?)?.toDouble() ?? 0,
      confidence: (raw['confidence'] as num?)?.toDouble() ?? 0,
    );
  }

  /// La función devuelve `{error: {code, message}}`; el mensaje ya viene
  /// redactado para mostrar, así que se respeta en vez de reescribirlo acá.
  static AppError _translate(FunctionException error) {
    final details = error.details;
    String? code;
    String? message;
    Duration? retryAfter;

    if (details is Map && details['error'] is Map) {
      final inner = details['error'] as Map;
      code = inner['code'] as String?;
      message = inner['message'] as String?;
      // Solo viene con el 429 del proveedor, y solo cuando él mismo dice
      // cuánto falta. Se lee como entrada —número, texto o nada— porque la
      // forma la decide el servidor.
      final raw = inner['retryAfter'];
      final seconds = raw is num ? raw.toInt() : int.tryParse('$raw');
      if (seconds != null && seconds > 0) {
        retryAfter = Duration(seconds: seconds);
      }
    }

    final apiCode = ApiErrorCode.values.firstWhere(
      (c) => c.wire == code,
      orElse: () => ApiErrorCode.upstreamFailed,
    );

    return AppError(
      code: apiCode,
      message:
          message ??
          'El análisis falló. Cargá la comida a mano; la foto queda adjunta.',
      retryAfter: retryAfter,
    );
  }
}
