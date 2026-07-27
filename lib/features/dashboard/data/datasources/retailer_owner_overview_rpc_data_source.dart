import 'package:supabase_flutter/supabase_flutter.dart';

/// The one Retailer Owner Overview RPC, named exactly once in the application.
const String retailerOwnerOverviewRpc = 'get_retailer_owner_portal_context';

/// Invokes `get_retailer_owner_portal_context()`.
///
/// ## Zero arguments, and that is the whole contract
///
/// The typedef takes nothing, because the function takes nothing. There is no
/// Retailer organization id, auth user id, profile id, membership id, tenant id,
/// organization name, role code, permission code, status, date range or
/// current-Retailer selector to express at this boundary — so there is none to
/// get wrong, and no future edit can quietly add one without changing this type
/// and the boundary test that asserts its shape.
///
/// The organization is derived server-side: the function's `where` clause is
/// `o.id = public.resolve_retailer_owner_organization('RETAILER_PORTAL_READ')`,
/// and that resolver reads `auth.uid()`. A caller cannot nominate whose
/// authorization is evaluated or whose data is returned, because the only input
/// the function has is the session the request travels on.
typedef RetailerOwnerOverviewInvoker = Future<Object?> Function();

/// The production invoker.
///
/// The only place in the application that names this RPC and touches the
/// Supabase client for it. Note the call site: a function name, and nothing else
/// at all.
///
/// **No `params` map is passed, not even an empty one.** An empty map would be
/// harmless today and would be the obvious place for someone to later add "just
/// one" selector; omitting it makes the zero-argument shape visible at the call
/// site rather than implied by an absence of keys.
RetailerOwnerOverviewInvoker supabaseRetailerOwnerOverviewInvoker(
  SupabaseClient client,
) {
  return () => client.rpc<Object?>(retailerOwnerOverviewRpc);
}

/// Reads the overview a Retailer Owner is entitled to.
///
/// Thin by design: it performs the call and lets exceptions propagate. Turning
/// an exception into a problem is the repository's job and turning a body into a
/// domain object is the parser's, so each of the three has one reason to change.
///
/// **No table is ever read here.** There is no query against `organizations`,
/// `organization_members`, `retailer_shops`, `profiles`, `member_roles`, `roles`,
/// `role_permissions` or `permissions` under any spelling, and no `count` head
/// request. `retailer_shops` carries exactly one vendor-scoped SELECT policy,
/// which returns **zero rows** to a Retailer Owner by design — so a client that
/// tried to count shops directly would render `0` for every Owner and look
/// entirely plausible doing it. The counts are computed in SQL for precisely
/// that reason.
///
/// **No write.** The function is `STABLE` and contains no insert, update or
/// delete, and none is named here.
final class RetailerOwnerOverviewRpcDataSource {
  const RetailerOwnerOverviewRpcDataSource({
    required RetailerOwnerOverviewInvoker overview,
  }) : _overview = overview;

  /// Builds the data source against a live client.
  factory RetailerOwnerOverviewRpcDataSource.forClient(SupabaseClient client) {
    return RetailerOwnerOverviewRpcDataSource(
      overview: supabaseRetailerOwnerOverviewInvoker(client),
    );
  }

  final RetailerOwnerOverviewInvoker _overview;

  /// The whole overview, in one round trip.
  Future<Object?> fetchOverview() => _overview();
}
