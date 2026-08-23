import 'package:flutter/services.dart';

import '../../core/error/app_error.dart';

/// En qué estado está Health Connect en este teléfono.
///
/// Son tres respuestas distintas y no se pueden confundir: "tu Android no lo
/// soporta" no tiene arreglo, "actualizá Health Connect" sí, y "está listo"
/// habilita el resto. Una sola bandera haría que la app ofreciera arreglar algo
/// imposible.
enum HealthConnectAvailability {
  available,
  updateRequired,
  unsupported;

  static HealthConnectAvailability fromWire(String? wire) => switch (wire) {
    'available' => available,
    'update_required' => updateRequired,
    _ => unsupported,
  };
}

/// Lo que Health Connect tiene de los últimos 30 días, un valor por día.
///
/// Las claves son fechas locales; el puente nativo ya resolvió a qué día
/// pertenece cada registro, porque eso depende de la zona horaria del teléfono y
/// es el único que la tiene.
class HealthConnectSnapshot {
  const HealthConnectSnapshot({
    this.weightKg = const <DateTime, double>{},
    this.bodyFatPct = const <DateTime, double>{},
    this.sleepMinutes = const <DateTime, int>{},
  });

  final Map<DateTime, double> weightKg;
  final Map<DateTime, double> bodyFatPct;
  final Map<DateTime, int> sleepMinutes;

  bool get isEmpty =>
      weightKg.isEmpty && bodyFatPct.isEmpty && sleepMinutes.isEmpty;

  int get total => weightKg.length + bodyFatPct.length + sleepMinutes.length;
}

/// Habla con Health Connect, el almacén de datos de salud de Android.
///
/// Es la **única** integración de dispositivos que hace falta, y no por
/// simplificar: Samsung Health escribe ahí, y el Zepp app también (Perfil →
/// vinculación de cuentas → Health Connect). Zepp no tiene API pública para que
/// un tercero le lea datos, así que este es el único camino que existe para un
/// Amazfit — y de paso entran Fitbit, Garmin y cualquier otra que sincronice.
///
/// Trae tres cosas y ninguna más: peso, grasa corporal y sueño. Las tres las
/// mide un aparato mejor que la memoria de una persona, y las tres son **una por
/// día o por noche** en Ceres, que al reimportar actualiza en vez de duplicar
/// (D-16). Lo que podría duplicar —las sesiones de ejercicio— no entra todavía:
/// necesita la revisión de duplicados de por medio y merece su propio paso.
///
/// Lo que **no** trae, a propósito:
///
/// - **Calorías activas.** El reloj las estima con su modelo y Ceres con MET.
///   Traer el número ajeno y mostrarlo como propio rompe RN-03; lo correcto es
///   traer la sesión y que Ceres calcule, como ya hace.
/// - **Pasos.** En Ceres solo existen colgados de una actividad, así que
///   importarlos obligaría a inventar actividades — y esas sí suman calorías.
/// - **Nutrición.** De la comida Ceres es la fuente de verdad.
class HealthConnectGateway {
  const HealthConnectGateway();

  static const MethodChannel _channel = MethodChannel('io.ceres.app/health');

  Future<HealthConnectAvailability> availability() async {
    try {
      final wire = await _channel.invokeMethod<String>('availability');
      return HealthConnectAvailability.fromWire(wire);
    } on MissingPluginException {
      return HealthConnectAvailability.unsupported;
    } on PlatformException {
      return HealthConnectAvailability.unsupported;
    }
  }

  Future<bool> hasPermissions() async {
    try {
      return await _channel.invokeMethod<bool>('hasPermissions') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Abre la pantalla de permisos de Health Connect y espera la respuesta.
  ///
  /// El permiso lo concede Health Connect en su propia pantalla, no el diálogo
  /// de Android: puede volver con algunos concedidos y otros no, y eso cuenta
  /// como "no" — con el sueño sin permiso, importar solo el peso dejaría media
  /// sincronización sin decirlo.
  Future<bool> requestPermissions() async {
    try {
      return await _channel.invokeMethod<bool>('requestPermissions') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Lee los últimos 30 días.
  ///
  /// Ese es el tope que Health Connect da sin el permiso de historial, y no lo
  /// pedimos: 30 días alcanzan para ponerse al día, y pedir el historial
  /// completo de la salud de alguien para eso sería pedir de más.
  Future<HealthConnectSnapshot> read() async {
    final Map<Object?, Object?>? raw;
    try {
      raw = await _channel.invokeMethod<Map<Object?, Object?>>('read');
    } on MissingPluginException {
      return const HealthConnectSnapshot();
    } on PlatformException catch (error) {
      // Un fallo de lectura no se come en silencio: la pantalla de
      // Integraciones lo muestra y se puede reintentar.
      throw AppError(
        code: ApiErrorCode.server,
        message: 'No pudimos leer Health Connect. Probá de nuevo.',
        requestId: error.message,
      );
    }
    if (raw == null) return const HealthConnectSnapshot();

    return HealthConnectSnapshot(
      weightKg: _numbers(raw['weightKg']),
      bodyFatPct: _numbers(raw['bodyFatPct']),
      sleepMinutes: _numbers(
        raw['sleepMinutes'],
      ).map((date, value) => MapEntry(date, value.round())),
    );
  }

  /// Lo que llega del canal es `Map<Object?, Object?>` con fechas como texto.
  /// Todo lo que no se pueda leer se descarta en silencio: un registro raro no
  /// puede tirar la importación entera.
  static Map<DateTime, double> _numbers(Object? raw) {
    if (raw is! Map) return const <DateTime, double>{};
    final out = <DateTime, double>{};
    for (final entry in raw.entries) {
      final date = DateTime.tryParse('${entry.key}');
      final value = entry.value;
      if (date == null || value is! num) continue;
      out[date] = value.toDouble();
    }
    return out;
  }
}
