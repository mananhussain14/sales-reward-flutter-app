import '../../../../core/errors/failure.dart';
import '../entities/vendor_retailer_lifecycle_status.dart';

/// The outcome of the Vendor Retailer lifecycle **write**.
///
/// Three cases, not two, and the third is the one that matters.
///
/// `ReadResult<T>` has two because a read either answered or did not, and a read
/// that did not answer changed nothing. A write is different: it can leave the
/// database changed while leaving *this client* unable to describe the change.
/// So there is a case for "it definitely did not happen"
/// ([VendorRetailerWriteFailure]) and a separate case for "it happened, but the
/// answer could not be read" ([VendorRetailerWriteUnconfirmed]) — because the
/// safe response to those two is opposite. One may be attempted again. The other
/// must never be retried, automatically or by a re-armed button.
///
/// This is the same distinction `VendorProductWriteResult` draws, for the same
/// reason. It is kept local to this feature for the same reason that one is: a
/// write's outcomes are shaped by the operation, and a shared `WriteResult<T>`
/// would either lose the shape or accumulate cases no caller has. It is
/// deliberately **not generic** — there is exactly one lifecycle write, and it
/// has exactly one success shape.
///
/// A [VendorRetailerWriteFailure] carries a [Failure] discriminant and **never**
/// the backend's own text. Postgres messages name tables, columns, constraints
/// and functions; none of that reaches a screen through this type.
sealed class VendorRetailerWriteResult {
  const VendorRetailerWriteResult();
}

/// The write committed **and** its answer was understood.
///
/// [confirmedStatus] is the status the database reported both rows now hold —
/// never the status that was requested. The two are the same on the ordinary
/// path, but stating the database's answer rather than the browser's request is
/// what makes this screen honest when they are not.
///
/// [statusChanged] is the RPC's own `status_changed` flag, and it is carried
/// because "you did that" and "somebody already had" are different things to an
/// administrator. A request for the status a Retailer already holds performs no
/// `UPDATE`, writes no audit row and does not move `updated_at`; it is an
/// idempotent no-op reported honestly rather than as a conflict.
final class VendorRetailerWriteSuccess extends VendorRetailerWriteResult {
  const VendorRetailerWriteSuccess({
    required this.confirmedStatus,
    required this.statusChanged,
  });

  /// The status **both** rows now hold, as the database reported it. The parser
  /// refuses a response whose two statuses disagree, so one value is enough.
  final VendorRetailerLifecycleStatus confirmedStatus;

  /// Whether this call actually moved the two rows.
  final bool statusChanged;
}

/// The write **succeeded**, but its answer could not be described.
///
/// Reachable from exactly one place: a call PostgREST reported no error for —
/// which means the transaction **committed** — whose body the strict parser
/// could not trust. Every parse failure lands here: zero rows, several rows, a
/// missing, malformed or *wrong* relationship id, an out-of-vocabulary status,
/// two statuses that disagree, and a non-boolean change flag.
///
/// Three rules follow, and all three are the point of having this case at all:
///
/// * **It is never reported as a failure.** Telling a Vendor a Retailer was not
///   deactivated when it was is the worst answer available.
/// * **It is never reported as "unchanged".** That would claim nothing happened
///   when an entire Retailer may have just been deactivated.
/// * **It is never retried**, automatically or by a re-armed button. There is
///   nothing left to retry. The canonical detail is re-read instead, because it
///   is the only authority on what the two rows now hold.
final class VendorRetailerWriteUnconfirmed extends VendorRetailerWriteResult {
  const VendorRetailerWriteUnconfirmed();
}

/// The write did **not** happen.
///
/// Every deployed refusal raises, and a raise rolls the whole function back — no
/// status change on either row, and no audit row. So a caller here may safely
/// offer the person another attempt.
///
/// The [Failure] is a discriminant chosen from the SQLSTATE alone. It never
/// carries a message, a constraint name, a SQLSTATE, an identifier, or any hint
/// of *which* of the four `55000` causes applied — the multi-Vendor case among
/// them must not disclose that another tenant exists.
final class VendorRetailerWriteFailure extends VendorRetailerWriteResult {
  const VendorRetailerWriteFailure(this.failure);

  final Failure failure;
}
