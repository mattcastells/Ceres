import 'package:material_ui/material_ui.dart';

import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/services/article_text.dart';

/// El cuerpo de un artículo, con las reglas de `article_text.dart` —las mismas
/// que dibuja el panel—: títulos, párrafos, listas y negrita. Nada más: lo
/// que no entra en esas reglas se muestra como texto.
class ArticleBody extends StatelessWidget {
  const ArticleBody({required this.body, super.key});

  final String body;

  @override
  Widget build(BuildContext context) {
    final blocks = articleBlocks(body);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (var i = 0; i < blocks.length; i++)
          Padding(
            padding: EdgeInsets.only(
              top: i == 0
                  ? 0
                  : blocks[i] is ArticleHeading
                  ? NmSpace.s6
                  : NmSpace.s4,
            ),
            child: _Block(block: blocks[i]),
          ),
      ],
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.block});

  final ArticleBlock block;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final body = NmTextStyles.from(NmType.body, color: nm.text);
    return switch (block) {
      ArticleHeading(:final text) => Semantics(
        header: true,
        child: Text(text, style: NmTextStyles.from(NmType.h4, color: nm.text)),
      ),
      ArticleParagraph(:final text) => _Inline(text: text, style: body),
      ArticleList(:final ordered, :final items) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : NmSpace.s2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: NmSpace.s6,
                    child: Text(
                      ordered ? '${i + 1}.' : '•',
                      style: body.copyWith(color: nm.textMuted).tnum,
                    ),
                  ),
                  Expanded(
                    child: _Inline(text: items[i], style: body),
                  ),
                ],
              ),
            ),
        ],
      ),
    };
  }
}

/// Una línea con sus tramos en negrita.
class _Inline extends StatelessWidget {
  const _Inline({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      style: style,
      children: <InlineSpan>[
        for (final span in articleSpans(text))
          TextSpan(
            text: span.text,
            style: span.bold
                ? const TextStyle(fontWeight: FontWeight.w600)
                : null,
          ),
      ],
    ),
  );
}
