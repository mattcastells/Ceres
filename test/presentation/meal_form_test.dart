// Las tres formas de sumar ítems a una comida, en la pantalla donde se arma.
//
// Dos bugs reportados sobre lo mismo: el estado vacío traía sus propias
// acciones y quedaban repetidas con los botones de abajo ("Escanear un código"
// dos veces en la misma pantalla), y faltaba la que sí se pedía —sacar una foto
// y que la IA la estime—.

import 'package:ceres/core/theme/app_theme.dart';
import 'package:ceres/core/utils/dates.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/domain/enums/enums.dart';
import 'package:ceres/domain/models/meal.dart';
import 'package:ceres/presentation/components/food/food_widgets.dart';
import 'package:ceres/presentation/providers/app_providers.dart';
import 'package:ceres/presentation/screens/meal/meal_draft.dart';
import 'package:ceres/presentation/screens/meal/meal_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

Widget _wrap(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: NmAppTheme.dark(),
    locale: const Locale('es', 'AR'),
    home: const MealFormScreen(slot: MealSlot.lunch),
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

  // La fila "Hoy · 21:18 / Cambiar hora" tenía el texto sin flexibilizar y se
  // desbordaba: con la fecha larga —un día que no es hoy ni ayer— o con el
  // texto agrandado, que la app promete soportar hasta 200 %.
  // ×2.0 todavía no pasa, y no es de este cambio: a ese tamaño el que no entra
  // es el propio botón "Cambiar hora", y `MealTotalsBar` desborda 175 px. La
  // app dice soportar 200 % y ninguna batería lo verificaba nunca —la de
  // `profile_screens_test.dart` llega a 1,3—. Queda anotado, no tapado.
  for (final scale in <double>[1.0, 1.3]) {
    testWidgets('se dibuja sin desbordes (texto ×$scale)', (tester) async {
      late ProviderContainer container;
      await tester.runAsync(() async {
        container = await _boot();
      });
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: NmAppTheme.dark(),
            locale: const Locale('es', 'AR'),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              // Una fecha que no es hoy ni ayer: `friendlyDay` devuelve la
              // forma larga, que es la que apretaba la fila.
              child: MealFormScreen(
                slot: MealSlot.lunch,
                date: today().subtract(const Duration(days: 5)),
              ),
            ),
          ),
        ),
      );
      await _settle(tester);

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('las formas de sumar ítems, cada una una sola vez', (
    tester,
  ) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _boot();
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await _settle(tester);

    expect(find.text('Agregar alimento'), findsOneWidget);
    expect(find.text('Sacar foto y analizarla'), findsOneWidget);
    expect(find.text('Describir lo que comiste'), findsOneWidget);

    // El escáner vive adentro del buscador, y "Agregar alimento" lo abre.
    // Tenerlo también acá era el mismo camino ofrecido dos veces.
    expect(find.text('Escanear un código'), findsNothing);

    // Adjuntar una foto a mano es cosa de una comida que ya existe: dando de
    // alta no está, y competía con el botón que sí analiza.
    expect(find.text('Agregar una foto'), findsNothing);

    // El vacío cuenta qué se puede hacer; los botones lo hacen. Sin acciones
    // propias, no hay dos botones para lo mismo.
    expect(find.text('Buscar alimento'), findsNothing);
    expect(find.text('Agregá el primer alimento'), findsOneWidget);
  });

  testWidgets('con ítems cargados siguen estando, sin repetirse', (
    tester,
  ) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _boot();
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await _settle(tester);

    container.read(mealDraftProvider.notifier).addItem(
      const MealItem(
        id: 'i-1',
        name: 'Milanesa',
        quantity: 1,
        unit: 'unidad',
        kcal: 289,
        proteinG: 23,
        carbsG: 14,
        fatG: 15,
        position: 0,
      ),
    );
    await _settle(tester);

    // Una sola fila de ítem. Se busca adentro de `MealItemRow` y no en toda la
    // pantalla porque el campo del título muestra de placeholder el resumen
    // que se guardaría —con un solo ítem, su nombre—, y eso es otra cosa: no
    // es el ítem repetido, es cómo se va a llamar la comida.
    expect(
      find.descendant(
        of: find.byType(MealItemRow),
        matching: find.text('Milanesa'),
      ),
      findsOneWidget,
    );
    expect(find.text('Agregar alimento'), findsOneWidget);
    expect(find.text('Sacar foto y analizarla'), findsOneWidget);
    expect(find.text('Describir lo que comiste'), findsOneWidget);
    expect(find.text('Agregá el primer alimento'), findsNothing);
  });

  test('el análisis se suma a la comida abierta, no la reemplaza', () async {
    final container = await _boot();
    addTearDown(container.dispose);
    final controller = container.read(mealDraftProvider.notifier);

    controller.start(slot: MealSlot.lunch, date: today());
    controller.addItem(
      const MealItem(
        id: 'manual-1',
        name: 'Pan',
        quantity: 60,
        unit: 'g',
        kcal: 160,
        proteinG: 5,
        carbsG: 30,
        fatG: 2,
        position: 0,
      ),
    );
    final antes = container.read(mealDraftProvider)!;

    controller.appendAnalysis(
      source: MealSource.aiPhoto,
      photoPath: '/tmp/foto.jpg',
      aiAnalysisId: 'a-1',
      items: <MealItem>[
        const MealItem(
          id: 'ia-1',
          name: 'Milanesa',
          quantity: 1,
          unit: 'unidad',
          kcal: 289,
          proteinG: 23,
          carbsG: 14,
          fatG: 15,
          aiConfidence: 0.82,
          position: 1,
        ),
      ],
    );

    final draft = container.read(mealDraftProvider)!;
    // Lo que ya estaba sigue estando, y en su lugar.
    expect(draft.items.map((i) => i.name), <String>['Pan', 'Milanesa']);
    expect(draft.id, antes.id);
    expect(draft.slot, MealSlot.lunch);
    expect(draft.photoPath, '/tmp/foto.jpg');
    expect(draft.aiAnalysisId, 'a-1');
    // Ante la duda se marca como estimada: decir "manual" afirmaría que ninguno
    // de sus números es una estimación, y hay uno que sí.
    expect(draft.source, MealSource.aiPhoto);
    // La procedencia fina queda por ítem.
    expect(draft.items.first.aiConfidence, isNull);
    expect(draft.items.last.aiConfidence, 0.82);
  });

  test('descartar el análisis deja la comida como estaba', () async {
    final container = await _boot();
    addTearDown(container.dispose);
    final controller = container.read(mealDraftProvider.notifier);

    controller.start(slot: MealSlot.dinner, date: today());
    controller.addItem(
      const MealItem(
        id: 'manual-1',
        name: 'Pan',
        quantity: 60,
        unit: 'g',
        kcal: 160,
        proteinG: 5,
        carbsG: 30,
        fatG: 2,
        position: 0,
      ),
    );
    final previo = container.read(mealDraftProvider);

    controller.appendAnalysis(
      source: MealSource.aiPhoto,
      items: <MealItem>[
        const MealItem(
          id: 'ia-1',
          name: 'Milanesa',
          quantity: 1,
          unit: 'unidad',
          kcal: 289,
          proteinG: 23,
          carbsG: 14,
          fatG: 15,
          aiConfidence: 0.82,
          position: 1,
        ),
      ],
    );
    controller.restore(previo);

    final draft = container.read(mealDraftProvider)!;
    expect(draft.items.map((i) => i.name), <String>['Pan']);
    expect(draft.source, MealSource.manual);
    expect(draft.photoPath, isNull);
  });
}
