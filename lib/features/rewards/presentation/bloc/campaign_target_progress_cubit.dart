import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/retailer_read_problem.dart';
import '../../domain/entities/campaign_target_progress.dart';
import '../../domain/repositories/staff_earnings_repository.dart';

part 'campaign_target_progress_state.dart';

/// A Sales Staff member's progress towards every target campaign they can see.
///
/// ## Deliberately a SECOND cubit beside the campaign list
///
/// The campaign list and this progress read are two contracts on two
/// permissions, and keeping them in two cubits is what makes the partial-failure
/// rule structural rather than remembered: a progress read that fails cannot
/// blank a campaign list it does not own, and a campaign read that fails cannot
/// take the progress with it. Merging them would put both behind one phase, and
/// one failure would erase both screens' worth of data.
///
/// ## Nothing here decides what a seller may see
///
/// `get_my_campaign_target_progress()` applies the same frozen Retailer
/// targeting, the same published-version join and the same `ACTIVE`/`SCHEDULED`
/// filter as `list_my_staff_campaigns()`, *"so a client can join these rows to
/// that list one-to-one on campaign_id"*. This cubit restates none of it: it
/// holds what came back, keyed by campaign id, and a campaign with no row simply
/// has no progress.
///
/// A `PER_UNIT_COINS` campaign never has a row, because the contract joins only
/// `TARGET_BONUS` rules. That is why there is no "is this a target campaign?"
/// branch anywhere in this feature — the absence of a row **is** the answer.
final class SalesStaffCampaignProgressCubit
    extends Cubit<CampaignTargetProgressState> {
  SalesStaffCampaignProgressCubit(this._repository)
    : super(const CampaignTargetProgressState());

  final StaffEarningsRepository _repository;

  /// Discriminates the answer this cubit is currently waiting for, so a read
  /// that lands after a session change cannot repopulate cleared progress.
  int _token = 0;

  /// Exposed for the isolation tests.
  int get requestToken => _token;

  Future<void> load() => _fetch(showLoading: true);

  /// Re-reads while keeping whatever is already on screen.
  Future<void> refresh() => _fetch(showLoading: state.byCampaignId == null);

  /// Loads only if nothing has been read yet.
  Future<void> loadOnce() {
    if (state.phase != CampaignTargetProgressPhase.initial) {
      return Future<void>.value();
    }
    return load();
  }

  Future<void> _fetch({required bool showLoading}) async {
    // The duplicate-request guard, matching the campaign list's. Two pulls in
    // quick succession issue one request rather than a storm.
    if (state.isRefreshing) {
      return;
    }

    final int token = ++_token;

    emit(
      state.copyWith(
        phase: showLoading
            ? CampaignTargetProgressPhase.loading
            : CampaignTargetProgressPhase.ready,
        isRefreshing: true,
        clearProblem: true,
      ),
    );

    final StaffCampaignTargetProgressResult result = await _repository
        .getMyCampaignTargetProgress();

    if (isClosed || token != _token) {
      return;
    }

    switch (result) {
      case StaffCampaignTargetProgressLoaded():
        emit(
          state.copyWith(
            phase: CampaignTargetProgressPhase.ready,
            byCampaignId: result.byCampaignId,
            isRefreshing: false,
            clearProblem: true,
          ),
        );
      case StaffCampaignTargetProgressFailed(
        :final RetailerReadProblem problem,
      ):
        emit(
          state.copyWith(
            phase: CampaignTargetProgressPhase.failed,
            problem: problem,
            isRefreshing: false,
            // Rows already on screen stay. They are still the last thing the
            // backend actually said, and the list labels the situation.
          ),
        );
    }
  }

  /// Drops the progress, the loading state and the problem.
  ///
  /// Called when the signed-in person or the resolved Retailer changes. How far
  /// a seller — or their team — has got towards a target is private to them, and
  /// must not survive into another person's session for even one frame.
  void clear() {
    _token++;
    emit(const CampaignTargetProgressState());
  }
}
