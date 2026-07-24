import 'receipt_rejection_reason.dart';

/// Every answer the `submit-receipt` Edge Function can give, and nothing else.
///
/// The function returns a **closed vocabulary** — `submitted`, `invalid`,
/// `unauthenticated`, `denied`, `duplicate`, `upload-failed`, `unavailable` —
/// paired one-to-one with an HTTP status. This union is that vocabulary plus one
/// case the function cannot report because it is about the *transport*:
/// [ReceiptSubmissionUnconfirmed].
///
/// ## The three distinctions this union exists to preserve
///
/// 1. **An outage is never a denial.** `503`/`502` and a dropped connection are
///    operational; `403` is a decision. Collapsing them would tell a Sales Staff
///    member they lack access when the network merely failed.
/// 2. **A refusal of the file is not a refusal of the person.** `400` names
///    something about the caller's own file or shop id and is safe to explain in
///    detail; `403` is deliberately indistinguishable across "not assigned",
///    "inactive", "another Retailer's" and "nonexistent", and must stay that
///    way.
/// 3. **"Failed" and "unknown" are not the same.** `502 upload-failed` is a
///    definite negative — the row is `UPLOAD_FAILED`, excluded from the
///    duplicate index, and the identical file may be sent again immediately.
///    [ReceiptSubmissionUnconfirmed] is the absence of an answer, and the one
///    case where resending automatically could create a second submission of a
///    receipt that already landed.
sealed class ReceiptSubmissionOutcome {
  const ReceiptSubmissionOutcome();
}

/// `200 submitted`. The receipt is stored and recorded.
///
/// [submissionId] is the id the function reserved. It is not a secret — the
/// caller's own history returns it — and it is the only input
/// `get_my_receipt_submission()` takes.
final class ReceiptSubmissionAccepted extends ReceiptSubmissionOutcome {
  const ReceiptSubmissionAccepted(this.submissionId);

  final String submissionId;
}

/// `400 invalid`. The file or the shop id was refused; [reason] says which.
final class ReceiptSubmissionRefused extends ReceiptSubmissionOutcome {
  const ReceiptSubmissionRefused(this.reason);

  final ReceiptRejectionReason reason;
}

/// `401 unauthenticated`. There is no usable session; signing in again is the
/// only way forward. Never presented as a permission problem.
final class ReceiptSubmissionUnauthenticated extends ReceiptSubmissionOutcome {
  const ReceiptSubmissionUnauthenticated();
}

/// `403 denied`. The caller may not submit against that shop.
///
/// Carries **no detail**, because the backend deliberately gives none: an
/// unassigned shop, an inactive shop, another Retailer's shop and a nonexistent
/// shop all produce one byte-identical answer, and that indistinguishability is
/// what stops the endpoint being used to probe another Retailer's estate one id
/// at a time.
final class ReceiptSubmissionDenied extends ReceiptSubmissionOutcome {
  const ReceiptSubmissionDenied();
}

/// `409 duplicate`. This person already has a live submission of these exact
/// bytes.
///
/// Scoped to the submitter by design, so it says nothing about anyone else's
/// receipts. Resending the same file can only produce this answer again, so the
/// only way forward is a different receipt.
final class ReceiptSubmissionDuplicate extends ReceiptSubmissionOutcome {
  const ReceiptSubmissionDuplicate();
}

/// `502 upload-failed`. Reserved, but the object did not land.
///
/// Definitely retryable: the row is `UPLOAD_FAILED` and is excluded from the
/// duplicate-protection index, so the same photo may be submitted again
/// immediately.
final class ReceiptSubmissionUploadFailed extends ReceiptSubmissionOutcome {
  const ReceiptSubmissionUploadFailed();
}

/// `503 unavailable`, or any status this client has no mapping for.
///
/// Operational. The request did not complete, so retrying is safe.
final class ReceiptSubmissionUnavailable extends ReceiptSubmissionOutcome {
  const ReceiptSubmissionUnavailable();
}

/// The transport did not deliver an answer this client can trust.
///
/// A timeout, a dropped connection mid-upload, or a `200` whose body could not
/// be understood. In every one of those the receipt **may already have been
/// stored**, so the client must not resend on its own. The recovery is to
/// refresh the submission history — which is authoritative — and let the person
/// decide.
final class ReceiptSubmissionUnconfirmed extends ReceiptSubmissionOutcome {
  const ReceiptSubmissionUnconfirmed();
}
