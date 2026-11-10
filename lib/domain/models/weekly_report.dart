/// El resumen semanal con IA (`care_reports`, `kind = patient_weekly`).
///
/// Tiene dos mitades que **no se mezclan en pantalla**: el texto, que redactó
/// el modelo, y [metrics], que calculó el servidor a partir de los registros.
/// Los números se muestran como datos y con su propia etiqueta; el modelo no
/// inventa ninguno, solo escribe sobre ellos. Es la regla de siempre en Ceres
/// —ningún número inventado— aplicada a un texto largo.
class WeeklyReport {
  const WeeklyReport({
    required this.id,
    required this.periodFrom,
    required this.periodTo,
    required this.createdAt,
    required this.title,
    required this.summary,
    required this.metrics,
    this.achievements = const <String>[],
    this.patterns = const <String>[],
    this.suggestions = const <String>[],
    this.closing = '',
  });

  final String id;
  final DateTime periodFrom;
  final DateTime periodTo;
  final DateTime createdAt;

  final String title;
  final String summary;
  final List<String> achievements;
  final List<String> patterns;
  final List<String> suggestions;
  final String closing;

  final WeeklyMetrics metrics;

  /// Lee una fila de `care_reports` (o el `report` que devuelve la función),
  /// o `null` si le falta lo indispensable.
  ///
  /// Sin título o sin resumen no hay informe que mostrar; el resto es
  /// opcional y se completa vacío. La forma la decide el servidor, así que se
  /// la trata como entrada y no como promesa.
  static WeeklyReport? fromRow(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final from = _date(raw['period_from']);
    final to = _date(raw['period_to']);
    final content = raw['content'];
    if (id is! String || id.isEmpty || from == null || to == null) return null;
    if (content is! Map) return null;

    final title = _text(content['titulo']);
    final summary = _text(content['resumen']);
    if (title == null || summary == null) return null;

    final created = raw['created_at'];
    return WeeklyReport(
      id: id,
      periodFrom: from,
      periodTo: to,
      createdAt:
          (created is String ? DateTime.tryParse(created)?.toLocal() : null) ??
          DateTime.now(),
      title: title,
      summary: summary,
      achievements: _texts(content['logros']),
      patterns: _texts(content['patrones']),
      suggestions: _texts(content['sugerencias']),
      closing: _text(content['cierre']) ?? '',
      metrics: WeeklyMetrics.fromJson(content['metricas']),
    );
  }

  static DateTime? _date(Object? raw) {
    if (raw is! String) return null;
    final parsed = DateTime.tryParse(raw);
    return parsed == null
        ? null
        : DateTime(parsed.year, parsed.month, parsed.day);
  }

  static String? _text(Object? raw) =>
      raw is String && raw.trim().isNotEmpty ? raw.trim() : null;

  static List<String> _texts(Object? raw) => raw is List
      ? <String>[
          for (final item in raw)
            if (_text(item) case final String text) text,
        ]
      : const <String>[];
}

/// Los números del período, tal como los calculó el servidor.
///
/// Todo es opcional: una semana sin pesajes no tiene cambio de peso, una
/// cuenta sin objetivo no tiene contra qué comparar. Un campo que falta se
/// muestra como que falta, nunca como cero.
class WeeklyMetrics {
  const WeeklyMetrics({
    this.daysLogged,
    this.periodDays,
    this.kcalAverage,
    this.kcalTarget,
    this.daysWithinTarget,
    this.proteinAverageG,
    this.proteinTargetG,
    this.weightChangeKg,
    this.activitySessions,
    this.activityMinutes,
  });

  final int? daysLogged;
  final int? periodDays;
  final int? kcalAverage;
  final int? kcalTarget;
  final int? daysWithinTarget;
  final int? proteinAverageG;
  final int? proteinTargetG;
  final double? weightChangeKg;
  final int? activitySessions;
  final int? activityMinutes;

  static WeeklyMetrics fromJson(Object? raw) {
    if (raw is! Map) return const WeeklyMetrics();
    final periodo = raw['periodo'];
    final calorias = raw['calorias'];
    final macros = raw['macros'];
    final peso = raw['peso'];
    final actividad = raw['actividad'];

    return WeeklyMetrics(
      daysLogged: _int(raw['diasConRegistro']),
      periodDays: periodo is Map ? _int(periodo['dias']) : null,
      kcalAverage: calorias is Map ? _int(calorias['promedio']) : null,
      kcalTarget: calorias is Map ? _int(calorias['objetivo']) : null,
      daysWithinTarget: calorias is Map
          ? _int(calorias['diasDentroDelObjetivo'])
          : null,
      proteinAverageG: macros is Map ? _int(macros['proteinaPromedioG']) : null,
      proteinTargetG: macros is Map ? _int(macros['objetivoProteinaG']) : null,
      weightChangeKg: peso is Map && peso['cambio'] is num
          ? (peso['cambio'] as num).toDouble()
          : null,
      activitySessions: actividad is Map ? _int(actividad['sesiones']) : null,
      activityMinutes: actividad is Map ? _int(actividad['minutos']) : null,
    );
  }

  static int? _int(Object? raw) => raw is num ? raw.round() : null;
}
