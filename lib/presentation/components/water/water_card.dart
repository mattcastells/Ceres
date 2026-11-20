import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/motion.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/formats.dart';
import '../../../core/utils/phosphor_icons.dart';
import '../../../domain/models/water.dart';
import '../../providers/app_providers.dart';
import '../system/surfaces.dart';

/// Vasos de agua del día, con los vasos dibujados y los botones de sumar y
/// restar.
///
/// No hay barra de progreso ni porcentaje: la meta de 8 vasos es una referencia
/// popular, no una regla médica, así que pasarse no es un logro y no llegar no
/// es una falla. Mismo criterio que el resto de la app con el exceso de
/// calorías (D-17, RN-14) — se muestra el dato, no un juicio.
class WaterCard extends ConsumerWidget {
  const WaterCard({required this.date, super.key});

  final DateTime date;

  /// Más de esto no entra prolijo en el ancho de un teléfono; a partir de ahí
  /// se muestra el número en vez de dibujar cada vaso.
  static const int _maxDrawn = 12;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nm = context.nm;
    final repo = ref.watch(repositoryProvider);
    final profile = ref.watch(profileProvider);
    ref.watch(appRevisionProvider);

    final glasses = repo.glassesOn(date);
    final goal = profile.waterGoalGlasses;
    final ml = glasses * profile.glassSizeMl;

    return NmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(PhosphorIcons.drop(), size: 18, color: nm.info),
              const SizedBox(width: NmSpace.s2),
              Text('Agua', style: NmTextStyles.from(NmType.h4, color: nm.text)),
              const Spacer(),
              Text(
                '$glasses de $goal · ${_formatMl(ml)}',
                style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
              ),
            ],
          ),
          const SizedBox(height: NmSpace.s4),

          Semantics(
            // Un lector de pantalla no puede con 8 íconos sueltos: se expone
            // una sola etiqueta con el dato completo y se ocultan los vasos.
            label: 'Agua: $glasses de $goal vasos, ${_formatMl(ml)}',
            excludeSemantics: true,
            child: glasses > _maxDrawn
                ? Text(
                    '$glasses vasos',
                    style: NmTextStyles.from(NmType.h2, color: nm.info),
                  )
                : Wrap(
                    spacing: NmSpace.s2,
                    runSpacing: NmSpace.s2,
                    children: <Widget>[
                      for (var i = 0; i < (goal > glasses ? goal : glasses); i++)
                        _Glass(filled: i < glasses),
                    ],
                  ),
          ),

          const SizedBox(height: NmSpace.s4),
          Row(
            children: <Widget>[
              _StepButton(
                icon: PhosphorIcons.minus(),
                tooltip: 'Quitar un vaso',
                enabled: glasses > 0,
                onPressed: () => repo.addGlasses(date, -1),
              ),
              const SizedBox(width: NmSpace.s3),
              _StepButton(
                icon: PhosphorIcons.plus(),
                tooltip: 'Sumar un vaso',
                enabled: glasses < WaterLog.maxGlasses,
                onPressed: () => repo.addGlasses(date, 1),
              ),
              const Spacer(),
              Text(
                'Vaso de ${profile.glassSizeMl} ml',
                style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Con `Fmt` y no `toStringAsFixed`: ese escribía "1.5 L" con el punto del
  // inglés, en una pantalla donde todo el resto va con coma.
  static String _formatMl(int ml) =>
      ml >= 1000 ? '${Fmt.decimal1(ml / 1000)} L' : '$ml ml';
}

class _Glass extends StatelessWidget {
  const _Glass({required this.filled});

  final bool filled;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: filled ? 1 : 0),
      duration: context.motion.fade(NmMotion.base),
      curve: NmMotion.ease,
      builder: (context, t, child) => Icon(
        // El vaso vacío es el contorno y el lleno el relleno: la diferencia no
        // depende solo del color (15-accessibility §3).
        t > 0.5 ? PhosphorIcons.drop(PhosphorIconsStyle.fill) : PhosphorIcons.drop(),
        size: 26,
        color: Color.lerp(nm.textMuted, nm.info, t),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: Material(
          color: enabled ? nm.accentFill : nm.surfaceRaised,
          borderRadius: NmRadius.brMd,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: NmRadius.brMd,
            child: SizedBox(
              // 48×48 es el mínimo táctil del handoff (15-accessibility §5).
              height: NmLayout.minTouchTarget,
              width: NmLayout.minTouchTarget + NmSpace.s4,
              child: Icon(
                icon,
                size: 20,
                color: enabled ? nm.accentOnFill : nm.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
