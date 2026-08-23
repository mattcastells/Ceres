// Recalcular una comida ya cargada, sin empezar de nuevo.
//
// El bug de uso: para corregir un peso que la IA estimó mal había que sacar la
// foto otra vez y rearmar la comida entera. Lo que estos tests fijan es lo que
// hace que corregir no cueste más que cargar:
//
// - el recálculo **reemplaza** los ítems en vez de sumarlos —el modelo devuelve
//   la comida completa ya corregida, así que sumarla la dejaría duplicada—;
// - la comida sigue siendo la misma: mismo id, mismo momento del día, misma
//   fecha. Se corrigen los números, no la comida;
// - está donde se pidió: en la pantalla de editar, no en la de alta;
// - y si el recálculo falla, la comida queda **como estaba**.
//
// El pedido falla en este entorno —no hay servidor, `recalculate` lanza
// `providerUnavailable`— y eso es justo lo que hace comprobable el último
// punto.

import 'package:ceres/core/theme/app_theme.dart';
import 'package:ceres/core/utils/dates.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/domain/enums/enums.dart';
import 'package:ceres/domain/models/meal.dart';
import 'package:ceres/presentation/providers/app_providers.dart';
import 'package:ceres/presentation/screens/meal/meal_draft.dart';
import 'package:ceres/presentation/screens/meal/meal_form_screen.dart';
import 'package:ceres/presentation/screens/meal/recalculate_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _milanesa = MealItem(
  id: 'i-1',
  name: 'Milanesa',
  quantity: 1,
  unit: 'unidad',
  kcal: 289,
  proteinG: 23,
  carbsG: 14,
  fatG: 15,
  aiConfidence: 0.62,
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
  aiConfidence: 0.64,
  position: 1,
);

Meal _meal() => Meal(
  id: 'm-1',
  slot: MealSlot.dinner,
  eatenAt: DateTime(2026, 8, 4, 21, 30),
  localDate: DateTime(2026, 8, 4),
  items: const <MealItem>[_milanesa, _pure],
  source: MealSource.aiPhoto,
  createdAt: DateTime(2026, 8, 4, 21, 30),
  updatedAt: DateTime(2026, 8, 4, 21, 30),
);

Future<ProviderContainer> _boot({bool conComida = false}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final store = await LocalStore.open();
  void Function() notify = () {};
  final repository = LocalRepository(store, onChanged: () => notify());
  if (conComida) await repository.saveMeal(_meal());
  final container = ProviderContainer(
    overrides: <Override>[repositoryProvider.overrideWithValue(repository)],
  );
  notify = () => container.read(appRevisionProvider.notifier).bump();
  return container;
}

Widget _wrap(ProviderContainer container, Widget home) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: NmAppTheme.dark(),
        locale: const Locale('es', 'AR'),
        home: home,
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

  test('el recálculo reemplaza los ítems y no los suma', () async {
    final container = await _boot();
    addTearDown(container.dispose);
    final controller = container.read(mealDraftProvider.notifier);

    controller.edit(_meal());
    final antes = container.read(mealDraftProvider)!;

    controller.replaceAnalysis(
      source: MealSource.aiPhoto,
      aiAnalysisId: 'a-2',
      items: const <MealItem>[
        MealItem(
          id: 'nuevo-1',
          name: 'Milanesa',
          quantity: 200,
          unit: 'g',
          kcal: 460,
          proteinG: 37,
          carbsG: 22,
          fatG: 24,
          aiConfidence: 0.86,
          position: 7,
        ),
        MealItem(
          id: 'nuevo-2',
          name: 'Puré de papas',
          quantity: 200,
          unit: 'g',
          kcal: 174,
          proteinG: 3.6,
          carbsG: 29,
          fatG: 5,
          aiConfidence: 0.64,
          position: 9,
        ),
      ],
    );

    final draft = container.read(mealDraftProvider)!;
    // Dos ítems, no cuatro: la respuesta es la comida entera ya corregida.
    expect(draft.items.length, 2);
    expect(draft.items.first.kcal, 460);
    // Las posiciones se renumeran desde cero, vengan como vengan.
    expect(draft.items.map((i) => i.position), <int>[0, 1]);

    // La comida es la misma: se corrigieron los números.
    expect(draft.editingMealId, antes.editingMealId);
    expect(draft.id, antes.id);
    expect(draft.slot, antes.slot);
    expect(draft.date, antes.date);
    expect(draft.eatenAt, antes.eatenAt);
    expect(draft.aiAnalysisId, 'a-2');
  });

  test('sin foto nueva, la que tenía la comida se conserva', () async {
    final container = await _boot();
    addTearDown(container.dispose);
    final controller = container.read(mealDraftProvider.notifier);

    controller.edit(
      Meal(
        id: 'm-2',
        slot: MealSlot.lunch,
        eatenAt: DateTime(2026, 8, 4, 13),
        localDate: DateTime(2026, 8, 4),
        items: const <MealItem>[_milanesa],
        source: MealSource.aiPhoto,
        photoPath: 'u-1/m-2.jpg',
        createdAt: DateTime(2026, 8, 4, 13),
        updatedAt: DateTime(2026, 8, 4, 13),
      ),
    );

    controller.replaceAnalysis(
      source: MealSource.aiPhoto,
      items: const <MealItem>[_pure],
    );

    expect(container.read(mealDraftProvider)!.photoPath, 'u-1/m-2.jpg');
  });

  testWidgets('está al editar una comida, no al crearla', (tester) async {
    late ProviderContainer editando;
    await tester.runAsync(() async {
      editando = await _boot(conComida: true);
    });
    addTearDown(editando.dispose);

    await tester.pumpWidget(
      _wrap(editando, const MealFormScreen(mealId: 'm-1')),
    );
    await _settle(tester);
    expect(find.text('Recalcular con IA'), findsOneWidget);

    late ProviderContainer nueva;
    await tester.runAsync(() async {
      nueva = await _boot();
    });
    addTearDown(nueva.dispose);

    await tester.pumpWidget(
      _wrap(nueva, const MealFormScreen(slot: MealSlot.lunch)),
    );
    await _settle(tester);
    // Dando de alta no hay comida que recalcular todavía.
    expect(find.text('Recalcular con IA'), findsNothing);
  });

  testWidgets('si el recálculo falla, la comida queda como estaba', (
    tester,
  ) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _boot();
    });
    addTearDown(container.dispose);
    container.read(mealDraftProvider.notifier).edit(_meal());

    await tester.pumpWidget(
      _wrap(container, const Scaffold(body: RecalculateSheet())),
    );
    await _settle(tester);

    await tester.enterText(
      find.byType(TextField).first,
      'la milanesa pesaba 200 g',
    );
    await _settle(tester);

    await tester.tap(find.text('Recalcular'));
    await _settle(tester);

    // Sin servidor no hay a quién preguntarle, y eso se cuenta.
    expect(find.textContaining('servidor'), findsOneWidget);

    // Y lo que había sigue estando, con sus números intactos.
    final draft = container.read(mealDraftProvider)!;
    expect(draft.items.map((i) => i.name), <String>['Milanesa', 'Puré de papas']);
    expect(draft.items.first.kcal, 289);
    expect(draft.editingMealId, 'm-1');
  });
}
