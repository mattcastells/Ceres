import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show TextTheme;

import 'tokens.dart';

/// Construcción de estilos a partir de la escala tipográfica (06-design-tokens.md §2).
///
/// Regla del sistema: la jerarquía es tamaño y espacio, no peso. Los títulos van
/// en 500 y nunca suben a 600/700.
abstract final class NmTextStyles {
  static FontWeight weightOf(int w) => switch (w) {
    400 => FontWeight.w400,
    500 => FontWeight.w500,
    600 => FontWeight.w600,
    _ => FontWeight.w400,
  };

  /// Convierte un token de tipografía en un [TextStyle] concreto.
  static TextStyle from(NmTypeSpec spec, {Color? color}) => TextStyle(
    fontFamily: NmType.fontFamily,
    fontSize: spec.size,
    height: spec.lineHeight,
    fontWeight: weightOf(spec.weight),
    letterSpacing: spec.letterSpacing,
    color: color,
  );

  static TextStyle get display => from(NmType.display);
  static TextStyle get h1 => from(NmType.h1);
  static TextStyle get h2 => from(NmType.h2);
  static TextStyle get h3 => from(NmType.h3);
  static TextStyle get h4 => from(NmType.h4);
  static TextStyle get body => from(NmType.body);
  static TextStyle get bodySm => from(NmType.bodySm);
  static TextStyle get caption => from(NmType.caption);
  static TextStyle get micro => from(NmType.micro);
  static TextStyle get overline => from(NmType.overline);

  static TextTheme textTheme(Color text, Color muted) => TextTheme(
    displayLarge: from(NmType.display, color: text).tnum,
    displayMedium: from(NmType.h1, color: text),
    headlineLarge: from(NmType.h1, color: text),
    headlineMedium: from(NmType.h2, color: text),
    headlineSmall: from(NmType.h3, color: text),
    titleLarge: from(NmType.h3, color: text),
    titleMedium: from(NmType.h4, color: text),
    titleSmall: from(NmType.bodySm, color: text),
    bodyLarge: from(NmType.body, color: text),
    bodyMedium: from(NmType.bodySm, color: text),
    bodySmall: from(NmType.caption, color: muted),
    labelLarge: from(NmType.bodySm, color: text),
    labelMedium: from(NmType.micro, color: muted),
    labelSmall: from(NmType.overline, color: muted),
  );
}

extension NmTextStyleX on TextStyle {
  /// Números tabulares: obligatorio en calorías, peso y duración para que las
  /// cifras no bailen al actualizarse (06-design-tokens.md §2).
  TextStyle get tnum =>
      copyWith(fontFeatures: const <FontFeature>[FontFeature.tabularFigures()]);

}
