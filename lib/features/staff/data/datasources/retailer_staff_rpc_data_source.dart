import 'package:supabase_flutter/supabase_flutter.dart';

/// The Retailer staff roster RPC, named exactly once in the application.
const String retailerStaffMembersRpc = 'list_retailer_staff_members';

/// The Retailer staff invitation-history RPC, named exactly once.
const String retailerStaffInvitationsRpc = 'list_retailer_staff_invitations';

/// Invokes `list_retailer_staff_members()`.
///
/// Zero arguments, because the function takes zero arguments. There is no
/// Retailer organization id, membership id, shop id, profile id, auth user id,
/// tenant id, role code, permission code, status filter, search term or page
/// selector to express at this boundary.
///
/// Which membership statuses come back is decided **inside** the function, from
/// the caller's own permissions. There is no flag here that selects between the
/// Owner view and the Manager view, and there could not be one — the parameter
/// list is empty.
typedef RetailerStaffMembersInvoker = Future<Object?> Function();

/// Invokes `list_retailer_staff_invitations()`.
///
/// Zero arguments, on the same terms. In particular there is no invitation id,
/// no state filter and no "include revoked" flag — the function returns the
/// whole history for the resolved Retailer, ordered by the backend.
typedef RetailerStaffInvitationsInvoker = Future<Object?> Function();

/// The production roster invoker.
///
/// **No `params` map is passed, not even an empty one.** An empty map would be
/// harmless today and would be the obvious place for someone to later add "just
/// one" filter; omitting it makes the zero-argument shape visible at the call
/// site rather than implied by an absence of keys.
RetailerStaffMembersInvoker supabaseRetailerStaffMembersInvoker(
  SupabaseClient client,
) {
  return () => client.rpc<Object?>(retailerStaffMembersRpc);
}

/// The production invitation-history invoker. Same rule: a name, and nothing
/// else.
RetailerStaffInvitationsInvoker supabaseRetailerStaffInvitationsInvoker(
  SupabaseClient client,
) {
  return () => client.rpc<Object?>(retailerStaffInvitationsRpc);
}

/// Reads the staff data a Retailer member is entitled to.
///
/// Thin by design: it performs the calls and lets exceptions propagate.
///
/// **No table is ever read here.** There is no query against
/// `organization_members`, `profiles`, `member_roles`, `roles`,
/// `retailer_shop_members`, `retailer_shops`, `retailer_staff_invitations` or
/// `retailer_invitation_shop_assignments` under any spelling. The four-table
/// join, the ACTIVE-role filter, the permission-dependent status predicate, the
/// positionally-aligned shop arrays and the whole invitation `CASE` all happen
/// in SQL — reproducing any of it in Dart would put the definitions into a
/// second client free to drift from the web.
///
/// **No write of any kind.** No invitation is created, sent, resent or revoked
/// here; no membership is activated, deactivated or re-roled; no shop assignment
/// is changed. Neither RPC named above can do any of those things, and the two
/// that can are not named anywhere in this application. Sending an invitation
/// also requires the `send-staff-invitation` Edge Function, which holds the
/// delivery credential — that credential exists only in the function's own
/// environment and appears nowhere in this binary.
final class RetailerStaffRpcDataSource {
  const RetailerStaffRpcDataSource({
    required RetailerStaffMembersInvoker members,
    required RetailerStaffInvitationsInvoker invitations,
  }) : _members = members,
       _invitations = invitations;

  /// Builds the data source against a live client.
  factory RetailerStaffRpcDataSource.forClient(SupabaseClient client) {
    return RetailerStaffRpcDataSource(
      members: supabaseRetailerStaffMembersInvoker(client),
      invitations: supabaseRetailerStaffInvitationsInvoker(client),
    );
  }

  final RetailerStaffMembersInvoker _members;
  final RetailerStaffInvitationsInvoker _invitations;

  /// The roster, in one round trip.
  Future<Object?> fetchMembers() => _members();

  /// The invitation history, in one round trip.
  Future<Object?> fetchInvitations() => _invitations();
}
