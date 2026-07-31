/// The lifecycle of one provider attempt.
///
/// Four states and no more, exactly as `receipt_extractions_status_allowed`
/// declares. There is deliberately **no** cancelled, retrying, partial or
/// reviewed state: none exists in the backend, and inventing the vocabulary
/// here would let the client display a status the database can never produce.
///
/// ## Why [unknown] exists, and what it may not do
///
/// A token this build does not recognise means the backend is newer than the
/// app. That is an additive change, so it degrades to [unknown] rather than
/// failing the whole read. A **missing or blank** status is a different thing —
/// a required value the response did not supply — and the parser refuses it.
///
/// [unknown] is never treated as success, never unlocks confirmation, never
/// counts as terminal, and never carries the raw token to a screen.
enum ReceiptExtractionStatus {
  /// The attempt exists and no worker has claimed it.
  queued('QUEUED'),

  /// A worker holds the job. The provider may or may not have answered yet.
  processing('PROCESSING'),

  /// The reading is stored. The normalized fields are populated.
  succeeded('SUCCEEDED'),

  /// The attempt ended without a reading. `failure_code` says which of the
  /// three client-visible reasons applies.
  failed('FAILED'),

  /// A value this build does not know. Displayed neutrally, and nothing more.
  unknown('');

  const ReceiptExtractionStatus(this.code);

  /// The backend token, or the empty string for [unknown].
  final String code;

  /// Maps a backend token, falling back to [unknown].
  ///
  /// Never throws: the caller has already established that a status string is
  /// present, and an unrecognised value is forward compatibility rather than a
  /// malformed response.
  static ReceiptExtractionStatus fromCode(String raw) {
    for (final ReceiptExtractionStatus status in values) {
      if (status != unknown && status.code == raw) {
        return status;
      }
    }
    return unknown;
  }

  /// Whether the attempt is still in flight.
  ///
  /// The two open states are the only ones that block confirmation — *"one rule
  /// blocks confirmation, not five"* — and the only ones a poll would advance.
  /// [unknown] is deliberately **not** open: a build that treated an
  /// unrecognised token as in-flight would poll forever.
  bool get isOpen => this == queued || this == processing;

  /// Whether the attempt reached a recorded end state.
  bool get isTerminal => this == succeeded || this == failed;
}
