import 'package:flutter/material.dart';

import 'sr_palette.dart';

/// The six status tones the product uses.
///
/// Mirrors `TONE_CLASSES` in the web's `components/ui/badge.tsx` and the
/// intent table in handoff § 2.4. A tone is an *identifier*; its colours are
/// resolved per theme through [SrColorScheme.tone], because the same
/// "success" tone is emerald-50/700 in light and emerald-950/300 in dark.
enum SrTone { emerald, amber, red, blue, indigo, slate }

/// The resolved colours for one status tone.
@immutable
class SrToneColors {
  const SrToneColors({
    required this.fill,
    required this.foreground,
    required this.ring,
    required this.border,
    required this.alertText,
    required this.discFill,
  });

  /// Badge and alert background — `-50` in light, `-950` in dark.
  final Color fill;

  /// Badge label and icon — `-700` in light, `-300` in dark.
  final Color foreground;

  /// The 1px **inset** ring on a badge, at 20% (light) / 30% (dark).
  final Color ring;

  /// The alert container border — `-200` in light, `-900` in dark.
  final Color border;

  /// Alert body text — `-900` in light (error is `-800` for contrast),
  /// `-100`/`-200` in dark.
  final Color alertText;

  /// The stronger disc fill used inside a status card — `-100` in light.
  final Color discFill;

  static SrToneColors lerp(SrToneColors a, SrToneColors b, double t) {
    return SrToneColors(
      fill: Color.lerp(a.fill, b.fill, t)!,
      foreground: Color.lerp(a.foreground, b.foreground, t)!,
      ring: Color.lerp(a.ring, b.ring, t)!,
      border: Color.lerp(a.border, b.border, t)!,
      alertText: Color.lerp(a.alertText, b.alertText, t)!,
      discFill: Color.lerp(a.discFill, b.discFill, t)!,
    );
  }
}

/// The SalesReward semantic colour layer, carried on [ThemeData] as a
/// [ThemeExtension].
///
/// Material's own [ColorScheme] cannot express this product: it has no slot for
/// "the hairline every card shares", "the nav active rail", "the skeleton
/// shimmer", or six status tones each with a fill, a foreground, a ring, a
/// border and a disc. Rather than scatter those as constants — which would make
/// a dark theme impossible without editing every widget — they live here and
/// every widget reads them through `context.sr`.
///
/// ## Light versus dark
///
/// [light] is a faithful transcription of the shipped web app (handoff § 2).
///
/// [dark] is a **counterpart of the same identity, not an inversion**. Three
/// rules governed it:
///
/// 1. **Same hue families.** Every dark value is another step of the same
///    Tailwind v4 family the light value came from. No new hue is introduced.
/// 2. **Lightness is re-mapped, not flipped.** Surfaces descend
///    (white → slate-900) while the *type* ascends (slate-900 → slate-50), and
///    saturated brand and status hues move to the lighter `300`/`400` steps so
///    they stay legible on a dark field. A literal inversion would turn indigo
///    into a muddy yellow-green and destroy the brand.
/// 3. **Contrast is verified, not assumed.** Every foreground/background pair
///    used for text in [dark] meets WCAG AA (≥ 4.5:1); the audit is recorded in
///    `docs/flutter-application-foundation.md`.
///
/// The brand mark itself is theme-independent — see [SrBrandLiterals].
@immutable
class SrColorScheme extends ThemeExtension<SrColorScheme> {
  const SrColorScheme({
    required this.brightness,
    required this.background,
    required this.backgroundSecondary,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceNav,
    required this.surfaceAppBar,
    required this.border,
    required this.borderStrong,
    required this.brand,
    required this.brandHover,
    required this.brandSoft,
    required this.onBrandSoft,
    required this.onBrand,
    required this.accent,
    required this.foreground,
    required this.textLabel,
    required this.textBody,
    required this.textSecondary,
    required this.textMuted,
    required this.onDark,
    required this.secondaryFill,
    required this.secondaryHover,
    required this.onSecondary,
    required this.outlineFill,
    required this.outlineHover,
    required this.onOutline,
    required this.ghostHover,
    required this.onGhost,
    required this.dangerFill,
    required this.dangerHover,
    required this.inputFill,
    required this.inputDisabledFill,
    required this.inputBorder,
    required this.inputFocusBorder,
    required this.inputErrorBorder,
    required this.inputErrorFocusBorder,
    required this.fieldError,
    required this.focusRing,
    required this.navLabel,
    required this.navActiveFill,
    required this.navActiveLabel,
    required this.navActiveRail,
    required this.skeletonBase,
    required this.skeletonHighlight,
    required this.scrim,
    required this.selectionBackground,
    required this.selectionForeground,
    required this.cardShadow,
    required this.elevatedShadow,
    required this.modalShadow,
    required this.subtleShadow,
    required this.emerald,
    required this.amber,
    required this.red,
    required this.blue,
    required this.indigo,
    required this.slate,
  });

  final Brightness brightness;

  // Surfaces ------------------------------------------------------------------

  /// The page behind every screen.
  final Color background;

  /// A recessed band inside a page.
  final Color backgroundSecondary;

  /// Cards, sheets, dialogs.
  final Color surface;

  /// The `muted` card variant — a recessed, shadowless surface.
  final Color surfaceMuted;

  /// The navigation drawer and rail.
  ///
  /// **In light this is white**, not the dark `--surface-nav` custom property.
  /// That property is declared in `globals.css` but is *never applied* — the
  /// shipped sidebar is white — and handoff § 2.3 says explicitly not to build
  /// a dark drawer from it.
  final Color surfaceNav;

  /// The sticky app bar, at 85% opacity behind a blur.
  final Color surfaceAppBar;

  /// The 1px hairline every card and divider shares.
  final Color border;

  /// The heavier border used by form controls and dashed empty states.
  final Color borderStrong;

  // Brand ---------------------------------------------------------------------

  final Color brand;
  final Color brandHover;

  /// The tinted brand surface: active nav fill, icon discs, info panels.
  final Color brandSoft;

  /// Text and icons on [brandSoft].
  final Color onBrandSoft;

  /// Text and icons on [brand].
  final Color onBrand;

  /// The violet gradient partner for avatars and the route progress bar.
  final Color accent;

  // Text ----------------------------------------------------------------------

  /// Headings and primary body.
  final Color foreground;

  /// Form field labels.
  final Color textLabel;

  /// Body copy and table cells.
  final Color textBody;

  /// Descriptions and supporting lines — the workhorse secondary.
  final Color textSecondary;

  /// Hints, captions, stat hints, placeholders.
  final Color textMuted;

  /// Text on a saturated or dark fill.
  final Color onDark;

  // Buttons -------------------------------------------------------------------

  final Color secondaryFill;
  final Color secondaryHover;
  final Color onSecondary;
  final Color outlineFill;
  final Color outlineHover;
  final Color onOutline;
  final Color ghostHover;
  final Color onGhost;
  final Color dangerFill;
  final Color dangerHover;

  // Form controls -------------------------------------------------------------

  final Color inputFill;
  final Color inputDisabledFill;
  final Color inputBorder;
  final Color inputFocusBorder;
  final Color inputErrorBorder;
  final Color inputErrorFocusBorder;
  final Color fieldError;
  final Color focusRing;

  // Navigation ----------------------------------------------------------------

  final Color navLabel;
  final Color navActiveFill;
  final Color navActiveLabel;

  /// The 4 × 24 rail flush to the left edge of an active drawer item, and the
  /// selected indicator in a bottom bar. Meaning is never colour alone, so this
  /// is a *shape* as well as a hue.
  final Color navActiveRail;

  // Feedback ------------------------------------------------------------------

  final Color skeletonBase;
  final Color skeletonHighlight;
  final Color scrim;
  final Color selectionBackground;
  final Color selectionForeground;

  // Elevation -----------------------------------------------------------------

  final List<BoxShadow> cardShadow;
  final List<BoxShadow> elevatedShadow;
  final List<BoxShadow> modalShadow;
  final List<BoxShadow> subtleShadow;

  // Status tones --------------------------------------------------------------

  final SrToneColors emerald;
  final SrToneColors amber;
  final SrToneColors red;
  final SrToneColors blue;
  final SrToneColors indigo;
  final SrToneColors slate;

  /// Resolves [tone] against this scheme.
  SrToneColors tone(SrTone tone) => switch (tone) {
    SrTone.emerald => emerald,
    SrTone.amber => amber,
    SrTone.red => red,
    SrTone.blue => blue,
    SrTone.indigo => indigo,
    SrTone.slate => slate,
  };

  bool get isDark => brightness == Brightness.dark;

  // ---------------------------------------------------------------------------
  // Light — a transcription of the shipped web app
  // ---------------------------------------------------------------------------

  static final SrColorScheme light = SrColorScheme(
    brightness: Brightness.light,
    background: SrPalette.slate50,
    backgroundSecondary: SrPalette.slate100,
    surface: SrPalette.white,
    surfaceMuted: SrPalette.slate50,
    // White. See the doc comment on [surfaceNav].
    surfaceNav: SrPalette.white,
    surfaceAppBar: SrPalette.white.withValues(alpha: 0.85),
    border: SrPalette.slate200,
    borderStrong: SrPalette.slate300,
    brand: SrPalette.indigo600,
    brandHover: SrPalette.indigo700,
    brandSoft: SrPalette.indigo50,
    onBrandSoft: SrPalette.indigo700,
    onBrand: SrPalette.white,
    accent: SrPalette.violet600,
    foreground: SrPalette.slate900,
    textLabel: SrPalette.slate800,
    textBody: SrPalette.slate600,
    textSecondary: SrPalette.slate500,
    textMuted: SrPalette.slate400,
    onDark: SrPalette.white,
    secondaryFill: SrPalette.slate900,
    secondaryHover: SrPalette.slate800,
    onSecondary: SrPalette.white,
    outlineFill: SrPalette.white,
    outlineHover: SrPalette.slate50,
    onOutline: SrPalette.slate700,
    ghostHover: SrPalette.slate100,
    onGhost: SrPalette.slate600,
    dangerFill: SrPalette.red600,
    dangerHover: SrPalette.red700,
    inputFill: SrPalette.white,
    inputDisabledFill: SrPalette.slate50,
    inputBorder: SrPalette.slate300,
    inputFocusBorder: SrPalette.indigo500,
    inputErrorBorder: SrPalette.red400,
    inputErrorFocusBorder: SrPalette.red500,
    fieldError: SrPalette.red700,
    focusRing: SrPalette.indigo500,
    navLabel: SrPalette.slate600,
    navActiveFill: SrPalette.indigo50,
    navActiveLabel: SrPalette.indigo700,
    navActiveRail: SrPalette.indigo600,
    skeletonBase: SrPalette.slate200,
    skeletonHighlight: SrPalette.white.withValues(alpha: 0.65),
    scrim: SrPalette.slate900.withValues(alpha: 0.4),
    selectionBackground: SrPalette.indigo200,
    selectionForeground: SrPalette.indigo950,
    cardShadow: _shadow(SrPalette.slate900, _cardStops),
    elevatedShadow: _shadow(SrPalette.slate900, _elevatedStops),
    modalShadow: _shadow(SrPalette.slate900, _modalStops),
    subtleShadow: _shadow(SrPalette.black, _subtleStops),
    emerald: const SrToneColors(
      fill: SrPalette.emerald50,
      foreground: SrPalette.emerald700,
      ring: Color(0x33009966),
      border: SrPalette.emerald200,
      alertText: SrPalette.emerald900,
      discFill: SrPalette.emerald100,
    ),
    amber: const SrToneColors(
      fill: SrPalette.amber50,
      foreground: SrPalette.amber700,
      ring: Color(0x33E17100),
      border: SrPalette.amber200,
      alertText: SrPalette.amber900,
      discFill: SrPalette.amber100,
    ),
    red: const SrToneColors(
      fill: SrPalette.red50,
      foreground: SrPalette.red700,
      ring: Color(0x33E7000B),
      border: SrPalette.red200,
      // red-800, the one documented exception, for contrast on red-50.
      alertText: SrPalette.red800,
      discFill: SrPalette.red100,
    ),
    blue: const SrToneColors(
      fill: SrPalette.blue50,
      foreground: SrPalette.blue700,
      ring: Color(0x33155DFC),
      border: SrPalette.blue200,
      alertText: SrPalette.blue900,
      discFill: SrPalette.blue100,
    ),
    indigo: const SrToneColors(
      fill: SrPalette.indigo50,
      foreground: SrPalette.indigo700,
      ring: Color(0x334F39F6),
      border: SrPalette.indigo200,
      alertText: SrPalette.indigo900,
      discFill: SrPalette.indigo100,
    ),
    slate: const SrToneColors(
      fill: SrPalette.slate100,
      foreground: SrPalette.slate600,
      ring: Color(0x3362748E),
      border: SrPalette.slate200,
      alertText: SrPalette.slate900,
      discFill: SrPalette.slate100,
    ),
  );

  // ---------------------------------------------------------------------------
  // Dark — the same identity, re-mapped
  // ---------------------------------------------------------------------------

  static final SrColorScheme dark = SrColorScheme(
    brightness: Brightness.dark,
    background: SrPalette.slate950,
    backgroundSecondary: SrPalette.slate900,
    surface: SrPalette.slate900,
    surfaceMuted: SrPalette.slate800,
    surfaceNav: SrPalette.slate900,
    surfaceAppBar: SrPalette.slate900.withValues(alpha: 0.85),
    border: SrPalette.slate800,
    borderStrong: SrPalette.slate700,
    // indigo-500 rather than -600: a brand fill needs to separate from a very
    // dark field, and white on indigo-500 still clears AA at 4.67:1.
    brand: SrPalette.indigo500,
    brandHover: SrPalette.indigo400,
    brandSoft: SrPalette.indigo950,
    onBrandSoft: SrPalette.indigo300,
    onBrand: SrPalette.white,
    accent: SrPalette.violet400,
    foreground: SrPalette.slate50,
    textLabel: SrPalette.slate200,
    textBody: SrPalette.slate300,
    textSecondary: SrPalette.slate300,
    // slate-400, not slate-500: on slate-950 the 500 step falls to 4.2:1.
    textMuted: SrPalette.slate400,
    onDark: SrPalette.white,
    // The light "secondary" is a near-black solid. On dark that would vanish,
    // so it becomes a near-white solid — the same role, the opposite end of the
    // same slate ramp.
    secondaryFill: SrPalette.slate100,
    secondaryHover: SrPalette.white,
    onSecondary: SrPalette.slate900,
    outlineFill: SrPalette.slate900,
    outlineHover: SrPalette.slate800,
    onOutline: SrPalette.slate200,
    ghostHover: SrPalette.slate800,
    onGhost: SrPalette.slate300,
    dangerFill: SrPalette.red600,
    dangerHover: SrPalette.red500,
    inputFill: SrPalette.slate800,
    inputDisabledFill: SrPalette.slate900,
    inputBorder: SrPalette.slate700,
    inputFocusBorder: SrPalette.indigo400,
    inputErrorBorder: SrPalette.red400,
    inputErrorFocusBorder: SrPalette.red300,
    fieldError: SrPalette.red300,
    focusRing: SrPalette.indigo400,
    navLabel: SrPalette.slate400,
    navActiveFill: SrPalette.indigo950,
    navActiveLabel: SrPalette.indigo300,
    navActiveRail: SrPalette.indigo400,
    skeletonBase: SrPalette.slate800,
    skeletonHighlight: SrPalette.white.withValues(alpha: 0.08),
    scrim: SrPalette.black.withValues(alpha: 0.6),
    selectionBackground: SrPalette.indigo900,
    selectionForeground: SrPalette.indigo100,
    // On a dark field a slate-tinted shadow is invisible, so the tint moves to
    // black and the alphas roughly double. The geometry is unchanged, which is
    // what keeps the elevation *language* the same.
    cardShadow: _shadow(SrPalette.black, _cardStops, alphaScale: 2.5),
    elevatedShadow: _shadow(SrPalette.black, _elevatedStops, alphaScale: 2.5),
    modalShadow: _shadow(SrPalette.black, _modalStops, alphaScale: 1.8),
    subtleShadow: _shadow(SrPalette.black, _subtleStops, alphaScale: 2),
    emerald: const SrToneColors(
      fill: SrPalette.emerald950,
      foreground: SrPalette.emerald300,
      ring: Color(0x4D00D492),
      border: SrPalette.emerald900,
      alertText: SrPalette.emerald100,
      discFill: SrPalette.emerald900,
    ),
    amber: const SrToneColors(
      fill: SrPalette.amber950,
      foreground: SrPalette.amber300,
      ring: Color(0x4DFFB900),
      border: SrPalette.amber900,
      alertText: SrPalette.amber100,
      discFill: SrPalette.amber900,
    ),
    red: const SrToneColors(
      fill: SrPalette.red950,
      foreground: SrPalette.red300,
      ring: Color(0x4DFF6467),
      border: SrPalette.red900,
      alertText: SrPalette.red200,
      discFill: SrPalette.red900,
    ),
    blue: const SrToneColors(
      fill: SrPalette.blue950,
      foreground: SrPalette.blue300,
      ring: Color(0x4D51A2FF),
      border: SrPalette.blue900,
      alertText: SrPalette.blue200,
      discFill: SrPalette.blue900,
    ),
    indigo: const SrToneColors(
      fill: SrPalette.indigo950,
      foreground: SrPalette.indigo300,
      ring: Color(0x4D7C86FF),
      border: SrPalette.indigo900,
      alertText: SrPalette.indigo200,
      discFill: SrPalette.indigo900,
    ),
    slate: const SrToneColors(
      fill: SrPalette.slate800,
      foreground: SrPalette.slate300,
      ring: Color(0x4D90A1B9),
      border: SrPalette.slate700,
      alertText: SrPalette.slate100,
      discFill: SrPalette.slate800,
    ),
  );

  // ---------------------------------------------------------------------------
  // Shadow recipes — geometry from handoff § 2.7, tint supplied per theme
  // ---------------------------------------------------------------------------

  /// `(dy, blur, spread, alpha)` for each stop.
  static const List<(double, double, double, double)> _cardStops =
      <(double, double, double, double)>[(1, 2, 0, 0.04), (1, 3, 0, 0.06)];

  static const List<(double, double, double, double)> _elevatedStops =
      <(double, double, double, double)>[(4, 12, -2, 0.08), (2, 6, -2, 0.05)];

  static const List<(double, double, double, double)> _modalStops =
      <(double, double, double, double)>[
        (20, 40, -12, 0.22),
        (8, 16, -8, 0.12),
      ];

  /// Tailwind v4 `shadow-sm`, worn by resting buttons, inputs and avatars.
  static const List<(double, double, double, double)> _subtleStops =
      <(double, double, double, double)>[(1, 3, 0, 0.1), (1, 2, -1, 0.1)];

  static List<BoxShadow> _shadow(
    Color tint,
    List<(double, double, double, double)> stops, {
    double alphaScale = 1,
  }) {
    return <BoxShadow>[
      for (final (double dy, double blur, double spread, double alpha) stop
          in stops)
        BoxShadow(
          color: tint.withValues(alpha: (stop.$4 * alphaScale).clamp(0.0, 1.0)),
          offset: Offset(0, stop.$1),
          blurRadius: stop.$2,
          spreadRadius: stop.$3,
        ),
    ];
  }

  @override
  SrColorScheme copyWith() => this;

  @override
  SrColorScheme lerp(ThemeExtension<SrColorScheme>? other, double t) {
    if (other is! SrColorScheme) {
      return this;
    }
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    List<BoxShadow> s(List<BoxShadow> a, List<BoxShadow> b) =>
        BoxShadow.lerpList(a, b, t)!;

    return SrColorScheme(
      brightness: t < 0.5 ? brightness : other.brightness,
      background: c(background, other.background),
      backgroundSecondary: c(backgroundSecondary, other.backgroundSecondary),
      surface: c(surface, other.surface),
      surfaceMuted: c(surfaceMuted, other.surfaceMuted),
      surfaceNav: c(surfaceNav, other.surfaceNav),
      surfaceAppBar: c(surfaceAppBar, other.surfaceAppBar),
      border: c(border, other.border),
      borderStrong: c(borderStrong, other.borderStrong),
      brand: c(brand, other.brand),
      brandHover: c(brandHover, other.brandHover),
      brandSoft: c(brandSoft, other.brandSoft),
      onBrandSoft: c(onBrandSoft, other.onBrandSoft),
      onBrand: c(onBrand, other.onBrand),
      accent: c(accent, other.accent),
      foreground: c(foreground, other.foreground),
      textLabel: c(textLabel, other.textLabel),
      textBody: c(textBody, other.textBody),
      textSecondary: c(textSecondary, other.textSecondary),
      textMuted: c(textMuted, other.textMuted),
      onDark: c(onDark, other.onDark),
      secondaryFill: c(secondaryFill, other.secondaryFill),
      secondaryHover: c(secondaryHover, other.secondaryHover),
      onSecondary: c(onSecondary, other.onSecondary),
      outlineFill: c(outlineFill, other.outlineFill),
      outlineHover: c(outlineHover, other.outlineHover),
      onOutline: c(onOutline, other.onOutline),
      ghostHover: c(ghostHover, other.ghostHover),
      onGhost: c(onGhost, other.onGhost),
      dangerFill: c(dangerFill, other.dangerFill),
      dangerHover: c(dangerHover, other.dangerHover),
      inputFill: c(inputFill, other.inputFill),
      inputDisabledFill: c(inputDisabledFill, other.inputDisabledFill),
      inputBorder: c(inputBorder, other.inputBorder),
      inputFocusBorder: c(inputFocusBorder, other.inputFocusBorder),
      inputErrorBorder: c(inputErrorBorder, other.inputErrorBorder),
      inputErrorFocusBorder: c(
        inputErrorFocusBorder,
        other.inputErrorFocusBorder,
      ),
      fieldError: c(fieldError, other.fieldError),
      focusRing: c(focusRing, other.focusRing),
      navLabel: c(navLabel, other.navLabel),
      navActiveFill: c(navActiveFill, other.navActiveFill),
      navActiveLabel: c(navActiveLabel, other.navActiveLabel),
      navActiveRail: c(navActiveRail, other.navActiveRail),
      skeletonBase: c(skeletonBase, other.skeletonBase),
      skeletonHighlight: c(skeletonHighlight, other.skeletonHighlight),
      scrim: c(scrim, other.scrim),
      selectionBackground: c(selectionBackground, other.selectionBackground),
      selectionForeground: c(selectionForeground, other.selectionForeground),
      cardShadow: s(cardShadow, other.cardShadow),
      elevatedShadow: s(elevatedShadow, other.elevatedShadow),
      modalShadow: s(modalShadow, other.modalShadow),
      subtleShadow: s(subtleShadow, other.subtleShadow),
      emerald: SrToneColors.lerp(emerald, other.emerald, t),
      amber: SrToneColors.lerp(amber, other.amber, t),
      red: SrToneColors.lerp(red, other.red, t),
      blue: SrToneColors.lerp(blue, other.blue, t),
      indigo: SrToneColors.lerp(indigo, other.indigo, t),
      slate: SrToneColors.lerp(slate, other.slate, t),
    );
  }
}

/// Reads the SalesReward colour layer for the current theme.
///
/// Falls back to [SrColorScheme.light] rather than throwing, so a design-system
/// widget rendered in a bare `MaterialApp` (a test harness, a widget preview)
/// still draws correctly instead of crashing.
extension SrColorSchemeContext on BuildContext {
  SrColorScheme get sr =>
      Theme.of(this).extension<SrColorScheme>() ?? SrColorScheme.light;
}
