// El sheet de "Agregar a…" abre con las tres puertas fijas y nada más: lo que
// se repite aparece recién cuando se desliza hacia arriba.
//
// Misma mecánica que `home_screen_test.dart`: la base local se toca dentro de
// `tester.runAsync` y no se usa `pumpAndSettle`.

import 'package:ceres/core/theme/app_theme.dart';
import 'package:ceres/core/utils/dates.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/domain/enums/enums.dart';
import 'package:ceres/presentation/providers/app_providers.dart';
import 'package:ceres/presentation/screens/home/add_to_slot_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting(appLocale);
  });

  testWidgets('lo que se repite aparece recién al deslizar hacia arriba', (
    tester,
  ) async {
    final container = await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = await LocalStore.open();
      store.seed();
      return ProviderContainer(
        overrides: [
          repositoryProvider.overrideWithValue(
            LocalRepository(store, onChanged: () {}),
          ),
        ],
      );
    });
    addTearDown(container!.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: NmAppTheme.dark(),
          locale: const Locale('es', 'AR'),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAddToSlotSheet(
                  context,
                  slot: MealSlot.lunch,
                  date: DateTime.now(),
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final repeated = find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          (widget.data == 'DE LO QUE REPETÍS' ||
              (widget.data?.startsWith('Las comidas que repitas') ?? false)),
    );
    expect(find.text('Buscar alimentos'), findsOneWidget);
    expect(repeated, findsNothing);

    await tester.drag(find.text('Buscar alimentos'), const Offset(0, -200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(repeated, findsOneWidget);
  });
}
