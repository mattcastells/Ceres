// Medidas corporales dejó de ser una fila de píldoras.
//
// Antes había que elegir una métrica con una píldora para ver su número —las
// otras siete quedaban invisibles— y para cargar cualquiera había que abrir un
// sheet aparte. Ahora cada métrica del grupo es un campo con la última medida
// abajo, y se guardan todas juntas desde la misma pantalla.

import 'package:ceres/core/theme/app_theme.dart';
import 'package:ceres/core/utils/dates.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/domain/enums/enums.dart';
import 'package:ceres/domain/repositories/repositories.dart';
import 'package:ceres/presentation/components/system/inputs.dart';
import 'package:ceres/presentation/providers/app_providers.dart';
import 'package:ceres/presentation/screens/progress/progress_detail_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<(ProviderContainer, CeresRepositories)> _boot() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final store = await LocalStore.open();
  void Function() notify = () {};
  final repository = LocalRepository(store, onChanged: () => notify());
  final container = ProviderContainer(
    overrides: <Override>[repositoryProvider.overrideWithValue(repository)],
  );
  notify = () => container.read(appRevisionProvider.notifier).bump();
  return (container, repository);
}

Widget _wrap(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: NmAppTheme.dark(),
    locale: const Locale('es', 'AR'),
    home: const MeasurementsScreen(),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting(appLocale);
  });

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.physicalSize = const Size(1080, 2340);
    view.devicePixelRatio = 2.75;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('cada perímetro es un campo, no una píldora', (tester) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = (await _boot()).$1;
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await _settle(tester);

    // Los ocho perímetros, cada uno con su campo.
    expect(
      find.byType(NmNumberField),
      findsNWidgets(MeasurementMetric.inGroup(MeasurementGroup.perimeters).length),
    );
    expect(find.text('Cintura (mínima)'), findsOneWidget);
    expect(find.text('Cadera (máxima)'), findsOneWidget);
    // Sin registros lo dice, en vez de mostrar un vacío que parece un error.
    expect(find.text('Sin registros'), findsWidgets);
    expect(find.text('Guardar medidas'), findsOneWidget);
  });

  testWidgets('el campo muestra la última medida cargada', (tester) async {
    late ProviderContainer container;
    late CeresRepositories repo;
    await tester.runAsync(() async {
      final booted = await _boot();
      container = booted.$1;
      repo = booted.$2;
      await repo.logMeasurement(
        metric: MeasurementMetric.waist,
        value: 82.5,
        date: today().subtract(const Duration(days: 4)),
      );
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await _settle(tester);

    expect(find.textContaining('Última: 82,5 cm'), findsOneWidget);
  });

  testWidgets('se cargan varias medidas de una y se guardan juntas', (
    tester,
  ) async {
    late ProviderContainer container;
    late CeresRepositories repo;
    await tester.runAsync(() async {
      final booted = await _boot();
      container = booted.$1;
      repo = booted.$2;
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await _settle(tester);

    await tester.enterText(find.byType(TextField).at(0), '32,5');
    await tester.enterText(find.byType(TextField).at(3), '84');
    await tester.pump();

    // Con ocho campos el botón queda abajo del pliegue: se lo trae a la vista
    // como haría cualquiera antes de tocarlo.
    await tester.ensureVisible(find.text('Guardar medidas'));
    await tester.pump();
    await tester.tap(find.text('Guardar medidas'));
    await _settle(tester);

    expect(repo.measurements(MeasurementMetric.arm).last.value, 32.5);
    expect(repo.measurements(MeasurementMetric.waist).last.value, 84);
  });

  testWidgets('un valor imposible se marca en su propio campo', (tester) async {
    late ProviderContainer container;
    late CeresRepositories repo;
    await tester.runAsync(() async {
      final booted = await _boot();
      container = booted.$1;
      repo = booted.$2;
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await _settle(tester);

    // La cintura va de 40 a 200 cm: 8 es un cero de menos.
    await tester.enterText(find.byType(TextField).at(3), '8');
    await tester.pump();
    // Con ocho campos el botón queda abajo del pliegue: se lo trae a la vista
    // como haría cualquiera antes de tocarlo.
    await tester.ensureVisible(find.text('Guardar medidas'));
    await tester.pump();
    await tester.tap(find.text('Guardar medidas'));
    await _settle(tester);

    expect(find.textContaining('Va de 40,0 a 200,0 cm'), findsOneWidget);
    expect(repo.measurements(MeasurementMetric.waist), isEmpty);
  });
}
