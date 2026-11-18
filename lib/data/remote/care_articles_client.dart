import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error/app_error.dart';
import '../../domain/models/care_article.dart';
import 'care_feedback_client.dart';

/// Los artículos y recetas que publicaron las profesionales con acceso a esta
/// cuenta (migración 52).
///
/// Solo lectura, y sin marca de "leído" en el servidor: lo que la persona ya
/// abrió se guarda en el teléfono (`ArticleSeenStore`). RLS decide qué llega
/// —lo publicado y no borrado de cada profesional con un acceso vigente—; el
/// filtro de abajo está para usar el índice.
class CareArticlesClient {
  CareArticlesClient(this._db);

  factory CareArticlesClient.fromInstance() =>
      CareArticlesClient(Supabase.instance.client);

  final SupabaseClient _db;

  /// Una lista que se lee de arriba abajo no necesita más, y sin tope una
  /// profesional muy activa haría crecer la consulta sin límite.
  static const int maxItems = 100;

  Future<List<CareArticle>> list() async {
    try {
      final rows = await _db
          .from('care_articles')
          .select('id, author_id, kind, title, body, tag, published_at, media')
          .not('published_at', 'is', null)
          .isFilter('deleted_at', null)
          .order('published_at', ascending: false)
          .limit(maxItems)
          .timeout(CareFeedbackClient.timeout);
      if (rows.isEmpty) return const <CareArticle>[];

      final names = await professionalNames(_db, <String>{
        for (final r in rows)
          if (r['author_id'] case final String id) id,
      });
      final urls = await _signImages(<String>[
        for (final r in rows) ...ArticleMedia.imagePaths(r['media']),
      ]);
      return parseRows(rows, namesById: names, imageUrls: urls);
    } on Exception {
      throw const AppError(
        code: ApiErrorCode.offline,
        message: 'No pudimos traer los artículos. Revisá tu conexión.',
      );
    }
  }

  /// Las imágenes de los artículos, firmadas todas juntas (bucket
  /// `article-media`, migración 61). Si falla, los artículos llegan igual,
  /// sin esas imágenes.
  Future<Map<String, String>> _signImages(List<String> paths) async {
    if (paths.isEmpty) return const <String, String>{};
    try {
      final signed = await _db.storage
          .from('article-media')
          .createSignedUrlsResult(paths, 60 * 60)
          .timeout(CareFeedbackClient.timeout);
      return <String, String>{
        for (final s in signed.whereType<SignedUrlSuccess>()) s.path: s.signedUrl,
      };
    } on Exception {
      return const <String, String>{};
    }
  }

  /// Público para probarlo sin servidor: descarta las filas que no cierran.
  static List<CareArticle> parseRows(
    List<dynamic> rows, {
    Map<String, String> namesById = const <String, String>{},
    Map<String, String> imageUrls = const <String, String>{},
  }) => <CareArticle>[
    for (final row in rows)
      if (row is Map)
        if (CareArticle.fromRow(
              Map<String, dynamic>.from(row),
              authorName: namesById[row['author_id']] ?? '',
              imageUrls: imageUrls,
            )
            case final CareArticle a)
          a,
  ];
}
