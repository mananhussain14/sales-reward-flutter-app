import 'package:flutter/material.dart';

import 'sr_colors.dart';

/// The elevation system, translated from the `@theme inline` block in the web
/// application's `app/globals.css`.
///
/// The web deliberately avoids heavy black shadows: every layer is tinted with
/// slate-900 at a low alpha, which is what makes the product read as "premium
/// light" rather than "Material default". Flutter's `BoxShadow.blurRadius` is
/// defined to match the CSS blur radius, and `spreadRadius` matches the CSS
/// spread, so each stop below is a direct one-to-one translation.
abstract final class SrShadows {
  /// The slate-900 tint every shadow is built from, rather than pure black.
  static Color _slate(double opacity) =>
      SrColors.slate900.withValues(alpha: opacity);

  /// `--shadow-card` — the resting elevation of every card surface.
  ///
  /// `0 1px 2px 0 rgb(15 23 42 / .04), 0 1px 3px 0 rgb(15 23 42 / .06)`
  static final List<BoxShadow> card = <BoxShadow>[
    BoxShadow(color: _slate(0.04), offset: const Offset(0, 1), blurRadius: 2),
    BoxShadow(color: _slate(0.06), offset: const Offset(0, 1), blurRadius: 3),
  ];

  /// `--shadow-elevated` — a card lifted by hover, or a pressed primary button.
  ///
  /// `0 4px 12px -2px rgb(15 23 42 / .08), 0 2px 6px -2px rgb(15 23 42 / .05)`
  static final List<BoxShadow> elevated = <BoxShadow>[
    BoxShadow(
      color: _slate(0.08),
      offset: const Offset(0, 4),
      blurRadius: 12,
      spreadRadius: -2,
    ),
    BoxShadow(
      color: _slate(0.05),
      offset: const Offset(0, 2),
      blurRadius: 6,
      spreadRadius: -2,
    ),
  ];

  /// `--shadow-modal` — dialogs and bottom sheets.
  ///
  /// `0 20px 40px -12px rgb(15 23 42 / .22), 0 8px 16px -8px rgb(15 23 42 / .12)`
  static final List<BoxShadow> modal = <BoxShadow>[
    BoxShadow(
      color: _slate(0.22),
      offset: const Offset(0, 20),
      blurRadius: 40,
      spreadRadius: -12,
    ),
    BoxShadow(
      color: _slate(0.12),
      offset: const Offset(0, 8),
      blurRadius: 16,
      spreadRadius: -8,
    ),
  ];

  /// `--shadow-brand` — an indigo glow reserved for the primary call to action.
  ///
  /// `0 8px 24px -6px rgb(79 70 229 / .35)`
  static final List<BoxShadow> brand = <BoxShadow>[
    BoxShadow(
      color: SrColors.brand.withValues(alpha: 0.35),
      offset: const Offset(0, 8),
      blurRadius: 24,
      spreadRadius: -6,
    ),
  ];

  /// Tailwind's `shadow-sm`, worn by resting buttons and form controls.
  ///
  /// `0 1px 2px 0 rgb(0 0 0 / .05)`
  static final List<BoxShadow> subtle = <BoxShadow>[
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: 0.05),
      offset: const Offset(0, 1),
      blurRadius: 2,
    ),
  ];
}

/// Motion durations and curves, translated from the web's transition utilities.
///
/// The web keeps motion restrained — 150ms on interactive state changes, 220ms
/// for a fade-in, 280ms for the one celebratory "pop". Mobile inherits the same
/// restraint rather than adopting Material's longer defaults.
abstract final class SrMotion {
  /// `duration-150` — hover / press state changes on buttons and cards.
  static const Duration fast = Duration(milliseconds: 150);

  /// `sr-fade-in` — 220ms ease-out, content arriving.
  static const Duration medium = Duration(milliseconds: 220);

  /// `sr-pop` — 280ms, a success confirmation.
  static const Duration slow = Duration(milliseconds: 280);

  /// `sr-shimmer` — the skeleton sweep, 1.4s linear and infinite.
  static const Duration shimmer = Duration(milliseconds: 1400);

  static const Curve standard = Curves.easeOut;

  /// `cubic-bezier(0.34, 1.56, 0.64, 1)` — the overshoot used by `sr-pop`.
  static const Curve pop = Cubic(0.34, 1.56, 0.64, 1);
}
