part of 'retailer_staff_cubit.dart';

/// Where one staff section has reached.
///
/// Each section carries its own value, because the roster and the invitation
/// history are companion reads on different permissions and can genuinely be in
/// different states at the same moment.
enum RetailerStaffPhase {
  /// Nothing has been read yet.
  initial,

  /// A read is in flight.
  loading,

  /// Rows are on screen — possibly zero, which is a real answer.
  ready,

  /// The read did not produce an answer.
  failed,

  /// This section is not part of this role's screen at all.
  ///
  /// Distinct from [failed] and from an empty [ready]: the Manager view does not
  /// show invitation history, so there is nothing to load, nothing to retry, and
  /// nothing to report. A Manager must never see an error where a section simply
  /// does not apply.
  notApplicable,
}

/// The staff screen's state: two sections, one search term.
///
/// Immutable, and holds **no raw Supabase map** — every value is a parsed domain
/// type.
final class RetailerStaffState extends Equatable {
  const RetailerStaffState({
    this.rosterPhase = RetailerStaffPhase.initial,
    this.invitationPhase = RetailerStaffPhase.initial,
    this.members,
    this.invitations,
    this.rosterProblem,
    this.invitationProblem,
    this.isRefreshing = false,
    this.searchTerm = '',
  });

  final RetailerStaffPhase rosterPhase;
  final RetailerStaffPhase invitationPhase;

  /// The roster rows, or null when none has been read.
  ///
  /// Null is **not** an empty roster and is never rendered as one.
  final List<RetailerStaffMember>? members;

  /// The invitation rows, or null when none has been read.
  final List<RetailerStaffInvitation>? invitations;

  /// Why the roster read failed. A discriminant; never backend text.
  final RetailerReadProblem? rosterProblem;

  /// Why the invitation read failed. Independent of [rosterProblem] — the whole
  /// point of modelling the two separately.
  final RetailerReadProblem? invitationProblem;

  final bool isRefreshing;

  /// The local filter, applied to both sections. Never sent anywhere.
  final String searchTerm;

  // -- roster ---------------------------------------------------------------

  /// The roster rows after the local filter.
  ///
  /// Matches **name, role name and shop name** — the three things a person
  /// searches a roster by. `roleCode` is deliberately excluded: it is an
  /// internal token that is never displayed, and matching on it would let a
  /// search surface rows for a reason the user cannot see.
  List<RetailerStaffMember> get visibleMembers {
    final List<RetailerStaffMember> all =
        members ?? const <RetailerStaffMember>[];
    final String needle = searchTerm.trim().toLowerCase();
    if (needle.isEmpty) {
      return all;
    }
    return all
        .where((RetailerStaffMember member) {
          return member.fullName.toLowerCase().contains(needle) ||
              member.roleName.toLowerCase().contains(needle) ||
              member.shopNames.any(
                (String shop) => shop.toLowerCase().contains(needle),
              );
        })
        .toList(growable: false);
  }

  bool get isRosterEmpty =>
      rosterPhase == RetailerStaffPhase.ready && (members?.isEmpty ?? false);

  bool get hasRosterFailedOutright =>
      rosterPhase == RetailerStaffPhase.failed && members == null;

  bool get isRosterStale =>
      rosterPhase == RetailerStaffPhase.failed && members != null;

  // -- invitations ----------------------------------------------------------

  /// The invitation rows after the local filter.
  ///
  /// Matches **name and email**. The role is matched through its code's label at
  /// the presentation layer rather than here, because the contract returns only
  /// `role_code` for an invitation and the raw token must not be searchable.
  List<RetailerStaffInvitation> get visibleInvitations {
    final List<RetailerStaffInvitation> all =
        invitations ?? const <RetailerStaffInvitation>[];
    final String needle = searchTerm.trim().toLowerCase();
    if (needle.isEmpty) {
      return all;
    }
    return all
        .where((RetailerStaffInvitation invitation) {
          return invitation.fullName.toLowerCase().contains(needle) ||
              invitation.email.toLowerCase().contains(needle);
        })
        .toList(growable: false);
  }

  /// Whether the invitation section belongs on this screen at all.
  bool get showsInvitations =>
      invitationPhase != RetailerStaffPhase.notApplicable;

  bool get isInvitationsEmpty =>
      invitationPhase == RetailerStaffPhase.ready &&
      (invitations?.isEmpty ?? false);

  bool get hasInvitationsFailedOutright =>
      invitationPhase == RetailerStaffPhase.failed && invitations == null;

  bool get isInvitationsStale =>
      invitationPhase == RetailerStaffPhase.failed && invitations != null;

  // -- whole screen ---------------------------------------------------------

  /// Anything at all has been read.
  bool get hasAnyContent => members != null || invitations != null;

  /// The skeleton should be shown: a first read with nothing yet to display.
  bool get isInitialLoading =>
      rosterPhase == RetailerStaffPhase.loading && !hasAnyContent;

  /// A search is active and hid everything that exists.
  bool get isSearchEmpty {
    if (searchTerm.trim().isEmpty) {
      return false;
    }
    final bool hasSomething =
        (members?.isNotEmpty ?? false) || (invitations?.isNotEmpty ?? false);
    return hasSomething && visibleMembers.isEmpty && visibleInvitations.isEmpty;
  }

  /// Exactly one section failed while the other succeeded.
  ///
  /// The state the screen must never describe as "everything failed".
  bool get isPartialSuccess {
    final bool rosterOk = rosterPhase == RetailerStaffPhase.ready;
    final bool invitesOk = invitationPhase == RetailerStaffPhase.ready;
    final bool rosterBad = rosterPhase == RetailerStaffPhase.failed;
    final bool invitesBad = invitationPhase == RetailerStaffPhase.failed;
    return (rosterOk && invitesBad) || (invitesOk && rosterBad);
  }

  RetailerStaffState copyWith({
    RetailerStaffPhase? rosterPhase,
    RetailerStaffPhase? invitationPhase,
    List<RetailerStaffMember>? members,
    List<RetailerStaffInvitation>? invitations,
    RetailerReadProblem? rosterProblem,
    RetailerReadProblem? invitationProblem,
    bool? isRefreshing,
    String? searchTerm,
    bool clearRosterProblem = false,
    bool clearInvitationProblem = false,
  }) {
    return RetailerStaffState(
      rosterPhase: rosterPhase ?? this.rosterPhase,
      invitationPhase: invitationPhase ?? this.invitationPhase,
      members: members ?? this.members,
      invitations: invitations ?? this.invitations,
      // Explicit clears, because `copyWith(x: null)` cannot be told from "leave
      // it alone" in Dart — and a stale problem surviving a successful refresh
      // would leave an error notice above fresh rows.
      rosterProblem: clearRosterProblem
          ? null
          : (rosterProblem ?? this.rosterProblem),
      invitationProblem: clearInvitationProblem
          ? null
          : (invitationProblem ?? this.invitationProblem),
      isRefreshing: isRefreshing ?? this.isRefreshing,
      searchTerm: searchTerm ?? this.searchTerm,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    rosterPhase,
    invitationPhase,
    members,
    invitations,
    rosterProblem,
    invitationProblem,
    isRefreshing,
    searchTerm,
  ];
}
