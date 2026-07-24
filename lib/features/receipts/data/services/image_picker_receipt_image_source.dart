import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:image_picker/image_picker.dart';

import '../../domain/services/receipt_image_source.dart';

/// [ReceiptImageSource] backed by `image_picker`.
///
/// ## Why this package
///
/// It is maintained by flutter.dev, it is federated — `image_picker_for_web`
/// makes the same two calls work in a browser — and it is scoped to images,
/// which is exactly the scope of this feature. A general file picker would open
/// a door to formats the backend refuses, and the extra breadth would buy
/// nothing: a receipt is a JPEG, a PNG or a WebP.
///
/// ## Permissions: only what the plugin actually needs
///
/// * **Android** — nothing is declared. `image_picker` captures through an
///   `ACTION_IMAGE_CAPTURE` intent and reads through the photo picker, neither
///   of which requires a manifest permission. Declaring `CAMERA` would make the
///   app *ask* for something it does not need.
/// * **iOS** — `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription`,
///   and nothing else. No microphone string: this flow reads one still image and
///   records no audio.
/// * **Web** — the browser's own file input; no permission is declared or
///   requested.
///
/// ## The picked file is read into memory and never persisted
///
/// `readAsBytes` gives the bytes and the flow ends there. Nothing is copied into
/// application storage, a cache directory or the gallery. A receipt is the
/// business's record, and a private image left behind on a shared shop-floor
/// device is a leak with no upside. The plugin's own temporary file is the
/// platform's to clean up; this class creates none of its own.
final class ImagePickerReceiptImageSource implements ReceiptImageSource {
  ImagePickerReceiptImageSource({
    ImagePicker? picker,
    TargetPlatform? platform,
    bool isWeb = kIsWeb,
  }) : _picker = picker ?? ImagePicker(),
       _platform = platform ?? defaultTargetPlatform,
       _isWeb = isWeb;

  final ImagePicker _picker;
  final TargetPlatform _platform;
  final bool _isWeb;

  /// Camera capture is offered on Android and iOS, and on the web where a
  /// browser maps it to a capture-hinted file input.
  ///
  /// Desktop is excluded because `image_picker` has no camera implementation
  /// there — the button would open nothing. This is presentation only: hiding it
  /// removes a dead end, and the operating system still decides access when the
  /// picker is actually opened.
  @override
  bool get supportsCamera {
    if (_isWeb) {
      return true;
    }
    return _platform == TargetPlatform.android ||
        _platform == TargetPlatform.iOS;
  }

  @override
  Future<PickedReceiptImage?> pick(ReceiptImageOrigin origin) async {
    final ImageSource source = switch (origin) {
      ReceiptImageOrigin.camera => ImageSource.camera,
      ReceiptImageOrigin.gallery => ImageSource.gallery,
    };

    final XFile? picked;
    try {
      // No maxWidth, maxHeight or imageQuality. Re-encoding would change the
      // bytes, and the duplicate guard the backend applies is a SHA-256 of the
      // bytes it actually receives — so any transformation belongs on the same
      // side of the wire as the hash, which is the server's. Downscaling here
      // would also degrade the very detail a future OCR step needs.
      picked = await _picker.pickImage(source: source);
    } on Object {
      // Platform exceptions can name a file path, a URI or an account. None is
      // bound, rethrown or logged; the caller gets a discriminant.
      throw const ReceiptImagePickException('picker failed');
    }

    if (picked == null) {
      // Cancelled. Not an error, and it must not disturb an existing selection.
      return null;
    }

    final Uint8List bytes;
    try {
      bytes = await picked.readAsBytes();
    } on Object {
      throw const ReceiptImagePickException('could not read the chosen image');
    }

    return PickedReceiptImage(fileName: picked.name, bytes: bytes);
  }
}
