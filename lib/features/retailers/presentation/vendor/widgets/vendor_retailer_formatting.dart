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

/// `25 Jul 2026`, in the device's own time zone.
///
/// Hand-rolled rather than `package:intl`, matching the receipt feature: the
/// application ships one locale, so a localisation dependency would be weight
/// for a handful of strings. `relationship_created_at` arrives as UTC from the
/// parser and is converted here — the single place a time zone is applied.
///
/// No time of day: "when did we onboard this Retailer" is a date-grained fact,
/// and a minute would imply a precision the question does not have.
String formatOnboardedDate(DateTime timestamp) {
  final DateTime local = timestamp.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}

/// `12 shops · 9 active`, or `1 shop · 1 active`.
///
/// Both numbers come from the SQL aggregate. Neither is derived from the length
/// of a shop list the client may not have loaded, so this line says the same
/// thing on the directory and on the detail screen.
String formatShopCounts(int shopCount, int activeShopCount) {
  final String noun = shopCount == 1 ? 'shop' : 'shops';
  return '$shopCount $noun · $activeShopCount active';
}

/// The value to render for a nullable column that came back empty.
///
/// A visible, spoken phrase rather than an em dash: a screen reader announcing
/// "dash" tells nobody anything, and a blank cell reads as a rendering bug.
const String notRecorded = 'Not recorded';
