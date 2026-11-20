// "Sumar un ítem": escribir una cosa más y que se sume al plato.
//
// El pedido: agregarle a una comida —nueva o ya guardada— "una feta de queso"
// o "pan" sin salir de ella, que se estime y que el total del plato cambie a
// la vista. Lo que estos tests fijan:
//
// - lo estimado se **suma** a lo que había, no lo reemplaza, y el total de
//   abajo cambia en el acto;
// - se manda lo que se escribió y nada más;
// - si falla, la comida queda como estaba y el error es una línea;
// - con el plan gratis no se pide nada al servidor: se ofrecen los planes y la
//   carga a mano, con lo escrito ya puesto como nombre;
// - en una comida guardada, sumar y guardar deja los totales persistidos al
//   día, en la misma comida y sin duplicarla.

import 'dart:async';

import 'package:ceres/core/error/app_error.dart';
import 'package:ceres/core/theme/app_theme.dart';
import 'package:ceres/core/utils/dates.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/remote/gemini_analysis_client.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/domain/enums/enums.dart';
import 'package:ceres/domain/models/ai_analysis.dart';
import 'package:ceres/domain/models/meal.dart';
import 'package:ceres/presentation/components/food/food_widgets.dart';
import 'package:ceres/presentation/providers/app_providers.dart';
import 'package:ceres/presentation/screens/meal/meal_draft.dart';
import 'package:ceres/presentation/screens/meal/meal_form_screen.dart';
import 'package:ceres/presentation/screens/meal/quick_add_item.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// El servidor de mentira: anota lo que se le pidió y contesta lo que diga el
/// test.
class _FakeAnalysis extends Fake implements GeminiAnalysisClient {
  final List<String> pedidos = <String>[];
  Future<AiAnalysis> Function(String description) respuesta = (_) async =>
      _analisis(<AiAnalysisItem>[_queso]);

  @override
  Future<AiAnalysis> analyzeText({required String description}) {
    pedidos.add(description);
    return respuesta(description);
  }
}

const _queso = AiAnalysisItem(
  name: 'Queso de máquina',
  quantity: 20,
  unit: 'g',
  kcal: 60,
  proteinG: 4.5,
  carbsG: 0.4,
  fatG: 4.6,
  confidence: 0.8,
);

AiAnalysis _analisis(List<AiAnalysisItem> items) => AiAnalysis(
  id: 'a-queso',
  photoPath: null,
  status: AiAnalysisStatus.completed,
  model: 'gemini',
  promptVersion: 'v5',
  latencyMs: 900,
  createdAt: DateTime(2026, 11, 13),
  items: items,
);

const _milanesa = MealItem(
  id: 'i-1',
  name: 'Milanesa',
  quantity: 1,
  unit: 'unidad',
  kcal: 289,
  proteinG: 23,
  carbsG: 14,
  fatG: 15,
  position: 0,
);

const _pure = MealItem(
  id: 'i-2',
  name: 'Puré de papas',
  quantity: 200,
  unit: 'g',
  kcal: 174,
  proteinG: 3.6,
  carbsG: 29,
  fatG: 5,
  position: 1,
);

Meal _guardada() => Meal(
  id: 'm-1',
  slot: MealSlot.dinner,
  eatenAt: DateTime(2026, 11, 12, 21, 30),
  localDate: DateTime(2026, 11, 12),
  items: const <MealItem>[_milanesa, _pure],
  source: MealSource.manual,
  createdAt: DateTime(2026, 11, 12, 21, 30),
  updatedAt: DateTime(2026, 11, 12, 21, 30),
);

class _Entorno {
  _Entorno(this.container, this.repository, this.ia);

  final ProviderContainer container;
  final LocalRepository repository;
  final _FakeAnalysis ia;
}

Future<_Entorno> _boot(
  WidgetTester tester, {
  bool conComida = false,
  bool iaDisponible = true,
}) async {
  late _Entorno entorno;
  await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = await LocalStore.open();
    void Function() notify = () {};
    final ia = _FakeAnalysis();
    final repository = LocalRepository(
      store,
      onChanged: () => notify(),
      aiAnalysis: ia,
    );
    if (conComida) await repository.saveMeal(_guardada());
    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repository),
        mealAiAvailableProvider.overrideWithValue(iaDisponible),
      ],
    );
    notify = () => container.read(appRevisionProvider.notifier).bump();
    entorno = _Entorno(container, repository, ia);
  });
  addTearDown(entorno.container.dispose);
  return entorno;
}

/// El formulario abierto encima de otra pantalla, con go_router de verdad:
/// guardar cierra con `context.pop()`.
Widget _routed(ProviderContainer container, {String? mealId}) {
  final router = GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => context.push('/meal'),
              child: const Text('abrir'),
            ),
          ),
        ),
        routes: <RouteBase>[
          GoRoute(
            path: 'meal',
            builder: (context, state) => mealId == null
                ? MealFormScreen(slot: MealSlot.lunch, date: today())
                : MealFormScreen(mealId: mealId),
          ),
        ],
      ),
    ],
  );
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: NmAppTheme.dark(),
      locale: const Locale('es', 'AR'),
      routerConfig: router,
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 700));
}

Future<void> _abrir(WidgetTester tester, _Entorno e, {String? mealId}) async {
  await tester.pumpWidget(_routed(e.container, mealId: mealId));
  await tester.tap(find.text('abrir'));
  await _settle(tester);
}

Finder get _campo => find.descendant(
  of: find.byType(QuickAddItemField),
  matching: find.byType(TextField),
);

Future<void> _sumar(WidgetTester tester, String texto) async {
  await tester.ensureVisible(_campo);
  await tester.enterText(_campo, texto);
  await tester.tap(find.byTooltip('Sumar'));
  await _settle(tester);
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

  group('appendEstimatedItems', () {
    MealItem estimado(String id, int kcal) => MealItem(
      id: id,
      name: 'Pan',
      quantity: 30,
      unit: 'g',
      kcal: kcal,
      proteinG: 2.5,
      carbsG: 15,
      fatG: 0.5,
      aiConfidence: 0.7,
      position: 9,
    );

    test('suma al plato y los totales salen de todos los ítems', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(mealDraftProvider.notifier)
        ..edit(_guardada());
      final antes = container.read(mealDraftProvider)!;

      final ok = controller.appendEstimatedItems(
        draftId: antes.id,
        items: <MealItem>[estimado('n-1', 80)],
        aiAnalysisId: 'a-1',
      );

      final draft = container.read(mealDraftProvider)!;
      expect(ok, isTrue);
      expect(draft.items.map((i) => i.name), <String>[
        'Milanesa',
        'Puré de papas',
        'Pan',
      ]);
      expect(draft.totalKcal, 289 + 174 + 80);
      expect(draft.proteinG, closeTo(23 + 3.6 + 2.5, 1e-9));
      expect(draft.carbsG, closeTo(14 + 29 + 15, 1e-9));
      expect(draft.fatG, closeTo(15 + 5 + 0.5, 1e-9));
      // La comida es la misma.
      expect(draft.id, antes.id);
      expect(draft.editingMealId, 'm-1');
      // Tenía todo cargado a mano y ahora tiene un número estimado: decir
      // "manual" sería falso.
      expect(draft.source, MealSource.aiText);
      expect(draft.aiAnalysisId, 'a-1');

      // Y al guardar, las posiciones quedan en orden.
      final meal = draft.toMeal(syncStatus: SyncStatus.synced);
      expect(meal.items.map((i) => i.position), <int>[0, 1, 2]);
      expect(meal.totalKcal, 543);
    });

    test('un plato de foto sigue siendo de foto, con su análisis', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(mealDraftProvider.notifier)
        ..start(
          slot: MealSlot.lunch,
          date: today(),
          source: MealSource.aiPhoto,
          aiAnalysisId: 'a-foto',
          photoPath: 'u/m.jpg',
          name: 'Milanesa con puré',
          items: const <MealItem>[_milanesa],
        );
      final id = container.read(mealDraftProvider)!.id;

      controller.appendEstimatedItems(
        draftId: id,
        items: <MealItem>[estimado('n-1', 80)],
        aiAnalysisId: 'a-pan',
      );

      final draft = container.read(mealDraftProvider)!;
      expect(draft.source, MealSource.aiPhoto);
      expect(draft.aiAnalysisId, 'a-foto');
      expect(draft.photoPath, 'u/m.jpg');
      expect(draft.name, 'Milanesa con puré');
    });

    test('una respuesta que llega para otra comida no se suma', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(mealDraftProvider.notifier)
        ..edit(_guardada());

      final ok = controller.appendEstimatedItems(
        draftId: 'otro-borrador',
        items: <MealItem>[estimado('n-1', 80)],
      );

      expect(ok, isFalse);
      expect(container.read(mealDraftProvider)!.items, hasLength(2));
    });
  });

  testWidgets('lo escrito se estima, se suma y el total cambia', (
    tester,
  ) async {
    final e = await _boot(tester);
    final respuesta = Completer<AiAnalysis>();
    e.ia.respuesta = (_) => respuesta.future;

    await _abrir(tester, e);
    e.container.read(mealDraftProvider.notifier)
      ..addItem(_milanesa)
      ..addItem(_pure);
    await _settle(tester);
    expect(find.text('463 kcal'), findsOneWidget);

    await _sumar(tester, '  una feta de queso  ');

    // Mientras espera: la fila dice qué pasa y no se puede volver a mandar.
    expect(find.text('Calculando…'), findsOneWidget);
    expect(find.byTooltip('Sumar'), findsNothing);
    expect(e.ia.pedidos, <String>['una feta de queso']);

    respuesta.complete(_analisis(<AiAnalysisItem>[_queso]));
    await _settle(tester);

    final draft = e.container.read(mealDraftProvider)!;
    expect(draft.items.map((i) => i.name), <String>[
      'Milanesa',
      'Puré de papas',
      'Queso de máquina',
    ]);
    expect(draft.items.last.aiConfidence, 0.8);
    expect(
      find.descendant(
        of: find.byType(MealItemRow),
        matching: find.text('Queso de máquina'),
      ),
      findsOneWidget,
    );
    // El total del plato, a la vista, ya sumado.
    expect(find.text('523 kcal'), findsOneWidget);
    expect(find.text('P 31 g · C 43 g · G 25 g'), findsOneWidget);
    // El campo queda listo para el siguiente.
    expect(find.text('Calculando…'), findsNothing);
    expect(tester.widget<TextField>(_campo).controller!.text, isEmpty);
  });

  testWidgets('si falla, la comida queda como estaba y el error es una línea', (
    tester,
  ) async {
    final e = await _boot(tester);
    e.ia.respuesta = (_) async => throw const AppError(
      code: ApiErrorCode.aiNoFood,
      message: 'No reconocimos ninguna comida en esa descripción. Probá '
          'nombrando los alimentos y las cantidades.',
    );

    await _abrir(tester, e);
    e.container.read(mealDraftProvider.notifier).addItem(_milanesa);
    await _settle(tester);

    await _sumar(tester, 'asdfgh');

    expect(e.container.read(mealDraftProvider)!.items, hasLength(1));
    expect(
      find.text('No lo reconocimos. Probá con el nombre y la cantidad.'),
      findsOneWidget,
    );
    // Lo escrito sigue ahí para corregirlo, y hay salida a mano.
    expect(tester.widget<TextField>(_campo).controller!.text, 'asdfgh');
    expect(find.text('Cargar a mano'), findsOneWidget);

    // Tocar el campo de nuevo limpia el error.
    await tester.enterText(_campo, 'pan');
    await _settle(tester);
    expect(
      find.text('No lo reconocimos. Probá con el nombre y la cantidad.'),
      findsNothing,
    );
  });

  testWidgets('con menos de tres letras no se pregunta nada', (tester) async {
    final e = await _boot(tester);
    await _abrir(tester, e);

    await _sumar(tester, 'a');

    expect(e.ia.pedidos, isEmpty);
    expect(find.text('Escribí qué querés sumar.'), findsOneWidget);
  });

  testWidgets('sin servidor, lo escrito pasa derecho a la carga a mano', (
    tester,
  ) async {
    final e = await _boot(tester, iaDisponible: false);
    await _abrir(tester, e);

    await _sumar(tester, 'pan');

    expect(e.ia.pedidos, isEmpty);
    expect(find.text('Sumar a la comida'), findsOneWidget);
  });

  testWidgets('en una comida guardada, sumar y guardar persiste los totales', (
    tester,
  ) async {
    final e = await _boot(tester, conComida: true);
    await _abrir(tester, e, mealId: 'm-1');
    expect(find.text('463 kcal'), findsOneWidget);

    await _sumar(tester, 'una feta de queso');
    expect(find.text('523 kcal'), findsOneWidget);

    await tester.tap(find.text('Guardar comida'));
    await _settle(tester);

    final meals = e.repository.store.meals;
    // La misma comida, no una copia.
    expect(meals, hasLength(1));
    final meal = e.repository.mealById('m-1')!;
    expect(meal.items, hasLength(3));
    expect(meal.totalKcal, 523);
    expect(meal.totalProteinG, closeTo(23 + 3.6 + 4.5, 1e-9));
    expect(meal.totalFatG, closeTo(15 + 5 + 4.6, 1e-9));
    expect(meal.items.map((i) => i.position), <int>[0, 1, 2]);
    expect(meal.createdAt, DateTime(2026, 11, 12, 21, 30));
    expect(meal.source, MealSource.aiText);
    expect(meal.aiAnalysisId, 'a-queso');
    // Volvió a la pantalla de antes.
    expect(find.text('abrir'), findsOneWidget);
  });
}
