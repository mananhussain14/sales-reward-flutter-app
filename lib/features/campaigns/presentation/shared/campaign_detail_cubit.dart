import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/retailer_read_problem.dart';
import '../../domain/entities/campaign_product.dart';
import '../../domain/entities/retailer_campaign.dart';
import '../../domain/entities/staff_campaign.dart';
import '../../domain/repositories/retailer_campaign_repository.dart';
import '../../domain/repositories/staff_campaign_repository.dart';
import 'campaign_presentation.dart';

part 'campaign_detail_state.dart';

/// Which of the three answers a detail read produced.
enum CampaignDetailAnswer {
  /// A campaign came back, with its product list.
  loaded,

  /// Zero rows. Unknown id, another Retailer's id, a superseded version, a
  /// malformed id refused on the device — and, for a seller, a campaign that is
  /// no longer `ACTIVE` or `SCHEDULED`. **One answer for all of them.**
  missing,

  /// The read did not complete.
  failed,
}

/// The role-neutral shape of one campaign detail read.
typedef CampaignDetailOutcome = ({
  CampaignDetailAnswer answer,
  CampaignPresentation? campaign,
  List<CampaignProduct> products,
  RetailerReadProblem? problem,
});

/// One campaign, addressed by id from the route.
///
/// ## The id is an address, not a permission
///
/// Typing an unknown id — or `not-a-uuid` — into the route reaches this cubit
/// and produces [CampaignDetailPhase.notFound], the same state for all of them.
/// The backend returns zero rows for an id that is not this Retailer's, and the
/// repository answers a malformed one locally without a request, so a
/// well-formed id belonging to somebody else reaches exactly the same screen as
/// a typo.
///
/// Nothing on the device decides whether the campaign is readable. That is
/// decided in SQL, under the caller's own token, on every call.
///
/// ## Two calls, in one order, once each
///
/// The repository issues `get_my_*_campaign` first and
/// `list_my_*_campaign_products` only if a row came back. This cubit's only job
/// in that sequence is to start it exactly once per opened id — [open] is
/// idempotent for the id it is already showing, so a rebuild, a router refresh
/// or a theme change issues nothing.
///
/// ## Shared implementation, distinct types
///
/// Same reasoning as [CampaignListCubitBase]: the sequencing, the tokens and
/// the stale-response guard are properties of reading a detail rather than of
/// either contract, while the two concrete classes keep an Owner's repository
/// from being wired into a seller's screen.
abstract base class CampaignDetailCubitBase extends Cubit<CampaignDetailState> {
  CampaignDetailCubitBase(CampaignAudience audience)
    : super(CampaignDetailState(audience: audience));

  /// One read, in whichever contract the subclass owns.
  Future<CampaignDetailOutcome> readCampaign(String campaignId);

  /// Discriminates the answer this cubit is currently waiting for.
  int _token = 0;

  /// Exposed for the isolation tests.
  int get requestToken => _token;

  /// Opens [campaignId], unless it is already open.
  ///
  /// Idempotent for the id currently held in any phase other than `initial`, so
  /// a repeated call from `didUpdateWidget` or a rebuild costs nothing. A
  /// **different** id always re-reads.
  Future<void> open(String campaignId) {
    if (state.campaignId == campaignId &&
        state.phase != CampaignDetailPhase.initial) {
      return Future<void>.value();
    }
    return _fetch(campaignId);
  }

  /// Re-reads the campaign currently open. A no-op before one is.
  Future<void> refresh() {
    final String? campaignId = state.campaignId;
    if (campaignId == null) {
      return Future<void>.value();
    }
    return _fetch(campaignId);
  }

  Future<void> _fetch(String campaignId) async {
    // Re-entry is suppressed only for the id already in flight. A **different**
    // id must always proceed: the cubit is provided at the shell and shared by
    // every detail route, so dropping a second id here would leave one
    // campaign's terms on screen under another campaign's address. The request
    // token below is what makes the superseded read harmless.
    if (state.isLoading && state.campaignId == campaignId) {
      return;
    }

    final int token = ++_token;

    emit(
      CampaignDetailState(
        audience: state.audience,
        campaignId: campaignId,
        phase: CampaignDetailPhase.loading,
        // The previous campaign's fields are dropped rather than kept behind a
        // spinner: this is a different campaign, and showing one campaign's
        // reward under another's name for even one frame is the one thing a
        // detail screen must never do.
      ),
    );

    final CampaignDetailOutcome outcome = await readCampaign(campaignId);

    if (isClosed || token != _token) {
      return;
    }

    switch (outcome.answer) {
      case CampaignDetailAnswer.loaded:
        emit(
          state.copyWith(
            phase: CampaignDetailPhase.ready,
            campaign: outcome.campaign,
            products: outcome.products,
          ),
        );

      case CampaignDetailAnswer.missing:
        // Not a failure, and no retry is offered: the backend answered, and it
        // will answer the same way again.
        emit(state.copyWith(phase: CampaignDetailPhase.notFound));

      case CampaignDetailAnswer.failed:
        emit(
          state.copyWith(
            phase: CampaignDetailPhase.failed,
            problem: outcome.problem ?? RetailerReadProblem.unexpected,
          ),
        );
    }
  }

  /// Drops the campaign, its products, the open id and the problem.
  ///
  /// Called when the signed-in person or the resolved Retailer changes.
  void clear() {
    _token++;
    emit(CampaignDetailState(audience: state.audience));
  }
}

/// The Retailer Owner's campaign detail.
///
/// Reads `get_my_retailer_campaign(uuid)` and, only on a hit,
/// `list_my_retailer_campaign_products(uuid)`.
final class RetailerCampaignDetailCubit extends CampaignDetailCubitBase {
  RetailerCampaignDetailCubit(this._repository)
    : super(CampaignAudience.retailerOwner);

  final RetailerCampaignRepository _repository;

  @override
  Future<CampaignDetailOutcome> readCampaign(String campaignId) async {
    final RetailerCampaignDetailResult result = await _repository
        .campaignDetail(campaignId);

    return switch (result) {
      RetailerCampaignDetailLoaded(
        :final RetailerCampaign campaign,
        :final List<CampaignProduct> products,
      ) =>
        (
          answer: CampaignDetailAnswer.loaded,
          campaign: CampaignPresentation.retailer(campaign),
          products: products,
          problem: null,
        ),
      RetailerCampaignDetailMissing() => (
        answer: CampaignDetailAnswer.missing,
        campaign: null,
        products: const <CampaignProduct>[],
        problem: null,
      ),
      RetailerCampaignDetailFailed(:final RetailerReadProblem problem) => (
        answer: CampaignDetailAnswer.failed,
        campaign: null,
        products: const <CampaignProduct>[],
        problem: problem,
      ),
    };
  }
}

/// The Sales Staff campaign detail.
///
/// Reads `get_my_staff_campaign(uuid)` and, only on a hit,
/// `list_my_staff_campaign_products(uuid)`. Both re-apply the
/// `ACTIVE`/`SCHEDULED` filter server-side, so a seller who addresses a paused
/// campaign directly reaches [CampaignDetailPhase.notFound] — which says
/// nothing about why.
final class SalesStaffCampaignDetailCubit extends CampaignDetailCubitBase {
  SalesStaffCampaignDetailCubit(this._repository)
    : super(CampaignAudience.salesStaff);

  final StaffCampaignRepository _repository;

  @override
  Future<CampaignDetailOutcome> readCampaign(String campaignId) async {
    final StaffCampaignDetailResult result = await _repository.campaignDetail(
      campaignId,
    );

    return switch (result) {
      StaffCampaignDetailLoaded(
        :final StaffCampaign campaign,
        :final List<CampaignProduct> products,
      ) =>
        (
          answer: CampaignDetailAnswer.loaded,
          campaign: CampaignPresentation.staff(campaign),
          products: products,
          problem: null,
        ),
      StaffCampaignDetailMissing() => (
        answer: CampaignDetailAnswer.missing,
        campaign: null,
        products: const <CampaignProduct>[],
        problem: null,
      ),
      StaffCampaignDetailFailed(:final RetailerReadProblem problem) => (
        answer: CampaignDetailAnswer.failed,
        campaign: null,
        products: const <CampaignProduct>[],
        problem: problem,
      ),
    };
  }
}
