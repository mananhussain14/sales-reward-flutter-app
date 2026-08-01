import 'package:equatable/equatable.dart';

/// A short-lived capability to fetch one receipt image.
///
/// ## This is a fetch credential, not a display credential
///
/// > *"The client fetches the bytes once inside the window and holds the
/// > decoded image for the review screen, so expiry is invisible in normal use.
/// > On any fetch failure — or when the app resumes and the image is no longer
/// > in memory — it calls the endpoint again. It must **never** persist the URL
/// > to disk, to logs, to an image-cache key, or to any state that outlives the
/// > screen."*
///
/// The window is [expiresInSeconds] — 120 by design: long enough for a 10 MB
/// photograph on a poor in-store connection, short enough that a URL leaked
/// through a log or a screenshot is dead almost immediately.
///
/// ## What this type deliberately does not do
///
/// It has no `toString` override, no `props` entry for [url], no serialization
/// and no equality that reads it. That is not fastidiousness: a value object
/// printed into a debug log or compared in a test failure message is the
/// ordinary way a credential ends up somewhere it outlives its window. Equality
/// is by [expiresInSeconds] alone, which is all any caller has a reason to
/// compare.
///
/// The bucket and object path are inside the URL string by construction — a
/// Supabase preview URL addresses the object — and that is accepted and bounded:
/// the path is composed entirely of the caller's own identifiers, and the bucket
/// is private, so the path alone grants nothing. No **separate** bucket, path,
/// MIME or hash field is returned, and this type has no field for one.
final class ReceiptImagePreview extends Equatable {
  const ReceiptImagePreview({
    required this.url,
    required this.expiresInSeconds,
  });

  /// The URL to fetch the bytes from, once, now.
  ///
  /// Never stored, never logged, never used as a cache key.
  final String url;

  /// `expires_in_seconds` — how long [url] remains usable.
  final int expiresInSeconds;

  @override
  List<Object?> get props => <Object?>[expiresInSeconds];

  @override
  String toString() =>
      'ReceiptImagePreview(expiresInSeconds: $expiresInSeconds)';
}
