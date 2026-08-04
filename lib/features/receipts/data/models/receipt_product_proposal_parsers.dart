import '../../domain/entities/receipt_product_proposal_line.dart';
import '../../domain/entities/receipt_with_products_outcome.dart';
import '../../domain/entities/receipt_with_products_result.dart';
import 'receipt_parsers.dart' show ReceiptFormatException;

/// Parses `get_my_receipt_product_proposal(uuid)`.
///
/// Field by field, never a spread: a column added to the function later must be
/// admitted here consciously before it can reach a screen.
abstract final class ReceiptProductProposalParser {
  /// Zero rows is a legitimate answer — "this receipt has no proposal", and
  /// also "this receipt is not yours or does not exist". The function makes the
  /// three indistinguishable on purpose, so this returns an empty list for all
  /// of them and the caller must not read anything more into it.
  static List<ReceiptProductProposalLine> parseList(Object? raw) {
    final List<ReceiptProductProposalLine> lines = _rows(
      raw,
      'proposal',
    ).map(parse).toList(growable: true);
    // The function orders by line_number; sorting again costs nothing and makes
    // the ordering a property of this build rather than of the wire.
    lines.sort(
      (ReceiptProductProposalLine a, ReceiptProductProposalLine b) =>
          a.lineNumber.compareTo(b.lineNumber),
    );
    return List<ReceiptProductProposalLine>.unmodifiable(lines);
  }

  static ReceiptProductProposalLine parse(Map<String, Object?> row) {
    return ReceiptProductProposalLine(
      lineNumber: _requiredInt(row['line_number'], 'proposal.line_number'),
      quantity: _requiredInt(row['quantity'], 'proposal.quantity'),
      productCode: _requiredString(
        row['product_code_at_proposal'],
        'proposal.product_code_at_proposal',
      ),
      productName: _requiredString(
        row['product_name_at_proposal'],
        'proposal.product_name_at_proposal',
      ),
      barcode: _optionalString(
        row['barcode_at_proposal'],
        'proposal.barcode_at_proposal',
      ),
      brand: _optionalString(
        row['brand_at_proposal'],
        'proposal.brand_at_proposal',
      ),
      productStatus: _requiredString(
        row['product_status_at_proposal'],
        'proposal.product_status_at_proposal',
      ),
    );
  }
}

/// Parses `confirm_receipt_with_products(...)`.
abstract final class ReceiptWithProductsResultParser {
  /// A response with no row is not a success.
  ///
  /// The RPC returns zero rows when the receipt is missing, foreign, someone
  /// else's or in the wrong status — the established staff-side oracle. That is
  /// not [ReceiptWithProductsOutcome.confirmed] and must never be rendered as
  /// one, so it becomes [ReceiptWithProductsOutcome.unknown] and the caller
  /// re-reads state rather than claiming anything.
  static ReceiptWithProductsResult parse(Object? raw) {
    final List<Map<String, Object?>> rows = _rows(raw, 'confirmation');
    if (rows.isEmpty) {
      return const ReceiptWithProductsResult(
        outcome: ReceiptWithProductsOutcome.unknown,
        lineCount: 0,
        changed: false,
      );
    }

    final Map<String, Object?> row = rows.first;
    final Object? rawOutcome = row['outcome'];
    final ReceiptWithProductsOutcome outcome = rawOutcome is String
        ? ReceiptWithProductsOutcome.fromCode(rawOutcome)
        : ReceiptWithProductsOutcome.unknown;

    return ReceiptWithProductsResult(
      outcome: outcome,
      confirmationId: _optionalUuid(
        row['confirmation_id'],
        'confirmation.confirmation_id',
      ),
      lineCount:
          _optionalInt(row['line_count'], 'confirmation.line_count') ?? 0,
      changed: row['changed'] == true,
    );
  }
}

// ---------------------------------------------------------------------------
// Local copies of the shared row helpers.
//
// receipt_parsers.dart keeps its own private, so these mirror them rather than
// widening that file's surface for one caller.
// ---------------------------------------------------------------------------

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

List<Map<String, Object?>> _rows(Object? raw, String what) {
  if (raw == null) {
    return const <Map<String, Object?>>[];
  }
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

String? _optionalString(Object? raw, String what) {
  if (raw == null) {
    return null;
  }
  if (raw is String) {
    return raw.trim().isEmpty ? null : raw;
  }
  throw ReceiptFormatException('$what is not a string');
}

String? _optionalUuid(Object? raw, String what) {
  final String? value = _optionalString(raw, what);
  if (value == null) {
    return null;
  }
  if (!_uuidPattern.hasMatch(value)) {
    throw ReceiptFormatException('$what is not a UUID');
  }
  return value;
}

int _requiredInt(Object? raw, String what) {
  if (raw is int) {
    return raw;
  }
  if (raw is num && raw == raw.roundToDouble() && raw.isFinite) {
    return raw.toInt();
  }
  throw ReceiptFormatException('$what is not an integer');
}

int? _optionalInt(Object? raw, String what) {
  if (raw == null) {
    return null;
  }
  return _requiredInt(raw, what);
}
