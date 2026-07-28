import 'package:supabase_flutter/supabase_flutter.dart';

/// The post-acceptance shop-assignment write RPC, named exactly once in the
/// application.
///
/// Not a mobile twin of anything: the Next.js portal's Manage Shops dialog calls
/// this same deployed function, so "replace a staff member's shops" — the
/// retirement rule, the same-Retailer check, the ACTIVE-shop validation, the
/// zero-shop refusal and the audit row — exists in exactly one place and the two
/// clients cannot hold different opinions about it.
const String setRetailerStaffShopAssignmentsRpc =
    'set_retailer_staff_shop_assignments';

/// The **two** parameter names this function accepts, and there is no third.
///
/// Named as constants so the whole payload vocabulary of this feature is legible
/// in one place, and so a boundary test can assert the set exactly. Note what is
/// not here and has no constant to be spelled with: no organization, tenant,
/// Retailer, auth-user, profile, actor or member-role parameter; no invitation
/// id; no role code, permission code or status; no current-assignment list and
/// no separate add/remove arrays; no audit metadata, timestamp, token or
/// idempotency key.
const String staffShopAssignmentMembershipParameter = 'p_membership_id';
const String staffShopAssignmentShopIdsParameter = 'p_shop_ids';

/// Invokes `set_retailer_staff_shop_assignments(uuid, uuid[])`.
///
/// Two arguments, and both are **addresses within one derived tenant**. No
/// identity travels beside them: the Retailer is derived from `auth.uid()`
/// inside the function, the membership is matched against *that* Retailer, and
/// every shop is validated against it too. Holding either id therefore grants
/// nothing, and another Retailer's id is refused byte-identically to one that
/// names nothing.
///
/// The typedef takes exactly these two and nothing else, which is the security
/// property enforced by the type system: a widened payload is an edit to this
/// line.
typedef RetailerStaffShopAssignmentInvoker =
    Future<Object?> Function({
      required String membershipId,
      required List<String> shopIds,
    });

/// The production invoker.
///
/// The only place in the application that names this RPC and touches the
/// Supabase client for it. Note the call site: one function name, two parameter
/// names, and no argument that is not one of the two addresses.
///
/// It travels on the caller's own session — which is the only reason the
/// function can derive an identity at all. A service-role connection has no
/// `auth.uid()` and could only ever be refused, and **no service-role key exists
/// anywhere in this application**.
RetailerStaffShopAssignmentInvoker supabaseRetailerStaffShopAssignmentInvoker(
  SupabaseClient client,
) {
  return ({required String membershipId, required List<String> shopIds}) =>
      client.rpc<Object?>(
        setRetailerStaffShopAssignmentsRpc,
        params: <String, Object?>{
          staffShopAssignmentMembershipParameter: membershipId,
          staffShopAssignmentShopIdsParameter: shopIds,
        },
      );
}

/// Performs the one shop-assignment write a Retailer Owner holding
/// `RETAILER_STAFF_SHOP_ASSIGN` is entitled to.
///
/// Thin by design, exactly like its read counterparts: it performs the call and
/// lets exceptions propagate. Turning an exception into a problem is the
/// repository's job and turning a body into domain values is the parser's, so
/// each has one reason to change.
///
/// **No table is ever read or written here.** There is no `insert`, `update`,
/// `upsert` or `delete` against `retailer_shop_members`, `retailer_shops`,
/// `organization_members`, `member_roles`, `profiles` or `audit_logs` under any
/// spelling, and no `select` either. `retailer_shops` carries one vendor-scoped
/// SELECT policy that returns zero rows to a Retailer Owner, so a client that
/// reproduced any of this would not merely be poorly layered — it would render
/// an empty estate and look entirely plausible doing it. The retirement, the
/// insertion, the same-Retailer trigger and the audit row all happen in SQL,
/// inside one transaction.
///
/// **No deletion, ever.** The function retires an assignment by stamping
/// `removed_at`; the row survives, which is what keeps the history readable and
/// what lets a re-added shop be told from one that was never removed.
///
/// **One write, and only this one.** There is no activation, deactivation, role
/// change, invitation accept, revoke or resend, and no shop create, edit or
/// status change here — no method, and no RPC name.
final class RetailerStaffShopAssignmentRpcDataSource {
  const RetailerStaffShopAssignmentRpcDataSource({
    required RetailerStaffShopAssignmentInvoker setAssignments,
  }) : _setAssignments = setAssignments;

  /// Builds the data source against a live client.
  factory RetailerStaffShopAssignmentRpcDataSource.forClient(
    SupabaseClient client,
  ) {
    return RetailerStaffShopAssignmentRpcDataSource(
      setAssignments: supabaseRetailerStaffShopAssignmentInvoker(client),
    );
  }

  final RetailerStaffShopAssignmentInvoker _setAssignments;

  /// One replacement, in one round trip. Never called twice for one submission.
  ///
  /// Returns the raw body, which for this set-returning function is a JSON array
  /// of exactly one object.
  Future<Object?> setShopAssignments({
    required String membershipId,
    required List<String> shopIds,
  }) => _setAssignments(membershipId: membershipId, shopIds: shopIds);
}
