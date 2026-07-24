import '../../domain/entities/receipt_product.dart';
import '../../domain/entities/receipt_shop.dart';
import '../../domain/entities/receipt_submission.dart';
import '../../domain/entities/receipt_submission_status.dart';

/// A receipt response could not be understood.
///
/// Every branch that throws this is a branch that would otherwise have to guess,
/// and the only safe guess is none. The repository turns it into an operational
/// failure — **never** into an empty list, never into a fabricated success, and
/// never into access denied.
final class ReceiptFormatException implements Exception {
  const ReceiptFormatException(this.reason);

  /// A short, developer-facing reason. Never rendered to a user, and never
  /// carrying a value read from the response.
  final String reason;

  @override
  String toString() => 'ReceiptFormatException: $reason';
}

/// The 8-4-4-4-12 hexadecimal shape of a UUID.
final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Whether [value] is shaped like a UUID.
///
/// Used before a submission id is put into a request, so a malformed identifier
/// cannot reach the backend dressed as a real one.
bool isUuid(String value) => _uuid.hasMatch(value);

/// Parses `list_my_assigned_receipt_shops()`.
abstract final class ReceiptShopParser {
  static List<ReceiptShop> parseList(Object? raw) {
    return _rows(raw, 'shops').map(parse).toList(growable: false);
  }

  static ReceiptShop parse(Map<String, Object?> row) {
    return ReceiptShop(
      shopId: _uuidField(row['shop_id'], 'shop.shop_id'),
      shopName: _requiredString(row['shop_name'], 'shop.shop_name'),
      shopCode: _optionalString(row['shop_code'], 'shop.shop_code'),
    );
  }
}

/// Parses `list_my_receipt_products()`.
abstract final class ReceiptProductParser {
  static List<ReceiptProduct> parseList(Object? raw) {
    return _rows(raw, 'products').map(parse).toList(growable: false);
  }

  static ReceiptProduct parse(Map<String, Object?> row) {
    return ReceiptProduct(
      productId: _uuidField(row['product_id'], 'product.product_id'),
      productCode: _requiredString(row['product_code'], 'product.product_code'),
      productName: _requiredString(row['product_name'], 'product.product_name'),
      barcode: _optionalString(row['barcode'], 'product.barcode'),
      brand: _optionalString(row['brand'], 'product.brand'),
    );
  }
}

/// Parses `list_my_receipt_submissions()` **and**
/// `get_my_receipt_submission(uuid)`.
///
/// One parser for both, because the backend made the two shapes byte-identical
/// on purpose so that a future column addition has to be made to both or to
/// neither. A second parser would be free to drift, and only one of the two
/// could be right.
abstract final class ReceiptSubmissionParser {
  static List<ReceiptSubmission> parseList(Object? raw) {
    return _rows(raw, 'submissions').map(parse).toList(growable: false);
  }

  /// The single-row read. Zero rows is a legitimate answer and yields null.
  ///
  /// The backend returns zero rows for a nonexistent id, another person's id and
  /// another Retailer's id alike — indistinguishably, so there is no existence
  /// oracle. This parser preserves that by having exactly one representation for
  /// all three.
  static ReceiptSubmission? parseSingle(Object? raw) {
    final List<Map<String, Object?>> rows = _rows(raw, 'submission');
    if (rows.isEmpty) {
      return null;
    }
    if (rows.length > 1) {
      // The function filters on a primary key; more than one row means the
      // response is not the one this build was written against.
      throw const ReceiptFormatException('submission returned several rows');
    }
    return parse(rows.first);
  }

  static ReceiptSubmission parse(Map<String, Object?> row) {
    return ReceiptSubmission(
      submissionId: _uuidField(
        row['submission_id'],
        'submission.submission_id',
      ),
      shopName: _requiredString(row['shop_name'], 'submission.shop_name'),
      shopCode: _optionalString(row['shop_code'], 'submission.shop_code'),
      // A status token this build does not know degrades to `unknown`; a
      // missing or blank one is a required value the response did not supply,
      // and _requiredString rejects it.
      status: ReceiptSubmissionStatus.fromCode(
        _requiredString(row['status'], 'submission.status'),
      ),
      originalFileName: _requiredString(
        row['original_file_name'],
        'submission.original_file_name',
      ),
      mimeType: _requiredString(row['mime_type'], 'submission.mime_type'),
      fileSizeBytes: _requiredInt(
        row['file_size_bytes'],
        'submission.file_size_bytes',
      ),
      submittedAt: _optionalTimestamp(
        row['submitted_at'],
        'submission.submitted_at',
      ),
      createdAt: _requiredTimestamp(row['created_at'], 'submission.created_at'),
    );
  }
}

// ---------------------------------------------------------------------------
// Strict field readers
//
// Every one of these throws rather than substituting a default. A default here
// would be a value the backend never sent, presented as though it had — which is
// how a malformed response becomes fabricated data.
// ---------------------------------------------------------------------------

List<Map<String, Object?>> _rows(Object? raw, String what) {
  if (raw is! List) {
    throw ReceiptFormatException('$what is not a list');
  }
  return raw
      .map<Map<String, Object?>>((Object? element) {
        if (element is! Map) {
          throw ReceiptFormatException('$what row is not an object');
        }
        return element.map<String, Object?>(
          (Object? key, Object? value) =>
              MapEntry<String, Object?>('$key', value),
        );
      })
      .toList(growable: false);
}

String _requiredString(Object? raw, String what) {
  if (raw is String && raw.trim().isNotEmpty) {
    return raw;
  }
  throw ReceiptFormatException('$what missing or blank');
}

/// A nullable column. Absent and SQL NULL both yield null; a present value of
/// the wrong type is malformed, not "close enough".
String? _optionalString(Object? raw, String what) {
  if (raw == null) {
    return null;
  }
  if (raw is String) {
    // A blank optional string is normalized to null: the schema forbids storing
    // one, so it cannot be meaningful data.
    return raw.trim().isEmpty ? null : raw;
  }
  throw ReceiptFormatException('$what is not a string');
}

String _uuidField(Object? raw, String what) {
  final String value = _requiredString(raw, what);
  if (!isUuid(value)) {
    throw ReceiptFormatException('$what is not a UUID');
  }
  return value;
}

/// A `bigint` column.
///
/// Accepts an integer, and a `num` whose value is integral — JSON has one number
/// type and a transport is entitled to hand back `1.0`. A string is refused: a
/// numeric column arriving as text means the response is not the shape this
/// build was written against.
int _requiredInt(Object? raw, String what) {
  if (raw is int) {
    return raw;
  }
  if (raw is num && raw == raw.roundToDouble() && raw.isFinite) {
    return raw.toInt();
  }
  throw ReceiptFormatException('$what is not an integer');
}

DateTime _requiredTimestamp(Object? raw, String what) {
  final DateTime? parsed = _tryTimestamp(raw);
  if (parsed == null) {
    throw ReceiptFormatException('$what is not a timestamp');
  }
  return parsed;
}

DateTime? _optionalTimestamp(Object? raw, String what) {
  if (raw == null) {
    return null;
  }
  final DateTime? parsed = _tryTimestamp(raw);
  if (parsed == null) {
    throw ReceiptFormatException('$what is not a timestamp');
  }
  return parsed;
}

/// Normalized to UTC on the way in, so the only place a timezone is applied is
/// where a value is formatted for display.
DateTime? _tryTimestamp(Object? raw) {
  if (raw is! String) {
    return null;
  }
  return DateTime.tryParse(raw)?.toUtc();
}
