import 'package:flutter/material.dart';

import '../../../../../core/errors/failure.dart';
import '../../../../../core/widgets/widgets.dart';
import '../cubit/vendor_retailer_lifecycle_notice.dart';
import 'vendor_retailer_lifecycle_copy.dart';

/// A lifecycle write refusal, worded from the discriminant alone.
///
/// Every sentence it can render comes from [VendorRetailerLifecycleCopy]. **No
/// backend text reaches this widget**: it is handed a [Failure], which carries a
/// discriminant and at most a form-field key, and no Postgres message, table
/// name, constraint name, function name, role code, permission code, SQLSTATE or
/// identifier can travel inside one.
///
/// The mapping is deliberately coarse where the backend is coarse:
///
/// * [DeniedFailure] is **one** wording for an unauthenticated caller, a caller
///   lacking `RETAILERS_MANAGE`, an unknown relationship, another Vendor's
///   relationship, and a target whose organization is not a `RETAILER`. SQL
///   refuses all five with the same code and the same message, precisely so that
///   sweeping relationship ids reveals neither which exist nor whose they are —
///   and a client that told them apart would hand that oracle back. It names no
///   permission.
/// * [NotReadyFailure] is `55000`, and it names **no cause**. An inconsistent
///   pair, a `DEACTIVATED` row, another Vendor still holding a live relationship
///   with this Retailer, and a compare-and-set row-count drift all arrive here
///   identically. The multi-Vendor case among them must not disclose that
///   another tenant exists, so this wording mentions no other organization, no
///   count and no reason.
/// * [InvalidFailure] covers `23514` — a requested status the function does not
///   accept — and `22P02`, a malformed identifier. Both are defects in the
///   request rather than anything the person did, and neither is retryable, so
///   the wording does not invite one.
/// * [UnavailableFailure] is the only one worded as an operational problem, and
///   it says explicitly that nothing was retried automatically.
class VendorRetailerLifecycleFailureAlert extends StatelessWidget {
  const VendorRetailerLifecycleFailureAlert({super.key, required this.failure});

  final Failure failure;

  @override
  Widget build(BuildContext context) {
    final (String title, String message) = switch (failure) {
      DeniedFailure() => (
        VendorRetailerLifecycleCopy.deniedTitle,
        VendorRetailerLifecycleCopy.deniedBody,
      ),
      UnauthenticatedFailure() => (
        VendorRetailerLifecycleCopy.signedOutTitle,
        VendorRetailerLifecycleCopy.signedOutBody,
      ),
      InvalidFailure() => (
        VendorRetailerLifecycleCopy.invalidTitle,
        VendorRetailerLifecycleCopy.invalidBody,
      ),
      NotReadyFailure() => (
        VendorRetailerLifecycleCopy.notReadyTitle,
        VendorRetailerLifecycleCopy.notReadyBody,
      ),
      // `23505` cannot arise from this write — it touches no unique index — and
      // a missing capability cannot either, since the RPC is deployed. Both fall
      // to the generic operational wording rather than to a sentence invented
      // for a case the contract does not produce.
      DuplicateFailure() || NotImplementedFailure() || UnavailableFailure() => (
        VendorRetailerLifecycleCopy.unavailableTitle,
        VendorRetailerLifecycleCopy.unavailableBody,
      ),
    };

    return SrAlert(tone: SrAlertTone.error, title: title, message: message);
  }
}

/// The acknowledgement for a lifecycle write that landed, shown on the canonical
/// Retailer screen beside the statuses it was re-read with.
///
/// Every wording is chosen from the status the **database confirmed**, never
/// from the one that was requested — and the two no-op members say plainly that
/// nothing was written, because "you did that" and "somebody already had" are
/// different things to an administrator and collapsing them would claim an event
/// that never happened.
///
/// The `unconfirmed` notice is a success in a quieter voice. No error means the
/// transaction committed, so it never says the change was lost; it says it could
/// not be confirmed from the response and points at the canonical statuses,
/// which are the authority either way. It deliberately offers no retry.
class VendorRetailerLifecycleNoticeAlert extends StatelessWidget {
  const VendorRetailerLifecycleNoticeAlert({super.key, required this.notice});

  final VendorRetailerLifecycleNotice notice;

  @override
  Widget build(BuildContext context) {
    final (SrAlertTone tone, String title, String message) = switch (notice) {
      VendorRetailerLifecycleNotice.deactivated => (
        SrAlertTone.success,
        VendorRetailerLifecycleCopy.deactivatedTitle,
        VendorRetailerLifecycleCopy.deactivatedBody,
      ),
      VendorRetailerLifecycleNotice.reactivated => (
        SrAlertTone.success,
        VendorRetailerLifecycleCopy.reactivatedTitle,
        VendorRetailerLifecycleCopy.reactivatedBody,
      ),
      VendorRetailerLifecycleNotice.alreadyInactive => (
        SrAlertTone.info,
        VendorRetailerLifecycleCopy.alreadyInactiveTitle,
        VendorRetailerLifecycleCopy.alreadyInactiveBody,
      ),
      VendorRetailerLifecycleNotice.alreadyActive => (
        SrAlertTone.info,
        VendorRetailerLifecycleCopy.alreadyActiveTitle,
        VendorRetailerLifecycleCopy.alreadyActiveBody,
      ),
      VendorRetailerLifecycleNotice.unconfirmed => (
        SrAlertTone.info,
        VendorRetailerLifecycleCopy.unconfirmedTitle,
        VendorRetailerLifecycleCopy.unconfirmedBody,
      ),
    };

    return SrAlert(tone: tone, title: title, message: message);
  }
}
