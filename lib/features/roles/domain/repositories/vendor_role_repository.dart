import '../../../../core/result/read_result.dart';
import '../entities/vendor_role_detail.dart';
import '../entities/vendor_role_permission.dart';
import '../entities/vendor_role_summary.dart';

/// The three Vendor Role reads, and nothing else.
///
/// One repository for all three deliberately: they share a Vendor derivation, a
/// selector vocabulary and a failure contract, and splitting them would create
/// three places for those to drift. It is also the whole surface — this
/// milestone is **read-only**, so there is no create, edit, delete, activate,
/// deactivate, duplicate, assign-permission, remove-permission or assign-role
/// method here, and no place to add one without changing this interface.
///
/// Those writes have no backend at all, on web or mobile: there is no role write
/// page, Server Action, RPC, or `INSERT`/`UPDATE`/`DELETE` policy anywhere in
/// the product, and `authenticated` holds `SELECT` and nothing more on all four
/// RBAC tables. So this is not "no mobile contract yet" — the whole Roles
/// surface is read-only in the shipped product.
///
/// ## What the signatures make impossible
///
/// [roles] takes **no arguments**. [roleDetail] and [rolePermissions] take
/// exactly one each, and it is a role id. There is no auth user id, profile id,
/// membership id, Vendor organization id, tenant id, role code, role name, role
/// status, permission id, permission code, permission set, module or
/// organization-context parameter anywhere on this interface — not as an
/// optional, not as a named argument with a default. The absence is the point:
/// the Vendor is derived from `auth.uid()` in SQL by
/// `get_vendor_super_admin_context()`, and the role id **selects** which
/// already-authorized catalogue row is read without ever deciding *whether*
/// anything may be read. Holding one grants nothing.
///
/// ## Why the detail read exists at all, given it returns a list row
///
/// Three reasons, and the third is the one this client depends on: a refresh
/// that costs one row instead of the catalogue; a deep link openable without the
/// list; and an **authoritative answer to "is this id addressable by me"**.
/// [rolePermissions] answers an empty list for a genuinely permission-less role
/// *and* for an id that names no role at all, indistinguishably. Zero rows from
/// [roleDetail] is what tells those apart — which is why a caller loads the
/// detail first and issues the permission read only after a row comes back.
abstract interface class VendorRoleRepository {
  /// `public.list_vendor_roles()` — zero arguments.
  ///
  /// Returns the whole shared catalogue in the backend's `role_name, role_id`
  /// order. Not a Vendor-scoped subset: there is none to return.
  ///
  /// An empty list is a legitimate answer and is never produced from a failure.
  /// In practice it is unreachable while the caller is authorized — a caller
  /// cannot hold `VENDOR_SUPER_ADMIN` unless that role is itself a row of this
  /// catalogue — so it is a defensive floor rather than an expected state.
  ///
  /// A refusal is `42501` and arrives as a [ReadFailure], because a denial and
  /// an empty catalogue are opposite claims.
  Future<ReadResult<List<VendorRoleSummary>>> roles();

  /// `public.get_vendor_role_detail(p_role_id)`.
  ///
  /// Returns `null` inside a success for zero rows — the backend's answer for an
  /// unknown uuid, a uuid belonging to some other table, and `null` alike, and
  /// this client adds a malformed id to that same set rather than inventing a
  /// fourth outcome.
  ///
  /// A zero-row answer is a **success carrying null**, never a failure: the
  /// backend answered, and reporting it as an outage would offer a retry that
  /// cannot change anything.
  ///
  /// There is no "another Vendor's role" to refuse here. The catalogue is
  /// global, so every role readable by one authorized Vendor is readable by all
  /// of them; only [VendorRoleSummary.assignedMemberCount] differs, and it is
  /// recomputed against the calling Vendor.
  Future<ReadResult<VendorRoleDetail?>> roleDetail(String roleId);

  /// `public.list_vendor_role_permissions(p_role_id)`.
  ///
  /// Every permission mapped to the selected role, in the backend's
  /// `permission_name, permission id` order. The id is ordered on and never
  /// returned.
  ///
  /// An empty list means the role grants nothing — **provided** [roleDetail]
  /// has already confirmed the id names a role. Called for an id that does not,
  /// it returns the same empty list, which is why it is never called first.
  ///
  /// The result is a listing of what is *mapped*. It is never proof that the
  /// current caller may perform those actions, and nothing may compute access
  /// from it.
  Future<ReadResult<List<VendorRolePermission>>> rolePermissions(String roleId);
}
