import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../design/design.dart';

/// The shared empty / notice state, translated from `EmptyState` in the web
/// application's `components/ui/empty-state.tsx`.
///
/// A dashed slate-300 outline around a white 16px-radius surface, with an icon
/// in a soft tinted disc above a short title and a supporting line.
///
/// [tone] only changes the disc color — never the wording, which each caller
/// supplies. That separation is deliberate on the web and is preserved here:
/// copy that explains *why* something is empty is the caller's business, and for
/// an unavailable result it must stay reason-free.
class SrEmptyState extends StatelessWidget {
  const SrEmptyState({
    super.key,
    required this.title,
    this.description,
    this.icon,
    this.tone = SrTone.slate,
    this.action,
  });

  final String title;
  final String? description;
  final IconData? icon;
  final SrTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: SrSpacing.xxl,
        vertical: SrSpacing.huge,
      ),
      decoration: ShapeDecoration(
        color: SrColors.surface,
        shape: _DashedRoundedBorder(
          radius: SrRadii.xl,
          color: SrColors.borderStrong,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: tone.background,
                borderRadius: BorderRadius.circular(SrRadii.xl),
              ),
              child: Icon(icon, size: 28, color: tone.foreground),
            ),
            const SizedBox(height: SrSpacing.lg),
          ],
          Text(
            title,
            style: SrTypography.cardTitle,
            textAlign: TextAlign.center,
          ),
          if (description != null) ...<Widget>[
            const SizedBox(height: SrSpacing.xsPlus),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 384),
              child: Text(
                description!,
                style: SrTypography.bodyMuted,
                textAlign: TextAlign.center,
              ),
            ),
          ],
          if (action != null) ...<Widget>[
            const SizedBox(height: SrSpacing.xxl),
            action!,
          ],
        ],
      ),
    );
  }
}

/// The dashed 16px-radius outline `border-dashed border-slate-300` produces on
/// the web. Flutter has no dashed border primitive, so the path is stroked
/// manually with the same 6px-on / 4px-off rhythm a browser renders.
class _DashedRoundedBorder extends OutlinedBorder {
  const _DashedRoundedBorder({required this.radius, required this.color})
    : super(side: BorderSide.none);

  final double radius;
  final Color color;

  static const double _dash = 6;
  static const double _gap = 4;

  RRect _rrect(Rect rect) =>
      RRect.fromRectAndRadius(rect, Radius.circular(radius));

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(_rrect(rect.deflate(1)));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(_rrect(rect));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (final PathMetric metric
        in (Path()..addRRect(_rrect(rect.deflate(0.5)))).computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final double end = (distance + _dash).clamp(0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + _gap;
      }
    }
  }

  @override
  OutlinedBorder copyWith({BorderSide? side}) => this;

  @override
  ShapeBorder scale(double t) =>
      _DashedRoundedBorder(radius: radius * t, color: color);

  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.all(1);
}
