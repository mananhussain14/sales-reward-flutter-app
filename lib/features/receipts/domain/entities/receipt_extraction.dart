import 'package:equatable/equatable.dart';

import 'extracted_value.dart';
import 'receipt_civil_date.dart';
import 'receipt_civil_time.dart';
import 'receipt_extraction_failure_code.dart';
import 'receipt_extraction_status.dart';
import 'receipt_extraction_warning_code.dart';

/// The latest extraction attempt for one of the caller's **own** receipts.
///
/// This is the *safe client projection* — every field `get_my_receipt_extraction`
/// returns and, because the Edge layer copies it through an explicit key
/// allowlist rather than a spread, nothing else. There is no field here for
/// `provider`, `provider_model`, `provider_operation_id`, `worker_claim_token`,
/// `expires_at`, the storage coordinates, the file hash, the internal failure
/// code, `retailer_organization_id` or `requested_by_profile_id`, because none
/// of them is on the wire.
///
/// ## Counters are facts; availability is one boolean
///
/// [attemptsUsed] and [attemptsRemaining] describe **persisted rows**, nothing
/// else:
///
/// > *"These two values are facts and are never adjusted to communicate
/// > availability. A disabled gate, a dead provider and a reaped claim all
/// > leave them exactly as the persisted rows make them."*
///
/// [retryAllowed] is the only field carrying availability, and the Edge layer
/// may only ever **narrow** it. Nothing in this client may reconstruct it from
/// the counters: an app that offered "retry" because `attemptsRemaining > 0`
/// would offer it while the provider was switched off.
///
/// ## What a null value means
///
/// Every extracted field is an [ExtractedValue], because a null reading and an
/// unreadable printed figure are different facts. See that type.
final class ReceiptExtraction extends Equatable {
  const ReceiptExtraction({
    required this.submissionId,
    required this.extractionId,
    required this.status,
    required this.attemptNumber,
    required this.attemptsUsed,
    required this.attemptsRemaining,
    required this.retryAllowed,
    required this.manualConfirmationAllowed,
    required this.confirmationExists,
    required this.requestedAt,
    required this.merchantName,
    required this.documentNumber,
    required this.transactionDate,
    required this.transactionTime,
    required this.currencyCode,
    required this.total,
    required this.subtotal,
    required this.taxTotal,
    required this.warningCodes,
    required this.lineItemCount,
    this.failureCode,
    this.completedAt,
    this.currencyMinorUnit,
  });

  /// `submission_id` — the receipt, echoed back by the function.
  final String submissionId;

  /// `extraction_id` — this attempt. The only id the client ever holds for the
  /// extraction side of the feature.
  final String extractionId;

  final ReceiptExtractionStatus status;

  /// `attempt_number` — a dense `1..3`. A fourth row cannot be inserted at all.
  final int attemptNumber;

  /// `attempts_used` — `count(*)` of every persisted row for this submission,
  /// whatever its status. There is no exempt failure.
  final int attemptsUsed;

  /// `attempts_remaining` — `greatest(0, 3 - attempts_used)`.
  final int attemptsRemaining;

  /// `retry_allowed` — the **only** field that carries availability.
  final bool retryAllowed;

  /// `manual_confirmation_allowed` — blocked by exactly two things, neither of
  /// them a mode gate: an existing confirmation, and an attempt in flight.
  final bool manualConfirmationAllowed;

  /// `confirmation_exists`.
  final bool confirmationExists;

  /// `failure_code` — null unless [status] is
  /// [ReceiptExtractionStatus.failed]. One of three client codes.
  final ReceiptExtractionFailureCode? failureCode;

  /// `requested_at`, in UTC. A real instant, unlike the receipt's own date.
  final DateTime requestedAt;

  /// `completed_at`, in UTC — null while the attempt is open.
  final DateTime? completedAt;

  final ExtractedValue<String> merchantName;
  final ExtractedValue<String> documentNumber;
  final ExtractedValue<ReceiptCivilDate> transactionDate;
  final ExtractedValue<ReceiptCivilTime> transactionTime;

  /// `currency_code` — an ISO 4217 alphabetic code, kept as a string. It is
  /// never parsed into anything else and never paired with a locale here.
  final ExtractedValue<String> currencyCode;

  /// `currency_minor_unit` — 0, 2, 3 or 4, joined from `iso_currency_codes`.
  /// Null when no currency was read, so there was nothing to join against.
  ///
  /// This is how many decimal places the minor-unit amounts below have. It is
  /// **display** information: no amount is ever divided by a power of ten to
  /// store it.
  final int? currencyMinorUnit;

  /// `total_minor` — **integer minor units**, and only ever that.
  ///
  /// > *"No floating point anywhere. The minor-unit integer is assembled by
  /// > string concatenation, so `19.99` becomes the characters `"1999"` and
  /// > then the integer `1999` — never the double `19.99` multiplied by 100,
  /// > which is wrong for a long tail of ordinary values."*
  ///
  /// Nothing in this client converts one of these to a double. Formatting for a
  /// screen is a presentation concern and uses [currencyMinorUnit] to place a
  /// separator in a string.
  final ExtractedValue<int> total;

  /// `subtotal_minor` — integer minor units. Null is not zero.
  final ExtractedValue<int> subtotal;

  /// `tax_total_minor` — integer minor units.
  ///
  /// Null and `0` are different facts and the backend keeps them apart: *"zero
  /// tax is a fact, unknown tax is not"*. Defaulting either way here would
  /// invent a figure the receipt never carried.
  final ExtractedValue<int> taxTotal;

  /// `warning_codes`, in the order the backend returned them.
  final List<ReceiptExtractionWarningCode> warningCodes;

  /// `line_item_count` — informational. Line items themselves are a separate
  /// read, because most screens never need them.
  final int lineItemCount;

  /// Whether the reading is stored and safe to present as extracted values.
  bool get hasReading => status == ReceiptExtractionStatus.succeeded;

  /// Whether a reviewer may proceed to type the values in themselves.
  ///
  /// The backend's own boolean, never re-derived. A failed attempt, an
  /// exhausted receipt and a receipt whose gate is shut are all confirmable —
  /// *"manual confirmation never consults either mode gate"*.
  bool get isConfirmable => manualConfirmationAllowed;

  @override
  List<Object?> get props => <Object?>[
    submissionId,
    extractionId,
    status,
    attemptNumber,
    attemptsUsed,
    attemptsRemaining,
    retryAllowed,
    manualConfirmationAllowed,
    confirmationExists,
    failureCode,
    requestedAt,
    completedAt,
    merchantName,
    documentNumber,
    transactionDate,
    transactionTime,
    currencyCode,
    currencyMinorUnit,
    total,
    subtotal,
    taxTotal,
    warningCodes,
    lineItemCount,
  ];
}
