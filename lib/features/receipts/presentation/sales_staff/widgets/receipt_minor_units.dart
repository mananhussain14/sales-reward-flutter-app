/// Converting between the amount a person types and the **integer minor units**
/// the contract stores.
///
/// ## Why this is string arithmetic and not `double`
///
/// The backend is explicit that no amount is ever a decimal on the wire — it
/// assembles minor units by concatenating characters precisely so that `19.99`
/// becomes `"1999"` and then the integer `1999`, and never the double `19.99`
/// multiplied by 100, which is wrong for a long tail of ordinary values.
///
/// This module is the mirror of that rule on the way *out*. Nothing here calls
/// `double.parse`, `toDouble`, `round`, `*` or `/` on a monetary value: the text
/// is split at its separator, the fractional half is padded to the currency's
/// width, and the two halves are concatenated into one integer. A total that
/// survives this function is the same integer the database will hold.
///
/// ## The number of decimals is the currency's, and this file has no opinion
///
/// Every function here that needs a width **takes** one. There is no default, no
/// fallback and no lookup table: the width comes from the backend, either as the
/// `currency_minor_unit` a successful extraction reports or as the answer to
/// `get_receipt_currency_minor_unit`, and until one of those has arrived the
/// caller has nothing to pass and must not invent one.
///
/// A two-decimal assumption used to live here. It was right for EUR and wrong
/// for JPY by a factor of 100, for KWD by 10 and for CLF by 100 — silently, into
/// an immutable row. Nothing in this module now returns a number of decimals.
library;

import '../../../domain/entities/receipt_confirmation_input.dart';

/// Why a typed amount could not become minor units.
///
/// A field-level discriminant, never backend text: this parse happens entirely
/// on the device, before anything is sent.
enum MinorUnitProblem {
  /// Nothing was typed.
  empty,

  /// Characters that are not part of a plain decimal amount.
  notANumber,

  /// More decimal places than the currency has. Refused rather than rounded:
  /// silently dropping a digit changes the figure a person entered.
  tooPrecise,

  /// Outside the `0 … 10^12` range every amount CHECK enforces.
  outOfRange,
}

/// The outcome of reading one typed amount.
sealed class MinorUnitResult {
  const MinorUnitResult();
}

/// The text was a plain amount, and this is it in integer minor units.
final class MinorUnitValue extends MinorUnitResult {
  const MinorUnitValue(this.minor);

  final int minor;
}

/// The text was refused, and [problem] says which rule it broke.
final class MinorUnitRefusal extends MinorUnitResult {
  const MinorUnitRefusal(this.problem);

  final MinorUnitProblem problem;
}

/// Reads a typed amount into integer minor units.
///
/// Accepts an ordinary decimal with either separator — `125.50` and `125,50`
/// are the same amount, and a shop-floor keyboard produces both. A string
/// containing *both* separators is refused rather than guessed at: `1,234.56`
/// and `1.234,56` are indistinguishable without a locale this application does
/// not carry, and inventing one would misread a total by three orders of
/// magnitude.
///
/// A **space inside** the digits is refused for the same reason. It is a
/// thousands separator in several locales, which would make `1 234` mean one
/// thousand — and it is equally often a typo, which would make it mean the same
/// thing by accident. Removing it silently turns both into `1234`; refusing it
/// costs one keystroke and never misreads a total by three orders of magnitude.
/// Spaces around the amount are trimmed, because those carry no meaning at
/// all.
MinorUnitResult parseMinorUnits(String raw, int digits) {
  final String text = raw.trim();
  if (text.isEmpty) {
    return const MinorUnitRefusal(MinorUnitProblem.empty);
  }

  final bool hasDot = text.contains('.');
  final bool hasComma = text.contains(',');
  if (hasDot && hasComma) {
    return const MinorUnitRefusal(MinorUnitProblem.notANumber);
  }

  final String normalized = hasComma ? text.replaceAll(',', '.') : text;
  if (normalized.indexOf('.') != normalized.lastIndexOf('.')) {
    return const MinorUnitRefusal(MinorUnitProblem.notANumber);
  }

  final int separator = normalized.indexOf('.');
  final String whole = separator < 0
      ? normalized
      : normalized.substring(0, separator);
  final String fraction = separator < 0
      ? ''
      : normalized.substring(separator + 1);

  // An amount is a sequence of digits. No sign, no exponent, no currency
  // symbol: a negative receipt total is out of scope for this milestone and a
  // symbol belongs to the label beside the field, not inside it.
  if (!_isDigits(whole) && whole.isNotEmpty) {
    return const MinorUnitRefusal(MinorUnitProblem.notANumber);
  }
  if (!_isDigits(fraction) && fraction.isNotEmpty) {
    return const MinorUnitRefusal(MinorUnitProblem.notANumber);
  }
  if (whole.isEmpty && fraction.isEmpty) {
    return const MinorUnitRefusal(MinorUnitProblem.notANumber);
  }
  if (fraction.length > digits) {
    return const MinorUnitRefusal(MinorUnitProblem.tooPrecise);
  }

  final String joined =
      (whole.isEmpty ? '0' : whole) + fraction.padRight(digits, '0');

  // int.tryParse and not a multiplication. The characters ARE the integer.
  final int? minor = int.tryParse(joined);
  if (minor == null) {
    return const MinorUnitRefusal(MinorUnitProblem.outOfRange);
  }
  if (minor < minMinorAmount || minor > maxMinorAmount) {
    return const MinorUnitRefusal(MinorUnitProblem.outOfRange);
  }
  return MinorUnitValue(minor);
}

/// Renders integer minor units as the text a person recognises.
///
/// The inverse of [parseMinorUnits] and, like it, pure string work: the integer
/// is padded and then split, so nothing is ever divided.
String formatMinorUnits(int minor, int digits) {
  if (digits <= 0) {
    return minor.toString();
  }
  final String padded = minor.toString().padLeft(digits + 1, '0');
  final int cut = padded.length - digits;
  return '${padded.substring(0, cut)}.${padded.substring(cut)}';
}

/// `AED 125.50` — the amount with the currency it was written in.
///
/// The code is placed before the figure and never translated into a symbol:
/// the backend stores an ISO alphabetic code, and a symbol would be this
/// client asserting a mapping nobody supplied.
String formatMinorAmount(int minor, String? currencyCode, int digits) {
  final String amount = formatMinorUnits(minor, digits);
  final String code = currencyCode?.trim() ?? '';
  return code.isEmpty ? amount : '$code $amount';
}

bool _isDigits(String value) {
  if (value.isEmpty) {
    return false;
  }
  for (int i = 0; i < value.length; i++) {
    final int unit = value.codeUnitAt(i);
    if (unit < 0x30 || unit > 0x39) {
      return false;
    }
  }
  return true;
}
