import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/vendor_product_assigned_retailer.dart';
import 'vendor_product_badges.dart';
import 'vendor_product_copy.dart';
import 'vendor_product_formatting.dart';

/// One Retailer this product has been assigned to.
///
/// ## Three statuses, three separate facts
///
/// The assignment, the Vendor–Retailer relationship and the Retailer
/// organization each carry their own pill with its own subject in the label. An
/// **active assignment against a suspended relationship or a suspended Retailer
/// is a real and reachable state** — the backend deliberately does not require
/// an active relationship to withdraw a product, and neither assignment count
/// consults the other two statuses — so all three are rendered exactly as
/// stored, and nothing here derives one from another in either direction.
///
/// The product's own status is not repeated per row. It is a property of the
/// product and is stated once, at the top of the screen.
///
/// ## An inactive assignment is history, and is labelled as history
///
/// Withdrawal sets `INACTIVE` and never deletes, so this row is the surviving
/// record that the product was once available here. It is shown — hiding it
/// would make ending an assignment look like erasing one, and would leave
/// `assignment_count` unexplainable — and it is styled as **secondary**: a
/// muted surface and a "Inactive assignment" pill, never the treatment a current
/// assignment gets. The distinction is carried by the pill's word and glyph as
/// well as by the surface, so it survives without colour.
///
/// ## Cross-linking is decided by the relationship id, and by nothing else
///
/// [VendorProductCopy.viewRetailer] is offered only when `relationship_id` is
/// present, because that id is the address `/vendor/retailers/:relationshipId`
/// accepts. Deliberately **not** decided by any status: a `SUSPENDED` or
/// `DEACTIVATED` relationship is still addressable and still opens, and the
/// Retailer detail screen exists precisely to explain such a state. And
/// deliberately never `retailer_organization_id`, which names a tenant other
/// Vendors may also manage and which the Retailer screens do not accept.
///
/// When the id is null the row shows
/// [VendorProductCopy.relationshipUnavailable] in its place, omits the
/// relationship pill entirely — there is no relationship row to have a status —
/// and stays in the list, counted like any other.
///
/// ## The assignment action is supplied, not decided here
///
/// [action] is built by the section, which is the only place that knows the
/// Product's own status — a fact about the whole screen rather than about any
/// one row. This widget renders it and nothing more, so the row stays a
/// rendering of one backend answer.
///
/// It sits **outside** the descriptive `Semantics`, whose `excludeSemantics`
/// collapses the facts above into one spoken sentence. A control swallowed by
/// that collapse would be invisible to a screen reader and unreachable by
/// keyboard, so every interactive element on this row keeps its own node.
class VendorProductAssignmentTile extends StatelessWidget {
  const VendorProductAssignmentTile({
    super.key,
    required this.assignment,
    required this.onOpenRetailer,
    this.action,
  });

  final VendorProductAssignedRetailer assignment;

  /// Invoked with the non-null `relationship_id`. Never called for an
  /// unlinkable row: the action is not rendered at all in that case, rather than
  /// rendered disabled.
  final ValueChanged<String> onOpenRetailer;

  /// The Withdraw or Reactivate control for this row, or null when the screen
  /// offers none — a read-only context, or a state in which no transition is
  /// available.
  final Widget? action;

  /// The one spoken sentence this row presents.
  ///
  /// Every fact in reading order, with each status named by its subject, so a
  /// listener is never left to guess which "Suspended" they just heard. The
  /// relationship-unavailable state is spoken as a full explanation rather than
  /// as the absence of a pill.
  ///
  /// It names no uuid — neither the relationship id nor the Retailer
  /// organization id — because both are addresses and neither means anything to
  /// a reader.
  static String semanticsFor(VendorProductAssignedRetailer assignment) {
    final String relationship = assignment.relationshipStatus == null
        ? VendorProductCopy.relationshipUnavailableSemantics
        : VendorProductRetailerStatusBadge.semanticsFor(
            VendorProductCopy.relationshipStatusSubject,
            assignment.relationshipStatus!,
          );

    return '${assignment.retailerName}. '
        '${VendorProductAssignmentStatusBadge.semanticsFor(assignment.assignmentStatus)}. '
        '${VendorProductRetailerStatusBadge.semanticsFor(VendorProductCopy.retailerStatusSubject, assignment.retailerStatus)}. '
        '$relationship. '
        '${VendorProductCopy.assignedOnLabel} '
        '${formatProductDate(assignment.assignedAt)}. '
        '${VendorProductCopy.assignmentUpdatedLabel} '
        '${formatProductDate(assignment.assignmentUpdatedAt)}.';
  }

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final bool isActive = assignment.assignmentStatus.isActive;

    return Container(
      margin: const EdgeInsets.only(bottom: SrSpacing.md),
      padding: const EdgeInsets.all(SrSpacing.lg),
      decoration: BoxDecoration(
        // A withdrawn assignment sits on the muted surface, so a reader
        // scanning shapes sees at once that it is not a current one. The
        // pill's word and glyph carry the same fact for a reader who cannot
        // see the difference.
        color: isActive ? sr.surface : sr.surfaceMuted,
        borderRadius: BorderRadius.circular(SrRadii.control),
        border: Border.all(color: sr.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Every fact about this assignment, collapsed into one spoken
          // sentence. The controls below are deliberately not inside it.
          Semantics(
            label: semanticsFor(assignment),
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  assignment.retailerName,
                  style: SrTypography.body.copyWith(
                    color: isActive ? sr.foreground : sr.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                  // No maxLines: a long organization name wraps onto as many
                  // lines as it needs rather than being cut, because there is no
                  // code beside it to disambiguate a truncated one.
                ),
                const SizedBox(height: SrSpacing.sm),
                // Wrap, so three pills stack onto separate lines on a 360px
                // phone at large text scale instead of overflowing sideways.
                Wrap(
                  spacing: SrSpacing.sm,
                  runSpacing: SrSpacing.sm,
                  children: <Widget>[
                    VendorProductAssignmentStatusBadge(
                      status: assignment.assignmentStatus,
                    ),
                    VendorProductRetailerStatusBadge(
                      status: assignment.retailerStatus,
                      subject: VendorProductCopy.retailerStatusSubject,
                    ),
                    // Rendered only when there is a relationship row to
                    // describe. A null status is the absence of a row, not an
                    // unfamiliar value, so it must not become an "Unknown" pill.
                    if (assignment.relationshipStatus != null)
                      VendorProductRetailerStatusBadge(
                        status: assignment.relationshipStatus!,
                        subject: VendorProductCopy.relationshipStatusSubject,
                      ),
                  ],
                ),
                const SizedBox(height: SrSpacing.md),
                _DateLine(
                  icon: Icons.event_available_outlined,
                  label: VendorProductCopy.assignedOnLabel,
                  value: formatProductDate(assignment.assignedAt),
                ),
                const SizedBox(height: SrSpacing.xs),
                // Labelled for what the column is. It is not a withdrawal date,
                // not even on an inactive row, and it is never spoken as one.
                _DateLine(
                  icon: Icons.update_rounded,
                  label: VendorProductCopy.assignmentUpdatedLabel,
                  value: formatProductDate(assignment.assignmentUpdatedAt),
                ),
              ],
            ),
          ),
          const SizedBox(height: SrSpacing.md),
          // Not a disabled button. A control a reader can see and cannot use
          // asks them to work out why; a sentence says it. It spans the row
          // rather than sitting in the button flow, because it is prose.
          if (!assignment.isCrossLinkable) ...<Widget>[
            const _RelationshipUnavailableNote(),
            if (action != null) const SizedBox(height: SrSpacing.md),
          ],
          // Wrap rather than a Row: on a 360px phone at large text scale the
          // cross-link and the assignment action stack instead of overflowing.
          if (assignment.isCrossLinkable || action != null)
            Wrap(
              spacing: SrSpacing.sm,
              runSpacing: SrSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                if (assignment.isCrossLinkable)
                  Semantics(
                    button: true,
                    label:
                        '${VendorProductCopy.viewRetailer}: '
                        '${assignment.retailerName}',
                    child: SrButton(
                      label: VendorProductCopy.viewRetailer,
                      variant: SrButtonVariant.outline,
                      size: SrButtonSize.sm,
                      icon: Icons.storefront_outlined,
                      onPressed: () =>
                          onOpenRetailer(assignment.relationshipId!),
                    ),
                  ),
                ?action,
              ],
            ),
        ],
      ),
    );
  }
}

/// One dated fact on an assignment row.
class _DateLine extends StatelessWidget {
  const _DateLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: SrSpacing.xxs),
          child: Icon(icon, size: 14, color: sr.textMuted),
        ),
        const SizedBox(width: SrSpacing.xs),
        Expanded(
          child: Text(
            '$label $value',
            style: SrTypography.caption.copyWith(color: sr.textMuted),
          ),
        ),
      ],
    );
  }
}

/// The state of an assignment whose `vendor_retailers` row is gone.
///
/// Neutral, factual, and scoped to what is actually missing: the assignment is
/// intact, its status is real, and it is still counted — only the link is
/// unavailable. It is styled as information rather than as a warning, because
/// nothing is wrong with the assignment being described.
class _RelationshipUnavailableNote extends StatelessWidget {
  const _RelationshipUnavailableNote();

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Semantics(
      label: VendorProductCopy.relationshipUnavailableSemantics,
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: SrSpacing.xxs),
            child: Icon(Icons.link_off_rounded, size: 14, color: sr.textMuted),
          ),
          const SizedBox(width: SrSpacing.xs),
          Expanded(
            child: Text(
              VendorProductCopy.relationshipUnavailable,
              style: SrTypography.caption.copyWith(
                color: sr.textMuted,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
