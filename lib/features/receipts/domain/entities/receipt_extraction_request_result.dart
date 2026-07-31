import 'package:equatable/equatable.dart';

import 'receipt_extraction.dart';
import 'receipt_extraction_request_outcome.dart';

/// The answer to "please read this receipt".
///
/// The counters here are the **top level** of the `request-receipt-extraction`
/// body, and they are the authority for this call. The nested [extraction] also
/// carries counters — it is the same caller-scoped re-read every response is
/// built from — and the two can differ by design in one place: the function
/// pins the top-level `retry_allowed` to `false` on every branch that reports
/// pre-existing state, because a retry is not what that branch is answering.
/// Read [retryAllowed] for "may I ask again now"; read the extraction's own copy
/// only when rendering the attempt itself.
///
/// [extraction] is null when no attempt row exists for the receipt — the
/// `ALREADY_CONFIRMED`-with-no-attempt case (a `MANUAL` confirmation needs no
/// extraction) and the shut-gate case where nothing has ever been created.
final class ReceiptExtractionRequestResult extends Equatable {
  const ReceiptExtractionRequestResult({
    required this.outcome,
    required this.attemptsUsed,
    required this.attemptsRemaining,
    required this.retryAllowed,
    required this.manualConfirmationAllowed,
    this.extraction,
  });

  final ReceiptExtractionRequestOutcome outcome;

  /// A fact about persisted rows. Never an availability signal — see
  /// [retryAllowed].
  final int attemptsUsed;

  /// `greatest(0, 3 - attempts_used)`. Also a fact, also not availability.
  final int attemptsRemaining;

  /// The only field that carries availability, and the Edge layer may only
  /// narrow it. This client never widens it and never reconstructs it.
  final bool retryAllowed;

  /// Whether the reviewer may type the values in themselves.
  final bool manualConfirmationAllowed;

  /// The attempt this call ended up pointing at, when one exists.
  final ReceiptExtraction? extraction;

  @override
  List<Object?> get props => <Object?>[
    outcome,
    attemptsUsed,
    attemptsRemaining,
    retryAllowed,
    manualConfirmationAllowed,
    extraction,
  ];
}
