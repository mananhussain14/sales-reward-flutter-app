import 'package:flutter/material.dart';

import '../../../domain/entities/retailer_staff_lifecycle_action.dart';
import 'retailer_staff_lifecycle_copy.dart';

/// Asks before a staff member's access changes, and answers whether it may
/// proceed.
///
/// ## Both directions confirm
///
/// Deactivation, because it stops a colleague working; and reactivation too,
/// because this application confirms every write that changes what somebody can
/// see, and a surface where one direction asks and the other does not teaches
/// people not to read the one that does.
///
/// ## What each body has to say, and why
///
/// * **Deactivate** — they lose access including receipt submission; anyone
///   already signed in is blocked on their next server-reaching action rather
///   than signed out; profile, sign-in, role, Shop assignments, receipts and
///   history are **kept**; reactivation returns their previous access. Every one
///   of those is provable from the deployed function, which writes `status` and
///   `deactivated_at` and contains no `DELETE`.
/// * **Reactivate** — access returns straight away; the previous role and Shop
///   assignments were never removed, so nothing needs setting up again; receipt
///   access resumes according to what they already hold. That last clause is the
///   one a reader would otherwise get wrong: reactivation restores what was
///   preserved, it does not grant anything new.
///
/// ## The colleague's name is display only
///
/// It is put in the title so the dialog is unambiguous about who it is about —
/// two colleagues may share a role and a status. It comes from the canonical
/// roster, it is never sent anywhere, and it is never an authorization input: the
/// RPC accepts no name, and the write is addressed by the membership id alone. No
/// identifier appears in the dialog at all.
///
/// ## Dismissal is a refusal
///
/// A tap outside, an escape key or a back gesture returns `false`. A change
/// nobody confirmed is a change nobody asked for.
///
/// The dialog is only ever open *before* a request exists — it is popped the
/// moment the primary action is chosen, and the progress state belongs to the
/// card control beneath it — so there is no window in which dismissing could
/// abandon a committed write.
Future<bool> confirmRetailerStaffLifecycle(
  BuildContext context, {
  required RetailerStaffLifecycleAction action,
  required String memberName,
}) async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text('${action.dialogTitle}\n$memberName'),
      // Scrollable, because the deactivation body is deliberately several
      // paragraphs — every one of them a claim the backend proves — and it must
      // stay readable on a small phone and under large text scaling rather than
      // being truncated to fit.
      content: SingleChildScrollView(
        child: Text(
          RetailerStaffLifecycleCopy.confirmBody(
            isDeactivation: action.isDeactivation,
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text(RetailerStaffLifecycleCopy.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(action.confirmLabel),
        ),
      ],
    ),
  );

  return confirmed ?? false;
}
