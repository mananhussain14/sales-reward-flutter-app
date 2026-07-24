import 'package:flutter/material.dart';

import '../design/design.dart';

/// The SalesReward brand mark.
///
/// Reproduced as a [CustomPainter] from the geometry table in § 1 of
/// `docs/mobile-ui-design-handoff.md`. The web draws it as inline SVG — there is
/// no PNG, no SVG file, and nothing in `public/` — so a raster would be a
/// downgrade as well as an unnecessary asset.
///
/// The mark is **theme-independent**: it keeps its own gradient tile in light
/// and dark, exactly as a logo should, and its colours come from
/// [SrBrandLiterals] rather than from the interface palette. Those literals are
/// the Tailwind v3-era hexes the SVG has always carried (decision D-1); using
/// them here and nowhere else is what keeps the mark pixel-identical to the web
/// while the interface uses the v4 steps that actually ship.
///
/// Sizes in use on the web: 36 (nav lockup), 40 (invitation, access-denied),
/// 44 (login).
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
        child: const CustomPaint(painter: _BrandMarkPainter()),
      ),
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  const _BrandMarkPainter();

  /// The SVG viewBox edge every coordinate below is expressed against.
  static const double _viewBox = 40;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _viewBox);

    // Tile: rect 0 0 40 40, radius 11, gradient (0,0) → (40,40).
    const Rect tile = Rect.fromLTWH(0, 0, _viewBox, _viewBox);
    canvas.drawRRect(
      RRect.fromRectAndRadius(tile, const Radius.circular(SrRadii.brandTile)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            SrBrandLiterals.gradientStart,
            SrBrandLiterals.gradientEnd,
          ],
        ).createShader(tile),
    );

    // Rising bars.
    _bar(canvas, x: 10, y: 23, height: 7, color: SrBrandLiterals.bar1);
    _bar(canvas, x: 16, y: 19, height: 11, color: SrBrandLiterals.bar2);

    // The tallest bar, which becomes the arrow shaft.
    canvas.drawLine(
      const Offset(24, 30),
      const Offset(24, 15.5),
      Paint()
        ..color = SrBrandLiterals.arrow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.6
        ..strokeCap = StrokeCap.round,
    );

    // The arrowhead.
    canvas.drawPath(
      Path()
        ..moveTo(20, 18.5)
        ..lineTo(24, 14.5)
        ..lineTo(28, 18.5),
      Paint()
        ..color = SrBrandLiterals.arrow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // The four-point reward spark, centred on (29.5, 13).
    canvas.drawPath(
      Path()
        ..moveTo(29.5, 9.5)
        ..lineTo(30.4, 12.1)
        ..lineTo(33, 13)
        ..lineTo(30.4, 13.9)
        ..lineTo(29.5, 16.5)
        ..lineTo(28.6, 13.9)
        ..lineTo(26, 13)
        ..lineTo(28.6, 12.1)
        ..close(),
      Paint()..color = SrBrandLiterals.spark,
    );

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

/// The mark paired with the "SalesReward" wordmark — the standard lockup, used
/// wherever an entry point needs to read as this product.
///
/// [portal] renders the optional caption under the wordmark. The web uses it for
/// the portal name — "Vendor Admin", "Retailer" — never for a role, and never as
/// a second product name.
class SrBrandLockup extends StatelessWidget {
  const SrBrandLockup({super.key, this.size = 36, this.portal});

  final double size;

  /// e.g. `'Vendor Admin'`. Rendered uppercase.
  final String? portal;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SrBrandMark(size: size),
        const SizedBox(width: SrSpacing.smPlus),
        // Flexible so a long caption truncates instead of overflowing a narrow
        // app bar or drawer header.
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'SalesReward',
                style: SrTypography.wordmark.copyWith(color: sr.foreground),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (portal != null) ...<Widget>[
                const SizedBox(height: SrSpacing.xs),
                Text(
                  portal!.toUpperCase(),
                  style: SrTypography.brandContext.copyWith(
                    color: sr.textSecondary,
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

/// The circular gradient avatar from the app bar (§ 3.19), carrying up to two
/// initials.
///
/// The initials rule follows `InitialsAvatar`: first character of the first
/// word plus first character of the **last** word — the resolution recommended
/// for decision D-3, because it handles middle names correctly. A single word
/// contributes its first two characters.
class SrInitialsAvatar extends StatelessWidget {
  const SrInitialsAvatar({
    super.key,
    required this.name,
    this.size = 36,
    this.fallback = 'SR',
  });

  final String? name;
  final double size;

  /// Shown when [name] yields nothing usable. Never a placeholder glyph — the
  /// web always renders letters.
  final String fallback;

  /// Extracts up to two initials from [source], upper-cased.
  static String initialsFor(String? source, {String fallback = 'SR'}) {
    final List<String> words = (source ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((String w) => w.isNotEmpty)
        .toList();

    if (words.isEmpty) {
      return fallback;
    }
    if (words.length == 1) {
      final String word = words.first;
      return (word.length >= 2 ? word.substring(0, 2) : word).toUpperCase();
    }
    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[sr.brand, sr.accent],
        ),
        boxShadow: sr.subtleShadow,
      ),
      child: Text(
        initialsFor(name, fallback: fallback),
        style: SrTypography.label.copyWith(
          color: sr.onBrand,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
