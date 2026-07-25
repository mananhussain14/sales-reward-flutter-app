import '../../../../core/errors/failure.dart';

/// The outcome of a Vendor Retailer **read**.
///
/// Two cases, mirroring the discriminated unions the rest of the application
/// already returns. A [VendorRetailerReadFailure] carries a [Failure]
/// discriminant and never the backend's own text: Postgres messages name tables,
/// columns, functions and policies, and none of that reaches a screen through
/// this type.
///
/// > **Deliberately local to this feature**, exactly as `ReceiptResult<T>` is
/// > local to receipts. The two are structurally identical, and promoting a
/// > shared `Result<T>` into `core/` is a refactor of a shipped feature rather
/// > than part of this milestone. When a third feature needs one, that is the
/// > evidence to promote it — and doing it then costs one mechanical change,
/// > where doing it now would mean editing receipt code this branch has no
/// > reason to touch.
sealed class VendorRetailerResult<T> {
  const VendorRetailerResult();
}

/// The read succeeded. [value] is already parsed into domain entities — no raw
/// SDK map ever travels past this boundary.
///
/// A `null` detail and an empty shop list are both **successes**: zero rows is a
/// real answer from the backend, and turning either into a failure would tell a
/// user an outage occurred when the database answered perfectly.
final class VendorRetailerReadSuccess<T> extends VendorRetailerResult<T> {
  const VendorRetailerReadSuccess(this.value);

  final T value;
}

/// The read did not produce an answer.
///
/// A malformed response lands here as [UnavailableFailure], never as a denial
/// and never as a fabricated empty list: "you are not allowed", "the backend
/// answered incomprehensibly" and "you manage no Retailers" are three different
/// events, and only one of them is worth retrying.
final class VendorRetailerReadFailure<T> extends VendorRetailerResult<T> {
  const VendorRetailerReadFailure(this.failure);

  final Failure failure;
}
