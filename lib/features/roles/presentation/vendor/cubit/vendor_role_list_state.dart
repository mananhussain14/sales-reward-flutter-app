part of 'vendor_role_list_cubit.dart';

/// Where the catalogue read has reached.
enum VendorRoleListPhase {
  /// Nothing has been read yet.
  initial,

  /// The first read is in flight.
  loading,

  /// A catalogue is on screen.
  ready,

  /// The read did not produce an answer.
  failed,
}

/// The shared role catalogue, plus the local narrowing applied to it.
final class VendorRoleListState extends Equatable {
  const VendorRoleListState({
    this.phase = VendorRoleListPhase.initial,
    this.roles = const <VendorRoleSummary>[],
    this.failure,
    this.isRefreshing = false,
    this.searchTerm = '',
    this.statusFilter,
  });

  final VendorRoleListPhase phase;

  /// Every row the backend returned, **in the backend's order**
  /// (`role_name, role_id`). Never re-sorted here — the database collation is
  /// not Dart's, and a second sort would be a second definition of the order.
  final List<VendorRoleSummary> roles;

  /// Why the read failed. A discriminant; never the backend's own message.
  final Failure? failure;

  /// True while a read is in flight, including a silent refresh over an
  /// already-populated catalogue.
  final bool isRefreshing;

  /// The local role-name search. Applied case-insensitively over [roles].
  final String searchTerm;

  /// The local status filter, or null for "all".
  final VendorRoleStatus? statusFilter;

  /// Whether anything is currently narrowing the list.
  bool get hasFilters => searchTerm.trim().isNotEmpty || statusFilter != null;

  /// The rows to render.
  ///
  /// With no search and no filter this is [roles] itself — the backend's order,
  /// untouched. `where` preserves order, so a narrowed list is a subsequence of
  /// it rather than a re-ranking, and clearing the narrowing restores the
  /// original order exactly.
  List<VendorRoleSummary> get visibleRoles {
    if (!hasFilters) {
      return roles;
    }
    final String needle = searchTerm.trim().toLowerCase();
    return roles
        .where((VendorRoleSummary role) {
          final bool matchesName =
              needle.isEmpty || role.roleName.toLowerCase().contains(needle);
          final bool matchesStatus =
              statusFilter == null || role.status == statusFilter;
          return matchesName && matchesStatus;
        })
        .toList(growable: false);
  }

  /// A successful read that returned nothing.
  ///
  /// Kept for resilience and covered by tests, but **not reachable while the
  /// caller is authorized**: a caller cannot hold `VENDOR_SUPER_ADMIN` unless
  /// that role is itself a row of this catalogue. It is a defensive floor, not
  /// an expected state.
  bool get isEmpty => phase == VendorRoleListPhase.ready && roles.isEmpty;

  /// Rows exist, but none survives the current narrowing. A different state
  /// from [isEmpty], and worded differently on screen.
  bool get hasNoMatches => roles.isNotEmpty && visibleRoles.isEmpty;

  /// How many role definitions the catalogue holds, before any narrowing.
  int get totalCount => roles.length;

  /// Definitions whose stored status is `ACTIVE` — the ones whose mapped
  /// permissions the backend will actually honour.
  ///
  /// Counted by a positive test against a single status, so a token this build
  /// does not recognise is counted as neither active nor inactive rather than
  /// being folded into one of them.
  int get activeCount =>
      roles.where((VendorRoleSummary r) => r.status.isActive).length;

  /// Definitions whose stored status is `INACTIVE`.
  int get inactiveCount => roles
      .where((VendorRoleSummary r) => r.status == VendorRoleStatus.inactive)
      .length;

  /// The total number of role→permission **mappings** across the catalogue.
  ///
  /// Deliberately not "how many permissions exist": a permission mapped to three
  /// roles contributes three. The catalogue-wide permission list is a different
  /// question and has no mobile operation, so this is presented as a count of
  /// mappings and never as a count of distinct permissions.
  int get totalPermissionMappings => roles.fold<int>(
    0,
    (int sum, VendorRoleSummary r) => sum + r.permissionCount,
  );

  /// How many memberships of the caller's own Vendor hold a catalogue role,
  /// counted once per role held.
  ///
  /// Used only to decide whether the assignment summary is worth showing at
  /// all — a Vendor whose every count is zero learns nothing from a row of
  /// zeroes.
  int get totalAssignments => roles.fold<int>(
    0,
    (int sum, VendorRoleSummary r) => sum + r.assignedMemberCount,
  );

  /// The statuses actually present in the loaded rows, in the enum's
  /// declaration order.
  ///
  /// Filter chips are built from this rather than from the enum, so the screen
  /// never offers a filter that can only ever produce an empty list — and never
  /// implies the backend uses a status it has not sent.
  /// [VendorRoleStatus.unknown] is included when a future token actually
  /// arrived, because hiding those rows behind no chip at all would make them
  /// unreachable.
  List<VendorRoleStatus> get presentStatuses {
    final Set<VendorRoleStatus> present = roles
        .map((VendorRoleSummary r) => r.status)
        .toSet();
    return VendorRoleStatus.values
        .where(present.contains)
        .toList(growable: false);
  }

  VendorRoleListState copyWith({
    VendorRoleListPhase? phase,
    List<VendorRoleSummary>? roles,
    Failure? failure,
    bool clearFailure = false,
    bool? isRefreshing,
    String? searchTerm,
    VendorRoleStatus? statusFilter,
    bool clearStatusFilter = false,
  }) {
    return VendorRoleListState(
      phase: phase ?? this.phase,
      roles: roles ?? this.roles,
      failure: clearFailure ? null : (failure ?? this.failure),
      isRefreshing: isRefreshing ?? this.isRefreshing,
      searchTerm: searchTerm ?? this.searchTerm,
      statusFilter: clearStatusFilter
          ? null
          : (statusFilter ?? this.statusFilter),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    phase,
    roles,
    failure,
    isRefreshing,
    searchTerm,
    statusFilter,
  ];
}
