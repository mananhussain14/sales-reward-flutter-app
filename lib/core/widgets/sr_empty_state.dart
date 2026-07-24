import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../design/design.dart';

/// The shared empty / notice state (§ 3.12).
///
/// A centred column inside a **dashed** 1px border at the surface radius:
/// 56px tinted disc → 24px → 16px semibold title → 6px → 14px supporting line
/// capped at `max-w-sm` → 24px → optional action.
///
/// [tone] changes only the disc. It never changes the wording, which each caller
/// supplies — and that separation is deliberate. The same component serves three
/// meanings on the web:
///
/// * "nothing yet" — *No staff yet*
/// * "could not load" — *Products could not be loaded*
/// * "nothing for you" — *No shops assigned yet*
///
/// > The "could not load" copy is deliberately **reason-free**. The underlying
/// > failure can only come from a database error whose detail must not reach a
/// > client, so no exception text, Postgres code or stack trace may ever be
/// > passed to [description].
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
    final SrColorScheme sr = context.sr;
    final SrToneColors colors = sr.tone(tone);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: SrSpacing.xxl,
        vertical: SrSpacing.huge,
      ),
      decoration: ShapeDecoration(
        color: sr.surface,
        shape: _DashedRoundedBorder(
          radius: SrRadii.surface,
          color: sr.borderStrong,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.fill,
                borderRadius: BorderRadius.circular(SrRadii.surface),
              ),
              child: Icon(icon, size: 24, color: colors.foreground),
            ),
            const SizedBox(height: SrSpacing.xxl),
          ],
          Text(
            title,
            style: SrTypography.cardTitle.copyWith(color: sr.foreground),
            textAlign: TextAlign.center,
          ),
          if (description != null) ...<Widget>[
            const SizedBox(height: SrSpacing.xsPlus),
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: SrSpacing.narrowMaxWidth,
              ),
              child: Text(
                description!,
                style: SrTypography.body.copyWith(color: sr.textSecondary),
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

/// The dashed outline `border-dashed border-slate-300` produces.
///
/// Flutter has no dashed border primitive, so the rounded path is stroked
/// manually with the 6-on / 4-off rhythm a browser renders.
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
