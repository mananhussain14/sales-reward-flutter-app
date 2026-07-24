import 'package:flutter/material.dart';

/// Motion, transcribed from § 2.12 of `docs/mobile-ui-design-handoff.md`.
///
/// The product's motion is deliberately restrained: a 220 ms fade for arriving
/// content, 150 ms for interactive state changes, and a 1.4 s skeleton shimmer.
/// Material's longer defaults would make the app feel like a different product.
///
/// Only the durations this milestone actually animates are declared. The web
/// also defines a 280 ms success "pop" and a one-shot login line draw; neither
/// has a counterpart here yet, and a token for an animation that does not exist
/// is a token that will drift before it is used.
///
/// **Reduced motion is honoured globally on the web** — every duration collapses
/// to ~0 and the skeleton shimmer is removed entirely, while the surface that
/// carried it stays. Feedback is preserved; only the movement is dropped. Use
/// [respects] to make the same decision in Flutter.
abstract final class SrMotion {
  /// `duration-150` — hover, press and selection changes.
  static const Duration fast = Duration(milliseconds: 150);

  /// `sr-animate-fade-in` — 220 ms, content arriving.
  static const Duration medium = Duration(milliseconds: 220);

  /// `sr-skeleton` — the shimmer sweep, 1.4 s linear and looping.
  static const Duration shimmer = Duration(milliseconds: 1400);

  static const Curve standard = Curves.easeOut;

  /// Whether animation should run at all for this user.
  ///
  /// Checks both the platform's reduce-motion setting and the
  /// accessible-navigation flag, matching the web's `prefers-reduced-motion`
  /// media query.
  ///
  /// A widget that returns false here must still render its **state** — a
  /// static skeleton block, the settled end of a fade — never nothing at all.
  static bool respects(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    return !media.disableAnimations && !media.accessibleNavigation;
  }
}
