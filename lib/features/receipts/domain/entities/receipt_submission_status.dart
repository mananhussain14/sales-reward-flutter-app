/// The lifecycle of a receipt submission row.
///
/// Three states and no more, exactly as `receipt_submissions_status_allowed`
/// declares. There is deliberately **no** review, approval, rejection, reward or
/// payout state: none of those workflows exists in the backend, and inventing
/// the vocabulary here would let the client display a status the database can
/// never produce.
///
/// ## Why [unknown] exists, and what it may not do
///
/// A status this build does not recognise means the backend is newer than the
/// app. That is an additive change, not a breaking one, so it degrades to
/// [unknown] and renders as "Unknown" rather than failing the whole read.
///
/// [unknown] is never treated as success, never unlocks an action, and never
/// carries the raw backend token to the screen. A **missing or blank** status is
/// a different thing entirely — a required value the response did not supply —
/// and the parser raises a format error for it instead.
enum ReceiptSubmissionStatus {
  /// The row exists; it claims nothing about an uploaded object.
  reserved('RESERVED'),

  /// The object is in the private bucket and every reserved fact still matches.
  submitted('SUBMITTED'),

  /// The upload did not complete. The same file may be submitted again
  /// immediately — it is excluded from the duplicate-protection index.
  uploadFailed('UPLOAD_FAILED'),

  /// A value this build does not know. Displayed neutrally, and nothing more.
  unknown('');

  const ReceiptSubmissionStatus(this.code);

  /// The backend token, or the empty string for [unknown].
  final String code;

  /// Maps a backend token to a status, falling back to [unknown].
  ///
  /// Never throws: the caller has already established that a status string is
  /// present, and an unrecognised value is a forward-compatibility case rather
  /// than a malformed response.
  static ReceiptSubmissionStatus fromCode(String raw) {
    for (final ReceiptSubmissionStatus status in values) {
      if (status != unknown && status.code == raw) {
        return status;
      }
    }
    return unknown;
  }

  /// Whether the receipt is stored and recorded.
  bool get isSubmitted => this == submitted;

  /// Whether the submitter may safely send the same file again.
  bool get isRetryable => this == uploadFailed;
}
