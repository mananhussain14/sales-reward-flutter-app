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
        track: sr.border,
        arc: colors.foreground,
        segments: (segments ?? 0) >= 2 ? segments : null,
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
        duration: const Duration(milliseconds: 700),
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
    required this.segments,
  });

  final double value;
  final double strokeWidth;
  final Color track;
  final Color arc;
  final int? segments;

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

    final Paint trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final Paint arcPaint = Paint()
      ..color = arc
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

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
      final double sweep = slice - _gap;
      canvas.drawArc(bounds, from, sweep, false, trackPaint);

      // How much of THIS segment is filled: 1 for a segment wholly behind the
      // value, the remainder for the one it lands in, 0 for the rest.
      final double portion = (filled - i).clamp(0.0, 1.0);
      if (portion > 0) {
        canvas.drawArc(bounds, from, sweep * portion, false, arcPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.track != track ||
      oldDelegate.arc != arc ||
      oldDelegate.segments != segments;
}
