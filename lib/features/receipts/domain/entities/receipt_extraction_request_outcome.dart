/// What asking for an extraction actually did.
///
/// The six tokens `request_receipt_extraction` returns, in the order its branch
/// list evaluates them. Only [queued] creates anything; the rest report state
/// that already existed, which is why answering them with a gate shut leaks no
/// configuration.
enum ReceiptExtractionRequestOutcome {
  /// A confirmation already exists. Nothing was created, and nothing can be.
  alreadyConfirmed('ALREADY_CONFIRMED'),

  /// An attempt is already in flight. Its id comes back so the caller can
  /// follow it; the provider is not asked a second time.
  active('ACTIVE'),

  /// A successful attempt already exists. *"The provider is NOT charged
  /// again."*
  succeeded('SUCCEEDED'),

  /// All three attempts are spent. Manual confirmation remains open.
  exhausted('EXHAUSTED'),

  /// No attempt was created and the reason is deliberately not narrowed.
  ///
  /// > *"EXTRACTION_UNAVAILABLE is returned both when a gate is closed and when
  /// > the infrastructure is broken, and the client cannot tell which. That
  /// > indistinguishability is the point: the action is identical in both
  /// > cases, and a client able to distinguish them would be reading our
  /// > configuration."*
  ///
  /// So there is deliberately **no** separate "runtime disabled" case in this
  /// enum. Adding one would require inventing a signal the backend refuses to
  /// send. Nothing was written, and the counters are untouched.
  extractionUnavailable('EXTRACTION_UNAVAILABLE'),

  /// A new attempt was created. This is the only outcome that consumes one.
  queued('QUEUED'),

  /// A token this build does not know.
  ///
  /// Never treated as [queued]: a build that assumed an attempt had been
  /// created would show a spinner for a job that does not exist.
  unknown('');

  const ReceiptExtractionRequestOutcome(this.code);

  /// The backend token, or the empty string for [unknown].
  final String code;

  /// Maps a backend token, falling back to [unknown].
  static ReceiptExtractionRequestOutcome fromCode(String raw) {
    for (final ReceiptExtractionRequestOutcome outcome in values) {
      if (outcome != unknown && outcome.code == raw) {
        return outcome;
      }
    }
    return unknown;
  }

  /// Whether this call consumed one of the three attempts.
  bool get consumedAnAttempt => this == queued;

  /// Whether an attempt is now, or already was, in flight.
  bool get isInFlight => this == queued || this == active;
}
