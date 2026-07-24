import 'package:flutter/material.dart';

import '../design/design.dart';

/// The SalesReward brand mark, translated from the inline SVG in the web
/// application's `components/ui/brand.tsx`.
///
/// A rounded indigo→violet tile carrying a rising sales bar chart whose tallest
/// bar becomes an upward arrow, topped with an amber reward spark. Drawn with a
/// [CustomPainter] rather than shipped as an asset, for the same reason the web
/// draws it inline: no asset, no package, no network request, and it stays crisp
/// at any size.
///
/// [size] is the tile edge in logical pixels; all geometry is expressed against
/// the SVG's 40×40 viewBox and scaled from there.
class SrBrandMark extends StatelessWidget {
  const SrBrandMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Semantics(
        label: 'SalesReward',
        image: true,
        child: CustomPaint(painter: _BrandMarkPainter()),
      ),
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  /// The SVG viewBox edge every coordinate below is expressed against.
  static const double _viewBox = 40;

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = size.width / _viewBox;
    canvas.save();
    canvas.scale(scale);

    // The tile: rect 40×40, rx 11, indigo-600 → violet-600 across the diagonal.
    final Rect tile = const Rect.fromLTWH(0, 0, _viewBox, _viewBox);
    canvas.drawRRect(
      RRect.fromRectAndRadius(tile, const Radius.circular(SrRadii.brandTile)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: SrColors.brandGradient,
        ).createShader(tile),
    );

    // Rising bars.
    _bar(canvas, x: 10, y: 23, height: 7, color: SrColors.indigo200);
    _bar(canvas, x: 16, y: 19, height: 11, color: SrColors.indigo100);

    // The tallest bar, which becomes the arrow shaft.
    final Paint shaft = Paint()
      ..color = SrColors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(24, 30), const Offset(24, 15.5), shaft);

    // The arrowhead.
    final Path head = Path()
      ..moveTo(20, 18.5)
      ..lineTo(24, 14.5)
      ..lineTo(28, 18.5);
    canvas.drawPath(
      head,
      Paint()
        ..color = SrColors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // The amber reward spark.
    final Path spark = Path()
      ..moveTo(29.5, 9.5)
      ..lineTo(30.4, 12.1)
      ..lineTo(33, 13)
      ..lineTo(30.4, 13.9)
      ..lineTo(29.5, 16.5)
      ..lineTo(28.6, 13.9)
      ..lineTo(26, 13)
      ..lineTo(28.6, 12.1)
      ..close();
    canvas.drawPath(spark, Paint()..color = SrColors.brandSpark);

    canvas.restore();
  }

  void _bar(
    Canvas canvas, {
    required double x,
    required double y,
    required double height,
    required Color color,
  }) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, 3.6, height),
        const Radius.circular(1.4),
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _BrandMarkPainter oldDelegate) => false;
}

/// The mark paired with the "SalesReward" wordmark — the standard lockup used on
/// every entry point so they all read as one product.
///
/// [context] renders the optional portal caption under the wordmark, exactly as
/// the web lockup does ("Vendor Admin", "Retailer Portal"). On mobile this is
/// how a role shell states which experience the user is in.
class SrBrandLockup extends StatelessWidget {
  const SrBrandLockup({
    super.key,
    this.size = 36,
    this.context,
    this.onDarkSurface = false,
  });

  final double size;

  /// An optional caption under the wordmark, e.g. `'Vendor Admin'`.
  final String? context;

  /// When the lockup sits on the dark `--surface-nav` drawer, the wordmark and
  /// caption invert so they stay legible.
  final bool onDarkSurface;

  @override
  Widget build(BuildContext buildContext) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SrBrandMark(size: size),
        const SizedBox(width: SrSpacing.smPlus),
        // Flexible, so a long portal caption ("Retailer Super Admin") truncates
        // instead of overflowing a narrow app bar or drawer header.
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'SalesReward',
                style: SrTypography.wordmark.copyWith(
                  color: onDarkSurface ? SrColors.white : SrColors.foreground,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (context != null) ...<Widget>[
                const SizedBox(height: SrSpacing.xs),
                Text(
                  context!.toUpperCase(),
                  style: SrTypography.brandContext.copyWith(
                    color: onDarkSurface
                        ? SrColors.slate400
                        : SrColors.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
