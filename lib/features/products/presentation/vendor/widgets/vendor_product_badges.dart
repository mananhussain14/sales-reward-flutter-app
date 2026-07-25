import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../../retailers/domain/entities/vendor_retailer_status.dart';
import '../../../domain/entities/vendor_product_assignment_status.dart';
import '../../../domain/entities/vendor_product_status.dart';
import 'vendor_product_copy.dart';

/// A product's place in the catalogue, as a pill.
///
/// ## Colour is never the message
///
/// Every state carries its own word and its own glyph, so a reader who cannot
/// distinguish emerald from slate reads exactly the same facts.
///
/// The semantics label spells the pair out — "Product status: Inactive" —
/// because a screen reader announcing "Inactive" alone leaves the subject to be
/// guessed, and there are three other statuses on a product detail screen that
/// could each have been the subject.
///
/// ## An unknown token is neutral, and is never active
///
/// [VendorProductStatus.unknown] renders "Unknown" in the slate tone with a
/// question glyph. The raw backend token is never shown — a future status must
/// not leak a database literal into the interface — and because the enum's
/// `isActive` tests `active` positively, nothing downstream can mistake it for a
/// live product. The product is still listed and still openable: losing sight of
/// a product because its status is unfamiliar would be worse than showing it
/// plainly.
class VendorProductStatusBadge extends StatelessWidget {
  const VendorProductStatusBadge({
    super.key,
    required this.status,
    this.showPrefix = true,
  });

  final VendorProductStatus status;

  /// Whether the subject appears in the visible label. When false it still
  /// appears in the semantics label, so the pair is never lost.
  final bool showPrefix;

  /// The subject, used in the visible prefix and in the spoken form.
  static const String subject = VendorProductCopy.statusLabel;

  /// The label for [status], without the subject. Exposed so a test can assert
  /// the mapping without building three widgets.
  static String labelFor(VendorProductStatus status) => switch (status) {
    VendorProductStatus.active => 'Active',
    VendorProductStatus.inactive => 'Inactive',
    VendorProductStatus.unknown => 'Unknown',
  };

  static SrTone _toneFor(VendorProductStatus status) => switch (status) {
    VendorProductStatus.active => SrTone.emerald,
    VendorProductStatus.inactive => SrTone.slate,
    VendorProductStatus.unknown => SrTone.slate,
  };

  static IconData _iconFor(VendorProductStatus status) => switch (status) {
    VendorProductStatus.active => Icons.check_rounded,
    VendorProductStatus.inactive => Icons.block_rounded,
    VendorProductStatus.unknown => Icons.help_outline_rounded,
  };

  /// The full spoken form — "Product status: Active".
  static String semanticsFor(VendorProductStatus status) =>
      '$subject: ${labelFor(status)}';

  @override
  Widget build(BuildContext context) {
    final String value = labelFor(status);

    return Semantics(
      label: semanticsFor(status),
      excludeSemantics: true,
      child: SrBadge(
        label: showPrefix ? 'Status: $value' : value,
        tone: _toneFor(status),
        icon: _iconFor(status),
      ),
    );
  }
}

/// Whether one Retailer currently holds this product, as a pill.
///
/// ## The wording is the point of this widget
///
/// `INACTIVE` reads **"Inactive assignment"**, never "Not assigned" and never a
/// bare "Inactive". The row exists because the product *was* assigned there and
/// the assignment was later withdrawn; "Not assigned" would describe a Retailer
/// that has no row at all, which this list never contains. And a bare "Inactive"
/// beside a Retailer status pill and a relationship status pill — all three
/// drawn from overlapping vocabularies — would leave a reader to guess which
/// subject it belonged to.
///
/// The subject therefore appears in the visible label *and* in the semantics
/// label, and both carry a glyph, so neither colour nor position is load-bearing.
///
/// ## An unknown token is neutral, and never reads as current
///
/// [VendorProductAssignmentStatus.unknown] renders "Unknown" in slate. The row
/// stays in the list and stays counted — dropping it would silently contradict
/// `assignment_count` — and it enables no navigation or action by itself.
class VendorProductAssignmentStatusBadge extends StatelessWidget {
  const VendorProductAssignmentStatusBadge({super.key, required this.status});

  final VendorProductAssignmentStatus status;

  static const String subject = VendorProductCopy.assignmentStatusSubject;

  /// The label for [status]. Exposed so a test can assert all three at once.
  static String labelFor(VendorProductAssignmentStatus status) =>
      switch (status) {
        VendorProductAssignmentStatus.active => 'Active assignment',
        VendorProductAssignmentStatus.inactive => 'Inactive assignment',
        VendorProductAssignmentStatus.unknown => 'Assignment status unknown',
      };

  static SrTone _toneFor(VendorProductAssignmentStatus status) =>
      switch (status) {
        VendorProductAssignmentStatus.active => SrTone.emerald,
        VendorProductAssignmentStatus.inactive => SrTone.slate,
        VendorProductAssignmentStatus.unknown => SrTone.slate,
      };

  static IconData _iconFor(VendorProductAssignmentStatus status) =>
      switch (status) {
        VendorProductAssignmentStatus.active => Icons.link_rounded,
        VendorProductAssignmentStatus.inactive => Icons.link_off_rounded,
        VendorProductAssignmentStatus.unknown => Icons.help_outline_rounded,
      };

  /// The full spoken form — "Assignment: Inactive assignment".
  static String semanticsFor(VendorProductAssignmentStatus status) =>
      '$subject: ${labelFor(status)}';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsFor(status),
      excludeSemantics: true,
      child: SrBadge(
        label: labelFor(status),
        tone: _toneFor(status),
        icon: _iconFor(status),
      ),
    );
  }
}

/// A Retailer status or a Vendor–Retailer relationship status, as a pill.
///
/// Both columns share the `ACTIVE / SUSPENDED / DEACTIVATED` vocabulary, so one
/// widget renders both and [subject] says which is which — "Retailer: Suspended"
/// beside "Relationship: Active" is a real and reachable pair, and a reader must
/// be able to tell them apart without inferring anything from position.
///
/// ## A null relationship status is not rendered here
///
/// When the `vendor_retailers` row is absent, `relationship_status` is null and
/// there is no status to show. That is a different statement from "a status this
/// build does not recognise", so it is **not** rendered as `unknown`: the
/// assignment tile shows
/// [VendorProductCopy.relationshipUnavailable] instead, and omits this pill.
class VendorProductRetailerStatusBadge extends StatelessWidget {
  const VendorProductRetailerStatusBadge({
    super.key,
    required this.status,
    required this.subject,
  });

  final VendorRetailerStatus status;

  /// "Retailer" or "Relationship".
  final String subject;

  static String labelFor(VendorRetailerStatus status) => switch (status) {
    VendorRetailerStatus.active => 'Active',
    VendorRetailerStatus.suspended => 'Suspended',
    VendorRetailerStatus.deactivated => 'Deactivated',
    VendorRetailerStatus.unknown => 'Unknown',
  };

  static SrTone _toneFor(VendorRetailerStatus status) => switch (status) {
    VendorRetailerStatus.active => SrTone.emerald,
    VendorRetailerStatus.suspended => SrTone.amber,
    VendorRetailerStatus.deactivated => SrTone.slate,
    VendorRetailerStatus.unknown => SrTone.slate,
  };

  static IconData _iconFor(VendorRetailerStatus status) => switch (status) {
    VendorRetailerStatus.active => Icons.check_rounded,
    VendorRetailerStatus.suspended => Icons.pause_rounded,
    VendorRetailerStatus.deactivated => Icons.block_rounded,
    VendorRetailerStatus.unknown => Icons.help_outline_rounded,
  };

  /// The full spoken form — "Retailer: Suspended".
  static String semanticsFor(String subject, VendorRetailerStatus status) =>
      '$subject: ${labelFor(status)}';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsFor(subject, status),
      excludeSemantics: true,
      child: SrBadge(
        label: '$subject: ${labelFor(status)}',
        tone: _toneFor(status),
        icon: _iconFor(status),
      ),
    );
  }
}

/// An identifier with a glyph and a label — the code and barcode lines a product
/// card and detail screen carry.
///
/// A plain row rather than an [SrBadge]: a badge is this product's *status*
/// pill, and an identifier is not a status. Making them look alike would invite
/// a reader to compare them.
class VendorProductIdentifierLine extends StatelessWidget {
  const VendorProductIdentifierLine({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.monospace = false,
  });

  final IconData icon;

  /// The subject — "Code", "Barcode", "Brand". Always visible, because a bare
  /// alphanumeric string tells a reader nothing about which identifier it is.
  final String label;

  final String value;

  /// Renders the value in a tabular figure treatment, for codes and barcodes
  /// where character alignment aids scanning.
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: SrSpacing.xxs),
            child: Icon(icon, size: 14, color: sr.textMuted),
          ),
          const SizedBox(width: SrSpacing.xs),
          Text(
            '$label ',
            style: SrTypography.caption.copyWith(color: sr.textMuted),
          ),
          // Expanded + soft wrap: a long barcode or brand at large text scale
          // grows the card downward rather than off the side of a phone.
          Expanded(
            child: Text(
              value,
              style: SrTypography.caption.copyWith(
                color: sr.textSecondary,
                fontFeatures: monospace
                    ? const <FontFeature>[FontFeature.tabularFigures()]
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
