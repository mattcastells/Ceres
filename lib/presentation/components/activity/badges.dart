import 'package:material_ui/material_ui.dart';

import '../../../core/theme/motion.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/phosphor_icons.dart';
import '../../../domain/enums/enums.dart';
import '../system/surfaces.dart';

/// Estado de sincronización. Iconografía + texto: **nunca** solo color.
/// En `error` es tappable para reintentar.
class SyncStatusBadge extends StatelessWidget {
  const SyncStatusBadge({
    required this.status,
    this.compact = true,
    this.onRetry,
    super.key,
  });

  final SyncStatus status;
  final bool compact;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    if (status == SyncStatus.synced && compact) {
      return const SizedBox.shrink();
    }

    final (IconData icon, Color color, String label) = switch (status) {
      SyncStatus.synced => (
        PhosphorIcons.checkCircle(),
        nm.success,
        'Sincronizado',
      ),
      SyncStatus.pending => (
        PhosphorIcons.cloudSlash(),
        nm.textMuted,
        'Pendiente',
      ),
      SyncStatus.syncing => (
        PhosphorIcons.arrowsClockwise(),
        nm.textMuted,
        'Sincronizando',
      ),
      SyncStatus.error => (
        PhosphorIcons.warningCircle(),
        nm.danger,
        'Sin sincronizar',
      ),
      SyncStatus.needsReview => (
        PhosphorIcons.warning(),
        nm.caution,
        'Revisar',
      ),
    };

    // El pulso de escala al pasar a sincronizado (21-motion §5).
    final badge = TweenAnimationBuilder<double>(
      key: ValueKey<SyncStatus>(status),
      tween: Tween<double>(begin: 0.92, end: 1),
      duration: context.motion.move(NmMotion.base),
      curve: NmMotion.ease,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: NmSpace.s1),
          Text(
            label,
            style: NmTextStyles.from(NmType.micro, color: color),
          ),
        ],
      ),
    );

    if (status == SyncStatus.error && onRetry != null) {
      return GestureDetector(onTap: onRetry, child: badge);
    }
    return badge;
  }
}

/// Origen del dato: "Manual" · "Importado · Health Connect" · "Estimado por IA".
class DataOriginBadge extends StatelessWidget {
  const DataOriginBadge({required this.origin, this.sourceLabel, super.key});

  final DataOrigin origin;
  final String? sourceLabel;

  @override
  Widget build(BuildContext context) {
    final label = switch (origin) {
      DataOrigin.manual => 'Manual',
      DataOrigin.imported =>
        'Importado${sourceLabel == null ? '' : ' · $sourceLabel'}',
      DataOrigin.ai => 'Estimado por IA',
    };
    return NmTag(
      label: label,
      variant: switch (origin) {
        DataOrigin.manual => NmTagVariant.outline,
        DataOrigin.imported => NmTagVariant.neutral,
        DataOrigin.ai => NmTagVariant.caution,
      },
    );
  }
}

/// Confianza del análisis de IA. Incluye texto, no solo color (S-20).
class ConfidenceBadge extends StatelessWidget {
  const ConfidenceBadge({required this.value, super.key});

  final double value;

  @override
  Widget build(BuildContext context) {
    final (String label, NmTagVariant variant) = value >= 0.75
        ? ('Confianza alta', NmTagVariant.success)
        : value >= 0.5
        ? ('Confianza media', NmTagVariant.neutral)
        : ('Confianza baja', NmTagVariant.caution);
    return NmTag(label: label, variant: variant);
  }
}
