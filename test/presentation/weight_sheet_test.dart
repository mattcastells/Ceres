// El bug reportado: "quiero agregar mi peso desde Inicio y no funciona".
//
// No era el sheet que no abría ni la navegación: era que **"Guardar" no
// guardaba**. Un cambio de más de 3 kg respecto del último registro mostraba
// un cartel dentro del mismo sheet y volvía sin escribir nada; había que tocar
// "Guardar" una segunda vez. Y si en el medio se tocaba el campo —lo primero
// que hace cualquiera cuando algo no pasó— el aviso se reseteaba y el botón
// volvía a no hacer nada. Indistinguible de un botón roto.
//
// Estos tests fijan el contrato: un toque en "Guardar" guarda, o pregunta con
// un botón que confirma al lado. Nunca no hace nada.

import 'package:ceres/core/theme/app_theme.dart';
import 'package:ceres/core/utils/dates.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/domain/repositories/repositories.dart';
import 'package:ceres/presentation/providers/app_providers.dart';
import 'package:ceres/presentation/screens/weight/weight_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<(ProviderContainer, CeresRepositories)> _boot({
  double? pesoPrevio,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final store = await LocalStore.open();
  void Function() notify = () {};
  final repository = LocalRepository(store, onChanged: () => notify());
  if (pesoPrevio != null) {
    await repository.logWeight(weightKg: pesoPrevio, date: today());
  }
  final container = ProviderContainer(
    overrides: <Override>[repositoryProvider.overrideWithValue(repository)],
  );
  notify = () => container.read(appRevisionProvider.notifier).bump();
  return (container, repository);
}

/// Una pantalla mínima con un botón que abre el sheet, para no arrastrar Inicio
/// entero a un test sobre el sheet.
Widget _wrap(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: NmAppTheme.dark(),
    locale: const Locale('es', 'AR'),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showWeightSheet(context),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 700));
}

Future<void> _abrir(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(_wrap(container));
  await tester.pump();
  await tester.tap(find.text('abrir'));
  await _settle(tester);
  expect(find.text('Nota (opcional)'), findsOneWidget);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting(appLocale);
  });

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.physicalSize = const Size(1179, 2556);
    view.devicePixelRatio = 3;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('sin registro previo, un toque en Guardar alcanza', (
    tester,
  ) async {
    late ProviderContainer container;
    late CeresRepositories repo;
    await tester.runAsync(() async {
      final booted = await _boot();
      container = booted.$1;
      repo = booted.$2;
    });
    addTearDown(() => container.dispose());

    await _abrir(tester, container);
    await tester.enterText(find.byType(TextField).first, '77,4');
    await tester.pump();
    await tester.tap(find.text('Guardar'));
    await _settle(tester);

    expect(repo.currentWeightKg, 77.4);
  });

  testWidgets('un cambio grande pregunta, y confirmar guarda en el mismo paso', (
    tester,
  ) async {
    late ProviderContainer container;
    late CeresRepositories repo;
    await tester.runAsync(() async {
      final booted = await _boot(pesoPrevio: 100);
      container = booted.$1;
      repo = booted.$2;
    });
    addTearDown(() => container.dispose());

    await _abrir(tester, container);
    await tester.enterText(find.byType(TextField).first, '77,4');
    await tester.pump();
    await tester.tap(find.text('Guardar'));
    await _settle(tester);

    // El pedido de confirmación trae el botón que confirma.
    expect(find.text('¿Confirmás ese peso?'), findsOneWidget);
    expect(repo.currentWeightKg, 100.0);

    await tester.tap(find.text('Sí, guardar'));
    await _settle(tester);

    expect(repo.currentWeightKg, 77.4);
  });

  testWidgets('un cambio grande se puede corregir sin guardar', (tester) async {
    late ProviderContainer container;
    late CeresRepositories repo;
    await tester.runAsync(() async {
      final booted = await _boot(pesoPrevio: 100);
      container = booted.$1;
      repo = booted.$2;
    });
    addTearDown(() => container.dispose());

    await _abrir(tester, container);
    await tester.enterText(find.byType(TextField).first, '17,4');
    await tester.pump();
    await tester.tap(find.text('Guardar'));
    await _settle(tester);

    // 17,4 kg está fuera de rango: eso se atrapa antes de preguntar nada.
    expect(find.text('Ingresá un peso entre 25 y 400 kg.'), findsOneWidget);
    expect(find.text('¿Confirmás ese peso?'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '71,4');
    await tester.pump();
    await tester.tap(find.text('Guardar'));
    await _settle(tester);

    await tester.tap(find.text('Corregir'));
    await _settle(tester);

    expect(repo.currentWeightKg, 100.0);
    // El sheet sigue abierto para corregir el número.
    expect(find.text('Nota (opcional)'), findsOneWidget);
  });
}
