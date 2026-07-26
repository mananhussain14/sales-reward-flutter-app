import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/vendor_product_assigned_retailer.dart';
import '../../../domain/entities/vendor_product_assignment_action.dart';
import '../../../domain/entities/vendor_product_assignment_status.dart';
import '../../../domain/entities/vendor_product_status.dart';
import '../cubit/vendor_product_assignment_cubit.dart';
import 'vendor_product_assignment_confirmations.dart';
import 'vendor_product_copy.dart';

/// The transition one assignment row offers, or null when it offers none.
///
/// Pure and static, so the rule can be asserted without a widget and stated in
/// one place rather than reconstructed inside a `build`.
///
/// | Assignment | Product | Retailer + relationship | Offered |
/// | --- | --- | --- | --- |
/// | active | any | any | [VendorProductAssignmentAction.withdraw] |
/// | inactive | active | both active | [VendorProductAssignmentAction.reactivate] |
/// | inactive | inactive | any | none |
/// | inactive | active | either not active | none |
/// | unrecognised | any | any | none |
///
/// That table mirrors the deployed gates and does not extend them. **Withdrawal
/// requires no status to be active** — a Vendor must be able to end an
/// assignment to a Retailer it has since suspended, which is exactly when it
/// matters most, and a status gate here would strand historical assignments as
/// permanently un-endable. **Reactivation shares the stricter assign gate**: the
/// Product active, this Vendor's relationship active, and the Retailer
/// organization active.
///
/// An assignment status this build does not recognise offers **neither**
/// transition. Guessing that an unfamiliar status is in force would offer to
/// withdraw something unknown, and guessing the reverse would offer to
/// reactivate it.
///
/// A missing relationship row — a null `relationship_id`, and therefore a null
/// `relationship_status` — cannot satisfy the reactivation gate and is not
/// repaired into one that can.
VendorProductAssignmentAction? assignmentActionFor(
  VendorProductAssignedRetailer assignment,
  VendorProductStatus productStatus,
) {
  if (assignment.assignmentStatus.isActive) {
    return VendorProductAssignmentAction.withdraw;
  }
  if (assignment.assignmentStatus != VendorProductAssignmentStatus.inactive) {
    return null;
  }
  final bool retailerIsEligible =
      assignment.retailerStatus.isActive &&
      (assignment.relationshipStatus?.isActive ?? false);
  if (!productStatus.isActive || !retailerIsEligible) {
    return null;
  }
  return VendorProductAssignmentAction.reactivate;
}

/// The Withdraw or Reactivate control for one assignment row.
///
/// ## It is a presentation guard, and only that
///
/// Whether this caller may change an assignment is decided in SQL on every call,
/// by `PRODUCT_RETAILER_ASSIGN` — a permission this client never names, sends or
/// inspects, and which is distinct from the one governing the Edit and Activate
/// controls elsewhere on this screen. The backend re-evaluates eligibility
/// inside the write, under row locks, and may refuse a control this widget
/// offered; that is the contract working rather than a defect to engineer
/// around.
///
/// ## Nothing is optimistic
///
/// No row is flipped, inserted or removed ahead of the backend. What is on
/// screen changes when — and only when — the canonical reads say so, which is
/// why a failure leaves the row exactly as it was rather than having to undo a
/// guess. While a request is in flight **this pairing's** control is disabled
/// and shows progress; every other row stays usable, and a second confirmation
/// for the same pairing cannot start a second write.
///
/// ## When there is no control, there is a sentence
///
/// A withdrawn assignment that cannot be reactivated shows a neutral
/// explanation instead of a disabled button — with different wording when the
/// blocker is a missing relationship rather than an inactive one, because
/// nothing is suspended in that case. The Product's own status is **not**
/// explained per row: it is one fact about the whole screen and is stated once,
/// above the list.
class VendorProductAssignmentRowAction extends StatelessWidget {
  const VendorProductAssignmentRowAction({
    super.key,
    required this.productId,
    required this.productStatus,
    required this.assignment,
  });

  final String productId;

  /// The Product's own status, from the canonical detail row.
  final VendorProductStatus productStatus;

  final VendorProductAssignedRetailer assignment;

  @override
  Widget build(BuildContext context) {
    final VendorProductAssignmentAction? action = assignmentActionFor(
      assignment,
      productStatus,
    );

    if (action == null) {
      return _NoActionNote(
        assignment: assignment,
        productStatus: productStatus,
      );
    }

    return BlocBuilder<
      VendorProductAssignmentCubit,
      VendorProductAssignmentState
    >(
      builder: (BuildContext context, VendorProductAssignmentState state) {
        final bool busy = state.isBusyForPairing(
          productId,
          assignment.retailerOrganizationId,
        );

        return Semantics(
          button: true,
          label: switch (action) {
            VendorProductAssignmentAction.withdraw =>
              '${VendorProductCopy.withdrawSemantics} '
                  '${assignment.retailerName}.',
            VendorProductAssignmentAction.reactivate =>
              '${VendorProductCopy.reactivateSemantics} '
                  '${assignment.retailerName}.',
            // Unreachable: a fresh assignment is never offered from a row that
            // already has one. The branch exists so a future member cannot be
            // added without being spoken.
            VendorProductAssignmentAction.assign =>
              VendorProductCopy.assignRetailerSemantics,
          },
          child: SrButton(
            label: switch (action) {
              VendorProductAssignmentAction.withdraw =>
                VendorProductCopy.withdrawAssignment,
              VendorProductAssignmentAction.reactivate =>
                VendorProductCopy.reactivateAssignment,
              VendorProductAssignmentAction.assign =>
                VendorProductCopy.assignRetailer,
            },
            loadingLabel: switch (action) {
              VendorProductAssignmentAction.withdraw =>
                VendorProductCopy.withdrawing,
              VendorProductAssignmentAction.reactivate =>
                VendorProductCopy.reactivating,
              VendorProductAssignmentAction.assign =>
                VendorProductCopy.assigning,
            },
            // Withdrawal looks destructive and is not: the row survives, keeps
            // its date and stays counted. The outline treatment rather than the
            // danger one, because red would say "this cannot be undone" about
            // something that reverses with one press and erases nothing.
            variant: SrButtonVariant.outline,
            size: SrButtonSize.sm,
            icon: switch (action) {
              VendorProductAssignmentAction.withdraw => Icons.link_off_rounded,
              VendorProductAssignmentAction.reactivate =>
                Icons.restart_alt_rounded,
              VendorProductAssignmentAction.assign => Icons.add_link_rounded,
            },
            loading: busy,
            // Null while this pairing is being written, which is the
            // duplicate-confirmation guard's visible half. The cubit refuses a
            // second call regardless, and both same-state requests are
            // idempotent no-ops in SQL — so even a request that got through
            // twice could not record two decisions or create a second row.
            onPressed: busy ? null : () => _confirmAndApply(context, action),
          ),
        );
      },
    );
  }

  /// Asks first, then applies.
  ///
  /// The dialog is the screen's job and the cubit knows nothing about it, so a
  /// test can exercise the write without a widget *and* a screen cannot skip the
  /// confirmation by calling something cheaper — the only path from this row to
  /// [VendorProductAssignmentCubit.apply] is through here.
  ///
  /// Cancelling calls nothing at all: no RPC, no state change, no optimistic
  /// flip.
  Future<void> _confirmAndApply(
    BuildContext context,
    VendorProductAssignmentAction action,
  ) async {
    final VendorProductAssignmentCubit cubit = context
        .read<VendorProductAssignmentCubit>();

    final bool confirmed = await confirmVendorProductAssignment(
      context,
      action: action,
      retailerName: assignment.retailerName,
    );
    if (!confirmed) {
      return;
    }

    await cubit.apply(
      productId: productId,
      // The Retailer organization id, verbatim from the canonical read. Never
      // the relationship id — the assignment table stores no such column — and
      // never the display name.
      retailerOrganizationId: assignment.retailerOrganizationId,
      action: action,
    );
  }
}

/// Why this row offers nothing, said in a sentence.
///
/// Rendered only for a withdrawn assignment: an active one always offers
/// withdrawal, and an unrecognised status is left silent because this build
/// cannot describe it honestly.
class _NoActionNote extends StatelessWidget {
  const _NoActionNote({required this.assignment, required this.productStatus});

  final VendorProductAssignedRetailer assignment;
  final VendorProductStatus productStatus;

  @override
  Widget build(BuildContext context) {
    if (assignment.assignmentStatus != VendorProductAssignmentStatus.inactive) {
      return const SizedBox.shrink();
    }
    // An inactive Product is explained once above the list, not on every row
    // it affects.
    if (!productStatus.isActive) {
      return const SizedBox.shrink();
    }

    final SrColorScheme sr = context.sr;
    final String message = assignment.hasNoRelationship
        ? VendorProductCopy.reactivateUnavailableNoRelationship
        : VendorProductCopy.reactivateUnavailable;

    // A plain `Text` rather than an icon beside a `Row`: this widget is laid out
    // inside a `Wrap` beside the cross-link button, where a `Row` would either
    // need an `Expanded` it cannot have or refuse to wrap its own text. The
    // sentence carries the whole meaning on its own, which is also why nothing
    // here relies on a glyph or a colour to say "unavailable".
    return Semantics(
      label: message,
      excludeSemantics: true,
      child: Text(
        message,
        style: SrTypography.caption.copyWith(color: sr.textMuted),
      ),
    );
  }
}
