import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../providers/plan_providers.dart';
import '../system/surfaces.dart';

/// Rubros que **nunca** se anuncian en Ceres, pague lo que pague quien sea.
///
/// Una app donde la gente registra lo que come no puede venderle a esa misma
/// gente pastillas para adelgazar, "detox" ni alcohol: el anuncio estaría
/// trabajando en contra del producto y de la persona.
enum BlockedAdCategory { dietPills, detox, alcohol, supplementsWithClaims }

/// Rubros permitidos. Comercios del barrio, deporte, cultura: nada que opine
/// sobre el cuerpo de nadie.
enum AdCategory { groceries, sports, books, services }

class SimulatedAd {
  const SimulatedAd({
    required this.brand,
    required this.line,
    required this.category,
    required this.icon,
  });

  final String brand;
  final String line;
  final AdCategory category;
  final IconData icon;
}

/// Los anuncios de la demo. **Inventados**: ninguna marca existe y ninguno
/// lleva a ningún lado.
///
/// La regla, que vale para cuando haya anuncios de verdad:
///
/// - **Contextuales, nunca dirigidos con datos de salud.** Lo que se elige
///   depende de la pantalla en la que aparece, jamás de lo que la persona
///   comió, pesó o se propuso. Ningún dato del registro sale del teléfono
///   hacia un anunciante, ni para elegir el anuncio ni para medirlo.
/// - **Rubros bloqueados** ([BlockedAdCategory]): pastillas para adelgazar,
///   detox, alcohol, suplementos con promesas. Lo que no está en
///   [AdCategory] no entra.
/// - **Solo en pantallas neutras**: historial, buscador de alimentos y
///   progreso. Nunca en Inicio, ni en el balance del día, ni en el peso, ni
///   en el formulario de una comida: un anuncio al lado de "te quedan 300
///   kcal" se lee como un comentario sobre eso.
/// - **Solo en el plan gratis**, y siempre con la salida a la vista.
const List<SimulatedAd> simulatedAds = <SimulatedAd>[
  SimulatedAd(
    brand: 'Verdulería Don Tito',
    line: 'Envío gratis en el barrio los martes y jueves.',
    category: AdCategory.groceries,
    icon: PhosphorIconsRegular.basket,
  ),
  SimulatedAd(
    brand: 'Club Atlético del Barrio',
    line: 'Clases de natación para todas las edades. Primera clase sin cargo.',
    category: AdCategory.sports,
    icon: PhosphorIconsRegular.swimmingPool,
  ),
  SimulatedAd(
    brand: 'Librería La Hoja',
    line: 'Novedades de la semana y club de lectura los sábados.',
    category: AdCategory.books,
    icon: PhosphorIconsRegular.bookOpen,
  ),
  SimulatedAd(
    brand: 'Bicicletería La Rueda',
    line: 'Service completo y préstamo de bici mientras esperás.',
    category: AdCategory.services,
    icon: PhosphorIconsRegular.bicycle,
  ),
  SimulatedAd(
    brand: 'Feria de Productores de Villa Sol',
    line: 'Todos los domingos en la plaza, de 9 a 14.',
    category: AdCategory.groceries,
    icon: PhosphorIconsRegular.storefront,
  ),
];

/// Un anuncio discreto, solo para el plan gratis. Con cualquier otro plan no
/// ocupa lugar.
///
/// Rota: cada vez que una pantalla lo monta muestra el siguiente de la lista.
/// Rota por turno y no por algo de la persona, por la regla de arriba.
class AdBanner extends ConsumerStatefulWidget {
  const AdBanner({this.padding = EdgeInsets.zero, super.key});

  /// El aire alrededor va adentro: sin anuncio no queda un hueco.
  final EdgeInsetsGeometry padding;

  @override
  ConsumerState<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends ConsumerState<AdBanner> {
  static int _turn = 0;
  late final SimulatedAd _ad = simulatedAds[(_turn++) % simulatedAds.length];

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(planProvider).showsAds) return const SizedBox.shrink();
    final nm = context.nm;

    return Padding(
      padding: widget.padding,
      child: Semantics(
        container: true,
        label: 'Anuncio',
        child: NmCard(
          padding: const EdgeInsets.all(NmSpace.s3),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: nm.surfaceRaised,
                  borderRadius: NmRadius.brMd,
                ),
                child: Icon(_ad.icon, size: NmIconSize.md, color: nm.textMuted),
              ),
              const SizedBox(width: NmSpace.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const NmTag(
                          label: 'Anuncio',
                          variant: NmTagVariant.outline,
                        ),
                        const SizedBox(width: NmSpace.s2),
                        Flexible(
                          child: Text(
                            _ad.brand,
                            overflow: TextOverflow.ellipsis,
                            style: NmTextStyles.from(
                              NmType.bodySm,
                              color: nm.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: NmSpace.s1),
                    Text(
                      _ad.line,
                      style: NmTextStyles.from(
                        NmType.caption,
                        color: nm.textMuted,
                      ),
                    ),
                    GestureDetector(
                      onTap: () =>
                          GoRouter.maybeOf(context)?.push(Routes.plans),
                      child: Padding(
                        padding: const EdgeInsets.only(top: NmSpace.s1),
                        child: Text(
                          'Quitar anuncios',
                          style: NmTextStyles.from(
                            NmType.caption,
                            color: nm.isDark ? nm.accentText : nm.accent,
                          ).copyWith(decoration: TextDecoration.underline),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
