// El resumen semanal con IA: cómo se lee lo que guarda `care-report` y qué
// tarjetas de números se arman.
//
// Dos reglas que se prueban acá: los números salen de `metricas` —los calculó
// el servidor, no el modelo— y un dato que falta **no se muestra en cero**:
// una semana sin pesajes no tuvo "0 kg de cambio".

import 'package:ceres/core/error/app_error.dart';
import 'package:ceres/data/remote/care_report_client.dart';
import 'package:ceres/domain/models/weekly_report.dart';
import 'package:ceres/presentation/screens/progress/weekly_report_screen.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _report({Object? metricas, Object? content}) =>
    <String, dynamic>{
      'id': 'r1',
      'kind': 'patient_weekly',
      'patient_id': 'u1',
      'period_from': '2026-11-03',
      'period_to': '2026-11-09',
      'created_at': '2026-11-10T12:00:00Z',
      'content':
          content ??
          <String, dynamic>{
            'titulo': 'Una semana pareja',
            'resumen': 'Registraste cinco de siete días.',
            'logros': <String>['Desayunaste todos los días', ''],
            'patrones': <String>['Los fines de semana cenás más tarde'],
            'sugerencias': <String>['Probá sumar una fruta a la merienda'],
            'cierre': 'Seguí así.',
            'metricas': metricas,
          },
    };

const Map<String, dynamic> _metricas = <String, dynamic>{
  'diasConRegistro': 5,
  'periodo': <String, dynamic>{
    'desde': '2026-11-03',
    'hasta': '2026-11-09',
    'dias': 7,
  },
  'calorias': <String, dynamic>{
    'promedio': 1850,
    'objetivo': 2000,
    'diasDentroDelObjetivo': 3,
    'porDia': <dynamic>[],
  },
  'macros': <String, dynamic>{
    'proteinaPromedioG': 92,
    'objetivoProteinaG': 110,
  },
  'peso': <String, dynamic>{'inicial': 80.2, 'final': 79.8, 'cambio': -0.4},
  'actividad': <String, dynamic>{'sesiones': 3, 'minutos': 140},
};

void main() {
  group('WeeklyReport.fromRow', () {
    test('lee el texto y los números', () {
      final r = WeeklyReport.fromRow(_report(metricas: _metricas))!;
      expect(r.title, 'Una semana pareja');
      expect(r.periodFrom, DateTime(2026, 11, 3));
      expect(r.periodTo, DateTime(2026, 11, 9));
      // El vacío se descarta: no hay viñetas en blanco.
      expect(r.achievements, <String>['Desayunaste todos los días']);
      expect(r.suggestions, hasLength(1));
      expect(r.closing, 'Seguí así.');

      final m = r.metrics;
      expect(m.daysLogged, 5);
      expect(m.periodDays, 7);
      expect(m.kcalAverage, 1850);
      expect(m.kcalTarget, 2000);
      expect(m.daysWithinTarget, 3);
      expect(m.proteinAverageG, 92);
      expect(m.proteinTargetG, 110);
      expect(m.weightChangeKg, -0.4);
      expect(m.activityMinutes, 140);
    });

    test('sin título o sin resumen no hay informe', () {
      expect(
        WeeklyReport.fromRow(
          _report(content: <String, dynamic>{'resumen': 'algo'}),
        ),
        isNull,
      );
      expect(WeeklyReport.fromRow(<String, dynamic>{'id': 'x'}), isNull);
      expect(WeeklyReport.fromRow('basura'), isNull);
    });

    test('macros y peso en null no rompen la lectura', () {
      final r = WeeklyReport.fromRow(
        _report(
          metricas: <String, dynamic>{
            'diasConRegistro': 2,
            'macros': null,
            'peso': null,
          },
        ),
      )!;
      expect(r.metrics.proteinAverageG, isNull);
      expect(r.metrics.weightChangeKg, isNull);
    });
  });

  group('tarjetas de números', () {
    test('las cuatro, cuando están todos los datos', () {
      final tiles = weeklyMetricTiles(WeeklyMetrics.fromJson(_metricas));
      expect(tiles.map((t) => t.label), <String>[
        'Días con registro',
        'Promedio diario',
        'Proteína promedio',
        'Cambio de peso',
      ]);
      expect(tiles.first.value, '5 de 7');
      expect(tiles[1].caption, contains('objetivo'));
      expect(tiles.last.value, contains('kg'));
    });

    test('lo que falta no aparece, en vez de aparecer en cero', () {
      final tiles = weeklyMetricTiles(
        WeeklyMetrics.fromJson(<String, dynamic>{'diasConRegistro': 4}),
      );
      expect(tiles.map((t) => t.label), <String>['Días con registro']);
      expect(weeklyMetricTiles(const WeeklyMetrics()), isEmpty);
    });
  });

  group('CareReportClient', () {
    test('parseGenerated lee { report }', () {
      final r = CareReportClient.parseGenerated(<String, dynamic>{
        'report': _report(metricas: _metricas),
        'model': 'gemini',
        'promptVersion': 'r1',
      });
      expect(r.id, 'r1');
    });

    test('una respuesta ilegible es un error legible, no un TypeError', () {
      expect(
        () => CareReportClient.parseGenerated(<String, dynamic>{'nada': 1}),
        throwsA(
          isA<AppError>().having(
            (e) => e.code,
            'code',
            ApiErrorCode.aiInvalidResponse,
          ),
        ),
      );
    });

    test('traduce los errores del servidor con su mensaje', () {
      AppError t(String code, String message) =>
          CareReportClient.translate(<String, dynamic>{
            'error': <String, dynamic>{'code': code, 'message': message},
          });

      expect(
        t('ERR_QUOTA_EXCEEDED', 'Llegaste a los 5 informes de hoy.').message,
        'Llegaste a los 5 informes de hoy.',
      );
      expect(t('ERR_NO_DATA', 'No hay registros.').code, ApiErrorCode.noData);
      expect(
        CareReportClient.translate(null).code,
        ApiErrorCode.upstreamFailed,
      );
    });
  });
}
