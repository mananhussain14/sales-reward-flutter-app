import 'package:supabase_flutter/supabase_flutter.dart';

/// The one Vendor Retailer lifecycle write RPC, named exactly once.
///
/// Deployed by `20260811090000_vendor_retailer_lifecycle.sql`, granted to
/// `authenticated` and to nothing else — not the anonymous role, not PUBLIC,
/// and not the privileged service role. This client calls the **same** deployed function the web
/// portal calls; there is no mobile twin and no second definition of "deactivate
/// a Retailer", so the two clients cannot disagree about the multi-Vendor
/// refusal, about which pairs are eligible, or about what survives a
/// deactivation.
const String setVendorRetailerStatusRpc = 'set_vendor_retailer_status';

/// The **two** parameter names this function accepts, and there is no third.
///
/// Named as constants so the whole payload vocabulary of this write is legible
/// in one place, and so a boundary test can assert the set exactly. Note what is
/// not here: no Vendor organization, Retailer organization, tenant, auth-user,
/// profile, membership, actor, role, permission, current-status, audit-action or
/// timestamp parameter — the function declares none, so none can be sent.
const String lifecycleRelationshipIdParameter = 'p_relationship_id';
const String lifecycleStatusParameter = 'p_status';

/// Invokes `set_vendor_retailer_status(uuid, text)`.
///
/// Two values: which relationship, and which of the two statuses. The status
/// arrives as a `String` because that is the RPC's parameter type, but the only
/// source of one is `VendorRetailerLifecycleStatus.code`, whose two members are
/// the only tokens the function's case-sensitive
/// `in ('ACTIVE', 'SUSPENDED')` test accepts.
///
/// The signature is the security property: with exactly two parameters there is
/// no third to get wrong, and a future edit that adds one has to change this
/// type.
typedef VendorRetailerLifecycleInvoker =
    Future<Object?> Function({
      required String relationshipId,
      required String status,
    });

/// The production invoker.
///
/// The only place in the application that names this RPC and touches the
/// Supabase client for it. Note the call site: one function name, two parameter
/// names, and no argument that is not a relationship id or a status token.
VendorRetailerLifecycleInvoker supabaseVendorRetailerLifecycleInvoker(
  SupabaseClient client,
) {
  return ({required String relationshipId, required String status}) =>
      client.rpc<Object?>(
        setVendorRetailerStatusRpc,
        params: <String, Object?>{
          lifecycleRelationshipIdParameter: relationshipId,
          lifecycleStatusParameter: status,
        },
      );
}

/// Performs the Retailer lifecycle write a Vendor Super Admin holding
/// `RETAILERS_MANAGE` is entitled to.
///
/// Thin by design, exactly like its read counterpart: it performs the call and
/// lets exceptions propagate. Turning an exception into a `Failure` is the
/// repository's job and turning a body into a value is the parser's, so each of
/// the three has one reason to change.
///
/// **No table is ever written here.** There is no `insert`, `update`, `upsert` or
/// `delete` against `organizations`, against `vendor_retailers`, or against
/// `audit_logs`. Both tables are SELECT-only for the browser with read-only
/// policies and no `INSERT`/`UPDATE`/`DELETE` privilege of any kind, so a direct
/// write here would not merely be poor layering — it would not work. The two
/// status columns move together, atomically, inside the RPC's own transaction,
/// each with a compare-and-set predicate and a checked row count; that is
/// precisely why this is one call and not two.
///
/// **No automatic retry.** The invoker is called once per write and nothing here
/// re-issues it.
///
/// **No service-role client, and no key of any kind.** The call travels on the
/// caller's own token, which is the only reason the function can derive an
/// identity at all — a service-role connection has no `auth.uid()` and could
/// only ever be refused.
final class VendorRetailerLifecycleRpcDataSource {
  const VendorRetailerLifecycleRpcDataSource({
    required VendorRetailerLifecycleInvoker setStatus,
  }) : _setStatus = setStatus;

  /// Builds the data source against a live client.
  factory VendorRetailerLifecycleRpcDataSource.forClient(
    SupabaseClient client,
  ) {
    return VendorRetailerLifecycleRpcDataSource(
      setStatus: supabaseVendorRetailerLifecycleInvoker(client),
    );
  }

  final VendorRetailerLifecycleInvoker _setStatus;

  /// Returns the raw body — for a `returns table (...)` function, a list of row
  /// objects, which the parser checks is exactly one trustworthy row.
  Future<Object?> setRetailerStatus({
    required String relationshipId,
    required String status,
  }) => _setStatus(relationshipId: relationshipId, status: status);
}
