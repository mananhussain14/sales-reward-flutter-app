part of 'campaign_earnings_cubit.dart';

/// Where the earnings screen's first read has reached.
enum EarningsPhase {
  /// Nothing has been read yet.
  initial,

  /// The first read is in flight.
  loading,

  /// Both contracts have settled — each one either with an answer or with its
  /// own problem.
  ready,
}

/// The totals, the reward history, and how each of them got there.
///
/// ## Two answers, two problems, on purpose
///
/// There is no single `phase: failed`. The summary and the history are separate
/// contracts and either can fail alone, so each carries its own optional
/// problem and neither clears the other's data. A third problem —
/// [olderProblem] — belongs to the *pagination attempt* and never touches the
/// rewards already loaded.
///
/// Immutable, and holds **no raw Supabase map**.
final class SalesStaffEarningsState extends Equatable {
  const SalesStaffEarningsState({
    this.phase = EarningsPhase.initial,
    this.summary,
    this.summaryUnavailable = false,
    this.summaryProblem,
    this.rewards,
    this.hasMore = false,
    this.rewardsProblem,
    this.olderProblem,
    this.isRefreshing = false,
    this.isLoadingOlder = false,
  });

  final EarningsPhase phase;

  /// The totals, or null when they have not been read or could not be.
  final CampaignEarningsSummary? summary;

  /// The summary contract returned **zero rows**: the caller is not an active
  /// Sales Staff member of exactly one active Retailer holding
  /// `STAFF_EARNINGS_VIEW`.
  ///
  /// Deliberately not represented as a summary of zeros. "You have earned
  /// nothing" and "this surface is not yours" are different statements.
  final bool summaryUnavailable;

  /// Why the summary read failed. A discriminant; never backend text.
  final RetailerReadProblem? summaryProblem;

  /// Every reward loaded so far, newest first, in the backend's own order.
  ///
  /// Null is **not** an empty list and is never rendered as one: an empty list
  /// is the true "you have not earned any campaign rewards yet" answer, and null
  /// means nothing has been read.
  final List<CampaignRewardRecord>? rewards;

  /// Whether another page may exist behind the oldest reward on screen.
  final bool hasMore;

  /// Why the first page of history failed.
  final RetailerReadProblem? rewardsProblem;

  /// Why the most recent *older* page failed.
  ///
  /// Its presence never removes a reward: everything already loaded is still
  /// what the backend said.
  final RetailerReadProblem? olderProblem;

  final bool isRefreshing;
  final bool isLoadingOlder;

  /// The cursor into the page before the oldest reward on screen.
  ///
  /// Built from the **last row of what is displayed**, which is exactly the row
  /// the contract's `(awarded_at, id) < (…)` predicate must exclude. Null when
  /// nothing has been loaded, which is also when no pagination control is
  /// rendered.
  CampaignRewardCursor? get cursor {
    final List<CampaignRewardRecord>? loaded = rewards;
    if (loaded == null || loaded.isEmpty) {
      return null;
    }
    final CampaignRewardRecord last = loaded.last;
    return CampaignRewardCursor(
      awardedAt: last.awardedAt,
      rewardId: last.rewardId,
    );
  }

  bool get isInitialLoading =>
      phase == EarningsPhase.loading && rewards == null && summary == null;

  /// The backend genuinely returned no rewards.
  bool get hasNoRewards =>
      phase == EarningsPhase.ready && (rewards?.isEmpty ?? false);

  /// The history could not be read at all — distinct from having none.
  bool get historyFailedOutright => rewardsProblem != null && rewards == null;

  /// Whether the "Load older rewards" control belongs on screen.
  ///
  /// Requires something to page from as well as something to page to, so the
  /// button never appears above an empty list.
  bool get canLoadOlder => hasMore && (rewards?.isNotEmpty ?? false);

  /// The history is complete: a page came back short, and there is at least one
  /// reward to have completed.
  bool get reachedEndOfHistory =>
      !hasMore && (rewards?.isNotEmpty ?? false) && olderProblem == null;

  SalesStaffEarningsState copyWith({
    EarningsPhase? phase,
    CampaignEarningsSummary? summary,
    bool? summaryUnavailable,
    RetailerReadProblem? summaryProblem,
    List<CampaignRewardRecord>? rewards,
    bool? hasMore,
    RetailerReadProblem? rewardsProblem,
    RetailerReadProblem? olderProblem,
    bool? isRefreshing,
    bool? isLoadingOlder,
    bool clearSummary = false,
    bool clearSummaryProblem = false,
    bool clearRewardsProblem = false,
    bool clearOlderProblem = false,
  }) {
    return SalesStaffEarningsState(
      phase: phase ?? this.phase,
      summary: clearSummary ? null : (summary ?? this.summary),
      summaryUnavailable: summaryUnavailable ?? this.summaryUnavailable,
      // Explicit clears, because `copyWith(x: null)` cannot be told from "leave
      // it alone" in Dart.
      summaryProblem: clearSummaryProblem
          ? null
          : (summaryProblem ?? this.summaryProblem),
      rewards: rewards ?? this.rewards,
      hasMore: hasMore ?? this.hasMore,
      rewardsProblem: clearRewardsProblem
          ? null
          : (rewardsProblem ?? this.rewardsProblem),
      olderProblem: clearOlderProblem
          ? null
          : (olderProblem ?? this.olderProblem),
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isLoadingOlder: isLoadingOlder ?? this.isLoadingOlder,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    phase,
    summary,
    summaryUnavailable,
    summaryProblem,
    rewards,
    hasMore,
    rewardsProblem,
    olderProblem,
    isRefreshing,
    isLoadingOlder,
  ];
}
