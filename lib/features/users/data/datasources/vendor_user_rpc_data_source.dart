import 'package:supabase_flutter/supabase_flutter.dart';

/// The two Vendor User RPCs, named exactly once each.
const String listVendorUsersRpc = 'list_vendor_users';
const String getVendorUserDetailRpc = 'get_vendor_user_detail';

/// The **only** parameter either of them accepts.
const String membershipIdParameter = 'p_membership_id';

/// Invokes `list_vendor_users()` and returns its raw body.
///
/// ## The signature is the security property
///
/// The RPC takes no arguments at all, and this typedef takes none either. That
/// is not a convenience — it makes an auth user id, profile id, Vendor
/// organization id, membership id, role code, permission code, tenant id, email
/// or status **impossible to express** at this boundary. There is no argument to
/// pass, so there is no argument to get wrong, and no future edit can quietly
/// add one without changing this type.
typedef VendorUserListInvoker = Future<Object?> Function();

/// Invokes `get_vendor_user_detail(uuid)`.
///
/// One `String`, and it is an `organization_members.id`. No identity travels
/// beside it: the function derives the Vendor from `auth.uid()` via
/// `get_vendor_super_admin_context()` and matches the row on **both** its own id
/// and that derived Vendor, neither of which this client can name.
///
/// Holding a membership id therefore grants nothing. Another Vendor's id — and a
/// Retailer organization's membership id, which exists but not in this
/// organization — are both inert: they match no row and yield the same zero-row
/// answer an unknown id does.
typedef VendorUserDetailInvoker = Future<Object?> Function(String membershipId);

/// The production invokers.
///
/// The only place in the application that names a Vendor User RPC and touches
/// the Supabase client for it. Note the call sites: a function name, and — once
/// — a single membership id.
VendorUserListInvoker supabaseVendorUsersInvoker(SupabaseClient client) {
  return () => client.rpc<Object?>(listVendorUsersRpc);
}

VendorUserDetailInvoker supabaseVendorUserDetailInvoker(SupabaseClient client) {
  return (String membershipId) => client.rpc<Object?>(
    getVendorUserDetailRpc,
    params: <String, Object?>{membershipIdParameter: membershipId},
  );
}

/// Reads the Vendor user data a Vendor Super Admin is entitled to.
///
/// Thin by design: it performs each call and lets exceptions propagate. Turning
/// an exception into a `Failure` is the repository's job and turning a body into
/// domain objects is the parser's, so each of the three has one reason to
/// change.
///
/// **No table is ever read here.** There is no query against
/// `organization_members`, `profiles`, `member_roles`, `roles`, `permissions`,
/// `role_permissions` or `auth.users`. The four-table join, the ACTIVE-role
/// filter, the name composition and the tenant scoping all happen in SQL inside
/// `SECURITY DEFINER` functions — reassembling them in a second client would be
/// a second place for the tenant scoping and the role filter to be got wrong.
final class VendorUserRpcDataSource {
  const VendorUserRpcDataSource({
    required VendorUserListInvoker users,
    required VendorUserDetailInvoker detail,
  }) : _users = users,
       _detail = detail;

  /// Builds the data source against a live client.
  factory VendorUserRpcDataSource.forClient(SupabaseClient client) {
    return VendorUserRpcDataSource(
      users: supabaseVendorUsersInvoker(client),
      detail: supabaseVendorUserDetailInvoker(client),
    );
  }

  final VendorUserListInvoker _users;
  final VendorUserDetailInvoker _detail;

  Future<Object?> fetchUsers() => _users();

  Future<Object?> fetchDetail(String membershipId) => _detail(membershipId);
}
