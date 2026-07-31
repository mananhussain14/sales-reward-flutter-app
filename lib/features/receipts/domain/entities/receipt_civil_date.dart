import 'package:equatable/equatable.dart';

/// A printed receipt date: a **civil date**, with no time and no zone.
///
/// The backend stores `transaction_date` as PostgreSQL `date`, and says why in
/// the migration itself:
///
/// > *"A printed receipt date is a CIVIL DATE with no zone. `date`, never
/// > `timestamptz`: storing it with a zone would silently shift it by a day for
/// > half the world."*
///
/// A `DateTime` cannot express that. Every `DateTime` is a moment, so parsing
/// `2026-07-25` into one has to pick a zone the receipt never had — and the day
/// a staff member then sees depends on the device's clock settings rather than
/// on the paper in their hand. This type holds three integers and no instant,
/// so there is nothing for a zone to shift.
///
/// It is also the **request** form: a confirmation sends [iso] back, which is
/// the exact text PostgREST casts to `date`.
final class ReceiptCivilDate extends Equatable
    implements Comparable<ReceiptCivilDate> {
  const ReceiptCivilDate(this.year, this.month, this.day);

  /// Parses the `YYYY-MM-DD` form PostgREST renders a `date` as.
  ///
  /// Returns null for everything else — including a full timestamp, which is
  /// evidence the response is not this shape rather than a value to truncate.
  /// The caller decides whether null means "absent" or "malformed"; this
  /// function never guesses a date.
  ///
  /// A syntactically well-formed but impossible date (`2026-02-30`) is refused
  /// too: `DateTime` would silently roll it forward into March, and a receipt
  /// dated a day that does not exist is a response this build cannot trust.
  static ReceiptCivilDate? tryParse(String raw) {
    final RegExpMatch? match = _shape.firstMatch(raw.trim());
    if (match == null) {
      return null;
    }

    final int year = int.parse(match.group(1)!);
    final int month = int.parse(match.group(2)!);
    final int day = int.parse(match.group(3)!);

    // The round trip is the range check: DateTime normalizes an out-of-range
    // component instead of refusing it, so a mismatch after normalization is
    // exactly the set of dates that do not exist.
    final DateTime probe = DateTime.utc(year, month, day);
    if (probe.year != year || probe.month != month || probe.day != day) {
      return null;
    }

    return ReceiptCivilDate(year, month, day);
  }

  static final RegExp _shape = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  final int year;
  final int month;
  final int day;

  /// The wire form, `YYYY-MM-DD`. Round-trips through [tryParse] exactly.
  String get iso => '${_pad(year, 4)}-${_pad(month, 2)}-${_pad(day, 2)}';

  static String _pad(int value, int width) =>
      value.toString().padLeft(width, '0');

  @override
  int compareTo(ReceiptCivilDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  List<Object?> get props => <Object?>[year, month, day];

  @override
  String toString() => iso;
}
