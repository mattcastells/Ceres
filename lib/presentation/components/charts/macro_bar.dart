import 'package:material_ui/material_ui.dart';

import '../../../core/theme/motion.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/formats.dart';
import '../../../domain/models/summaries.dart';

/// Proteínas / carbohidratos / grasas consumidos contra su objetivo.
///
/// Al montar entran de 0 a su valor con un stagger de 40 ms entre las tres
/// (21-motion §3.4).
class MacroBar extends StatelessWidget {
  const MacroBar({required this.macros, super.key});

  final MacroSet macros;

  @override
  Widget build(BuildContext context) {
    // Los tres colores salen de la paleta de datos (§1.4), no de los roles
    // semánticos: `caution` está reservado para lo estimado o incierto.
    final charts = context.nm.charts;
    final items = <(String, String, Color)>[
      ('Proteínas', 'protein', charts.intake),
      ('Carbohidratos', 'carbs', charts.running),
      ('Grasas', 'fat', charts.sports),
    ];

    return Column(
      children: <Widget>[
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: EdgeInsets.only(
              bottom: i == items.length - 1 ? 0 : NmSpace.s4,
            ),
            child: _MacroRow(
              label: items[i].$1,
              progress: switch (items[i].$2) {
                'protein' => macros.protein,
                'carbs' => macros.carbs,
                _ => macros.fat,
              },
              color: items[i].$3,
              index: i,
            ),
          ),
      ],
    );
  }
}

class _MacroRow extends StatelessWidget {
  const _MacroRow({
    required this.label,
    required this.progress,
    required this.color,
    required this.index,
  });

  final String label;
  final MacroProgress progress;
  final Color color;
  final int index;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final motion = context.motion;
    final fraction = progress.fraction.clamp(0.0, 1.0);

    return Semantics(
      label:
          '$label: ${Fmt.integer(progress.current)} de '
          '${Fmt.integer(progress.target)} gramos',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    label,
                    style: NmTextStyles.from(NmType.caption, color: nm.text),
                  ),
                ),
                Text(
                  '${Fmt.integer(progress.current)} / '
                  '${Fmt.grams(progress.target)}',
                  style: NmTextStyles.from(
                    NmType.caption,
                    color: nm.textMuted,
                  ).tnum,
                ),
              ],
            ),
            const SizedBox(height: NmSpace.s2),
            ClipRRect(
              borderRadius: BorderRadius.circular(NmRadius.full),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: fraction),
                duration:
                    motion.move(NmMotion.slow) + motion.staggerFor(index),
                curve: NmMotion.ease,
                builder: (context, value, _) => Stack(
                  children: <Widget>[
                    Container(height: 6, color: nm.divider),
                    FractionallySizedBox(
                      widthFactor: value,
                      child: Container(height: 6, color: color),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
