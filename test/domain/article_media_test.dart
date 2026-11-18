// Los adjuntos de los artículos (migración 61).
import 'package:ceres/domain/models/care_article.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lee videos e imágenes firmadas, en orden, y descarta lo demás', () {
    final media = ArticleMedia.parse(
      <Object?>[
        <String, dynamic>{'type': 'youtube', 'id': 'dQw4w9WgXcQ'},
        <String, dynamic>{'type': 'image', 'path': 'a/1.png'},
        <String, dynamic>{'type': 'image', 'path': 'a/sin-firma.png'},
        <String, dynamic>{'type': 'youtube', 'id': 'corto'},
        'basura',
      ],
      imageUrls: <String, String>{'a/1.png': 'https://firmada/1'},
    );
    expect(media.map((m) => m.kind), <ArticleMediaKind>[
      ArticleMediaKind.youtube,
      ArticleMediaKind.image,
    ]);
    expect(
      media.first.previewUrl,
      'https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
    );
    expect(
      media.first.openUri.toString(),
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    );
    expect(media.last.previewUrl, 'https://firmada/1');
    expect(media.last.openUri, isNull);
  });

  test('las rutas de imagen se juntan para firmarlas de una vez', () {
    expect(
      ArticleMedia.imagePaths(<Object?>[
        <String, dynamic>{'type': 'image', 'path': 'a/1.png'},
        <String, dynamic>{'type': 'youtube', 'id': 'dQw4w9WgXcQ'},
      ]),
      <String>['a/1.png'],
    );
    expect(ArticleMedia.imagePaths(null), isEmpty);
  });
}
