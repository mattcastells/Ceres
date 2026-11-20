import 'package:material_ui/material_ui.dart';

import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/formats.dart';
import '../../../core/utils/phosphor_icons.dart';
import '../../../domain/models/alcohol.dart';
import '../../../domain/models/day_marker.dart';

/// El contexto del día, en una línea.
///
/// **Aparece solo si hay algo que decir.** No es una tarjeta más del día: es lo
/// que explica al resto, y una tarjeta permanente que dice "0 tragos · sin
/// enfermedad" convierte en ruido diario lo que tiene que saltar el día que
/// pasó algo.
///
/// Ni la enfermedad ni el alcohol cambian ningún número de la pantalla. Están
/// para que un día flojo se pueda leer, no para justificarlo: la app no opina
/// sobre una semana que no vio. Ver `docs/contexto-diario.md`.
class DayContextStrip extends StatelessWidget {
  const DayContextStrip({
    super.key,
    this.sick,
    this.alcohol,
    this.onTapSick,
    this.onTapAlcohol,
  });

  final DayMarker? sick;
  final AlcoholDay? alcohol;
  final VoidCallback? onTapSick;
  final VoidCallback? onTapAlcohol;

  bool get _isEmpty => sick == null && (alcohol == null || alcohol!.isEmpty);

  @override
  Widget build(BuildContext context) {
    if (_isEmpty) return const SizedBox.shrink();
    final nm = context.nm;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (sick != null)
          _Fila(
            icon: PhosphorIcons.thermometer(),
            title: <String>[
              'Día de enfermedad',
              if (sick!.severity != null) sick!.severity!.label.toLowerCase(),
            ].join(' · '),
            detail: sick!.note,
            onTap: onTapSick,
          ),
        if (alcohol != null && !alcohol!.isEmpty)
          _Fila(
            icon: PhosphorIcons.wine(),
            title: Fmt.standardDrinks(alcohol!.standardDrinks),
            // Las calorías del alcohol se muestran acá y **no** se suman a las
            // comidas: sumarlas ahí escondería de dónde salieron, que es justo
            // el dato que se busca cuando el peso no baja.
            detail: '${Fmt.estimatedKcal(alcohol!.kcal)} · aparte de las '
                'comidas',
            onTap: onTapAlcohol,
          ),
        const SizedBox(height: NmSpace.s2),
        Text(
          'Contexto: no cambia tu objetivo ni tus promedios.',
          style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
        ),
      ],
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.icon,
    required this.title,
    this.detail,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(NmRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: NmSpace.s2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: NmIconSize.md, color: nm.textMuted),
            const SizedBox(width: NmSpace.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: NmTextStyles.from(NmType.body, color: nm.text),
                  ),
                  if (detail != null && detail!.isNotEmpty)
                    Text(
                      detail!,
                      style: NmTextStyles.from(
                        NmType.caption,
                        color: nm.textMuted,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
