import 'package:supabase_flutter/supabase_flutter.dart';

/// The one Retailer shop RPC, named exactly once in the application.
const String retailerShopsRpc = 'list_retailer_owner_portal_shops';

/// Invokes `list_retailer_owner_portal_shops()`.
///
/// ## Zero arguments, and that is the whole contract
///
/// The typedef takes nothing, because the function takes nothing. There is no
/// Retailer organization id, shop id, auth user id, profile id, membership id,
/// tenant id, role code, permission code, status filter, search term, sort or
/// page selector to express at this boundary — so there is none to get wrong,
/// and no future edit can quietly add one without changing this type and the
/// boundary test that asserts its shape.
///
/// Ordering is the backend's: `order by s.name, s.code nulls last, s.id`. It is
/// not requested and not re-sorted here.
typedef RetailerShopsInvoker = Future<Object?> Function();

/// The production invoker.
///
/// The only place in the application that names this RPC and touches the
/// Supabase client for it. Note the call site: a function name, and nothing else
/// at all.
///
/// **No `params` map is passed, not even an empty one.** An empty map would be
/// harmless today and would be the obvious place for someone to later add "just
/// one" filter; omitting it makes the zero-argument shape visible at the call
/// site rather than implied by an absence of keys.
RetailerShopsInvoker supabaseRetailerShopsInvoker(SupabaseClient client) {
  return () => client.rpc<Object?>(retailerShopsRpc);
}

/// Reads the shops a Retailer Owner is entitled to.
///
/// Thin by design: it performs the call and lets exceptions propagate. Turning
/// an exception into a problem is the repository's job and turning a body into
/// domain objects is the parser's.
///
/// **No table is ever read here.** There is no query against `retailer_shops`,
/// `organizations`, `organization_members` or any other relation under any
/// spelling. A direct read would not merely be untidy — `retailer_shops` carries
/// exactly one *vendor-scoped* SELECT policy, which returns zero rows to a
/// Retailer Owner by design, so a client that tried would render an empty estate
/// for every Owner and look entirely plausible doing it.
///
/// **No write.** The function is `STABLE` and contains no insert, update or
/// delete, and none is named here — there is no shop create, edit, status change
/// or delete anywhere in this application.
final class RetailerShopRpcDataSource {
  const RetailerShopRpcDataSource({required RetailerShopsInvoker shops})
    : _shops = shops;

  /// Builds the data source against a live client.
  factory RetailerShopRpcDataSource.forClient(SupabaseClient client) {
    return RetailerShopRpcDataSource(
      shops: supabaseRetailerShopsInvoker(client),
    );
  }

  final RetailerShopsInvoker _shops;

  /// Every shop, in one round trip.
  Future<Object?> fetchShops() => _shops();
}
