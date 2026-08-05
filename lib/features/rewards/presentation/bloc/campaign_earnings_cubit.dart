import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/retailer_read_problem.dart';
import '../../domain/entities/campaign_earnings_summary.dart';
import '../../domain/entities/campaign_reward_record.dart';
import '../../domain/repositories/staff_earnings_repository.dart';

part 'campaign_earnings_state.dart';

/// A Sales Staff member's own campaign earnings: the totals, and the history.
///
/// ## Two reads, and neither can erase the other
///
/// The summary and the first page of history are issued together and settled
/// **independently**. A failed summary leaves the rewards on screen; a failed
/// history leaves the totals on screen; a failed *older page* leaves everything
/// already loaded exactly where it was. That is the rule the milestone states
/// outright — *"a reward-history pagination failure must not erase a
/// successfully loaded earnings summary"* — and it is enforced by keeping the
/// two answers in separate fields with separate problems rather than behind one
/// phase.
///
/// ## Keyset pagination, and no infinite scroll
///
/// Older rewards are fetched only when a person presses a button. Nothing loads
/// on scroll: a seller reading their own earnings should not have the list grow
/// under their thumb, and an automatic fetch would issue requests for pages
/// nobody asked to see.
///
/// The cursor is the `(awarded_at, campaign_reward_id)` pair of the **last row
/// already shown** — the same pair the contract orders by — held whole in a
/// [CampaignRewardCursor] so half of it cannot be sent.
///
/// ## Duplicates are impossible twice over
///
/// The keyset predicate is strict (`<`), so the backend cannot return a row that
/// is already on screen. [_appendUnseen] then filters by reward id anyway, so a
/// contract change, a retried page or a clock anomaly still cannot produce two
/// cards for one reward.
///
/// ## Nothing here computes an amount
///
/// No total is summed on the device, no cap is applied, no coin is derived. The
/// summary's five numbers are the database's, and the history's amounts are the
/// database's. This cubit sequences reads and holds answers.
final class SalesStaffEarningsCubit extends Cubit<SalesStaffEarningsState> {
  SalesStaffEarningsCubit(
    this._repository, {
    this.pageSize = campaignRewardPageSize,
  }) : super(const SalesStaffEarningsState());

  final StaffEarningsRepository _repository;

  /// Fixed for the life of the cubit and never read from user input.
  final int pageSize;

  /// Discriminates the answer this cubit is currently waiting for.
  int _token = 0;

  /// Exposed for the isolation tests.
  int get requestToken => _token;

  Future<void> load() => _fetch(showLoading: true);

  /// Re-reads both contracts while keeping whatever is already on screen.
  ///
  /// A refresh starts the history again from the newest reward: rewards are
  /// append-only, so anything awarded since the last read belongs at the top,
  /// and keeping the old pages below it would leave a gap nobody could see.
  Future<void> refresh() => _fetch(showLoading: state.rewards == null);

  /// Loads only if nothing has been read yet.
  Future<void> loadOnce() {
    if (state.phase != EarningsPhase.initial) {
      return Future<void>.value();
    }
    return load();
  }

  Future<void> _fetch({required bool showLoading}) async {
    // The duplicate-request guard.
    if (state.isRefreshing) {
      return;
    }

    final int token = ++_token;

    emit(
      state.copyWith(
        phase: showLoading ? EarningsPhase.loading : EarningsPhase.ready,
        isRefreshing: true,
        clearSummaryProblem: true,
        clearRewardsProblem: true,
        clearOlderProblem: true,
      ),
    );

    // Issued together rather than in sequence: they are independent contracts
    // and one round trip of latency is enough for a screen that shows both.
    final (
      StaffEarningsSummaryResult summaryResult,
      StaffCampaignRewardsResult rewardsResult,
    ) = await (
      _repository.getMyCampaignEarningsSummary(),
      _repository.getMyCampaignRewards(
        limit: pageSize,
        // The FIRST request carries NO cursor. Both halves are null, which is
        // what the contract's guard reads as "start at the newest".
        beforeAwardedAt: null,
        beforeRewardId: null,
      ),
    ).wait;

    if (isClosed || token != _token) {
      return;
    }

    SalesStaffEarningsState next = state.copyWith(
      phase: EarningsPhase.ready,
      isRefreshing: false,
    );

    switch (summaryResult) {
      case StaffEarningsSummaryLoaded(:final CampaignEarningsSummary summary):
        next = next.copyWith(summary: summary, summaryUnavailable: false);
      case StaffEarningsSummaryUnavailable():
        // Zero rows: this surface is not this caller's. Distinct from a summary
        // of zeros, and rendered as a refusal rather than as "you earned 0".
        next = next.copyWith(summaryUnavailable: true, clearSummary: true);
      case StaffEarningsSummaryFailed(:final RetailerReadProblem problem):
        next = next.copyWith(summaryProblem: problem);
    }

    switch (rewardsResult) {
      case StaffCampaignRewardsLoaded(
        :final List<CampaignRewardRecord> rewards,
        :final bool hasMore,
      ):
        next = next.copyWith(rewards: rewards, hasMore: hasMore);
      case StaffCampaignRewardsFailed(:final RetailerReadProblem problem):
        next = next.copyWith(rewardsProblem: problem);
    }

    emit(next);
  }

  /// Fetches the page **before** the oldest reward on screen.
  ///
  /// A no-op unless there is something to page from and something to page to.
  /// The `isLoadingOlder` guard is what makes a double tap issue one request:
  /// the button is also disabled while it runs, but a guard that depends on a
  /// widget being rebuilt is not a guard.
  Future<void> loadOlder() async {
    if (state.isLoadingOlder || state.isRefreshing || !state.hasMore) {
      return;
    }

    final CampaignRewardCursor? cursor = state.cursor;
    if (cursor == null) {
      // No page has loaded, so there is nothing to page from. Not an error:
      // the button is not rendered in this state.
      return;
    }

    final int token = ++_token;

    emit(state.copyWith(isLoadingOlder: true, clearOlderProblem: true));

    final StaffCampaignRewardsResult result = await _repository
        .getMyCampaignRewards(
          limit: pageSize,
          // BOTH halves, always together. `state.cursor` is built from one row,
          // so there is no way to send one without the other.
          beforeAwardedAt: cursor.awardedAt,
          beforeRewardId: cursor.rewardId,
        );

    if (isClosed || token != _token) {
      return;
    }

    switch (result) {
      case StaffCampaignRewardsLoaded(
        :final List<CampaignRewardRecord> rewards,
        :final bool hasMore,
      ):
        emit(
          state.copyWith(
            rewards: _appendUnseen(rewards),
            hasMore: hasMore,
            isLoadingOlder: false,
          ),
        );
      case StaffCampaignRewardsFailed(:final RetailerReadProblem problem):
        emit(
          state.copyWith(
            // Everything already loaded stays: the totals, and every reward on
            // screen. Only the attempt to extend the list failed.
            olderProblem: problem,
            isLoadingOlder: false,
          ),
        );
    }
  }

  /// The existing rewards, plus any of [page] not already present.
  ///
  /// Belt and braces over a strict keyset predicate — see the class doc.
  List<CampaignRewardRecord> _appendUnseen(List<CampaignRewardRecord> page) {
    final List<CampaignRewardRecord> existing =
        state.rewards ?? const <CampaignRewardRecord>[];
    final Set<String> seen = existing
        .map((CampaignRewardRecord reward) => reward.rewardId)
        .toSet();

    return <CampaignRewardRecord>[
      ...existing,
      for (final CampaignRewardRecord reward in page)
        if (seen.add(reward.rewardId)) reward,
    ];
  }

  /// Drops the totals, the history, the cursor and every problem.
  ///
  /// Called when the signed-in person or the resolved Retailer changes. What
  /// somebody has earned is the most private thing this application holds, and
  /// it must not survive into another person's session for even one frame.
  void clear() {
    _token++;
    emit(const SalesStaffEarningsState());
  }
}
