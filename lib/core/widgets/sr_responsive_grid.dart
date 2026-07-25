import 'package:flutter/material.dart';

import '../design/design.dart';

/// A column-count-by-width arrangement for content cards.
///
/// One full-width column on a phone, two once there is genuinely room, three on
/// a wide desktop browser. **The thresholds are supplied by the caller** rather
/// than fixed here, because the width at which a second column stops helping
/// depends on what the card carries: a row of status pills needs more room than
/// a name and a date, and one shared pair of numbers would serve neither
/// feature well.
///
/// ## How this differs from [SrCardGrid]
///
/// [SrCardGrid] is the stat-card grid: a fixed 520px pairing threshold and never
/// more than two columns, matching the web's `sm:grid-cols-2`. This is the
/// directory grid — three column counts, caller-chosen breakpoints — and the two
/// are kept apart so tuning a Retailer list cannot silently reflow every
/// dashboard.
///
/// ## Deliberately not a table
///
/// The web renders these directories as desktop tables. A table on a phone is
/// either horizontally scrolled — which the design handoff forbids — or squeezed
/// until its columns are unreadable. Cards read identically at every width and
/// are the same widget in both orientations, so there is no wide-only layout to
/// keep working and no phone-only fallback to keep in step.
class SrResponsiveGrid extends StatelessWidget {
  const SrResponsiveGrid({
    super.key,
    required this.children,
    required this.twoUpThreshold,
    required this.threeUpThreshold,
  });

  final List<Widget> children;

  /// Below this width a second column would squeeze the card's content.
  final double twoUpThreshold;

  /// Above this width a third column still leaves each card wider than a phone.
  final double threeUpThreshold;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final int columns = width >= threeUpThreshold
            ? 3
            : (width >= twoUpThreshold ? 2 : 1);

        if (columns == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < children.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(height: SrSpacing.lg),
                children[i],
              ],
            ],
          );
        }

        final double itemWidth =
            (width - (SrSpacing.lg * (columns - 1))) / columns;

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
