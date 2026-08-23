import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/analysis_stage.dart';

/// Barra de avance del análisis por foto.
///
/// El handoff (21-motion §4.4) prohíbe el progreso falso, y con razón: una
/// barra que avanza a ritmo constante hacia el 100 % promete un final que
/// nadie puede prometer. Pero tampoco sirve una animación decorativa que no
/// distingue "va bien" de "se colgó".
///
/// El acuerdo que respeta las dos cosas:
///
/// - **Los pasos son reales.** Preparar, subir y analizar son observables: la
///   app sabe con exactitud cuándo empieza y termina cada uno, y la barra
///   salta de verdad al cambiar de paso.
/// - **Dentro del último paso se estima**, porque cuánto tarda el modelo no lo
///   decide Ceres. Ahí la barra avanza contra la mediana **medida** (12,3 s)
///   y se **frena asintóticamente** en 92 %: nunca completa sola.
/// - **El 100 % solo llega con la respuesta.** Si el modelo se demora, la
///   barra desacelera y se queda esperando, que es exactamente lo que pasa.
///
/// Una barra que se clava en 99 % es la peor versión de esto. Acá la
/// desaceleración se ve, y el `≈` delante del porcentaje dice que es una
/// estimación sin necesidad de una aclaración aparte. La había —"el tiempo
/// restante es una estimación: cuánto tarda el modelo no lo decidimos
/// nosotros"— y se sacó: era cierta, pero le ponía el foco al reloj, que es
/// exactamente lo que una pantalla de espera no necesita.
class AnalysisProgress extends StatelessWidget {
  const AnalysisProgress({
    required this.stage,
    required this.elapsedInStage,
    super.key,
  });

  final AnalysisStage stage;

  /// Cuánto lleva el paso actual. Solo se usa para estimar dentro de
  /// `analyzing`; los otros dos son tan cortos que no hace falta.
  final Duration elapsedInStage;

  /// Techo del tramo estimado. Deja aire visible para el salto final.
  static const double _ceiling = 0.92;

  double get value {
    final base = stage.start;
    if (stage != AnalysisStage.analyzing) {
      // Preparar y subir son rápidos y discretos: se muestran completos al
      // pasar al siguiente, sin inventar avance intermedio.
      return base;
    }

    // Curva que se acerca al techo sin tocarlo: al llegar a la mediana va por
    // ~63 % del tramo, y de ahí en más cada segundo suma menos. Es la forma
    // honesta de decir "esto debería estar por salir" sin prometerlo.
    final t = elapsedInStage.inMilliseconds /
        AnalysisTiming.typical.inMilliseconds;
    final avance = 1 - math.exp(-t);
    return base + stage.weight * avance * _ceiling;
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final pct = (value * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          value: '$pct por ciento',
          child: ClipRRect(
            borderRadius: NmRadius.brSm,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: value),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                backgroundColor: nm.surfaceRaised,
                valueColor: AlwaysStoppedAnimation<Color>(nm.accent),
              ),
            ),
          ),
        ),
        const SizedBox(height: NmSpace.s3),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                stage.label,
                style: NmTextStyles.from(NmType.body, color: nm.text),
              ),
            ),
            Text(
              // Los pasos medibles muestran su porcentaje; el tramo estimado
              // lo dice con el "≈" que el producto usa en todo lo estimado.
              stage == AnalysisStage.analyzing ? '≈ $pct %' : '$pct %',
              style: NmTextStyles.from(
                NmType.caption,
                color: nm.textMuted,
              ).tnum,
            ),
          ],
        ),
      ],
    );
  }
}
