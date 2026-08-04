/// What `confirm_receipt_with_products` actually did.
///
/// Three tokens. Note what is **not** here: the combined RPC never returns
/// `EXTRACTION_IN_PROGRESS`. When the underlying header confirmation is blocked
/// it maps that to [conflict], because nothing was written and no proposal may
/// exist either — reporting a distinct "in progress" state would invite a retry
/// of an immutable write.
enum ReceiptWithProductsOutcome {
  /// This call created the confirmation **and** the product proposal.
  confirmed('CONFIRMED'),

  /// The exact same header and the exact same ordered product list already
  /// existed. Not an error: a resend after a lost reply lands here, and nothing
  /// was duplicated.
  alreadyConfirmed('ALREADY_CONFIRMED'),

  /// A confirmation exists that does not match what was sent — a different
  /// header, a different list, a different order, or a header-only confirmation
  /// created before this milestone.
  ///
  /// Nothing was written and nothing was overwritten. A proposal is immutable,
  /// so there is no correction path: the honest answer is that this receipt
  /// already carries a different assertion.
  conflict('CONFLICT'),

  /// A token this build does not know.
  ///
  /// Never treated as [confirmed]. Telling somebody their products were
  /// submitted on the strength of a token this build could not read is the one
  /// mistake this feature cannot undo.
  unknown('');

  const ReceiptWithProductsOutcome(this.code);

  final String code;

  static ReceiptWithProductsOutcome fromCode(String raw) {
    for (final ReceiptWithProductsOutcome outcome in values) {
      if (outcome != unknown && outcome.code == raw) {
        return outcome;
      }
    }
    return unknown;
  }

  /// Whether a confirmation and proposal now exist for this receipt, whoever
  /// wrote them. Both settled tokens mean the flow is finished and read-only.
  bool get isSettled => this == confirmed || this == alreadyConfirmed;
}
