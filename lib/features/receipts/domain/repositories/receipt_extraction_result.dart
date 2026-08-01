import '../entities/receipt_extraction_problem.dart';

/// The outcome of one extraction or confirmation call.
///
/// Two cases, mirroring `ReceiptResult` next door. Kept separate from it
/// deliberately: that union carries the shared `Failure` discriminant, which is
/// built from SQLSTATEs and has no vocabulary for a `404 not-found` or a `400
/// invalid` reason. Collapsing the two would have meant either widening
/// `Failure` for one feature or losing the distinctions the Edge contract is
/// careful to draw.
///
/// A [ReceiptExtractionFailed] carries a [ReceiptExtractionProblem] and never
/// the backend's own text.
sealed class ReceiptExtractionResult<T> {
  const ReceiptExtractionResult();
}

/// The call produced an answer. [value] is already parsed into domain entities —
/// no raw SDK map or HTTP body travels past this boundary.
///
/// Note that a *successful* result can describe a failed extraction, an
/// exhausted receipt or a shut gate. Those are answers, not faults.
final class ReceiptExtractionSuccess<T> extends ReceiptExtractionResult<T> {
  const ReceiptExtractionSuccess(this.value);

  final T value;
}

/// The call did not produce an answer.
final class ReceiptExtractionFailed<T> extends ReceiptExtractionResult<T> {
  const ReceiptExtractionFailed(this.problem);

  final ReceiptExtractionProblem problem;
}
