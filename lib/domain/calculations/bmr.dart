import '../../core/error/app_error.dart';
import '../enums/enums.dart';
import 'rounding.dart';

/// Rangos válidos compartidos por las fórmulas corporales (§1).
abstract final class BodyRanges {
  static const double minWeightKg = 25;
  static const double maxWeightKg = 400;
  static const double minHeightCm = 90;
  static const double maxHeightCm = 250;
  static const int minAgeYears = 13;
  static const int maxAgeYears = 100;
}

/// BMR con Mifflin-St Jeor (11-calculation-rules.md §1, decisión D-03).
///
/// ```
/// bmr(male)        = 10 × pesoKg + 6,25 × alturaCm − 5 × edad + 5
/// bmr(female)      = 10 × pesoKg + 6,25 × alturaCm − 5 × edad − 161
/// bmr(unspecified) = promedio de ambas
/// ```
int bmrMifflinStJeor({
  required double weightKg,
  required double heightCm,
  required int ageYears,
  required BiologicalSex sex,
}) {
  if (weightKg < BodyRanges.minWeightKg || weightKg > BodyRanges.maxWeightKg) {
    throw const CalculationError('bmr', 'weightKg', 'debe estar entre 25 y 400 kg');
  }
  if (heightCm < BodyRanges.minHeightCm || heightCm > BodyRanges.maxHeightCm) {
    throw const CalculationError('bmr', 'heightCm', 'debe estar entre 90 y 250 cm');
  }
  if (ageYears < BodyRanges.minAgeYears || ageYears > BodyRanges.maxAgeYears) {
    throw const CalculationError('bmr', 'ageYears', 'debe estar entre 13 y 100 años');
  }

  final base = 10 * weightKg + 6.25 * heightCm - 5 * ageYears;
  final value = switch (sex) {
    BiologicalSex.male => base + 5,
    BiologicalSex.female => base - 161,
    // Promedio de ambas: base + (5 + (−161)) / 2.
    BiologicalSex.unspecified => base + (5 - 161) / 2,
  };
  return roundHalfUp(value);
}

/// La fecha de nacimiento más vieja que aceptan las fórmulas: hoy menos
/// [BodyRanges.maxAgeYears]. Es el `firstDate` de los selectores de
/// nacimiento; con el 1920 genérico se podía elegir alguien de 105 años y
/// `bmrMifflinStJeor` lanzaba adentro de un `build`.
DateTime earliestBirthDate({DateTime? on}) {
  final ref = on ?? DateTime.now();
  return DateTime(ref.year - BodyRanges.maxAgeYears, ref.month, ref.day);
}

/// Edad en años enteros a la fecha de referencia.
int ageFromBirthDate(DateTime birthDate, {DateTime? on}) {
  final ref = on ?? DateTime.now();
  var age = ref.year - birthDate.year;
  final hadBirthday =
      ref.month > birthDate.month ||
      (ref.month == birthDate.month && ref.day >= birthDate.day);
  if (!hadBirthday) age -= 1;
  return age;
}
