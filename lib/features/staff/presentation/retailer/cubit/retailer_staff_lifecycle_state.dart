part of 'retailer_staff_lifecycle_cubit.dart';

/// A lifecycle change that has settled, so it can be acknowledged.
///
/// A **statement about the past** rather than a status: nothing here decides what
/// a membership currently looks like, which is the re-read roster's job alone.
/// Every member is chosen from the status the *database confirmed*, never from
/// the status that was requested.
enum RetailerStaffLifecycleNotice {
  /// The database confirmed the membership now holds `DEACTIVATED`, and this
  /// call is what moved it.
  deactivated,

  /// The database confirmed the membership now holds `ACTIVE`, and this call is
  /// what moved it.
  reactivated,

  /// The membership was already inactive; this call changed nothing.
  ///
  /// Presented as an outcome rather than an error: nothing went wrong, nothing
  /// was written, no audit row was recorded and the original `deactivated_at`
  /// was preserved. Most often it means a second Owner got there first.
  alreadyInactive,

  /// The membership was already active; this call changed nothing.
  alreadyActive,

  /// The RPC answered without an error — so the transaction **committed** — but
  /// with a body this build could not trust.
  ///
  /// One member for both directions, because the direction is precisely what
  /// could not be established. It never says the change was lost, and nothing
  /// retries it: the canonical roster is re-read, and that is the only authority
  /// on what the membership now holds.
  unconfirmed,
}

/// Every lifecycle decision currently in flight or awaiting acknowledgement,
/// **keyed by membership id**.
///
/// ## Why three maps and not one "current decision"
///
/// The roster renders many cards at once, and each is an independent target: the
/// deployed function serializes on the **target row** with `FOR UPDATE`, so two
/// different memberships are two different rows and do not contend. Modelling one
/// decision at a time would therefore impose a restriction the backend does not
/// have — and, worse, would leave every other row's button visibly enabled while
/// the cubit silently refused it.
///
/// So there is no single `membershipId`, no single `phase` and no single
/// `problem`. There are three collections, and every question a card asks is
/// answered for its own id alone:
///
/// * [busyMembershipIds] — which rows have a request in flight;
/// * [problems] — which rows have an outstanding refusal;
/// * [notices] — which rows have a committed outcome to acknowledge.
///
/// A membership is in **at most one** of the two result maps at a time: starting a
/// request clears both entries for that id, and settling writes exactly one.
///
/// Every collection is unmodifiable, so a caller cannot mutate the state it was
/// handed.
final class RetailerStaffLifecycleState extends Equatable {
  const RetailerStaffLifecycleState({
    this.busyMembershipIds = const <String>{},
    this.problems = const <String, RetailerStaffLifecycleProblem>{},
    this.notices = const <String, RetailerStaffLifecycleNotice>{},
  });

  /// The memberships with a request in flight.
  ///
  /// Never rendered as ids. Each is an address, held for exactly as long as one
  /// decision takes, and only ever the value that became `p_membership_id`.
  final Set<String> busyMembershipIds;

  /// Outstanding refusals, by membership.
  ///
  /// A discriminant, never the backend's text: a denial covers eleven causes
  /// identically, exactly as SQL does, and says nothing about whether the target
  /// exists, who they are, or what roles they hold.
  final Map<String, RetailerStaffLifecycleProblem> problems;

  /// Committed outcomes awaiting acknowledgement, by membership.
  final Map<String, RetailerStaffLifecycleNotice> notices;

  /// Whether a request for [id] specifically is in flight.
  ///
  /// This is what a card binds its spinner **and its disabled state** to. Because
  /// the cubit refuses only a *duplicate* request for the same membership, a
  /// button that is enabled is a button whose press will always be acted on.
  bool isBusyFor(String id) => busyMembershipIds.contains(id);

  /// The outstanding refusal for [id] specifically, or null.
  RetailerStaffLifecycleProblem? problemFor(String id) => problems[id];

  /// The acknowledgement for [id] specifically, or null.
  RetailerStaffLifecycleNotice? noticeFor(String id) => notices[id];

  /// Whether any request at all is in flight. Diagnostic and test use only —
  /// **no control may be disabled from this**, because doing so would disable
  /// rows the cubit would happily have accepted.
  bool get hasAnyInFlight => busyMembershipIds.isNotEmpty;

  /// Whether nothing is in flight and nothing is awaiting acknowledgement.
  bool get isIdle =>
      busyMembershipIds.isEmpty && problems.isEmpty && notices.isEmpty;

  RetailerStaffLifecycleState copyWith({
    Set<String>? busyMembershipIds,
    Map<String, RetailerStaffLifecycleProblem>? problems,
    Map<String, RetailerStaffLifecycleNotice>? notices,
  }) {
    return RetailerStaffLifecycleState(
      busyMembershipIds: busyMembershipIds ?? this.busyMembershipIds,
      problems: problems ?? this.problems,
      notices: notices ?? this.notices,
    );
  }

  @override
  List<Object?> get props => <Object?>[busyMembershipIds, problems, notices];
}
