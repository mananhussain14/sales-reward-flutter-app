import 'dart:typed_data';

/// Where a receipt image comes from.
enum ReceiptImageOrigin {
  /// The device camera. The single biggest genuine mobile improvement over the
  /// web's file input, and the reason this role opens the app at all.
  camera,

  /// The photo library on a phone, or the file picker in a browser.
  gallery,
}

/// One image the person chose, as bytes and a name.
///
/// Nothing platform-specific survives this boundary: no `XFile`, no `File`, no
/// `Blob`, no path. A path in particular is deliberately absent — it would tempt
/// a later change into reading the file twice, or into keeping a copy on disk.
final class PickedReceiptImage {
  const PickedReceiptImage({required this.fileName, required this.bytes});

  /// The name the platform reported. Untrusted: it is sanitized before display
  /// and never consulted to decide the file's type.
  final String? fileName;

  final Uint8List bytes;
}

/// The picker failed for a reason that is not the person cancelling.
///
/// [reason] is developer-facing only. It never reaches a screen, and it never
/// carries a path, a URI or a platform message.
final class ReceiptImagePickException implements Exception {
  const ReceiptImagePickException(this.reason);

  final String reason;

  @override
  String toString() => 'ReceiptImagePickException: $reason';
}

/// Chooses or captures a receipt image.
///
/// ## Why this interface exists
///
/// Camera and gallery access is the one genuinely platform-shaped part of this
/// feature: an Android intent, an iOS picker controller and an `<input
/// type="file" capture>` have nothing in common. Naming the capability here, and
/// keeping the plugin behind it, means the BLoC and every widget deal in bytes —
/// so a submission flow can be tested end to end with no platform channel, no
/// method-channel mock and no browser.
abstract interface class ReceiptImageSource {
  /// Whether capture should be offered at all.
  ///
  /// A **presentation** answer: false hides a button that would open nothing on
  /// this platform. It is not a permission check — the operating system decides
  /// that when the picker is actually opened.
  bool get supportsCamera;

  /// Opens [origin] and returns the chosen image, or null if the person
  /// cancelled.
  ///
  /// Throws [ReceiptImagePickException] when the picker itself fails.
  Future<PickedReceiptImage?> pick(ReceiptImageOrigin origin);
}
