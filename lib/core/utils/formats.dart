import 'package:intl/intl.dart';

import '../../domain/enums/enums.dart';
import 'dates.dart';

/// Formateo para mostrar. La conversión a unidades imperiales es de
/// presentación: el almacenamiento siempre es kg, cm, metros, minutos, kcal.
abstract final class Fmt {
  static final NumberFormat _int = NumberFormat.decimalPattern(appLocale);
  static final NumberFormat _one = NumberFormat('#,##0.0', appLocale);
  static final NumberFormat _two = NumberFormat('#,##0.00', appLocale);

  /// "2.100" — miles con punto, como corresponde al español rioplatense.
  static String integer(num v) => _int.format(v.round());

  static String decimal1(num v) => _one.format(v);

  static String decimal2(num v) => _two.format(v);

  /// "2.100 kcal".
  static String kcal(num v) => '${integer(v)} kcal';

  /// "≈ 184 kcal" — prefijo obligatorio en todo gasto estimado (RN-03).
  static String estimatedKcal(num v) => '≈ ${integer(v)} kcal';

  /// "2 tragos" · "1,5 tragos" — unidades de bebida estándar.
  ///
  /// Se dice "tragos" y no "UBE" porque nadie habla en unidades de bebida
  /// estándar; el número **es** la UBE, que es lo que permite sumar una
  /// cerveza y un whisky. La equivalencia está explicada en la pantalla de
  /// carga, que es donde importa entenderla.
  static String standardDrinks(double v) {
    final n = v == v.roundToDouble() ? integer(v) : decimal1(v);
    return v == 1 ? '$n trago' : '$n tragos';
  }

  /// "+120" / "−80" con el signo tipográfico correcto.
  static String signed(num v) {
    if (v == 0) return '0';
    return v > 0 ? '+${integer(v)}' : '−${integer(v.abs())}';
  }

  static String signedDecimal1(num v) {
    if (v == 0) return '0,0';
    return v > 0 ? '+${decimal1(v)}' : '−${decimal1(v.abs())}';
  }

  /// "45 min" · "1 h 30 min" · "2 h".
  static String duration(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '$h h' : '$h h $m min';
  }

  /// "01:30" — el campo libre de `DurationInput` (D-22).
  static String hhmm(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  static int? parseHhmm(String raw) {
    final parts = raw.trim().split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || m < 0 || m > 59 || h < 0) return null;
    return h * 60 + m;
  }

  /// "72,4 kg" o su equivalente imperial, según el perfil.
  static String weight(double kg, UnitSystem units) =>
      '${weightValue(kg, units)} ${weightUnit(units)}';

  static String weightValue(double kg, UnitSystem units) =>
      decimal1(toWeightUnits(kg, units));

  static String weightUnit(UnitSystem units) =>
      units == UnitSystem.metric ? 'kg' : 'lb';

  /// Una variación de peso ("−0,4 kg" / "−0,9 lb"), en las unidades del
  /// perfil. Escrita a mano con `weightUnit` al lado quedaba el número en kilos
  /// y la etiqueta en libras.
  static String signedWeight(double kg, UnitSystem units) =>
      '${signedDecimal1(toWeightUnits(kg, units))} ${weightUnit(units)}';

  /// Kilos → la unidad del perfil, como número.
  static double toWeightUnits(double kg, UnitSystem units) =>
      units == UnitSystem.metric ? kg : kg * _lbPerKg;

  /// La unidad del perfil → kilos, para guardar lo que se escribió.
  static double fromWeightUnits(double value, UnitSystem units) =>
      units == UnitSystem.metric ? value : value / _lbPerKg;

  static const double _lbPerKg = 2.20462;

  /// "175 cm" o "5' 9\"".
  static String height(double cm, UnitSystem units) {
    if (units == UnitSystem.metric) return '${cm.round()} cm';
    final totalInches = cm / 2.54;
    final feet = totalInches ~/ 12;
    final inches = (totalInches % 12).round();
    return "$feet' $inches\"";
  }

  /// "5,20 km" o "3,23 mi".
  static String distance(int meters, UnitSystem units) =>
      units == UnitSystem.metric
      ? '${decimal2(meters / 1000)} km'
      : '${decimal2(meters / 1609.344)} mi';

  static String distanceUnit(UnitSystem units) =>
      units == UnitSystem.metric ? 'km' : 'mi';

  /// "1.245" pasos.
  static String steps(int v) => integer(v);

  /// "3,5" — MET siempre con un decimal.
  static String met(double v) => decimal1(v);

  /// "45 %".
  static String percent(num v) => '${integer(v)} %';

  /// "128 g".
  static String grams(num v) => '${integer(v)} g';
}
