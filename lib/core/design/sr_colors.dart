import 'package:flutter/material.dart';

/// The SalesReward color palette, translated from the web application's
/// `app/globals.css` custom properties and the Tailwind scales the web
/// components use directly.
///
/// The web design system documents that the Tailwind slate / indigo / emerald /
/// amber scales **are** the brand palette — there is no bespoke color layer to
/// drift from. This file is the Dart mirror of that decision: the raw scale
/// steps the web components reference by class name are named here once, and the
/// semantic aliases below map them to roles exactly as `:root` does in CSS.
///
/// The product is deliberately LIGHT-ONLY for this milestone, matching
/// `html { color-scheme: light }` on the web. No dark palette is defined,
/// because defining one would invite a second visual identity to appear.
abstract final class SrColors {
  // ---------------------------------------------------------------------------
  // Raw scale steps
  //
  // Only the steps the web components actually use are listed. Adding an unused
  // step invites a component to reach for a shade the web never renders.
  // ---------------------------------------------------------------------------

  static const Color slate50 = Color(0xFFF8FAFC);
  static const Color slate100 = Color(0xFFF1F5F9);
  static const Color slate200 = Color(0xFFE2E8F0);
  static const Color slate300 = Color(0xFFCBD5E1);
  static const Color slate400 = Color(0xFF94A3B8);
  static const Color slate500 = Color(0xFF64748B);
  static const Color slate600 = Color(0xFF475569);
  static const Color slate700 = Color(0xFF334155);
  static const Color slate800 = Color(0xFF1E293B);
  static const Color slate900 = Color(0xFF0F172A);

  static const Color indigo50 = Color(0xFFEEF2FF);
  static const Color indigo100 = Color(0xFFE0E7FF);
  static const Color indigo200 = Color(0xFFC7D2FE);
  static const Color indigo300 = Color(0xFFA5B4FC);
  static const Color indigo500 = Color(0xFF6366F1);
  static const Color indigo600 = Color(0xFF4F46E5);
  static const Color indigo700 = Color(0xFF4338CA);
  static const Color indigo950 = Color(0xFF1E1B4B);

  static const Color violet600 = Color(0xFF7C3AED);

  static const Color emerald50 = Color(0xFFECFDF5);
  static const Color emerald100 = Color(0xFFD1FAE5);
  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald700 = Color(0xFF047857);

  static const Color amber50 = Color(0xFFFFFBEB);
  static const Color amber100 = Color(0xFFFEF3C7);
  static const Color amber500 = Color(0xFFF59E0B);
  static const Color amber600 = Color(0xFFD97706);
  static const Color amber700 = Color(0xFFB45309);

  static const Color blue50 = Color(0xFFEFF6FF);
  static const Color blue700 = Color(0xFF1D4ED8);

  static const Color red50 = Color(0xFFFEF2F2);
  static const Color red100 = Color(0xFFFEE2E2);
  static const Color red400 = Color(0xFFF87171);
  static const Color red600 = Color(0xFFDC2626);
  static const Color red700 = Color(0xFFB91C1C);

  static const Color white = Color(0xFFFFFFFF);

  // ---------------------------------------------------------------------------
  // Semantic aliases — the Dart equivalent of the `:root` block in globals.css.
  // Components should prefer these over the raw steps above.
  // ---------------------------------------------------------------------------

  /// `--app-background` — the page surface behind every screen.
  static const Color appBackground = slate50;

  /// `--app-background-secondary` — a recessed band inside a page.
  static const Color appBackgroundSecondary = slate100;

  /// `--surface` — cards, sheets, dialogs, inputs.
  static const Color surface = white;

  /// `--surface-nav` — the dark navigation chrome (web sidebar; mobile drawer).
  static const Color surfaceNav = slate900;

  /// `--border` — the hairline around every card.
  static const Color border = slate200;

  /// `--border-strong` — form control borders and dashed empty-state outlines.
  static const Color borderStrong = slate300;

  /// `--brand` — the primary action color.
  static const Color brand = indigo600;

  /// `--brand-hover` — the pressed / hovered primary.
  static const Color brandHover = indigo700;

  /// `--brand-soft` — a tinted brand surface (eyebrows, soft discs).
  static const Color brandSoft = indigo50;

  /// `--foreground` — primary body and heading text.
  static const Color foreground = slate900;

  /// `--text-secondary` — supporting text and inactive navigation labels.
  static const Color textSecondary = slate600;

  /// `--text-muted` — descriptions, hints, captions.
  static const Color textMuted = slate500;

  /// The brand mark's indigo → violet gradient, used by the logo tile only.
  static const List<Color> brandGradient = <Color>[indigo600, violet600];

  /// The amber "reward spark" accent inside the brand mark.
  static const Color brandSpark = amber500;

  /// Text-selection colors from `::selection` in globals.css.
  static const Color selectionBackground = indigo200;
  static const Color selectionForeground = indigo950;

  /// The skeleton base color (`.sr-skeleton { background-color: slate-200 }`).
  static const Color skeletonBase = slate200;

  /// The highlight sweep in the skeleton shimmer gradient.
  static const Color skeletonHighlight = Color(0xA6FFFFFF); // white @ 65%
}
