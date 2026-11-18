import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'nm_theme.dart';
import 'palettes.dart';
import 'text_styles.dart';
import 'tokens.dart';

/// Tema claro y oscuro. El oscuro es el canónico del sistema de diseño
/// (Nocturne, D-10); el claro invierte la rampa neutral y baja el acento un
/// paso para conservar ≥ 4,5:1 sobre blanco.
abstract final class NmAppTheme {
  static ThemeData dark() => _build(NmTheme.dark());

  static ThemeData light() => _build(NmTheme.light());

  /// El tema elegido en Apariencia, en su variante clara u oscura. Sakura y
  /// Neo Tokyo ignoran [dark]: tienen un solo modo.
  static ThemeData of(AppPalette palette, {required bool dark}) =>
      _build(NmTheme(palette.data(dark: dark)));

  static ThemeData _build(NmTheme nm) {
    final c = nm.colors;
    final brightness = nm.isDark ? Brightness.dark : Brightness.light;
    final textTheme = NmTextStyles.textTheme(c.text, c.textMuted);

    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: nm.onAccent,
      primaryContainer: nm.accentFill,
      onPrimaryContainer: nm.accentOnFill,
      secondary: nm.isDark ? nm.accent2Ramp.c400 : nm.accent2Ramp.c600,
      onSecondary: nm.onAccent,
      surface: c.surface,
      onSurface: c.text,
      surfaceContainerHighest: c.surfaceRaised,
      onSurfaceVariant: c.textMuted,
      error: c.danger,
      onError: nm.onAccent,
      outline: c.divider,
      outlineVariant: c.divider,
      shadow: const Color(0xFF000000),
      inverseSurface: c.text,
      onInverseSurface: c.bg,
      inversePrimary: c.accent,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.bg,
      fontFamily: NmType.fontFamily,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      extensions: <ThemeExtension<dynamic>>[nm],

      // El foco visible usa el anillo de acento del sistema, nunca el del SO (§7).
      focusColor: c.accent.withValues(alpha: NmStateToken.hoverAccentAlpha),
      hoverColor: nm.hoverNeutral,
      highlightColor: nm.pressedNeutral,
      splashColor: nm.hoverAccent,
      dividerColor: c.divider,

      appBarTheme: AppBarTheme(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: c.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: NmTextStyles.from(NmType.h3, color: c.text),
        systemOverlayStyle: nm.isDark
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: c.bg,
              )
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: c.bg,
              ),
      ),

      dividerTheme: DividerThemeData(
        color: c.divider,
        thickness: 1,
        space: 1,
      ),

      cardTheme: CardThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: NmRadius.brMd),
      ),

      // El primario es contorneado, nunca relleno (05-component-library §4).
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll<Size>(
            Size(0, NmLayout.minTouchTarget),
          ),
          padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(
              horizontal: NmSpace.s6,
              vertical: NmSpace.s3,
            ),
          ),
          shape: const WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: NmRadius.brMd),
          ),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return BorderSide(
                color: c.accent.withValues(
                  alpha: NmStateToken.disabledOpacity,
                ),
              );
            }
            return BorderSide(color: c.accent);
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return nm.isDark ? nm.accentRamp.c300 : nm.accentRamp.c700;
            }
            return nm.isDark ? c.accentText : c.accent;
          }),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) return nm.pressedAccent;
            return nm.hoverAccent;
          }),
          textStyle: WidgetStatePropertyAll<TextStyle>(
            NmTextStyles.from(NmType.bodySm).copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll<Size>(Size(0, 44)),
          padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(horizontal: NmSpace.s4, vertical: NmSpace.s2),
          ),
          shape: const WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: NmRadius.brMd),
          ),
          foregroundColor: WidgetStatePropertyAll<Color>(
            nm.isDark ? c.accentText : c.accent,
          ),
          overlayColor: WidgetStatePropertyAll<Color>(nm.hoverAccent),
          textStyle: WidgetStatePropertyAll<TextStyle>(
            NmTextStyles.from(NmType.bodySm),
          ),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll<Size>(
            Size(NmLayout.minTouchTarget, NmLayout.minTouchTarget),
          ),
          foregroundColor: WidgetStatePropertyAll<Color>(c.text),
          overlayColor: WidgetStatePropertyAll<Color>(nm.hoverNeutral),
        ),
      ),

      iconTheme: IconThemeData(color: c.text, size: NmIconSize.lg),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: NmSpace.s4,
          vertical: NmSpace.s4,
        ),
        hintStyle: NmTextStyles.from(NmType.bodySm, color: c.textMuted),
        labelStyle: NmTextStyles.from(NmType.caption, color: c.textMuted),
        floatingLabelStyle: NmTextStyles.from(NmType.caption, color: c.accent),
        errorStyle: NmTextStyles.from(NmType.caption, color: c.danger),
        border: OutlineInputBorder(
          borderRadius: NmRadius.brMd,
          borderSide: BorderSide(color: c.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: NmRadius.brMd,
          borderSide: BorderSide(color: c.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: NmRadius.brMd,
          borderSide: BorderSide(color: c.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: NmRadius.brMd,
          borderSide: BorderSide(color: c.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: NmRadius.brMd,
          borderSide: BorderSide(color: c.danger, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: NmRadius.brMd,
          borderSide: BorderSide(
            color: c.divider.withValues(alpha: NmStateToken.disabledOpacity),
          ),
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: c.surface,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: c.divider,
        dragHandleSize: const Size(36, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(NmRadius.lg),
          ),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: NmRadius.brLg),
        titleTextStyle: NmTextStyles.from(NmType.h3, color: c.text),
        contentTextStyle: NmTextStyles.from(NmType.bodySm, color: c.text),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.surfaceRaised,
        contentTextStyle: NmTextStyles.from(NmType.bodySm, color: c.text),
        actionTextColor: nm.isDark ? c.accentText : c.accent,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: NmRadius.brMd),
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: c.accent,
        inactiveTrackColor: c.divider,
        thumbColor: c.accent,
        overlayColor: nm.hoverAccent,
        trackHeight: 3,
        valueIndicatorColor: c.surfaceRaised,
        valueIndicatorTextStyle: NmTextStyles.from(
          NmType.caption,
          color: c.text,
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return nm.isDark ? nm.accentRamp.c200 : Colors.white;
          }
          return nm.isDark ? nm.neutralRamp.c400 : nm.neutralRamp.c500;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return c.accent;
          return c.surfaceRaised;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return c.accent;
          return c.divider;
        }),
      ),

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return c.accent;
          return c.textMuted;
        }),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return c.accent;
          return Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll<Color>(
          nm.onAccent,
        ),
        side: BorderSide(color: c.divider, width: 1.5),
        shape: const RoundedRectangleBorder(borderRadius: NmRadius.brSm),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: c.divider,
        circularTrackColor: Colors.transparent,
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          borderRadius: NmRadius.brSm,
          border: Border.all(color: c.divider),
        ),
        textStyle: NmTextStyles.from(NmType.micro, color: c.text),
      ),

      listTileTheme: ListTileThemeData(
        iconColor: c.text,
        textColor: c.text,
        minVerticalPadding: NmSpace.s3,
        shape: const RoundedRectangleBorder(borderRadius: NmRadius.brMd),
      ),

      // Deslizamiento de 12 px desde la derecha + fundido (21-motion §2).
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: NmPageTransitionsBuilder(),
          TargetPlatform.iOS: NmPageTransitionsBuilder(),
          TargetPlatform.windows: NmPageTransitionsBuilder(),
          TargetPlatform.macOS: NmPageTransitionsBuilder(),
          TargetPlatform.linux: NmPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// Transición de pantalla del sistema: 12 px desde la derecha + fundido,
/// `motion.base` con `ease` al entrar y `easeOut` al salir (21-motion §2).
class NmPageTransitionsBuilder extends PageTransitionsBuilder {
  const NmPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext? context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => NmPageTransition(
    animation: animation,
    secondaryAnimation: secondaryAnimation,
    child: child,
  );
}

class NmPageTransition extends StatelessWidget {
  const NmPageTransition({
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
    super.key,
  });

  /// Desplazamiento fijo en píxeles lógicos, no fraccional.
  static const double slide = 12;

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final curved = CurvedAnimation(
      parent: animation,
      curve: NmMotion.ease,
      reverseCurve: NmMotion.easeOut,
    );
    return AnimatedBuilder(
      animation: curved,
      builder: (context, inner) {
        final dx = reduced ? 0.0 : slide * (1 - curved.value);
        return Opacity(
          opacity: curved.value.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(dx, 0), child: inner),
        );
      },
      child: child,
    );
  }
}
