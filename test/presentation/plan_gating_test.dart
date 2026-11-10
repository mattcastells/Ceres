// Lo que ve una cuenta del plan gratis: el sheet de Premium en lugar de la IA,
// los anuncios en las pantallas neutras y la compra simulada.
//
// Mismo reloj falso que el resto de los tests de widget: las operaciones de la
// base local van dentro de `tester.runAsync`, y no se usa `pumpAndSettle`
// porque el skeleton y el spinner son animaciones en bucle a propósito.

import 'package:ceres/core/error/app_error.dart';
import 'package:ceres/core/theme/app_theme.dart';
import 'package:ceres/data/local/local_auth_gateway.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/remote/plan_client.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/domain/models/plan.dart';
import 'package:ceres/domain/repositories/auth_gateway.dart';
import 'package:ceres/presentation/components/plan/ad_banner.dart';
import 'package:ceres/presentation/components/plan/ai_gate.dart';
import 'package:ceres/presentation/providers/app_providers.dart';
import 'package:ceres/presentation/providers/auth_providers.dart';
import 'package:ceres/presentation/providers/plan_providers.dart';
import 'package:ceres/presentation/screens/plans/plans_screen.dart';
import 'package:ceres/presentation/screens/progress/progress_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// El servidor de mentira: contesta el plan que tenga y "compra" como la
/// función de la demo, o se niega como con una cuenta real.
class _FakePlanClient implements PlanClient {
  _FakePlanClient(this.plan, {this.forbid = false});

  AppPlan plan;
  final bool forbid;
  final List<AppPlan> switches = <AppPlan>[];

  @override
  Future<AppPlan> effectivePlan() async => plan;

  @override
  Future<AppPlan> demoSwitch(AppPlan target) async {
    switches.add(target);
    if (forbid) throw PlanClient.translate('ERR_FORBIDDEN');
    plan = target;
    return plan;
  }
}

Future<ProviderContainer> _boot(
  WidgetTester tester, {
  required AppPlan plan,
  bool cloud = true,
  PlanClient? client,
  String? email,
}) async {
  late ProviderContainer container;
  await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = await LocalStore.open();
    store.seed();
    void Function() notify = () {};
    final repository = LocalRepository(store, onChanged: () => notify());
    // El mail va solo en la sesión, como en la app real: el perfil que se
    // trae del servidor no lo tiene.
    container = ProviderContainer(
      overrides: <Override>[
        repositoryProvider.overrideWithValue(repository),
        authGatewayProvider.overrideWithValue(LocalAuthGateway(
          initial: email == null ? null : AuthAccount(id: 'cuenta-de-prueba', email: email),
        )),
        isCloudEnabledProvider.overrideWithValue(cloud),
        if (client != null) planClientProvider.overrideWithValue(client),
      ],
    );
    notify = () => container.read(appRevisionProvider.notifier).bump();
  });
  container.read(planProvider.notifier).debugSet(plan);
  addTearDown(container.dispose);
  return container;
}

Widget _wrap(ProviderContainer container, Widget child) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: NmAppTheme.light(),
        locale: const Locale('es', 'AR'),
        home: child,
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

/// Una puerta de IA cualquiera, para probar el guardia sin depender de que
/// la compilación tenga servidor (sin él, los botones reales están apagados).
class _AiDoor extends ConsumerWidget {
  const _AiDoor({required this.onRun, this.onManual});

  final VoidCallback onRun;
  final VoidCallback? onManual;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () {
          if (!ensureAiAllowed(context, ref, onManual: onManual)) return;
          onRun();
        },
        child: const Text('Analizar con IA'),
      ),
    ),
  );
}

void main() {
  setUpAll(() => initializeDateFormatting('es_AR'));

  group('el guardia de la IA', () {
    testWidgets('en Gratis no corre: ofrece los planes y la salida a mano', (
      tester,
    ) async {
      final container = await _boot(tester, plan: AppPlan.free);
      var ran = 0;
      var manual = 0;
      await tester.pumpWidget(
        _wrap(container, _AiDoor(onRun: () => ran++, onManual: () => manual++)),
      );

      await tester.tap(find.text('Analizar con IA'));
      await _settle(tester);

      expect(ran, 0);
      expect(find.text('Esto usa IA'), findsOneWidget);
      expect(find.textContaining('es parte de Premium'), findsOneWidget);
      expect(find.text('Ver planes'), findsOneWidget);

      await tester.tap(find.text('Cargar a mano'));
      await _settle(tester);
      expect(manual, 1);
      expect(find.text('Esto usa IA'), findsNothing);
    });

    testWidgets('sin salida a mano, el sheet ofrece solo los planes', (
      tester,
    ) async {
      final container = await _boot(tester, plan: AppPlan.free);
      await tester.pumpWidget(_wrap(container, _AiDoor(onRun: () {})));

      await tester.tap(find.text('Analizar con IA'));
      await _settle(tester);
      expect(find.text('Ver planes'), findsOneWidget);
      expect(find.text('Cargar a mano'), findsNothing);
    });

    for (final plan in <AppPlan>[
      AppPlan.premium,
      AppPlan.patient,
      AppPlan.pro,
    ]) {
      testWidgets('con ${plan.wire} corre directo', (tester) async {
        final container = await _boot(tester, plan: plan);
        var ran = 0;
        await tester.pumpWidget(_wrap(container, _AiDoor(onRun: () => ran++)));

        await tester.tap(find.text('Analizar con IA'));
        await _settle(tester);
        expect(ran, 1);
        expect(find.text('Esto usa IA'), findsNothing);
      });
    }

    testWidgets('un 402 del servidor abre el mismo sheet; otro error no', (
      tester,
    ) async {
      final container = await _boot(tester, plan: AppPlan.premium);
      late BuildContext ctx;
      await tester.pumpWidget(
        _wrap(
          container,
          Builder(
            builder: (context) {
              ctx = context;
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      );

      const other = AppError(code: ApiErrorCode.quotaExceeded, message: 'x');
      expect(handlePlanRequired(ctx, other), isFalse);
      await _settle(tester);
      expect(find.text('Esto usa IA'), findsNothing);

      const plan = AppError(code: ApiErrorCode.planRequired, message: 'y');
      expect(handlePlanRequired(ctx, plan), isTrue);
      await _settle(tester);
      expect(find.text('Esto usa IA'), findsOneWidget);
    });
  });

  group('Progreso', () {
    testWidgets('en Gratis: "Tu semana con IA" ofrece Premium y hay anuncio', (
      tester,
    ) async {
      final container = await _boot(tester, plan: AppPlan.free);
      await tester.pumpWidget(_wrap(container, const ProgressScreen()));
      await _settle(tester);

      expect(find.text('Tu semana con IA'), findsOneWidget);
      expect(find.text('Premium'), findsOneWidget);

      await tester.scrollUntilVisible(find.byType(AdBanner), 300);
      expect(find.text('Quitar anuncios'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Tu semana con IA'), -300);
      await tester.tap(find.text('Tu semana con IA'));
      await _settle(tester);
      expect(find.text('Esto usa IA'), findsOneWidget);
    });

    testWidgets('en Premium no hay anuncio ni etiqueta', (tester) async {
      final container = await _boot(tester, plan: AppPlan.premium);
      await tester.pumpWidget(_wrap(container, const ProgressScreen()));
      await _settle(tester);

      expect(find.text('Tu semana con IA'), findsOneWidget);
      expect(find.text('Premium'), findsNothing);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -4000));
      await _settle(tester);
      expect(find.text('Quitar anuncios'), findsNothing);
    });

    testWidgets('sin servidor no hay resumen con IA ni anuncio', (
      tester,
    ) async {
      // El modo local es la app de siempre: plan por defecto (Premium) y
      // nada que dependa del servidor.
      final container = await _boot(
        tester,
        plan: AppPlan.premium,
        cloud: false,
      );
      await tester.pumpWidget(_wrap(container, const ProgressScreen()));
      await _settle(tester);
      expect(find.text('Tu semana con IA'), findsNothing);
      expect(container.read(planProvider), AppPlan.premium);
    });
  });

  group('Planes', () {
    testWidgets('la compra simulada cambia el plan en el acto', (tester) async {
      final client = _FakePlanClient(AppPlan.free);
      final container = await _boot(
        tester,
        plan: AppPlan.free,
        client: client,
        email: 'ana@demo.ceres.app',
      );
      await tester.pumpWidget(_wrap(container, const PlansScreen()));
      await _settle(tester);

      expect(
        find.text('Compra simulada · demostración. No se cobra nada.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Pasarme a Premium'));
      await tester.tap(find.text('Pasarme a Premium'));
      await _settle(tester);

      expect(client.switches, <AppPlan>[AppPlan.premium]);
      expect(container.read(planProvider), AppPlan.premium);
      expect(find.text('Pasarme a Premium'), findsNothing);
      // Una cuenta de demo puede volver a Gratis para repetir la demo.
      expect(find.text('Volver al plan Gratis (demo)'), findsOneWidget);
    });

    testWidgets('una cuenta real no puede, y se le explica', (tester) async {
      final client = _FakePlanClient(AppPlan.free, forbid: true);
      final container = await _boot(
        tester,
        plan: AppPlan.free,
        client: client,
        email: 'ana@gmail.com',
      );
      await tester.pumpWidget(_wrap(container, const PlansScreen()));
      await _settle(tester);

      await tester.ensureVisible(find.text('Pasarme a Premium'));
      await tester.tap(find.text('Pasarme a Premium'));
      await _settle(tester);

      expect(container.read(planProvider), AppPlan.free);
      expect(find.textContaining('cuentas reales'), findsOneWidget);
    });

    testWidgets('una cuenta real en Premium no ve el botón de volver', (
      tester,
    ) async {
      final container = await _boot(
        tester,
        plan: AppPlan.premium,
        email: 'ana@gmail.com',
      );
      await tester.pumpWidget(_wrap(container, const PlansScreen()));
      await _settle(tester);
      expect(find.text('Volver al plan Gratis (demo)'), findsNothing);
      expect(find.text('Pasarme a Premium'), findsNothing);
    });
  });
}
