// El reporte con IA: abrir lee lo guardado, generar es un botón, y el texto
// del modelo va separado —y etiquetado— de los números que calculó el
// servidor.

import 'dart:async';

import 'package:ceres/core/error/app_error.dart';
import 'package:ceres/core/theme/app_theme.dart';
import 'package:ceres/data/remote/care_report_client.dart';
import 'package:ceres/domain/models/weekly_report.dart';
import 'package:ceres/presentation/providers/auth_providers.dart';
import 'package:ceres/presentation/providers/care_providers.dart';
import 'package:ceres/presentation/screens/progress/weekly_report_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

final WeeklyReport _report = WeeklyReport(
  id: 'r1',
  periodFrom: DateTime(2026, 11, 3),
  periodTo: DateTime(2026, 11, 9),
  createdAt: DateTime(2026, 11, 10, 12),
  title: 'Una semana pareja',
  summary: 'Registraste cinco de siete días.',
  achievements: const <String>['Desayunaste todos los días'],
  suggestions: const <String>['Probá sumar una fruta a la merienda'],
  metrics: const WeeklyMetrics(
    daysLogged: 5,
    periodDays: 7,
    kcalAverage: 1850,
    kcalTarget: 2000,
  ),
);

class _FakeReportClient implements CareReportClient {
  _FakeReportClient({this.stored, this.generated, this.error});

  WeeklyReport? stored;
  final WeeklyReport? generated;
  final AppError? error;
  int generateCalls = 0;
  Completer<void>? gate;

  @override
  Future<WeeklyReport?> latestWeekly({int days = 7}) async => stored;

  @override
  Future<WeeklyReport> generateWeekly({int days = 7}) async {
    generateCalls++;
    await gate?.future;
    if (error != null) throw error!;
    stored = generated;
    return generated!;
  }
}

Future<ProviderContainer> _boot(CareReportClient client) async {
  final container = ProviderContainer(
    overrides: <Override>[
      isCloudEnabledProvider.overrideWithValue(true),
      careReportClientProvider.overrideWithValue(client),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Widget _wrap(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: NmAppTheme.light(),
    locale: const Locale('es', 'AR'),
    home: const WeeklyReportScreen(),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('es_AR'));

  testWidgets('muestra el último resumen sin generar uno nuevo', (
    tester,
  ) async {
    final client = _FakeReportClient(stored: _report);
    await tester.pumpWidget(_wrap(await _boot(client)));
    await _settle(tester);

    expect(find.text('Una semana pareja'), findsOneWidget);
    expect(find.text('CALCULADO CON TUS REGISTROS'), findsOneWidget);
    expect(find.text('5 de 7'), findsOneWidget);
    expect(
      find.text('Redactado con IA a partir de tus registros'),
      findsOneWidget,
    );
    expect(find.text('Probá sumar una fruta a la merienda'), findsOneWidget);
    expect(client.generateCalls, 0);
  });

  testWidgets('sin resumen guardado ofrece generarlo y lo muestra', (
    tester,
  ) async {
    final client = _FakeReportClient(generated: _report)
      ..gate = Completer<void>();
    await tester.pumpWidget(_wrap(await _boot(client)));
    await _settle(tester);

    expect(find.text('Generar reporte'), findsOneWidget);
    await tester.tap(find.text('Generar reporte'));
    await tester.pump();
    expect(find.text('Puede tardar hasta un minuto.'), findsOneWidget);

    client.gate!.complete();
    await _settle(tester);
    expect(client.generateCalls, 1);
    expect(find.text('Una semana pareja'), findsOneWidget);
  });

  testWidgets('otros errores muestran el mensaje del servidor', (tester) async {
    final client = _FakeReportClient(
      error: const AppError(
        code: ApiErrorCode.noData,
        message: 'No hay registros en la última semana para armar el resumen.',
      ),
    );
    await tester.pumpWidget(_wrap(await _boot(client)));
    await _settle(tester);

    await tester.tap(find.text('Generar reporte'));
    await _settle(tester);
    expect(
      find.text('No hay registros en la última semana para armar el resumen.'),
      findsOneWidget,
    );
    expect(find.text('Esto usa IA'), findsNothing);
  });
}
