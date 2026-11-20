import 'package:material_ui/material_ui.dart';

import '../../../core/theme/motion.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/formats.dart';
import '../../../core/utils/phosphor_icons.dart';
import '../../../domain/enums/enums.dart';
import '../charts/calorie_ring.dart' show CountUpText;
import '../system/buttons.dart';

/// La pieza que hace visible la honestidad del producto (S-10). ★
///
/// Reglas obligatorias (RN-03): siempre el prefijo "≈", siempre una segunda
/// línea con el método, y nunca la palabra "quemaste" — se dice "gasto
/// estimado".
class ExerciseCaloriesEstimate extends StatelessWidget {
  const ExerciseCaloriesEstimate({
    required this.calories,
    required this.method,
    this.metValue,
    this.weightKg,
    this.durationMinutes,
    this.originalCalories,
    this.sourceLabel,
    this.unavailableReason,
    this.onOverride,
    this.onRestore,
    this.recalculatedHint,
    this.onUseRecalculated,
    this.onFixWeight,
    super.key,
  });

  final int calories;
  final EstimationMethod method;
  final double? metValue;
  final double? weightKg;
  final int? durationMinutes;
  final int? originalCalories;
  final String? sourceLabel;

  /// "Necesitamos tu peso para estimar" y su CTA.
  final String? unavailableReason;
  final VoidCallback? onOverride;
  final VoidCallback? onRestore;

  /// Si hay override activo, el recálculo no pisa el número: se ofrece.
  final int? recalculatedHint;
  final VoidCallback? onUseRecalculated;
  final VoidCallback? onFixWeight;

  String get _methodLine => switch (method) {
    EstimationMethod.met =>
      metValue == null
          ? 'Estimado por MET'
          : 'Estimado con MET ${Fmt.met(metValue!)}'
                '${weightKg == null ? '' : ' · ${weightKg!.round()} kg'}'
                '${durationMinutes == null ? '' : ' · $durationMinutes min'}',
    EstimationMethod.pace => 'Estimado por ritmo'
        '${durationMinutes == null ? '' : ' · $durationMinutes min'}',
    EstimationMethod.provider =>
      'Informado por ${sourceLabel ?? 'el dispositivo'}',
    EstimationMethod.userOverride =>
      originalCalories == null
          ? 'Corregido por vos'
          : 'Corregido por vos (cálculo original: '
                '${Fmt.integer(originalCalories!)} kcal)',
    EstimationMethod.metRecalculated =>
      'Recalculado por MET${metValue == null ? '' : ' ${Fmt.met(metValue!)}'}',
  };

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;

    if (unavailableReason != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(NmSpace.s4),
        decoration: BoxDecoration(
          color: nm.surfaceRaised,
          borderRadius: NmRadius.brMd,
          border: Border.all(color: nm.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              unavailableReason!,
              style: NmTextStyles.from(NmType.h4, color: nm.text),
            ),
            const SizedBox(height: NmSpace.s3),
            if (onFixWeight != null)
              NmButton.secondary(
                label: 'Registrar mi peso',
                onPressed: onFixWeight,
              ),
          ],
        ),
      );
    }

    return Semantics(
      label:
          'aproximadamente ${Fmt.integer(calories)} calorías, '
          '${_methodLine.toLowerCase()}',
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(NmSpace.s4),
          decoration: BoxDecoration(
            color: nm.surfaceRaised,
            borderRadius: NmRadius.brMd,
            border: Border.all(color: nm.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Gasto estimado',
                style: NmTextStyles.from(NmType.overline, color: nm.textMuted),
              ),
              const SizedBox(height: NmSpace.s2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  CountUpText(
                    value: calories,
                    prefix: '≈ ',
                    animate: context.motion.animatesCounters,
                    style: NmTextStyles.from(NmType.h1, color: nm.text).tnum,
                  ),
                  const SizedBox(width: NmSpace.s2),
                  Text(
                    'kcal',
                    style: NmTextStyles.from(NmType.h4, color: nm.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: NmSpace.s1),
              // El crossfade de la línea de método (21-motion §3.3).
              AnimatedSwitcher(
                duration: context.motion.fade(NmMotion.fast),
                child: Text(
                  _methodLine,
                  key: ValueKey<String>(_methodLine),
                  style: NmTextStyles.from(
                    NmType.caption,
                    color: nm.textMuted,
                  ),
                ),
              ),
              if (recalculatedHint != null && onUseRecalculated != null) ...<Widget>[
                const SizedBox(height: NmSpace.s3),
                InkWell(
                  onTap: onUseRecalculated,
                  child: Row(
                    children: <Widget>[
                      Icon(
                        PhosphorIcons.arrowsClockwise(),
                        size: NmIconSize.sm,
                        color: nm.caution,
                      ),
                      const SizedBox(width: NmSpace.s2),
                      Flexible(
                        child: Text(
                          'El cálculo daría ≈ ${Fmt.integer(recalculatedHint!)} '
                          'kcal · usar este valor',
                          style: NmTextStyles.from(
                            NmType.caption,
                            color: nm.caution,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: NmSpace.s3),
              Row(
                children: <Widget>[
                  if (onOverride != null)
                    NmButton.ghost(
                      label: 'Ingresar otro valor',
                      onPressed: onOverride,
                    ),
                  if (onRestore != null)
                    NmButton.ghost(
                      label: 'Restaurar el valor calculado',
                      onPressed: onRestore,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
