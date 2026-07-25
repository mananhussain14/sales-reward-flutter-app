import 'package:supabase_flutter/supabase_flutter.dart';

/// The three Vendor Role RPCs, named exactly once each.
const String listVendorRolesRpc = 'list_vendor_roles';
const String getVendorRoleDetailRpc = 'get_vendor_role_detail';
const String listVendorRolePermissionsRpc = 'list_vendor_role_permissions';

/// The **only** parameter any of them accepts.
const String roleIdParameter = 'p_role_id';

/// Invokes `list_vendor_roles()` and returns its raw body.
///
/// ## The signature is the security property
///
/// The RPC takes no arguments at all, and this typedef takes none either. That
/// is not a convenience — it makes an auth user id, profile id, Vendor
/// organization id, tenant id, role id, role code, role status, permission code,
/// permission set, search term, page cursor or organization context
/// **impossible to express** at this boundary. There is no argument to pass, so
/// there is no argument to get wrong, and no future edit can quietly add one
/// without changing this type.
typedef VendorRoleListInvoker = Future<Object?> Function();

/// Invokes `get_vendor_role_detail(uuid)`.
///
/// One `String`, and it is a `roles.id`. No identity travels beside it: the
/// function derives the Vendor from `auth.uid()` via
/// `get_vendor_super_admin_context()` and uses the id only to select which
/// already-authorized catalogue row is read.
///
/// Holding a role id therefore grants nothing. An id that names no role — and an
/// id belonging to some other table entirely — is inert: it matches no row and
/// yields the same zero-row answer.
typedef VendorRoleDetailInvoker = Future<Object?> Function(String roleId);

/// Invokes `list_vendor_role_permissions(uuid)`.
///
/// The same selector as the detail read, deliberately: two operations addressed
/// by one id cannot drift into two address spaces. There is no permission id,
/// permission code or permission set in the signature that could widen this
/// beyond the selected role's own mappings.
typedef VendorRolePermissionsInvoker = Future<Object?> Function(String roleId);

/// The production invokers.
///
/// The only place in the application that names a Vendor Role RPC and touches
/// the Supabase client for it. Note the call sites: a function name, and — twice
/// — a single role id.
VendorRoleListInvoker supabaseVendorRolesInvoker(SupabaseClient client) {
  return () => client.rpc<Object?>(listVendorRolesRpc);
}

VendorRoleDetailInvoker supabaseVendorRoleDetailInvoker(SupabaseClient client) {
  return (String roleId) => client.rpc<Object?>(
    getVendorRoleDetailRpc,
    params: <String, Object?>{roleIdParameter: roleId},
  );
}

VendorRolePermissionsInvoker supabaseVendorRolePermissionsInvoker(
  SupabaseClient client,
) {
  return (String roleId) => client.rpc<Object?>(
    listVendorRolePermissionsRpc,
    params: <String, Object?>{roleIdParameter: roleId},
  );
}

/// Reads the Vendor Role data a Vendor Super Admin is entitled to.
///
/// Thin by design: it performs each call and lets exceptions propagate. Turning
/// an exception into a `Failure` is the repository's job and turning a body into
/// domain objects is the parser's, so each of the three has one reason to
/// change.
///
/// **No table is ever read here.** There is no query against `roles`,
/// `permissions`, `role_permissions`, `member_roles` or `organization_members`,
/// and none against `auth.users` under any spelling. The role→permission join,
/// both counts and the tenant scoping of the member count all happen in SQL
/// inside `SECURITY DEFINER` functions — the web assembles the same screen from
/// three whole-table reads and a TypeScript join, and reassembling that in a
/// second client would be a second definition of "which permissions does this
/// role grant".
final class VendorRoleRpcDataSource {
  const VendorRoleRpcDataSource({
    required VendorRoleListInvoker roles,
    required VendorRoleDetailInvoker detail,
    required VendorRolePermissionsInvoker permissions,
  }) : _roles = roles,
       _detail = detail,
       _permissions = permissions;

  /// Builds the data source against a live client.
  factory VendorRoleRpcDataSource.forClient(SupabaseClient client) {
    return VendorRoleRpcDataSource(
      roles: supabaseVendorRolesInvoker(client),
      detail: supabaseVendorRoleDetailInvoker(client),
      permissions: supabaseVendorRolePermissionsInvoker(client),
    );
  }

  final VendorRoleListInvoker _roles;
  final VendorRoleDetailInvoker _detail;
  final VendorRolePermissionsInvoker _permissions;

  Future<Object?> fetchRoles() => _roles();

  Future<Object?> fetchDetail(String roleId) => _detail(roleId);

  Future<Object?> fetchPermissions(String roleId) => _permissions(roleId);
}
