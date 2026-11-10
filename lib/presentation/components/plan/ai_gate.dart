import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/error/app_error.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../providers/plan_providers.dart';
import '../system/buttons.dart';
import '../system/overlays.dart';

/// Si la IA se puede usar. Si no, ofrece los planes y devuelve `false`.
///
/// Va **antes** de arrancar, en cada puerta de entrada a la IA: sacar la foto
/// para que después el servidor diga que no sería hacerle perder el tiempo a
/// alguien. [onManual] es la salida sin IA de esa puerta en particular
/// —buscar el alimento, escribir el número— cuando la hay; sin ella el sheet
/// ofrece solo los planes.
bool ensureAiAllowed(
  BuildContext context,
  WidgetRef ref, {
  VoidCallback? onManual,
}) {
  if (ref.read(planProvider).includesAi) return true;
  showAiUpsellSheet(context, onManual: onManual);
  return false;
}

/// Si [error] es el 402 del plan, ofrece los planes y devuelve `true`.
///
/// Es la defensa de atrás: la app ya frena en los botones, pero el plan se
/// puede haber cambiado en otro lado —la profesional cortó el vínculo, la
/// demo volvió a Gratis desde otro teléfono— y el servidor es el que sabe. Un
/// 402 no es un error que mostrar en rojo: es la misma conversación que el
/// botón, que llegó tarde.
bool handlePlanRequired(
  BuildContext context,
  Object error, {
  VoidCallback? onManual,
}) {
  if (error is! AppError || error.code != ApiErrorCode.planRequired) {
    return false;
  }
  showAiUpsellSheet(context, onManual: onManual);
  // De paso se corrige el plan: si el servidor dijo que no, lo que creía la
  // app estaba viejo, y los demás botones tienen que dejar de ofrecerlo.
  final container = ProviderScope.containerOf(context, listen: false);
  container.read(planProvider.notifier).refresh().ignore();
  return true;
}

/// El sheet de "esto es parte de Premium".
///
/// Se abre sobre el navigator **raíz** y todo lo que hace después lo hace con
/// ese contexto: casi siempre se llama desde algo que se está cerrando —otro
/// sheet, una pantalla que vuelve— y el contexto de quien lo pidió puede no
/// existir ya cuando la persona toca un botón.
Future<void> showAiUpsellSheet(BuildContext context, {VoidCallback? onManual}) {
  final root = Navigator.of(context, rootNavigator: true).context;
  return showNmSheet<void>(
    context: root,
    builder: (sheetContext) => AiUpsellSheet(
      onPlans: () {
        Navigator.of(sheetContext).pop();
        GoRouter.maybeOf(root)?.push(Routes.plans);
      },
      onManual: onManual == null
          ? null
          : () {
              Navigator.of(sheetContext).pop();
              onManual();
            },
    ),
  );
}

class AiUpsellSheet extends StatelessWidget {
  const AiUpsellSheet({required this.onPlans, this.onManual, super.key});

  final VoidCallback onPlans;
  final VoidCallback? onManual;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return NmSheet(
      title: 'Esto usa IA',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                PhosphorIcons.sparkle(),
                size: NmIconSize.md,
                color: nm.isDark ? nm.accentText : nm.accent,
              ),
              const SizedBox(width: NmSpace.s3),
              Expanded(
                child: Text(
                  // El tono es el de un dato, no el de una puerta cerrada: lo
                  // que la persona venía haciendo sigue a mano, sin perder
                  // nada.
                  'Esto usa IA y es parte de Premium. Con el plan Gratis '
                  'podés seguir registrando todo a mano: buscar alimentos, '
                  'escanear códigos y armar tus comidas.',
                  style: NmTextStyles.from(NmType.body, color: nm.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: NmSpace.s6),
          NmButton(label: 'Ver planes', block: true, onPressed: onPlans),
          if (onManual != null) ...<Widget>[
            const SizedBox(height: NmSpace.s2),
            NmButton.secondary(
              label: 'Cargar a mano',
              block: true,
              onPressed: onManual,
            ),
          ],
        ],
      ),
    );
  }
}
