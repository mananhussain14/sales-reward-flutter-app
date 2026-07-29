import 'package:supabase_flutter/supabase_flutter.dart';

/// The permission-check helper. One call, one name, greppable.
///
/// `public.has_organization_permission(uuid, text) -> boolean` is the same
/// helper every RLS policy in this deployment already asks the question with, so
/// this probe adds no new authorization surface and no new definition of "may
/// this caller manage Retailers".
const String hasOrganizationPermissionRpc = 'has_organization_permission';

/// The **two** parameter names the helper accepts, and there is no third.
const String targetOrganizationIdParameter = 'target_organization_id';
const String targetPermissionCodeParameter = 'target_permission_code';

/// The permission this milestone introduced, mapped to `VENDOR_SUPER_ADMIN`
/// alone.
///
/// Stated here because a permission **code** is what this probe asks *about* —
/// it is not an authorization decision made in Dart. The decision is the
/// database's, and the `role_permissions` mapping is the authority: if a future
/// migration grants `RETAILERS_MANAGE` to another Vendor-side role, that role
/// gains the operation without this file being edited.
///
/// This is deliberately the **only** permission code named anywhere in this
/// application, and it is named for one purpose: to be sent as an argument. It
/// is never compared against anything, and no role code appears beside it.
const String retailersManagePermissionCode = 'RETAILERS_MANAGE';

/// Invokes `has_organization_permission(uuid, text)`.
///
/// ## Why this probe exists at all
///
/// `get_my_portal_context()` proves the caller holds the ACTIVE
/// `VENDOR_SUPER_ADMIN` role in an ACTIVE `VENDOR` organization, and returns
/// **no** Vendor permission detail — its `capabilities` block covers the
/// Retailer portal only. `RETAILERS_MANAGE` is mapped to that role today, but
/// the *mapping* is the authority and it can change without this application
/// being rebuilt. A screen that inferred the capability from the portal kind
/// would silently keep offering a control the database refuses on the day the
/// mapping is revoked.
///
/// The Retailer-side capability hints solve the same problem by having the
/// backend call each operation's own resolver. There is no read RPC gated on
/// `RETAILERS_MANAGE` — the write is its only consumer — so this asks the
/// question directly.
///
/// ## The organization id is server-derived, and cannot be pointed elsewhere
///
/// The value handed to this invoker comes from the Vendor block of the resolved
/// `PortalContext`, which the backend produced from `auth.uid()`. It never comes
/// from a route parameter, a form field, local storage, a Retailer record or any
/// user-editable state.
///
/// Even so, the helper is `SECURITY DEFINER` and hard-filtered to `auth.uid()`:
/// it requires an ACTIVE profile, an ACTIVE membership **of the organization
/// asked about**, an ACTIVE organization and an ACTIVE role carrying the
/// permission. A substituted id could therefore only ever answer `false`, which
/// hides the control rather than revealing anything.
typedef VendorRetailerCapabilityInvoker =
    Future<Object?> Function(String organizationId);

/// The production invoker.
///
/// The only place in the application that names `has_organization_permission`
/// or `RETAILERS_MANAGE` in executable code, and the only place that touches the
/// Supabase client for either.
VendorRetailerCapabilityInvoker supabaseVendorRetailerCapabilityInvoker(
  SupabaseClient client,
) {
  return (String organizationId) => client.rpc<Object?>(
    hasOrganizationPermissionRpc,
    params: <String, Object?>{
      targetOrganizationIdParameter: organizationId,
      targetPermissionCodeParameter: retailersManagePermissionCode,
    },
  );
}

/// Asks the database whether this caller may change a Retailer's lifecycle.
///
/// Thin by design: it performs the call and lets exceptions propagate.
/// Classifying the answer is the repository's job.
///
/// **No table is read here.** There is no `.from('role_permissions')`, no
/// `.from('member_roles')` and no `.from('roles')`. Reassembling the permission
/// join in a second client would be a second definition of the authorization
/// rule, free to drift from the one every RLS policy already uses.
///
/// **No service-role client, and no key of any kind.** The call travels on the
/// caller's own token — which is the only reason the helper can filter on
/// `auth.uid()` at all.
final class VendorRetailerCapabilityRpcDataSource {
  const VendorRetailerCapabilityRpcDataSource({
    required VendorRetailerCapabilityInvoker probe,
  }) : _probe = probe;

  /// Builds the data source against a live client.
  factory VendorRetailerCapabilityRpcDataSource.forClient(
    SupabaseClient client,
  ) {
    return VendorRetailerCapabilityRpcDataSource(
      probe: supabaseVendorRetailerCapabilityInvoker(client),
    );
  }

  final VendorRetailerCapabilityInvoker _probe;

  /// Returns the raw body — a bare JSON boolean for a `returns boolean`
  /// function, which the repository checks is a genuine `bool`.
  Future<Object?> hasRetailersManage(String organizationId) =>
      _probe(organizationId);
}
