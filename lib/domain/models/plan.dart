/// El plan **efectivo** de la cuenta: el que decide qué se puede usar.
///
/// Lo calcula el servidor (`effective_plan()`), no la app. La app no sabe si
/// la profesional de alguien tiene Pro ni si el acceso que le dio sigue
/// vigente, y adivinarlo desde acá sería prender o apagar la IA con un dato
/// viejo. Lo que la app hace con esto es **anticiparse**: no ofrecer un botón
/// que el servidor va a rechazar. El que decide sigue siendo el servidor, que
/// contesta 402 igual si alguien llega por otro lado.
enum AppPlan {
  /// Registro completo, sin IA y con anuncios.
  free('free', 'Gratis'),

  /// Toda la IA, sin anuncios. Es lo que tienen todas las cuentas reales.
  premium('premium', 'Premium'),

  /// La profesional. La IA del panel y la propia.
  pro('pro', 'Pro'),

  /// Cuenta gratis vinculada a una profesional Pro: la IA la paga ella.
  patient('patient', 'IA incluida por tu nutricionista');

  const AppPlan(this.wire, this.label);

  final String wire;

  /// Cómo se nombra en Perfil, después de "Tu plan:".
  final String label;

  /// Lo que se asume cuando no se sabe: sin servidor, sin sesión o con la
  /// consulta caída.
  ///
  /// Premium y no Gratis a propósito. Una cuenta sin fila en `account_plans`
  /// —todas las reales— **es** Premium, así que equivocarse para este lado
  /// solo puede mostrar un botón que el servidor después frena con su 402. Al
  /// revés, una red lenta le sacaría la IA a alguien que la tiene y le pondría
  /// anuncios encima.
  static const AppPlan fallback = AppPlan.premium;

  /// Un valor que no se reconoce cae en [fallback] por lo mismo: un plan nuevo
  /// del servidor que esta versión no conoce no puede apagarle nada a nadie.
  static AppPlan fromWire(Object? raw) {
    if (raw is! String) return fallback;
    final value = raw.trim().toLowerCase();
    for (final plan in AppPlan.values) {
      if (plan.wire == value) return plan;
    }
    return fallback;
  }

  /// Si la foto, la descripción, "¿Qué como?", el recálculo, el objetivo con
  /// IA y el resumen semanal se pueden usar.
  bool get includesAi => this != AppPlan.free;

  /// Los anuncios simulados de la demo van **solo** en el plan gratis.
  bool get showsAds => this == AppPlan.free;
}

/// Las cuentas del escenario de demostración, que son las únicas que pueden
/// "comprar" un plan desde la app (`demo_switch_plan`).
///
/// Se reconoce por el mail igual que lo hace el servidor. Acá es solo para no
/// ofrecer el botón de volver a Gratis a una cuenta real: la que decide es la
/// función, que a una cuenta real le contesta `ERR_FORBIDDEN` igual.
bool isDemoAccountEmail(String? email) =>
    email != null && email.trim().toLowerCase().endsWith('@demo.ceres.app');
