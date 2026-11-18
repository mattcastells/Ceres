import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/care_article.dart';

/// Qué artículos ya vio la persona, guardado en el teléfono.
///
/// El servidor no tiene "leído" para artículos —un artículo es de todo el
/// equipo de la profesional, no de una persona—, así que la marca de "Nuevo"
/// vive acá. Perderla (otro teléfono, borrar datos) solo hace que vuelvan a
/// aparecer como nuevos: no hay nada que reparar.
///
/// Son dos marcas distintas a propósito:
///
/// - **abierto**: el artículo se leyó. En la lista deja de decir "Nuevo".
/// - **la lista se vio**: Inicio deja de avisar por lo publicado hasta ese
///   momento. Sin esto, una receta que a alguien no le interesa quedaría
///   avisando en Inicio para siempre.
class ArticleSeen {
  const ArticleSeen({this.opened = const <String>{}, this.listVisitedAt});

  final Set<String> opened;
  final DateTime? listVisitedAt;

  bool isNew(CareArticle a) => !opened.contains(a.id);

  /// Lo que Inicio cuenta como nuevo: sin abrir y publicado después de la
  /// última vez que se miró la lista.
  List<CareArticle> newForHome(List<CareArticle> all) => <CareArticle>[
    for (final a in all)
      if (isNew(a) &&
          (listVisitedAt == null || a.publishedAt.isAfter(listVisitedAt!)))
        a,
  ];
}

class ArticleSeenStore {
  static const String _openedKey = 'ceres.care_articles.opened';
  static const String _visitedKey = 'ceres.care_articles.list_visited_at';

  /// Tope de ids guardados. Más que esto son artículos que ya no están en la
  /// lista (que trae 100); se olvidan los más viejos.
  static const int maxOpened = 300;

  Future<ArticleSeen> load() async {
    final prefs = await SharedPreferences.getInstance();
    final visited = prefs.getString(_visitedKey);
    return ArticleSeen(
      opened: (prefs.getStringList(_openedKey) ?? const <String>[]).toSet(),
      listVisitedAt: visited == null ? null : DateTime.tryParse(visited),
    );
  }

  Future<void> saveOpened(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    final list = ids.toList();
    await prefs.setStringList(
      _openedKey,
      list.length > maxOpened ? list.sublist(list.length - maxOpened) : list,
    );
  }

  Future<void> saveListVisited(DateTime at) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_visitedKey, at.toIso8601String());
  }
}
