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
    this.media = const <ArticleMedia>[],
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

  /// Imágenes y videos, en el orden en que van debajo del texto
  /// (migración 61). Hasta cinco.
  final List<ArticleMedia> media;

  /// Lee una fila de `care_articles`, o `null` si no cierra. Una fila rota se
  /// descarta y no tumba la lista, como en `CareFeedback.fromRow`.
  static CareArticle? fromRow(
    Map<String, dynamic> row, {
    String authorName = '',
    Map<String, String> imageUrls = const <String, String>{},
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
      media: ArticleMedia.parse(row['media'], imageUrls: imageUrls),
    );
  }
}

enum ArticleMediaKind { image, youtube }

/// Un adjunto de un artículo: una imagen del bucket `article-media` o un video
/// de YouTube del que solo se guarda el id.
class ArticleMedia {
  const ArticleMedia({required this.kind, required this.ref, this.signedUrl});

  final ArticleMediaKind kind;

  /// La ruta en el bucket (imagen) o el id del video (YouTube).
  final String ref;

  /// La URL firmada de una imagen; `null` si no se pudo firmar.
  final String? signedUrl;

  /// Lo que se dibuja: la imagen, o la miniatura pública del video.
  String? get previewUrl => kind == ArticleMediaKind.youtube
      ? 'https://img.youtube.com/vi/$ref/hqdefault.jpg'
      : signedUrl;

  /// Adónde lleva tocarlo: el video en YouTube. Una imagen no lleva a ningún
  /// lado.
  Uri? get openUri => kind == ArticleMediaKind.youtube
      ? Uri.parse('https://www.youtube.com/watch?v=$ref')
      : null;

  static final RegExp _youtubeId = RegExp(r'^[\w-]{11}$');

  /// `care_articles.media`, sin lo que no cierra. Una imagen sin URL firmada
  /// se descarta: un recuadro vacío no le sirve a nadie.
  static List<ArticleMedia> parse(
    Object? raw, {
    Map<String, String> imageUrls = const <String, String>{},
  }) {
    if (raw is! List) return const <ArticleMedia>[];
    final out = <ArticleMedia>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final type = item['type'];
      if (type == 'youtube' &&
          item['id'] is String &&
          _youtubeId.hasMatch(item['id'] as String)) {
        out.add(
          ArticleMedia(kind: ArticleMediaKind.youtube, ref: item['id'] as String),
        );
      } else if (type == 'image' && item['path'] is String) {
        final path = item['path'] as String;
        final url = imageUrls[path];
        if (url != null) {
          out.add(
            ArticleMedia(
              kind: ArticleMediaKind.image,
              ref: path,
              signedUrl: url,
            ),
          );
        }
      }
      if (out.length == 5) break;
    }
    return out;
  }

  /// Las rutas de imagen de una fila, para firmarlas todas juntas.
  static List<String> imagePaths(Object? raw) => <String>[
    if (raw is List)
      for (final item in raw)
        if (item is Map && item['type'] == 'image' && item['path'] is String)
          item['path'] as String,
  ];
}
