import 'package:flutter/material.dart';

import 'palettes.dart';
import 'tokens.dart';

/// Los tokens del sistema, disponibles desde cualquier widget vía `context.nm`.
///
/// Ningún componente escribe un hex, un nombre de fuente ni un número de píxel
/// que ya exista como token (06-design-tokens.md, regla de oro). Los colores
/// salen del tema elegido en Apariencia ([AppPalette]): un componente que lee
/// `NmAccent` o `NmChartColors` directo se queda con los de Ceres en Sakura.
@immutable
class NmTheme extends ThemeExtension<NmTheme> {
  const NmTheme(this.palette);

  factory NmTheme.dark() => const NmTheme(NmPalettes.ceresDark);

  factory NmTheme.light() => const NmTheme(NmPalettes.ceresLight);

  final NmPaletteData palette;

  NmColorRoles get colors => palette.colors;
  List<BoxShadow> get shadowSm => palette.shadowSm;
  List<BoxShadow> get shadowMd => palette.shadowMd;
  List<BoxShadow> get shadowLg => palette.shadowLg;
  bool get isDark => palette.isDark;

  /// Las rampas del tema, para los tonos que no son un rol.
  NmRamp get accentRamp => palette.accent;
  NmRamp get accent2Ramp => palette.accent2;
  NmRamp get neutralRamp => palette.neutral;

  /// Los colores de datos del tema (§1.4).
  NmChartPalette get charts => palette.charts;

  /// Lo que va encima del acento (el ícono del botón +, el tilde de una casilla).
  Color get onAccent => isDark ? neutralRamp.c900 : Colors.white;

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
  Color get overBudget => accentRamp.c700;

  /// Relleno tintado sobre fondo oscuro / claro para superficies de acento.
  Color get accentFill =>
      isDark ? accentRamp.c800.withValues(alpha: 0.55) : accentRamp.c100;

  /// Texto legible sobre [accentFill].
  Color get accentOnFill => isDark ? accentRamp.c200 : accentRamp.c700;

  /// Relleno tintado de [caution], para el fondo de un estado marcado.
  ///
  /// Sale del token y no es un color nuevo: así un cambio de paleta lo arrastra
  /// solo. El alpha es bajo a propósito — es un fondo que tiene que dejar leer
  /// el ícono que lleva encima, no un cartel.
  Color get cautionFill => caution.withValues(alpha: isDark ? 0.22 : 0.16);

  /// Color del bloque de skeleton (21-motion-and-loading.md §4.2).
  Color get skeleton => isDark ? neutralRamp.c800 : neutralRamp.c200;

  Color get skeletonHighlight =>
      isDark ? neutralRamp.c700 : neutralRamp.c100.withValues(alpha: 0.9);

  /// El fondo del anillo de calorías y de las pistas vacías.
  Color get track => isDark ? neutralRamp.c800 : neutralRamp.c200;

  /// Tinte de estado presionado (§7).
  Color get pressedAccent =>
      (isDark ? accentRamp.c400 : accent).withValues(alpha: NmStateToken.pressedAccentAlpha);

  Color get hoverAccent =>
      accent.withValues(alpha: NmStateToken.hoverAccentAlpha);

  Color get hoverNeutral =>
      text.withValues(alpha: NmStateToken.hoverNeutralAlpha);

  Color get pressedNeutral =>
      text.withValues(alpha: NmStateToken.pressedNeutralAlpha);

  @override
  NmTheme copyWith({NmPaletteData? palette}) => NmTheme(palette ?? this.palette);

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
