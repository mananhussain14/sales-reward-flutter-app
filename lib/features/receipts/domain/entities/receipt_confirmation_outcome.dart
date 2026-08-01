/// What confirming actually did.
///
/// Three tokens, and the middle one is not an error:
///
/// > *"A duplicate call returns `ALREADY_CONFIRMED` with the existing row and
/// > does not compare the resubmitted values — returning "ok" when they differ
/// > would be a lie, and replacing them is forbidden."*
///
/// So a caller that resends after a lost reply gets the stored confirmation
/// back, not a second one and not a refusal. A confirmation is immutable: there
/// is no update, no delete and no revision anywhere in the contract.
enum ReceiptConfirmationOutcome {
  /// The confirmation was created by **this** call. It is the only token that
  /// distinguishes writing the row from finding one already there.
  confirmed('CONFIRMED'),

  /// One already existed. The returned id, entry mode and changed fields are
  /// the **stored** ones, not a re-derivation of what was just sent.
  alreadyConfirmed('ALREADY_CONFIRMED'),

  /// An attempt is `QUEUED` or `PROCESSING`. The one rule that blocks
  /// confirmation, because confirming mid-flight would race the success write
  /// and derive the wrong entry mode. Nothing was written.
  extractionInProgress('EXTRACTION_IN_PROGRESS'),

  /// A token this build does not know.
  ///
  /// Never treated as [confirmed]: telling somebody their receipt was confirmed
  /// on the strength of a token this build could not read would be the one
  /// mistake this feature cannot undo.
  unknown('');

  const ReceiptConfirmationOutcome(this.code);

  /// The backend token, or the empty string for [unknown].
  final String code;

  /// Maps a backend token, falling back to [unknown].
  static ReceiptConfirmationOutcome fromCode(String raw) {
    for (final ReceiptConfirmationOutcome outcome in values) {
      if (outcome != unknown && outcome.code == raw) {
        return outcome;
      }
    }
    return unknown;
  }

  /// Whether a confirmation now exists for the receipt, whoever wrote it.
  bool get isSettled => this == confirmed || this == alreadyConfirmed;
}
