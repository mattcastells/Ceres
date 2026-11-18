/// El texto de los artículos y recetas: el markdown mínimo que dibujan el panel
/// y la app.
///
/// Es una traducción línea por línea de `backoffice/lib/articulos.ts`, con los
/// mismos casos de test. Las dos tienen que decir lo mismo: si el panel
/// muestra una lista y el teléfono un párrafo con guiones, la vista previa que
/// ve la profesional miente.
///
/// Las reglas: una línea en blanco separa bloques; `# ` (hasta tres `#`) es un
/// título; `- `, `* ` o `• ` es una viñeta y `1. ` o `1) ` un ítem numerado;
/// `**así**` es negrita. Lo que no entra en esas reglas se muestra tal cual.
library;

sealed class ArticleBlock {
  const ArticleBlock();
}

class ArticleHeading extends ArticleBlock {
  const ArticleHeading(this.text);
  final String text;

  @override
  bool operator ==(Object other) =>
      other is ArticleHeading && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'ArticleHeading($text)';
}

class ArticleParagraph extends ArticleBlock {
  const ArticleParagraph(this.text);

  /// Con los saltos de línea de adentro del párrafo: se respetan.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is ArticleParagraph && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'ArticleParagraph($text)';
}

class ArticleList extends ArticleBlock {
  const ArticleList({required this.ordered, required this.items});
  final bool ordered;
  final List<String> items;

  @override
  bool operator ==(Object other) =>
      other is ArticleList &&
      other.ordered == ordered &&
      other.items.join('\u0000') == items.join('\u0000') &&
      other.items.length == items.length;

  @override
  int get hashCode => Object.hash(ordered, Object.hashAll(items));

  @override
  String toString() => 'ArticleList(ordered: $ordered, $items)';
}

/// Un tramo de texto dentro de una línea.
class ArticleSpan {
  const ArticleSpan(this.text, {this.bold = false});
  final String text;
  final bool bold;

  @override
  bool operator ==(Object other) =>
      other is ArticleSpan && other.text == text && other.bold == bold;

  @override
  int get hashCode => Object.hash(text, bold);

  @override
  String toString() => 'ArticleSpan($text, bold: $bold)';
}

final RegExp _bullet = RegExp(r'^\s*[-*•]\s+');
final RegExp _number = RegExp(r'^\s*\d+[.)]\s+');
final RegExp _heading = RegExp(r'^\s*#{1,3}\s+');
final RegExp _bold = RegExp(r'\*\*(.+?)\*\*');

/// El cuerpo, en bloques (`bloques` en el panel).
List<ArticleBlock> articleBlocks(String body) {
  final out = <ArticleBlock>[];
  var paragraph = <String>[];
  bool? listOrdered;
  var listItems = <String>[];

  void close() {
    if (paragraph.isNotEmpty) out.add(ArticleParagraph(paragraph.join('\n')));
    if (listOrdered != null) {
      out.add(ArticleList(ordered: listOrdered!, items: listItems));
    }
    paragraph = <String>[];
    listOrdered = null;
    listItems = <String>[];
  }

  final normalized = body.replaceAll(RegExp(r'\r\n?'), '\n');
  for (final line in normalized.split('\n')) {
    if (line.trim().isEmpty) {
      close();
      continue;
    }
    if (_heading.hasMatch(line)) {
      close();
      out.add(ArticleHeading(line.replaceFirst(_heading, '').trim()));
      continue;
    }
    final bullet = _bullet.hasMatch(line);
    final number = _number.hasMatch(line);
    if (bullet || number) {
      if (paragraph.isNotEmpty ||
          (listOrdered != null && listOrdered != number)) {
        close();
      }
      listOrdered ??= number;
      listItems.add(line.replaceFirst(bullet ? _bullet : _number, '').trim());
      continue;
    }
    if (listOrdered != null) {
      // Una línea sin viñeta pegada a una lista sigue el ítem anterior.
      listItems[listItems.length - 1] += ' ${line.trim()}';
      continue;
    }
    paragraph.add(line.trim());
  }
  close();
  return out;
}

/// "Hola **mundo**" → [texto, negrita] (`enLinea` en el panel). Un `**` sin
/// cerrar queda como texto.
List<ArticleSpan> articleSpans(String text) {
  final out = <ArticleSpan>[];
  var from = 0;
  for (final m in _bold.allMatches(text)) {
    if (m.start > from) out.add(ArticleSpan(text.substring(from, m.start)));
    out.add(ArticleSpan(m.group(1)!, bold: true));
    from = m.end;
  }
  if (from < text.length) out.add(ArticleSpan(text.substring(from)));
  return out;
}

/// Las primeras palabras, sin marcas, para la lista (`extracto` en el panel).
/// Sale de los párrafos; si no hay ninguno —una receta que es solo listas—,
/// de las listas.
String articleExcerpt(String body, {int length = 180}) {
  final blocks = articleBlocks(body);
  final paragraphs = blocks.whereType<ArticleParagraph>().toList();
  final source = paragraphs.isNotEmpty
      ? paragraphs.map((p) => p.text)
      : blocks.whereType<ArticleList>().map((l) => l.items.join(' · '));
  final plain = source
      .join(' ')
      .replaceAll('**', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (plain.length <= length) return plain;
  final cut = plain.lastIndexOf(' ', length);
  return '${plain.substring(0, cut > length * 0.6 ? cut : length)}…';
}
