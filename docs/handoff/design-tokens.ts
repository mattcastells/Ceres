/**
 * Ceres — design tokens (React Native / TypeScript).
 * Generado desde design-tokens.json. No editar a mano: editar el JSON y regenerar.
 */

export const palette = {
  neutral: {
    100: '#f3f5fe', 200: '#e4e7f5', 300: '#cfd3e5', 400: '#b2b6ca', 500: '#9397ab',
    600: '#75798c', 700: '#595d6c', 800: '#3f424d', 900: '#292b31',
  },
  accent: {
    100: '#f5f4ff', 200: '#e7e5fe', 300: '#d2cefd', 400: '#b5abfc', 500: '#968ae0',
    600: '#796cbf', 700: '#5d5294', 800: '#423a6a', 900: '#2b2741',
  },
  accent2: {
    100: '#f5f4ff', 200: '#e7e5fe', 300: '#d2cefd', 400: '#b5afe8', 500: '#9690c9',
    600: '#7972a9', 700: '#5c5783', 800: '#423e5d', 900: '#2b293a',
  },
} as const;

export const chartColors = {
  walking: '#9184d9',
  running: '#7fa8d9',
  strength: '#b5abfc',
  cycling: '#6fbf9a',
  sports: '#d9b46a',
  other: '#9397ab',
  intake: '#968ae0',
  target: '#cfd3e5',
  weight: '#b5abfc',
  trend: '#e9e9ed',
} as const;

export const darkColors = {
  bg: '#161826',
  surface: '#232532',
  surfaceRaised: '#2b2e3d',
  text: '#e9e9ed',
  textMuted: 'rgba(233,233,237,0.55)',
  accent: '#9184d9',
  accentText: '#d2cefd',
  divider: 'rgba(233,233,237,0.16)',
  section: '#262a60',
  success: '#6fbf9a',
  caution: '#d9b46a',
  danger: '#d97b7b',
  info: '#7fa8d9',
} as const;

export const lightColors: typeof darkColors = {
  bg: '#f7f7fb',
  surface: '#ffffff',
  surfaceRaised: '#f0f0f6',
  text: '#1b1c26',
  textMuted: 'rgba(27,28,38,0.58)',
  accent: '#796cbf',
  accentText: '#5d5294',
  divider: 'rgba(27,28,38,0.12)',
  section: '#262a60',
  success: '#2f8f6a',
  caution: '#9a7420',
  danger: '#b04141',
  info: '#3c6ea8',
};

export const typography = {
  display:  { fontSize: 42, lineHeight: 47, fontWeight: '500', letterSpacing: -0.63 },
  h1:       { fontSize: 32, lineHeight: 36, fontWeight: '500', letterSpacing: -0.48 },
  h2:       { fontSize: 25, lineHeight: 29, fontWeight: '500', letterSpacing: -0.38 },
  h3:       { fontSize: 20, lineHeight: 24, fontWeight: '500', letterSpacing: -0.2 },
  h4:       { fontSize: 16, lineHeight: 21, fontWeight: '500', letterSpacing: 0 },
  body:     { fontSize: 15, lineHeight: 23, fontWeight: '400', letterSpacing: 0 },
  bodySm:   { fontSize: 14, lineHeight: 21, fontWeight: '400', letterSpacing: 0 },
  caption:  { fontSize: 13, lineHeight: 19, fontWeight: '400', letterSpacing: 0 },
  micro:    { fontSize: 11, lineHeight: 15, fontWeight: '400', letterSpacing: 0.22 },
  overline: { fontSize: 10, lineHeight: 14, fontWeight: '500', letterSpacing: 1.0, textTransform: 'uppercase' },
} as const;

export const space = { s1: 3, s2: 6, s3: 8, s4: 11, s5: 14, s6: 17, s8: 22, s10: 28, s12: 34 } as const;
export const radius = { sm: 4, md: 8, lg: 14, full: 999 } as const;
export const icon = { sm: 16, md: 20, lg: 24, xl: 32 } as const;

export const layout = {
  screenPaddingCompact: 16,
  screenPaddingMedium: 24,
  contentMaxWidth: 720,
  tabBarHeight: 56,
  fabSize: 56,
  minTouchTarget: 48,
} as const;

export const motion = {
  instant: 90, fast: 160, base: 240, slow: 380, chart: 520,
  stagger: 40, shimmerLoop: 1200, spinnerLoop: 900,
  loadingMinVisible: 400, loadingThreshold: 200,
  ease: 'cubic-bezier(0.2,0.8,0.2,1)',
  easeOut: 'cubic-bezier(0.4,0,1,1)',
} as const;

export const breakpoint = { compact: 0, medium: 600, expanded: 905 } as const;

export const zIndex = {
  content: 0, appBar: 10, fab: 20, sheet: 30, dialog: 40, snackbar: 50, systemBanner: 60,
} as const;

export const stateTokens = {
  hoverAccentAlpha: 0.12,
  pressedAccentAlpha: 0.22,
  hoverNeutralAlpha: 0.07,
  pressedNeutralAlpha: 0.14,
  disabledOpacity: 0.45,
  focusRing: { width: 2, offset: 2 },
} as const;

export type ThemeMode = 'light' | 'dark';

export const theme = (mode: ThemeMode) => ({
  mode,
  colors: mode === 'dark' ? darkColors : lightColors,
  palette,
  chartColors,
  typography,
  space,
  radius,
  icon,
  layout,
  motion,
  breakpoint,
  zIndex,
  state: stateTokens,
  shadow:
    mode === 'dark'
      ? {
          sm: { shadowColor: '#000', shadowOpacity: 0, elevation: 0, borderWidth: 1, borderColor: '#3f424d' },
          md: { shadowColor: '#000', shadowOpacity: 0.55, shadowRadius: 18, shadowOffset: { width: 0, height: 6 }, elevation: 8 },
          lg: { shadowColor: '#000', shadowOpacity: 0.65, shadowRadius: 40, shadowOffset: { width: 0, height: 16 }, elevation: 16 },
        }
      : {
          sm: { shadowColor: '#1b1c26', shadowOpacity: 0.08, shadowRadius: 2, shadowOffset: { width: 0, height: 1 }, elevation: 1 },
          md: { shadowColor: '#1b1c26', shadowOpacity: 0.1, shadowRadius: 14, shadowOffset: { width: 0, height: 4 }, elevation: 4 },
          lg: { shadowColor: '#1b1c26', shadowOpacity: 0.16, shadowRadius: 40, shadowOffset: { width: 0, height: 16 }, elevation: 12 },
        },
});

export type CeresTheme = ReturnType<typeof theme>;
