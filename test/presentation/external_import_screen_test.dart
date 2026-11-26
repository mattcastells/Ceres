// La pantalla de "Traer datos de otra app": pegar, revisar e importar.

import 'package:ceres/core/theme/app_theme.dart';
import 'package:ceres/core/utils/dates.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/domain/models/user_profile.dart';
import 'package:ceres/presentation/providers/app_providers.dart';
import 'package:ceres/presentation/screens/settings/external_import_screen.dart';
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

  testWidgets('pegar el bloque muestra qué entra y lo importa', (tester) async {
    final repo = await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = await LocalStore.open();
      store.profile = UserProfile.empty('persona');
      return LocalRepository(store, onChanged: () {});
    });
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(repo!)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: NmAppTheme.dark(),
          locale: const Locale('es', 'AR'),
          home: const ExternalImportScreen(),
        ),
      ),
    );
    await tester.pump();

    final yesterday = isoDate(today().subtract(const Duration(days: 1)));
    await tester.enterText(
      find.byType(TextField),
      '===CERES===\n{"v": 1, "pesajes": [{"fecha": "$yesterday", "kg": 81}], '
      '"suplementos": [{"nombre": "Creatina", "dosis": "5 g"}]}\n===FIN===',
    );
    await tester.pump();
    await tester.tap(find.text('Revisar'));
    await tester.pump();

    expect(find.text('Pesajes'), findsOneWidget);
    expect(find.textContaining('No se importa suplementos'), findsOneWidget);

    await tester.ensureVisible(find.text('Importar 1 registro'));
    await tester.pump();
    await tester.tap(find.text('Importar 1 registro'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    expect(repo.weightLogs.single.weightKg, 81);
  });
}
