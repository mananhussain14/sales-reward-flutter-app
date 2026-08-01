import 'package:equatable/equatable.dart';

/// One currency's authoritative decimal width, as the backend reports it.
///
/// The answer to *"how many decimal places is this currency written with"*, and
/// deliberately nothing else. It carries no name, no numeric code, no symbol and
/// no provenance, because the function that produces it has no room for one:
/// `get_receipt_currency_minor_unit` returns two columns.
///
/// ## Why this exists at all
///
/// Every monetary value on this contract is an **integer number of minor
/// units**, and how many minor units make one major unit is a property of the
/// currency: 2 for EUR, 0 for JPY, 3 for KWD, 4 for CLF. Given the integer
/// `1000` and the code `JPY` there is no way to tell afterwards whether ¥1000 or
/// ¥10.00 was meant, and a confirmation is immutable — so the width has to be
/// known *before* a typed amount becomes an integer, and it has to come from the
/// backend rather than from a table this client carries.
///
/// There is no ISO map anywhere in this application. A width this client cannot
/// obtain from the backend is a width this client does not have.
final class ReceiptCurrencyMinorUnit extends Equatable {
  const ReceiptCurrencyMinorUnit({
    required this.currencyCode,
    required this.minorUnit,
  });

  /// The normalized alphabetic code the backend answered with — trimmed and
  /// upper-cased on both sides, so the two can never disagree about which code
  /// a given input names.
  final String currencyCode;

  /// `0`, `2`, `3` or `4` in the seeded list.
  ///
  /// Read as a bounded integer rather than an enumeration of the four values,
  /// so a future ISO revision adding one does not break an installed build.
  final int minorUnit;

  @override
  List<Object?> get props => <Object?>[currencyCode, minorUnit];
}

/// The narrowest minor unit any currency has.
const int minMinorDigits = 0;

/// The widest minor unit the seeded list contains.
const int maxMinorDigits = 4;

/// Whether [value] is inside the range the backend can report.
bool isSupportedMinorDigits(int value) =>
    value >= minMinorDigits && value <= maxMinorDigits;
