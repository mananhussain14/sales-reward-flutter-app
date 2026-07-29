import 'package:supabase_flutter/supabase_flutter.dart';

/// The one Retailer staff lifecycle write RPC, named exactly once.
///
/// Deployed by `20260810090000_retailer_staff_membership_lifecycle.sql`, granted
/// to `authenticated` and to nothing else — not the anonymous role, not PUBLIC,
/// and **not the privileged service role**, which is revoked deliberately: the
/// function's entire authority is `auth.uid()`, which a privileged connection
/// does not have, so the write would have no actor to attribute its audit row to.
///
/// This client calls the **same** deployed function the Next.js portal calls.
/// There is no mobile twin and no second definition of "deactivate a staff
/// member", so the two clients cannot disagree about the Owner exclusion, the
/// multi-role refusal, or what survives a deactivation.
const String setRetailerStaffMembershipStatusRpc =
    'set_retailer_staff_membership_status';

/// The **two** parameter names this function accepts, and there is no third.
///
/// Named as constants so the whole payload vocabulary of this write is legible in
/// one place, and so a boundary test can assert the set exactly. Note what is not
/// here: no Retailer organization, tenant, auth-user, profile, membership-role,
/// actor, role, permission, current-status, audit-action or timestamp parameter —
/// the function declares none, so none can be sent.
const String staffLifecycleMembershipIdParameter = 'p_membership_id';
const String staffLifecycleStatusParameter = 'p_status';

/// Invokes `set_retailer_staff_membership_status(uuid, text)`.
///
/// Two values: which membership, and which of the two statuses. The status
/// arrives as a `String` because that is the RPC's parameter type, but the only
/// source of one is `RetailerStaffLifecycleStatus.code`, whose two members are
/// the only tokens the function's case-sensitive
/// `in ('ACTIVE', 'DEACTIVATED')` test accepts.
///
/// The signature is the security property: with exactly two parameters there is
/// no third to get wrong, and a future edit that adds one has to change this
/// type.
typedef RetailerStaffLifecycleInvoker =
    Future<Object?> Function({
      required String membershipId,
      required String status,
    });

/// The production invoker.
///
/// The only place in the application that names this RPC and touches the
/// Supabase client for it. Note the call site: one function name, two parameter
/// names, and no argument that is not a membership id or a status token.
RetailerStaffLifecycleInvoker supabaseRetailerStaffLifecycleInvoker(
  SupabaseClient client,
) {
  return ({required String membershipId, required String status}) =>
      client.rpc<Object?>(
        setRetailerStaffMembershipStatusRpc,
        params: <String, Object?>{
          staffLifecycleMembershipIdParameter: membershipId,
          staffLifecycleStatusParameter: status,
        },
      );
}

/// Performs the staff lifecycle write a Retailer Owner holding
/// `RETAILER_STAFF_MANAGE` is entitled to.
///
/// Thin by design, exactly like its read counterparts: it performs the call and
/// lets exceptions propagate. Turning an exception into a problem is the
/// repository's job and turning a body into a value is the parser's, so each of
/// the three has one reason to change.
///
/// **No table is ever written here.** There is no `insert`, `update`, `upsert` or
/// `delete` against `organization_members`, against `member_roles`, against
/// `profiles`, or against `audit_logs`. `organization_members` is SELECT-only for
/// the browser with a single read policy and no `INSERT`/`UPDATE`/`DELETE`
/// privilege of any kind, so a direct write here would not merely be poor
/// layering — it would not work. The status column, `deactivated_at` and the
/// audit row all move inside the RPC's own transaction, under a `FOR UPDATE`
/// lock this client could not take.
///
/// **No automatic retry.** The invoker is called once per write and nothing here
/// re-issues it.
///
/// **No service-role client, and no key of any kind.** The call travels on the
/// caller's own token, which is the only reason the function can derive an
/// identity at all.
final class RetailerStaffLifecycleRpcDataSource {
  const RetailerStaffLifecycleRpcDataSource({
    required RetailerStaffLifecycleInvoker setStatus,
  }) : _setStatus = setStatus;

  /// Builds the data source against a live client.
  factory RetailerStaffLifecycleRpcDataSource.forClient(SupabaseClient client) {
    return RetailerStaffLifecycleRpcDataSource(
      setStatus: supabaseRetailerStaffLifecycleInvoker(client),
    );
  }

  final RetailerStaffLifecycleInvoker _setStatus;

  /// Returns the raw body — for a `returns table (...)` function, a list of row
  /// objects, which the parser checks is exactly one trustworthy row.
  Future<Object?> setMembershipStatus({
    required String membershipId,
    required String status,
  }) => _setStatus(membershipId: membershipId, status: status);
}
