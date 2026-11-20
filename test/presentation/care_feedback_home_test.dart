// "De tu nutricionista" en Inicio, y la pantalla de devoluciones.
//
// Inicio es para el día: la tarjeta aparece solo con algo nuevo o vigente, y
// sin nada no ocupa lugar. Abrir la lista es leer: lo que estaba sin leer se
// marca en el servidor.

import 'package:ceres/core/config/feature_flags.dart';
import 'package:ceres/core/theme/app_theme.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/remote/care_feedback_client.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/domain/models/care_feedback.dart';
import 'package:ceres/presentation/providers/app_providers.dart';
import 'package:ceres/presentation/providers/auth_providers.dart';
import 'package:ceres/presentation/providers/care_providers.dart';
import 'package:ceres/presentation/screens/home/home_screen.dart';
import 'package:ceres/presentation/screens/profile/care_feedback_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Inicio no muestra nada de la nutricionista con `NM_NUTRITIONIST` apagado.
const bool _sinNutricionista = !FeatureFlags.nutritionist;

class _FakeFeedbackClient implements CareFeedbackClient {
  _FakeFeedbackClient(this.items);

  List<CareFeedback> items;
  final List<String> marked = <String>[];

  @override
  Future<List<CareFeedback>> list() async => items;

  @override
  Future<void> markRead(String id) async {
    marked.add(id);
    items = <CareFeedback>[
      for (final f in items) f.id == id ? f.markedRead(DateTime.now()) : f,
    ];
  }

  @override
  Future<void> markTargetApplied(String id) async {}
}

CareFeedback _f(
  String id,
  String body, {
  CareFeedbackKind kind = CareFeedbackKind.feedback,
  bool read = false,
  int daysAgo = 0,
}) {
  final at = DateTime.now().subtract(Duration(days: daysAgo));
  return CareFeedback(
    id: id,
    authorId: 'pro-1',
    authorName: 'Natalia',
    kind: kind,
    body: body,
    publishedAt: at,
    readAt: read ? at : null,
  );
}

Future<ProviderContainer> _boot(
  WidgetTester tester, {
  required CareFeedbackClient client,
}) async {
  late ProviderContainer container;
  await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = await LocalStore.open();
    store.seed();
    void Function() notify = () {};
    final repository = LocalRepository(store, onChanged: () => notify());
    container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repository),
        isCloudEnabledProvider.overrideWithValue(true),
        careFeedbackClientProvider.overrideWithValue(client),
      ],
    );
    notify = () => container.read(appRevisionProvider.notifier).bump();
  });
  addTearDown(container.dispose);
  return container;
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

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('es_AR'));

  group('la tarjeta de Inicio', () {
    testWidgets('muestra la última devolución sin leer y las indicaciones', (
      tester,
    ) async {
      final client = _FakeFeedbackClient(<CareFeedback>[
        _f('vieja', 'Una devolución de antes.', daysAgo: 3),
        _f('nueva', 'Muy bien la semana, seguí con el desayuno.'),
        _f(
          'ind',
          'Sumá proteína en el desayuno.',
          kind: CareFeedbackKind.indication,
          read: true,
          daysAgo: 5,
        ),
      ]);
      final container = await _boot(tester, client: client);
      await tester.pumpWidget(_wrap(container, const HomeScreen()));
      await _settle(tester);

      expect(find.text('DE TU NUTRICIONISTA'), findsOneWidget);
      expect(find.text('Natalia · Hoy'), findsOneWidget);
      expect(
        find.text('Muy bien la semana, seguí con el desayuno.'),
        findsOneWidget,
      );
      // Solo la última sin leer: la vieja queda para la lista.
      expect(find.text('Una devolución de antes.'), findsNothing);
      expect(find.text('Indicación vigente'), findsOneWidget);
      expect(find.text('Sumá proteína en el desayuno.'), findsOneWidget);
      expect(find.text('2 nuevas'), findsOneWidget);
      // Inicio no marca nada como leído: solo la lista lo hace.
      expect(client.marked, isEmpty);
    }, skip: _sinNutricionista);

    testWidgets('sin nada nuevo ni vigente no ocupa lugar', (tester) async {
      final client = _FakeFeedbackClient(<CareFeedback>[
        _f('leida', 'Ya la leíste.', read: true),
      ]);
      final container = await _boot(tester, client: client);
      await tester.pumpWidget(_wrap(container, const HomeScreen()));
      await _settle(tester);

      expect(find.text('DE TU NUTRICIONISTA'), findsNothing);
      expect(find.text('Ya la leíste.'), findsNothing);
    });

    testWidgets('sin servidor tampoco aparece', (tester) async {
      late ProviderContainer container;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final store = await LocalStore.open();
        store.seed();
        container = ProviderContainer(
          overrides: [
            repositoryProvider.overrideWithValue(
              LocalRepository(store, onChanged: () {}),
            ),
          ],
        );
      });
      addTearDown(container.dispose);
      await tester.pumpWidget(_wrap(container, const HomeScreen()));
      await _settle(tester);
      expect(find.text('DE TU NUTRICIONISTA'), findsNothing);
    });
  });

  testWidgets('abrir la lista marca lo no leído y conserva la marca de nueva', (
    tester,
  ) async {
    final client = _FakeFeedbackClient(<CareFeedback>[
      _f('a', 'Primera devolución.'),
      _f('b', 'Ya leída.', read: true, daysAgo: 2),
      _f(
        'c',
        'Tomá dos litros de agua.',
        kind: CareFeedbackKind.indication,
        daysAgo: 1,
      ),
    ]);
    final container = await _boot(tester, client: client);
    await tester.pumpWidget(_wrap(container, const CareFeedbackScreen()));
    await _settle(tester);

    expect(find.text('INDICACIONES VIGENTES'), findsOneWidget);
    expect(find.text('DEVOLUCIONES'), findsOneWidget);
    expect(find.text('Primera devolución.'), findsOneWidget);
    expect(find.text('Ya leída.'), findsOneWidget);
    expect(client.marked.toSet(), <String>{'a', 'c'});
    // Leídas en el servidor, pero durante esta visita siguen marcadas.
    expect(find.text('Nueva'), findsNWidgets(2));
    expect(container.read(careFeedbackProvider).value?.unreadCount, 0);
  });
}
