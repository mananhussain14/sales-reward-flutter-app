import 'package:flutter/material.dart';

import 'sr_colors.dart';

/// The typography hierarchy, translated from the web application's Tailwind
/// classes.
///
/// ## Font family
///
/// The web app loads Geist Sans through `next/font/google` and declares this
/// fallback stack in `globals.css`:
///
/// ```
/// var(--font-geist-sans), ui-sans-serif, system-ui, -apple-system,
/// "Segoe UI", Roboto, Arial, sans-serif
/// ```
///
/// This milestone deliberately ships **no bundled font asset and no network
/// font fetch**, so the app renders the platform sans-serif — which is exactly
/// the documented fallback the web app itself uses when Geist has not loaded.
/// The proportions, weights and letter-spacing below are what actually carry the
/// hierarchy, and they are reproduced exactly. Bundling Geist as an asset is a
/// self-contained follow-up: set [fontFamily] and nothing else changes.
///
/// ## Scale
///
/// Every size below is a Tailwind step the web components use, with the line
/// height Tailwind pairs with it and the `tracking-*` value converted from `em`
/// to logical pixels at that size.
abstract final class SrTypography {
  /// Left null so Flutter resolves the platform sans-serif — the same outcome
  /// as the web's fallback stack. Set this once Geist ships as a bundled asset.
  static const String? fontFamily = null;

  /// `text-2xl font-semibold tracking-tight` — the page title in `PageHeader`.
  /// 24px / 32px, -0.025em → -0.6px.
  static const TextStyle pageTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    height: 32 / 24,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.6,
    color: SrColors.foreground,
  );

  /// `text-xl font-semibold tracking-tight` — the heading on a standalone card
  /// screen such as access-denied. 20px / 28px, -0.5px.
  static const TextStyle screenTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    height: 28 / 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.5,
    color: SrColors.foreground,
  );

  /// `text-lg font-semibold tracking-tight` — `SectionHeader`.
  /// 18px / 28px, -0.45px.
  static const TextStyle sectionTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    height: 28 / 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.45,
    color: SrColors.foreground,
  );

  /// `text-base font-semibold` — the title inside a `SectionCard` or
  /// `StatusCard`. 16px / 24px.
  static const TextStyle cardTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w600,
    color: SrColors.foreground,
  );

  /// `text-base` — body copy at the large step. 16px / 24px.
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
    color: SrColors.foreground,
  );

  /// `text-sm` — the product's default body size. 14px / 20px.
  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
    color: SrColors.foreground,
  );

  /// `text-sm text-slate-500` — descriptions under a title.
  static const TextStyle bodyMuted = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
    color: SrColors.textMuted,
  );

  /// `text-sm font-medium text-slate-800` — a form field label.
  static const TextStyle label = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w500,
    color: SrColors.slate800,
  );

  /// `text-sm font-semibold` — button text at the `sm` and `md` sizes.
  static const TextStyle button = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w600,
  );

  /// `text-base font-semibold` — button text at the `lg` size.
  static const TextStyle buttonLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w600,
  );

  /// `text-xs text-slate-500` — a field hint or caption. 12px / 16px.
  static const TextStyle caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
    color: SrColors.textMuted,
  );

  /// `text-xs font-medium` — the label inside a status badge.
  static const TextStyle badge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w500,
  );

  /// `text-xs font-semibold uppercase tracking-wide text-indigo-600` — the
  /// eyebrow above a page title. 0.05em → +0.6px. Callers uppercase the string.
  static const TextStyle eyebrow = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
    color: SrColors.brand,
  );

  /// `text-[0.7rem] font-medium uppercase tracking-wide text-slate-500` — the
  /// portal caption under the brand wordmark ("Vendor Admin"). 11.2px.
  static const TextStyle brandContext = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11.2,
    height: 16 / 11.2,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.56,
    color: SrColors.textMuted,
  );

  /// `text-[0.95rem] font-semibold tracking-tight` — the "SalesReward"
  /// wordmark. 15.2px.
  static const TextStyle wordmark = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15.2,
    height: 1.1,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.38,
    color: SrColors.foreground,
  );

  /// `text-sm font-medium text-red-700` — a field-level validation error.
  static const TextStyle fieldError = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w500,
    color: SrColors.red700,
  );

  /// The Material [TextTheme] the app theme is built from. Each slot is mapped
  /// to the closest step in the scale above so that any Material widget which
  /// resolves typography from the theme still lands on a documented style.
  static const TextTheme textTheme = TextTheme(
    displayLarge: pageTitle,
    displayMedium: pageTitle,
    displaySmall: screenTitle,
    headlineLarge: pageTitle,
    headlineMedium: screenTitle,
    headlineSmall: sectionTitle,
    titleLarge: sectionTitle,
    titleMedium: cardTitle,
    titleSmall: label,
    bodyLarge: bodyLarge,
    bodyMedium: body,
    bodySmall: caption,
    labelLarge: button,
    labelMedium: label,
    labelSmall: badge,
  );
}
