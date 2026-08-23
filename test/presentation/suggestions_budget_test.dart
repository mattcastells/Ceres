// Con cuántas calorías se piden las sugerencias.
//
// "¿Qué como?" preguntaba siempre por el saldo del día. Es la pregunta de la
// noche, cuando lo que importa es no pasarse; pero también se cocina al
// mediodía con el día entero por delante, y ahí el número que interesa es el
// del plato —"algo de 600"— y no el saldo. Con un solo modo esa pregunta no se
// podía hacer.
//
// Estos tests fijan las dos cosas que hacen que el modo nuevo no estorbe: que
// el saldo siga siendo lo que pasa sin tocar nada, y que el número escrito sea
// el que se usa de verdad.
//
// El pedido falla en este entorno —no hay servidor, `suggestMeals` lanza
// `providerUnavailable`— y no importa: lo que se comprueba es con qué
// presupuesto salió el pedido, y eso la pantalla lo dice antes de la respuesta.

import 'package:ceres/core/theme/app_theme.dart';
import 'package:ceres/core/utils/dates.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/presentation/components/system/buttons.dart';
import 'package:ceres/presentation/providers/app_providers.dart';
import 'package:ceres/presentation/screens/meal/suggestions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _boot() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final store = await LocalStore.open();
  // Un día cargado: sin él no hay saldo contra el que comparar.
  store.seed();

  void Function() notify = () {};
  final repository = LocalRepository(store, onChanged: () => notify());
  final container = ProviderContainer(
    overrides: <Override>[repositoryProvider.overrideWithValue(repository)],
  );
  notify = () => container.read(appRevisionProvider.notifier).bump();
  return container;
}

Widget _wrap(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: NmAppTheme.dark(),
    locale: const Locale('es', 'AR'),
    home: const SuggestionsScreen(),
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
    view.physicalSize = const Size(1179, 2556);
    view.devicePixelRatio = 3;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('sin tocar nada pregunta por el saldo del día', (tester) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _boot();
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await _settle(tester);

    final restante = container.read(todaySummaryProvider).balance.remainingKcal;

    // El camino corto no cambió: se entra y ya está pidiendo, sin un paso de
    // configuración antes.
    expect(find.text('Lo que me queda'), findsOneWidget);
    expect(find.text('Otro número'), findsOneWidget);
    expect(find.textContaining('$restante kcal que te quedan'), findsOneWidget);

    // El campo solo aparece cuando se lo pide.
    expect(find.text('Calorías del plato'), findsNothing);
  });

  testWidgets('"Otro número" arranca del saldo y se puede corregir', (
    tester,
  ) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _boot();
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await _settle(tester);

    final restante = container.read(todaySummaryProvider).balance.remainingKcal;

    await tester.tap(find.text('Otro número'));
    await _settle(tester);

    // El saldo como punto de partida: casi siempre se lo quiere correr un poco,
    // no escribirlo de cero.
    expect(find.text('Calorías del plato'), findsOneWidget);
    expect(find.widgetWithText(TextField, '$restante'), findsOneWidget);
  });

  testWidgets('el número escrito es el que se pide', (tester) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _boot();
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await _settle(tester);

    await tester.tap(find.text('Otro número'));
    await _settle(tester);

    await tester.enterText(find.byType(TextField), '600');
    await _settle(tester);
    await tester.tap(find.text('Buscar opciones'));
    await _settle(tester);

    // El texto describe el pedido que salió, no lo que está elegido ahora: por
    // eso decir "600" prueba que el pedido usó 600 y no el saldo del día.
    expect(find.text('Tres platos de hasta 600 kcal.'), findsOneWidget);
    expect(find.textContaining('que te quedan'), findsNothing);
  });

  testWidgets('sin número no se puede pedir', (tester) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _boot();
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await _settle(tester);

    await tester.tap(find.text('Otro número'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), '');
    await _settle(tester);

    // Un pedido con presupuesto 0 no tiene respuesta posible: se frena acá y no
    // se gasta una llamada para que el servidor conteste lo obvio.
    final boton = tester.widget<NmButton>(
      find.widgetWithText(NmButton, 'Buscar opciones'),
    );
    expect(boton.onPressed, isNull);
  });
}
