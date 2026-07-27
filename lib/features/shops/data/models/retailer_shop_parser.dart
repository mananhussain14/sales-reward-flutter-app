import '../../../../core/parsing/rpc_row.dart';
import '../../domain/entities/retailer_shop.dart';

/// Parses `list_retailer_owner_portal_shops()`.
///
/// ## The whole list, or none of it
///
/// One malformed row fails the read. The alternative — skipping bad rows — would
/// silently under-report a Retailer's estate, and an estate that is quietly
/// short by one shop is worse than one that honestly failed to load, because
/// nothing on screen would say so.
///
/// ## Which malformations are rejected, and which are tolerated
///
/// Rejected, because guessing would state something false:
///
/// * a body that is not a list, or a row that is not an object;
/// * a missing, null, blank or non-string `shop_name`;
/// * a missing, null or non-string `shop_status`;
/// * a non-string `shop_code`, `city` or `country_code`.
///
/// Tolerated, because the contract is explicitly additive or genuinely nullable:
///
/// * an **empty list** → an empty result. A real answer, and on this contract an
///   ambiguous one — see `RetailerShopRepository.shops`.
/// * an **unrecognized extra key** → ignored. A new column must not break an old
///   client.
/// * an **unrecognized status token** → [RetailerShopStatus.unknown], displayed
///   neutrally and never as active.
/// * a **null `shop_code`, `city` or `country_code`** → null. All three are
///   nullable in the schema, so null means "not recorded".
/// * **duplicate rows** → kept, both of them. Two shops may legitimately share a
///   name, a city and a country — the schema has no uniqueness constraint across
///   those columns, and only `code` is distinctive when present. Deduplicating
///   here would hide a real shop, and because the contract returns no id there is
///   no way to tell a genuine duplicate from two distinct shops that look alike.
///   The list therefore shows exactly what the backend returned, in the backend's
///   own order.
abstract final class RetailerShopParser {
  static List<RetailerShop> parse(Object? raw) {
    return RpcRow.asRows(
      raw,
      'shops',
    ).map(RetailerShopParser.parseRow).toList(growable: false);
  }

  /// One row. Exposed so a test can pin a single field's behaviour without
  /// wrapping it in a list every time.
  static RetailerShop parseRow(Map<String, Object?> row) {
    return RetailerShop(
      name: RpcRow.requiredString(row['shop_name'], 'shop_name'),
      code: RpcRow.optionalString(row['shop_code'], 'shop_code'),
      city: RpcRow.optionalString(row['city'], 'city'),
      countryCode: RpcRow.optionalString(row['country_code'], 'country_code'),
      status: RetailerShopStatus.fromCode(
        RpcRow.requiredString(row['shop_status'], 'shop_status'),
      ),
      // No shop id, because the contract returns none. There is no field here to
      // put one in, which is what keeps a fabricated identifier out of the app
      // by construction rather than by a review rule.
    );
  }
}
