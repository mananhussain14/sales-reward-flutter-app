import 'package:flutter/material.dart';

/// Motion, transcribed from § 2.12 of `docs/mobile-ui-design-handoff.md`.
///
/// The product's motion is deliberately restrained: a 220 ms fade for arriving
/// content, a 280 ms spring for a success confirmation, 150 ms for interactive
/// state changes, and a 1.4 s skeleton shimmer. Material's longer defaults would
/// make the app feel like a different product.
///
/// **Reduced motion is honoured globally on the web** — every duration collapses
/// to ~0, the skeleton shimmer is removed entirely, and the route progress bar
/// becomes a *static* full-width bar rather than disappearing. That last detail
/// matters: feedback is preserved, only the movement is dropped. Use
/// [respects] to make the same decision in Flutter.
abstract final class SrMotion {
  /// `duration-150` — hover, press and selection changes.
  static const Duration fast = Duration(milliseconds: 150);

  /// The drawer slide, 200 ms `ease-in-out`.
  static const Duration drawer = Duration(milliseconds: 200);

  /// `sr-animate-fade-in` — 220 ms, content arriving.
  static const Duration medium = Duration(milliseconds: 220);

  /// `sr-animate-pop` — 280 ms, a success confirmation.
  static const Duration slow = Duration(milliseconds: 280);

  /// `sr-skeleton` — the shimmer sweep, 1.4 s linear and looping.
  static const Duration shimmer = Duration(milliseconds: 1400);

  static const Curve standard = Curves.easeOut;

  static const Curve easeInOut = Curves.easeInOut;

  /// `cubic-bezier(.34, 1.56, .64, 1)` — the overshoot used by `sr-animate-pop`.
  static const Curve pop = Cubic(0.34, 1.56, 0.64, 1);

  /// Whether animation should run at all for this user.
  ///
  /// Checks both the platform's reduce-motion setting and the
  /// accessible-navigation flag, matching the web's `prefers-reduced-motion`
  /// media query.
  ///
  /// A widget that returns false here must still render its **state** — a
  /// static skeleton block, a static progress bar — never nothing at all.
  static bool respects(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    return !media.disableAnimations && !media.accessibleNavigation;
  }
}
