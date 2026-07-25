import '../../domain/entities/retailer_owner_state.dart';
import '../../domain/entities/vendor_retailer_detail.dart';
import '../../domain/entities/vendor_retailer_shop.dart';
import '../../domain/entities/vendor_retailer_status.dart';
import '../../domain/entities/vendor_retailer_summary.dart';

/// A Vendor Retailer response could not be understood.
///
/// Every branch that throws this is a branch that would otherwise have to guess,
/// and the only safe guess is none. The repository turns it into an operational
/// failure — **never** into an empty list, never into a fabricated Retailer, and
/// never into access denied.
final class VendorRetailerFormatException implements Exception {
  const VendorRetailerFormatException(this.reason);

  /// A short, developer-facing reason. Never rendered to a user, and never
  /// carrying a value read from the response.
  final String reason;

  @override
  String toString() => 'VendorRetailerFormatException: $reason';
}

/// The 8-4-4-4-12 hexadecimal shape of a UUID.
final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Whether [value] is shaped like a UUID.
///
/// Used before a relationship id read off a route is put into a request, so a
/// mistyped URL cannot reach PostgREST as a cast error and come back dressed as
/// a database outage.
///
/// Declared here rather than imported from the receipt parsers on purpose: one
/// feature reaching into another's data layer for a regular expression is a
/// dependency that outlives the convenience, and this file must be readable as
/// the whole of what this feature parses.
bool isRelationshipIdShaped(String value) => _uuid.hasMatch(value);

/// Parses `list_vendor_retailers()`.
abstract final class VendorRetailerSummaryParser {
  /// The rows, in the order the backend returned them.
  ///
  /// The SQL orders by `retailer_name, relationship_id` — total, so a re-fetch
  /// cannot make two rows swap places. That order is preserved rather than
  /// re-sorted here; re-sorting would be a second, drifting definition of "the
  /// directory order" and the two clients would disagree.
  static List<VendorRetailerSummary> parseList(Object? raw) {
    return _rows(raw, 'retailers').map(parse).toList(growable: false);
  }

  static VendorRetailerSummary parse(Map<String, Object?> row) {
    final int shopCount = _requiredCount(
      row['shop_count'],
      'retailer.shop_count',
    );
    final int activeShopCount = _requiredCount(
      row['active_shop_count'],
      'retailer.active_shop_count',
    );
    _assertCountsAgree(shopCount, activeShopCount, 'retailer');

    return VendorRetailerSummary(
      relationshipId: _uuidField(
        row['relationship_id'],
        'retailer.relationship_id',
      ),
      retailerOrganizationId: _uuidField(
        row['retailer_organization_id'],
        'retailer.retailer_organization_id',
      ),
      retailerName: _requiredString(
        row['retailer_name'],
        'retailer.retailer_name',
      ),
      // A status token this build does not know degrades to `unknown`, which is
      // never active. A missing or blank one is a required value the response
      // did not supply, and _requiredString rejects it.
      retailerStatus: VendorRetailerStatus.fromCode(
        _requiredString(row['retailer_status'], 'retailer.retailer_status'),
      ),
      relationshipStatus: VendorRetailerStatus.fromCode(
        _requiredString(
          row['relationship_status'],
          'retailer.relationship_status',
        ),
      ),
      relationshipCreatedAt: _requiredTimestamp(
        row['relationship_created_at'],
        'retailer.relationship_created_at',
      ),
      shopCount: shopCount,
      activeShopCount: activeShopCount,
      ownerState: RetailerOwnerState.fromCode(
        _requiredString(row['owner_state'], 'retailer.owner_state'),
      ),
    );
  }
}

/// Parses `get_vendor_retailer_detail(uuid)`.
abstract final class VendorRetailerDetailParser {
  /// The single-row read. **Zero rows is a legitimate answer and yields null.**
  ///
  /// The backend returns zero rows for a nonexistent id, another Vendor's id and
  /// `null` alike — indistinguishably, so there is no existence oracle. This
  /// parser preserves that by having exactly one representation for all three,
  /// and by never turning any of them into an error the UI could word
  /// differently.
  static VendorRetailerDetail? parseSingle(Object? raw) {
    final List<Map<String, Object?>> rows = _rows(raw, 'retailer detail');
    if (rows.isEmpty) {
      return null;
    }
    if (rows.length > 1) {
      // The function filters on a primary key and the derived Vendor; more than
      // one row means the response is not the shape this build was written
      // against.
      throw const VendorRetailerFormatException(
        'retailer detail returned several rows',
      );
    }
    return parse(rows.first);
  }

  static VendorRetailerDetail parse(Map<String, Object?> row) {
    final int shopCount = _requiredCount(
      row['shop_count'],
      'detail.shop_count',
    );
    final int activeShopCount = _requiredCount(
      row['active_shop_count'],
      'detail.active_shop_count',
    );
    _assertCountsAgree(shopCount, activeShopCount, 'detail');

    return VendorRetailerDetail(
      relationshipId: _uuidField(
        row['relationship_id'],
        'detail.relationship_id',
      ),
      retailerOrganizationId: _uuidField(
        row['retailer_organization_id'],
        'detail.retailer_organization_id',
      ),
      retailerName: _requiredString(
        row['retailer_name'],
        'detail.retailer_name',
      ),
      retailerStatus: VendorRetailerStatus.fromCode(
        _requiredString(row['retailer_status'], 'detail.retailer_status'),
      ),
      // `organizations.country_code` and `default_currency` are both declared
      // `null`-able. Absence is a Retailer that never recorded one, not a
      // malformed response — but a present value of the wrong type still is.
      countryCode: _optionalString(row['country_code'], 'detail.country_code'),
      defaultCurrency: _optionalString(
        row['default_currency'],
        'detail.default_currency',
      ),
      relationshipStatus: VendorRetailerStatus.fromCode(
        _requiredString(
          row['relationship_status'],
          'detail.relationship_status',
        ),
      ),
      relationshipCreatedAt: _requiredTimestamp(
        row['relationship_created_at'],
        'detail.relationship_created_at',
      ),
      shopCount: shopCount,
      activeShopCount: activeShopCount,
      ownerState: RetailerOwnerState.fromCode(
        _requiredString(row['owner_state'], 'detail.owner_state'),
      ),
    );
  }
}

/// Parses `list_vendor_retailer_shops(uuid)`.
abstract final class VendorRetailerShopParser {
  /// The rows, in the backend's `shop_name, shop_id` order. Not re-sorted.
  static List<VendorRetailerShop> parseList(Object? raw) {
    return _rows(raw, 'shops').map(parse).toList(growable: false);
  }

  static VendorRetailerShop parse(Map<String, Object?> row) {
    return VendorRetailerShop(
      shopId: _uuidField(row['shop_id'], 'shop.shop_id'),
      shopName: _requiredString(row['shop_name'], 'shop.shop_name'),
      // `retailer_shops.status` is NOT NULL, so a missing one is malformed. An
      // absent status is never read as ACTIVE — that is the one inference this
      // parser exists to refuse.
      shopStatus: VendorRetailerStatus.fromCode(
        _requiredString(row['shop_status'], 'shop.shop_status'),
      ),
      shopCode: _optionalString(row['shop_code'], 'shop.shop_code'),
      city: _optionalString(row['city'], 'shop.city'),
      countryCode: _optionalString(row['country_code'], 'shop.country_code'),
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
    throw VendorRetailerFormatException('$what is not a list');
  }
  return raw
      .map<Map<String, Object?>>((Object? element) {
        if (element is! Map) {
          throw VendorRetailerFormatException('$what row is not an object');
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
  throw VendorRetailerFormatException('$what missing or blank');
}

/// A nullable column. Absent and SQL NULL both yield null; a present value of
/// the wrong type is malformed, not "close enough".
String? _optionalString(Object? raw, String what) {
  if (raw == null) {
    return null;
  }
  if (raw is String) {
    // A blank optional string is normalized to null: the schema forbids storing
    // one (`retailer_shops_code_not_empty`), so it cannot be meaningful data.
    return raw.trim().isEmpty ? null : raw;
  }
  throw VendorRetailerFormatException('$what is not a string');
}

String _uuidField(Object? raw, String what) {
  final String value = _requiredString(raw, what);
  if (!isRelationshipIdShaped(value)) {
    throw VendorRetailerFormatException('$what is not a UUID');
  }
  return value;
}

/// An `integer` count column.
///
/// Accepts an integer, and a `num` whose value is integral — JSON has one number
/// type and a transport is entitled to hand back `3.0`. A string is refused: a
/// numeric column arriving as text means the response is not the shape this
/// build was written against.
///
/// **A negative count is refused rather than clamped.** `count(*)` cannot be
/// negative, so a negative value is evidence the response is not the one this
/// build expects, and clamping it to zero would show a Retailer "0 shops" on
/// the strength of a number the backend never produced.
int _requiredCount(Object? raw, String what) {
  final int value;
  if (raw is int) {
    value = raw;
  } else if (raw is num && raw.isFinite && raw == raw.roundToDouble()) {
    value = raw.toInt();
  } else {
    throw VendorRetailerFormatException('$what is not an integer');
  }

  if (value < 0) {
    throw VendorRetailerFormatException('$what is negative');
  }
  return value;
}

/// The active subset can never exceed the total.
///
/// `active_shop_count` is `count(*) filter (…)` over the same rows `shop_count`
/// counts, so the backend cannot produce a pair that violates this. A pair that
/// does is a response this build should not render — displaying "12 shops (40
/// active)" would be worse than an honest retry.
void _assertCountsAgree(int total, int active, String what) {
  if (active > total) {
    throw VendorRetailerFormatException(
      '$what active count exceeds total count',
    );
  }
}

DateTime _requiredTimestamp(Object? raw, String what) {
  if (raw is! String) {
    throw VendorRetailerFormatException('$what is not a timestamp');
  }
  final DateTime? parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    throw VendorRetailerFormatException('$what is not a timestamp');
  }
  // Normalized to UTC on the way in, so the only place a timezone is applied is
  // where a value is formatted for display.
  return parsed.toUtc();
}
