import 'package:equatable/equatable.dart';

/// Why an extraction call produced no usable answer.
///
/// ## Three different things are *not* in this union, on purpose
///
/// A great deal of what a review screen must react to is **not** a problem at
/// all, and modelling it here would be the mistake:
///
/// * **A failed extraction** is a successful read of a `FAILED` attempt. It
///   arrives as a `ReceiptExtraction` with a status and a failure code.
/// * **Attempts exhausted** is `ReceiptExtractionRequestOutcome.exhausted`, a
///   200 carrying honest counters.
/// * **Runtime disabled** is `EXTRACTION_UNAVAILABLE`, which the backend
///   returns for a shut gate *and* for broken infrastructure alike, refusing to
///   say which. Splitting it here would mean inventing a distinction the
///   contract deliberately withholds.
///
/// Everything in this union is a call that did not deliver an answer.
///
/// ## No case carries backend text
///
/// No message, no SQLSTATE, no HTTP body, no URL, no token, no id. The Edge
/// Functions log a fixed category and return a closed status vocabulary; this
/// union is that vocabulary plus the two faults only a client can observe.
sealed class ReceiptExtractionProblem extends Equatable {
  const ReceiptExtractionProblem();

  @override
  List<Object?> get props => const <Object?>[];
}

/// `401`. There is no usable session. Signing in again is the way forward, and
/// this is never presented as a permission problem.
final class ExtractionUnauthenticatedProblem extends ReceiptExtractionProblem {
  const ExtractionUnauthenticatedProblem();
}

/// `403 denied` — SQLSTATE `42501`.
///
/// The caller is not an authorized Sales Staff member at all. Carries no
/// detail, because the backend gives none.
final class ExtractionForbiddenProblem extends ReceiptExtractionProblem {
  const ExtractionForbiddenProblem();
}

/// `404 not-found`.
///
/// Deliberately overloaded, and the client must preserve that:
///
/// > *"Unknown, another Sales Staff member's, another Retailer's, `RESERVED`,
/// > `UPLOAD_FAILED` — all byte-identical. A distinguishable refusal would
/// > confirm somebody else's receipt."*
///
/// It also covers "you own this receipt and no attempt exists yet", which costs
/// the caller nothing: they already know they own it. Never render this as
/// "that is not yours".
final class ExtractionNotFoundProblem extends ReceiptExtractionProblem {
  const ExtractionNotFoundProblem();
}

/// `400 invalid`, or an input this client refused before sending.
///
/// [reason] is a fixed token from the endpoints' own closed vocabulary — never a
/// parse message and never the offending value.
final class ExtractionInvalidRequestProblem extends ReceiptExtractionProblem {
  const ExtractionInvalidRequestProblem(this.reason);

  final ExtractionInvalidReason reason;

  @override
  List<Object?> get props => <Object?>[reason];
}

/// SQLSTATE `22023`, on a confirmation and on nothing else.
///
/// The scale this client stated for the amounts is not the one the backend
/// records for that currency — or none was stated at all, which the backend
/// treats as the same defect for the same reason: in neither case is there a
/// verified agreement about what the integers mean.
///
/// It is **not** an unsupported currency (that is still `23514`), not a denial,
/// not an outage and not a transport fault. It means the width has to be
/// established again before another confirmation may be attempted, and nothing
/// in this application resends the confirmation on its own — a mis-scaled
/// confirmation is immutable, so a resend that guessed the same width again
/// would either fail identically or, worse, succeed against a width that had
/// meanwhile changed.
///
/// Carries no SQLSTATE, no Postgres message and no expected value. The backend
/// deliberately names none of them, and a client that showed "expected 0" would
/// be inviting somebody to retype a figure to match a number they cannot check.
final class ExtractionCurrencyScaleMismatchProblem
    extends ReceiptExtractionProblem {
  const ExtractionCurrencyScaleMismatchProblem();
}

/// `503 unavailable`.
///
/// The endpoint could not complete: missing server configuration, a database
/// call that failed or timed out, an unknown fixture, an unexpected throw.
/// Operational, and never an authorization answer. Retrying is safe **for the
/// reads**; see the repository for why a mutating call is not retried
/// automatically.
final class ExtractionServiceUnavailableProblem
    extends ReceiptExtractionProblem {
  const ExtractionServiceUnavailableProblem();
}

/// The request never reached an answer: a socket fault, a timeout, a dropped
/// connection.
///
/// Kept apart from [ExtractionServiceUnavailableProblem] because they mean
/// different things for a **mutating** call. A `503` is a server that decided
/// not to act; a transport fault is the absence of a decision, and a receipt
/// extraction request that vanished mid-flight may still have consumed one of
/// the three attempts. Nothing here resends on its own.
final class ExtractionNetworkProblem extends ReceiptExtractionProblem {
  const ExtractionNetworkProblem();
}

/// A `200` this build could not understand, or a row that is not the shape it
/// was written against.
///
/// Never degraded to an empty list, a null extraction or a fabricated success.
/// "Unreadable" and "nothing there" are different answers.
final class ExtractionMalformedResponseProblem
    extends ReceiptExtractionProblem {
  const ExtractionMalformedResponseProblem();
}

/// A status or a `status` token this build has no rule for.
///
/// Fails closed: it is never treated as success, and never as a denial.
final class ExtractionUnknownProblem extends ReceiptExtractionProblem {
  const ExtractionUnknownProblem();
}

/// The reasons a `400 invalid` may carry.
///
/// The endpoints' closed list, plus [unknown] for a token a future backend
/// adds — which renders as generic copy rather than leaking a raw string.
///
/// [invalidSubmissionId] is also produced locally, before a request leaves the
/// device, when a caller passes something that is not shaped like a UUID.
enum ExtractionInvalidReason {
  methodNotAllowed('method-not-allowed'),
  malformedBody('malformed-body'),
  bodyTooLarge('body-too-large'),
  unknownField('unknown-field'),
  invalidSubmissionId('invalid-submission-id'),

  /// A rule the client checked itself, or one the backend named in a token this
  /// build does not recognise. The offending value is never retained.
  unknown('');

  const ExtractionInvalidReason(this.code);

  /// The backend token, or the empty string for [unknown].
  final String code;

  /// Maps a backend token, falling back to [unknown].
  static ExtractionInvalidReason fromCode(String? raw) {
    if (raw == null) {
      return unknown;
    }
    for (final ExtractionInvalidReason reason in values) {
      if (reason != unknown && reason.code == raw) {
        return reason;
      }
    }
    return unknown;
  }
}
