import 'package:flutter/material.dart';

import '../design/design.dart';

/// The mobile form of the web's responsive card grids (§ 4.5).
///
/// The web uses `grid-cols-1 sm:grid-cols-2 xl:grid-cols-4` for stat cards and
/// `sm:grid-cols-3` for shortcuts. Both collapse to **one full-width column** on
/// a phone, and the handoff is explicit that the cards must not be shrunk to
/// compensate: the 30px stat value and the 40px disc are a deliberate part of
/// the look, and four stacked cards is acceptable above the fold.
///
/// This pairs items up once there is room for two, and stays single-column
/// below that.
class SrCardGrid extends StatelessWidget {
  const SrCardGrid({super.key, required this.children});

  final List<Widget> children;

  /// Below this width a second column would make each card too narrow for a
  /// 30px `tabular-nums` value plus a 40px disc.
  static const double twoUpThreshold = 520;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool twoUp = constraints.maxWidth >= twoUpThreshold;
        final double itemWidth = twoUp
            ? (constraints.maxWidth - SrSpacing.lg) / 2
            : constraints.maxWidth;

        return Wrap(
          spacing: SrSpacing.lg,
          runSpacing: SrSpacing.lg,
          children: <Widget>[
            for (final Widget child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

/// A "Quick action" shortcut card: a 40px tinted disc, a label, and the
/// trailing arrow-up-right glyph the web's Vendor dashboard uses.
class SrShortcutCard extends StatelessWidget {
  const SrShortcutCard({
    super.key,
    required this.label,
    required this.icon,
    this.tone = SrTone.indigo,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final SrTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final SrToneColors colors = sr.tone(tone);

    return _ShortcutSurface(
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.fill,
              borderRadius: BorderRadius.circular(SrRadii.control),
            ),
            child: Icon(icon, size: 20, color: colors.foreground),
          ),
          const SizedBox(width: SrSpacing.md),
          Expanded(
            child: Text(
              label,
              style: SrTypography.label.copyWith(color: sr.foreground),
            ),
          ),
          Icon(Icons.arrow_outward_rounded, size: 16, color: sr.textMuted),
        ],
      ),
    );
  }
}

class _ShortcutSurface extends StatelessWidget {
  const _ShortcutSurface({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final BorderRadius radius = BorderRadius.circular(SrRadii.surface);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: sr.surface,
        borderRadius: radius,
        border: Border.all(color: sr.border),
        boxShadow: sr.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.all(SrSpacing.xl),
            child: child,
          ),
        ),
      ),
    );
  }
}
