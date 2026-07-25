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

/// `26 Jul 2026, 1:25 AM`, in the device's own time zone.
///
/// Hand-rolled rather than `package:intl`, matching the receipt, Retailer, User,
/// Role and Product features: the application ships one locale, so a
/// localisation dependency would be weight for a handful of strings.
///
/// ## Why this one carries a time when the others do not
///
/// Every other date in the app answers a day-grained question — when a product
/// was created, when a Retailer was onboarded — and a minute would imply a
/// precision the question does not have. An audit line answers the opposite: the
/// whole point of a history is *when*, and two events minutes apart are a
/// sequence a reader needs to see. The stored value is `timestamptz` to
/// microsecond precision, so the minute is real data rather than a rendering
/// flourish.
///
/// ## Local, and only here
///
/// Timestamps arrive as UTC from the parser and are converted here — the single
/// place a time zone is applied. The web page fixes UTC for its own reasons (a
/// server rendering for every reader), but a phone has exactly one reader and
/// their own clock is the one they will compare against.
///
/// The exact [DateTime] is kept on the entity regardless, because it is half of
/// the keyset cursor; nothing paginates on a formatted string.
String formatAuditTimestamp(DateTime timestamp) {
  final DateTime local = timestamp.toLocal();

  // 0 and 12 both render as 12, so midnight is `12:05 AM` rather than `0:05 AM`.
  final int hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final String minute = local.minute.toString().padLeft(2, '0');
  final String period = local.hour < 12 ? 'AM' : 'PM';

  return '${local.day} ${_months[local.month - 1]} ${local.year}, '
      '$hour:$minute $period';
}

/// `26 Jul 2026` — the date alone.
///
/// Used for the day separators that group the feed, so a reader sees the day
/// once rather than on every line.
String formatAuditDate(DateTime timestamp) {
  final DateTime local = timestamp.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}

/// Whether two instants fall on the same **local** calendar day.
///
/// Compared after conversion, so the grouping matches the dates the reader can
/// actually see beside each event rather than the UTC days underneath them.
bool isSameLocalDay(DateTime a, DateTime b) {
  final DateTime left = a.toLocal();
  final DateTime right = b.toLocal();
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}
