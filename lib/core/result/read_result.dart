import '../errors/failure.dart';

/// The outcome of a backend **read**.
///
/// Two cases, mirroring the discriminated unions the web application already
/// returns from every operation. A [ReadFailure] carries a [Failure]
/// discriminant and never the backend's own text: Postgres messages name
/// tables, columns, functions and policies, and none of that reaches a screen
/// through this type.
///
/// ## Why this is here now, and was not before
///
/// The receipt feature declared a local `ReceiptResult<T>` and said so
/// explicitly: *"one feature is not enough evidence for a shared abstraction,
/// and a premature `Result<T>` tends to accumulate helpers nobody needs."* The
/// Vendor Retailer feature repeated the shape and recorded the trigger — *"when
/// a third feature needs one, that is the evidence to promote it."*
///
/// Vendor Users is the third. So this is the promotion, and it is deliberately
/// the whole of it: two constructors, no helpers, no `map`, no `fold`, no
/// `getOrElse`. Every one of those would be a place for a caller to turn a
/// failure into a value, which is precisely what the exhaustive `switch` at each
/// call site exists to prevent.
///
/// `VendorRetailerResult<T>` is now an alias of this type, so the Retailer
/// feature moved with zero call-site changes. `ReceiptResult<T>` stays separate
/// for now: it sits beside `ReceiptSubmissionOutcome`, which models a *write*
/// with four settled outcomes rather than a read, and untangling the two is a
/// receipt-milestone change rather than this one.
sealed class ReadResult<T> {
  const ReadResult();
}

/// The read succeeded. [value] is already parsed into domain entities — no raw
/// SDK map ever travels past this boundary.
///
/// A `null` single-row result and an empty list are both **successes**: zero
/// rows is a real answer from the backend, and turning either into a failure
/// would tell a user an outage occurred when the database answered perfectly.
final class ReadSuccess<T> extends ReadResult<T> {
  const ReadSuccess(this.value);

  final T value;
}

/// The read did not produce an answer.
///
/// A malformed response lands here as [UnavailableFailure], never as a denial
/// and never as a fabricated empty list: "you are not allowed", "the backend
/// answered incomprehensibly" and "there is nothing to show" are three different
/// events, and only one of them is worth retrying.
final class ReadFailure<T> extends ReadResult<T> {
  const ReadFailure(this.failure);

  final Failure failure;
}
