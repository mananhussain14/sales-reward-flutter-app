import 'package:supabase_flutter/supabase_flutter.dart';

/// The one Vendor Dashboard RPC, named exactly once.
const String vendorDashboardSummaryRpc = 'get_vendor_admin_dashboard_summary';

/// Invokes `get_vendor_admin_dashboard_summary()`.
///
/// ## Zero arguments, and that is the whole contract
///
/// The typedef takes nothing, because the function takes nothing. There is no
/// auth user id, profile id, membership id, Vendor organization id, tenant id,
/// organization name, role code, permission code, status, date range, period or
/// current-Vendor selector to express at this boundary — so there is none to get
/// wrong, and no future edit can quietly add one without changing this type.
///
/// The Vendor is derived server-side from `auth.uid()` through
/// `get_vendor_super_admin_context()`, with the same lowest-organization-id
/// tie-break every other Vendor RPC applies. That is also the resolver behind the
/// organization name the session already holds, which is why the name on screen
/// and the counts on screen describe the same organization without either being
/// sent to the other.
typedef VendorDashboardSummaryInvoker = Future<Object?> Function();

/// The production invoker.
///
/// The only place in the application that names the Vendor Dashboard RPC and
/// touches the Supabase client for it. Note the call site: a function name, and
/// nothing else at all.
///
/// **No `params` map is passed, not even an empty one.** An empty map would be
/// harmless today and would be the obvious place for someone to later add "just
/// one" selector; omitting it makes the zero-argument shape visible at the call
/// site rather than implied by an absence of keys.
VendorDashboardSummaryInvoker supabaseVendorDashboardSummaryInvoker(
  SupabaseClient client,
) {
  return () => client.rpc<Object?>(vendorDashboardSummaryRpc);
}

/// Reads the dashboard summary a Vendor Super Admin is entitled to.
///
/// Thin by design: it performs the call and lets exceptions propagate. Turning an
/// exception into a `Failure` is the repository's job and turning a body into a
/// domain object is the parser's, so each of the three has one reason to change.
///
/// **No table is ever read here.** There is no query against
/// `organization_members`, `roles`, `permissions`, `audit_logs`, `organizations`,
/// `profiles` or `auth.users` under any spelling, and no `count` head request.
/// The web assembles this page from four separate table reads plus an
/// authorization round trip; reproducing that in Dart would put the metric
/// definitions — including *which two of the four are not tenant-scoped at all* —
/// into a second client free to drift from the first.
///
/// **No write.** The function is `STABLE` and contains no insert, update or
/// delete, and none is named here. Reading a count is not an event, so this call
/// records no audit row of its own.
final class VendorDashboardRpcDataSource {
  const VendorDashboardRpcDataSource({
    required VendorDashboardSummaryInvoker summary,
  }) : _summary = summary;

  /// Builds the data source against a live client.
  factory VendorDashboardRpcDataSource.forClient(SupabaseClient client) {
    return VendorDashboardRpcDataSource(
      summary: supabaseVendorDashboardSummaryInvoker(client),
    );
  }

  final VendorDashboardSummaryInvoker _summary;

  /// The whole summary, in one round trip.
  Future<Object?> fetchSummary() => _summary();
}
