import 'package:flutter/material.dart';

import 'tokens.dart';

/// Los tokens del sistema, disponibles desde cualquier widget vía `context.nm`.
///
/// Ningún componente escribe un hex, un nombre de fuente ni un número de píxel
/// que ya exista como token (06-design-tokens.md, regla de oro).
@immutable
class NmTheme extends ThemeExtension<NmTheme> {
  const NmTheme({
    required this.colors,
    required this.shadowSm,
    required this.shadowMd,
    required this.shadowLg,
    required this.isDark,
  });

  factory NmTheme.dark() => const NmTheme(
    colors: NmColors.dark,
    shadowSm: NmShadow.darkSm,
    shadowMd: NmShadow.darkMd,
    shadowLg: NmShadow.darkLg,
    isDark: true,
  );

  factory NmTheme.light() => const NmTheme(
    colors: NmColors.light,
    shadowSm: NmShadow.lightSm,
    shadowMd: NmShadow.lightMd,
    shadowLg: NmShadow.lightLg,
    isDark: false,
  );

  final NmColorRoles colors;
  final List<BoxShadow> shadowSm;
  final List<BoxShadow> shadowMd;
  final List<BoxShadow> shadowLg;
  final bool isDark;

  // Atajos de rol, para no escribir `context.nm.colors.x` en cada línea.
  Color get bg => colors.bg;
  Color get surface => colors.surface;
  Color get surfaceRaised => colors.surfaceRaised;
  Color get text => colors.text;
  Color get textMuted => colors.textMuted;
  Color get accent => colors.accent;
  Color get accentText => colors.accentText;
  Color get divider => colors.divider;
  Color get success => colors.success;

  /// Todo lo estimado o incierto: banner de IA, badge de revisión (§1.3).
  Color get caution => colors.caution;

  /// Errores del sistema y acciones destructivas. **Nunca** el exceso calórico
  /// (RN-14 / D-17): ese usa [overBudget].
  Color get danger => colors.danger;
  Color get info => colors.info;

  /// El arco excedente del anillo de calorías (D-17).
  Color get overBudget => NmAccent.c700;

  /// Relleno tintado sobre fondo oscuro / claro para superficies de acento.
  Color get accentFill =>
      isDark ? NmAccent.c800.withValues(alpha: 0.55) : NmAccent.c100;

  /// Texto legible sobre [accentFill].
  Color get accentOnFill => isDark ? NmAccent.c200 : NmAccent.c700;

  /// Relleno tintado de [caution], para el fondo de un estado marcado.
  ///
  /// Sale del token y no es un color nuevo: así un cambio de paleta lo arrastra
  /// solo. El alpha es bajo a propósito — es un fondo que tiene que dejar leer
  /// el ícono que lleva encima, no un cartel.
  Color get cautionFill => caution.withValues(alpha: isDark ? 0.22 : 0.16);

  /// Color del bloque de skeleton (21-motion-and-loading.md §4.2).
  Color get skeleton => isDark ? NmNeutral.c800 : NmNeutral.c200;

  Color get skeletonHighlight =>
      isDark ? NmNeutral.c700 : NmNeutral.c100.withValues(alpha: 0.9);

  /// Tinte de estado presionado (§7).
  Color get pressedAccent =>
      (isDark ? NmAccent.c400 : accent).withValues(alpha: NmStateToken.pressedAccentAlpha);

  Color get hoverAccent =>
      accent.withValues(alpha: NmStateToken.hoverAccentAlpha);

  Color get hoverNeutral =>
      text.withValues(alpha: NmStateToken.hoverNeutralAlpha);

  Color get pressedNeutral =>
      text.withValues(alpha: NmStateToken.pressedNeutralAlpha);

  @override
  NmTheme copyWith({
    NmColorRoles? colors,
    List<BoxShadow>? shadowSm,
    List<BoxShadow>? shadowMd,
    List<BoxShadow>? shadowLg,
    bool? isDark,
  }) => NmTheme(
    colors: colors ?? this.colors,
    shadowSm: shadowSm ?? this.shadowSm,
    shadowMd: shadowMd ?? this.shadowMd,
    shadowLg: shadowLg ?? this.shadowLg,
    isDark: isDark ?? this.isDark,
  );

  @override
  NmTheme lerp(ThemeExtension<NmTheme>? other, double t) {
    if (other is! NmTheme) return this;
    return t < 0.5 ? this : other;
  }
}

extension NmThemeContext on BuildContext {
  /// Tokens del tema vigente.
  NmTheme get nm => Theme.of(this).extension<NmTheme>() ?? NmTheme.dark();

  TextTheme get texts => Theme.of(this).textTheme;

  /// Ancho lógico de pantalla, para las decisiones de layout de §6.
  double get screenWidth => MediaQuery.sizeOf(this).width;

  bool get isCompact => screenWidth < NmBreakpoint.medium;
  bool get isMedium =>
      screenWidth >= NmBreakpoint.medium && screenWidth < NmBreakpoint.expanded;
  bool get isExpanded => screenWidth >= NmBreakpoint.expanded;

  /// 16 px laterales en móvil, 24 px ≥ 600 px (§3).
  double get screenPadding =>
      isCompact ? NmLayout.screenPaddingCompact : NmLayout.screenPaddingMedium;
}
