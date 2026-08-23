// Borrar la cuenta, y sobre todo el orden en que se borra.
//
// La pantalla existía con su "escribí ELIMINAR" y su botón rojo, y lo único
// que hacía era `signOut()`: las tablas, las fotos, los respaldos y el usuario
// de Auth quedaban intactos, y volver a entrar restauraba todo. El texto
// prometía lo contrario.
//
// Lo que se fija acá es el invariante que se decidió al arreglarlo: **primero
// el servidor, después el teléfono**. Al revés, un borrado que falla deja a la
// persona sin sus datos locales y con la cuenta viva, que es lo peor de los dos
// mundos y además irreversible desde la app.

import 'dart:async';

import 'package:ceres/core/error/app_error.dart';
import 'package:ceres/core/router/routes.dart';
import 'package:ceres/core/theme/app_theme.dart';
import 'package:ceres/core/utils/dates.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/domain/enums/enums.dart';
import 'package:ceres/domain/models/meal.dart';
import 'package:ceres/domain/repositories/auth_gateway.dart';
import 'package:ceres/presentation/providers/app_providers.dart';
import 'package:ceres/presentation/providers/auth_providers.dart';
import 'package:ceres/presentation/screens/settings/settings_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Anota si le pidieron borrar y permite hacer fallar ese pedido.
class _FakeGateway implements AuthGateway {
  AuthAccount? _account = const AuthAccount(
    id: 'uuid-1',
    email: 'yo@ceres.test',
  );
  final StreamController<AuthAccount?> _changes =
      StreamController<AuthAccount?>.broadcast();

  int deleteCalls = 0;
  AppError? deleteError;

  @override
  AuthAccount? get currentAccount => _account;

  @override
  bool get hasSession => _account != null;

  @override
  Stream<AuthAccount?> get changes => _changes.stream;

  @override
  Future<AuthAccount> signIn({
    required String email,
    required String password,
  }) async => _account!;

  @override
  Future<AuthAccount?> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async => _account;

  @override
  Future<void> signOut() async {
    _account = null;
    _changes.add(null);
  }

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> deleteAccount() async {
    deleteCalls++;
    final error = deleteError;
    if (error != null) throw error;
    _account = null;
    _changes.add(null);
  }
}

Future<(ProviderContainer, LocalRepository, _FakeGateway)> _boot() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final store = await LocalStore.open();
  final repository = LocalRepository(store, onChanged: () {});
  await repository.signIn('yo@ceres.test');
  // Una comida cargada: es lo que no se puede perder si el servidor falla.
  final ahora = DateTime.now();
  await repository.saveMeal(
    Meal(
      id: 'comida-1',
      slot: MealSlot.lunch,
      eatenAt: ahora,
      localDate: dateOnly(ahora),
      name: 'Milanesa',
      items: const <MealItem>[
        MealItem(
          id: 'item-1',
          name: 'Milanesa',
          quantity: 1,
          unit: 'porcion',
          kcal: 620,
          proteinG: 30,
          carbsG: 40,
          fatG: 25,
          position: 0,
        ),
      ],
      source: MealSource.manual,
      createdAt: ahora,
      updatedAt: ahora,
    ),
  );
  final gateway = _FakeGateway();
  final container = ProviderContainer(
    overrides: <Override>[
      repositoryProvider.overrideWithValue(repository),
      authGatewayProvider.overrideWithValue(gateway),
    ],
  );
  return (container, repository, gateway);
}

Widget _wrap(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp.router(
    theme: NmAppTheme.dark(),
    locale: const Locale('es', 'AR'),
    routerConfig: GoRouter(
      initialLocation: Routes.deleteAccount,
      routes: <RouteBase>[
        GoRoute(
          path: Routes.deleteAccount,
          builder: (context, state) => const DeleteAccountScreen(),
        ),
        GoRoute(
          path: Routes.welcome,
          builder: (context, state) => const Scaffold(body: Text('BIENVENIDA')),
        ),
      ],
    ),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 700));
}

/// Recorre los dos pasos hasta dejar el botón rojo habilitado, y lo toca.
Future<void> _confirmDelete(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(InkWell, 'Entiendo, continuar'));
  await _settle(tester);

  await tester.enterText(find.byType(TextField).first, 'ELIMINAR');
  await _settle(tester);

  await tester.tap(find.widgetWithText(InkWell, 'Eliminar definitivamente'));
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
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
    view.physicalSize = const Size(1179, 2556);
    view.devicePixelRatio = 3;
  });

  testWidgets('borrar la cuenta se lo pide al servidor, no solo cierra sesión', (
    tester,
  ) async {
    late ProviderContainer container;
    late LocalRepository repository;
    late _FakeGateway gateway;
    await tester.runAsync(() async {
      (container, repository, gateway) = await _boot();
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await _settle(tester);
    await _confirmDelete(tester);

    expect(gateway.deleteCalls, 1, reason: 'tiene que llamar al servidor');
    expect(repository.hasSession, isFalse);
    expect(repository.mealsOn(DateTime.now()), isEmpty);
    expect(find.text('BIENVENIDA'), findsOneWidget);
  });

  testWidgets('si el servidor no pudo borrar, lo local queda intacto', (
    tester,
  ) async {
    late ProviderContainer container;
    late LocalRepository repository;
    late _FakeGateway gateway;
    await tester.runAsync(() async {
      (container, repository, gateway) = await _boot();
    });
    addTearDown(container.dispose);

    gateway.deleteError = const AppError(
      code: ApiErrorCode.server,
      message: 'No pudimos borrar tus fotos, así que no borramos la cuenta.',
    );

    await tester.pumpWidget(_wrap(container));
    await _settle(tester);
    await _confirmDelete(tester);

    expect(gateway.deleteCalls, 1);
    // Lo que importa: la comida sigue estando y la sesión también. Quedarse sin
    // datos **y** con la cuenta viva es el modo de falla que este orden evita.
    expect(repository.hasSession, isTrue);
    expect(repository.mealsOn(DateTime.now()), isNotEmpty);
    expect(find.text('BIENVENIDA'), findsNothing);
    expect(find.textContaining('no borramos la cuenta'), findsOneWidget);
  });
}
