import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';

/// The responsive arrangement for Retailer cards.
///
/// One full-width column on a phone; two side by side once there is genuinely
/// room; three on a wide desktop browser. The thresholds are wider than
/// [SrCardGrid]'s because a Retailer card carries three status pills on one Wrap
/// line, and pairing them at 520px would push every pill onto its own row —
/// technically not an overflow, but a worse layout than a single column.
///
/// ## Deliberately not a table
///
/// The web renders this directory as a desktop table. A table on a phone is
/// either horizontally scrolled — which the handoff forbids — or squeezed until
/// its columns are unreadable. Cards read identically at every width and are the
/// same widget in both orientations, so there is no wide-only layout to keep
/// working and no phone-only fallback to keep in step.
class VendorRetailerGrid extends StatelessWidget {
  const VendorRetailerGrid({super.key, required this.children});

  final List<Widget> children;

  /// Below this a second column would squeeze the status pills.
  static const double twoUpThreshold = 760;

  /// Above this a third column still leaves each card wider than a phone.
  static const double threeUpThreshold = 1100;

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
