import '../../core/error/app_error.dart';
import 'rounding.dart';

/// Ajuste por ejercicio (§13, RN-02). ★
///
/// ```
/// caloriasEjercicioAplicadas = round(caloriasEjercicioEstimadas × porcentaje ÷ 100)
/// ```
///
/// El porcentaje se **congela** en cada actividad al guardarla (D-05): al
/// cambiar la configuración se recalculan solo el día en curso y los futuros.
int calculateAppliedExerciseCalories({
  required int estimatedCalories,
  required int creditPercentage,
  bool creditEnabled = true,
}) {
  if (creditPercentage < 0 || creditPercentage > 100) {
    throw const CalculationError(
      'calculateAppliedExerciseCalories',
      'creditPercentage',
      'debe estar entre 0 y 100',
    );
  }
  if (estimatedCalories < 0) {
    throw const CalculationError(
      'calculateAppliedExerciseCalories',
      'estimatedCalories',
      'no puede ser negativo',
    );
  }
  if (!creditEnabled) return 0;
  return roundHalfUp(estimatedCalories * creditPercentage / 100);
}

/// Opciones fijas del selector de crédito (S-28). "No sumar" es la recomendada.
abstract final class ExerciseCreditOptions {
  static const List<int> presets = <int>[0, 50, 75, 100];

  static const int defaultPercentage = 0;

}
