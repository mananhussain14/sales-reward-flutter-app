import '../../../../core/errors/failure.dart';

/// The outcome of a receipt **read**.
///
/// Two cases, mirroring the discriminated unions the rest of the application
/// already returns. Deliberately local to this feature rather than promoted into
/// `core/`: one feature is not enough evidence for a shared abstraction, and a
/// premature `Result<T>` tends to accumulate helpers nobody needs.
///
/// A [ReceiptReadFailure] carries a [Failure] discriminant and never the
/// backend's own text. Postgres messages name tables, columns, functions and
/// policies; none of that reaches a screen through this type.
sealed class ReceiptResult<T> {
  const ReceiptResult();
}

/// The read succeeded. [value] is already parsed into domain entities — no raw
/// SDK map ever travels past this boundary.
final class ReceiptReadSuccess<T> extends ReceiptResult<T> {
  const ReceiptReadSuccess(this.value);

  final T value;
}

/// The read did not produce an answer.
///
/// A malformed response lands here as [UnavailableFailure], never as a denial
/// and never as a fabricated empty list: "you are not allowed" and "the backend
/// answered incomprehensibly" are different events and only one is worth
/// retrying.
final class ReceiptReadFailure<T> extends ReceiptResult<T> {
  const ReceiptReadFailure(this.failure);

  final Failure failure;
}
