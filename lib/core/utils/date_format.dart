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
/// Hand-rolled rather than `package:intl`, matching the receipt, Retailer, User,
/// Role and Product features: the application ships one locale, so a
/// localisation dependency would be weight for a handful of strings.
///
/// Timestamps arrive as **UTC** from the parsers and are converted here — the
/// single place a time zone is applied, which is what keeps equality and
/// ordering device-independent everywhere above the presentation layer.
///
/// No time of day: every date the Retailer portal shows answers a day-grained
/// question ("when did they join", "when does this expire"), and a minute would
/// imply a precision the question does not have.
///
/// Promoted to `core` for this milestone because Shops, Staff and Products all
/// needed it — the same rule `ReadResult` records: *"when a third feature needs
/// one, that is the evidence to promote it."* `formatProductDate` in the Vendor
/// feature is the original and is left alone, since renaming a working Vendor
/// helper is churn this milestone has no reason to spend.
String formatDayDate(DateTime timestamp) {
  final DateTime local = timestamp.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}
