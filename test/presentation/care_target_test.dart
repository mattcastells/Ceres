// El objetivo recomendado de la nutricionista, en la app.
//
// "Aplicar" tiene que dejar el objetivo puesto por el mismo camino que
// cambiarlo a mano (`saveGoal`, que sincroniza) y recién después avisarle al
// servidor.

import 'package:ceres/core/theme/app_theme.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/remote/care_feedback_client.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/domain/enums/enums.dart';
import 'package:ceres/domain/models/care_feedback.dart';
import 'package:ceres/presentation/components/system/overlays.dart';
import 'package:ceres/presentation/providers/app_providers.dart';
import 'package:ceres/presentation/providers/auth_providers.dart';
import 'package:ceres/presentation/providers/plan_providers.dart';
import 'package:ceres/presentation/screens/home/home_screen.dart';
import 'package:ceres/presentation/screens/profile/care_feedback_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeFeedbackClient implements CareFeedbackClient {
  _FakeFeedbackClient(this.items);

  List<CareFeedback> items;
  final List<String> applied = <String>[];

  /// Lo que pasaba con la base al momento de avisar, para probar el orden.
  final List<int?> kcalWhenApplied = <int?>[];
  LocalRepository? repo;

  @override
  Future<List<CareFeedback>> list() async => items;

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<void> markTargetApplied(String id) async {
    applied.add(id);
    kcalWhenApplied.add(repo?.currentGoalOrNull?.baseCalorieTarget);
    items = <CareFeedback>[
      for (final f in items) f.id == id ? f.markedApplied(DateTime.now()) : f,
    ];
  }
}

CareFeedback _target({
  String id = 't',
  CareTarget target = const CareTarget(
    kcal: 1800,
    proteinG: 120,
    carbsG: 180,
    fatG: 60,
  ),
  DateTime? appliedAt,
}) => CareFeedback(
  id: id,
  authorId: 'pro-1',
  authorName: 'Valentina',
  kind: CareFeedbackKind.indication,
  body:
      'Objetivo recomendado: 1.800 kcal por día.\n\n'
      'Subimos la proteína en el desayuno.',
  publishedAt: DateTime.now().subtract(const Duration(days: 1)),
  readAt: DateTime.now(),
  target: target,
  appliedAt: appliedAt,
);

class _Boot {
  _Boot(this.container, this.repository);
  final ProviderContainer container;
  final LocalRepository repository;
}

Future<_Boot> _boot(
  WidgetTester tester, {
  CareFeedbackClient? feedback,
  Map<String, Object> prefs = const <String, Object>{},
}) async {
  late ProviderContainer container;
  late LocalRepository repository;
  await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues(prefs);
    final store = await LocalStore.open();
    store.seed();
    void Function() notify = () {};
    repository = LocalRepository(store, onChanged: () => notify());
    container = ProviderContainer(
      overrides: <Override>[
        repositoryProvider.overrideWithValue(repository),
        isCloudEnabledProvider.overrideWithValue(true),
        careFeedbackClientProvider.overrideWithValue(
          feedback ?? _FakeFeedbackClient(const <CareFeedback>[]),
        ),
      ],
    );
    notify = () => container.read(appRevisionProvider.notifier).bump();
  });
  addTearDown(container.dispose);
  return _Boot(container, repository);
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

/// Deja vencer el snackbar, que si no queda con un timer pendiente.
Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('es_AR'));

  group('objetivo recomendado', () {
    testWidgets('Inicio muestra los números y "Aplicar"; aplicar cambia el '
        'objetivo y después avisa', (tester) async {
      final client = _FakeFeedbackClient(<CareFeedback>[_target()]);
      final boot = await _boot(tester, feedback: client);
      client.repo = boot.repository;
      final before = boot.repository.currentGoalOrNull!;
      expect(before.baseCalorieTarget, isNot(1800));

      await tester.pumpWidget(_wrap(boot.container, const HomeScreen()));
      await _settle(tester);

      expect(find.text('DE TU NUTRICIONISTA'), findsOneWidget);
      expect(find.text('Objetivo recomendado'), findsOneWidget);
      expect(
        find.text('1.800 kcal · P 120 g · C 180 g · G 60 g'),
        findsOneWidget,
      );
      expect(find.text('Subimos la proteína en el desayuno.'), findsOneWidget);
      // No es una indicación de texto más.
      expect(find.text('Indicación vigente'), findsNothing);

      final apply = find.text('Aplicar');
      await tester.ensureVisible(apply);
      await tester.tap(apply);
      await _settle(tester);

      // La confirmación: lo nuevo, con lo de ahora al lado.
      expect(find.byType(NmDialog), findsOneWidget);
      expect(find.text('Aplicar el objetivo recomendado'), findsOneWidget);
      expect(
        find.text('ahora ${_kcal(before.baseCalorieTarget)}'),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(NmDialog),
          matching: find.text('Aplicar'),
        ),
      );
      await _settle(tester);

      final after = boot.repository.currentGoalOrNull!;
      expect(after.baseCalorieTarget, 1800);
      expect(
        <int>[after.proteinG, after.carbsG, after.fatG],
        <int>[120, 180, 60],
      );
      expect(after.macroMethod, 'custom');
      expect(after.targetMethod, TargetMethod.manual);
      expect(after.goalType, before.goalType);
      // El de antes quedó cerrado, no reescrito.
      expect(
        boot.repository.store.goals.where((g) => g.isCurrent),
        hasLength(1),
      );

      // Primero el objetivo, después el aviso.
      expect(client.applied, <String>['t']);
      expect(client.kcalWhenApplied, <int?>[1800]);

      expect(find.textContaining('Aplicado el'), findsOneWidget);
      expect(find.text('Aplicar'), findsNothing);
      await _drain(tester);
    });

    testWidgets('cancelar no cambia nada', (tester) async {
      final client = _FakeFeedbackClient(<CareFeedback>[_target()]);
      final boot = await _boot(tester, feedback: client);
      final before = boot.repository.currentGoalOrNull!.baseCalorieTarget;

      await tester.pumpWidget(_wrap(boot.container, const HomeScreen()));
      await _settle(tester);
      await tester.ensureVisible(find.text('Aplicar'));
      await tester.tap(find.text('Aplicar'));
      await _settle(tester);
      await tester.tap(find.text('Cancelar'));
      await _settle(tester);

      expect(boot.repository.currentGoalOrNull!.baseCalorieTarget, before);
      expect(client.applied, isEmpty);
      expect(find.text('Aplicar'), findsOneWidget);
    });

    testWidgets('si ya es el objetivo vigente, no ofrece aplicarlo', (
      tester,
    ) async {
      late _Boot boot;
      final client = _FakeFeedbackClient(const <CareFeedback>[]);
      boot = await _boot(tester, feedback: client);
      final g = boot.repository.currentGoalOrNull!;
      client.items = <CareFeedback>[
        _target(
          target: CareTarget(kcal: g.baseCalorieTarget, proteinG: g.proteinG),
        ),
      ];

      await tester.pumpWidget(_wrap(boot.container, const HomeScreen()));
      await _settle(tester);

      expect(find.text('Objetivo recomendado'), findsOneWidget);
      expect(find.text('Es tu objetivo actual'), findsOneWidget);
      expect(find.text('Aplicar'), findsNothing);
    });

    testWidgets('ya aplicado dice cuándo, también en la lista', (tester) async {
      final client = _FakeFeedbackClient(<CareFeedback>[
        _target(appliedAt: DateTime(2026, 11, 9, 12)),
      ]);
      final boot = await _boot(tester, feedback: client);

      await tester.pumpWidget(_wrap(boot.container, const HomeScreen()));
      await _settle(tester);
      expect(find.text('Aplicado el 9 nov'), findsOneWidget);
      expect(find.text('Aplicar'), findsNothing);

      await tester.pumpWidget(
        _wrap(boot.container, const CareFeedbackScreen()),
      );
      await _settle(tester);
      expect(find.text('OBJETIVO RECOMENDADO'), findsOneWidget);
      expect(find.text('Aplicado el 9 nov'), findsOneWidget);
      expect(find.text('INDICACIONES VIGENTES'), findsNothing);
    });
  });
}

String _kcal(int v) {
  final s = v.toString();
  return s.length > 3
      ? '${s.substring(0, s.length - 3)}.${s.substring(s.length - 3)} kcal'
      : '$s kcal';
}
