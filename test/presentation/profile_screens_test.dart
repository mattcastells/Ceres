// Pantallas de perfil a tamaño de teléfono real y con el texto agrandado:
// un RenderFlex desbordado es una excepción, así que acá falla el test en vez
// de romperse en el teléfono.

import 'package:ceres/core/theme/app_theme.dart';
import 'package:ceres/core/utils/dates.dart';
import 'package:ceres/data/local/local_auth_gateway.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/presentation/providers/app_providers.dart';
import 'package:ceres/presentation/providers/auth_providers.dart';
import 'package:ceres/presentation/screens/profile/body_target_screens.dart';
import 'package:ceres/presentation/screens/progress/progress_detail_screens.dart';
import 'package:ceres/presentation/screens/settings/water_goal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _boot() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final store = await LocalStore.open();
  final repository = LocalRepository(store, onChanged: () {});
  await repository.signIn('yo@ceres.test');
  return ProviderContainer(
    overrides: <Override>[
      repositoryProvider.overrideWithValue(repository),
      authGatewayProvider.overrideWithValue(LocalAuthGateway()),
    ],
  );
}

Widget _wrap(ProviderContainer container, Widget screen, double textScale) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: NmAppTheme.dark(),
        locale: const Locale('es', 'AR'),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: screen,
        ),
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
    // Un Galaxy real, no los 800×600 por defecto.
    view.physicalSize = const Size(1080, 2340);
    view.devicePixelRatio = 2.75;
  });

  final screens = <String, Widget Function()>{
    'Perfil corporal': BodyProfileScreen.new,
    'Objetivo y macros': TargetScreen.new,
    'Meta de agua': WaterGoalScreen.new,
    // Medidas corporales pasó de una fila de píldoras a ocho campos con su
    // etiqueta, su unidad y la última medida abajo: es la pantalla del grupo
    // con más chances de desbordar cuando alguien agranda el texto.
    'Medidas corporales': MeasurementsScreen.new,
    'Mis cosas': MyItemsScreen.new,
  };

  for (final entry in screens.entries) {
    // 1.0 es el tamaño normal; 1.3 es lo que usa mucha gente en un Samsung.
    for (final scale in <double>[1.0, 1.3]) {
      testWidgets(
        '${entry.key} se dibuja sin desbordes (texto ×$scale)',
        (tester) async {
          late ProviderContainer container;
          await tester.runAsync(() async {
            container = await _boot();
          });
          addTearDown(container.dispose);

          await tester.pumpWidget(
            _wrap(container, entry.value(), scale),
          );
          await _settle(tester);

          // Un RenderFlex desbordado es una excepción: acá se convierte en una
          // falla del test en vez de en una pantalla rota en el teléfono.
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
