import '../../../domain/entities/receipt_submission.dart';

const List<String> _months = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `25 Jul 2026 · 14:32`, in the device's own time zone.
///
/// Hand-rolled rather than `package:intl`: the application ships one locale and
/// this is the only date it displays, so a localisation dependency would be
/// weight for one string. The timestamp arrives as UTC from the parser and is
/// converted here — the single place a time zone is applied.
String formatReceiptTimestamp(DateTime timestamp) {
  final DateTime local = timestamp.toLocal();
  final String month = _months[local.month - 1];
  final String hour = local.hour.toString().padLeft(2, '0');
  final String minute = local.minute.toString().padLeft(2, '0');
  return '${local.day} $month ${local.year} · $hour:$minute';
}

/// "Submitted 25 Jul 2026 · 14:32", or "Created …" for a row that never
/// reached `SUBMITTED`.
///
/// The wording follows the data: `submitted_at` is null unless the status is
/// `SUBMITTED`, and the schema enforces that equivalence, so a row without one
/// must not claim to have been submitted.
String formatReceiptMoment(ReceiptSubmission submission) {
  final bool wasSubmitted = submission.submittedAt != null;
  final String prefix = wasSubmitted ? 'Submitted' : 'Created';
  return '$prefix ${formatReceiptTimestamp(submission.displayedAt)}';
}
