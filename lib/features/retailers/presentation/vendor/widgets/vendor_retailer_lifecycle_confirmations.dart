import 'package:flutter/material.dart';

import '../../../domain/entities/vendor_retailer_lifecycle_action.dart';
import 'vendor_retailer_lifecycle_copy.dart';

/// Asks before a Retailer's lifecycle changes, and answers whether it may
/// proceed.
///
/// ## Both directions confirm
///
/// Deactivation, because it stops every person at a whole company from working;
/// and reactivation too, because this application confirms every write that
/// changes what a Retailer can see, and a surface where one direction asks and
/// the other does not teaches people not to read the one that does.
///
/// ## What each body has to say, and why
///
/// * **Deactivate** — Owner, Manager and Sales Staff access stops; people
///   already signed in are blocked on their next refresh or protected action
///   rather than signed out; receipt submission stops; new Shop creation,
///   product assignment and invitation operations stop; existing users, Shops,
///   assignments, receipts and invitations are **preserved**; and reactivation
///   restores prior access where those records remain valid. Every one of those
///   is provable from the deployed function, which moves two status columns and
///   contains no `DELETE`.
/// * **Reactivate** — the preserved users, roles, Shops and assignments become
///   available; valid unexpired invitations become usable; and receipt access
///   resumes according to the permissions and assignments each person already
///   holds. That last clause is the one a reader would otherwise get wrong:
///   reactivation restores what was preserved, it does not grant anything new.
///
/// ## The Retailer name is display only
///
/// It is put in the title so the dialog is unambiguous about which Retailer it
/// is about. It comes from the canonical detail read, it is never sent anywhere,
/// and it is never an authorization input — the RPC accepts no name, and the
/// write is addressed by the relationship id alone. No identifier appears in the
/// dialog at all.
///
/// ## Dismissal is a refusal
///
/// A tap outside, an escape key or a back gesture returns `false`. A lifecycle
/// change nobody confirmed is a lifecycle change nobody asked for.
///
/// [barrierDismissible] is left at its default `true` so Escape and an outside
/// tap both work while the dialog is open. The dialog is only ever open *before*
/// a request exists — it is popped the moment the primary action is chosen, and
/// the progress state belongs to the button beneath it — so there is no window
/// in which dismissing could abandon a committed write.
Future<bool> confirmVendorRetailerLifecycle(
  BuildContext context, {
  required VendorRetailerLifecycleAction action,
  required String retailerName,
}) async {
  final (String title, String body, String confirmLabel) = action.isDeactivation
      ? (
          VendorRetailerLifecycleCopy.deactivateConfirmTitle,
          VendorRetailerLifecycleCopy.deactivateConfirmBody,
          VendorRetailerLifecycleCopy.deactivate,
        )
      : (
          VendorRetailerLifecycleCopy.reactivateConfirmTitle,
          VendorRetailerLifecycleCopy.reactivateConfirmBody,
          VendorRetailerLifecycleCopy.reactivate,
        );

  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text('$title\n$retailerName'),
      // Scrollable, because the deactivation body is deliberately several
      // paragraphs — every one of them a claim the backend proves — and it must
      // stay readable on a small phone and under large text scaling rather than
      // being truncated to fit.
      content: SingleChildScrollView(child: Text(body)),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text(VendorRetailerLifecycleCopy.cancel),
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
