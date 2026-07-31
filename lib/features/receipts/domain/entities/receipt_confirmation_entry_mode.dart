/// How a confirmation's values came to be.
///
/// **Server-derived. There is no parameter for it**, and this client must never
/// compute one: the comparison rules that produce it live in SQL, are
/// deliberately forgiving about casing and punctuation, and a second definition
/// in Dart would be free to drift from the stored answer.
enum ReceiptConfirmationEntryMode {
  /// No successful extraction existed. Every value was typed.
  manual('MANUAL'),

  /// A successful extraction existed and every compared value matched it.
  extracted('EXTRACTED'),

  /// A successful extraction existed and at least one compared value differs.
  mixed('MIXED'),

  /// A token this build does not know.
  unknown('');

  const ReceiptConfirmationEntryMode(this.code);

  /// The backend token, or the empty string for [unknown].
  final String code;

  /// Maps a backend token, falling back to [unknown].
  static ReceiptConfirmationEntryMode fromCode(String raw) {
    for (final ReceiptConfirmationEntryMode mode in values) {
      if (mode != unknown && mode.code == raw) {
        return mode;
      }
    }
    return unknown;
  }
}
