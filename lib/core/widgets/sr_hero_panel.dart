import 'package:flutter/material.dart';

import '../design/design.dart';

/// The one brand-filled surface a screen is allowed.
///
/// ## Why exactly one, and why it is a component
///
/// A gradient on every card is noise: nothing stands out when everything does.
/// This exists so the *single* most important figure on a screen — coins earned,
/// a campaign's headline offer — can be given the brand fill, while every other
/// surface stays a plain [SrCard]. Making it a named component rather than a
/// decoration recipe is what keeps that budget of one enforceable in review.
///
/// ## Contrast is not left to a gradient
///
/// The fill runs between [SrColorScheme.brand] and [SrColorScheme.brandHover] —
/// two steps of one ramp, not two hues — and every child is rendered in
/// [SrColorScheme.onBrand], which is the foreground the palette already pairs
/// with both. A gradient between distant colours would leave the text passing
/// contrast at one end of the panel and failing at the other.
class SrHeroPanel extends StatelessWidget {
  const SrHeroPanel({
    super.key,
    required this.child,
    this.icon,
    this.padding = const EdgeInsets.all(SrSpacing.xxl),
  });

  final Widget child;

  /// A watermark glyph, bled into the top-right corner. Decorative only, and
  /// excluded from semantics — every meaning on this panel is in its text.
  final IconData? icon;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final BorderRadius radius = BorderRadius.circular(SrRadii.surface);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: sr.elevatedShadow,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[sr.brand, sr.brandHover],
            ),
          ),
          child: Stack(
            children: <Widget>[
              if (icon != null)
                Positioned(
                  top: -SrSpacing.xxl,
                  right: -SrSpacing.xl,
                  child: ExcludeSemantics(
                    child: Icon(
                      icon,
                      size: 160,
                      // Low enough that the watermark never competes with the
                      // figure it sits behind.
                      color: sr.onBrand.withValues(alpha: 0.10),
                    ),
                  ),
                ),
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// A label-over-value pair, sized for a hero panel's supporting row.
///
/// Rendered in [SrColorScheme.onBrand] at two opacities rather than in two
/// palette colours, because the panel it sits on is brand-filled and the
/// ordinary text ramp is tuned for a light surface.
class SrHeroFact extends StatelessWidget {
  const SrHeroFact({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: SrTypography.caption.copyWith(
            color: sr.onBrand.withValues(alpha: 0.78),
          ),
        ),
        const SizedBox(height: SrSpacing.xxs),
        Text(value, style: SrTypography.bodyLarge.copyWith(color: sr.onBrand)),
      ],
    );
  }
}
