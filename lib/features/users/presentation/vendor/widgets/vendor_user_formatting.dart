import 'vendor_user_copy.dart';

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
/// Hand-rolled rather than `package:intl`, matching the receipt and Retailer
/// features: the application ships one locale, so a localisation dependency
/// would be weight for a handful of strings. Timestamps arrive as UTC from the
/// parser and are converted here — the single place a time zone is applied.
///
/// No time of day: "when did this membership start" is a date-grained fact, and
/// a minute would imply a precision the question does not have.
String formatUserDate(DateTime timestamp) {
  final DateTime local = timestamp.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}

/// A nullable membership date, as a phrase.
///
/// `joined_at` is null for somebody who has not joined, and the honest rendering
/// of that is a sentence rather than a blank or an em dash — a screen reader
/// announcing "dash" tells nobody anything.
///
/// The phrase describes **the date only**. It never asserts a lifecycle state:
/// the status badges carry that, and the backend is explicit that a status must
/// not be inferred from the presence or absence of a timestamp.
String formatJoined(DateTime? joinedAt) =>
    joinedAt == null ? VendorUserCopy.notJoinedYet : formatUserDate(joinedAt);

/// `2 roles` / `1 role` / the empty-role phrase.
///
/// Counted from the array the backend sent, never stored as a separate number —
/// two representations of one fact can disagree; one cannot.
String formatRoleCount(int count) {
  if (count == 0) {
    return VendorUserCopy.noRoles;
  }
  return count == 1 ? '1 role' : '$count roles';
}
