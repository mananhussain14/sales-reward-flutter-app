import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/retailer_read_problem.dart';
import '../../domain/entities/retailer_campaign.dart';
import '../../domain/entities/staff_campaign.dart';
import '../../domain/repositories/retailer_campaign_repository.dart';
import '../../domain/repositories/staff_campaign_repository.dart';
import 'campaign_presentation.dart';

part 'campaign_list_state.dart';

/// The role-neutral shape of one campaign list read.
///
/// Exactly one of the two fields is set. A record rather than a second sealed
/// hierarchy: it exists only to carry a repository's answer up to the shared
/// base class, and both repositories already return properly sealed results of
/// their own.
typedef CampaignListOutcome = ({
  List<CampaignPresentation>? campaigns,
  RetailerReadProblem? problem,
});

/// The campaign list, for whichever role the subclass reads for.
///
/// ## One implementation, two roles, and why that is safe here
///
/// The load sequencing, the request tokens, the stale-response guard, the
/// refresh suppression, the "loaded once" rule and the session-clear behaviour
/// are identical for both roles, because they are properties of *reading a list*
/// rather than of either contract. Writing them twice would give the two roles
/// two chances to diverge on a rule neither is allowed to have an opinion about.
///
/// What is **not** shared is the type. [RetailerCampaignListCubit] and
/// [SalesStaffCampaignListCubit] are distinct classes over distinct
/// repositories, so `context.read<SalesStaffCampaignListCubit>()` cannot resolve
/// to an Owner's cubit and a shell wired to the wrong repository does not
/// compile. That mirrors the backend, which deliberately kept the two reads on
/// two permissions so that widening either could not widen the other.
///
/// ## Nothing here filters, sorts or derives a state
///
/// Which campaigns a role may see is decided in SQL. The staff contract's
/// `ACTIVE`/`SCHEDULED` restriction is not restated, the Owner contract's
/// "in-force version only" join is not restated, and no lifecycle state is
/// recomputed from a date against the device clock. This cubit holds what the
/// backend returned, in the order it returned it.
abstract base class CampaignListCubitBase extends Cubit<CampaignListState> {
  CampaignListCubitBase(CampaignAudience audience)
    : super(CampaignListState(audience: audience));

  /// One read, in whichever contract the subclass owns.
  Future<CampaignListOutcome> readCampaigns();

  /// Discriminates the answer this cubit is currently waiting for, so a read
  /// that lands after a session change cannot repopulate a cleared list.
  int _token = 0;

  /// Exposed for the isolation tests.
  int get requestToken => _token;

  Future<void> load() => _fetch(showLoading: true);

  /// Re-reads while keeping whatever is already on screen.
  ///
  /// The skeleton is shown only when there is nothing to keep — a pull-to-
  /// refresh over a populated list must not blank it.
  Future<void> refresh() => _fetch(showLoading: state.campaigns == null);

  /// Loads only if nothing has been read yet — what makes "opening the tab
  /// reads once" and "returning to a loaded tab reads nothing" both true.
  Future<void> loadOnce() {
    if (state.phase != CampaignListPhase.initial) {
      return Future<void>.value();
    }
    return load();
  }

  Future<void> _fetch({required bool showLoading}) async {
    // The duplicate-request guard. Two pulls in quick succession, or a pull
    // landing on top of the first load, issue one request rather than a storm.
    if (state.isRefreshing) {
      return;
    }

    final int token = ++_token;

    emit(
      state.copyWith(
        phase: showLoading
            ? CampaignListPhase.loading
            : CampaignListPhase.ready,
        isRefreshing: true,
        clearProblem: true,
      ),
    );

    final CampaignListOutcome outcome = await readCampaigns();

    // The stale-response guard. `isClosed` covers a disposed screen; the token
    // covers a session change that cleared this cubit while a read was in
    // flight. Either way the answer is dropped rather than emitted into state
    // that has moved on.
    if (isClosed || token != _token) {
      return;
    }

    final List<CampaignPresentation>? campaigns = outcome.campaigns;
    if (campaigns != null) {
      emit(
        state.copyWith(
          phase: CampaignListPhase.ready,
          campaigns: campaigns,
          isRefreshing: false,
          clearProblem: true,
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        phase: CampaignListPhase.failed,
        problem: outcome.problem ?? RetailerReadProblem.unexpected,
        isRefreshing: false,
        // Rows already on screen stay. They are still the last thing the
        // backend actually said, and the screen labels them as stale.
      ),
    );
  }

  /// Drops the campaigns, the loading and refresh state and the problem.
  ///
  /// Called when the signed-in person or the resolved Retailer changes. Which
  /// campaigns a Vendor targets at a Retailer — and on what terms — is a
  /// commercial fact about that relationship, and it must not survive into
  /// another person's session for even one frame.
  ///
  /// Advancing the token is the other half: a read already in flight for the
  /// previous identity is dropped on arrival rather than repopulating a list
  /// that has just been emptied.
  void clear() {
    _token++;
    emit(CampaignListState(audience: state.audience));
  }
}

/// The Retailer Owner's campaign list.
///
/// Reads `list_my_retailer_campaigns()` through
/// [RetailerCampaignRepository.campaigns] — zero arguments, scoped in SQL from
/// `auth.uid()` on `CAMPAIGNS_VIEW_ASSIGNED`.
final class RetailerCampaignListCubit extends CampaignListCubitBase {
  RetailerCampaignListCubit(this._repository)
    : super(CampaignAudience.retailerOwner);

  final RetailerCampaignRepository _repository;

  @override
  Future<CampaignListOutcome> readCampaigns() async {
    final RetailerCampaignsResult result = await _repository.campaigns();
    return switch (result) {
      RetailerCampaignsLoaded(:final List<RetailerCampaign> campaigns) => (
        campaigns: campaigns
            .map(CampaignPresentation.retailer)
            .toList(growable: false),
        problem: null,
      ),
      RetailerCampaignsFailed(:final RetailerReadProblem problem) => (
        campaigns: null,
        problem: problem,
      ),
    };
  }
}

/// The Sales Staff campaign list.
///
/// Reads `list_my_staff_campaigns()` through
/// [StaffCampaignRepository.campaigns] — zero arguments, scoped in SQL from
/// `auth.uid()` on `STAFF_CAMPAIGNS_VIEW`, and filtered there to `ACTIVE` and
/// `SCHEDULED`.
///
/// It holds **no** [RetailerCampaignRepository] and cannot reach one: the field
/// is typed to the staff interface, so an Owner repository does not compile
/// here — and would be refused with `42501` if it somehow arrived, because
/// `CAMPAIGNS_VIEW_ASSIGNED` is mapped to `RETAILER_OWNER` alone.
final class SalesStaffCampaignListCubit extends CampaignListCubitBase {
  SalesStaffCampaignListCubit(this._repository)
    : super(CampaignAudience.salesStaff);

  final StaffCampaignRepository _repository;

  @override
  Future<CampaignListOutcome> readCampaigns() async {
    final StaffCampaignsResult result = await _repository.campaigns();
    return switch (result) {
      StaffCampaignsLoaded(:final List<StaffCampaign> campaigns) => (
        campaigns: campaigns
            .map(CampaignPresentation.staff)
            .toList(growable: false),
        problem: null,
      ),
      StaffCampaignsFailed(:final RetailerReadProblem problem) => (
        campaigns: null,
        problem: problem,
      ),
    };
  }
}
