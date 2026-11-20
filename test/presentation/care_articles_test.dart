// Los artículos y recetas de la nutricionista, en la app.
//
// Se leen; lo visto se guarda en el teléfono. Inicio avisa con una fila y
// deja de avisar cuando se mira la lista; cada artículo dice "Nuevo" hasta
// que se abre.

import 'package:ceres/core/config/feature_flags.dart';
import 'package:ceres/core/theme/app_theme.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/remote/care_articles_client.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/domain/models/care_article.dart';
import 'package:ceres/presentation/providers/app_providers.dart';
import 'package:ceres/presentation/providers/auth_providers.dart';
import 'package:ceres/presentation/providers/care_providers.dart';
import 'package:ceres/presentation/screens/home/home_screen.dart';
import 'package:ceres/presentation/screens/profile/care_articles_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Inicio no muestra nada de la nutricionista con `NM_NUTRITIONIST` apagado.
const bool _sinNutricionista = !FeatureFlags.nutritionist;

class _FakeArticlesClient implements CareArticlesClient {
  _FakeArticlesClient(this.items);

  final List<CareArticle> items;

  @override
  Future<List<CareArticle>> list() async => items;
}

CareArticle _article(
  String id,
  String title, {
  CareArticleKind kind = CareArticleKind.article,
  String body = 'Un texto.',
  String? tag,
  int daysAgo = 0,
}) => CareArticle(
  id: id,
  authorId: 'pro-1',
  authorName: 'Lic. Valentina Ruiz',
  kind: kind,
  title: title,
  body: body,
  tag: tag,
  publishedAt: DateTime.now().subtract(Duration(days: daysAgo, minutes: 1)),
);

class _Boot {
  _Boot(this.container, this.repository);
  final ProviderContainer container;
  final LocalRepository repository;
}

Future<_Boot> _boot(
  WidgetTester tester, {
  CareArticlesClient? articles,
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
      overrides: [
        repositoryProvider.overrideWithValue(repository),
        isCloudEnabledProvider.overrideWithValue(true),
        if (articles != null)
          careArticlesClientProvider.overrideWithValue(articles),
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

void main() {
  setUpAll(() => initializeDateFormatting('es_AR'));

  group('artículos', () {
    final articles = <CareArticle>[
      _article(
        'receta',
        'Budín de avena y banana',
        kind: CareArticleKind.recipe,
        tag: 'Desayunos',
        body:
            '# Ingredientes\n- 2 bananas\n- 1 taza de avena\n\n'
            '# Preparación\n1. Pisá las bananas.\n2. Horno medio.\n\n'
            'Rinde 8 porciones de **120 kcal**.',
      ),
      _article('vianda', 'Cómo armar una vianda', daysAgo: 3),
    ];

    testWidgets('Inicio avisa los nuevos con una fila, sin más', (
      tester,
    ) async {
      final boot = await _boot(tester, articles: _FakeArticlesClient(articles));
      await tester.pumpWidget(_wrap(boot.container, const HomeScreen()));
      await _settle(tester);

      expect(find.text('DE TU NUTRICIONISTA'), findsOneWidget);
      expect(find.text('2 artículos y recetas nuevos'), findsOneWidget);
      // Los títulos son para la lista, no para Inicio.
      expect(find.text('Budín de avena y banana'), findsNothing);
    }, skip: _sinNutricionista);

    testWidgets('mirar la lista apaga el aviso de Inicio; "Nuevo" queda '
        'hasta abrirlo', (tester) async {
      final boot = await _boot(tester, articles: _FakeArticlesClient(articles));
      await tester.pumpWidget(
        _wrap(boot.container, const CareArticlesScreen()),
      );
      await _settle(tester);

      expect(find.text('Budín de avena y banana'), findsOneWidget);
      expect(find.text('Cómo armar una vianda'), findsOneWidget);
      expect(find.text('Receta'), findsOneWidget);
      expect(find.text('Artículo'), findsOneWidget);
      expect(find.text('Desayunos'), findsOneWidget);
      expect(find.text('Nuevo'), findsNWidgets(2));
      // El extracto sale de los párrafos, sin marcas.
      expect(find.text('Rinde 8 porciones de 120 kcal.'), findsOneWidget);
      expect(find.textContaining('Lic. Valentina Ruiz · '), findsNWidgets(2));

      expect(boot.container.read(newArticlesProvider), isEmpty);
    });

    testWidgets('el detalle dibuja el formato y lo marca como visto', (
      tester,
    ) async {
      final boot = await _boot(tester, articles: _FakeArticlesClient(articles));
      await tester.pumpWidget(
        _wrap(boot.container, const CareArticleScreen(articleId: 'receta')),
      );
      await _settle(tester);

      expect(find.text('Budín de avena y banana'), findsOneWidget);
      expect(find.text('Ingredientes'), findsOneWidget);
      expect(find.text('Preparación'), findsOneWidget);
      expect(find.text('•'), findsNWidgets(2));
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
      expect(
        find.text('Pisá las bananas.', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.text('Rinde 8 porciones de 120 kcal.', findRichText: true),
        findsOneWidget,
      );

      final seen = boot.container.read(articleSeenProvider).value!;
      expect(seen.opened, contains('receta'));
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getStringList('ceres.care_articles.opened'),
        contains('receta'),
      );
      // Abierto deja de ser nuevo; el otro sigue avisando en Inicio.
      expect(
        boot.container.read(newArticlesProvider).map((a) => a.id),
        <String>['vianda'],
      );
    });

    testWidgets('lo visto antes no avisa', (tester) async {
      final boot = await _boot(
        tester,
        articles: _FakeArticlesClient(articles),
        prefs: <String, Object>{
          'ceres.care_articles.opened': <String>['receta', 'vianda'],
        },
      );
      await tester.pumpWidget(_wrap(boot.container, const HomeScreen()));
      await _settle(tester);
      expect(find.text('DE TU NUTRICIONISTA'), findsNothing);
    });

    testWidgets('un artículo que ya no está lo dice', (tester) async {
      final boot = await _boot(tester, articles: _FakeArticlesClient(articles));
      await tester.pumpWidget(
        _wrap(boot.container, const CareArticleScreen(articleId: 'otro')),
      );
      await _settle(tester);
      expect(find.text('Este artículo ya no está'), findsOneWidget);
    });

    testWidgets('sin servidor no hay artículos ni aviso', (tester) async {
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
      expect(container.read(newArticlesProvider), isEmpty);
    });
  });
}
