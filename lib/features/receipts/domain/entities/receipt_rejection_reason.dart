/// Why a receipt was refused.
///
/// One vocabulary for two producers, so a rejection reads the same whether the
/// client caught it or the server did:
///
/// * the client-side pre-check in `ReceiptFileValidator`, which exists purely so
///   a person is told immediately rather than after a 10 MiB upload;
/// * the `reason` field the Edge Function returns alongside a `400 invalid`.
///
/// The backend's fixed vocabulary is `malformed-body`, `invalid-shop`,
/// `missing`, `empty`, `too-large`, `unsupported-type`, `invalid-name`,
/// `too-many-files` and `rejected`. Every one has a case here, plus [unknown]
/// for a token a future backend adds — which renders as generic copy rather than
/// leaking a raw string to the screen.
enum ReceiptRejectionReason {
  /// The request body was not readable as multipart. Client-side unreachable.
  malformedBody,

  /// `shop_id` was absent or not a UUID.
  invalidShop,

  /// No file part was present.
  missing,

  /// The file has zero bytes.
  empty,

  /// Larger than [maxReceiptFileBytes].
  tooLarge,

  /// The leading bytes are not JPEG, PNG or WebP.
  unsupportedType,

  /// Nothing usable remained of the filename after sanitization.
  invalidName,

  /// More than one file part. The client sends exactly one, so this can only
  /// arrive from the server.
  tooManyFiles,

  /// The file was refused for a reason the server did not narrow further.
  rejected,

  /// A token this build does not recognise.
  unknown;

  /// Maps the Edge Function's `reason` token.
  ///
  /// Unrecognised input becomes [unknown]. The raw token is never retained, so
  /// it cannot reach the interface.
  static ReceiptRejectionReason fromCode(String? raw) => switch (raw) {
    'malformed-body' => malformedBody,
    'invalid-shop' => invalidShop,
    'missing' => missing,
    'empty' => empty,
    'too-large' => tooLarge,
    'unsupported-type' => unsupportedType,
    'invalid-name' => invalidName,
    'too-many-files' => tooManyFiles,
    'rejected' => rejected,
    _ => unknown,
  };
}

/// The MVP ceiling, in bytes: 10 MiB.
///
/// The same number three other places already enforce — the `receipts` bucket's
/// `file_size_limit`, the `receipt_submissions_file_size_range` CHECK, and
/// `MAX_RECEIPT_FILE_BYTES` in the shared validation module. Checking it here
/// saves a doomed upload; it does not make this client the authority.
const int maxReceiptFileBytes = 10 * 1024 * 1024;
