import '../../../../core/errors/failure.dart';

/// The outcome of a Vendor Product **write**.
///
/// Three cases, not two, and the third is the one that matters.
///
/// `ReadResult<T>` has two because a read either answered or did not, and a read
/// that did not answer changed nothing. A write is different: it can leave the
/// database changed while leaving *this client* unable to describe the change. So
/// there is a case for "it definitely did not happen"
/// ([VendorProductWriteFailure]) and a separate case for "it happened, but the
/// answer could not be read" ([VendorProductWriteUnconfirmed]) — because the
/// safe response to those two is opposite. One may be retried. The other must
/// never be retried automatically, or a second product appears.
///
/// This is the same distinction `ReceiptSubmissionOutcome` draws with
/// `ReceiptSubmissionUnconfirmed`, for the same reason, and it is kept local to
/// this feature for the same reason that one is: a write's outcomes are shaped by
/// the operation, and a shared `WriteResult<T>` would either lose the shape or
/// accumulate cases no caller has.
///
/// A [VendorProductWriteFailure] carries a [Failure] discriminant and **never**
/// the backend's own text. Postgres messages name tables, columns, constraints
/// and functions; none of that reaches a screen through this type.
sealed class VendorProductWriteResult<T> {
  const VendorProductWriteResult();
}

/// The write completed and the backend's answer was understood.
///
/// [value] is the new product id for a create, and `null` for an edit or a status
/// change — both of which `return void`, so there is nothing to carry and nothing
/// is invented. In particular this is **not** a product row: the write RPCs
/// return none, and a screen that needs one re-reads
/// `get_vendor_product_detail`.
///
/// A backend **no-op** arrives here too, indistinguishably: an edit that changed
/// nothing and a status change to the status already held are both successes in
/// SQL, deliberately, so that a client never has to tell "nothing changed" apart
/// from "the write failed".
final class VendorProductWriteSuccess<T> extends VendorProductWriteResult<T> {
  const VendorProductWriteSuccess(this.value);

  final T value;
}

/// The write **succeeded**, but its answer could not be read.
///
/// Reachable from exactly one place: a `create_vendor_product` call that returned
/// success without a value shaped like a uuid. The insert and its audit row are
/// committed — the function raises rather than returns on every refusal — so the
/// product exists and this client simply cannot address it.
///
/// Two rules follow, and both are the point of having this case at all:
///
/// * **it is never reported as a failure.** Telling a Vendor their product was
///   not created when it was is the worst answer available.
/// * **it is never retried, automatically or by a re-armed button.** A second
///   create would either duplicate the product or be refused by the unique index
///   as a duplicate code, and neither is a useful thing to do to somebody who has
///   already succeeded. The catalogue is refreshed instead, because it is the only
///   authority on what exists.
final class VendorProductWriteUnconfirmed<T>
    extends VendorProductWriteResult<T> {
  const VendorProductWriteUnconfirmed();
}

/// The write did **not** happen.
///
/// Every deployed refusal raises, and a raise rolls the whole function back — no
/// product row, no status change, no audit row, and no assignment touched. So a
/// caller here may safely offer the person another attempt.
///
/// The [Failure] is a discriminant chosen from the SQLSTATE, plus — for a
/// duplicate alone — a field hint. It never carries a message, a constraint name
/// or a SQLSTATE to the screen.
final class VendorProductWriteFailure<T> extends VendorProductWriteResult<T> {
  const VendorProductWriteFailure(this.failure);

  final Failure failure;
}
