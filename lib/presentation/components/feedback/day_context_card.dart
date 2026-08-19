import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/motion.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/day_marker.dart';
import '../../providers/app_providers.dart';
import '../system/surfaces.dart';

/// Cómo estuvo el día: enfermedad y descanso, a un toque.
///
/// Va **abajo de todo** a propósito. No es un registro más —no suma calorías,
/// no mueve el objetivo, no entra en ningún promedio— sino lo que explica al
/// resto, y arriba competiría por atención con los números que sí son del día.
///
/// Se muestra **siempre**, aunque no haya nada marcado, y esa es la diferencia
/// con la tarjeta del alcohol: acá no hay una hoja de carga a la que llegar
/// desde el "+", así que si la fila no está el día que uno se enferma, la
/// función no existe. Apagado es un botón, no un cero.
///
/// Nada de esto pinta de rojo ni de verde. Un día de enfermedad no es una
/// falta, y un día de descanso no es un premio: los dos son contexto, y el
/// único acento es el ámbar con el que la app marca todo lo que hay que mirar
/// antes de leer el resto.
class DayContextCard extends ConsumerWidget {
  const DayContextCard({
    required this.date,
    required this.onTapSick,
    required this.onTapRest,
    super.key,
  });

  final DateTime date;
  final VoidCallback onTapSick;
  final VoidCallback onTapRest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);
    ref.watch(appRevisionProvider);

    final enfermo = repo.markerOn(date, DayMarkerKind.sick);
    final descanso = repo.markerOn(date, DayMarkerKind.rest);

    return NmCard(
      child: Column(
        children: <Widget>[
          _Fila(
            icon: PhosphorIcons.thermometer(),
            label: 'Día de enfermedad',
            // La nota es lo que hace útil la marca dos semanas después: sin
            // ella queda "estuviste enfermo" y con ella queda de qué.
            detail: enfermo == null
                ? 'No lo marcaste'
                : <String>[
                    if (enfermo.severity != null) enfermo.severity!.label,
                    if (enfermo.note?.trim().isNotEmpty ?? false)
                      enfermo.note!.trim(),
                  ].join(' · '),
            marcado: enfermo != null,
            onTap: onTapSick,
          ),
          const NmDivider(),
          _Fila(
            icon: PhosphorIcons.couch(),
            label: 'Descanso planificado',
            detail: descanso == null
                ? 'No lo marcaste'
                : 'No cuenta como día sin actividad',
            marcado: descanso != null,
            onTap: onTapRest,
          ),
        ],
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.icon,
    required this.label,
    required this.detail,
    required this.marcado,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String detail;
  final bool marcado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final color = marcado ? nm.caution : nm.textMuted;

    return Semantics(
      button: true,
      // El estado va en la etiqueta y no solo en el color: "marcado" y "no
      // marcado" tienen que llegar igual a un lector de pantalla.
      label: '$label, ${marcado ? "marcado" : "sin marcar"}. $detail',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: NmRadius.brMd,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: NmSpace.s3),
          child: Row(
            children: <Widget>[
              // El relleno y no solo el color distingue lo marcado de lo que
              // no: la diferencia no puede depender del tono
              // (15-accessibility §3).
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: marcado ? 1 : 0),
                duration: context.motion.fade(NmMotion.base),
                curve: NmMotion.ease,
                builder: (context, t, _) => Container(
                  height: 36,
                  width: 36,
                  decoration: BoxDecoration(
                    color: Color.lerp(nm.surfaceRaised, nm.cautionFill, t),
                    borderRadius: NmRadius.brMd,
                  ),
                  child: Icon(icon, size: 20, color: color),
                ),
              ),
              const SizedBox(width: NmSpace.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: NmTextStyles.from(
                        NmType.body,
                        color: marcado ? nm.text : nm.textMuted,
                      ),
                    ),
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: NmTextStyles.from(
                        NmType.caption,
                        color: nm.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                marcado
                    ? PhosphorIcons.checkCircle(PhosphorIconsStyle.fill)
                    : PhosphorIcons.plusCircle(),
                size: NmIconSize.md,
                color: color,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
