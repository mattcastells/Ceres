import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';

/// Meta de agua: cuántos vasos por día y de qué tamaño.
class WaterGoalScreen extends ConsumerWidget {
  const WaterGoalScreen({super.key});

  /// Los tamaños habituales de vaso y botella en Argentina.
  static const List<int> _sizes = <int>[200, 250, 330, 500, 750];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nm = context.nm;
    final profile = ref.watch(profileProvider);
    final repo = ref.watch(repositoryProvider);

    final total = profile.waterGoalGlasses * profile.glassSizeMl;

    return NmScreen(
      title: 'Meta de agua',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          const NmSectionHeader(title: 'Vasos por día'),
          NmCard(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Slider(
                    value: profile.waterGoalGlasses.toDouble(),
                    min: 1,
                    max: 20,
                    divisions: 19,
                    label: '${profile.waterGoalGlasses}',
                    onChanged: (v) => repo.setWaterGoal(
                      glasses: v.round(),
                      glassSizeMl: profile.glassSizeMl,
                    ),
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${profile.waterGoalGlasses}',
                    textAlign: TextAlign.end,
                    style: NmTextStyles.from(NmType.h3, color: nm.text),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: NmSpace.s6),
          const NmSectionHeader(title: 'Tamaño del vaso'),
          NmCard(
            child: Wrap(
              spacing: NmSpace.s2,
              runSpacing: NmSpace.s2,
              children: <Widget>[
                for (final size in _sizes)
                  NmChip(
                    label: '$size ml',
                    selected: profile.glassSizeMl == size,
                    onTap: () => repo.setWaterGoal(
                      glasses: profile.waterGoalGlasses,
                      glassSizeMl: size,
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: NmSpace.s6),
          NmCard(
            child: ValueRow(
              label: 'Equivale a',
              value: total >= 1000
                  ? '${(total / 1000).toStringAsFixed(1)} L por día'
                  : '$total ml por día',
              emphasis: true,
            ),
          ),

          const SizedBox(height: NmSpace.s6),
          const InfoNote(
            text:
                'Cambiar el tamaño del vaso no toca los días ya registrados.',
          ),
        ],
      ),
    );
  }
}
