import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/formats.dart';
import '../../../core/utils/icons.dart';
import '../../../domain/models/alcohol.dart';
import '../../providers/app_providers.dart';
import '../system/surfaces.dart';

/// Lo que se tomó en el día, dibujado.
///
/// Va debajo del agua porque es la otra mitad de la misma pregunta —qué
/// tomaste— y porque comparte la forma de la tarjeta: título, el dato al
/// costado, el dibujo en el medio.
///
/// Tres decisiones que la separan del agua y conviene no deshacer:
///
/// - **No hay objetivo ni vasos vacíos.** El agua dibuja ocho siluetas porque
///   hay una referencia popular de ocho vasos; acá no hay ninguna meta que
///   alcanzar, y dibujar huecos diría "te faltan cuatro". Se dibuja solo lo que
///   se tomó.
/// - **Un ícono por consumo, no por unidad de bebida.** La UBE es continua
///   —3,7— y dibujar cuatro siluetas para 3,7 sería redondear a la vista. Con
///   un ícono por consumo, dos copas de vino y una cerveza se ven como dos
///   copas y una cerveza, que además dice más.
/// - **No hay color de alarma.** El número va en el gris de siempre. La
///   pantalla muestra distancias, no notas, igual que el agua y que el exceso
///   de calorías (RN-14).
class AlcoholCard extends ConsumerWidget {
  const AlcoholCard({required this.date, required this.onTap, super.key});

  final DateTime date;
  final VoidCallback onTap;

  /// Más siluetas que esto no entran prolijas en el ancho de un teléfono; de
  /// ahí en adelante se muestra el número, como hace el agua.
  static const int _maxDrawn = 10;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nm = context.nm;
    final repo = ref.watch(repositoryProvider);
    ref.watch(appRevisionProvider);

    final logs = repo.alcoholOn(date);
    final ube = logs.fold(0.0, (acc, a) => acc + a.standardDrinksTotal);
    final kcal = logs.fold(0, (acc, a) => acc + a.kcal);

    // Un ícono por unidad tomada: dos copas de vino son dos copas, no una
    // entrada. Se corta en `_maxDrawn` y el resto se cuenta.
    final siluetas = <AlcoholLog>[
      for (final log in logs)
        for (var i = 0; i < log.quantity.ceil(); i++) log,
    ];

    return NmCard(
      child: InkWell(
        onTap: onTap,
        borderRadius: NmRadius.brMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(PhosphorIcons.wine(), size: 18, color: nm.caution),
                const SizedBox(width: NmSpace.s2),
                Text(
                  'Alcohol',
                  style: NmTextStyles.from(NmType.h4, color: nm.text),
                ),
                const Spacer(),
                if (logs.isNotEmpty)
                  Text(
                    // El "≈" y no un número seco: la UBE sale de volumen y
                    // graduación de tabla, no de medir lo que había en el vaso.
                    '≈ ${Fmt.standardDrinks(ube)} · ${Fmt.estimatedKcal(kcal)}',
                    style: NmTextStyles.from(
                      NmType.bodySm,
                      color: nm.textMuted,
                    ).tnum,
                  ),
              ],
            ),

            const SizedBox(height: NmSpace.s4),

            if (logs.isEmpty)
              // El día sin alcohol no dice "0 tragos": un cero repetido todos
              // los días convierte en ruido diario algo que la mayoría de las
              // veces no pasó, y de paso lo pone en una escala que nadie pidió.
              Row(
                children: <Widget>[
                  Text(
                    'Sin registro',
                    style: NmTextStyles.from(
                      NmType.body,
                      color: nm.textMuted,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Anotar',
                    style: NmTextStyles.from(
                      NmType.bodySm,
                      color: nm.accentText,
                    ),
                  ),
                  Icon(
                    PhosphorIcons.caretRight(),
                    size: NmIconSize.sm,
                    color: nm.accentText,
                  ),
                ],
              )
            else
              Semantics(
                // Un lector de pantalla no puede con ocho siluetas sueltas: una
                // sola etiqueta con el dato entero, y los íconos ocultos. Mismo
                // criterio que los vasos del agua.
                label:
                    'Alcohol: ${Fmt.standardDrinks(ube)} aproximados, '
                    '${logs.map((l) => l.label).join(", ")}, '
                    'unas $kcal calorías',
                excludeSemantics: true,
                child: Wrap(
                  spacing: NmSpace.s2,
                  runSpacing: NmSpace.s2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    for (final log in siluetas.take(_maxDrawn))
                      Icon(
                        NmIcons.drink(log.type),
                        size: 26,
                        color: nm.caution,
                      ),
                    if (siluetas.length > _maxDrawn)
                      Text(
                        '+${siluetas.length - _maxDrawn}',
                        style: NmTextStyles.from(
                          NmType.body,
                          color: nm.textMuted,
                        ).tnum,
                      ),
                  ],
                ),
              ),

            if (logs.isNotEmpty) ...<Widget>[
              const SizedBox(height: NmSpace.s3),
              Text(
                // Dónde van esas calorías es la pregunta que sigue, y la
                // respuesta no es obvia: no están en el total de comidas.
                'Aparte de las comidas · tocá para editar',
                style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
