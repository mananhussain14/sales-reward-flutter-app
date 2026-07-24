import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/receipt_submission_status.dart';

/// The status pill for a receipt submission.
///
/// ## Why not the shared [SrStatusBadge]
///
/// That widget carries the product-wide enum map, which has no entry for
/// `RESERVED` or `UPLOAD_FAILED` — both would render as "Unknown". Adding them
/// there would put receipt vocabulary into a component every other feature
/// reads, which is exactly the coupling each role's separate navigation list
/// avoids. Three states belong to this feature, so their presentation lives
/// here.
///
/// The property [SrStatusBadge] guarantees is preserved verbatim: **the raw
/// backend token never reaches the screen.** An unrecognised status renders
/// "Unknown" in a neutral tone rather than leaking a database value.
class ReceiptStatusBadge extends StatelessWidget {
  const ReceiptStatusBadge({super.key, required this.status});

  final ReceiptSubmissionStatus status;

  /// The label for [status]. Exposed so a test can assert the mapping without
  /// building four widgets.
  static String labelFor(ReceiptSubmissionStatus status) => switch (status) {
    ReceiptSubmissionStatus.submitted => 'Submitted',
    ReceiptSubmissionStatus.reserved => 'Pending upload',
    ReceiptSubmissionStatus.uploadFailed => 'Upload failed',
    ReceiptSubmissionStatus.unknown => 'Unknown',
  };

  @override
  Widget build(BuildContext context) {
    final (SrTone tone, IconData? icon) = switch (status) {
      ReceiptSubmissionStatus.submitted => (
        SrTone.emerald,
        Icons.check_rounded,
      ),
      ReceiptSubmissionStatus.reserved => (
        SrTone.amber,
        Icons.schedule_rounded,
      ),
      ReceiptSubmissionStatus.uploadFailed => (
        SrTone.red,
        Icons.error_outline_rounded,
      ),
      ReceiptSubmissionStatus.unknown => (SrTone.slate, null),
    };

    return SrBadge(label: labelFor(status), tone: tone, icon: icon);
  }
}
