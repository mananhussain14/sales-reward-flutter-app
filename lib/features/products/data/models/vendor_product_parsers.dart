import '../../../retailers/domain/entities/vendor_retailer_status.dart';
import '../../domain/entities/vendor_product_assigned_retailer.dart';
import '../../domain/entities/vendor_product_assignment_status.dart';
import '../../domain/entities/vendor_product_detail.dart';
import '../../domain/entities/vendor_product_status.dart';
import '../../domain/entities/vendor_product_summary.dart';

/// A Vendor Product response could not be understood.
///
/// Every branch that throws this is a branch that would otherwise have to guess,
/// and the only safe guess is none. The repository turns it into an operational
/// failure — **never** into an empty catalogue, never into a fabricated product,
/// never into a fabricated count, never into an `ACTIVE` status, never into a
/// dropped assignment row, and never into access denied.
final class VendorProductFormatException implements Exception {
  const VendorProductFormatException(this.reason);

  /// A short, developer-facing reason. Never rendered to a user, and never
  /// carrying a value read from the response.
  final String reason;

  @override
  String toString() => 'VendorProductFormatException: $reason';
}

/// The 8-4-4-4-12 hexadecimal shape of a UUID.
final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Whether [value] is shaped like a product id.
///
/// Used before an id read off a route is put into a request, so a mistyped URL
/// cannot reach PostgREST as a `22P02` cast error and come back dressed as a
/// database outage — complete with a retry that could never succeed.
///
/// Declared here rather than imported from the Retailer or Role parsers on
/// purpose, matching those files' own reasoning: one feature reaching into
/// another's data layer for a regular expression is a dependency that outlives
/// the convenience, and this file must be readable as the whole of what this
/// feature parses.
bool isProductIdShaped(String value) => _uuid.hasMatch(value);

/// The ten columns `list_vendor_products()` and `get_vendor_product_detail()`
/// both return, read once.
///
/// This is the "one shared mapper for the common fields" the backend audit
/// recommends, and it is safe for exactly one reason: the backend pins those ten
/// columns byte-identical in **name, type and meaning** across the two reads —
/// including `active_assignment_count`, which is `bigint` on both sides — and
/// asserts that relationship structurally rather than by restating two literals.
///
/// It is a shared *parse*, not a shared *type*. Both entities are built from it
/// and neither inherits from the other, so the detail cannot silently widen the
/// summary's contract and a future column has to be added to both reads or to
/// neither.
typedef _CommonProductFields = ({
  String productId,
  String productCode,
  String? barcode,
  String productName,
  String? brand,
  String? description,
  VendorProductStatus status,
  int activeAssignmentCount,
  DateTime createdAt,
  DateTime updatedAt,
});

_CommonProductFields _common(Map<String, Object?> row, String what) {
  return (
    productId: _uuidField(row['product_id'], '$what.product_id'),
    productCode: _requiredString(row['product_code'], '$what.product_code'),
    // Nullable in the deployed schema — there is no separate SKU, GTIN, EAN or
    // UPC column, so this is the single GTIN-family field and null means the
    // product simply has none. Never replaced by the product code.
    barcode: _optionalString(row['barcode'], '$what.barcode'),
    productName: _requiredString(row['product_name'], '$what.product_name'),
    brand: _optionalString(row['brand'], '$what.brand'),
    description: _optionalString(row['description'], '$what.description'),
    // A token this build does not know degrades to `unknown`, which is never
    // active. A missing or blank one is a required value the response did not
    // supply, and _requiredString rejects it.
    status: VendorProductStatus.fromCode(
      _requiredString(row['status'], '$what.status'),
    ),
    activeAssignmentCount: _requiredCount(
      row['active_assignment_count'],
      '$what.active_assignment_count',
    ),
    createdAt: _requiredTimestamp(row['created_at'], '$what.created_at'),
    updatedAt: _requiredTimestamp(row['updated_at'], '$what.updated_at'),
  );
}

/// Parses `list_vendor_products()`.
abstract final class VendorProductSummaryParser {
  /// The rows, in the order the backend returned them.
  ///
  /// The SQL orders by `created_at desc, id desc` — total, so two products
  /// created in the same instant cannot swap places between requests. That order
  /// is preserved rather than re-sorted here: re-sorting would be a second,
  /// drifting definition of "the catalogue order", and it would immediately
  /// disagree with the web page showing the same rows.
  ///
  /// **One malformed row fails the whole read.** Dropping it would silently
  /// shorten a catalogue with no sign that anything was missing, and a Vendor
  /// counting their products would get a wrong answer from a screen that looked
  /// perfectly healthy.
  static List<VendorProductSummary> parseList(Object? raw) {
    return _rows(raw, 'product list').map(parse).toList(growable: false);
  }

  static VendorProductSummary parse(Map<String, Object?> row) {
    final _CommonProductFields fields = _common(row, 'product');

    return VendorProductSummary(
      productId: fields.productId,
      productCode: fields.productCode,
      barcode: fields.barcode,
      productName: fields.productName,
      brand: fields.brand,
      description: fields.description,
      status: fields.status,
      activeAssignmentCount: fields.activeAssignmentCount,
      createdAt: fields.createdAt,
      updatedAt: fields.updatedAt,
      // No assignment_count: the list does not return one, and inventing a
      // nullable field for it here is precisely what the two-entity shape
      // exists to prevent.
    );
  }
}

/// Parses `get_vendor_product_detail(uuid)`.
abstract final class VendorProductDetailParser {
  /// The single-row read. **Zero rows is a legitimate answer and yields null.**
  ///
  /// The backend returns zero rows for an unknown id, another Vendor's id, an id
  /// belonging to some other table and `null` alike — indistinguishably, so
  /// there is no existence oracle. This parser preserves that by having exactly
  /// one representation for all four, and by never turning any of them into an
  /// error the UI could word differently.
  static VendorProductDetail? parseSingle(Object? raw) {
    final List<Map<String, Object?>> rows = _rows(raw, 'product detail');
    if (rows.isEmpty) {
      return null;
    }
    if (rows.length > 1) {
      // The function filters on a primary key and the derived Vendor; more than
      // one row means the response is not the shape this build was written
      // against.
      throw const VendorProductFormatException(
        'product detail returned several rows',
      );
    }
    return parse(rows.first);
  }

  static VendorProductDetail parse(Map<String, Object?> row) {
    final _CommonProductFields fields = _common(row, 'detail');

    // The one column the list has no counterpart for, and the reason there are
    // two entities rather than one with a nullable count.
    final int assignmentCount = _requiredCount(
      row['assignment_count'],
      'detail.assignment_count',
    );
    _assertCountsAgree(assignmentCount, fields.activeAssignmentCount);

    return VendorProductDetail(
      productId: fields.productId,
      productCode: fields.productCode,
      barcode: fields.barcode,
      productName: fields.productName,
      brand: fields.brand,
      description: fields.description,
      status: fields.status,
      assignmentCount: assignmentCount,
      activeAssignmentCount: fields.activeAssignmentCount,
      createdAt: fields.createdAt,
      updatedAt: fields.updatedAt,
    );
  }
}

/// Parses `list_vendor_product_assigned_retailers(uuid)`.
abstract final class VendorProductAssignedRetailerParser {
  /// The assignment rows, in the backend's
  /// `retailer_name, retailer_organization_id` order.
  ///
  /// Nothing here sorts, de-duplicates or filters. The ordering is already
  /// deterministic and total in SQL — the tie-break is the organization id
  /// rather than the relationship id precisely because the latter is nullable —
  /// and a `Set` would hide a genuine backend duplication bug rather than
  /// prevent one (the unique index already makes duplicates impossible).
  ///
  /// **No row is dropped for any reason**, including a null `relationship_id`.
  /// The list's length is `assignment_count` by construction, so a client that
  /// quietly removed a row would put the list and the count in permanent,
  /// unexplainable disagreement.
  ///
  /// One malformed row fails the whole read, for the same reason.
  static List<VendorProductAssignedRetailer> parseList(Object? raw) {
    return _rows(raw, 'assigned retailers').map(parse).toList(growable: false);
  }

  static VendorProductAssignedRetailer parse(Map<String, Object?> row) {
    return VendorProductAssignedRetailer(
      // NULLABLE, and null is a real state rather than a fault: the SQL joins
      // the relationship LEFT, so a deleted `vendor_retailers` row surfaces here
      // as null instead of making the assignment vanish and contradict the
      // count. A present value must still be a real uuid.
      relationshipId: _optionalUuidField(
        row['relationship_id'],
        'assignment.relationship_id',
      ),
      retailerOrganizationId: _uuidField(
        row['retailer_organization_id'],
        'assignment.retailer_organization_id',
      ),
      retailerName: _requiredString(
        row['retailer_name'],
        'assignment.retailer_name',
      ),
      // NOT NULL — the join to `organizations` is on a primary key, so an
      // absent value means the response is not the shape this build expects.
      retailerStatus: VendorRetailerStatus.fromCode(
        _requiredString(row['retailer_status'], 'assignment.retailer_status'),
      ),
      // NULLABLE, and only ever null together with `relationship_id`. Null is
      // "there is no relationship row", which is a different statement from
      // "the relationship has a status this build does not recognise" — so it
      // stays null rather than becoming `unknown`.
      relationshipStatus: _optionalStatus(
        row['relationship_status'],
        'assignment.relationship_status',
      ),
      // NOT NULL, guaranteed: this read is driven FROM the assignment table, so
      // unlike the web's editor matrix it can never emit a null here. A missing
      // one is malformed, and is emphatically never read as ACTIVE.
      assignmentStatus: VendorProductAssignmentStatus.fromCode(
        _requiredString(
          row['assignment_status'],
          'assignment.assignment_status',
        ),
      ),
      assignedAt: _requiredTimestamp(
        row['assigned_at'],
        'assignment.assigned_at',
      ),
      // The assignment row's own `updated_at`. Not a `withdrawn_at` — no such
      // column exists — and no status is ever inferred from it.
      assignmentUpdatedAt: _requiredTimestamp(
        row['assignment_updated_at'],
        'assignment.assignment_updated_at',
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Strict field readers
//
// Every one of these throws rather than substituting a default. A default here
// would be a value the backend never sent, presented as though it had — which is
// how a malformed response becomes fabricated data, how an unreadable status
// becomes an ACTIVE product, and how a broken count becomes "this product is
// assigned to nobody".
// ---------------------------------------------------------------------------

List<Map<String, Object?>> _rows(Object? raw, String what) {
  if (raw is! List) {
    throw VendorProductFormatException('$what is not a list');
  }
  return raw
      .map<Map<String, Object?>>((Object? element) {
        if (element is! Map) {
          throw VendorProductFormatException('$what row is not an object');
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
  throw VendorProductFormatException('$what missing or blank');
}

/// A nullable `text` column.
///
/// Absent and SQL NULL both yield null — a product with no barcode, brand or
/// description. A value of the **wrong type** is malformed rather than "close
/// enough": rendering `42` where a brand belongs would be presenting a response
/// this build cannot read as though it had understood it.
///
/// A present-but-blank string also yields null, so a screen's "is there a
/// barcode?" test cannot be satisfied by whitespace.
String? _optionalString(Object? raw, String what) {
  if (raw == null) {
    return null;
  }
  if (raw is! String) {
    throw VendorProductFormatException('$what is not text');
  }
  return raw.trim().isEmpty ? null : raw;
}

String _uuidField(Object? raw, String what) {
  final String value = _requiredString(raw, what);
  if (!isProductIdShaped(value)) {
    throw VendorProductFormatException('$what is not a UUID');
  }
  return value;
}

/// A nullable `uuid` column.
///
/// Null is accepted and preserved — it is the documented state of an assignment
/// whose relationship row is gone. A **present** value must still be a real
/// uuid: a malformed one is a response this build cannot read, and passing it
/// through would put a broken address behind a "View Retailer" action.
String? _optionalUuidField(Object? raw, String what) {
  if (raw == null) {
    return null;
  }
  return _uuidField(raw, what);
}

/// A nullable status token.
///
/// Null yields null — the absence of a row, not an unfamiliar value, and the two
/// must not be collapsed: `unknown` would tell a reader "this relationship has a
/// status we do not recognise", which is a different and false claim.
///
/// A present value of the wrong type, or a blank string, is malformed. The
/// column is `NOT NULL` with a `CHECK` constraint wherever it exists, so a blank
/// cannot be data; accepting one would be inventing a fourth relationship state.
VendorRetailerStatus? _optionalStatus(Object? raw, String what) {
  if (raw == null) {
    return null;
  }
  if (raw is! String) {
    throw VendorProductFormatException('$what is not text');
  }
  return VendorRetailerStatus.fromCode(_requiredString(raw, what));
}

/// A `bigint` count column.
///
/// Accepts an integer, and a `num` whose value is integral — JSON has one number
/// type and a transport is entitled to hand back `3.0`. A string is refused: a
/// numeric column arriving as text means the response is not the shape this
/// build was written against.
///
/// **A negative count is refused rather than clamped.** `count(*)` cannot be
/// negative, so a negative value is evidence the response is not the one this
/// build expects, and clamping it to zero would tell a Vendor "no Retailer holds
/// this product" on the strength of a number the backend never produced.
int _requiredCount(Object? raw, String what) {
  final int value;
  if (raw is int) {
    value = raw;
  } else if (raw is num && raw.isFinite && raw == raw.roundToDouble()) {
    value = raw.toInt();
  } else {
    throw VendorProductFormatException('$what is not an integer');
  }

  if (value < 0) {
    throw VendorProductFormatException('$what is negative');
  }
  return value;
}

/// The active subset can never exceed the total.
///
/// `active_assignment_count` is `count(*) filter (where status = 'ACTIVE')` over
/// the very rows `assignment_count` counts, in the *same* lateral aggregate, so
/// the backend cannot produce a pair that violates this. A pair that does is a
/// response this build should not render — showing "2 Retailer assignments, 5
/// currently active" would be worse than an honest retry.
void _assertCountsAgree(int total, int active) {
  if (active > total) {
    throw const VendorProductFormatException(
      'detail active assignment count exceeds total assignment count',
    );
  }
}

DateTime _requiredTimestamp(Object? raw, String what) {
  if (raw is! String) {
    throw VendorProductFormatException('$what is not a timestamp');
  }
  final DateTime? parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    throw VendorProductFormatException('$what is not a timestamp');
  }
  // Normalized to UTC on the way in, so the only place a timezone is applied is
  // where a value is formatted for display.
  return parsed.toUtc();
}
