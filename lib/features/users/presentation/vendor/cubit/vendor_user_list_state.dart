part of 'vendor_user_list_cubit.dart';

/// Where the directory read has reached.
enum VendorUserListPhase {
  /// Nothing has been read yet.
  initial,

  /// The first read is in flight.
  loading,

  /// A directory is on screen.
  ready,

  /// The read did not produce an answer.
  failed,
}

/// The Vendor's user directory, plus the local narrowing applied to it.
final class VendorUserListState extends Equatable {
  const VendorUserListState({
    this.phase = VendorUserListPhase.initial,
    this.users = const <VendorUserSummary>[],
    this.failure,
    this.isRefreshing = false,
    this.searchTerm = '',
    this.profileFilter,
    this.membershipFilter,
  });

  final VendorUserListPhase phase;

  /// Every row the backend returned, **in the backend's order**
  /// (`display_name, membership_id`). Never re-sorted here — the database
  /// collation is not Dart's.
  final List<VendorUserSummary> users;

  /// Why the read failed. A discriminant; never the backend's own message.
  final Failure? failure;

  /// True while a read is in flight, including a silent refresh over an
  /// already-populated directory.
  final bool isRefreshing;

  /// The local display-name search. Applied case-insensitively over [users].
  final String searchTerm;

  /// The local profile-status filter, or null for "all".
  final VendorUserStatus? profileFilter;

  /// The local membership-status filter, or null for "all".
  final VendorUserStatus? membershipFilter;

  /// Whether anything is currently narrowing the list.
  bool get hasFilters =>
      searchTerm.trim().isNotEmpty ||
      profileFilter != null ||
      membershipFilter != null;

  /// The rows to render.
  ///
  /// With no search and no filter this is [users] itself — the backend's order,
  /// untouched. `where` preserves order, so a narrowed list is a subsequence of
  /// it rather than a re-ranking.
  List<VendorUserSummary> get visibleUsers {
    if (!hasFilters) {
      return users;
    }
    final String needle = searchTerm.trim().toLowerCase();
    return users
        .where((VendorUserSummary user) {
          final bool matchesName =
              needle.isEmpty || user.displayName.toLowerCase().contains(needle);
          final bool matchesProfile =
              profileFilter == null || user.profileStatus == profileFilter;
          final bool matchesMembership =
              membershipFilter == null ||
              user.membershipStatus == membershipFilter;
          return matchesName && matchesProfile && matchesMembership;
        })
        .toList(growable: false);
  }

  /// A successful read that returned nothing.
  ///
  /// Kept for resilience and covered by tests, but **not reachable while the
  /// caller is authorized**: an authorized caller is by definition an ACTIVE
  /// member of the Vendor they are listing, so their own row is always present.
  /// The real "no colleagues" case is one row — see [isOnlyMe] — and the empty
  /// state is worded against that.
  bool get isEmpty => phase == VendorUserListPhase.ready && users.isEmpty;

  /// The Vendor has exactly one user. That user is the caller.
  bool get isOnlyMe => phase == VendorUserListPhase.ready && users.length == 1;

  /// Rows exist, but none survives the current narrowing. A different state
  /// from [isEmpty], and worded differently on screen.
  bool get hasNoMatches => users.isNotEmpty && visibleUsers.isEmpty;

  /// How many users this Vendor has, before any narrowing.
  int get totalCount => users.length;

  /// Users whose **membership** in this Vendor is active.
  ///
  /// Membership rather than profile status, because "who is working in this
  /// organization" is the question a Vendor directory answers. Derived directly
  /// from the returned statuses — nothing here is counted from a value the
  /// backend did not send, and an unknown status is counted in none of the
  /// three buckets rather than being quietly folded into one.
  int get activeCount => _countWhere(VendorUserStatus.active);

  /// Users recorded but not yet joined.
  int get invitedCount => _countWhere(VendorUserStatus.invited);

  /// Users whose membership is suspended or deactivated.
  int get inactiveCount =>
      _countWhere(VendorUserStatus.suspended) +
      _countWhere(VendorUserStatus.deactivated);

  int _countWhere(VendorUserStatus status) =>
      users.where((VendorUserSummary u) => u.membershipStatus == status).length;

  /// The profile statuses actually present in the loaded rows, in the enum's
  /// declaration order.
  ///
  /// Filter chips are built from this rather than from the enum, so the screen
  /// never offers a filter that can only ever produce an empty list — and never
  /// implies the backend uses a status it has not sent.
  /// [VendorUserStatus.unknown] is included when a future token actually
  /// arrived, because hiding those rows behind no chip at all would make them
  /// unreachable.
  List<VendorUserStatus> get presentProfileStatuses =>
      _present((VendorUserSummary u) => u.profileStatus);

  /// The membership statuses actually present in the loaded rows.
  List<VendorUserStatus> get presentMembershipStatuses =>
      _present((VendorUserSummary u) => u.membershipStatus);

  List<VendorUserStatus> _present(
    VendorUserStatus Function(VendorUserSummary user) of,
  ) {
    final Set<VendorUserStatus> present = users.map(of).toSet();
    return VendorUserStatus.values
        .where(present.contains)
        .toList(growable: false);
  }

  VendorUserListState copyWith({
    VendorUserListPhase? phase,
    List<VendorUserSummary>? users,
    Failure? failure,
    bool clearFailure = false,
    bool? isRefreshing,
    String? searchTerm,
    VendorUserStatus? profileFilter,
    bool clearProfileFilter = false,
    VendorUserStatus? membershipFilter,
    bool clearMembershipFilter = false,
  }) {
    return VendorUserListState(
      phase: phase ?? this.phase,
      users: users ?? this.users,
      failure: clearFailure ? null : (failure ?? this.failure),
      isRefreshing: isRefreshing ?? this.isRefreshing,
      searchTerm: searchTerm ?? this.searchTerm,
      profileFilter: clearProfileFilter
          ? null
          : (profileFilter ?? this.profileFilter),
      membershipFilter: clearMembershipFilter
          ? null
          : (membershipFilter ?? this.membershipFilter),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    phase,
    users,
    failure,
    isRefreshing,
    searchTerm,
    profileFilter,
    membershipFilter,
  ];
}
