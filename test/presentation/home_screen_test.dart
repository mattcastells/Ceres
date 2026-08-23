// Tests de widget sobre la pantalla principal.
//
// Corren en el entorno `mock`: la app entera contra `data/mock/` con datos
// simulados realistas (19-project-structure.md §5).
//
// Nota de mecánica: `testWidgets` corre en un reloj falso, así que toda
// operación de la base local se hace dentro de `tester.runAsync`. Tampoco se
// usa `pumpAndSettle`: el shimmer del skeleton y el spinner son animaciones en
// bucle a propósito (21-motion §6).

import 'package:ceres/core/theme/app_theme.dart';
import 'package:ceres/core/utils/dates.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/domain/repositories/repositories.dart';
import 'package:ceres/presentation/components/charts/calorie_ring.dart';
import 'package:ceres/presentation/providers/app_providers.dart';
import 'package:ceres/presentation/screens/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<(ProviderContainer, CeresRepositories)> _boot() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final store = await LocalStore.open();
  // En una instalación nueva la base arranca vacía y se siembra desde "Probar
  // sin cuenta"; acá se siembra a mano para tener un día cargado.
  store.seed();

  void Function() notify = () {};
  final repository = LocalRepository(store, onChanged: () => notify());
  final container = ProviderContainer(
    overrides: <Override>[repositoryProvider.overrideWithValue(repository)],
  );
  notify = () => container.read(appRevisionProvider.notifier).bump();
  return (container, repository);
}

Widget _wrap(ProviderContainer container, Widget child) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: NmAppTheme.dark(),
        locale: const Locale('es', 'AR'),
        home: child,
      ),
    );

/// Avanza el reloj lo suficiente para pasar el estado de carga y terminar las
/// animaciones de entrada.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting(appLocale);
  });

  setUp(() {
    // Un teléfono real en lugar de los 800×600 por defecto.
    final view = TestWidgetsFlutterBinding
        .instance
        .platformDispatcher
        .implicitView!;
    view.physicalSize = const Size(1179, 2556);
    view.devicePixelRatio = 3;
  });

  tearDown(() {
    final view = TestWidgetsFlutterBinding
        .instance
        .platformDispatcher
        .implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('Inicio muestra el desglose completo del día', (tester) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      final booted = await _boot();
      container = booted.$1;
    });
    addTearDown(() => container.dispose());

    await tester.pumpWidget(_wrap(container, const HomeScreen()));
    await _settle(tester);

    // Las filas del cálculo se muestran siempre por separado (RN-01).
    expect(find.text('Objetivo base'), findsOneWidget);
    expect(find.text('Consumido'), findsOneWidget);
    expect(find.text('Actividad'), findsWidgets);
    expect(find.text('Te quedan'), findsWidgets);
    expect(find.text('¿Cómo se calcula?'), findsOneWidget);
    expect(find.byType(CalorieRing), findsOneWidget);
  });

  testWidgets('con crédito 0 % no hay fila de ajuste ni texto sobre ella', (
    tester,
  ) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      final booted = await _boot();
      container = booted.$1;
      await booted.$2.setExerciseCredit(percentage: 0, enabled: true);
    });
    addTearDown(() => container.dispose());

    await tester.pumpWidget(_wrap(container, const HomeScreen()));
    await _settle(tester);

    // D-02 / AC-04: sin crédito, la fila de ajuste desaparece. El crédito se
    // maneja desde preferencias, así que la tarjeta tampoco lo explica acá.
    expect(find.text('Ajuste aplicado'), findsNothing);
    expect(find.text('El ejercicio no suma a tu presupuesto'), findsNothing);
    expect(find.text('Objetivo ajustado'), findsNothing);
  });

  testWidgets('con crédito 50 % aparecen el ajuste y el objetivo ajustado', (
    tester,
  ) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      final booted = await _boot();
      container = booted.$1;
      await booted.$2.setExerciseCredit(percentage: 50, enabled: true);
    });
    addTearDown(() => container.dispose());

    await tester.pumpWidget(_wrap(container, const HomeScreen()));
    await _settle(tester);

    expect(find.text('Ajuste aplicado'), findsOneWidget);
    expect(find.text('Objetivo ajustado'), findsOneWidget);
  });

  testWidgets('con movimiento reducido el contenido llega a su estado final', (
    tester,
  ) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      final booted = await _boot();
      container = booted.$1;
    });
    addTearDown(() => container.dispose());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: NmAppTheme.dark(),
          locale: const Locale('es', 'AR'),
          home: const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: HomeScreen(),
          ),
        ),
      ),
    );
    await _settle(tester);

    expect(find.byType(CalorieRing), findsOneWidget);
    expect(find.text('Objetivo base'), findsOneWidget);
  });

  test('el balance del día refleja las comidas y el crédito vigente', () async {
    final (container, repo) = await _boot();
    addTearDown(container.dispose);

    await repo.setExerciseCredit(percentage: 50, enabled: true);
    final summary = repo.daily(today());

    // El ajuste es el 50 % de lo estimado, redondeado (RN-02).
    expect(
      summary.exerciseAppliedKcal,
      (summary.exerciseEstimatedKcal * 0.5).round(),
    );
    expect(
      summary.adjustedTarget,
      summary.baseTarget + summary.exerciseAppliedKcal,
    );
    expect(summary.remainingKcal, summary.adjustedTarget - summary.consumedKcal);

    // El día sembrado trae 3 comidas y 2 actividades (decisions.md §2).
    expect(summary.meals.length, 3);
    expect(summary.activities.length, 2);
    expect(summary.consumedKcal, greaterThan(0));
  });
}
