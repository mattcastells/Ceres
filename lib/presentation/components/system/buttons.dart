import 'package:flutter/material.dart';

import '../../../core/theme/motion.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';

enum NmButtonVariant { primary, secondary, ghost, danger }

/// Botón del sistema. **El primario es contorneado, nunca relleno** (Nocturne).
///
/// Con `loading` el texto se reemplaza por un spinner y el botón conserva su
/// ancho: nada de saltos de layout (21-motion §4.3).
class NmButton extends StatelessWidget {
  const NmButton({
    required this.label,
    required this.onPressed,
    this.variant = NmButtonVariant.primary,
    this.block = false,
    this.loading = false,
    this.icon,
    this.semanticLabel,
    super.key,
  });

  const NmButton.secondary({
    required this.label,
    required this.onPressed,
    this.block = false,
    this.loading = false,
    this.icon,
    this.semanticLabel,
    super.key,
  }) : variant = NmButtonVariant.secondary;

  const NmButton.ghost({
    required this.label,
    required this.onPressed,
    this.block = false,
    this.loading = false,
    this.icon,
    this.semanticLabel,
    super.key,
  }) : variant = NmButtonVariant.ghost;

  final String label;
  final VoidCallback? onPressed;
  final NmButtonVariant variant;
  final bool block;
  final bool loading;
  final IconData? icon;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final disabled = onPressed == null || loading;

    final (Color fg, Color border) = switch (variant) {
      NmButtonVariant.primary => (
        nm.isDark ? nm.accentText : nm.accent,
        nm.accent,
      ),
      NmButtonVariant.secondary => (nm.text, nm.divider),
      NmButtonVariant.ghost => (
        nm.isDark ? nm.accentText : nm.accent,
        Colors.transparent,
      ),
      NmButtonVariant.danger => (nm.danger, nm.danger),
    };

    final child = loading
        ? SizedBox(
            height: NmIconSize.sm,
            width: NmIconSize.sm,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        : Row(
            mainAxisSize: block ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: NmIconSize.md),
                const SizedBox(width: NmSpace.s2),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: NmTextStyles.from(NmType.bodySm).copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          );

    return Semantics(
      button: true,
      enabled: !disabled,
      label: semanticLabel ?? (loading ? 'Guardando' : label),
      child: ExcludeSemantics(
        child: Opacity(
          opacity: onPressed == null ? NmStateToken.disabledOpacity : 1,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: disabled ? null : onPressed,
              borderRadius: NmRadius.brMd,
              splashColor: nm.pressedAccent,
              highlightColor: nm.hoverAccent,
              child: AnimatedContainer(
                duration: context.motion.fade(NmMotion.instant),
                curve: NmMotion.ease,
                width: block ? double.infinity : null,
                constraints: const BoxConstraints(
                  minHeight: NmLayout.minTouchTarget,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: NmSpace.s6,
                  vertical: NmSpace.s3,
                ),
                decoration: BoxDecoration(
                  borderRadius: NmRadius.brMd,
                  border: Border.all(
                    color: border,
                    width: variant == NmButtonVariant.ghost ? 0 : 1,
                  ),
                ),
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: fg),
                  child: IconTheme.merge(
                    data: IconThemeData(color: fg),
                    child: Center(child: child),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Botón de ícono con área táctil de 48×48 garantizada.
class NmIconButton extends StatelessWidget {
  const NmIconButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.active = false,
    this.size = NmIconSize.lg,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkResponse(
          onTap: onPressed,
          radius: NmLayout.minTouchTarget / 2,
          child: Container(
            height: NmLayout.minTouchTarget,
            width: NmLayout.minTouchTarget,
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: size,
              color: active ? nm.accent : nm.text,
            ),
          ),
        ),
      ),
    );
  }
}

/// FAB central: 56×56, ícono `Plus` que rota 45° hasta la × al abrir el sheet
/// (21-motion §5).
class NmFab extends StatelessWidget {
  const NmFab({required this.onPressed, this.expanded = false, super.key});

  final VoidCallback onPressed;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return Semantics(
      button: true,
      label: 'Agregar registro',
      child: SizedBox(
        height: NmLayout.fabSize,
        width: NmLayout.fabSize,
        child: Material(
          color: nm.accent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: AnimatedRotation(
              turns: expanded ? 0.125 : 0,
              duration: context.motion.move(NmMotion.base),
              curve: NmMotion.ease,
              child: Icon(
                Icons.add,
                size: NmIconSize.xl,
                color: nm.onAccent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
