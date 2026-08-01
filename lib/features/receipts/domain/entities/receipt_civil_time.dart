import 'package:equatable/equatable.dart';

/// A printed receipt time: a **civil time**, with no date and no zone.
///
/// The backend column is `time without time zone`, for the same reason
/// `transaction_date` is a `date`. A `DateTime` would attach both a day and a
/// zone that the receipt never carried.
///
/// ## Minute precision is the comparison contract
///
/// `confirm_receipt_extraction` truncates the submitted time to the minute
/// (`date_trunc('minute', ...)`) and compares both sides at that precision, so
/// *"a provider's `:00` seconds is not a correction"* and does not turn an
/// otherwise `EXTRACTED` confirmation into a `MIXED` one.
///
/// [second] is still carried, because the extraction read may return one and
/// discarding it here would mean this build silently disagreed with the stored
/// row. [truncatedToMinute] is what the comparison sees.
final class ReceiptCivilTime extends Equatable
    implements Comparable<ReceiptCivilTime> {
  const ReceiptCivilTime(this.hour, this.minute, [this.second = 0]);

  /// Parses the `HH:MM:SS` form PostgREST renders a `time` as, and the `HH:MM`
  /// form a caller may hold before sending.
  ///
  /// Fractional seconds are accepted and dropped: PostgreSQL may render them,
  /// and they are below the precision anything in this contract compares at.
  /// `24:00:00` — legal in PostgreSQL — is refused, because it is not a time
  /// that can be printed on a receipt.
  static ReceiptCivilTime? tryParse(String raw) {
    final RegExpMatch? match = _shape.firstMatch(raw.trim());
    if (match == null) {
      return null;
    }

    final int hour = int.parse(match.group(1)!);
    final int minute = int.parse(match.group(2)!);
    final String? rawSecond = match.group(3);
    final int second = rawSecond == null ? 0 : int.parse(rawSecond);

    if (hour > 23 || minute > 59 || second > 59) {
      return null;
    }

    return ReceiptCivilTime(hour, minute, second);
  }

  static final RegExp _shape = RegExp(
    r'^(\d{2}):(\d{2})(?::(\d{2}))?(?:\.\d+)?$',
  );

  final int hour;
  final int minute;
  final int second;

  /// The wire form, `HH:MM:SS`. Round-trips through [tryParse] exactly.
  String get iso => '${_pad(hour)}:${_pad(minute)}:${_pad(second)}';

  /// The value the backend's comparison actually sees.
  ReceiptCivilTime get truncatedToMinute =>
      second == 0 ? this : ReceiptCivilTime(hour, minute);

  static String _pad(int value) => value.toString().padLeft(2, '0');

  @override
  int compareTo(ReceiptCivilTime other) {
    if (hour != other.hour) return hour.compareTo(other.hour);
    if (minute != other.minute) return minute.compareTo(other.minute);
    return second.compareTo(other.second);
  }

  @override
  List<Object?> get props => <Object?>[hour, minute, second];

  @override
  String toString() => iso;
}
