// El alta guiada, caminada de punta a punta.
//
// Es obligatoria: mientras `needsOnboarding` sea `true` el router no deja entrar
// a Inicio. Eso la vuelve el lugar más caro para tener un bug — si un paso no
// deja avanzar, la persona no queda con una pantalla fea, queda **afuera de la
// app**, sin más salida que cerrar sesión.
//
// `onboarding_test.dart` prueba la regla (quién tiene que completar); esto
// prueba que se pueda.

import 'package:ceres/core/error/app_error.dart';
import 'package:ceres/core/router/routes.dart';
import 'package:ceres/core/theme/app_theme.dart';
import 'package:ceres/core/utils/dates.dart';
import 'package:ceres/core/utils/formats.dart';
import 'package:ceres/data/local/local_auth_gateway.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/remote/calorie_target_client.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/domain/calculations/bmr.dart';
import 'package:ceres/domain/calculations/calorie_target.dart';
import 'package:ceres/domain/calculations/goal_presets.dart';
import 'package:ceres/domain/calculations/tdee.dart';
import 'package:ceres/domain/enums/enums.dart';
import 'package:ceres/domain/models/ai_calorie_target.dart';
import 'package:ceres/presentation/providers/app_providers.dart';
import 'package:ceres/presentation/providers/auth_providers.dart';
import 'package:ceres/presentation/screens/auth/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Un cliente de propuestas que no sale a la red.
///
/// La validación de verdad —que el número caiga dentro de la banda que permite
/// el gasto— vive en la Edge Function, que es donde tiene que estar: si
/// dependiera del teléfono, no estaría validando nada. Acá se prueba lo que le
/// toca a la pantalla: que una propuesta se vea, que aceptarla la deje guardada
/// con su propio método, y que cuando falla se pueda seguir igual.
class _FakeTargetClient implements CalorieTargetClient {
  _FakeTargetClient({this.answer, this.error});

  final AiCalorieTarget? answer;
  final AppError? error;
  int calls = 0;

  @override
  Future<AiCalorieTarget> propose({
    required BiologicalSex sex,
    required int ageYears,
    required double heightCm,
    required double weightKg,
    required ActivityLevel activityLevel,
    required GoalType goalType,
    required int formulaTarget,
  }) async {
    calls++;
    if (error != null) throw error!;
    return answer!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<(ProviderContainer, LocalRepository)> _boot({
  DateTime? birthDate,
  CalorieTargetClient? calorieTargets,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});

  // El repositorio avisa de cada escritura por el contador de revisión, igual
  // que en `bootstrap`. No es detalle de armado: sin ese cable, el peso que se
  // registra en el paso 2 no lo ve `currentWeightProvider` en el paso 4, y el
  // objetivo sale `manual` en vez de calculado — que es exactamente el bug que
  // esta pantalla existe para no tener.
  void Function() notify = () {};
  final repo = LocalRepository(
    await LocalStore.open(),
    calorieTargets: calorieTargets,
    onChanged: () => notify(),
  );
  await repo.signIn('elias@ceres.test');
  if (birthDate != null) {
    await repo.updateProfile(repo.profile.copyWith(birthDate: birthDate));
  }
  final container = ProviderContainer(
    overrides: <Override>[
      repositoryProvider.overrideWithValue(repo),
      authGatewayProvider.overrideWithValue(LocalAuthGateway()),
    ],
  );
  notify = () => container.read(appRevisionProvider.notifier).bump();
  return (container, repo);
}

Widget _wrap(ProviderContainer container, {double textScale = 1.0}) =>
    UncontrolledProviderScope(
  container: container,
  child: MaterialApp.router(
    theme: NmAppTheme.dark(),
    locale: const Locale('es', 'AR'),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
      ),
      child: child!,
    ),
    routerConfig: GoRouter(
      initialLocation: Routes.onboarding,
      routes: <RouteBase>[
        GoRoute(
          path: Routes.onboarding,
          builder: (context, state) => const OnboardingScreen(),
        ),
        GoRoute(
          path: Routes.home,
          builder: (context, state) => const Scaffold(body: Text('INICIO')),
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
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _continuar(WidgetTester tester, String etiqueta) async {
  await tester.ensureVisible(find.text(etiqueta));
  await tester.pump();
  await tester.tap(find.text(etiqueta));
  await tester.pump();
  // Cada paso escribe en la base local antes de avanzar, y esa escritura
  // necesita tiempo real: bajo el reloj falso el `await` no resuelve nunca.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 60)),
  );
  await _settle(tester);
}

/// Camina los cuatro primeros pasos y deja la pantalla en el quinto, con el
/// mismo perfil que el recorrido completo: M, 178 cm, 82 kg, ligero, bajar.
Future<void> _hastaElPlan(WidgetTester tester) async {
  await _elegir(tester, 'Masculino');
  await _continuar(tester, 'Continuar');

  final campos = find.byType(TextField);
  await tester.enterText(campos.at(0), '178');
  await tester.enterText(campos.at(1), '82');
  await _settle(tester);
  await _continuar(tester, 'Continuar');

  await _elegir(tester, ActivityLevel.light.label);
  await _continuar(tester, 'Continuar');

  // Alimentación: se pasa de largo sin tocar nada, que es lo que hace la
  // mayoría y lo que el paso permite explícitamente.
  await _continuar(tester, 'Continuar');

  await _elegir(tester, GoalType.lose.label);
  await _continuar(tester, 'Continuar');
}

Future<void> _elegir(WidgetTester tester, String etiqueta) async {
  await tester.ensureVisible(find.text(etiqueta));
  await tester.pump();
  await tester.tap(find.text(etiqueta));
  await _settle(tester);
}

/// El objetivo que le corresponde al perfil guardado, con las funciones del
/// dominio. Se recalcula en vez de escribirlo a mano porque depende de la edad,
/// y la edad depende del día en que corra el test.
({CalorieTargetResult target, double rateKgPerWeek}) _planCalculado(
  LocalRepository repo, {
  GoalPace? pace,
}) {
  final profile = repo.profile;
  final bmrValue = bmrMifflinStJeor(
    weightKg: repo.currentWeightKg!,
    heightCm: profile.heightCm!,
    ageYears: ageFromBirthDate(profile.birthDate!),
    sex: profile.biologicalSex,
  );
  return calorieTargetForPace(
    tdee: tdee(bmr: bmrValue, activityLevel: profile.activityLevel),
    goalType: GoalType.lose,
    fractionOfTdee: (pace ?? GoalPreset.lose.defaultPace).fractionFor(
      GoalType.lose,
    ),
    sex: profile.biologicalSex,
  );
}

int _objetivoCalculado(LocalRepository repo, {GoalPace? pace}) =>
    _planCalculado(repo, pace: pace).target.target;

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

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('sin fecha de nacimiento no se puede pasar del primer paso', (
    tester,
  ) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      (container, _) = await _boot();
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await _settle(tester);

    expect(find.text('Paso 1 de 6'), findsOneWidget);
    await _continuar(tester, 'Continuar');

    // Sigue en el primero: sin edad no hay Mifflin-St Jeor y el paso no se
    // puede dar por cumplido.
    expect(find.text('Paso 1 de 6'), findsOneWidget);
  });

  testWidgets('los seis pasos se caminan y dejan a la persona en Inicio', (
    tester,
  ) async {
    late ProviderContainer container;
    late LocalRepository repo;
    await tester.runAsync(() async {
      (container, repo) = await _boot(birthDate: DateTime(1990, 4, 12));
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await _settle(tester);

    // ── Paso 1: sexo y nacimiento ──────────────────────────────────────
    expect(find.text('Empecemos por vos'), findsOneWidget);
    await tester.tap(find.text('Masculino'));
    await _settle(tester);
    await _continuar(tester, 'Continuar');

    // ── Paso 2: altura y peso ──────────────────────────────────────────
    expect(find.text('Paso 2 de 6'), findsOneWidget);
    final campos = find.byType(TextField);
    await tester.enterText(campos.at(0), '178');
    await tester.enterText(campos.at(1), '82');
    await _settle(tester);
    await _continuar(tester, 'Continuar');

    expect(find.text('Paso 3 de 6'), findsOneWidget);
    expect(repo.profile.heightCm, 178);
    // El peso entra como registro con fecha, no como campo del perfil: es lo
    // que hace que el primer punto de la curva de progreso sea el de hoy.
    expect(repo.currentWeightKg, 82);
    expect(repo.weightOn(today()), isNotNull);

    // ── Paso 3: nivel de actividad ─────────────────────────────────────
    await tester.tap(find.text(ActivityLevel.light.label));
    await _settle(tester);
    await _continuar(tester, 'Continuar');

    // ── Paso 4: alimentación ───────────────────────────────────────────
    // Es el único paso que se puede pasar sin tocar nada, y se prueba tocando
    // algo: una alergia elegida acá tiene que quedar escrita en el momento, no
    // al final del alta, porque quien cierra la app a mitad de camino no puede
    // volver a encontrarse sin ella.
    expect(find.text('Paso 4 de 6'), findsOneWidget);
    expect(find.text('¿Hay algo que no comas?'), findsOneWidget);
    await _elegir(tester, DietaryFlag.glutenFree.label);
    expect(repo.profile.dietaryFlags, <DietaryFlag>[DietaryFlag.glutenFree]);
    await _continuar(tester, 'Continuar');

    // ── Paso 5: objetivo ───────────────────────────────────────────────
    expect(find.text('Paso 5 de 6'), findsOneWidget);
    expect(find.text('¿Qué buscás?'), findsOneWidget);
    expect(repo.profile.activityLevel, ActivityLevel.light);

    // Viene con "Mantener" marcado —es el objetivo de referencia que crea el
    // alta— así que elegir otro es un toque de verdad y no una formalidad.
    expect(find.text(GoalType.maintain.label), findsOneWidget);
    await tester.ensureVisible(find.text(GoalType.lose.label));
    await tester.pump();
    await tester.tap(find.text(GoalType.lose.label));
    await _settle(tester);
    await _continuar(tester, 'Continuar');

    // ── Paso 6: el número, antes de entrar ─────────────────────────────
    expect(find.text('Paso 6 de 6'), findsOneWidget);
    expect(find.text('Tus calorías por día'), findsOneWidget);

    // Elegir el objetivo todavía no guardó nada: el objetivo vigente sigue
    // siendo el de referencia. Si acá se guardara, "Atrás" ya no alcanzaría
    // para deshacer una elección que nunca se confirmó.
    expect(repo.currentGoalOrNull?.goalType, GoalType.maintain);

    // El número está en pantalla, y es el mismo que el del resumen: es lo que
    // se está por confirmar.
    final esperado = _objetivoCalculado(repo);
    expect(find.text(Fmt.integer(esperado)), findsWidgets);

    await _continuar(tester, 'Confirmar y empezar');

    expect(find.text('INICIO'), findsOneWidget);

    // Y el objetivo salió del cálculo, no del valor de referencia: es la razón
    // entera por la que esta pantalla existe.
    final goal = repo.currentGoalOrNull;
    expect(goal, isNotNull);
    expect(goal!.goalType, GoalType.lose);
    expect(goal.targetMethod, TargetMethod.calculated);
    expect(goal.baseCalorieTarget, esperado);
    // Los kilos por semana no se eligen: salen del gasto de esta persona.
    expect(goal.rateKgPerWeek, _planCalculado(repo).rateKgPerWeek);
    expect(goal.bmrKcal, isNotNull);
    expect(repo.needsOnboarding, isFalse);
  });

  testWidgets('el ritmo elegido es el que queda guardado', (tester) async {
    late ProviderContainer container;
    late LocalRepository repo;
    await tester.runAsync(() async {
      (container, repo) = await _boot(birthDate: DateTime(1990, 4, 12));
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await _settle(tester);
    await _hastaElPlan(tester);

    // Cada opción muestra el objetivo que deja: es la única diferencia real
    // entre ellas, y sin el número al lado la elección se haría sobre un
    // adjetivo.
    final suave = _planCalculado(repo, pace: GoalPace.gentle);
    expect(find.text(Fmt.kcal(suave.target.target)), findsWidgets);
    // Y el porcentaje del gasto, que es lo que hace comparable la elección
    // entre dos personas de tamaños distintos.
    expect(
      find.textContaining(GoalPace.gentle.shareLabelFor(GoalType.lose)),
      findsOneWidget,
    );

    await _elegir(tester, GoalPace.gentle.label);
    await _continuar(tester, 'Confirmar y empezar');

    final goal = repo.currentGoalOrNull!;
    expect(goal.rateKgPerWeek, suave.rateKgPerWeek);
    expect(goal.baseCalorieTarget, suave.target.target);
    expect(goal.targetMethod, TargetMethod.calculated);

    // El déficit es el 10 % de su gasto, no medio kilo por semana para todos.
    expect(
      (goal.tdeeKcal! - goal.baseCalorieTarget) / goal.tdeeKcal!,
      closeTo(0.10, 0.005),
    );
  });

  testWidgets('el número se puede escribir, y queda marcado como manual', (
    tester,
  ) async {
    late ProviderContainer container;
    late LocalRepository repo;
    await tester.runAsync(() async {
      (container, repo) = await _boot(birthDate: DateTime(1990, 4, 12));
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await _settle(tester);
    await _hastaElPlan(tester);

    await tester.ensureVisible(find.text('Prefiero escribir el número'));
    await tester.pump();
    await tester.tap(find.text('Prefiero escribir el número'));
    await _settle(tester);

    await tester.enterText(find.byType(TextField).first, '1900');
    await _settle(tester);
    await _continuar(tester, 'Confirmar y empezar');

    expect(find.text('INICIO'), findsOneWidget);

    // Un número escrito no puede decir "calculado": de dónde salió cada valor
    // es parte del valor (RN-03).
    final goal = repo.currentGoalOrNull!;
    expect(goal.baseCalorieTarget, 1900);
    expect(goal.targetMethod, TargetMethod.manual);
    // El BMR se guarda igual: es un hecho de los datos del cuerpo, y es lo que
    // después permite explicar cuánto se apartó el número elegido.
    expect(goal.bmrKcal, isNotNull);
  });

  testWidgets('la propuesta de la IA se ve, se acepta y queda con su método', (
    tester,
  ) async {
    late ProviderContainer container;
    late LocalRepository repo;
    final ia = _FakeTargetClient(
      answer: const AiCalorieTarget(
        targetKcal: 2050,
        rationale: 'Con un trabajo de oficina y dos entrenamientos, el gasto '
            'estimado se queda un poco corto: 2.050 te deja margen.',
        clamped: false,
        bmrKcal: 1758,
        tdeeKcal: 2417,
      ),
    );
    await tester.runAsync(() async {
      (container, repo) = await _boot(
        birthDate: DateTime(1990, 4, 12),
        calorieTargets: ia,
      );
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await _settle(tester);
    await _hastaElPlan(tester);

    // No se pide sola al entrar: gastar una consulta de la cuota de alguien que
    // iba a aceptar el número calculado es cobrarle por algo que no pidió.
    expect(ia.calls, 0);

    await _elegir(tester, 'Que lo calcule la IA');
    expect(ia.calls, 1);

    // El porqué está en pantalla. Sin él esto no tiene sentido: el número solo
    // ya lo da la fórmula, y sin llamar a nadie.
    expect(find.textContaining('se queda un poco corto'), findsOneWidget);
    // Y todavía no reemplazó nada: es una opción al lado, no una decisión
    // tomada por otro.
    expect(find.text(Fmt.integer(_objetivoCalculado(repo))), findsWidgets);

    await _elegir(tester, 'Usar este número');
    await _continuar(tester, 'Confirmar y empezar');

    expect(find.text('INICIO'), findsOneWidget);
    final goal = repo.currentGoalOrNull!;
    expect(goal.baseCalorieTarget, 2050);
    expect(goal.targetMethod, TargetMethod.ai);
    // Ni `calculated` ni `manual`: no salió de Mifflin-St Jeor y nadie lo
    // escribió, y confundirlos borraría la única pista de por qué el objetivo
    // no coincide con la fórmula.
    expect(goal.bmrKcal, isNotNull);
  });

  testWidgets('si la IA falla se sigue con el calculado', (tester) async {
    late ProviderContainer container;
    late LocalRepository repo;
    await tester.runAsync(() async {
      (container, repo) = await _boot(
        birthDate: DateTime(1990, 4, 12),
        calorieTargets: _FakeTargetClient(
          error: const AppError(
            code: ApiErrorCode.quotaExceeded,
            message: 'Llegaste a las 20 consultas de hoy.',
          ),
        ),
      );
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await _settle(tester);
    await _hastaElPlan(tester);

    await _elegir(tester, 'Que lo calcule la IA');

    // El motivo se ve en la pantalla y no en un cartel que se va: acá no hay a
    // dónde volver, y quien no llegue a leerlo se queda sin saber si conviene
    // reintentar o seguir.
    expect(find.textContaining('20 consultas'), findsOneWidget);

    // Y sobre todo: el alta no se traba. Un fallo de la IA no puede dejar a
    // nadie encerrado en el último paso.
    await _continuar(tester, 'Confirmar y empezar');
    expect(find.text('INICIO'), findsOneWidget);
    expect(repo.currentGoalOrNull!.targetMethod, TargetMethod.calculated);
    expect(repo.currentGoalOrNull!.baseCalorieTarget, _objetivoCalculado(repo));
  });

  testWidgets('sin servidor no se ofrece un botón que siempre falla', (
    tester,
  ) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      (container, _) = await _boot(birthDate: DateTime(1990, 4, 12));
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await _settle(tester);
    await _hastaElPlan(tester);

    expect(find.text('Que lo calcule la IA'), findsNothing);
    // Y el resto del paso sigue entero.
    expect(find.text('Prefiero escribir el número'), findsOneWidget);
  });

  // El paso del objetivo es el más largo del alta —el número, cuatro ritmos
  // con su cuenta al lado, el campo a mano y el resumen— y es el último: si
  // desborda, desborda justo antes de entrar a la app y sin nada que se pueda
  // tocar para arreglarlo.
  for (final scale in <double>[1.0, 1.3]) {
    testWidgets('el paso del objetivo se dibuja sin desbordes (texto ×$scale)', (
      tester,
    ) async {
      late ProviderContainer container;
      await tester.runAsync(() async {
        (container, _) = await _boot(birthDate: DateTime(1990, 4, 12));
      });
      addTearDown(container.dispose);

      await tester.pumpWidget(_wrap(container, textScale: scale));
      await _settle(tester);
      await _hastaElPlan(tester);

      expect(find.text('Paso 6 de 6'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('volver atrás conserva lo cargado', (tester) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      (container, _) = await _boot(birthDate: DateTime(1990, 4, 12));
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await _settle(tester);
    await _continuar(tester, 'Continuar');

    await tester.enterText(find.byType(TextField).at(0), '178');
    await _settle(tester);

    await tester.tap(find.text('Atrás'));
    await _settle(tester);
    expect(find.text('Paso 1 de 6'), findsOneWidget);

    await _continuar(tester, 'Continuar');

    // La altura sigue escrita: si volver borrara lo cargado, "Atrás" sería una
    // trampa y nadie lo tocaría dos veces.
    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller?.text,
      '178',
    );
  });

  testWidgets('hay salida: no se queda nadie encerrado', (tester) async {
    late ProviderContainer container;
    late LocalRepository repo;
    await tester.runAsync(() async {
      (container, repo) = await _boot();
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await _settle(tester);

    // Sin esto, quien no quiera dar estos datos no tiene forma de salir: el
    // router lo devuelve acá en cada arranque y la única salida sería
    // desinstalar.
    await tester.ensureVisible(find.text('Salir'));
    await tester.pump();
    await tester.tap(find.text('Salir'));
    await _settle(tester);

    await tester.tap(find.text('Salir').last);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await _settle(tester);

    expect(find.text('BIENVENIDA'), findsOneWidget);
    expect(repo.hasSession, isFalse);
  });
}
