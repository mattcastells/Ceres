import '../../core/error/app_error.dart';
import '../enums/enums.dart';
import 'rounding.dart';

/// Objetivo calórico base: déficit o superávit sobre el TDEE (§3).
class CalorieTargetResult {
  const CalorieTargetResult({
    required this.target,
    required this.clamped,
    required this.uncappedTarget,
    required this.minimum,
  });

  /// Valor final a usar (ya clampeado si hizo falta).
  final int target;

  /// Si el clamp de RN-12 actuó, la UI lo dice explícitamente.
  final bool clamped;

  /// El valor antes del clamp, para poder explicar el ajuste.
  final int uncappedTarget;
  final int minimum;

  String get clampNotice =>
      'Ajustamos tu objetivo al mínimo saludable de $minimum kcal.';
}

abstract final class CalorieTargetRules {
  /// Equivalente energético de 1 kg de grasa.
  static const double kcalPerKgOfFat = 7700;

  /// Tope de ritmo: 1 kg por semana (RN-13). No hay opción "agresiva".
  static const double maxRateKgPerWeek = 1.0;

  /// Tope del ajuste como fracción del gasto diario.
  ///
  /// Es el techo del camino relativo ([calorieTargetForPace]). Un déficit de
  /// 550 kcal es el 21 % del gasto de una persona de 2.600 y el 35 % del de una
  /// de 1.550: el mismo número de kilos por semana no es el mismo esfuerzo para
  /// dos cuerpos distintos, y el piso plano de RN-12 no alcanza para notarlo
  /// —actúa recién en 1.200 kcal, cuando el desbalance ya pasó—.
  static const double maxFractionOfTdee = 0.30;

  static const int absoluteMin = 800;
  static const int absoluteMax = 6000;

  /// Mínimos de RN-12 por sexo del perfil.
  static int minimumFor(BiologicalSex sex) => switch (sex) {
    BiologicalSex.female => 1200,
    BiologicalSex.male => 1500,
    BiologicalSex.unspecified => 1350,
  };

  /// Ajuste calórico diario de un ritmo semanal.
  static double dailyAdjustment(double rateKgPerWeek) =>
      rateKgPerWeek * kcalPerKgOfFat / 7;
}

/// ```
/// objetivoBase(lose)        = tdee − ajusteDiario
/// objetivoBase(gain)        = tdee + ajusteDiario × 0,5   (superávit conservador, D-04)
/// objetivoBase(gain_muscle) = tdee + ajusteDiario
/// objetivoBase(maintain)    = tdee
/// ```
///
/// `gain_muscle` usa el superávit completo y no la mitad: el recorte de D-04
/// existe para que subir de peso no sea subir grasa, y ahí el freno lo pone el
/// ritmo, que por defecto es 0,25 kg/semana (≈ 275 kcal). Recortarlo otra vez
/// dejaría un superávit tan chico que no alcanza para construir tejido.
CalorieTargetResult calorieTarget({
  required int tdee,
  required GoalType goalType,
  required double rateKgPerWeek,
  required BiologicalSex sex,
}) {
  if (tdee <= 0) {
    throw const CalculationError(
      'calorieTarget',
      'tdee',
      'debe ser mayor que cero',
    );
  }
  if (rateKgPerWeek < 0 || rateKgPerWeek > CalorieTargetRules.maxRateKgPerWeek) {
    throw const CalculationError(
      'calorieTarget',
      'rateKgPerWeek',
      'debe estar entre 0 y 1 kg por semana (RN-13)',
    );
  }

  final adjustment = CalorieTargetRules.dailyAdjustment(rateKgPerWeek);
  final raw = switch (goalType) {
    GoalType.lose => tdee - adjustment,
    // Medio superávit: un superávit completo se traduce mayormente en grasa (D-04).
    GoalType.gain => tdee + adjustment * 0.5,
    GoalType.gainMuscle => tdee + adjustment,
    GoalType.maintain => tdee.toDouble(),
  };

  final uncapped = roundHalfUp(raw);
  final minimum = CalorieTargetRules.minimumFor(sex);

  var target = uncapped;
  var clamped = false;
  if (target < minimum) {
    target = minimum;
    clamped = true;
  }
  if (target > CalorieTargetRules.absoluteMax) {
    target = CalorieTargetRules.absoluteMax;
    clamped = true;
  }

  return CalorieTargetResult(
    target: target,
    clamped: clamped,
    uncappedTarget: uncapped,
    minimum: minimum,
  );
}

/// El objetivo de un ritmo **relativo al gasto**, y el ritmo semanal que
/// implica para ese cuerpo.
///
/// [calorieTarget] parte de los kilos por semana y llega a las calorías. Esto
/// va al revés: parte de una fracción del gasto —que ya viene de metabolismo
/// basal × nivel de actividad, o sea de los datos de la persona— y los kilos
/// por semana salen como consecuencia. Es la diferencia entre "medio kilo por
/// semana" —que para alguien de 1.550 kcal de gasto es un déficit del 35 %— y
/// "un 20 % menos que tu gasto", que es el mismo esfuerzo para cualquiera.
///
/// El ritmo devuelto es el que hay que **guardar**: sale redondeado a dos
/// decimales, que es lo que acepta la columna, y el objetivo se calcula desde
/// ese valor redondeado. Si se calculara desde la fracción sin redondear, el
/// número guardado y el número mostrado no coincidirían.
///
/// RN-13 sigue siendo el techo: sobre un gasto muy grande, una fracción chica
/// puede pasarse del kilo por semana, y ahí manda el kilo.
///
/// A diferencia del camino por ritmo, acá **no** se aplica el medio superávit
/// de D-04: la decisión sigue viva, pero pasa a estar donde se puede leer —las
/// fracciones de `gain` son la mitad de las de `gain_muscle`— en vez de
/// escondida en una multiplicación por 0,5.
({CalorieTargetResult target, double rateKgPerWeek}) calorieTargetForPace({
  required int tdee,
  required GoalType goalType,
  required double fractionOfTdee,
  required BiologicalSex sex,
}) {
  if (tdee <= 0) {
    throw const CalculationError(
      'calorieTargetForPace',
      'tdee',
      'debe ser mayor que cero',
    );
  }
  if (fractionOfTdee < 0 ||
      fractionOfTdee > CalorieTargetRules.maxFractionOfTdee) {
    throw const CalculationError(
      'calorieTargetForPace',
      'fractionOfTdee',
      'debe estar entre 0 y 0,30 del gasto diario',
    );
  }

  final wanted = goalType == GoalType.maintain ? 0.0 : tdee * fractionOfTdee;
  var rate = roundTo(wanted * 7 / CalorieTargetRules.kcalPerKgOfFat, 2);
  if (rate > CalorieTargetRules.maxRateKgPerWeek) {
    rate = CalorieTargetRules.maxRateKgPerWeek;
  }

  final adjustment = CalorieTargetRules.dailyAdjustment(rate);
  final raw = switch (goalType) {
    GoalType.lose => tdee - adjustment,
    GoalType.maintain => tdee.toDouble(),
    GoalType.gain || GoalType.gainMuscle => tdee + adjustment,
  };

  final uncapped = roundHalfUp(raw);
  final minimum = CalorieTargetRules.minimumFor(sex);

  var target = uncapped;
  var clamped = false;
  if (target < minimum) {
    target = minimum;
    clamped = true;
  }
  if (target > CalorieTargetRules.absoluteMax) {
    target = CalorieTargetRules.absoluteMax;
    clamped = true;
  }

  return (
    target: CalorieTargetResult(
      target: target,
      clamped: clamped,
      uncappedTarget: uncapped,
      minimum: minimum,
    ),
    rateKgPerWeek: rate,
  );
}

/// Qué fracción del gasto representa un ritmo ya guardado.
///
/// Los objetivos viejos guardan kilos por semana y no fracciones: esto es el
/// puente para volver a calcularlos con la regla nueva. Se recorta al techo
/// porque un objetivo de antes de este cambio puede pedir el 45 % del gasto, y
/// hacer explotar la pantalla de quien lo tenga guardado no le arregla el
/// objetivo a nadie.
double fractionOfTdeeForRate({
  required double rateKgPerWeek,
  required int tdee,
}) {
  if (tdee <= 0) return 0;
  final fraction = CalorieTargetRules.dailyAdjustment(rateKgPerWeek) / tdee;
  return fraction.clamp(0.0, CalorieTargetRules.maxFractionOfTdee);
}

