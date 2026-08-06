/// The richer surface vocabulary the Sales Staff experience is built from.
///
/// Three pieces, and deliberately only three. The product already has one card
/// ([SrCard]) and one brand panel ([SrHeroPanel]); what it lacked was a way to
/// make a screen feel **composed** rather than tiled — a soft ground behind the
/// content, a compact way to state a figure, and a raised surface for the one
/// thing that matters most on a screen.
///
/// Everything here is decorative. Not one of these widgets renders a value, so
/// none of them can misstate one.
library;

import 'package:flutter/material.dart';

import '../design/design.dart';

/// Two soft brand-tinted shapes behind a screen's content.
///
/// ## Why a painted backdrop rather than a gradient background
///
/// A full-page gradient tints every card sitting on it and flattens the
/// hierarchy the cards are there to create. Two large, very low-opacity discs
/// bled off the top corners give the page depth where there is no content and
/// leave the surfaces above them unchanged.
///
/// ## It does not move
///
/// Painted once and never animated. A drifting background is movement a reader
/// cannot stop, on a screen they are trying to read numbers off.
class SrSoftBackdrop extends StatelessWidget {
  const SrSoftBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: ExcludeSemantics(
            child: CustomPaint(
              painter: _BackdropPainter(
                primary: sr.brand.withValues(alpha: 0.07),
                secondary: sr
                    .tone(SrTone.blue)
                    .foreground
                    .withValues(alpha: 0.05),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter({required this.primary, required this.secondary});

  final Color primary;
  final Color secondary;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint one = Paint()
      ..color = primary
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40);
    final Paint two = Paint()
      ..color = secondary
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40);

    // Bled off the corners so neither disc reads as an object on the page.
    canvas.drawCircle(Offset(size.width * 0.88, -40), 150, one);
    canvas.drawCircle(Offset(-60, size.height * 0.16), 120, two);
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter oldDelegate) =>
      oldDelegate.primary != primary || oldDelegate.secondary != secondary;
}

/// A compact label-over-value pill.
///
/// The unit of the earnings strip and of a campaign card's metadata: a tinted
/// rounded surface carrying one caption and one figure. It replaces the
/// full-width bordered row, which is what made every screen read as a form.
class SrStatPill extends StatelessWidget {
  const SrStatPill({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.tone,
    this.onSurface = false,
  });

  final String label;
  final String value;
  final IconData? icon;

  /// Tints the pill. Null leaves it on the muted surface.
  final SrTone? tone;

  /// Renders for a brand-filled parent, where the ordinary text ramp is tuned
  /// for the wrong background.
  final bool onSurface;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final SrToneColors? colors = tone == null ? null : sr.tone(tone!);

    final Color labelColor = onSurface
        ? sr.onBrand.withValues(alpha: 0.76)
        : sr.textMuted;
    final Color valueColor = onSurface ? sr.onBrand : sr.foreground;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SrSpacing.md,
        vertical: SrSpacing.smPlus,
      ),
      decoration: BoxDecoration(
        color: onSurface
            ? sr.onBrand.withValues(alpha: 0.14)
            : (colors?.fill ?? sr.surfaceMuted),
        borderRadius: BorderRadius.circular(SrRadii.control),
        border: onSurface
            ? null
            : Border.all(color: colors?.border ?? sr.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 12, color: labelColor),
                const SizedBox(width: SrSpacing.xs),
              ],
              Flexible(
                child: Text(
                  label,
                  style: SrTypography.caption.copyWith(color: labelColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: SrSpacing.xxs),
          Text(
            value,
            style: SrTypography.label.copyWith(
              color: valueColor,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// The raised surface for the single most important thing on a screen.
///
/// A larger radius than [SrCard], a heavier shadow, and an optional tinted
/// wash behind its content. It is the visual budget a screen spends **once**;
/// a page with two of these has neither.
class SrFeatureCard extends StatelessWidget {
  const SrFeatureCard({
    super.key,
    required this.child,
    this.tone = SrTone.indigo,
    this.padding = const EdgeInsets.all(SrSpacing.xl),
    this.onTap,
  });

  final Widget child;
  final SrTone tone;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// `rounded-[28px]` — larger than the 16 every other surface uses, which is
  /// what makes this card read as a different kind of object rather than as a
  /// bigger one.
  static const double radius = 28;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final SrToneColors colors = sr.tone(tone);
    final BorderRadius shape = BorderRadius.circular(radius);

    Widget content = Padding(padding: padding, child: child);

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: shape,
          splashColor: colors.fill,
          highlightColor: colors.fill,
          child: content,
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: sr.elevatedShadow,
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: sr.surface,
            // A wash rather than a fill: the tint fades out before the content
            // starts, so text sits on the plain surface and keeps its contrast.
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: <Color>[colors.fill, sr.surface],
              stops: const <double>[0, 0.62],
            ),
            border: Border.all(color: colors.border),
          ),
          child: content,
        ),
      ),
    );
  }
}
