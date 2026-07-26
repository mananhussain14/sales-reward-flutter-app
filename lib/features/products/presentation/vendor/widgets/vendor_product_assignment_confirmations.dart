import 'package:flutter/material.dart';

import '../../../domain/entities/vendor_product_assignment_action.dart';
import 'vendor_product_copy.dart';

/// Asks before any assignment transition, and answers whether it may proceed.
///
/// ## All three transitions confirm
///
/// Withdrawal and reactivation, because each has a consequence a reader must be
/// told before it happens; and a fresh assignment too, because this application
/// confirms every write that changes what a Retailer can see, and a surface
/// where two of three actions ask and the third does not teaches people not to
/// read the ones that do.
///
/// ## What each body has to say, and why
///
/// * **Withdraw** — the assignment becomes inactive; the record stays in the
///   history with its assigned date and its place in the total; the Product is
///   not deleted; the Vendor–Retailer relationship is not affected; and it can
///   be reactivated later. Every one of those is provable from the deployed
///   function, which sets a status and contains no `DELETE`. The words *delete*,
///   *remove* and *erase* appear nowhere, because none of them happens.
/// * **Reactivate** — the assignment becomes active, the existing record is
///   reused rather than duplicated, **and its assigned date is reset to the
///   moment of reactivation**. That last clause is the one thing a reader would
///   otherwise get wrong: `assign_vendor_product_to_retailer` overwrites
///   `assigned_at` with `now()`, so the date afterwards is when *this*
///   assignment began and not when the pairing was first made.
/// * **Assign** — the Product becomes available at the Retailer, nothing about
///   the Product or the relationship changes, and withdrawing later keeps the
///   record.
///
/// Nothing here claims a Retailer has sold, stocked or received the Product. An
/// assignment records availability, and the schema records nothing else about
/// it.
///
/// ## Dismissal is a refusal
///
/// A tap outside, an escape key or a back gesture returns `false`. A transition
/// nobody confirmed is a transition nobody asked for.
Future<bool> confirmVendorProductAssignment(
  BuildContext context, {
  required VendorProductAssignmentAction action,
  required String retailerName,
}) async {
  final (String title, String body, String confirmLabel) = switch (action) {
    VendorProductAssignmentAction.withdraw => (
      VendorProductCopy.withdrawConfirmTitle,
      VendorProductCopy.withdrawConfirmBody,
      VendorProductCopy.withdrawAssignment,
    ),
    VendorProductAssignmentAction.reactivate => (
      VendorProductCopy.reactivateConfirmTitle,
      VendorProductCopy.reactivateConfirmBody,
      VendorProductCopy.reactivateAssignment,
    ),
    VendorProductAssignmentAction.assign => (
      VendorProductCopy.assignConfirmTitle,
      VendorProductCopy.assignConfirmBody,
      VendorProductCopy.assignConfirmAction,
    ),
  };

  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      // The Retailer is named in the title so the dialog is unambiguous about
      // which pairing it is about — a list of rows all offering the same verb
      // otherwise produces a dialog that could be any of them. The name is
      // display text from a trusted read; no id appears.
      title: Text('$title\n$retailerName'),
      // Scrollable, because each body is deliberately several sentences — every
      // one of them a claim the backend proves — and it must stay readable on a
      // small phone at large text scale.
      content: SingleChildScrollView(child: Text(body)),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text(VendorProductCopy.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );

  return confirmed ?? false;
}
