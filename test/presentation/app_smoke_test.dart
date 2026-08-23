// Smoke test de la app completa: monta `CeresApp` con su router real y
// recorre las decisiones de arranque de S-01 y S-02.

import 'package:ceres/app.dart';
import 'package:ceres/core/config/feature_flags.dart';
import 'package:ceres/core/utils/dates.dart';
import 'package:ceres/data/local/local_auth_gateway.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/presentation/components/charts/calorie_ring.dart';
import 'package:ceres/presentation/providers/app_providers.dart';
import 'package:ceres/presentation/providers/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _boot({required bool seeded}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final store = await LocalStore.open();
  if (seeded) store.seed();

  void Function() notify = () {};
  final repository = LocalRepository(store, onChanged: () => notify());
  final container = ProviderContainer(
    overrides: <Override>[
      repositoryProvider.overrideWithValue(repository),
      // Sin este override cualquier pantalla que toque la sesión revienta con
      // `authGatewayProvider sin inicializar`, que es exactamente lo que se
      // quiere: el arranque tiene que elegir explícitamente una implementación.
      authGatewayProvider.overrideWithValue(LocalAuthGateway()),
    ],
  );
  notify = () => container.read(appRevisionProvider.notifier).bump();
  return container;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 900));
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting(appLocale);
  });

  setUp(() {
    // Un teléfono real, no los 800×600 por defecto: con el viewport chico la
    // bienvenida queda cortada y no se puede tocar el último botón.
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher
        .implicitView!;
    view.physicalSize = const Size(1179, 2556);
    view.devicePixelRatio = 3;
  });

  tearDown(() {
    FeatureFlags.seededDemoDataOverride = null;
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher
        .implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('sin sesión, el splash lleva a la bienvenida', (tester) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _boot(seeded: false);
    });
    addTearDown(() => container.dispose());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CeresApp(),
      ),
    );
    await _settle(tester);

    expect(
      find.text('Comida y movimiento, en un solo número honesto'),
      findsOneWidget,
    );
    expect(find.text('Crear cuenta'), findsOneWidget);
    expect(find.text('Probar sin cuenta'), findsOneWidget);
  });

  testWidgets('con perfil completo, el splash lleva a Inicio', (tester) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _boot(seeded: true);
    });
    addTearDown(() => container.dispose());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CeresApp(),
      ),
    );
    await _settle(tester);

    expect(find.byType(CalorieRing), findsOneWidget);
    expect(find.text('Objetivo base'), findsOneWidget);
    // El shell muestra los cuatro destinos y el FAB.
    expect(find.text('Inicio'), findsOneWidget);
    expect(find.text('Pals'), findsOneWidget);
    expect(find.text('Progreso'), findsOneWidget);
    expect(find.text('Perfil'), findsOneWidget);
  });

  testWidgets('"Probar sin cuenta" entra en modo demo y muestra Inicio', (
    tester,
  ) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _boot(seeded: false);
    });
    addTearDown(() => container.dispose());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CeresApp(),
      ),
    );
    await _settle(tester);

    final demoButton = find.text('Probar sin cuenta');
    await tester.ensureVisible(demoButton);
    await tester.pump();
    await tester.tap(demoButton);
    await tester.pump();
    // La escritura en la base local es asíncrona de verdad: hay que dejar
    // correr el reloj real antes de seguir pumpeando.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await _settle(tester);

    // Modo demo (D-15): usuario local anónimo con la app entera funcionando.
    expect(find.byType(CalorieRing), findsOneWidget);
    expect(container.read(profileProvider).isDemo, isTrue);
  });

  testWidgets('se puede navegar a Progreso (con Historial adentro), Pals y Perfil', (
    tester,
  ) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _boot(seeded: true);
    });
    addTearDown(() => container.dispose());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CeresApp(),
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('Progreso'));
    await _settle(tester);
    expect(find.text('Promedio diario'), findsOneWidget);
    expect(find.text('Adherencia'), findsOneWidget);

    // Historial ya no es una tab: se entra desde acá, más abajo en Progreso.
    final historyRow = find.text('Historial');
    await tester.ensureVisible(historyRow);
    await tester.pump();
    await tester.tap(historyRow);
    await _settle(tester);
    expect(find.textContaining('días coinciden'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await _settle(tester);

    // Sin servidor configurado, Pals lo dice en vez de mostrar la lista.
    await tester.tap(find.text('Pals'));
    await _settle(tester);
    expect(
      find.textContaining('Esta compilación no tiene servidor'),
      findsOneWidget,
    );

    await tester.tap(find.text('Perfil'));
    await _settle(tester);
    expect(find.text('Cerrar sesión'), findsOneWidget);
    // El objetivo se muestra desglosado: qué se busca y con cuántas calorías.
    expect(find.text('Calorías por día'), findsOneWidget);
    expect(find.text('Proteína por día'), findsOneWidget);
  });

  // Una cuenta nueva entraba directo a Inicio, con un objetivo de 2.000 kcal
  // que no salía de ningún cálculo porque no había con qué calcularlo. El
  // guardia está en el `redirect` del router y no en la pantalla de alta, así
  // que también agarra al que cierra la app a mitad de camino y la vuelve a
  // abrir: este test entra por el splash, que es justamente ese caso.
  testWidgets('una cuenta sin datos no llega a Inicio: va al alta guiada', (
    tester,
  ) async {
    FeatureFlags.seededDemoDataOverride = false;
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _boot(seeded: false);
      await container.read(repositoryProvider).signIn('elias@ceres.test');
    });
    addTearDown(() => container.dispose());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CeresApp(),
      ),
    );
    await _settle(tester);

    expect(find.text('Empecemos por vos'), findsOneWidget);
    expect(find.text('Paso 1 de 6'), findsOneWidget);
    expect(find.byType(CalorieRing), findsNothing);
    // Y no hay forma de saltearlo: el único camino que no es completarlo es
    // salir de la cuenta.
    expect(find.text('Ahora no'), findsNothing);
    expect(find.text('Salir'), findsOneWidget);
  });

  testWidgets('con los datos cargados, la misma cuenta entra a Inicio', (
    tester,
  ) async {
    FeatureFlags.seededDemoDataOverride = false;
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _boot(seeded: false);
      final repo = container.read(repositoryProvider);
      await repo.signIn('elias@ceres.test');
      await repo.updateProfile(
        repo.profile.copyWith(birthDate: DateTime(1990, 4, 12), heightCm: 178),
      );
      await repo.logWeight(weightKg: 82, date: today());
    });
    addTearDown(() => container.dispose());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CeresApp(),
      ),
    );
    await _settle(tester);

    expect(find.byType(CalorieRing), findsOneWidget);
    expect(find.text('Empecemos por vos'), findsNothing);
  });
}
