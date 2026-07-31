import 'package:equatable/equatable.dart';

import 'receipt_civil_date.dart';
import 'receipt_civil_time.dart';
import 'receipt_confirmation_entry_mode.dart';
import 'receipt_confirmation_field.dart';

/// The one immutable confirmation a receipt may carry.
///
/// One per receipt, enforced by a unique constraint that is also the concurrency
/// authority. There is no update, no delete and no revision path in the
/// contract, so this entity has no `copyWith` that could suggest otherwise.
///
/// ## Four of these fields are derived and cannot be sent
///
/// [entryMode], [changedFields], [sourceExtractionId] and [confirmationId] are
/// all server-derived — the first two as *outcomes* of the confirmation, decided
/// by comparing what was sent against what was read. `confirm_receipt_extraction`
/// takes ten parameters: the submission id and nine values about the receipt,
/// one of which is the currency's minor unit. **None** of the ten is an entry
/// mode, a changed-fields list, an extraction id, an organization id, a shop id
/// or a profile id.
///
/// ## What is absent
///
/// There is no duplicate signal, no reward, no coin amount and no review state,
/// because none exists in the backend. There is also no `retailer_shop_id` or
/// `confirmed_by_profile_id`: both are stored, and neither is returned.
final class ReceiptConfirmation extends Equatable {
  const ReceiptConfirmation({
    required this.confirmationId,
    required this.entryMode,
    required this.changedFields,
    required this.transactionDate,
    required this.currencyCode,
    required this.currencyMinorUnit,
    required this.totalMinor,
    required this.confirmedAt,
    this.sourceExtractionId,
    this.transactionTime,
    this.subtotalMinor,
    this.taxTotalMinor,
    this.merchantName,
    this.documentNumber,
  });

  /// `confirmation_id`.
  final String confirmationId;

  final ReceiptConfirmationEntryMode entryMode;

  /// `changed_fields` — empty for a [ReceiptConfirmationEntryMode.manual] or
  /// [ReceiptConfirmationEntryMode.extracted] confirmation, by construction.
  final List<ReceiptConfirmationField> changedFields;

  /// `source_extraction_id` — the `SUCCEEDED` attempt these values were
  /// compared against, or null when there was none. Never a caller's choice.
  final String? sourceExtractionId;

  /// `transaction_date` — required, and a civil date.
  final ReceiptCivilDate transactionDate;

  /// `transaction_time` — optional, stored truncated to the minute.
  final ReceiptCivilTime? transactionTime;

  /// `currency_code` — an ISO 4217 code, foreign-keyed to the seeded list.
  final String currencyCode;

  /// `currency_minor_unit` — 0, 2, 3 or 4. Non-null here: the currency column
  /// is `not null` and the read joins on it.
  final int currencyMinorUnit;

  /// `total_minor` — required, **integer minor units**, never a double.
  final int totalMinor;

  /// `subtotal_minor` — optional. Null is not zero.
  final int? subtotalMinor;

  /// `tax_total_minor` — optional. Null is not zero: *"zero tax is a fact,
  /// unknown tax is not"*.
  final int? taxTotalMinor;

  final String? merchantName;
  final String? documentNumber;

  /// `confirmed_at`, in UTC.
  final DateTime confirmedAt;

  /// Whether a human corrected anything the provider read.
  bool get wasCorrected => changedFields.isNotEmpty;

  @override
  List<Object?> get props => <Object?>[
    confirmationId,
    entryMode,
    changedFields,
    sourceExtractionId,
    transactionDate,
    transactionTime,
    currencyCode,
    currencyMinorUnit,
    totalMinor,
    subtotalMinor,
    taxTotalMinor,
    merchantName,
    documentNumber,
    confirmedAt,
  ];
}
