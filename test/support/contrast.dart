import 'dart:math' as math;

import 'package:flutter/material.dart';

/// WCAG 2.1 relative luminance and contrast ratio.
///
/// Used to assert that the dark theme is genuinely accessible rather than
/// merely plausible. The formulas are from the WCAG definition of
/// [relative luminance](https://www.w3.org/TR/WCAG21/#dfn-relative-luminance)
/// and [contrast ratio](https://www.w3.org/TR/WCAG21/#dfn-contrast-ratio).
double relativeLuminance(Color color) {
  double channel(double value) {
    return value <= 0.04045
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

/// The contrast ratio between two opaque colours, from 1:1 to 21:1.
double contrastRatio(Color a, Color b) {
  final double la = relativeLuminance(a);
  final double lb = relativeLuminance(b);
  final double lighter = math.max(la, lb);
  final double darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

/// WCAG AA for normal-size text.
const double aaNormalText = 4.5;

/// WCAG AA for large text (≥ 18.66px bold or ≥ 24px regular) and for UI
/// component boundaries.
const double aaLargeText = 3.0;
