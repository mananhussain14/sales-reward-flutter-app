import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/design.dart';

/// A circular progress indicator, drawn in the product's own language.
///
/// ## It draws a ratio and claims nothing
///
/// [value] is a **display fraction** supplied by the caller, already clamped to
/// `0.0`–`1.0`. This widget performs no comparison, reads no target and decides
/// nothing about whether a goal was met: a ring that filled itself from two
/// numbers would be a second definition of "reached" living in a painter.
///
/// The caller keeps the real numerator and denominator on screen beside it —
/// 9 of 8 stays 9 of 8 while the ring rests at full, because a ring cannot draw
/// past its own circumference and rounding the numbers to match it would make a
/// target look smaller than it is.
///
/// ## The richer treatment is optional, and additive
///
/// A bare call draws one arc on a hairline track — that is what a campaign card
/// wants. The hero on the Sales Staff home passes [gradient], [ticks] and
/// [glow] and gets a thick, softly-lit gauge with a graduated sweep. **None of
/// those change the geometry**: the arc still ends at exactly [value], the ticks
/// are evenly spaced marks around the full circle rather than a scale derived
/// from the data, and the glow is painted under the arc it follows.
///
/// ## Silent to assistive technology, by design
///
/// The ring carries no semantics. A bare circular indicator announces a
/// percentage and nothing about whose units it counts, so every caller wraps the
/// whole block in one `Semantics` node whose label names the scope, the values
/// and the state. Announcing here as well would have a reader hear the
/// percentage twice.
///
/// ## Motion
///
/// The arc sweeps once from zero to [value] and stops. Under reduced motion it
/// is painted at [value] immediately — the settled end, never nothing.
class SrProgressRing extends StatelessWidget {
  const SrProgressRing({
    super.key,
    required this.value,
    this.size = 128,
    this.strokeWidth = 10,
    this.tone = SrTone.indigo,
    this.segments,
    this.center,
    this.gradient,
    this.ticks,
    this.glow = false,
    this.trackColor,
  });

  /// The fraction to fill, `0.0`–`1.0`. Values outside the range are clamped
  /// here as well as by the caller: a painter that swept past a full turn would
  /// overdraw its own start.
  final double value;

  final double size;
  final double strokeWidth;
  final SrTone tone;

  /// Splits the ring into this many equal arcs with a hairline gap between
  /// them, for a target that reads as a set of steps rather than a continuum.
  ///
  /// Null draws one continuous arc. Values below 2 are treated as null — a
  /// single "segment" is a continuous ring with a gap cut into it.
  final int? segments;

  /// Rendered inside the ring. Usually the percentage and a short label.
  final Widget? center;

  /// Two or more colours swept along the arc, replacing the flat tone.
  ///
  /// A **presentation** choice only. The colours are laid along the drawn arc,
  /// so the same [value] produces the same geometry with or without them.
  final List<Color>? gradient;

  /// Evenly spaced marks around the whole circle.
  ///
  /// Deliberately **not** derived from the target: a 50-unit target does not
  /// get 50 ticks. They are a dial's graduations — a constant number of marks
  /// that make the sweep easier to read — and they say nothing about units.
  final int? ticks;

  /// Paints a soft halo beneath the arc.
  final bool glow;

  /// Overrides the hairline track colour, for a ring on a tinted surface.
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final SrToneColors colors = sr.tone(tone);
    final double target = value.clamp(0.0, 1.0);

    Widget ring(double drawn) => CustomPaint(
      size: Size.square(size),
      painter: _RingPainter(
        value: drawn,
        strokeWidth: strokeWidth,
        track: trackColor ?? sr.border,
        arc: colors.foreground,
        gradient: (gradient?.length ?? 0) >= 2 ? gradient : null,
        segments: (segments ?? 0) >= 2 ? segments : null,
        ticks: (ticks ?? 0) >= 2 ? ticks : null,
        tickColor: trackColor ?? sr.border,
        glow: glow,
      ),
      child: SizedBox.square(
        dimension: size,
        child: center == null
            ? null
            : Center(
                child: Padding(
                  padding: EdgeInsets.all(strokeWidth + SrSpacing.sm),
                  child: center,
                ),
              ),
      ),
    );

    if (!SrMotion.respects(context)) {
      return ExcludeSemantics(child: ring(target));
    }

    return ExcludeSemantics(
      child: TweenAnimationBuilder<double>(
        // Keyed on the target, so the sweep runs once per real value and a
        // rebuild that changes nothing leaves the arc where it is.
        tween: Tween<double>(begin: 0, end: target),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (BuildContext context, double drawn, Widget? child) =>
            ring(drawn),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.value,
    required this.strokeWidth,
    required this.track,
    required this.arc,
    required this.gradient,
    required this.segments,
    required this.ticks,
    required this.tickColor,
    required this.glow,
  });

  final double value;
  final double strokeWidth;
  final Color track;
  final Color arc;
  final List<Color>? gradient;
  final int? segments;
  final int? ticks;
  final Color tickColor;
  final bool glow;

  /// Twelve o'clock. A ring that started at three would read as a pie chart.
  static const double _start = -math.pi / 2;
  static const double _turn = math.pi * 2;

  /// The gap between segments, in radians. Small enough that a 12-segment ring
  /// still reads as a ring.
  static const double _gap = 0.06;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect bounds = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );

    _paintTicks(canvas, size);

    final Paint trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final List<Color>? sweep = gradient;
    final Paint arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    if (sweep == null) {
      arcPaint.color = arc;
    } else {
      // Laid along the drawn arc rather than across the box, so the first
      // colour is always at twelve o'clock and the last is always at the head
      // of the sweep — whatever the value happens to be.
      arcPaint.shader = SweepGradient(
        startAngle: _start,
        endAngle: _start + _turn,
        colors: sweep,
        transform: GradientRotation(_start),
      ).createShader(bounds);
    }

    if (glow && value > 0) {
      final Paint halo = Paint()
        ..color = (sweep?.last ?? arc).withValues(alpha: 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 1.7
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawArc(bounds, _start, _turn * value, false, halo);
    }

    final int? count = segments;
    if (count == null) {
      canvas.drawArc(bounds, _start, _turn, false, trackPaint);
      if (value > 0) {
        canvas.drawArc(bounds, _start, _turn * value, false, arcPaint);
      }
      return;
    }

    final double slice = _turn / count;
    final double filled = value * count;
    for (int i = 0; i < count; i++) {
      final double from = _start + (slice * i) + (_gap / 2);
      final double sweepAngle = slice - _gap;
      canvas.drawArc(bounds, from, sweepAngle, false, trackPaint);

      // How much of THIS segment is filled: 1 for a segment wholly behind the
      // value, the remainder for the one it lands in, 0 for the rest.
      final double portion = (filled - i).clamp(0.0, 1.0);
      if (portion > 0) {
        canvas.drawArc(bounds, from, sweepAngle * portion, false, arcPaint);
      }
    }
  }

  /// The dial graduations, inside the track.
  void _paintTicks(Canvas canvas, Size size) {
    final int? count = ticks;
    if (count == null) {
      return;
    }

    final Offset centre = Offset(size.width / 2, size.height / 2);
    final double outer = (size.width / 2) - strokeWidth - 3;
    final double inner = outer - 5;
    final Paint paint = Paint()
      ..color = tickColor
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < count; i++) {
      final double angle = _start + (_turn / count * i);
      canvas.drawLine(
        centre + Offset(math.cos(angle) * inner, math.sin(angle) * inner),
        centre + Offset(math.cos(angle) * outer, math.sin(angle) * outer),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.track != track ||
      oldDelegate.arc != arc ||
      oldDelegate.gradient != gradient ||
      oldDelegate.segments != segments ||
      oldDelegate.ticks != ticks ||
      oldDelegate.glow != glow;
}
