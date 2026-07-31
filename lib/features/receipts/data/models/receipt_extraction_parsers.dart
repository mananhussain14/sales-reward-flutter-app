import '../../domain/entities/extracted_value.dart';
import '../../domain/entities/receipt_civil_date.dart';
import '../../domain/entities/receipt_civil_time.dart';
import '../../domain/entities/receipt_confirmation.dart';
import '../../domain/entities/receipt_confirmation_entry_mode.dart';
import '../../domain/entities/receipt_confirmation_field.dart';
import '../../domain/entities/receipt_confirmation_input.dart';
import '../../domain/entities/receipt_confirmation_outcome.dart';
import '../../domain/entities/receipt_confirmation_result.dart';
import '../../domain/entities/receipt_currency_minor_unit.dart';
import '../../domain/entities/receipt_extraction.dart';
import '../../domain/entities/receipt_extraction_failure_code.dart';
import '../../domain/entities/receipt_extraction_line_item.dart';
import '../../domain/entities/receipt_extraction_request_outcome.dart';
import '../../domain/entities/receipt_extraction_request_result.dart';
import '../../domain/entities/receipt_extraction_status.dart';
import '../../domain/entities/receipt_extraction_warning_code.dart';
import '../../domain/entities/receipt_image_preview.dart';
import 'receipt_parsers.dart';

/// Parsers for the receipt extraction and confirmation contract.
///
/// They share [ReceiptFormatException] and [isUuid] with the submission parsers
/// next door rather than declaring a second unreadable-response type: one
/// feature, one meaning for "this response is not the shape this build was
/// written against".
///
/// ## Every reader here refuses rather than substitutes
///
/// A default in a parser is a value the backend never sent, presented as though
/// it had. On this contract that is how somebody comes to be shown a receipt
/// total of zero, an empty warning list on a receipt the provider flagged, or a
/// confirmation entry mode nobody derived. The repository turns a refusal into
/// `ExtractionMalformedResponseProblem`, which is neither a denial nor a
/// success.
///
/// ## Money never becomes a double
///
/// [_minorAmount] returns `int` and there is no other amount reader. A `num`
/// with a fractional part is refused outright: the backend assembles minor units
/// by string concatenation precisely so that no value ever travels as a decimal,
/// so a fraction arriving here means the response is not this contract's.

/// Parses the `extraction` payload the three Edge Functions share.
///
/// The payload is built key by key from an explicit allowlist on the server, so
/// this parser reads exactly those keys and no more. An unrecognised extra key
/// is ignored rather than refused: the server cannot send one today, and a
/// future additive column must not break an installed build.
abstract final class ReceiptExtractionParser {
  static ReceiptExtraction parse(Map<String, Object?> row) {
    return ReceiptExtraction(
      submissionId: _uuidField(
        row['submission_id'],
        'extraction.submission_id',
      ),
      extractionId: _uuidField(
        row['extraction_id'],
        'extraction.extraction_id',
      ),
      // A token this build does not know degrades to `unknown`; a missing or
      // blank one is a required value the response did not supply.
      status: ReceiptExtractionStatus.fromCode(
        _requiredString(row['status'], 'extraction.status'),
      ),
      attemptNumber: _requiredInt(
        row['attempt_number'],
        'extraction.attempt_number',
      ),
      attemptsUsed: _requiredInt(
        row['attempts_used'],
        'extraction.attempts_used',
      ),
      attemptsRemaining: _requiredInt(
        row['attempts_remaining'],
        'extraction.attempts_remaining',
      ),
      retryAllowed: _requiredBool(
        row['retry_allowed'],
        'extraction.retry_allowed',
      ),
      manualConfirmationAllowed: _requiredBool(
        row['manual_confirmation_allowed'],
        'extraction.manual_confirmation_allowed',
      ),
      confirmationExists: _requiredBool(
        row['confirmation_exists'],
        'extraction.confirmation_exists',
      ),
      failureCode: _failureCode(row['failure_code']),
      requestedAt: _requiredTimestamp(
        row['requested_at'],
        'extraction.requested_at',
      ),
      completedAt: _optionalTimestamp(
        row['completed_at'],
        'extraction.completed_at',
      ),
      merchantName: _extracted<String>(
        row,
        value: 'merchant_name',
        sourceText: 'merchant_name_source_text',
        confidence: 'merchant_name_confidence',
        read: (Object? raw, String what) => _optionalString(raw, what),
      ),
      documentNumber: _extracted<String>(
        row,
        value: 'document_number',
        sourceText: 'document_number_source_text',
        confidence: 'document_number_confidence',
        read: (Object? raw, String what) => _optionalString(raw, what),
      ),
      transactionDate: _extracted<ReceiptCivilDate>(
        row,
        value: 'transaction_date',
        sourceText: 'transaction_date_source_text',
        confidence: 'transaction_date_confidence',
        read: _optionalCivilDate,
      ),
      transactionTime: _extracted<ReceiptCivilTime>(
        row,
        value: 'transaction_time',
        sourceText: 'transaction_time_source_text',
        confidence: 'transaction_time_confidence',
        read: _optionalCivilTime,
      ),
      currencyCode: _extracted<String>(
        row,
        value: 'currency_code',
        sourceText: 'currency_code_source_text',
        confidence: 'currency_code_confidence',
        read: (Object? raw, String what) => _optionalString(raw, what),
      ),
      currencyMinorUnit: _optionalMinorUnit(row['currency_minor_unit']),
      // Note the asymmetry, which is the backend's and is reproduced exactly:
      // the tax value column is `tax_total_minor` while its companions are
      // `tax_source_text` and `tax_confidence`.
      total: _extracted<int>(
        row,
        value: 'total_minor',
        sourceText: 'total_source_text',
        confidence: 'total_confidence',
        read: _minorAmount,
      ),
      subtotal: _extracted<int>(
        row,
        value: 'subtotal_minor',
        sourceText: 'subtotal_source_text',
        confidence: 'subtotal_confidence',
        read: _minorAmount,
      ),
      taxTotal: _extracted<int>(
        row,
        value: 'tax_total_minor',
        sourceText: 'tax_source_text',
        confidence: 'tax_confidence',
        read: _minorAmount,
      ),
      warningCodes: _warningCodes(row['warning_codes']),
      lineItemCount: _requiredInt(
        row['line_item_count'],
        'extraction.line_item_count',
      ),
    );
  }
}

/// Parses the `request-receipt-extraction` body.
///
/// The counters are read from the **top level**, which is the authority for this
/// call, and the nested payload is parsed by [ReceiptExtractionParser] when one
/// is present. A null `extraction` is a real answer: no attempt row exists.
abstract final class ReceiptExtractionRequestResultParser {
  static ReceiptExtractionRequestResult parse(Map<String, Object?> body) {
    final Object? extraction = body['extraction'];

    return ReceiptExtractionRequestResult(
      outcome: ReceiptExtractionRequestOutcome.fromCode(
        _requiredString(body['outcome'], 'request.outcome'),
      ),
      attemptsUsed: _requiredInt(
        body['attempts_used'],
        'request.attempts_used',
      ),
      attemptsRemaining: _requiredInt(
        body['attempts_remaining'],
        'request.attempts_remaining',
      ),
      retryAllowed: _requiredBool(
        body['retry_allowed'],
        'request.retry_allowed',
      ),
      manualConfirmationAllowed: _requiredBool(
        body['manual_confirmation_allowed'],
        'request.manual_confirmation_allowed',
      ),
      extraction: extraction == null
          ? null
          : ReceiptExtractionParser.parse(
              _asMap(extraction, 'request.extraction'),
            ),
    );
  }
}

/// Parses the `extraction` envelope `get-receipt-extraction` returns.
///
/// That endpoint always carries a payload on a `200 ok`; a missing or null one
/// is malformed rather than "no attempt", because the absence of an attempt is
/// reported as `404` there instead.
abstract final class ReceiptExtractionEnvelopeParser {
  static ReceiptExtraction parse(Map<String, Object?> body) {
    return ReceiptExtractionParser.parse(
      _asMap(body['extraction'], 'get.extraction'),
    );
  }
}

/// Parses `list_my_receipt_extraction_line_items(uuid)`.
///
/// An empty array is a real, successful answer — no line items, or no successful
/// attempt — and passes straight through.
abstract final class ReceiptExtractionLineItemParser {
  static List<ReceiptExtractionLineItem> parseList(Object? raw) {
    return _rows(raw, 'line items').map(parse).toList(growable: false);
  }

  static ReceiptExtractionLineItem parse(Map<String, Object?> row) {
    return ReceiptExtractionLineItem(
      lineNumber: _requiredInt(row['line_number'], 'line item.line_number'),
      description: _optionalString(row['description'], 'line item.description'),
      descriptionSourceText: _optionalString(
        row['description_source_text'],
        'line item.description_source_text',
      ),
      quantity: _optionalDecimal(row['quantity'], 'line item.quantity'),
      quantitySourceText: _optionalString(
        row['quantity_source_text'],
        'line item.quantity_source_text',
      ),
      unitPriceMinor: _minorAmount(
        row['unit_price_minor'],
        'line item.unit_price_minor',
      ),
      unitPriceSourceText: _optionalString(
        row['unit_price_source_text'],
        'line item.unit_price_source_text',
      ),
      lineTotalMinor: _minorAmount(
        row['line_total_minor'],
        'line item.line_total_minor',
      ),
      lineTotalSourceText: _optionalString(
        row['line_total_source_text'],
        'line item.line_total_source_text',
      ),
      confidence: _optionalConfidence(
        row['confidence'],
        'line item.confidence',
      ),
    );
  }
}

/// Parses the `receipt-image-preview` body.
///
/// The URL is required and non-blank: a body without one is not a capability,
/// and presenting it as one would produce a review screen stuck on a broken
/// image with nothing to retry.
abstract final class ReceiptImagePreviewParser {
  static ReceiptImagePreview parse(Map<String, Object?> body) {
    return ReceiptImagePreview(
      url: _requiredString(body['url'], 'preview.url'),
      expiresInSeconds: _requiredInt(
        body['expires_in_seconds'],
        'preview.expires_in_seconds',
      ),
    );
  }
}

/// Parses `confirm_receipt_extraction(...)`.
///
/// Zero rows means the access predicate returned false, which the repository
/// reports as not-found — the same answer every unreadable receipt gets.
abstract final class ReceiptConfirmationResultParser {
  static ReceiptConfirmationResult? parseSingle(Object? raw) {
    final List<Map<String, Object?>> rows = _rows(raw, 'confirmation result');
    if (rows.isEmpty) {
      return null;
    }
    if (rows.length > 1) {
      throw const ReceiptFormatException(
        'confirmation result returned several rows',
      );
    }

    final Map<String, Object?> row = rows.first;
    final String? entryMode = _optionalString(
      row['entry_mode'],
      'confirmation result.entry_mode',
    );

    return ReceiptConfirmationResult(
      outcome: ReceiptConfirmationOutcome.fromCode(
        _requiredString(row['outcome'], 'confirmation result.outcome'),
      ),
      confirmationId: _optionalUuidField(
        row['confirmation_id'],
        'confirmation result.confirmation_id',
      ),
      entryMode: entryMode == null
          ? null
          : ReceiptConfirmationEntryMode.fromCode(entryMode),
      changedFields: _changedFields(row['changed_fields']),
    );
  }
}

/// Parses `get_my_receipt_confirmation(uuid)`.
///
/// Zero rows is a legitimate answer and yields null: the function returns none
/// for an unconfirmed receipt and for an unreadable one alike, and preserving
/// that single representation is what stops the read confirming that somebody
/// else's receipt exists.
abstract final class ReceiptConfirmationParser {
  static ReceiptConfirmation? parseSingle(Object? raw) {
    final List<Map<String, Object?>> rows = _rows(raw, 'confirmation');
    if (rows.isEmpty) {
      return null;
    }
    if (rows.length > 1) {
      // The table carries one confirmation per receipt, enforced by a unique
      // constraint; more than one row means this is not that contract.
      throw const ReceiptFormatException('confirmation returned several rows');
    }
    return parse(rows.first);
  }

  static ReceiptConfirmation parse(Map<String, Object?> row) {
    return ReceiptConfirmation(
      confirmationId: _uuidField(
        row['confirmation_id'],
        'confirmation.confirmation_id',
      ),
      entryMode: ReceiptConfirmationEntryMode.fromCode(
        _requiredString(row['entry_mode'], 'confirmation.entry_mode'),
      ),
      changedFields: _changedFields(row['changed_fields']),
      sourceExtractionId: _optionalUuidField(
        row['source_extraction_id'],
        'confirmation.source_extraction_id',
      ),
      transactionDate: _requiredCivilDate(
        row['transaction_date'],
        'confirmation.transaction_date',
      ),
      transactionTime: _optionalCivilTime(
        row['transaction_time'],
        'confirmation.transaction_time',
      ),
      currencyCode: _requiredString(
        row['currency_code'],
        'confirmation.currency_code',
      ),
      currencyMinorUnit: _requiredMinorUnit(
        row['currency_minor_unit'],
        'confirmation.currency_minor_unit',
      ),
      totalMinor: _requiredMinorAmount(
        row['total_minor'],
        'confirmation.total_minor',
      ),
      subtotalMinor: _minorAmount(
        row['subtotal_minor'],
        'confirmation.subtotal_minor',
      ),
      taxTotalMinor: _minorAmount(
        row['tax_total_minor'],
        'confirmation.tax_total_minor',
      ),
      merchantName: _optionalString(
        row['merchant_name'],
        'confirmation.merchant_name',
      ),
      documentNumber: _optionalString(
        row['document_number'],
        'confirmation.document_number',
      ),
      confirmedAt: _requiredTimestamp(
        row['confirmed_at'],
        'confirmation.confirmed_at',
      ),
    );
  }
}

/// `get_receipt_currency_minor_unit(text)` — zero rows, or exactly one.
///
/// The two properties that matter here are both refusals:
///
/// * **Zero rows is `null`, and `null` means unsupported.** It is never widened
///   into a width, never into a default, and never into an error: the backend
///   answers an unknown code, a blank one and a null one identically, and this
///   parser preserves that.
/// * **More than one row is unreadable, not a first-wins.** The function selects
///   on a primary key, so a second row means the response is not this contract's
///   — and quietly taking one of two candidate widths is precisely the silent
///   mis-scaling this whole correction exists to remove.
abstract final class ReceiptCurrencyMinorUnitParser {
  static ReceiptCurrencyMinorUnit? parseSingle(Object? raw) {
    final List<Map<String, Object?>> rows = _rows(raw, 'currency minor unit');
    if (rows.isEmpty) {
      return null;
    }
    if (rows.length > 1) {
      throw const ReceiptFormatException(
        'currency minor unit returned several rows',
      );
    }

    final Map<String, Object?> row = rows.first;
    final String code = _requiredString(
      row['currency_code'],
      'currency minor unit.currency_code',
    ).trim().toUpperCase();

    return ReceiptCurrencyMinorUnit(
      currencyCode: code,
      minorUnit: _requiredMinorUnit(
        row['minor_unit'],
        'currency minor unit.minor_unit',
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Strict field readers
//
// Every one of these throws rather than substituting a default. See the module
// header for why that is the only safe behaviour on this contract.
// ---------------------------------------------------------------------------

/// Assembles one field's value, source text and confidence.
///
/// The three are read independently, because they are independently nullable:
/// source text may exist when the value could not be normalized, and that is the
/// case a reviewer most needs to see.
ExtractedValue<T> _extracted<T extends Object>(
  Map<String, Object?> row, {
  required String value,
  required String sourceText,
  required String confidence,
  required T? Function(Object? raw, String what) read,
}) {
  return ExtractedValue<T>(
    value: read(row[value], 'extraction.$value'),
    sourceText: _optionalString(row[sourceText], 'extraction.$sourceText'),
    confidence: _optionalConfidence(row[confidence], 'extraction.$confidence'),
  );
}

List<Map<String, Object?>> _rows(Object? raw, String what) {
  if (raw is! List) {
    throw ReceiptFormatException('$what is not a list');
  }
  return raw
      .map<Map<String, Object?>>(
        (Object? element) => _asMap(element, '$what row'),
      )
      .toList(growable: false);
}

Map<String, Object?> _asMap(Object? raw, String what) {
  if (raw is! Map) {
    throw ReceiptFormatException('$what is not an object');
  }
  return raw.map<String, Object?>(
    (Object? key, Object? value) => MapEntry<String, Object?>('$key', value),
  );
}

String _requiredString(Object? raw, String what) {
  if (raw is String && raw.trim().isNotEmpty) {
    return raw;
  }
  throw ReceiptFormatException('$what missing or blank');
}

/// A nullable text column. A present value of the wrong type is malformed, not
/// "close enough"; a blank one is normalized to null, since the schema's
/// `not_empty` checks mean one cannot legally be stored.
String? _optionalString(Object? raw, String what) {
  if (raw == null) {
    return null;
  }
  if (raw is! String) {
    throw ReceiptFormatException('$what is not a string');
  }
  return raw.trim().isEmpty ? null : raw;
}

String _uuidField(Object? raw, String what) {
  final String value = _requiredString(raw, what);
  if (!isUuid(value)) {
    throw ReceiptFormatException('$what is not a UUID');
  }
  return value;
}

String? _optionalUuidField(Object? raw, String what) {
  final String? value = _optionalString(raw, what);
  if (value == null) {
    return null;
  }
  if (!isUuid(value)) {
    throw ReceiptFormatException('$what is not a UUID');
  }
  return value;
}

/// A `boolean` column that is never null in this contract.
///
/// A truthy string or a `1` is refused. Every one of these booleans is an
/// authorization-adjacent answer — may I retry, may I confirm, is it already
/// confirmed — and coercing a value into `true` is not a shortcut worth having.
bool _requiredBool(Object? raw, String what) {
  if (raw is bool) {
    return raw;
  }
  throw ReceiptFormatException('$what is not a boolean');
}

/// A non-negative `integer` column.
///
/// Accepts an integer and a `num` whose value is integral — JSON has one number
/// type and a transport may hand back `1.0`. A string is refused.
int _requiredInt(Object? raw, String what) {
  final int? value = _tryInt(raw);
  if (value == null) {
    throw ReceiptFormatException('$what is not an integer');
  }
  if (value < 0) {
    // Attempt numbers, counters and a line-item count are all bounded below by
    // zero in the schema. A negative one is evidence of a different contract.
    throw ReceiptFormatException('$what is negative');
  }
  return value;
}

/// A `bigint` amount in **integer minor units**, or null.
///
/// The range is the one the CHECK constraints enforce — `0` through `10^12`
/// inclusive — so a value outside it is a response this build was not written
/// against rather than a figure to clamp. A fractional number is refused for the
/// reason given in the module header: no amount in this contract is ever a
/// decimal on the wire.
int? _minorAmount(Object? raw, String what) {
  if (raw == null) {
    return null;
  }
  final int? value = _tryInt(raw);
  if (value == null) {
    throw ReceiptFormatException('$what is not an integer amount');
  }
  if (value < minMinorAmount || value > maxMinorAmount) {
    throw ReceiptFormatException('$what is outside the permitted range');
  }
  return value;
}

int _requiredMinorAmount(Object? raw, String what) {
  final int? value = _minorAmount(raw, what);
  if (value == null) {
    throw ReceiptFormatException('$what is missing');
  }
  return value;
}

/// `currency_minor_unit` — 0, 2, 3 or 4 in the seeded list.
///
/// Read as a bounded integer rather than an enumeration of the four values, so
/// a future ISO revision adding one does not break an installed build over a
/// display detail.
int? _optionalMinorUnit(Object? raw) {
  if (raw == null) {
    return null;
  }
  return _requiredMinorUnit(raw, 'extraction.currency_minor_unit');
}

int _requiredMinorUnit(Object? raw, String what) {
  final int value = _requiredInt(raw, what);
  if (!isSupportedMinorDigits(value)) {
    throw ReceiptFormatException('$what is not a plausible minor unit');
  }
  return value;
}

int? _tryInt(Object? raw) {
  if (raw is int) {
    return raw;
  }
  if (raw is num && raw.isFinite && raw == raw.roundToDouble()) {
    return raw.toInt();
  }
  return null;
}

/// A `numeric` confidence, bounded by a CHECK on both ends.
double? _optionalConfidence(Object? raw, String what) {
  final double? value = _optionalDecimal(raw, what);
  if (value == null) {
    return null;
  }
  if (value < 0 || value > 1) {
    throw ReceiptFormatException('$what is outside 0..1');
  }
  return value;
}

/// A `numeric` column that is genuinely fractional — a confidence or a quantity.
///
/// The only two such columns in this contract. Money is never read through here.
double? _optionalDecimal(Object? raw, String what) {
  if (raw == null) {
    return null;
  }
  if (raw is num) {
    if (!raw.isFinite) {
      throw ReceiptFormatException('$what is not a finite number');
    }
    return raw.toDouble();
  }
  // PostgREST renders `numeric` unquoted, but a transport is entitled to widen
  // a high-precision numeric into a string rather than lose digits.
  if (raw is String) {
    final double? parsed = double.tryParse(raw);
    if (parsed == null || !parsed.isFinite) {
      throw ReceiptFormatException('$what is not a number');
    }
    return parsed;
  }
  throw ReceiptFormatException('$what is not a number');
}

ReceiptExtractionFailureCode? _failureCode(Object? raw) {
  final String? value = _optionalString(raw, 'extraction.failure_code');
  return value == null ? null : ReceiptExtractionFailureCode.fromCode(value);
}

/// `warning_codes` — `text[] not null default '{}'`, so a missing key or a null
/// value is a malformed row rather than "no warnings".
///
/// Unlike the shared `stringArray` reader, an element that is not a string is
/// refused instead of dropped: a warning silently discarded is a review hint the
/// reviewer never sees, on the one contract whose warnings exist precisely to
/// draw their eye.
List<ReceiptExtractionWarningCode> _warningCodes(Object? raw) {
  if (raw is! List) {
    throw const ReceiptFormatException(
      'extraction.warning_codes is not an array',
    );
  }
  return raw
      .map<ReceiptExtractionWarningCode>((Object? element) {
        if (element is! String) {
          throw const ReceiptFormatException(
            'extraction.warning_codes holds a non-string',
          );
        }
        return ReceiptExtractionWarningCode.fromCode(element);
      })
      .toList(growable: false);
}

/// `changed_fields` — `text[] not null default '{}'` on the table, but the
/// blocked confirmation branch returns a literal `null::text[]`, which is a real
/// answer meaning "nothing was compared" and yields an empty list.
///
/// The backend sorts; the order it sent is preserved rather than re-sorted here.
List<ReceiptConfirmationField> _changedFields(Object? raw) {
  if (raw == null) {
    return const <ReceiptConfirmationField>[];
  }
  if (raw is! List) {
    throw const ReceiptFormatException('changed_fields is not an array');
  }
  return raw
      .map<ReceiptConfirmationField>((Object? element) {
        if (element is! String) {
          throw const ReceiptFormatException(
            'changed_fields holds a non-string',
          );
        }
        return ReceiptConfirmationField.fromCode(element);
      })
      .toList(growable: false);
}

ReceiptCivilDate _requiredCivilDate(Object? raw, String what) {
  final ReceiptCivilDate? parsed = _optionalCivilDate(raw, what);
  if (parsed == null) {
    throw ReceiptFormatException('$what is missing');
  }
  return parsed;
}

/// A `date` column. Never converted to a `DateTime`: see [ReceiptCivilDate].
ReceiptCivilDate? _optionalCivilDate(Object? raw, String what) {
  if (raw == null) {
    return null;
  }
  if (raw is! String) {
    throw ReceiptFormatException('$what is not a date string');
  }
  final ReceiptCivilDate? parsed = ReceiptCivilDate.tryParse(raw);
  if (parsed == null) {
    throw ReceiptFormatException('$what is not a parseable civil date');
  }
  return parsed;
}

/// A `time without time zone` column.
ReceiptCivilTime? _optionalCivilTime(Object? raw, String what) {
  if (raw == null) {
    return null;
  }
  if (raw is! String) {
    throw ReceiptFormatException('$what is not a time string');
  }
  final ReceiptCivilTime? parsed = ReceiptCivilTime.tryParse(raw);
  if (parsed == null) {
    throw ReceiptFormatException('$what is not a parseable civil time');
  }
  return parsed;
}

DateTime _requiredTimestamp(Object? raw, String what) {
  final DateTime? parsed = _optionalTimestamp(raw, what);
  if (parsed == null) {
    throw ReceiptFormatException('$what is missing');
  }
  return parsed;
}

/// A `timestamptz` column, normalized to UTC on the way in so nothing
/// downstream depends on the device's zone for ordering or equality.
DateTime? _optionalTimestamp(Object? raw, String what) {
  if (raw == null) {
    return null;
  }
  if (raw is! String) {
    throw ReceiptFormatException('$what is not a timestamp string');
  }
  final DateTime? parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    throw ReceiptFormatException('$what is not a parseable timestamp');
  }
  return parsed.toUtc();
}
