/// Un artículo o una receta que la nutricionista publicó para todo su equipo
/// (migración 52).
///
/// No es una devolución: esa va a una persona y vive en `care_feedback`. Un
/// artículo es de la profesional y lo lee cualquiera que le haya dado acceso.
/// La app solo lee; qué llega lo decide RLS.
enum CareArticleKind {
  article('article', 'Artículo'),
  recipe('recipe', 'Receta');

  const CareArticleKind(this.wire, this.label);

  final String wire;
  final String label;

  /// Un tipo que esta versión no conoce se muestra como artículo: es texto
  /// igual, y perderlo por la etiqueta sería peor.
  static CareArticleKind fromWire(Object? raw) =>
      raw == 'recipe' ? recipe : article;
}

class CareArticle {
  const CareArticle({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.kind,
    required this.title,
    required this.body,
    required this.publishedAt,
    this.tag,
  });

  final String id;
  final String authorId;

  /// Vacío si `care_professionals` no lo devolvió.
  final String authorName;
  final CareArticleKind kind;
  final String title;
  final String body;

  /// "Desayunos", "Vianda". Opcional.
  final String? tag;
  final DateTime publishedAt;

  /// Lee una fila de `care_articles`, o `null` si no cierra. Una fila rota se
  /// descarta y no tumba la lista, como en `CareFeedback.fromRow`.
  static CareArticle? fromRow(
    Map<String, dynamic> row, {
    String authorName = '',
  }) {
    final id = row['id'];
    final title = row['title'];
    final body = row['body'];
    final rawPublished = row['published_at'];
    final published = rawPublished is String
        ? DateTime.tryParse(rawPublished)?.toLocal()
        : null;
    if (id is! String || id.isEmpty) return null;
    if (title is! String || title.trim().isEmpty) return null;
    if (body is! String || body.trim().isEmpty) return null;
    if (published == null) return null;

    final authorId = row['author_id'];
    final tag = row['tag'];
    return CareArticle(
      id: id,
      authorId: authorId is String ? authorId : '',
      authorName: authorName,
      kind: CareArticleKind.fromWire(row['kind']),
      title: title.trim(),
      body: body,
      tag: tag is String && tag.trim().isNotEmpty ? tag.trim() : null,
      publishedAt: published,
    );
  }
}
