/// A safe review hint attached to a `SUCCEEDED` extraction.
///
/// Codes only — never values. The twelve tokens below are the complete contents
/// of `receipt_extractions_warning_codes_allowed`.
///
/// **None of these blocks anything.** `SUBTOTAL_TAX_TOTAL_MISMATCH` is the
/// clearest case: real receipts round their lines independently of their total,
/// so `subtotal + tax = total` is not a fact about receipts and there is
/// deliberately no CHECK asserting it. The warning exists so a reviewer's eye is
/// drawn to the figure, and for no other purpose.
enum ReceiptExtractionWarningCode {
  lowConfidenceTotal('LOW_CONFIDENCE_TOTAL'),
  lowConfidenceDate('LOW_CONFIDENCE_DATE'),
  missingMerchantName('MISSING_MERCHANT_NAME'),
  missingDocumentNumber('MISSING_DOCUMENT_NUMBER'),
  missingTransactionTime('MISSING_TRANSACTION_TIME'),
  subtotalTaxTotalMismatch('SUBTOTAL_TAX_TOTAL_MISMATCH'),

  /// An amount whose decimal separator could not be resolved. The value is
  /// **not** guessed — the field is null and its source text is preserved.
  ambiguousAmountFormat('AMBIGUOUS_AMOUNT_FORMAT'),

  /// The provider produced a negative amount. Refused, never absolute-valued.
  negativeAmountRejected('NEGATIVE_AMOUNT_REJECTED'),

  /// A zero total. Valid: a fully discounted receipt is real.
  zeroTotal('ZERO_TOTAL'),

  dateInFuture('DATE_IN_FUTURE'),
  currencyInferredFromDefault('CURRENCY_INFERRED_FROM_DEFAULT'),
  multipleTotalsFound('MULTIPLE_TOTALS_FOUND'),

  /// A token this build does not know. Rendered as a generic hint, never as the
  /// raw string, and never treated as an absence of warnings.
  unknown('');

  const ReceiptExtractionWarningCode(this.code);

  /// The backend token, or the empty string for [unknown].
  final String code;

  /// Maps a backend token, falling back to [unknown].
  static ReceiptExtractionWarningCode fromCode(String raw) {
    for (final ReceiptExtractionWarningCode warning in values) {
      if (warning != unknown && warning.code == raw) {
        return warning;
      }
    }
    return unknown;
  }
}
