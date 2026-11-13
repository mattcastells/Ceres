import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../domain/models/care_feedback.dart';
import '../../providers/plan_providers.dart';
import '../system/surfaces.dart';
import 'care_target_block.dart';

/// "De tu nutricionista", en Inicio.
///
/// Aparece solo cuando hay algo que decir: la última devolución sin leer, el
/// objetivo recomendado y las indicaciones vigentes. Sin nada de eso no
/// ocupa lugar —Inicio es para el
/// día, y una tarjeta vacía que dice "no hay nada" es ruido todos los días—.
///
/// Mientras carga o si la consulta falla, tampoco: es información que suma,
/// no una que falte. Un error acá no puede ensuciar la pantalla principal.
class CareFeedbackHomeCard extends ConsumerWidget {
  const CareFeedbackHomeCard({super.key});

  /// Cuántas indicaciones se muestran antes del "y N más". Inicio no es la
  /// lista: es el aviso de que hay una.
  static const int maxIndications = 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox =
        ref.watch(careFeedbackProvider).valueOrNull ??
        CareInbox(const <CareFeedback>[]);
    if (!inbox.hasSomethingForHome) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: NmSpace.s6),
      child: CareFeedbackSummary(
        inbox: inbox,
        onTap: () => GoRouter.maybeOf(context)?.push(Routes.careFeedback),
      ),
    );
  }
}

/// El contenido de la tarjeta, separado del provider para poder dibujarlo
/// con cualquier bandeja.
class CareFeedbackSummary extends StatelessWidget {
  const CareFeedbackSummary({
    required this.inbox,
    this.onTap,
    super.key,
  });

  final CareInbox inbox;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final latest = inbox.latestUnreadFeedback;
    final target = inbox.target;
    final indications = inbox.indications;
    final unread = inbox.unreadCount;
    final shown = indications.take(CareFeedbackHomeCard.maxIndications);

    return Semantics(
      button: onTap != null,
      label: 'De tu nutricionista',
      child: NmCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  PhosphorIcons.stethoscope(),
                  size: NmIconSize.sm,
                  color: nm.textMuted,
                ),
                const SizedBox(width: NmSpace.s2),
                Expanded(
                  child: Text(
                    'DE TU NUTRICIONISTA',
                    style: NmTextStyles.from(
                      NmType.overline,
                      color: nm.textMuted,
                    ),
                  ),
                ),
                if (unread > 0)
                  NmTag(
                    label: unread == 1 ? '1 nueva' : '$unread nuevas',
                    variant: NmTagVariant.accent,
                  ),
                const SizedBox(width: NmSpace.s1),
                Icon(
                  PhosphorIcons.caretRight(),
                  size: NmIconSize.sm,
                  color: nm.textMuted,
                ),
              ],
            ),
            if (latest != null) ...<Widget>[
              const SizedBox(height: NmSpace.s3),
              Text(
                _byline(latest),
                style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
              ),
              const SizedBox(height: NmSpace.s1),
              Text(
                latest.body,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: NmTextStyles.from(NmType.body, color: nm.text),
              ),
            ],
            if (target != null) ...<Widget>[
              const SizedBox(height: NmSpace.s3),
              if (latest != null) ...<Widget>[
                const NmDivider(),
                const SizedBox(height: NmSpace.s3),
              ],
              CareTargetBlock(feedback: target, compact: true),
            ],
            if (indications.isNotEmpty) ...<Widget>[
              const SizedBox(height: NmSpace.s3),
              if (latest != null || target != null) ...<Widget>[
                const NmDivider(),
                const SizedBox(height: NmSpace.s3),
              ],
              Text(
                indications.length == 1
                    ? 'Indicación vigente'
                    : 'Indicaciones vigentes',
                style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
              ),
              const SizedBox(height: NmSpace.s2),
              for (final indication in shown)
                Padding(
                  padding: const EdgeInsets.only(bottom: NmSpace.s2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          PhosphorIcons.pushPin(),
                          size: NmIconSize.sm,
                          color: nm.isDark ? nm.accentText : nm.accent,
                        ),
                      ),
                      const SizedBox(width: NmSpace.s2),
                      Expanded(
                        child: Text(
                          indication.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: NmTextStyles.from(
                            NmType.bodySm,
                            color: nm.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (indications.length > shown.length)
                Text(
                  'y ${indications.length - shown.length} más',
                  style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Lic. Natalia Pérez · Ayer". Sin nombre, solo la fecha.
String _byline(CareFeedback f) {
  final day = friendlyDay(f.publishedAt);
  return f.authorName.trim().isEmpty ? day : '${f.authorName.trim()} · $day';
}

/// Lo mismo para la lista entera.
String careFeedbackByline(CareFeedback f) => _byline(f);
