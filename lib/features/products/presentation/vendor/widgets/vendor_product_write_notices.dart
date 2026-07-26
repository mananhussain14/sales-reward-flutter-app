import 'package:flutter/material.dart';

import '../../../../../core/errors/failure.dart';
import '../../../../../core/widgets/widgets.dart';
import '../cubit/vendor_product_write_notice.dart';
import 'vendor_product_copy.dart';

/// A form-level write refusal, worded from the discriminant alone.
///
/// Every sentence it can render comes from [VendorProductCopy]. **No backend text
/// reaches this widget**: it is handed a [Failure], which carries a discriminant
/// and at most a form-field key, and no Postgres message, table name, constraint
/// name, function name, role code, permission code or SQLSTATE can travel inside
/// one.
///
/// The mapping is deliberately coarse where the backend is coarse:
///
/// * [DeniedFailure] is **one** wording for an unauthorized caller, a product that
///   does not exist, and a product belonging to another Vendor. The backend refuses
///   all three byte-identically, precisely so that an id sweep reveals neither the
///   existence nor the size of another Vendor's catalogue, and a client that told
///   them apart would hand that oracle back. It names no permission.
/// * [DuplicateFailure] reaching *here* means the backend did not attribute the
///   conflict to a field — an attributed one is rendered under its own control
///   instead — so the wording stays unspecific rather than pointing at an input
///   that may be fine.
/// * [InvalidFailure] is generic. The backend's five validation messages are English
///   prose this client does not parse, and anything a person can act on has already
///   been reported by this app's own checks against the same rules.
/// * [UnavailableFailure] is offered as retryable, and is **never** worded as a
///   permission problem. Nothing was written, so another attempt is legitimate.
class VendorProductWriteAlert extends StatelessWidget {
  const VendorProductWriteAlert({super.key, required this.failure});

  final Failure failure;

  @override
  Widget build(BuildContext context) {
    final (String title, String message) = switch (failure) {
      DeniedFailure() => (
        VendorProductCopy.writeDeniedTitle,
        VendorProductCopy.writeDeniedBody,
      ),
      UnauthenticatedFailure() => (
        VendorProductCopy.writeSignedOutTitle,
        VendorProductCopy.writeSignedOutBody,
      ),
      DuplicateFailure() => (
        VendorProductCopy.duplicateUnattributedTitle,
        VendorProductCopy.duplicateUnattributedBody,
      ),
      InvalidFailure() => (
        VendorProductCopy.invalidWriteTitle,
        VendorProductCopy.invalidWriteBody,
      ),
      // `55000` cannot arise from these three writes — it belongs to the assignment
      // functions, which this milestone does not call — and a missing capability
      // cannot either, since all three RPCs are deployed. Both fall to the generic
      // operational wording rather than to a sentence invented for a case the
      // contract does not produce.
      NotReadyFailure() || NotImplementedFailure() || UnavailableFailure() => (
        VendorProductCopy.writeUnavailableTitle,
        VendorProductCopy.writeUnavailableBody,
      ),
    };

    return SrAlert(tone: SrAlertTone.error, title: title, message: message);
  }
}

/// The acknowledgement for a write that landed, shown on the canonical product
/// screen beside the values it was read back with.
///
/// Every wording here is true of a **no-op** as well as of a real change: an edit
/// that matched what was stored, and a status set to the one already held, both
/// write nothing and both succeed silently, and the contract makes them deliberately
/// indistinguishable so no client has to tell "nothing changed" apart from "the
/// write failed". So nothing here claims a change was made — only that what is on
/// screen is what is on record.
///
/// The two `unconfirmed` notices are a success in a quieter voice. A 2xx from a
/// `void` write means the transaction committed, so they never say the change was
/// lost; they say it could not be confirmed from the response and point at the
/// figures that were re-read, which are the authority either way.
class VendorProductWriteNoticeAlert extends StatelessWidget {
  const VendorProductWriteNoticeAlert({super.key, required this.notice});

  final VendorProductWriteNotice notice;

  @override
  Widget build(BuildContext context) {
    final (SrAlertTone tone, String title, String message) = switch (notice) {
      VendorProductWriteNotice.created => (
        SrAlertTone.success,
        VendorProductCopy.createdTitle,
        VendorProductCopy.createdBody,
      ),
      VendorProductWriteNotice.updated => (
        SrAlertTone.success,
        VendorProductCopy.updatedTitle,
        VendorProductCopy.updatedBody,
      ),
      VendorProductWriteNotice.statusChanged => (
        SrAlertTone.success,
        VendorProductCopy.statusChangedTitle,
        VendorProductCopy.statusChangedBody,
      ),
      VendorProductWriteNotice.updateUnconfirmed ||
      VendorProductWriteNotice.statusUnconfirmed => (
        SrAlertTone.info,
        VendorProductCopy.unconfirmedWriteTitle,
        VendorProductCopy.unconfirmedWriteBody,
      ),
    };

    return SrAlert(tone: tone, title: title, message: message);
  }
}
