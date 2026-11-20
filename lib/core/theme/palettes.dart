import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

/// Una rampa 100→900 de un color, para los tonos que no son un rol (rellenos,
/// estados presionados, el arco de exceso).
@immutable
class NmRamp {
  const NmRamp(
    this.c100,
    this.c200,
    this.c300,
    this.c400,
    this.c500,
    this.c600,
    this.c700,
    this.c800,
    this.c900,
  );

  final Color c100;
  final Color c200;
  final Color c300;
  final Color c400;
  final Color c500;
  final Color c600;
  final Color c700;
  final Color c800;
  final Color c900;
}

/// Los colores de datos de un tema (§1.4): mismo orden y mismo significado en
/// todos, cambia solo el tono.
@immutable
class NmChartPalette {
  const NmChartPalette({
    required this.walking,
    required this.running,
    required this.strength,
    required this.cycling,
    required this.sports,
    required this.other,
    required this.intake,
    required this.weight,
  });

  final Color walking;
  final Color running;
  final Color strength;
  final Color cycling;
  final Color sports;
  final Color other;
  final Color intake;
  final Color weight;

  /// Series de categoría de actividad, en el orden canónico.
  List<Color> get categories => <Color>[
    walking,
    running,
    strength,
    cycling,
    sports,
    other,
  ];
}

/// Todo lo que define un tema.
@immutable
class NmPaletteData {
  const NmPaletteData({
    required this.colors,
    required this.accent,
    required this.accent2,
    required this.neutral,
    required this.charts,
    required this.shadowSm,
    required this.shadowMd,
    required this.shadowLg,
    required this.isDark,
  });

  final NmColorRoles colors;
  final NmRamp accent;
  final NmRamp accent2;
  final NmRamp neutral;
  final NmChartPalette charts;
  final List<BoxShadow> shadowSm;
  final List<BoxShadow> shadowMd;
  final List<BoxShadow> shadowLg;
  final bool isDark;
}

/// Los temas que se eligen en Apariencia.
///
/// Ceres respeta claro, oscuro o el del sistema. Sakura y Neo Tokyo tienen un
/// solo modo cada uno: son una estética entera, no una paleta que se invierte,
/// y un Sakura oscuro dejaría de ser Sakura.
enum AppPalette {
  ceres('ceres', 'Ceres', null),
  sakura('sakura', 'Sakura', Brightness.light),
  neoTokyo('neo_tokyo', 'Neo Tokyo', Brightness.dark);

  const AppPalette(this.wire, this.label, this.fixedBrightness);

  final String wire;
  final String label;

  /// `null` = sigue el modo elegido (claro, oscuro o el del sistema).
  final Brightness? fixedBrightness;

  static AppPalette fromWire(String? raw) => AppPalette.values.firstWhere(
    (p) => p.wire == raw,
    orElse: () => AppPalette.ceres,
  );

  NmPaletteData data({required bool dark}) => switch (this) {
    AppPalette.ceres => dark ? NmPalettes.ceresDark : NmPalettes.ceresLight,
    AppPalette.sakura => NmPalettes.sakura,
    AppPalette.neoTokyo => NmPalettes.neoTokyo,
  };
}

abstract final class NmPalettes {
  // ── Ceres · Nocturne, el de siempre ──────────────────────────────────────
  static const NmRamp _ceresAccent = NmRamp(
    NmAccent.c100,
    NmAccent.c200,
    NmAccent.c300,
    NmAccent.c400,
    NmAccent.c500,
    NmAccent.c600,
    NmAccent.c700,
    NmAccent.c800,
    NmAccent.c900,
  );
  static const NmRamp _ceresAccent2 = NmRamp(
    NmAccent2.c100,
    NmAccent2.c200,
    NmAccent2.c300,
    NmAccent2.c400,
    NmAccent2.c500,
    NmAccent2.c600,
    NmAccent2.c700,
    NmAccent2.c800,
    NmAccent2.c900,
  );
  static const NmRamp _ceresNeutral = NmRamp(
    NmNeutral.c100,
    NmNeutral.c200,
    NmNeutral.c300,
    NmNeutral.c400,
    NmNeutral.c500,
    NmNeutral.c600,
    NmNeutral.c700,
    NmNeutral.c800,
    NmNeutral.c900,
  );
  static const NmChartPalette _ceresCharts = NmChartPalette(
    walking: NmChartColors.walking,
    running: NmChartColors.running,
    strength: NmChartColors.strength,
    cycling: NmChartColors.cycling,
    sports: NmChartColors.sports,
    other: NmChartColors.other,
    intake: NmChartColors.intake,
    weight: NmChartColors.weight,
  );

  static const NmPaletteData ceresDark = NmPaletteData(
    colors: NmColors.dark,
    accent: _ceresAccent,
    accent2: _ceresAccent2,
    neutral: _ceresNeutral,
    charts: _ceresCharts,
    shadowSm: NmShadow.darkSm,
    shadowMd: NmShadow.darkMd,
    shadowLg: NmShadow.darkLg,
    isDark: true,
  );

  static const NmPaletteData ceresLight = NmPaletteData(
    colors: NmColors.light,
    accent: _ceresAccent,
    accent2: _ceresAccent2,
    neutral: _ceresNeutral,
    charts: _ceresCharts,
    shadowSm: NmShadow.lightSm,
    shadowMd: NmShadow.lightMd,
    shadowLg: NmShadow.lightLg,
    isDark: false,
  );

  // ── Sakura · papel washi, rosa sakura y tinta sumi ───────────────────────
  // Claro. El acento es el rosa de los pétalos llevado a un tono que se lee
  // sobre blanco (4,9:1); el segundo color es glicina, y los datos suman
  // índigo, matcha y dorado, los colores de la estampa japonesa.
  static const NmPaletteData sakura = NmPaletteData(
    colors: NmColorRoles(
      bg: Color(0xFFFBF6F4),
      surface: Color(0xFFFFFFFF),
      surfaceRaised: Color(0xFFF8EDEF),
      text: Color(0xFF2B1F25),
      textMuted: Color(0x992B1F25),
      accent: Color(0xFFC2416C),
      accentText: Color(0xFF9E2F55),
      divider: Color(0x212B1F25),
      section: Color(0xFF6E2240),
      success: Color(0xFF3F8A64),
      caution: Color(0xFFA2691A),
      danger: Color(0xFFB0363A),
      info: Color(0xFF3F64A0),
    ),
    accent: NmRamp(
      Color(0xFFFDF1F4),
      Color(0xFFFADDE5),
      Color(0xFFF5BFD0),
      Color(0xFFEE9AB5),
      Color(0xFFE27499),
      Color(0xFFC2416C),
      Color(0xFF9E2F55),
      Color(0xFF6E2240),
      Color(0xFF3E1426),
    ),
    accent2: NmRamp(
      Color(0xFFF4F1FA),
      Color(0xFFE2DCF2),
      Color(0xFFC8BDE6),
      Color(0xFFA899D4),
      Color(0xFF8877BD),
      Color(0xFF6B5AA0),
      Color(0xFF53467E),
      Color(0xFF3A315A),
      Color(0xFF241F38),
    ),
    neutral: NmRamp(
      Color(0xFFFAF6F5),
      Color(0xFFF1E9E9),
      Color(0xFFDFD4D6),
      Color(0xFFC4B7BA),
      Color(0xFFA4969B),
      Color(0xFF85777C),
      Color(0xFF675A5F),
      Color(0xFF4B4045),
      Color(0xFF2F272B),
    ),
    charts: NmChartPalette(
      walking: Color(0xFFE27499),
      running: Color(0xFF5B7FBF),
      strength: Color(0xFFA899D4),
      cycling: Color(0xFF6FAF8A),
      sports: Color(0xFFD9A04A),
      other: Color(0xFFA4969B),
      intake: Color(0xFFE27499),
      weight: Color(0xFFC2416C),
    ),
    shadowSm: <BoxShadow>[
      BoxShadow(color: Color(0x146E2240), offset: Offset(0, 1), blurRadius: 2),
    ],
    shadowMd: <BoxShadow>[
      BoxShadow(color: Color(0x1A6E2240), offset: Offset(0, 4), blurRadius: 14),
    ],
    shadowLg: <BoxShadow>[
      BoxShadow(color: Color(0x266E2240), offset: Offset(0, 16), blurRadius: 40),
    ],
    isDark: false,
  );

  // ── Neo Tokyo · noche violeta, neón arrebol y bordó ──────────────────────
  // Oscuro. Fondos violeta noche, acento rojo arrebol (bordó en la parte baja
  // de la rampa: el arco de exceso y los rellenos), violeta neón de segundo
  // color y cian para la información. El error es naranja rojizo para no
  // confundirse con el acento.
  static const NmPaletteData neoTokyo = NmPaletteData(
    colors: NmColorRoles(
      bg: Color(0xFF130A22),
      surface: Color(0xFF1F1233),
      surfaceRaised: Color(0xFF2A1844),
      text: Color(0xFFF2EAF7),
      textMuted: Color(0x99F2EAF7),
      accent: Color(0xFFFF4D82),
      accentText: Color(0xFFFFA3C2),
      divider: Color(0x29F2EAF7),
      section: Color(0xFF3F1C78),
      success: Color(0xFF3EE0A1),
      caution: Color(0xFFFFB648),
      danger: Color(0xFFFF6A3D),
      info: Color(0xFF3FD0FF),
    ),
    accent: NmRamp(
      Color(0xFFFFE8F0),
      Color(0xFFFFC9DB),
      Color(0xFFFFA3C2),
      Color(0xFFFF73A0),
      Color(0xFFFF4D82),
      Color(0xFFD92A68),
      Color(0xFFA81E52),
      Color(0xFF6E1438),
      Color(0xFF3D0B21),
    ),
    accent2: NmRamp(
      Color(0xFFF3EBFF),
      Color(0xFFE2D0FF),
      Color(0xFFC9A8FF),
      Color(0xFFAE7DFF),
      Color(0xFF9D5CFF),
      Color(0xFF7E3FE0),
      Color(0xFF5F2BB0),
      Color(0xFF3F1C78),
      Color(0xFF241046),
    ),
    neutral: NmRamp(
      Color(0xFFF4EEFA),
      Color(0xFFE3D8F0),
      Color(0xFFC9B8DE),
      Color(0xFFA893C4),
      Color(0xFF8670A6),
      Color(0xFF665288),
      Color(0xFF4B3A6A),
      Color(0xFF33254C),
      Color(0xFF1E1430),
    ),
    charts: NmChartPalette(
      walking: Color(0xFF9D5CFF),
      running: Color(0xFF3FD0FF),
      strength: Color(0xFFD27BFF),
      cycling: Color(0xFF3EE0A1),
      sports: Color(0xFFFFB648),
      other: Color(0xFF8670A6),
      intake: Color(0xFFFF4D82),
      weight: Color(0xFFD27BFF),
    ),
    shadowSm: <BoxShadow>[
      BoxShadow(color: Color(0xFF33254C), spreadRadius: 1),
    ],
    shadowMd: <BoxShadow>[
      BoxShadow(color: Color(0xFF4B3A6A), spreadRadius: 1),
      BoxShadow(color: Color(0x8C05010D), offset: Offset(0, 6), blurRadius: 18),
    ],
    shadowLg: <BoxShadow>[
      BoxShadow(color: Color(0xFF8670A6), spreadRadius: 1),
      BoxShadow(color: Color(0xA605010D), offset: Offset(0, 16), blurRadius: 40),
    ],
    isDark: true,
  );
}
