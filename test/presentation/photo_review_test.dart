// El bug: "Agregar un ítem que falta" en la revisión de la IA no hacía nada.
//
// Los ítems vivían en una lista de la pantalla y el borrador de la comida se
// armaba recién al guardar. El buscador de alimentos agrega al borrador, así
// que agregaba a `null`: `addItem` sobre un borrador inexistente no hace nada y
// no avisa. El alimento elegido se perdía en silencio.
//
// Ahora el borrador es la única lista y se abre al entrar. Estos tests fijan
// las tres cosas que eso tiene que garantizar: que lo que se agrega aparece,
// que un alimento del catálogo **no** se muestra con badge de confianza (no es
// una estimación), y que salir sin guardar no deja el borrador dando vueltas.

import 'package:ceres/core/theme/app_theme.dart';
import 'package:ceres/core/utils/dates.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/domain/enums/enums.dart';
import 'package:ceres/domain/models/ai_analysis.dart';
import 'package:ceres/domain/models/meal.dart';
import 'package:ceres/presentation/components/activity/badges.dart';
import 'package:ceres/presentation/providers/app_providers.dart';
import 'package:ceres/presentation/screens/meal/meal_draft.dart';
import 'package:ceres/presentation/screens/photo/photo_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _analysis = AiAnalysis(
  id: 'a-1',
  photoPath: null,
  status: AiAnalysisStatus.completed,
  model: 'gemini',
  promptVersion: 'text_v1',
  latencyMs: 1200,
  items: <AiAnalysisItem>[
    const AiAnalysisItem(
      name: 'Empanada de carne',
      quantity: 2,
      unit: 'unidad',
      kcal: 460,
      proteinG: 18,
      carbsG: 44,
      fatG: 22,
      confidence: 0.82,
    ),
  ],
  createdAt: DateTime(2026, 7, 30, 19, 26),
);

Future<ProviderContainer> _boot() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final store = await LocalStore.open();
  void Function() notify = () {};
  final repository = LocalRepository(store, onChanged: () => notify());
  final container = ProviderContainer(
    overrides: <Override>[repositoryProvider.overrideWithValue(repository)],
  );
  notify = () => container.read(appRevisionProvider.notifier).bump();
  container.read(analysisProvider.notifier).state = _analysis;
  return container;
}

Widget _wrap(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: NmAppTheme.dark(),
    locale: const Locale('es', 'AR'),
    home: const PhotoReviewScreen(),
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

  testWidgets('al entrar hay borrador, así que el buscador tiene dónde agregar', (
    tester,
  ) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _boot();
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await _settle(tester);

    // Esto era `null` antes del arreglo: de ahí que agregar un ítem no hiciera
    // nada.
    final draft = container.read(mealDraftProvider);
    expect(draft, isNotNull);
    expect(draft!.items.length, 1);
    expect(draft.source, MealSource.aiText);

    // Lo que hace el detalle de alimento al tocar "Agregar a la comida".
    container.read(mealDraftProvider.notifier).addItem(
      const MealItem(
        id: 'manual-1',
        foodId: 'f-1',
        name: 'Coca-Cola',
        quantity: 350,
        unit: 'ml',
        kcal: 149,
        proteinG: 0,
        carbsG: 37,
        fatG: 0,
        position: 1,
      ),
    );
    await _settle(tester);

    expect(find.text('Coca-Cola'), findsOneWidget);
    // 460 + 149: el total de la barra inferior lo toma del borrador.
    expect(find.textContaining('609'), findsWidgets);
  });

  testWidgets('un alimento del catálogo no se muestra como estimación', (
    tester,
  ) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _boot();
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await _settle(tester);

    // El ítem de la IA sí lleva badge de confianza.
    expect(find.byType(ConfidenceBadge), findsOneWidget);

    container.read(mealDraftProvider.notifier).addItem(
      const MealItem(
        id: 'manual-1',
        foodId: 'f-1',
        name: 'Coca-Cola',
        quantity: 350,
        unit: 'ml',
        kcal: 149,
        proteinG: 0,
        carbsG: 37,
        fatG: 0,
        position: 1,
      ),
    );
    await _settle(tester);

    // Sigue habiendo uno solo: el del catálogo lleva su propia etiqueta.
    expect(find.byType(ConfidenceBadge), findsOneWidget);
    expect(find.text('Del catálogo'), findsOneWidget);
  });

  testWidgets('salir sin guardar no deja el borrador abierto', (tester) async {
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
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const PhotoReviewScreen(),
                    ),
                  ),
                  child: const Text('revisar'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('revisar'));
    await _settle(tester);
    expect(container.read(mealDraftProvider), isNotNull);

    // La X del encabezado.
    await tester.tap(find.byTooltip('Cerrar'));
    await _settle(tester);

    // Si quedara abierto, "Nueva comida" lo retomaría y aparecería con los
    // ítems de un análisis que se descartó.
    expect(container.read(mealDraftProvider), isNull);
    expect(container.read(analysisProvider), isNull);
  });
}
