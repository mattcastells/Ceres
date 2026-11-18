/// Códigos de error de la API (09-api-contracts.md §2, 10-types §API envelope).
enum ApiErrorCode {
  unauthenticated('ERR_UNAUTHENTICATED'),
  forbidden('ERR_FORBIDDEN'),
  notFound('ERR_NOT_FOUND'),
  validation('ERR_VALIDATION'),
  conflict('ERR_CONFLICT'),
  rateLimited('ERR_RATE_LIMITED'),
  quotaExceeded('ERR_QUOTA_EXCEEDED'),
  upstreamTimeout('ERR_UPSTREAM_TIMEOUT'),
  upstreamFailed('ERR_UPSTREAM_FAILED'),
  aiInvalidResponse('ERR_AI_INVALID_RESPONSE'),
  aiNoFood('ERR_AI_NO_FOOD'),

  /// La cuota del proveedor de IA se agotó. **No es** `rateLimited`, que es el
  /// nuestro: este techo lo comparten todos los usuarios de la app y no se
  /// libera por dejar de insistir, así que la pantalla espera el tiempo que
  /// diga el proveedor antes de volver a ofrecer el botón.
  ///
  /// Sin este valor caía en `upstreamFailed` por el `orElse` de la traducción,
  /// y "Reintentar" aparecía al toque: cuatro toques en cuarenta segundos
  /// contra una puerta cerrada, cada uno gastando cuota.
  aiRateLimited('ERR_AI_RATE_LIMITED'),

  /// El modelo está saturado un momento. Se parece al de arriba y es lo
  /// contrario: acá insistir en unos segundos suele funcionar.
  aiOverloaded('ERR_AI_OVERLOADED'),

  /// Ninguna de las opciones que devolvió el modelo cerró con el presupuesto.
  /// No es un fallo del servidor: es que esta tirada no dio, y volver a
  /// intentar sí puede dar — por eso tiene su propio código y no `server`.
  aiNoSuggestions('ERR_AI_NO_SUGGESTIONS'),

  /// Quedan tan pocas calorías que no hay plato que sugerir sin inventarlo.
  budgetTooLow('ERR_BUDGET_TOO_LOW'),

  /// No hay registros con los que armar un informe (422).
  noData('ERR_NO_DATA'),

  permissionDenied('ERR_PERMISSION_DENIED'),
  providerUnavailable('ERR_PROVIDER_UNAVAILABLE'),
  syncFailed('ERR_SYNC_FAILED'),
  offline('ERR_OFFLINE'),
  server('ERR_SERVER'),
  emailTaken('ERR_EMAIL_TAKEN'),
  weakPassword('ERR_WEAK_PASSWORD'),
  invalidCredentials('ERR_INVALID_CREDENTIALS'),
  reauthRequired('ERR_REAUTH_REQUIRED');

  const ApiErrorCode(this.wire);

  final String wire;

  /// Los errores reintentables no revierten una escritura optimista (D-08).
  bool get isRetryable => switch (this) {
    ApiErrorCode.offline ||
    ApiErrorCode.server ||
    ApiErrorCode.upstreamTimeout ||
    ApiErrorCode.upstreamFailed ||
    ApiErrorCode.syncFailed ||
    // Volver a pedir sugerencias sí puede dar otro resultado: el modelo no es
    // determinista y lo que falló fue que ninguna opción cerrara, no el
    // servidor.
    ApiErrorCode.aiNoSuggestions ||
    ApiErrorCode.rateLimited ||
    // Los dos del proveedor son reintentables, pero no *ya*: el de la cuota
    // trae cuánto falta en `AppError.retryAfter` y quien lo muestre tiene que
    // respetarlo. Reintentable significa "esto puede salir bien la próxima",
    // no "el botón va habilitado".
    ApiErrorCode.aiRateLimited ||
    ApiErrorCode.aiOverloaded => true,
    _ => false,
  };
}

/// Error de aplicación con mensaje ya redactado para el usuario.
///
/// El handoff prohíbe "Ocurrió un error": cada mensaje dice qué falló y qué
/// puede hacer la persona (05-component-library §5).
class AppError implements Exception {
  const AppError({
    required this.code,
    required this.message,
    this.fields = const <String, String>{},
    this.requestId,
    this.retryAfter,
  });

  final ApiErrorCode code;
  final String message;

  /// Errores por campo, para pintarlos debajo del input que corresponde.
  final Map<String, String> fields;
  final String? requestId;

  /// Cuánto falta para que tenga sentido reintentar, cuando el servidor lo
  /// dice. Hoy lo manda el 429 del proveedor de IA, que sabe cuándo se libera
  /// su ventana. `null` es "no lo sabemos", no "ya".
  final Duration? retryAfter;

  bool get isRetryable => code.isRetryable;

  static const AppError offline = AppError(
    code: ApiErrorCode.offline,
    message: 'No hay conexión. Vas a poder reintentar cuando vuelva.',
  );

  @override
  String toString() => '${code.wire}: $message';
}

/// Error de una fórmula pura: siempre nombra la función y el campo ofensor
/// (11-calculation-rules.md, reglas transversales).
class CalculationError implements Exception {
  const CalculationError(this.calculation, this.field, this.detail);

  final String calculation;
  final String field;
  final String detail;

  @override
  String toString() => 'CalculationError($calculation, $field): $detail';
}
