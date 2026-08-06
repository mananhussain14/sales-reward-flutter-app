import 'package:equatable/equatable.dart';

import '../../../../campaigns/presentation/shared/campaign_presentation.dart';
import '../../../../rewards/domain/entities/campaign_target_progress.dart';

/// One campaign as the Sales Staff home shows it: the offer, and the seller's
/// progress towards it when the backend returned a row.
///
/// The two halves come from two contracts on two permissions and are joined on
/// the **campaign id**, never on the name — two campaigns may share a name and
/// only the id is the key both reads return.
final class SalesStaffOpportunity extends Equatable {
  const SalesStaffOpportunity({required this.campaign, required this.progress});

  final CampaignPresentation campaign;

  /// Null for a `PER_UNIT_COINS` campaign, which has no threshold to progress
  /// towards, and for a session where the progress read has not run.
  final CampaignTargetProgress? progress;

  bool get isRunning => campaign.offer.lifecycleState.isRunning;

  bool get hasTarget => progress != null;

  @override
  List<Object?> get props => <Object?>[campaign, progress];
}

/// Pairs each campaign with its progress row, preserving the backend's order.
///
/// `list_my_staff_campaigns()` returns soonest-first and that order is carried
/// through untouched: this function zips, it does not sort.
List<SalesStaffOpportunity> buildOpportunities(
  List<CampaignPresentation> campaigns,
  CampaignTargetProgress? Function(String campaignId) progressFor,
) {
  return <SalesStaffOpportunity>[
    for (final CampaignPresentation campaign in campaigns)
      SalesStaffOpportunity(
        campaign: campaign,
        progress: progressFor(campaign.offer.campaignId),
      ),
  ];
}

/// The one campaign the home screen leads with.
///
/// ## A presentation rule, not a recommendation
///
/// Three ordered preferences, each a filter over the list the backend already
/// ordered:
///
/// 1. the first **running** campaign that has a target progress row;
/// 2. otherwise the first **running** campaign;
/// 3. otherwise the first campaign of any state.
///
/// Nothing is scored, ranked, weighted or compared against another campaign,
/// and nothing about the reading seller enters the choice. A campaign that is
/// first here is first because the backend returned it first — which is the
/// only ordering this application has any authority to present.
///
/// In particular the rule does **not** prefer an unreached target over a
/// reached one. That would be a judgement about which reward is worth more
/// attention, and the contract gives no basis for one.
///
/// Returns null only when there is nothing to show at all.
SalesStaffOpportunity? selectHeroOpportunity(
  List<SalesStaffOpportunity> opportunities,
) {
  if (opportunities.isEmpty) {
    return null;
  }

  for (final SalesStaffOpportunity opportunity in opportunities) {
    if (opportunity.isRunning && opportunity.hasTarget) {
      return opportunity;
    }
  }
  for (final SalesStaffOpportunity opportunity in opportunities) {
    if (opportunity.isRunning) {
      return opportunity;
    }
  }
  return opportunities.first;
}

/// Everything except the hero, in the backend's order.
///
/// The hero is removed by **identity** rather than by id: a list that somehow
/// carried the same campaign twice would lose only the instance actually shown
/// above, which is the behaviour a reader expects from "and the rest".
List<SalesStaffOpportunity> remainingOpportunities(
  List<SalesStaffOpportunity> opportunities,
  SalesStaffOpportunity? hero,
) {
  if (hero == null) {
    return opportunities;
  }
  return <SalesStaffOpportunity>[
    for (final SalesStaffOpportunity opportunity in opportunities)
      if (!identical(opportunity, hero)) opportunity,
  ];
}
