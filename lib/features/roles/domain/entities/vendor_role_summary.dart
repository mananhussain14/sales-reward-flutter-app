import 'package:equatable/equatable.dart';

import 'vendor_role_status.dart';

/// One row of `public.list_vendor_roles()`.
///
/// Every field is a column the deployed function actually returns, and there is
/// no field it does not return. In particular there is **no** role code, no
/// permission row, no permission code, no permission module, no organization id,
/// no role scope, no role kind, no `is_system` / `is_custom` / `is_editable`
/// flag, and no `updated_at` — because none of those is returned, and every one
/// of them is refused on purpose.
///
/// ## The catalogue this row belongs to is GLOBAL
///
/// `public.roles`, `public.permissions` and `public.role_permissions` carry no
/// `organization_id`. They are one catalogue of role and permission
/// *definitions* shared by every organization on the platform, so two Vendors
/// read byte-identical role rows — including the three Retailer role
/// definitions, exactly as the web `/roles` page shows them today.
///
/// Nothing in this entity may be used to narrow that catalogue. There is no
/// scope or kind property to filter on, and inferring one from the role **name**
/// would be inventing a taxonomy the schema does not have and immediately
/// disagreeing with the web.
///
/// ## [assignedMemberCount] is the one tenant-scoped value
///
/// It counts memberships of the **calling** Vendor Super Admin's own Vendor that
/// hold this role, and of no other organization — `m.organization_id` is
/// compared against a Vendor derived from `auth.uid()` in SQL and never against
/// a parameter. Vendor A and Vendor B open the same role and read the same name,
/// description and status with different counts. A Retailer role reads `0` for a
/// Vendor, which is the true answer rather than a hidden row.
///
/// It is an **assignment** count, not a headcount of active staff: the backend
/// filters neither membership status nor profile status nor role status, so a
/// retired definition still held by four people reports `4`.
final class VendorRoleSummary extends Equatable {
  const VendorRoleSummary({
    required this.roleId,
    required this.roleName,
    required this.description,
    required this.status,
    required this.createdAt,
    required this.permissionCount,
    required this.assignedMemberCount,
  });

  /// `roles.id` — the selector both companion reads take, and the segment the
  /// detail route carries.
  ///
  /// The id and never the code. `roles.code` is `UNIQUE` and would address a
  /// role just as precisely, and that is exactly why the backend refuses it: the
  /// codes are the literals the RLS policies and the authorization helpers match
  /// on, and putting one in a client's hands would invite the client to reason
  /// about authorization. This uuid is opaque and means nothing anywhere else.
  final String roleId;

  /// The display name — `Vendor Super Admin`, not `VENDOR_SUPER_ADMIN`. Never
  /// null, never blank, and never the internal code, which is not returned.
  final String roleName;

  /// The stored description, or **null** when the role has none.
  ///
  /// Null is a real answer and is never replaced by a fabricated sentence, by
  /// the role name, or by a phrase derived from either.
  final String? description;

  /// The stored lifecycle state of the definition.
  ///
  /// Returned unfiltered by the backend and rendered unfiltered here: a
  /// catalogue that hid `INACTIVE` definitions would misrepresent what is
  /// stored, and the definition is the subject of this screen.
  final VendorRoleStatus status;

  /// When the role definition was created. UTC.
  ///
  /// `updated_at` is deliberately not part of the contract: the backend's role
  /// seed is an upsert that rewrites it on every run, so it records when the
  /// seed last ran rather than when the role last changed.
  final DateTime createdAt;

  /// How many permissions are **mapped** to this role.
  ///
  /// Never null; `0` for a role with no mappings, which is a real state — two
  /// seeded roles are exactly that. Computed in SQL by joining
  /// `role_permissions` to `permissions`, so it is by construction the number of
  /// rows `list_vendor_role_permissions()` returns for the same role.
  ///
  /// **Mapped, not effective.** For a role whose [status] is not
  /// [VendorRoleStatus.active] these permissions grant nothing; the count is
  /// still the honest number of mappings and is never adjusted for status.
  final int permissionCount;

  /// How many memberships **in the caller's own Vendor** hold this role.
  ///
  /// Never null; `0` for a role nobody in this Vendor holds. See the class
  /// comment for the exact semantics.
  final int assignedMemberCount;

  /// Whether this role grants no permission at all today.
  bool get hasNoPermissions => permissionCount == 0;

  /// Whether nobody in the caller's Vendor holds this role.
  bool get hasNoAssignedMembers => assignedMemberCount == 0;

  @override
  List<Object?> get props => <Object?>[
    roleId,
    roleName,
    description,
    status,
    createdAt,
    permissionCount,
    assignedMemberCount,
  ];
}
