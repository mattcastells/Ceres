import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;

import 'supabase_config.dart';

/// Interruptores de las integraciones que todavía no están conectadas de
/// verdad.
///
/// Regla: **mientras una integración devuelva datos inventados, su flag va en
/// `false`**. Es preferible una pantalla que diga "todavía no" a un registro
/// falso metido en el historial de la persona — el producto se apoya en que
/// ningún número sea inventado (RN-03, D-07).
///
/// Se encienden en tiempo de compilación:
/// ```bash
/// flutter run --dart-define=NM_AI_PHOTO=true
/// ```
abstract final class FeatureFlags {
  /// Los 30 días de historial inventados de `data/mock/seed.dart`.
  ///
  /// **Solo existen mientras se desarrolla, y en una compilación sin
  /// servidor.** Un usuario nuevo entró a la plataforma y se encontró con las
  /// comidas, el peso y el nombre de una persona que no existe; ese historial
  /// además viaja a las tablas en cuanto se abre sesión, así que datos
  /// inventados y datos reales terminan en la misma cuenta y no se distinguen.
  ///
  /// Las tres condiciones tienen que darse juntas:
  ///
  /// - `kDebugMode`: un APK de release nunca siembra, ni siquiera el que se
  ///   compila sin credenciales. Publicar no es depurar.
  /// - `!SupabaseConfig.isConfigured`: si hay servidor hay cuentas, y donde hay
  ///   cuentas no puede haber una persona de mentira.
  /// - `NM_DEMO_SEED`: la salida para depurar sin datos de ejemplo
  ///   (`--dart-define=NM_DEMO_SEED=false`).
  ///
  /// No alcanza con no llamar a la siembra: `LocalStore.seed` la vuelve a
  /// mirar, así que una llamada nueva desde cualquier lado tampoco puede
  /// meter datos inventados en una compilación de verdad.
  static bool get seededDemoData =>
      seededDemoDataOverride ??
      (kDebugMode &&
          !SupabaseConfig.isConfigured &&
          const bool.fromEnvironment('NM_DEMO_SEED', defaultValue: true));

  /// Fuerza el valor de [seededDemoData] desde un test.
  ///
  /// Las tres condiciones de arriba se resuelven en tiempo de compilación y
  /// `flutter test` corre justo en la combinación que **sí** siembra, así que
  /// sin esto el caso que importa —una compilación de verdad, donde la siembra
  /// tiene que estar muerta— sería el único que no se puede probar. Y ese es el
  /// que se rompió.
  @visibleForTesting
  static bool? seededDemoDataOverride;

  /// Análisis de foto con Gemini.
  ///
  /// Ya no devuelve un resultado fijo: la Edge Function `analyze-meal-photo`
  /// está desplegada, con la clave del lado del servidor y la cuota diaria de
  /// 20 análisis (D-18).
  ///
  /// Encendido por defecto. En una compilación **sin** Supabase no hay a quién
  /// preguntarle, así que ahí se apaga solo.
  static const bool aiPhotoAnalysis = bool.fromEnvironment(
    'NM_AI_PHOTO',
    defaultValue: true,
  );

  /// Importación desde Health Connect.
  ///
  /// Ya no inserta actividades de ejemplo: lee de verdad el peso, la grasa
  /// corporal y el sueño de los últimos 30 días (`HealthConnectGateway`). Con
  /// esto entran los datos de Samsung Health y del Zepp app, que escriben ahí —
  /// Zepp no tiene API pública para leerle nada a nadie, así que este es el
  /// único camino que existe para un Amazfit.
  ///
  /// Encendido por defecto. En un teléfono sin Health Connect la pantalla de
  /// Integraciones lo dice y no ofrece conectar.
  static const bool healthConnectSync = bool.fromEnvironment(
    'NM_HEALTH_SYNC',
    defaultValue: true,
  );

  // El flag `cloudBackup` se sacó: no lo leía nadie y encima mentía. Decía
  // "mientras esté apagado, los datos viven solo en este teléfono", y el
  // respaldo a la nube funciona desde hace varias versiones — lo decide
  // `SupabaseConfig.isConfigured`, no un flag. Un interruptor apagado que
  // describe un comportamiento que ya no existe es peor que no tenerlo:
  // manda a buscar el problema al lugar equivocado.

  /// Catálogo externo de alimentos (Open Food Facts). No necesita clave.
  static const bool onlineFoodCatalog = bool.fromEnvironment(
    'NM_FOOD_CATALOG',
    defaultValue: true,
  );

  /// Todo lo de la nutricionista: Mi nutricionista, devoluciones, objetivo
  /// recomendado, artículos y recetas, y los datos que precarga en el alta.
  ///
  /// Apagado por defecto: las tablas y funciones que usa (`care_feedback`,
  /// `care_articles`, las invitaciones, el vínculo todo o nada) no están en la
  /// base de producción. Apagado, la app ni siquiera arma esos clientes, así
  /// que nunca les pregunta nada.
  static const bool nutritionist = bool.fromEnvironment(
    'NM_NUTRITIONIST',
    defaultValue: false,
  );

  /// El reporte con IA de Progreso (semana, mes, trimestre, año).
  ///
  /// Apagado por defecto: lee `care_reports` y llama a la Edge Function
  /// `care-report`, que no existen en producción.
  static const bool aiProgressReport = bool.fromEnvironment(
    'NM_AI_PROGRESS_REPORT',
    defaultValue: false,
  );
}
