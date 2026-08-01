/// One of the eight comparable fields, and therefore one of the only values
/// `changed_fields` may contain.
///
/// ## `changed_fields` means "a human corrected this"
///
/// It does not mean "these two strings differ". The derivation collapses
/// whitespace and case on the merchant name, strips non-alphanumerics from the
/// document number, and compares times at minute precision — because *"counting
/// OCR casing or punctuation would make nearly every confirmation `MIXED` and
/// render the signal useless"*.
///
/// The array is sorted by the backend, so two identical confirmations produce
/// identical arrays. This enum is declared in that same sorted order, and the
/// parser preserves the order it was given rather than re-sorting.
enum ReceiptConfirmationField {
  currencyCode('currency_code'),
  documentNumber('document_number'),
  merchantName('merchant_name'),
  subtotalMinor('subtotal_minor'),
  taxTotalMinor('tax_total_minor'),
  totalMinor('total_minor'),
  transactionDate('transaction_date'),
  transactionTime('transaction_time'),

  /// A field name this build does not know.
  ///
  /// Kept rather than dropped: the count of changed fields is part of what the
  /// signal means, and silently discarding one would understate a correction.
  unknown('');

  const ReceiptConfirmationField(this.code);

  /// The backend token, or the empty string for [unknown].
  final String code;

  /// Maps a backend token, falling back to [unknown].
  static ReceiptConfirmationField fromCode(String raw) {
    for (final ReceiptConfirmationField field in values) {
      if (field != unknown && field.code == raw) {
        return field;
      }
    }
    return unknown;
  }
}
