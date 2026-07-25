import 'dart:async';

import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/core/result/read_result.dart';
import 'package:sale_reward/features/roles/domain/entities/vendor_role_detail.dart';
import 'package:sale_reward/features/roles/domain/entities/vendor_role_permission.dart';
import 'package:sale_reward/features/roles/domain/entities/vendor_role_status.dart';
import 'package:sale_reward/features/roles/domain/entities/vendor_role_summary.dart';
import 'package:sale_reward/features/roles/domain/repositories/vendor_role_repository.dart';

/// A hand-written [VendorRoleRepository] fake.
///
/// Hand-written rather than mocked because these tests care about *what was
/// sent* and *in what order* as much as what came back: [requestedDetailIds] and
/// [requestedPermissionIds] are how a test proves that one role id — and nothing
/// beside it — ever leaves the client, and that the permission read is never
/// issued for a role the detail read could not return.
class FakeVendorRoleRepository implements VendorRoleRepository {
  ReadResult<List<VendorRoleSummary>> rolesResult =
      ReadSuccess<List<VendorRoleSummary>>(catalogueSummaries);

  /// When set, every detail read answers this whatever id was asked for — how a
  /// test scripts a failure or a blanket "not addressable".
  ReadResult<VendorRoleDetail?>? detailResult;

  /// Otherwise the fake answers the way the backend does: an id that names a
  /// catalogue role returns its row, and **every** other id — unknown, from
  /// another table, or malformed — returns zero rows, indistinguishably.
  Map<String, VendorRoleDetail> knownDetails = <String, VendorRoleDetail>{
    superAdminRoleUuid: superAdminSummary,
    claimReviewerRoleUuid: claimReviewerSummary,
    retailerOwnerRoleUuid: retailerOwnerSummary,
    legacyRoleUuid: legacySummary,
  };

  /// When set, every permission read answers this.
  ReadResult<List<VendorRolePermission>>? permissionsResult;

  /// Otherwise: the mappings for the requested role, or an empty list — which is
  /// also what an id naming no role produces.
  Map<String, List<VendorRolePermission>> knownPermissions =
      <String, List<VendorRolePermission>>{
        superAdminRoleUuid: superAdminPermissions,
        legacyRoleUuid: legacyPermissions,
      };

  int rolesCallCount = 0;
  final List<String> requestedDetailIds = <String>[];
  final List<String> requestedPermissionIds = <String>[];

  int get detailCallCount => requestedDetailIds.length;
  int get permissionsCallCount => requestedPermissionIds.length;

  /// The order the two companion reads were issued in, so a test can assert the
  /// sequence rather than only the counts.
  final List<String> callLog = <String>[];

  /// When true, every [roles] call stays pending until [completeRoles] is
  /// called — so "a second refresh while one is in flight" is deterministic
  /// rather than a sleep-and-hope.
  bool manualRoles = false;
  final List<Completer<ReadResult<List<VendorRoleSummary>>>> _pendingRoles =
      <Completer<ReadResult<List<VendorRoleSummary>>>>[];

  int get pendingRoleCount => _pendingRoles.length;

  void completeRoles([ReadResult<List<VendorRoleSummary>>? override]) {
    _pendingRoles.removeAt(0).complete(override ?? rolesResult);
  }

  /// The same control for the detail read.
  bool manualDetail = false;
  final List<Completer<ReadResult<VendorRoleDetail?>>> _pendingDetail =
      <Completer<ReadResult<VendorRoleDetail?>>>[];

  int get pendingDetailCount => _pendingDetail.length;

  void completeDetail([ReadResult<VendorRoleDetail?>? override]) =>
      completeDetailAt(0, override);

  /// Completes a pending detail read **out of order**, so a test can make an
  /// *older* request answer after a newer one — the stale-response race the
  /// request token exists to close. [index] is into the pending queue, oldest
  /// first.
  void completeDetailAt(int index, [ReadResult<VendorRoleDetail?>? override]) {
    final Completer<ReadResult<VendorRoleDetail?>> completer = _pendingDetail
        .removeAt(index);
    completer.complete(override ?? _detailFor(requestedDetailIds[index]));
  }

  /// And for the permission companion.
  bool manualPermissions = false;
  final List<Completer<ReadResult<List<VendorRolePermission>>>>
  _pendingPermissions = <Completer<ReadResult<List<VendorRolePermission>>>>[];

  int get pendingPermissionCount => _pendingPermissions.length;

  void completePermissions([ReadResult<List<VendorRolePermission>>? override]) {
    _pendingPermissions
        .removeAt(0)
        .complete(override ?? _permissionsFor(requestedPermissionIds.last));
  }

  @override
  Future<ReadResult<List<VendorRoleSummary>>> roles() {
    rolesCallCount++;
    callLog.add('roles');
    if (manualRoles) {
      final Completer<ReadResult<List<VendorRoleSummary>>> completer =
          Completer<ReadResult<List<VendorRoleSummary>>>();
      _pendingRoles.add(completer);
      return completer.future;
    }
    return Future<ReadResult<List<VendorRoleSummary>>>.value(rolesResult);
  }

  @override
  Future<ReadResult<VendorRoleDetail?>> roleDetail(String roleId) {
    requestedDetailIds.add(roleId);
    callLog.add('detail');
    if (manualDetail) {
      final Completer<ReadResult<VendorRoleDetail?>> completer =
          Completer<ReadResult<VendorRoleDetail?>>();
      _pendingDetail.add(completer);
      return completer.future;
    }
    return Future<ReadResult<VendorRoleDetail?>>.value(_detailFor(roleId));
  }

  @override
  Future<ReadResult<List<VendorRolePermission>>> rolePermissions(
    String roleId,
  ) {
    requestedPermissionIds.add(roleId);
    callLog.add('permissions');
    if (manualPermissions) {
      final Completer<ReadResult<List<VendorRolePermission>>> completer =
          Completer<ReadResult<List<VendorRolePermission>>>();
      _pendingPermissions.add(completer);
      return completer.future;
    }
    return Future<ReadResult<List<VendorRolePermission>>>.value(
      _permissionsFor(roleId),
    );
  }

  ReadResult<VendorRoleDetail?> _detailFor(String roleId) =>
      detailResult ?? ReadSuccess<VendorRoleDetail?>(knownDetails[roleId]);

  ReadResult<List<VendorRolePermission>> _permissionsFor(String roleId) =>
      permissionsResult ??
      ReadSuccess<List<VendorRolePermission>>(
        knownPermissions[roleId] ?? const <VendorRolePermission>[],
      );
}

// ---------------------------------------------------------------------------
// Fixtures
//
// Invented role names and invented ids. Nothing here is a real identifier from
// any environment. The shape follows the deployed catalogue: several ACTIVE
// definitions including a Retailer one, and one INACTIVE definition that still
// has permissions mapped to it and members holding it — the case the whole
// mapped-versus-effective distinction exists for.
// ---------------------------------------------------------------------------

const String superAdminRoleUuid = '1a2b3c4d-5e6f-4071-8293-a4b5c6d7e8f9';
const String claimReviewerRoleUuid = '2b3c4d5e-6f70-4182-93a4-b5c6d7e8f9a0';
const String retailerOwnerRoleUuid = '3c4d5e6f-7081-4293-a4b5-c6d7e8f9a0b1';
const String legacyRoleUuid = '4d5e6f70-8192-43a4-b5c6-d7e8f9a0b1c2';

/// A well-formed id that names no role this caller can read. Well formed on
/// purpose: the point is that a *valid-looking* id is inert. It stands in
/// equally for an unknown role and for an id belonging to some other table —
/// the backend answers zero rows for both, indistinguishably.
const String unknownRoleUuid = '5e6f7081-92a3-44b5-c6d7-e8f9a0b1c2d3';

final DateTime superAdminCreatedAt = DateTime.utc(2026, 1, 5, 8, 0);
final DateTime claimReviewerCreatedAt = DateTime.utc(2026, 2, 11, 9, 30);
final DateTime retailerOwnerCreatedAt = DateTime.utc(2026, 3, 3, 12, 15);
final DateTime legacyCreatedAt = DateTime.utc(2026, 4, 21, 7, 45);

/// An active definition with permissions mapped and members holding it here.
final VendorRoleSummary superAdminSummary = VendorRoleSummary(
  roleId: superAdminRoleUuid,
  roleName: 'Vendor Super Admin',
  description: 'Full administrative control of a Vendor organization.',
  status: VendorRoleStatus.active,
  createdAt: superAdminCreatedAt,
  permissionCount: 3,
  assignedMemberCount: 2,
);

/// Active, **no description**, **no permissions**, **nobody holding it** — three
/// nullable/zero cases that must render honestly rather than be filled in.
final VendorRoleSummary claimReviewerSummary = VendorRoleSummary(
  roleId: claimReviewerRoleUuid,
  roleName: 'Claim Reviewer',
  description: null,
  status: VendorRoleStatus.active,
  createdAt: claimReviewerCreatedAt,
  permissionCount: 0,
  assignedMemberCount: 0,
);

/// A **Retailer** role definition, present in a Vendor's catalogue because the
/// catalogue is global. It must be listed, and never hidden or relabelled.
final VendorRoleSummary retailerOwnerSummary = VendorRoleSummary(
  roleId: retailerOwnerRoleUuid,
  roleName: 'Retailer Owner',
  description: 'Owns a Retailer organization and its shops.',
  status: VendorRoleStatus.active,
  createdAt: retailerOwnerCreatedAt,
  permissionCount: 2,
  assignedMemberCount: 0,
);

/// **Inactive, with permissions still mapped and members still holding it.** The
/// permissions are listed and counted; they grant nothing.
final VendorRoleSummary legacySummary = VendorRoleSummary(
  roleId: legacyRoleUuid,
  roleName: 'Legacy Auditor',
  description: 'Retired definition kept for historical assignments.',
  status: VendorRoleStatus.inactive,
  createdAt: legacyCreatedAt,
  permissionCount: 2,
  assignedMemberCount: 1,
);

/// The catalogue in the backend's `role_name, role_id` order.
final List<VendorRoleSummary> catalogueSummaries = <VendorRoleSummary>[
  claimReviewerSummary,
  legacySummary,
  retailerOwnerSummary,
  superAdminSummary,
];

/// Mapped permissions, in the backend's `permission_name` order. The third has
/// **no description**, which must render as a phrase rather than a blank.
final List<VendorRolePermission> superAdminPermissions =
    const <VendorRolePermission>[
      VendorRolePermission(
        name: 'Manage retailers',
        description: 'Create and maintain Retailer relationships.',
      ),
      VendorRolePermission(
        name: 'Read organization members',
        description: 'See everyone with a membership in the organization.',
      ),
      VendorRolePermission(name: 'Read roles', description: null),
    ];

/// The inactive role's mappings — still returned, still counted.
final List<VendorRolePermission> legacyPermissions =
    const <VendorRolePermission>[
      VendorRolePermission(
        name: 'Read audit log',
        description: 'See recorded administrative events.',
      ),
      VendorRolePermission(
        name: 'Read reports',
        description: 'See summary reporting.',
      ),
    ];

/// A `list_vendor_roles()` body, as PostgREST returns it.
List<Map<String, Object?>> roleRows() => <Map<String, Object?>>[
  roleRow(
    roleId: claimReviewerRoleUuid,
    roleName: 'Claim Reviewer',
    description: null,
    createdAt: '2026-02-11T09:30:00+00:00',
    permissionCount: 0,
    assignedMemberCount: 0,
  ),
  roleRow(),
];

Map<String, Object?> roleRow({
  Object? roleId = superAdminRoleUuid,
  Object? roleName = 'Vendor Super Admin',
  Object? description = 'Full administrative control of a Vendor organization.',
  Object? status = 'ACTIVE',
  Object? createdAt = '2026-01-05T08:00:00+00:00',
  Object? permissionCount = 3,
  Object? assignedMemberCount = 2,
}) => <String, Object?>{
  'role_id': roleId,
  'role_name': roleName,
  'role_description': description,
  'role_status': status,
  'role_created_at': createdAt,
  'permission_count': permissionCount,
  'assigned_member_count': assignedMemberCount,
};

/// A `list_vendor_role_permissions(uuid)` row.
Map<String, Object?> permissionRow({
  Object? name = 'Read roles',
  Object? description = 'See roles and their permissions.',
}) => <String, Object?>{
  'permission_name': name,
  'permission_description': description,
};

/// A read that failed the way an unreadable body does.
ReadResult<T> unavailableRoleRead<T>() =>
    ReadFailure<T>(const UnavailableFailure());

/// A read the backend refused with `42501`.
ReadResult<T> deniedRoleRead<T>() => ReadFailure<T>(const DeniedFailure());
