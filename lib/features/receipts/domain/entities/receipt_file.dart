import 'dart:typed_data';

import 'receipt_image_type.dart';
import 'receipt_rejection_reason.dart';

/// A receipt image held in memory, ready to be submitted.
///
/// ## Independent of any picker
///
/// Nothing in this class comes from `image_picker`, `file_picker`, `dart:io` or
/// `dart:html`. It is a filename, some bytes and a sniffed type, which is
/// exactly what the multipart request needs and exactly what a test can build
/// without a platform channel. Swapping the picker is then a data-layer change
/// that no BLoC, widget or repository interface can notice.
///
/// ## It is never written to disk
///
/// The bytes live in memory for the duration of one submission and are dropped
/// when the selection is cleared. The app writes no copy to application
/// storage, no cache directory and no gallery album: a receipt is the
/// business's record, not the device's, and a private image left behind on a
/// shared shop-floor phone is a leak with no upside.
///
/// ## Identity equality is deliberate
///
/// This class does **not** implement value equality. Two different selections
/// that happen to share a name, a type and a length are different selections,
/// and a state object holding one must be considered changed when it holds the
/// other. Deep-comparing up to 10 MiB of bytes on every BLoC emission would be
/// the only alternative, and it would cost more than it could ever catch.
final class ReceiptFile {
  const ReceiptFile({
    required this.fileName,
    required this.bytes,
    required this.imageType,
  });

  /// The display name, taken from the picked file. It never shapes the storage
  /// path — that is generated in SQL from ids the database derived — and the
  /// backend sanitizes it again before storing it.
  final String fileName;

  final Uint8List bytes;

  /// Derived from [bytes] by [ReceiptImageType.sniff], never from [fileName].
  final ReceiptImageType imageType;

  int get sizeBytes => bytes.length;

  /// A human file size, matching the backend's `formatFileSize` thresholds so
  /// the same file reads the same in both clients.
  String get readableSize => formatReceiptFileSize(sizeBytes);
}

/// `1023 B` · `640 KB` · `2.4 MB`.
String formatReceiptFileSize(int bytes) {
  if (bytes < 0) {
    return '—';
  }
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// The result of the client-side pre-check.
sealed class ReceiptFileValidation {
  const ReceiptFileValidation();
}

/// The file passed every check this client can perform.
///
/// Not a promise that the backend will accept it — the backend validates the
/// same bytes again and its answer is the one that counts.
final class ReceiptFileAccepted extends ReceiptFileValidation {
  const ReceiptFileAccepted(this.file);

  final ReceiptFile file;
}

/// The file was refused before any upload was attempted.
final class ReceiptFileRefused extends ReceiptFileValidation {
  const ReceiptFileRefused(this.reason);

  final ReceiptRejectionReason reason;
}

/// The client-side pre-check.
///
/// Mirrors the order of `validateReceiptFile` in the backend's shared module:
/// presence, then emptiness, then size, then signature, then name — so an
/// oversized file is refused without sniffing it, and a name is only considered
/// for a file that would otherwise be accepted.
///
/// **This is feedback, not authorization.** Every rule below is applied again on
/// the server against the same bytes. Skipping it would make the app slower and
/// ruder; weakening it cannot make the backend accept anything more.
abstract final class ReceiptFileValidator {
  static ReceiptFileValidation validate({
    required String? fileName,
    required Uint8List? bytes,
  }) {
    if (bytes == null) {
      return const ReceiptFileRefused(ReceiptRejectionReason.missing);
    }
    if (bytes.isEmpty) {
      return const ReceiptFileRefused(ReceiptRejectionReason.empty);
    }
    if (bytes.length > maxReceiptFileBytes) {
      return const ReceiptFileRefused(ReceiptRejectionReason.tooLarge);
    }

    final ReceiptImageType? imageType = ReceiptImageType.sniff(bytes);
    if (imageType == null) {
      return const ReceiptFileRefused(ReceiptRejectionReason.unsupportedType);
    }

    final String? sanitized = sanitizeReceiptFileName(fileName);
    if (sanitized == null) {
      return const ReceiptFileRefused(ReceiptRejectionReason.invalidName);
    }

    return ReceiptFileAccepted(
      ReceiptFile(fileName: sanitized, bytes: bytes, imageType: imageType),
    );
  }
}

/// The longest filename `receipt_submissions.original_file_name` will store.
const int maxReceiptFileNameLength = 255;

final RegExp _controlChars = RegExp(r'[\u0000-\u001f\u007f]');
final RegExp _whitespaceRun = RegExp(r'\s+');

/// A safe display filename, or null when nothing usable remains.
///
/// Takes the last path segment — so `../../etc/passwd` and `C:\x\y.jpg` reduce
/// to `passwd` and `y.jpg` — removes control characters, collapses whitespace
/// runs, trims, and caps the length. The same transformation the backend
/// applies, performed here only so the name shown in the preview is the name
/// that will be stored.
String? sanitizeReceiptFileName(String? raw) {
  if (raw == null) {
    return null;
  }
  final List<String> segments = raw.split(RegExp(r'[/\\]'));
  final String lastSegment = segments.isEmpty ? '' : segments.last;

  String cleaned = lastSegment
      .replaceAll(_controlChars, '')
      .replaceAll(_whitespaceRun, ' ')
      .trim();

  if (cleaned.length > maxReceiptFileNameLength) {
    cleaned = cleaned.substring(0, maxReceiptFileNameLength).trim();
  }

  return cleaned.isEmpty ? null : cleaned;
}
