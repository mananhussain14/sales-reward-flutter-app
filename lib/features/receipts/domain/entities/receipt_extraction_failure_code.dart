/// Why an attempt failed, in the **client** vocabulary.
///
/// The backend stores ten failure codes and shows a client three. That is not a
/// simplification, it is the removal of an availability oracle:
///
/// > *"Two of the stored codes describe the caller's own file and are
/// > actionable — retake the photo. The other eight describe our infrastructure
/// > and are not: the action in every one of those cases is identical, so a
/// > finer distinction buys the caller nothing while telling them whether our
/// > provider is healthy, whether we have exhausted a billing quota, and
/// > whether a storage read failed."*
///
/// The mapping happens in SQL inside `get_my_receipt_extraction`. This client
/// never sees a stored code and has no representation for one.
enum ReceiptExtractionFailureCode {
  /// The provider read the image and it is not a receipt. Retake the photo.
  imageNotAReceipt('IMAGE_NOT_A_RECEIPT'),

  /// The image itself cannot be used. Retake the photo.
  imageUnusable('IMAGE_UNUSABLE'),

  /// Everything else. Not actionable beyond retrying or typing the values in.
  extractionUnavailable('EXTRACTION_UNAVAILABLE'),

  /// A token this build does not know.
  ///
  /// Still a failure. The backend's own mapper takes the same position — *"an
  /// unrecognised failure is still a failure"* — so this must never be read as
  /// "no failure" and must never unlock anything a real code would not.
  unknown('');

  const ReceiptExtractionFailureCode(this.code);

  /// The backend token, or the empty string for [unknown].
  final String code;

  /// Maps a backend token, falling back to [unknown].
  static ReceiptExtractionFailureCode fromCode(String raw) {
    for (final ReceiptExtractionFailureCode failure in values) {
      if (failure != unknown && failure.code == raw) {
        return failure;
      }
    }
    return unknown;
  }

  /// Whether retaking the photograph is the useful next step.
  ///
  /// True only for the two codes that describe the caller's own file. It is a
  /// copy hint and never an authorization or retry decision — whether another
  /// attempt is permitted is carried by `retry_allowed` alone.
  bool get isAboutTheImage => this == imageNotAReceipt || this == imageUnusable;
}
