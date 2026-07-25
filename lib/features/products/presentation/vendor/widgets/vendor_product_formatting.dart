import 'vendor_product_copy.dart';

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

/// `12 Mar 2026`, in the device's own time zone.
///
/// Hand-rolled rather than `package:intl`, matching the receipt, Retailer, User
/// and Role features: the application ships one locale, so a localisation
/// dependency would be weight for a handful of strings. Timestamps arrive as UTC
/// from the parser and are converted here — the single place a time zone is
/// applied.
///
/// No time of day: every date this feature shows answers a day-grained question,
/// and a minute would imply a precision the question does not have.
String formatProductDate(DateTime timestamp) {
  final DateTime local = timestamp.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}

/// `2 Retailers currently hold this` / `1 Retailer currently holds this` /
/// `No Retailer currently holds this`.
///
/// The list card's assignment line. Worded around **currently**, because
/// `active_assignment_count` is exactly that: the rows whose assignment status
/// is `ACTIVE` right now. It says nothing about how many Retailers ever held the
/// product, because the list contract does not return that number.
String formatActiveAssignmentCount(int count) {
  if (count == 0) {
    return 'No Retailer currently holds this';
  }
  return count == 1
      ? '1 Retailer currently holds this'
      : '$count Retailers currently hold this';
}

/// `3 Retailer assignments` / `1 Retailer assignment` / `No Retailer
/// assignments`.
///
/// The **total** — every assignment row, active and withdrawn alike. It is
/// deliberately not "Retailers currently assigned": withdrawn rows are counted
/// here, and calling them current would be false about the number the backend
/// actually sent.
String formatAssignmentCount(int count) {
  if (count == 0) {
    return 'No Retailer assignments';
  }
  return count == 1 ? '1 Retailer assignment' : '$count Retailer assignments';
}

/// `2 currently active` / `1 currently active` / `None currently active`.
///
/// Reads beside [formatAssignmentCount] as "3 Retailer assignments · 2 currently
/// active", which is the pair the detail screen exists to state precisely. Both
/// numbers come from the detail row; neither is counted from the loaded list.
String formatActiveOfAssignments(int activeCount) {
  if (activeCount == 0) {
    return 'None currently active';
  }
  return '$activeCount currently active';
}

/// The one sentence that states both assignment figures together.
///
/// Used as the section description and in the spoken summary, so a reader never
/// meets one number without the other.
String formatAssignmentSummary(int total, int active) =>
    '${formatAssignmentCount(total)} · ${formatActiveOfAssignments(active)}';

/// A nullable product field, as something a screen can always render.
///
/// Null is a real answer — a product may genuinely have no barcode, brand or
/// description — and the honest rendering of it is a neutral phrase, never a
/// value invented from another field and never a blank that leaves a reader
/// wondering whether it failed to load.
///
/// This is a **presentation** fallback only. The entity keeps null; nothing
/// upstream ever sees this string, and nothing compares against it.
String formatOptional(String? value) => value ?? VendorProductCopy.notRecorded;
