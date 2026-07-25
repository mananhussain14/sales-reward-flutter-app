import 'package:flutter/material.dart';

import '../../../../../core/widgets/widgets.dart';

/// The responsive arrangement for Retailer cards.
///
/// The layout itself lives in [SrResponsiveGrid], promoted into the design
/// system when the Vendor User directory needed the same three-column-count
/// behaviour at different widths. What stays here is the pair of numbers, which
/// is the part that belongs to *this* content: a Retailer card carries three
/// status pills on one Wrap line, so pairing them at [SrCardGrid]'s 520px would
/// push every pill onto its own row — technically not an overflow, but a worse
/// layout than a single column.
class VendorRetailerGrid extends StatelessWidget {
  const VendorRetailerGrid({super.key, required this.children});

  final List<Widget> children;

  /// Below this a second column would squeeze the status pills.
  static const double twoUpThreshold = 760;

  /// Above this a third column still leaves each card wider than a phone.
  static const double threeUpThreshold = 1100;

  @override
  Widget build(BuildContext context) {
    return SrResponsiveGrid(
      twoUpThreshold: twoUpThreshold,
      threeUpThreshold: threeUpThreshold,
      children: children,
    );
  }
}
