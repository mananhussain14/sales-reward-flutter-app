import 'package:flutter/material.dart';

/// The raw SalesReward colour scale.
///
/// Every value is a **Tailwind CSS v4** step as it actually renders in the
/// shipped web app, transcribed from § 2.2–2.5 of
/// `docs/mobile-ui-design-handoff.md`.
///
/// ## Why v4 and not the familiar v3 hexes
///
/// The web project is on Tailwind v4, whose default palette is defined in OKLCH
/// and resolves to **different sRGB values** than the v3 hexes most people have
/// memorised. `slate-500` is `#62748E`, not `#64748B`; `indigo-600` is
/// `#4F39F6`, not `#4F46E5`. Using the v3 values would produce an app that is
/// subtly but consistently the wrong colour.
///
/// The handoff records one deliberate exception, tracked as decision **D-1**:
/// the brand mark's SVG carries hard-coded v3-era literals that were never
/// updated. Until D-1 is answered the instruction is to reproduce exactly what
/// ships today — v4 steps for the interface, the literals for the mark — so
/// those literals live in [SrBrandLiterals] and are used nowhere else.
///
/// ## Dark steps
///
/// The web is light-only and therefore supplies no dark palette. The dark steps
/// below (`*300`, `*400`, `*900`, `*950`) are further steps of the **same
/// Tailwind v4 families**, not invented colours — so the dark theme is a
/// counterpart of the same identity rather than a second identity. See
/// [SrColorScheme.dark] for how they are assigned and
/// `docs/flutter-application-foundation.md` for the contrast audit.
abstract final class SrPalette {
  // ---------------------------------------------------------------------------
  // Slate — surfaces, borders and text
  // ---------------------------------------------------------------------------

  static const Color slate50 = Color(0xFFF8FAFC);
  static const Color slate100 = Color(0xFFF1F5F9);
  static const Color slate200 = Color(0xFFE2E8F0);
  static const Color slate300 = Color(0xFFCAD5E2);
  static const Color slate400 = Color(0xFF90A1B9);
  static const Color slate500 = Color(0xFF62748E);
  static const Color slate600 = Color(0xFF45556C);
  static const Color slate700 = Color(0xFF314158);
  static const Color slate800 = Color(0xFF1D293D);
  static const Color slate900 = Color(0xFF0F172B);
  static const Color slate950 = Color(0xFF020618);

  // ---------------------------------------------------------------------------
  // Indigo — the primary brand hue
  // ---------------------------------------------------------------------------

  static const Color indigo50 = Color(0xFFEEF2FF);
  static const Color indigo100 = Color(0xFFE0E7FF);
  static const Color indigo200 = Color(0xFFC6D2FF);
  static const Color indigo300 = Color(0xFFA3B3FF);
  static const Color indigo400 = Color(0xFF7C86FF);
  static const Color indigo500 = Color(0xFF615FFF);
  static const Color indigo600 = Color(0xFF4F39F6);
  static const Color indigo700 = Color(0xFF432DD7);
  static const Color indigo800 = Color(0xFF372AAC);
  static const Color indigo900 = Color(0xFF312C85);
  static const Color indigo950 = Color(0xFF1E1A4D);

  // ---------------------------------------------------------------------------
  // Violet — the gradient partner for avatars and the route progress bar
  // ---------------------------------------------------------------------------

  static const Color violet400 = Color(0xFFA684FF);
  static const Color violet600 = Color(0xFF7F22FE);

  // ---------------------------------------------------------------------------
  // Emerald — success
  // ---------------------------------------------------------------------------

  static const Color emerald50 = Color(0xFFECFDF5);
  static const Color emerald100 = Color(0xFFD0FAE5);
  static const Color emerald200 = Color(0xFFA4F4CF);
  static const Color emerald300 = Color(0xFF5EE9B5);
  static const Color emerald400 = Color(0xFF00D492);
  static const Color emerald600 = Color(0xFF009966);
  static const Color emerald700 = Color(0xFF007A55);
  static const Color emerald900 = Color(0xFF004F3B);
  static const Color emerald950 = Color(0xFF002C22);

  // ---------------------------------------------------------------------------
  // Amber — warning, and the reward accent
  // ---------------------------------------------------------------------------

  static const Color amber50 = Color(0xFFFFFBEB);
  static const Color amber100 = Color(0xFFFEF3C6);
  static const Color amber200 = Color(0xFFFEE685);
  static const Color amber300 = Color(0xFFFFD230);
  static const Color amber400 = Color(0xFFFFB900);
  static const Color amber600 = Color(0xFFE17100);
  static const Color amber700 = Color(0xFFBB4D00);
  static const Color amber900 = Color(0xFF7B3306);
  static const Color amber950 = Color(0xFF461901);

  // ---------------------------------------------------------------------------
  // Red — error and destructive
  // ---------------------------------------------------------------------------

  static const Color red50 = Color(0xFFFEF2F2);
  static const Color red100 = Color(0xFFFFE2E2);
  static const Color red200 = Color(0xFFFFC9C9);
  static const Color red300 = Color(0xFFFFA2A2);
  static const Color red400 = Color(0xFFFF6467);
  static const Color red500 = Color(0xFFFB2C36);
  static const Color red600 = Color(0xFFE7000B);
  static const Color red700 = Color(0xFFC10007);
  static const Color red800 = Color(0xFF9F0712);
  static const Color red900 = Color(0xFF82181A);
  static const Color red950 = Color(0xFF460809);

  // ---------------------------------------------------------------------------
  // Blue — informational
  // ---------------------------------------------------------------------------

  static const Color blue50 = Color(0xFFEFF6FF);
  static const Color blue100 = Color(0xFFDBEAFE);
  static const Color blue200 = Color(0xFFBEDBFF);
  static const Color blue300 = Color(0xFF8EC5FF);
  static const Color blue400 = Color(0xFF51A2FF);
  static const Color blue600 = Color(0xFF155DFC);
  static const Color blue700 = Color(0xFF1447E6);
  static const Color blue900 = Color(0xFF1C398E);
  static const Color blue950 = Color(0xFF162456);

  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
}

/// The brand mark's hard-coded SVG literals.
///
/// These are **Tailwind v3-era** hexes that the web's inline SVG never migrated
/// (handoff § 2.1, decision **D-1**). They are deliberately isolated here and
/// must be used by the brand mark alone: applying them anywhere else would mix
/// the two palettes that D-1 exists to eventually reconcile.
///
/// They are also **theme-independent**. The mark is a fixed-gradient tile and
/// renders identically in light and dark, exactly as a logo should.
abstract final class SrBrandLiterals {
  /// The tile gradient, `(0,0) → (40,40)`.
  static const Color gradientStart = Color(0xFF4F46E5);
  static const Color gradientEnd = Color(0xFF7C3AED);

  /// The two shorter chart bars.
  static const Color bar1 = Color(0xFFC7D2FE);
  static const Color bar2 = Color(0xFFE0E7FF);

  /// The arrow shaft and head.
  static const Color arrow = Color(0xFFFFFFFF);

  /// The four-point reward spark.
  static const Color spark = Color(0xFFF59E0B);
}
