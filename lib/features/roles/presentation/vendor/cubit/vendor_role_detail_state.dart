part of 'vendor_role_detail_cubit.dart';

/// Where the detail read has reached.
enum VendorRoleDetailPhase {
  /// Nothing is open.
  initial,

  /// `get_vendor_role_detail` is in flight.
  loading,

  /// One addressable role is on screen.
  ready,

  /// The backend returned **zero rows**.
  ///
  /// One state for an unknown id, an id belonging to some other table and a
  /// malformed id alike. Not an error, not an outage, and not retryable: the
  /// backend answered, and it will answer the same way again.
  notFound,

  /// The read did not produce an answer — a denial, an expired session, a
  /// timeout, or a body that could not be understood.
  failed,
}

/// Where the companion permission read has reached.
///
/// Tracked separately from [VendorRoleDetailPhase] because the two degrade
/// independently: a role whose permissions could not be loaded still has a name,
/// a status and two counts that came from a call which succeeded.
enum VendorRolePermissionsPhase { initial, loading, ready, failed }

/// One open role, and the permissions mapped to it.
final class VendorRoleDetailState extends Equatable {
  const VendorRoleDetailState({
    this.roleId,
    this.phase = VendorRoleDetailPhase.initial,
    this.detail,
    this.failure,
    this.permissionsPhase = VendorRolePermissionsPhase.initial,
    this.permissions = const <VendorRolePermission>[],
    this.permissionsFailure,
  });

  /// The role currently open, or null when nothing is.
  ///
  /// Held so a retry knows what to re-read, and so [VendorRoleDetailCubit.open]
  /// can recognise a repeat. It is **not** rendered as a field: an internal
  /// identifier on screen is noise to a Vendor.
  final String? roleId;

  final VendorRoleDetailPhase phase;

  /// The loaded row, present only in [VendorRoleDetailPhase.ready].
  final VendorRoleDetail? detail;

  /// Why the detail read failed. A discriminant; never the backend's message.
  final Failure? failure;

  final VendorRolePermissionsPhase permissionsPhase;

  /// The mapped permissions, in the backend's `permission_name, permission id`
  /// order. Not re-sorted, not de-duplicated, not filtered.
  final List<VendorRolePermission> permissions;

  final Failure? permissionsFailure;

  bool get isDetailLoading => phase == VendorRoleDetailPhase.loading;

  /// A real, successful "this role grants nothing" — distinguishable from "this
  /// is not a role" only because the detail read came back first.
  bool get hasNoPermissions =>
      phase == VendorRoleDetailPhase.ready &&
      permissionsPhase == VendorRolePermissionsPhase.ready &&
      permissions.isEmpty;

  /// Whether the open role's mapped permissions are currently **effective**.
  ///
  /// False for an `INACTIVE` role — and for a status token this build does not
  /// recognise, because "effective" is a positive test against `ACTIVE` and
  /// never the absence of something else. Also false while nothing is open, so
  /// no caller can read an affirmative answer out of an empty state.
  ///
  /// Presentation input only: it chooses which sentence the screen shows. The
  /// backend re-evaluates the real question on every call, and nothing here
  /// grants or withholds anything.
  bool get permissionsAreEffective =>
      detail?.status.grantsMappedPermissions ?? false;

  /// The loaded row disagrees with the companion about how many mappings exist.
  ///
  /// The backend computes `permission_count` by joining `role_permissions` to
  /// `permissions`, so it is *by construction* the number of rows the companion
  /// returns, and pgTAP asserts it for every role in the catalogue. A mismatch
  /// therefore means the two reads saw different states — most plausibly a
  /// catalogue change between them.
  ///
  /// It is surfaced as a note and nothing more: **every returned row is still
  /// shown and the count is still reported unchanged.** Dropping rows to match
  /// the number, or adjusting the number to match the rows, would each fabricate
  /// agreement the backend did not send.
  bool get permissionCountDisagrees =>
      phase == VendorRoleDetailPhase.ready &&
      permissionsPhase == VendorRolePermissionsPhase.ready &&
      detail != null &&
      detail!.permissionCount != permissions.length;

  VendorRoleDetailState copyWith({
    String? roleId,
    VendorRoleDetailPhase? phase,
    VendorRoleDetail? detail,
    Failure? failure,
    VendorRolePermissionsPhase? permissionsPhase,
    List<VendorRolePermission>? permissions,
    Failure? permissionsFailure,
    bool clearPermissionsFailure = false,
  }) {
    return VendorRoleDetailState(
      roleId: roleId ?? this.roleId,
      phase: phase ?? this.phase,
      detail: detail ?? this.detail,
      failure: failure ?? this.failure,
      permissionsPhase: permissionsPhase ?? this.permissionsPhase,
      permissions: permissions ?? this.permissions,
      permissionsFailure: clearPermissionsFailure
          ? null
          : (permissionsFailure ?? this.permissionsFailure),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    roleId,
    phase,
    detail,
    failure,
    permissionsPhase,
    permissions,
    permissionsFailure,
  ];
}
