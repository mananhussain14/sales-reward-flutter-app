import 'package:equatable/equatable.dart';

import 'receipt_submission_status.dart';

/// One of the caller's **own** receipt submissions.
///
/// One entity deserializes two RPCs, because the backend made their shapes
/// byte-identical on purpose:
///
/// * `public.list_my_receipt_submissions()` — zero arguments, the caller's whole
///   history.
/// * `public.get_my_receipt_submission(p_submission_id uuid)` — the single row
///   just created.
///
/// > *"THE SHAPE IS DELIBERATELY IDENTICAL … so one client-side model
/// > deserializes both, and a future column addition has to be made to both or
/// > to neither."*
///
/// Building a second model for the history list would be the drift that comment
/// exists to prevent, so there is only this one.
///
/// ## What is absent, and why it stays absent
///
/// `storage_bucket`, `storage_object_path` and `file_sha256` are withheld by
/// **both** functions. A private object location is not display data, and the
/// hash would let one person test whether a file they hold matches a
/// submission. There is no field for them here because there is no value to put
/// in one — and no receipt-image retrieval path exists anywhere in the backend.
final class ReceiptSubmission extends Equatable {
  const ReceiptSubmission({
    required this.submissionId,
    required this.shopName,
    required this.status,
    required this.originalFileName,
    required this.mimeType,
    required this.fileSizeBytes,
    required this.createdAt,
    this.shopCode,
    this.submittedAt,
  });

  /// `submission_id` — a UUID, validated on parse.
  final String submissionId;

  /// `shop_name`.
  final String shopName;

  /// `shop_code` — nullable in the schema.
  final String? shopCode;

  final ReceiptSubmissionStatus status;

  /// `original_file_name` — the **sanitized** name the backend stored, kept only
  /// so a submitter recognises their own row. It never formed part of the
  /// storage path.
  final String originalFileName;

  /// `mime_type` — the type the backend **sniffed from the bytes**, not the one
  /// the client declared.
  final String mimeType;

  final int fileSizeBytes;

  /// `submitted_at` — null unless [status] is
  /// [ReceiptSubmissionStatus.submitted]; the schema enforces that equivalence.
  final DateTime? submittedAt;

  final DateTime createdAt;

  /// The moment to show for this row: when it was submitted, or failing that
  /// when it was created.
  DateTime get displayedAt => submittedAt ?? createdAt;

  @override
  List<Object?> get props => <Object?>[
    submissionId,
    shopName,
    shopCode,
    status,
    originalFileName,
    mimeType,
    fileSizeBytes,
    submittedAt,
    createdAt,
  ];
}
