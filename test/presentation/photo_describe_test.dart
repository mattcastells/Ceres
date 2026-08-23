// El paso entre sacar la foto y analizarla.
//
// La foto tiene un techo que no se sube mejorando el prompt: una empanada se ve
// igual sea de carne o de humita, y el modelo elige la más probable y se
// equivoca callado. Quien la sacó sabe la respuesta, y hasta acá no tenía dónde
// escribirla.
//
// Lo que estos tests fijan es lo que hace que el paso no moleste: que lo
// escrito llegue al análisis, y que **no escribir nada sea una respuesta
// válida** — si el campo fuera obligatorio, el paso sería un peaje.

import 'package:ceres/core/router/routes.dart';
import 'package:ceres/core/theme/app_theme.dart';
import 'package:ceres/core/utils/dates.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/presentation/components/system/buttons.dart';
import 'package:ceres/presentation/providers/app_providers.dart';
import 'package:ceres/presentation/screens/photo/photo_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _boot() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final store = await LocalStore.open();
  void Function() notify = () {};
  final repository = LocalRepository(store, onChanged: () => notify());
  final container = ProviderContainer(
    overrides: <Override>[repositoryProvider.overrideWithValue(repository)],
  );
  notify = () => container.read(appRevisionProvider.notifier).bump();
  return container;
}

/// El router de verdad no entra en un test de widget, pero la pantalla usa
/// `pushReplacement`: con estas dos rutas alcanza para ver adónde va.
Widget _wrap(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp.router(
    theme: NmAppTheme.dark(),
    locale: const Locale('es', 'AR'),
    routerConfig: GoRouter(
      initialLocation: Routes.photoDescribe,
      routes: <RouteBase>[
        GoRoute(
          path: Routes.photoDescribe,
          builder: (context, state) => const PhotoDescribeScreen(),
        ),
        GoRoute(
          path: Routes.photoAnalyzing,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('analizando'))),
        ),
      ],
    ),
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

  testWidgets('lo que se escribe viaja al análisis', (tester) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _boot();
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await _settle(tester);

    await tester.enterText(
      find.byType(TextField),
      '  empanadas de carne al horno  ',
    );
    await tester.tap(find.text('Analizar'));
    await _settle(tester);

    // Sin los espacios de los costados: lo que se manda es la aclaración, no
    // el tipeo.
    expect(container.read(photoNoteProvider), 'empanadas de carne al horno');
    expect(find.text('analizando'), findsOneWidget);
  });

  testWidgets('sin escribir nada se analiza igual', (tester) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _boot();
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await _settle(tester);

    // El campo vacío no bloquea: no hay validación de largo mínimo ni botón
    // deshabilitado esperando texto.
    await tester.tap(find.text('Analizar'));
    await _settle(tester);

    expect(container.read(photoNoteProvider), '');
    expect(find.text('analizando'), findsOneWidget);
  });

  testWidgets('hay un solo botón, y es el campo el que decide', (tester) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _boot();
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await _settle(tester);

    // Había un segundo botón —"Analizar sin describir"— que con el campo vacío
    // hacía lo mismo que este y con el campo lleno tiraba lo escrito: dos
    // botones para una decisión que el campo ya expresa solo.
    expect(find.widgetWithText(NmButton, 'Analizar'), findsOneWidget);
    expect(find.textContaining('sin describir'), findsNothing);

    // Borrar lo tipeado vuelve al caso vacío sin necesitar otro botón.
    await tester.enterText(find.byType(TextField), 'algo');
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Analizar'));
    await _settle(tester);

    expect(container.read(photoNoteProvider), '');
    expect(find.text('analizando'), findsOneWidget);
  });
}
