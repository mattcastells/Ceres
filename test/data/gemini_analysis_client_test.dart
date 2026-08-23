// El bug: contra la cuota agotada del proveedor, "Reintentar" salía
// habilitado.
//
// El 13 de agosto se tocó cuatro veces en cuarenta segundos, y ninguno de los
// cuatro toques podía funcionar: la cuota de Gemini es del proyecto entero y no
// se libera por insistir. Peor, cada toque gastaba cupo — con el reintento que
// tenía la Edge Function, dos pedidos por toque.
//
// La causa estaba en dos lugares que se tapaban entre sí. `ERR_AI_RATE_LIMITED`
// **no existía** en `ApiErrorCode`, así que el `orElse` de la traducción lo
// convertía en `upstreamFailed` y la pantalla lo trataba como un fallo
// cualquiera; y aunque hubiera existido, nadie le pasaba a la app cuántos
// segundos faltaban, que es el único dato con el que se puede apagar un botón
// sin adivinar.
//
// Estos tests fijan la mitad que vive en el cliente: que los dos códigos del
// proveedor lleguen enteros y que la espera se lea cuando viene.

import 'package:ceres/core/error/app_error.dart';
import 'package:ceres/data/remote/gemini_analysis_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Un `FunctionsClient` que no llama a nadie: tira el error que le pasen.
class _Falla extends FunctionsClient {
  _Falla(this.error) : super('http://localhost:54321', const <String, String>{});

  final FunctionException error;

  @override
  Future<FunctionResponse> invoke(
    String functionName, {
    Map<String, String>? headers,
    Object? body,
    Iterable<http.MultipartFile>? files,
    Map<String, dynamic>? queryParameters,
    HttpMethod method = HttpMethod.post,
    String? region,
  }) async {
    throw error;
  }
}

FunctionException _respuesta(
  int status,
  String code,
  String message, {
  Object? retryAfter,
}) {
  return FunctionException(
    status: status,
    details: <String, dynamic>{
      'error': <String, dynamic>{
        'code': code,
        'message': message,
        if (retryAfter != null) 'retryAfter': retryAfter,
      },
    },
  );
}

Future<AppError> _errorDe(FunctionException falla) async {
  final client = GeminiAnalysisClient(_Falla(falla));
  try {
    await client.analyze(photoPath: 'u-1/foto.jpg');
    fail('tenía que lanzar');
  } on AppError catch (error) {
    return error;
  }
}

void main() {
  test('la cuota agotada llega con su código y con cuánto falta', () async {
    final error = await _errorDe(
      _respuesta(
        429,
        'ERR_AI_RATE_LIMITED',
        'El servicio de análisis está al límite por ahora. Esperá 26 '
            'segundos y probá de nuevo, o cargá la comida a mano.',
        retryAfter: 26,
      ),
    );

    expect(error.code, ApiErrorCode.aiRateLimited);
    expect(error.retryAfter, const Duration(seconds: 26));
    // El texto lo redacta el servidor y se respeta: ya viene con el número.
    expect(error.message, contains('26 segundos'));
  });

  test('sin el dato del proveedor no se inventa una espera', () async {
    final error = await _errorDe(
      _respuesta(429, 'ERR_AI_RATE_LIMITED', 'Probá de nuevo en un rato.'),
    );

    expect(error.code, ApiErrorCode.aiRateLimited);
    // `null` es "no sabemos", y la pantalla lo trata como "el botón va
    // habilitado". Un cero disfrazado de espera sería peor que no tener nada.
    expect(error.retryAfter, isNull);
  });

  test('el modelo saturado no se confunde con la cuota', () async {
    final error = await _errorDe(
      _respuesta(
        503,
        'ERR_AI_OVERLOADED',
        'El modelo está ocupado en este momento.',
      ),
    );

    expect(error.code, ApiErrorCode.aiOverloaded);
    expect(error.retryAfter, isNull);
    // Los dos son reintentables; lo que cambia es cuándo.
    expect(error.isRetryable, isTrue);
  });

  test('un código que no conocemos sigue cayendo en el genérico', () async {
    final error = await _errorDe(
      _respuesta(500, 'ERR_LO_QUE_SEA', 'Algo pasó del otro lado.'),
    );

    expect(error.code, ApiErrorCode.upstreamFailed);
    expect(error.message, 'Algo pasó del otro lado.');
  });

  test('una espera con forma rara no rompe la traducción', () async {
    // La forma la decide el servidor: si algún día manda `"26s"` o `null`, el
    // análisis tiene que seguir fallando por lo que falló y no por el parseo.
    final error = await _errorDe(
      _respuesta(
        429,
        'ERR_AI_RATE_LIMITED',
        'Al límite.',
        retryAfter: 'un rato',
      ),
    );

    expect(error.code, ApiErrorCode.aiRateLimited);
    expect(error.retryAfter, isNull);
  });
}
