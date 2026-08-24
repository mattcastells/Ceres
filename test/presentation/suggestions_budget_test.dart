// Con cuántas calorías se piden las sugerencias.
//
// "¿Qué como?" preguntaba siempre por el saldo del día. Es la pregunta de la
// noche, cuando lo que importa es no pasarse; pero también se cocina al
// mediodía con el día entero por delante, y ahí el número que interesa es el
// del plato —"algo de 600"— y no el saldo. Con un solo modo esa pregunta no se
// podía hacer.
//
// Estos tests fijan las dos cosas que hacen que el modo nuevo no estorbe: que
// el saldo siga siendo el punto de partida, y que el número escrito sea el que
// se usa de verdad.
//
// Y una tercera, que se agregó después: **entrar no pide nada**. La pantalla
// preguntaba sola al abrirse, o sea que abrirla ya gastaba una de las 20
// consultas del día —incluso entrando sin querer— y lo hacía con el saldo que
// hubiera en ese instante, que casi nunca es el número con el que uno quiere
// buscar.
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

  testWidgets('entrar no le pregunta nada al modelo', (tester) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _boot();
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await _settle(tester);

    final restante = container.read(todaySummaryProvider).balance.remainingKcal;

    // El saldo del día sigue siendo el modo por omisión y se dice cuál es: lo
    // que cambió es que decirlo no es pedirlo.
    expect(find.text('Lo que me queda'), findsOneWidget);
    expect(find.text('Otro número'), findsOneWidget);
    expect(find.textContaining('$restante kcal que te quedan'), findsOneWidget);

    // El campo solo aparece cuando se lo pide.
    expect(find.text('Calorías del plato'), findsNothing);

    // Y lo que de verdad prueba este test: no salió ningún pedido.
    //
    // En este entorno `suggestMeals` lanza `providerUnavailable`, así que un
    // pedido disparado solo terminaría en un error en pantalla. Que se vea la
    // invitación —y ningún error— es la única forma de comprobar desde acá que
    // la pantalla no le habló al modelo por su cuenta, que era el bug: se
    // gastaba una de las 20 consultas del día con solo abrirla.
    expect(find.text('Decime con cuánto y busco'), findsOneWidget);
    expect(find.textContaining('necesitan cuenta'), findsNothing);
    expect(find.text('Buscar opciones'), findsOneWidget);
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
