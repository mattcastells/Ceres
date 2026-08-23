import 'package:flutter/widgets.dart';

import '../../../core/utils/formats.dart';
import '../../../domain/enums/enums.dart';
import '../../../domain/repositories/repositories.dart';

/// Los campos de medidas corporales de una fecha, con su validación y su
/// guardado.
///
/// Vive aparte porque hay **dos** pantallas que cargan lo mismo —el sheet de
/// "Registrar medidas" y la pantalla de Medidas corporales— y la regla de qué
/// pasa con un campo en blanco no puede estar escrita dos veces: vaciar un
/// campo significa "esto no se midió" y borra el registro que hubiera. Dos
/// copias de esa regla es una copia que en algún momento borra de menos o de
/// más.
class MeasurementDraft {
  /// Un controlador por métrica, en los tres grupos a la vez: cambiar de grupo
  /// no puede tirar lo que se venía escribiendo.
  final Map<MeasurementMetric, TextEditingController> fields =
      <MeasurementMetric, TextEditingController>{};

  final Map<MeasurementMetric, String> errors = <MeasurementMetric, String>{};

  /// Trae lo que ya haya cargado en [date] para poder corregirlo.
  void loadFrom(CeresRepositories repo, DateTime date) {
    final existing = repo.measurementsOn(date);
    for (final metric in MeasurementMetric.values) {
      final text = existing[metric] == null
          ? ''
          : Fmt.decimal1(existing[metric]!.value);
      final field = fields[metric];
      if (field == null) {
        fields[metric] = TextEditingController(text: text);
      } else {
        field.text = text;
      }
    }
    errors.clear();
  }

  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
  }

  TextEditingController controller(MeasurementMetric metric) =>
      fields[metric] ??= TextEditingController();

  double? parse(MeasurementMetric metric) {
    final raw = controller(metric).text.replaceAll(',', '.').trim();
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  /// Sumatoria de los pliegues cargados. Se devuelve con cuántos, porque una
  /// suma de cuatro y una de siete no son el mismo número ni se comparan.
  (double sum, int count) get foldSum {
    var sum = 0.0;
    var count = 0;
    for (final metric in MeasurementMetric.folds) {
      final value = parse(metric);
      if (value != null && value >= metric.min && value <= metric.max) {
        sum += value;
        count++;
      }
    }
    return (sum, count);
  }

  /// Valida y guarda. Devuelve cuántas medidas quedaron escritas, o `null` si
  /// no guardó nada: en ese caso [errors] dice por qué y de qué campo.
  Future<int?> commit(CeresRepositories repo, DateTime date) async {
    final found = <MeasurementMetric, String>{};
    final toSave = <MeasurementMetric, double>{};

    for (final metric in MeasurementMetric.values) {
      final raw = controller(metric).text.trim();
      if (raw.isEmpty) continue;
      final value = parse(metric);
      if (value == null || value < metric.min || value > metric.max) {
        found[metric] =
            'Va de ${Fmt.decimal1(metric.min)} a ${Fmt.decimal1(metric.max)}'
            '${metric.unitLabel.isEmpty ? '' : ' ${metric.unitLabel}'}.';
        continue;
      }
      toSave[metric] = value;
    }

    errors
      ..clear()
      ..addAll(found);
    if (found.isNotEmpty) return null;

    if (toSave.isEmpty) {
      errors[MeasurementMetric.waist] = 'Cargá al menos una.';
      return null;
    }

    // Lo que se dejó en blanco y ya existía se borra: vaciar un campo es la
    // forma natural de decir "esto no se midió".
    final existing = repo.measurementsOn(date);
    for (final entry in existing.entries) {
      if (!toSave.containsKey(entry.key)) {
        await repo.deleteMeasurement(entry.value.id);
      }
    }
    for (final entry in toSave.entries) {
      await repo.logMeasurement(
        metric: entry.key,
        value: entry.value,
        date: date,
      );
    }
    return toSave.length;
  }
}
