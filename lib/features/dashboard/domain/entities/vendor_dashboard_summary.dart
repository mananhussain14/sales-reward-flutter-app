import 'package:equatable/equatable.dart';

/// The four counts `public.get_vendor_admin_dashboard_summary()` returns, as one
/// snapshot.
///
/// ## One snapshot, not four fields
///
/// The backend answers all four in a **single statement**, so the four numbers
/// describe one instant. They are held together here — and replaced together by
/// the cubit — because updating one of them from a later read would produce a
/// screen whose figures came from two different moments while claiming to be one
/// overview.
///
/// ## Two of these are NOT this Vendor's metrics
///
/// This is the most important fact about the type, and it is why the two
/// catalogue fields keep the backend's own `catalog` naming rather than being
/// shortened to `roleCount` and `permissionCount`:
///
/// | Field | Scope |
/// | --- | --- |
/// | [activeMemberCount] | **Vendor** — this organization's ACTIVE memberships |
/// | [catalogActiveRoleCount] | **Global** — deployment-wide role definitions |
/// | [catalogPermissionCount] | **Global** — deployment-wide permission definitions |
/// | [auditEventCount] | **Vendor** — this organization's all-time recorded events |
///
/// `public.roles` and `public.permissions` carry no `organization_id` at all, so
/// the two catalogue counts are **identical for every authorized Vendor**. They
/// leak nothing — a count of definitions written by migrations says nothing about
/// any tenant's data — but a screen that labelled either of them "your roles"
/// would be stating something false. The presentation layer is required to say so
/// in words rather than in colour.
///
/// ## Every count is a real count
///
/// All four are `bigint` and `NOT NULL` in the contract, and `count(*)` is
/// non-negative by construction. So there is no "unavailable" figure to model
/// here and no nullable field: a failure is a [ReadFailure], never a null count
/// and never a zero. `0` means **none**, and it is a reachable, honest answer for
/// both Vendor-scoped fields.
final class VendorDashboardSummary extends Equatable {
  const VendorDashboardSummary({
    required this.activeMemberCount,
    required this.catalogActiveRoleCount,
    required this.catalogPermissionCount,
    required this.auditEventCount,
  });

  /// ACTIVE memberships of the caller's Vendor organization.
  ///
  /// Counts `organization_members` rows whose `status` is exactly `ACTIVE`, and
  /// **does not join profiles** — a suspended person holding an ACTIVE membership
  /// is counted, exactly as the web card counts them. One membership counts once
  /// whether it carries no role, one role or several, because the table is
  /// `UNIQUE (organization_id, user_id)`.
  ///
  /// INVITED, SUSPENDED and DEACTIVATED memberships are excluded, as are every
  /// other organization's memberships.
  final int activeMemberCount;

  /// ACTIVE rows in `public.roles` — **deployment-wide**.
  ///
  /// Role *definitions*, not assignments: it does not move when a role is given
  /// to or taken from a member, and it is the same number for every authorized
  /// Vendor. `roles.status` permits exactly `ACTIVE` and `INACTIVE`, so this is
  /// "every role definition that is not retired".
  final int catalogActiveRoleCount;

  /// Every row in `public.permissions` — **deployment-wide**.
  ///
  /// The table has no status column, so there is no active/inactive distinction
  /// to make and the whole catalogue is counted. Permission *definitions*, not
  /// grants: `role_permissions` is not read, and this is not the caller's own
  /// permission set.
  final int catalogPermissionCount;

  /// Every `audit_logs` row filed against the caller's Vendor organization.
  ///
  /// **All-time.** There is no window, no date range and no action, entity or
  /// actor filter — the product defines no "today", "this week" or "last 30
  /// days", so none is applied and none may be implied by a label. Rows with a
  /// null organization and every other Vendor's rows are excluded; rows whose
  /// actor was later deleted still count.
  final int auditEventCount;

  @override
  List<Object?> get props => <Object?>[
    activeMemberCount,
    catalogActiveRoleCount,
    catalogPermissionCount,
    auditEventCount,
  ];
}
