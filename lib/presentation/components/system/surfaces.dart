import 'package:material_ui/material_ui.dart';

import '../../../core/theme/motion.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/phosphor_icons.dart';

enum NmElevationLevel { sm, md, lg }

/// Tarjeta del sistema: `surface` + radio `md` + borde-elevación.
class NmCard extends StatelessWidget {
  const NmCard({
    required this.child,
    this.padding = const EdgeInsets.all(NmSpace.s4),
    this.elevation = NmElevationLevel.sm,
    this.onTap,
    this.raised = false,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final NmElevationLevel elevation;
  final VoidCallback? onTap;

  /// Superficie sobre superficie (`surfaceRaised`).
  final bool raised;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final shadows = switch (elevation) {
      NmElevationLevel.sm => nm.shadowSm,
      NmElevationLevel.md => nm.shadowMd,
      NmElevationLevel.lg => nm.shadowLg,
    };

    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: raised ? nm.surfaceRaised : nm.surface,
        borderRadius: NmRadius.brMd,
        boxShadow: shadows,
      ),
      child: child,
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: NmRadius.brMd,
        splashColor: nm.hoverAccent,
        highlightColor: nm.hoverNeutral,
        child: content,
      ),
    );
  }
}

enum NmTagVariant {
  accent,
  accent2,
  neutral,
  outline,
  caution,
  success,
  danger,
}

/// Etiqueta compacta. Nunca depende solo del color: siempre lleva texto.
class NmTag extends StatelessWidget {
  const NmTag({
    required this.label,
    this.variant = NmTagVariant.neutral,
    this.icon,
    super.key,
  });

  final String label;
  final NmTagVariant variant;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final (Color bg, Color fg) = switch (variant) {
      NmTagVariant.accent => (nm.accentFill, nm.accentOnFill),
      NmTagVariant.accent2 => (
        nm.isDark ? nm.accent2Ramp.c800 : nm.accent2Ramp.c100,
        nm.isDark ? nm.accent2Ramp.c200 : nm.accent2Ramp.c700,
      ),
      NmTagVariant.neutral => (
        nm.isDark ? nm.neutralRamp.c800 : nm.neutralRamp.c200,
        nm.text,
      ),
      NmTagVariant.outline => (Colors.transparent, nm.textMuted),
      NmTagVariant.caution => (
        nm.caution.withValues(alpha: nm.isDark ? 0.18 : 0.14),
        nm.caution,
      ),
      NmTagVariant.success => (
        nm.success.withValues(alpha: nm.isDark ? 0.18 : 0.14),
        nm.success,
      ),
      NmTagVariant.danger => (
        nm.danger.withValues(alpha: nm.isDark ? 0.18 : 0.14),
        nm.danger,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NmSpace.s3,
        vertical: NmSpace.s1,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(NmRadius.full),
        border: variant == NmTagVariant.outline
            ? Border.all(color: nm.divider)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: NmSpace.s1),
          ],
          Text(label, style: NmTextStyles.from(NmType.micro, color: fg)),
        ],
      ),
    );
  }
}

/// Kicker de sección: overline en mayúsculas + acción opcional a la derecha.
class NmSectionHeader extends StatelessWidget {
  const NmSectionHeader({
    required this.title,
    this.action,
    this.onAction,
    this.actionIcon,
    super.key,
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;
  final IconData? actionIcon;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return Padding(
      padding: const EdgeInsets.only(bottom: NmSpace.s3),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: NmTextStyles.from(NmType.overline, color: nm.textMuted),
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(action!),
                  if (actionIcon != null) ...<Widget>[
                    const SizedBox(width: NmSpace.s1),
                    Icon(actionIcon, size: NmIconSize.sm),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Fila de lista con ícono, título, subtítulo y acción — la base de los menús
/// y de Configuración.
class NmListRow extends StatelessWidget {
  const NmListRow({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.disabledNote,
    this.dense = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  /// Motivo visible cuando la fila está deshabilitada ("Necesita conexión").
  final String? disabledNote;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return Semantics(
      button: onTap != null,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : NmStateToken.disabledOpacity,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: NmRadius.brMd,
            highlightColor: nm.hoverNeutral,
            child: Container(
              constraints: const BoxConstraints(
                minHeight: NmLayout.minTouchTarget,
              ),
              padding: EdgeInsets.symmetric(
                horizontal: NmSpace.s3,
                vertical: dense ? NmSpace.s2 : NmSpace.s3,
              ),
              child: Row(
                children: <Widget>[
                  if (leading != null) ...<Widget>[
                    leading!,
                    const SizedBox(width: NmSpace.s4),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          title,
                          style: NmTextStyles.from(NmType.body, color: nm.text),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: NmTextStyles.from(
                              NmType.caption,
                              color: nm.textMuted,
                            ),
                          ),
                        if (!enabled && disabledNote != null)
                          Text(
                            disabledNote!,
                            style: NmTextStyles.from(
                              NmType.micro,
                              color: nm.caution,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (trailing != null) ...<Widget>[
                    const SizedBox(width: NmSpace.s3),
                    trailing!,
                  ] else if (onTap != null)
                    Icon(
                      PhosphorIcons.caretRight(),
                      size: NmIconSize.md,
                      color: nm.textMuted,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum NmNoteTone { neutral, caution, info, success }

/// Nota explicativa: estimaciones, límites, aclaraciones de cálculo.
class InfoNote extends StatelessWidget {
  const InfoNote({
    required this.text,
    this.tone = NmNoteTone.neutral,
    this.icon,
    this.action,
    this.onAction,
    super.key,
  });

  final String text;
  final NmNoteTone tone;
  final IconData? icon;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final color = switch (tone) {
      NmNoteTone.neutral => nm.textMuted,
      NmNoteTone.caution => nm.caution,
      NmNoteTone.info => nm.info,
      NmNoteTone.success => nm.success,
    };
    final bg = tone == NmNoteTone.neutral
        ? Colors.transparent
        : color.withValues(alpha: nm.isDark ? 0.10 : 0.08);

    return Container(
      padding: EdgeInsets.all(tone == NmNoteTone.neutral ? 0 : NmSpace.s3),
      decoration: BoxDecoration(color: bg, borderRadius: NmRadius.brMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (icon != null || tone != NmNoteTone.neutral) ...<Widget>[
            Icon(
              icon ?? PhosphorIcons.info(),
              size: NmIconSize.sm,
              color: color,
            ),
            const SizedBox(width: NmSpace.s2),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  text,
                  style: NmTextStyles.from(NmType.caption, color: color),
                ),
                if (action != null)
                  GestureDetector(
                    onTap: onAction,
                    child: Padding(
                      padding: const EdgeInsets.only(top: NmSpace.s1),
                      child: Text(
                        action!,
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
    );
  }
}

/// Fila etiqueta–valor del desglose diario. Se lee como par por el lector de
/// pantalla (S-06, accesibilidad).
class ValueRow extends StatelessWidget {
  const ValueRow({
    required this.label,
    required this.value,
    this.caption,
    this.hint,
    this.emphasis = false,
    this.valueColor,
    this.muted = false,
    this.onEdit,
    this.editTooltip = 'Editar',
    super.key,
  });

  final String label;
  final String value;
  final String? caption;

  /// Detalle que no hace falta leer siempre: va en un tooltip detrás de un
  /// ícono chico al lado de la etiqueta, en vez de texto gris en la fila.
  final String? hint;
  final bool emphasis;
  final Color? valueColor;
  final bool muted;

  /// Con esto la fila se vuelve tocable y muestra un lápiz al final: sirve
  /// para los valores que la persona puede cambiar y que, sin la señal, se
  /// leen como resultados de un cálculo intocable.
  final VoidCallback? onEdit;
  final String editTooltip;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final labelStyle = emphasis
        ? NmTextStyles.from(NmType.h4, color: nm.text)
        : NmTextStyles.from(
            NmType.bodySm,
            color: muted ? nm.textMuted : nm.text,
          );
    final valueStyle =
        (emphasis
                ? NmTextStyles.from(NmType.h4, color: nm.text)
                : NmTextStyles.from(
                    NmType.bodySm,
                    color: muted ? nm.textMuted : nm.text,
                  ))
            .tnum
            .copyWith(color: valueColor);

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: NmSpace.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Flexible(child: Text(label, style: labelStyle)),
                if (hint != null) ...<Widget>[
                  const SizedBox(width: NmSpace.s1),
                  Tooltip(
                    message: hint,
                    triggerMode: TooltipTriggerMode.tap,
                    showDuration: const Duration(seconds: 4),
                    child: Icon(
                      PhosphorIcons.info(),
                      size: NmIconSize.sm,
                      color: nm.textMuted,
                    ),
                  ),
                ],
                if (caption != null) ...<Widget>[
                  const SizedBox(width: NmSpace.s2),
                  Flexible(
                    child: Text(
                      caption!,
                      style: NmTextStyles.from(
                        NmType.micro,
                        color: nm.textMuted,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: NmSpace.s3),
          Text(value, style: valueStyle),
          if (onEdit != null) ...<Widget>[
            const SizedBox(width: NmSpace.s2),
            Icon(
              PhosphorIcons.pencilSimple(),
              size: NmIconSize.sm,
              color: nm.isDark ? nm.accentText : nm.accent,
            ),
          ],
        ],
      ),
    );

    return Semantics(
      label: '$label: $value${caption == null ? '' : ', $caption'}',
      button: onEdit != null,
      onTapHint: onEdit == null ? null : editTooltip,
      child: ExcludeSemantics(
        child: onEdit == null
            ? row
            : InkWell(onTap: onEdit, borderRadius: NmRadius.brSm, child: row),
      ),
    );
  }
}

/// Fórmula del desglose diario, expuesta como texto plano legible (S-07).
class FormulaRow extends StatelessWidget {
  const FormulaRow({required this.expression, required this.values, super.key});

  final String expression;
  final String values;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(NmSpace.s4),
      decoration: BoxDecoration(
        color: nm.surfaceRaised,
        borderRadius: NmRadius.brMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            expression,
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
          ),
          const SizedBox(height: NmSpace.s2),
          Text(
            values,
            style: NmTextStyles.from(NmType.h4, color: nm.text).tnum,
          ),
        ],
      ),
    );
  }
}

/// Divisor de 1 px con el color de token.
class NmDivider extends StatelessWidget {
  const NmDivider({this.indent = 0, super.key});

  final double indent;

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    thickness: 1,
    indent: indent,
    color: context.nm.divider,
  );
}

/// Chip seleccionable. Cambia borde y color en `instant`, **sin** cambio de
/// tamaño: mover el layout al seleccionar desorienta (21-motion §5).
class NmChip extends StatelessWidget {
  const NmChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.subtitle,
    this.semanticsInRadioGroup = false,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final String? subtitle;
  final bool semanticsInRadioGroup;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: semanticsInRadioGroup,
      button: !semanticsInRadioGroup,
      label: subtitle == null ? label : '$label, $subtitle',
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(NmRadius.full),
            child: AnimatedContainer(
              duration: context.motion.fade(NmMotion.instant),
              curve: NmMotion.ease,
              constraints: const BoxConstraints(minHeight: 40),
              padding: const EdgeInsets.symmetric(
                horizontal: NmSpace.s4,
                vertical: NmSpace.s2,
              ),
              decoration: BoxDecoration(
                color: selected ? nm.accentFill : nm.surfaceRaised,
                borderRadius: BorderRadius.circular(NmRadius.full),
                border: Border.all(color: selected ? nm.accent : nm.divider),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(
                      icon,
                      size: NmIconSize.md,
                      color: selected ? nm.accentOnFill : nm.text,
                    ),
                    const SizedBox(width: NmSpace.s2),
                  ],
                  // `Flexible` y no el `Column` suelto: dentro de un `Wrap` el
                  // chip recibe el ancho de la fila como techo, y un texto que
                  // no cede desborda por derecha en vez de pasar a dos
                  // renglones. Con esto el chip se hace más alto, que es lo
                  // único que un chip puede hacer sin romper la grilla.
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          label,
                          style: NmTextStyles.from(
                            NmType.bodySm,
                            color: selected ? nm.accentOnFill : nm.text,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: NmTextStyles.from(
                              NmType.micro,
                              color: selected ? nm.accentOnFill : nm.textMuted,
                            ).tnum,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
