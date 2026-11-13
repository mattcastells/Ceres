// El texto de los artículos: el markdown mínimo que dibujan el panel y la app.
//
// Son los casos de `backoffice/lib/articulos.test.ts`, uno por uno: si el
// panel y el teléfono leyeran distinto el mismo texto, la vista previa que ve
// la profesional mentiría. `validarArticulo` no se porta porque la app no
// escribe artículos.

import 'package:ceres/domain/services/article_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('articleBlocks', () {
    test('párrafos separados por una línea en blanco', () {
      expect(articleBlocks('Uno\ndos\n\nTres'), <ArticleBlock>[
        const ArticleParagraph('Uno\ndos'),
        const ArticleParagraph('Tres'),
      ]);
    });

    test('listas con guion y numeradas, y un título', () {
      expect(
        articleBlocks(
          '# Ingredientes\n- Avena\n- Banana\n\n1. Mezclar\n2. Hornear',
        ),
        <ArticleBlock>[
          const ArticleHeading('Ingredientes'),
          const ArticleList(ordered: false, items: <String>['Avena', 'Banana']),
          const ArticleList(
            ordered: true,
            items: <String>['Mezclar', 'Hornear'],
          ),
        ],
      );
    });

    test('una lista pegada a un párrafo empieza un bloque nuevo', () {
      expect(articleBlocks('Necesitás:\n- Huevo'), <ArticleBlock>[
        const ArticleParagraph('Necesitás:'),
        const ArticleList(ordered: false, items: <String>['Huevo']),
      ]);
    });

    test('una línea sin viñeta sigue al ítem anterior', () {
      expect(articleBlocks('- Yogur natural\n  sin azúcar'), <ArticleBlock>[
        const ArticleList(
          ordered: false,
          items: <String>['Yogur natural sin azúcar'],
        ),
      ]);
    });

    test('CRLF de Windows', () {
      expect(articleBlocks('A\r\n\r\nB'), <ArticleBlock>[
        const ArticleParagraph('A'),
        const ArticleParagraph('B'),
      ]);
    });
  });

  test('articleSpans: negrita, y un ** sin cerrar queda como texto', () {
    expect(articleSpans('Sumá **proteína** al desayuno'), <ArticleSpan>[
      const ArticleSpan('Sumá '),
      const ArticleSpan('proteína', bold: true),
      const ArticleSpan(' al desayuno'),
    ]);
    expect(articleSpans('2 ** 3'), <ArticleSpan>[const ArticleSpan('2 ** 3')]);
  });

  test('articleExcerpt: los párrafos, sin títulos ni marcas, cortado en una '
      'palabra', () {
    expect(articleExcerpt('# Título\nUn **texto** corto.'), 'Un texto corto.');
    expect(articleExcerpt('- Avena\n- Banana\n\nRinde 8.'), 'Rinde 8.');
    expect(articleExcerpt('- Avena\n- Banana'), 'Avena · Banana');
    final largo = articleExcerpt('palabra ' * 60, length: 50);
    expect(largo.endsWith('…'), isTrue);
    expect(largo.length, lessThanOrEqualTo(51));
  });
}
