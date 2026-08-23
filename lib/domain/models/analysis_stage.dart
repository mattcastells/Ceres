/// Los pasos reales del análisis por foto.
///
/// Existen para que la pantalla de espera diga lo que **está pasando** en vez
/// de animar algo decorativo. Los tres primeros son observables desde la app:
/// se sabe con exactitud cuándo empieza y termina cada uno. El último no —
/// cuánto tarda el modelo no lo decide Ceres— y por eso se trata distinto.
enum AnalysisStage {
  /// Comprimiendo y dejando la foto lista para subir. Es instantáneo.
  preparing('Preparando la foto…'),

  /// Subiendo al bucket. Depende de la conexión, no del modelo.
  uploading('Subiendo la foto…'),

  /// Esperando al modelo. Es el 80 % de la espera y el único paso cuya
  /// duración no controlamos.
  analyzing('Analizando la comida…');

  const AnalysisStage(this.label);

  final String label;

  /// Cuánto pesa cada paso en la barra, sobre 1.
  ///
  /// No son números elegidos a ojo: salen de medir el circuito real. La
  /// llamada al modelo tiene una mediana de 12,3 s contra menos de 2 s de
  /// preparación y subida juntas, así que se lleva la mayor parte de la barra.
  double get weight => switch (this) {
    AnalysisStage.preparing => 0.05,
    AnalysisStage.uploading => 0.15,
    AnalysisStage.analyzing => 0.80,
  };

  /// Fracción de la barra ya completada cuando **arranca** este paso.
  double get start {
    var acc = 0.0;
    for (final s in AnalysisStage.values) {
      if (s == this) return acc;
      acc += s.weight;
    }
    return acc;
  }
}

/// Tiempos medidos del análisis por foto, para calibrar la espera.
///
/// Salen de las corridas reales guardadas en `ai_analyses`, no de una
/// estimación: mediana 12,3 s, percentil 90 en 24,9 s y un máximo de 35,8 s
/// —ese último fue un reintento, porque un JSON inválido dispara una segunda
/// llamada al modelo y duplica el tiempo—.
///
/// Queda una sola constante y es a propósito. Hubo dos más, `slow` y
/// `tooLong`, que existían para decidir cuándo avisar que se demoraba; ese
/// aviso se fue entero. Marcar el umbral obliga a elegir a partir de qué
/// segundo una espera normal pasa a ser un problema, y no hay tal segundo:
/// cuánto tarda el modelo no lo decide Ceres, así que anunciarlo solo pone
/// a mirar el reloj. La mediana sí se usa, pero para dibujar la barra.
abstract final class AnalysisTiming {
  /// Mediana medida de la llamada al modelo.
  static const Duration typical = Duration(milliseconds: 12300);
}
