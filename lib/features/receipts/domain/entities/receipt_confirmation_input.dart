import 'package:equatable/equatable.dart';

import 'receipt_civil_date.dart';
import 'receipt_civil_time.dart';
import 'receipt_currency_minor_unit.dart';

/// Everything a confirmation sends, and nothing else.
///
/// Ten values, matching `confirm_receipt_extraction`'s ten parameters exactly.
/// There is **no** field here for an organization id, shop id, profile id,
/// membership id, extraction id, entry mode, changed-fields list or duplicate
/// signal — every one of those is derived server-side, and the absence of a
/// field is the structural reason this client cannot supply one.
///
/// ## Amounts are integer minor units on the way out as well as in
///
/// [totalMinor], [subtotalMinor] and [taxTotalMinor] are `int`. Nothing in this
/// class or its transport multiplies, divides or rounds them: whatever a review
/// screen parsed from a text field arrives here already as minor units, and it
/// is that integer that reaches `bigint`.
///
/// Null and `0` stay apart. An omitted subtotal is null, not zero, because the
/// comparison that derives `changed_fields` treats them as different facts.
///
/// ## [currencyMinorUnit] is required, is an `int`, and has no default
///
/// It is the **scale those integers were built with**, declared so the backend
/// can check it against its own authority and refuse rather than store a
/// mis-scaled immutable row. A default of `2` here would silently re-create the
/// defect this field exists to close — for JPY a total 100× too large, for KWD
/// 10× too small — so there is none, and there is no nullable path to the RPC
/// either. The value comes from `get_receipt_currency_minor_unit`, never from a
/// table this client carries.
final class ReceiptConfirmationInput extends Equatable {
  const ReceiptConfirmationInput({
    required this.submissionId,
    required this.transactionDate,
    required this.currencyCode,
    required this.currencyMinorUnit,
    required this.totalMinor,
    this.merchantName,
    this.documentNumber,
    this.transactionTime,
    this.subtotalMinor,
    this.taxTotalMinor,
  });

  /// The receipt. `p_submission_id`.
  final String submissionId;

  /// `p_transaction_date` — required. A civil date, sent as `YYYY-MM-DD`.
  final ReceiptCivilDate transactionDate;

  /// `p_currency_code` — required. An ISO 4217 alphabetic code, sent as a
  /// string; the backend upper-cases, trims and foreign-key checks it.
  final String currencyCode;

  /// `p_currency_minor_unit` — required. The scale the three amounts below were
  /// built with, which the backend verifies against [currencyCode]'s own.
  final int currencyMinorUnit;

  /// `p_total_minor` — required, integer minor units.
  final int totalMinor;

  /// `p_merchant_name` — optional.
  final String? merchantName;

  /// `p_document_number` — optional.
  final String? documentNumber;

  /// `p_transaction_time` — optional. Stored truncated to the minute.
  final ReceiptCivilTime? transactionTime;

  /// `p_subtotal_minor` — optional, integer minor units.
  final int? subtotalMinor;

  /// `p_tax_total_minor` — optional, integer minor units.
  final int? taxTotalMinor;

  /// The first shape rule this input breaks, or null when it breaks none.
  ///
  /// A pre-check, in the spirit of the file-size ceiling the submission flow
  /// already applies: it saves a doomed round trip and lets a form highlight a
  /// field immediately. **It does not make this client the authority.** Every
  /// rule below is enforced again in SQL, and the backend's answer is the one
  /// that counts — most obviously for the currency, where the real check is a
  /// foreign key against a 165-row seeded list this client does not carry.
  ReceiptConfirmationProblem? validate() {
    if (!_uuid.hasMatch(submissionId)) {
      return ReceiptConfirmationProblem.invalidSubmissionId;
    }
    if (!_currency.hasMatch(currencyCode.trim().toUpperCase())) {
      return ReceiptConfirmationProblem.invalidCurrency;
    }
    // A width outside the range the backend can report is a defect in this
    // build rather than anything a person typed. Refused here so it can never
    // become a `22023` somebody has to interpret — and never a stored row.
    if (!isSupportedMinorDigits(currencyMinorUnit)) {
      return ReceiptConfirmationProblem.invalidCurrencyMinorUnit;
    }
    if (_isOutOfRange(totalMinor)) {
      return ReceiptConfirmationProblem.invalidTotal;
    }
    if (subtotalMinor != null && _isOutOfRange(subtotalMinor!)) {
      return ReceiptConfirmationProblem.invalidSubtotal;
    }
    if (taxTotalMinor != null && _isOutOfRange(taxTotalMinor!)) {
      return ReceiptConfirmationProblem.invalidTax;
    }
    if ((merchantName?.length ?? 0) > _maxMerchantNameLength) {
      return ReceiptConfirmationProblem.merchantNameTooLong;
    }
    if ((documentNumber?.length ?? 0) > _maxDocumentNumberLength) {
      return ReceiptConfirmationProblem.documentNumberTooLong;
    }
    if (transactionDate.compareTo(_earliestDate) < 0) {
      return ReceiptConfirmationProblem.dateTooEarly;
    }
    return null;
  }

  static bool _isOutOfRange(int minor) =>
      minor < minMinorAmount || minor > maxMinorAmount;

  @override
  List<Object?> get props => <Object?>[
    submissionId,
    transactionDate,
    currencyCode,
    currencyMinorUnit,
    totalMinor,
    merchantName,
    documentNumber,
    transactionTime,
    subtotalMinor,
    taxTotalMinor,
  ];
}

/// Which rule an input broke. A form-field discriminant, never backend text.
enum ReceiptConfirmationProblem {
  invalidSubmissionId,
  invalidCurrency,
  invalidCurrencyMinorUnit,
  invalidTotal,
  invalidSubtotal,
  invalidTax,
  merchantNameTooLong,
  documentNumberTooLong,
  dateTooEarly,
}

/// Amounts are non-negative: a refund or credit note is out of scope.
const int minMinorAmount = 0;

/// The ceiling every amount CHECK mirrors: 10^12.
///
/// For a two-minor currency that is ten billion major units — far above any
/// retail receipt, and low enough that a barcode misread as an amount fails
/// loudly instead of being stored.
const int maxMinorAmount = 1000000000000;

/// The floor `confirm_receipt_extraction` enforces on a receipt date.
const ReceiptCivilDate _earliestDate = ReceiptCivilDate(2000, 1, 1);

const int _maxMerchantNameLength = 255;
const int _maxDocumentNumberLength = 100;

final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Three uppercase ASCII letters. The *shape* rule, not the membership rule.
final RegExp _currency = RegExp(r'^[A-Z]{3}$');
