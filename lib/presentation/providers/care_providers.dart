import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/article_seen_store.dart';
import '../../data/remote/care_articles_client.dart';
import '../../data/remote/care_feedback_client.dart';
import '../../data/remote/care_report_client.dart';
import '../../domain/models/care_article.dart';
import '../../domain/models/care_feedback.dart';
import '../../domain/models/weekly_report.dart';
import 'app_providers.dart';

// ── De tu nutricionista ──────────────────────────────────────────────────

/// Null sin servidor: no hay nutricionista que escriba.
final careFeedbackClientProvider = Provider<CareFeedbackClient?>((ref) => null);

/// Todo lo publicado para esta cuenta, de lo más nuevo a lo más viejo.
///
/// `autoDispose` por lo mismo que `careGrantsProvider`: sin eso la lista se
/// consulta una vez por sesión de app y una devolución nueva no aparecería
/// hasta reiniciar. Inicio lo mantiene vivo mientras está montado; volver a la
/// app y tirar para actualizar lo invalidan.
final careFeedbackProvider = FutureProvider.autoDispose<CareInbox>((ref) async {
  final client = ref.watch(careFeedbackClientProvider);
  if (client == null) return CareInbox(const <CareFeedback>[]);
  return CareInbox(await client.list());
});

// ── Artículos y recetas ──────────────────────────────────────────────────

/// Null sin servidor: no hay profesional que publique.
final careArticlesClientProvider = Provider<CareArticlesClient?>((ref) => null);

/// Lo publicado por las profesionales con acceso, de lo más nuevo a lo más
/// viejo. `autoDispose` por lo mismo que [careFeedbackProvider].
final careArticlesProvider = FutureProvider.autoDispose<List<CareArticle>>((
  ref,
) async {
  final client = ref.watch(careArticlesClientProvider);
  if (client == null) return const <CareArticle>[];
  return client.list();
});

/// Dónde se guarda qué se vio. Un provider para poder cambiarlo en los tests.
final articleSeenStoreProvider = Provider<ArticleSeenStore>(
  (ref) => ArticleSeenStore(),
);

/// Qué artículos ya se abrieron y cuándo se miró la lista por última vez.
class ArticleSeenController extends AsyncNotifier<ArticleSeen> {
  @override
  Future<ArticleSeen> build() => ref.read(articleSeenStoreProvider).load();

  Future<void> markOpened(String id) async {
    final current = state.valueOrNull ?? await future;
    if (current.opened.contains(id)) return;
    final opened = <String>{...current.opened, id};
    state = AsyncData(
      ArticleSeen(opened: opened, listVisitedAt: current.listVisitedAt),
    );
    await ref.read(articleSeenStoreProvider).saveOpened(opened);
  }

  Future<void> markListVisited() async {
    final current = state.valueOrNull ?? await future;
    final now = DateTime.now();
    state = AsyncData(ArticleSeen(opened: current.opened, listVisitedAt: now));
    await ref.read(articleSeenStoreProvider).saveListVisited(now);
  }
}

final articleSeenProvider =
    AsyncNotifierProvider<ArticleSeenController, ArticleSeen>(
      ArticleSeenController.new,
    );

/// Los artículos que avisa Inicio. Vacío mientras carga o si algo falla: es
/// información que suma, no una que falte.
final newArticlesProvider = Provider.autoDispose<List<CareArticle>>((ref) {
  final articles = ref.watch(careArticlesProvider).valueOrNull;
  final seen = ref.watch(articleSeenProvider).valueOrNull;
  if (articles == null || seen == null) return const <CareArticle>[];
  return seen.newForHome(articles);
});

// ── Resumen semanal ──────────────────────────────────────────────────────

/// Null sin servidor: el resumen lo arma una Edge Function.
final careReportClientProvider = Provider<CareReportClient?>((ref) => null);

/// El último resumen guardado. Leerlo no gasta nada; generarlo sí, y eso lo
/// hace solo el botón de la pantalla.
final latestWeeklyReportProvider = FutureProvider.autoDispose<WeeklyReport?>((
  ref,
) async {
  final client = ref.watch(careReportClientProvider);
  if (client == null) return null;
  // El del período elegido en Progreso: el del mes no es el de la semana.
  return client.latestWeekly(days: ref.watch(progressRangeProvider).days);
});

/// Lo que se refresca al volver a la app o al tirar para actualizar: lo que
/// escribió o publicó la nutricionista. Un solo lugar para que los
/// disparadores no se separen con el tiempo.
void refreshServerState(WidgetRef ref) {
  ref
    ..invalidate(careFeedbackProvider)
    ..invalidate(careArticlesProvider);
}
