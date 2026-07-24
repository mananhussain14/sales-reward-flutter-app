import 'dart:typed_data';

/// The three image formats a receipt may be.
///
/// Byte-identical to `SUPPORTED_RECEIPT_MIME_TYPES` in the backend's
/// `lib/receipts/receipt-file.ts`, to the `receipts` bucket's
/// `allowed_mime_types`, and to the `receipt_submissions_mime_type_allowed`
/// CHECK. PDF is absent for the same reason it is absent there: a format that
/// cannot be verified by signature would put the declared type back in charge.
enum ReceiptImageType {
  jpeg('image/jpeg', 'JPEG'),
  png('image/png', 'PNG'),
  webp('image/webp', 'WebP');

  const ReceiptImageType(this.mimeType, this.label);

  final String mimeType;

  /// A short display name for the preview card.
  final String label;

  /// The type these bytes actually are, or null when they are none of the
  /// three.
  ///
  /// ## The filename is never consulted
  ///
  /// Not the extension, not the declared content type of a picked file — only
  /// the leading bytes. A `.jpg` whose contents are a ZIP archive is refused
  /// here, before an upload is attempted, exactly as the backend refuses it
  /// afterwards.
  ///
  /// This check exists for **immediate feedback only**. The Edge Function sniffs
  /// the bytes again server-side and its answer is the one that is stored; a
  /// client that skipped this step would be slower, never more permissive.
  ///
  ///   JPEG  `FF D8 FF`
  ///   PNG   `89 50 4E 47 0D 0A 1A 0A`
  ///   WebP  `"RIFF"` at 0 and `"WEBP"` at 8
  static ReceiptImageType? sniff(Uint8List bytes) {
    if (_startsWith(bytes, <int>[0xff, 0xd8, 0xff])) {
      return jpeg;
    }
    if (_startsWith(bytes, <int>[
      0x89,
      0x50,
      0x4e,
      0x47,
      0x0d,
      0x0a,
      0x1a,
      0x0a,
    ])) {
      return png;
    }
    if (_startsWith(bytes, <int>[0x52, 0x49, 0x46, 0x46]) &&
        _startsWith(bytes, <int>[0x57, 0x45, 0x42, 0x50], 8)) {
      return webp;
    }
    return null;
  }

  static bool _startsWith(
    Uint8List bytes,
    List<int> signature, [
    int offset = 0,
  ]) {
    if (bytes.length < offset + signature.length) {
      return false;
    }
    for (int i = 0; i < signature.length; i++) {
      if (bytes[offset + i] != signature[i]) {
        return false;
      }
    }
    return true;
  }
}
