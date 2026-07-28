import '../../../../core/parsing/rpc_row.dart';
import '../../domain/entities/retailer_assignable_shop.dart';

/// The canonical uuid shape, matched case-insensitively.
///
/// Applied to `shop_id` because this is the one Retailer read whose value is
/// **sent back** to the backend. Everywhere else an unexpected string would only
/// be displayed; here it would become an element of `shopIds`, and a client that
/// forwarded a malformed one would turn a readable local refusal into an opaque
/// `INVALID_REQUEST` from the function.
final RegExp _uuidShape = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Parses `list_retailer_staff_assignable_shops()`.
///
/// ## The whole list, or none of it
///
/// One malformed row fails the read. Skipping bad rows would silently
/// under-report which shops a Sales Staff member may be assigned to, and a
/// picker quietly missing a shop is worse than one that honestly failed to load:
/// nobody would know to look for the absent option.
///
/// ## Which malformations are rejected, and which are tolerated
///
/// Rejected, because guessing would state something false:
///
/// * a body that is not a list, or a row that is not an object;
/// * a missing, null, blank or non-string `shop_id`, or one that is not shaped
///   like a uuid;
/// * a **duplicate** `shop_id` across rows — the id is the primary key and the
///   backend's ordering ends `, s.id`, so two rows sharing one is evidence the
///   response is not this contract, and a picker built from it could send the
///   same shop twice, which the function refuses outright;
/// * a missing, null, blank or non-string `shop_name`;
/// * a non-string `shop_code` or `city`.
///
/// Tolerated, because the contract is explicitly additive or genuinely nullable:
///
/// * an **empty list** → an empty result. A real answer, and a meaningful one: a
///   refused caller raises `42501` instead, so an empty picker genuinely means
///   this Retailer has no ACTIVE shops.
/// * an **unrecognized extra key** → ignored. A new column must not break an old
///   client.
/// * a **null `shop_code` or `city`** → null. Both are nullable in the schema, so
///   null means "not recorded" and renders as an absence rather than an empty
///   string.
/// * two shops sharing a **name, code and city** → both kept. The schema has no
///   uniqueness constraint across those columns, and the two rows are still
///   distinct shops with distinct ids, which is what the selection is keyed on.
///
/// ## There is no status here to parse
///
/// The function filters `status = 'ACTIVE'` itself and returns no status column.
/// This parser therefore has no status field, no status enum and no inactive
/// case — an inactive shop simply is not in the response. Inventing a status
/// would be inventing a value the backend never sent.
abstract final class RetailerAssignableShopParser {
  static List<RetailerAssignableShop> parse(Object? raw) {
    final List<RetailerAssignableShop> shops = RpcRow.asRows(
      raw,
      'shops',
    ).map(RetailerAssignableShopParser.parseRow).toList(growable: false);

    final Set<String> seen = <String>{};
    for (final RetailerAssignableShop shop in shops) {
      if (!seen.add(shop.id)) {
        throw const RpcFormatException('shop_id is duplicated across rows');
      }
    }

    return shops;
  }

  /// One row. Exposed so a test can pin a single field's behaviour without
  /// wrapping it in a list every time.
  static RetailerAssignableShop parseRow(Map<String, Object?> row) {
    final String id = RpcRow.requiredString(row['shop_id'], 'shop_id');
    if (!_uuidShape.hasMatch(id.trim())) {
      throw const RpcFormatException('shop_id is not shaped like a uuid');
    }

    return RetailerAssignableShop(
      // Lower-cased so the value held is the value the contract canonicalizes to
      // — the function lower-cases each submitted id before validating it, and a
      // local duplicate check that compared unfolded spellings could pass two
      // ids the function would then refuse as one duplicate.
      id: id.trim().toLowerCase(),
      name: RpcRow.requiredString(row['shop_name'], 'shop_name'),
      code: RpcRow.optionalString(row['shop_code'], 'shop_code'),
      city: RpcRow.optionalString(row['city'], 'city'),
    );
  }
}
