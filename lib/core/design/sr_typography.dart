import 'package:flutter/material.dart';

/// The SalesReward type scale, transcribed from § 2.11 of
/// `docs/mobile-ui-design-handoff.md`.
///
/// ## These styles carry no colour
///
/// Every style below is **geometry only** — size, weight, line height, letter
/// spacing. Colour is applied by the caller from `context.sr`, because the same
/// role is `slate-900` in light and `slate-50` in dark. Baking a colour into a
/// [TextStyle] is what makes a design system impossible to re-theme.
///
/// ## Font family
///
/// The web loads **Geist** via `next/font/google`, with the fallback chain
/// `ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, Arial`.
///
/// This milestone ships **no bundled font asset and no runtime font download**,
/// so the app renders the platform sans-serif — which is precisely the fallback
/// the web itself uses before Geist loads. The hierarchy is carried by the
/// sizes, weights and tracking below, and those are exact.
///
/// The handoff asks for Geist to be bundled; it is recorded as a required asset
/// in `docs/required-design-assets.md`. Adopting it is a one-line change:
/// set [fontFamily] and add the `.ttf` to `pubspec.yaml`.
///
/// ## Line heights
///
/// Tailwind's defaults, applied as a unitless multiplier:
/// `text-xs` 1.333 · `text-sm` 1.4286 · `text-base` 1.5 · `text-lg` 1.556 ·
/// `text-xl` 1.4 · `text-2xl` 1.333 · `text-3xl` 1.2.
/// `tracking-tight` = −0.025em, `tracking-wide` = +0.025em, converted to
/// logical pixels at each size.
abstract final class SrTypography {
  /// Null resolves the platform sans-serif. Set once Geist ships as an asset.
  static const String? fontFamily = null;

  static const double _xs = 1.3333;
  static const double _sm = 1.4286;
  static const double _base = 1.5;
  static const double _lg = 1.5556;
  static const double _xl = 1.4;
  static const double _xxl = 1.3333;
  static const double _xxxl = 1.2;

  /// `text-2xl` 24 / 600 / tracking-tight — the page title.
  static const TextStyle pageTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    height: _xxl,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.6,
  );

  /// `text-xl` 20 / 600 / tracking-tight — invitation and access-denied titles.
  static const TextStyle screenTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    height: _xl,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.5,
  );

  /// `text-lg` 18 / 600 / tracking-tight — a section heading.
  static const TextStyle sectionTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    height: _lg,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.45,
  );

  /// `text-base` 16 / 600 — a card title, and the app-bar title.
  static const TextStyle cardTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    height: _base,
    fontWeight: FontWeight.w600,
  );

  /// `text-3xl` 30 / 600 / tabular — a stat value.
  static const TextStyle statValue = TextStyle(
    fontFamily: fontFamily,
    fontSize: 30,
    height: _xxxl,
    fontWeight: FontWeight.w600,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  /// `text-lg` 18 / 500 — a stat value that could not be read ("Unavailable").
  static const TextStyle statUnavailable = TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    height: _lg,
    fontWeight: FontWeight.w500,
  );

  /// `text-base` 16 / 400.
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    height: _base,
    fontWeight: FontWeight.w400,
  );

  /// `text-sm` 14 / 400 — the product's default body size.
  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    height: _sm,
    fontWeight: FontWeight.w400,
  );

  /// `text-sm` 14 / 500 — a form field label, a nav item, an identity name.
  static const TextStyle label = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    height: _sm,
    fontWeight: FontWeight.w500,
  );

  /// `text-sm` 14 / 600 — a button label at `sm` and `md`.
  static const TextStyle button = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    height: _sm,
    fontWeight: FontWeight.w600,
  );

  /// `text-base` 16 / 600 — a button label at `lg`.
  static const TextStyle buttonLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    height: _base,
    fontWeight: FontWeight.w600,
  );

  /// `text-xs` 12 / 400 — a hint or caption.
  static const TextStyle caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    height: _xs,
    fontWeight: FontWeight.w400,
  );

  /// `text-xs` 12 / 500 — a status badge label.
  static const TextStyle badge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    height: _xs,
    fontWeight: FontWeight.w500,
  );

  /// `text-xs` 12 / 600 / uppercase / tracking-wide — the eyebrow above a page
  /// title. Callers uppercase the string themselves.
  static const TextStyle eyebrow = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    height: _xs,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
  );

  /// 15.2 / 600 / tracking-tight — the "SalesReward" wordmark.
  static const TextStyle wordmark = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15.2,
    height: 1.15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.38,
  );

  /// 11.2 / 500 / uppercase / tracking-wide — the portal caption under the
  /// wordmark, and the stage-indicator label.
  static const TextStyle brandContext = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11.2,
    height: 1.4,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.28,
  );

  /// 10 / 600 / uppercase / tracking-wide — the "Soon" pill on a disabled nav
  /// item.
  static const TextStyle soonPill = TextStyle(
    fontFamily: fontFamily,
    fontSize: 10,
    height: 1.4,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.25,
  );

  /// `text-sm` 14 / 500 — a field-level validation error.
  static const TextStyle fieldError = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    height: _sm,
    fontWeight: FontWeight.w500,
  );

  /// The Material [TextTheme], with [foreground] applied to the primary slots
  /// and [secondary] to the supporting ones, so any stock Material widget still
  /// lands on a documented style in whichever theme is active.
  static TextTheme textTheme({
    required Color foreground,
    required Color secondary,
  }) {
    return TextTheme(
      displayLarge: pageTitle.copyWith(color: foreground),
      displayMedium: pageTitle.copyWith(color: foreground),
      displaySmall: screenTitle.copyWith(color: foreground),
      headlineLarge: pageTitle.copyWith(color: foreground),
      headlineMedium: screenTitle.copyWith(color: foreground),
      headlineSmall: sectionTitle.copyWith(color: foreground),
      titleLarge: sectionTitle.copyWith(color: foreground),
      titleMedium: cardTitle.copyWith(color: foreground),
      titleSmall: label.copyWith(color: foreground),
      bodyLarge: bodyLarge.copyWith(color: foreground),
      bodyMedium: body.copyWith(color: foreground),
      bodySmall: caption.copyWith(color: secondary),
      labelLarge: button.copyWith(color: foreground),
      labelMedium: label.copyWith(color: foreground),
      labelSmall: badge.copyWith(color: secondary),
    );
  }
}
