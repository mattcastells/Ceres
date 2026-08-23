// Inicio de sesión contra un gateway falso: verifica que la app solo se dé por
// autenticada cuando el servidor aceptó las credenciales.
//
// Nota de mecánica, igual que en home_screen_test: no se usa `pumpAndSettle`
// porque el spinner del botón es una animación en bucle a propósito y nunca
// llegaría a estabilizarse. Y la pantalla navega con `context.go` al entrar,
// así que necesita un GoRouter de verdad alrededor.

import 'dart:async';

import 'package:ceres/core/error/app_error.dart';
import 'package:ceres/core/router/routes.dart';
import 'package:ceres/core/theme/app_theme.dart';
import 'package:ceres/core/utils/dates.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/domain/repositories/auth_gateway.dart';
import 'package:ceres/presentation/providers/app_providers.dart';
import 'package:ceres/presentation/providers/auth_providers.dart';
import 'package:ceres/presentation/screens/auth/auth_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Acepta un único par de credenciales y rechaza el resto, como haría Supabase.
class _FakeGateway implements AuthGateway {
  _FakeGateway();

  static const String validEmail = 'yo@ceres.test';
  static const String validPassword = 'clave1234';

  AuthAccount? _account;
  int signInCalls = 0;
  String? lastEmail;
  final StreamController<AuthAccount?> _changes =
      StreamController<AuthAccount?>.broadcast();

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
  }) async {
    signInCalls++;
    lastEmail = email;
    if (email != validEmail || password != validPassword) {
      throw const AppError(
        code: ApiErrorCode.invalidCredentials,
        message: 'El correo o la contraseña no coinciden.',
      );
    }
    final account = AuthAccount(id: 'uuid-1', email: email);
    _account = account;
    _changes.add(account);
    return account;
  }

  @override
  Future<AuthAccount?> signUp({
    required String email,
    required String password,
    String? displayName,
  }) => signIn(email: email, password: password);

  @override
  Future<void> signOut() async {
    _account = null;
    _changes.add(null);
  }

  @override
  Future<void> sendPasswordReset(String email) async {}

  /// Cuántas veces se pidió borrar la cuenta del servidor, y si toca fallar.
  int deleteCalls = 0;
  AppError? deleteError;

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
  final gateway = _FakeGateway();
  final container = ProviderContainer(
    overrides: <Override>[
      repositoryProvider.overrideWithValue(repository),
      authGatewayProvider.overrideWithValue(gateway),
    ],
  );
  return (container, repository, gateway);
}

/// Router mínimo: la pantalla real y destinos de utilería, para que
/// `context.go` tenga a dónde ir sin montar la app entera.
Widget _wrap(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp.router(
    theme: NmAppTheme.dark(),
    locale: const Locale('es', 'AR'),
    routerConfig: GoRouter(
      initialLocation: Routes.signIn,
      routes: <RouteBase>[
        GoRoute(
          path: Routes.signIn,
          builder: (context, state) => const SignInScreen(),
        ),
        GoRoute(
          path: Routes.home,
          builder: (context, state) => const Scaffold(body: Text('INICIO')),
        ),
        GoRoute(
          path: Routes.forgotPassword,
          builder: (context, state) => const Scaffold(body: Text('OLVIDE')),
        ),
        GoRoute(
          path: Routes.signUp,
          builder: (context, state) => const Scaffold(body: Text('ALTA')),
        ),
      ],
    ),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump(const Duration(milliseconds: 700));
}

Future<void> _signInWith(
  WidgetTester tester, {
  required String email,
  required String password,
}) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), email);
  await tester.enterText(fields.at(1), password);
  await _settle(tester);

  await tester.tap(find.widgetWithText(InkWell, 'Entrar').first);
  await tester.pump();

  // Un inicio de sesión válido escribe el perfil en la base local, y esa
  // escritura necesita tiempo real: bajo el reloj falso de `testWidgets` el
  // `await` no resuelve nunca. El `runAsync` va solo con el delay — pumpear
  // adentro se traba, porque el pump espera trabajo que el reloj real todavía
  // no terminó.
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
    final view = TestWidgetsFlutterBinding
        .instance
        .platformDispatcher
        .implicitView!;
    view.physicalSize = const Size(1179, 2556);
    view.devicePixelRatio = 3;
  });

  testWidgets('una contraseña incorrecta no abre sesión', (tester) async {
    late ProviderContainer container;
    late LocalRepository repository;
    late _FakeGateway gateway;
    // El `_boot` va dentro de `runAsync` por lo mismo que en home_screen_test:
    // `SharedPreferences` cachea su instancia entre tests del mismo archivo, y
    // bajo el reloj falso la segunda apertura no resuelve nunca.
    await tester.runAsync(() async {
      (container, repository, gateway) = await _boot();
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await _settle(tester);
    await _signInWith(
      tester,
      email: _FakeGateway.validEmail,
      password: 'equivocada9',
    );

    expect(gateway.signInCalls, 1);
    expect(gateway.hasSession, isFalse);
    // Lo que de verdad importa: el perfil local no quedó marcado como sesión
    // iniciada, así que el splash no va a dejar entrar en el próximo arranque.
    expect(repository.hasSession, isFalse);
    expect(find.textContaining('no coinciden'), findsOneWidget);
    expect(find.text('INICIO'), findsNothing);
  });

  testWidgets('con las credenciales correctas sí abre sesión', (tester) async {
    late ProviderContainer container;
    late LocalRepository repository;
    late _FakeGateway gateway;
    // El `_boot` va dentro de `runAsync` por lo mismo que en home_screen_test:
    // `SharedPreferences` cachea su instancia entre tests del mismo archivo, y
    // bajo el reloj falso la segunda apertura no resuelve nunca.
    await tester.runAsync(() async {
      (container, repository, gateway) = await _boot();
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await _settle(tester);
    await _signInWith(
      tester,
      email: _FakeGateway.validEmail,
      password: _FakeGateway.validPassword,
    );

    expect(gateway.hasSession, isTrue);
    expect(repository.hasSession, isTrue);
    expect(repository.profile.email, _FakeGateway.validEmail);
    // Sin asistente de por medio, entrar lleva directo a Inicio.
    expect(find.text('INICIO'), findsOneWidget);
  });

  testWidgets('el correo se normaliza antes de mandarlo', (tester) async {
    late ProviderContainer container;
    late LocalRepository repository;
    late _FakeGateway gateway;
    // El `_boot` va dentro de `runAsync` por lo mismo que en home_screen_test:
    // `SharedPreferences` cachea su instancia entre tests del mismo archivo, y
    // bajo el reloj falso la segunda apertura no resuelve nunca.
    await tester.runAsync(() async {
      (container, repository, gateway) = await _boot();
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await _settle(tester);
    await _signInWith(
      tester,
      email: '  YO@Ceres.TEST ',
      password: _FakeGateway.validPassword,
    );

    expect(gateway.lastEmail, _FakeGateway.validEmail);
    expect(repository.profile.email, _FakeGateway.validEmail);
  });
}
