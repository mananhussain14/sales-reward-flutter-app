import 'package:equatable/equatable.dart';

import 'campaign_lifecycle_state.dart';
import 'campaign_measurement.dart';
import 'campaign_product_eligibility.dart';
import 'campaign_reward.dart';
import 'campaign_schedule.dart';
import 'campaign_stacking_mode.dart';

/// Everything the Retailer Owner and Sales Staff campaign contracts have in
/// common — which is all of both, minus two columns.
///
/// ## Why one type serves two roles
///
/// The two contracts were written to be the same shape on purpose. The
/// migration says so where it defines the Owner detail read:
///
/// > *THE SHAPE IS DELIBERATELY IDENTICAL to `list_my_retailer_campaigns()` —
/// > same column names, same order, same types, same withheld fields — so one
/// > client-side model deserializes both and a future column has to be added to
/// > both or to neither.*
///
/// The staff pair repeats that shape and drops two columns. So the seventeen
/// shared columns are parsed **once**, here, and the lifecycle grouping, the
/// reward wording, the eligibility wording and the zero-product rule are all
/// written against this type alone. Neither role has its own copy of any of
/// them, which is the property that keeps the two experiences from drifting into
/// two different descriptions of one campaign.
///
/// The two differences live on [RetailerCampaign] and are absent from
/// [StaffCampaign]:
///
/// 1. **`vendor_name`.** The Owner read returns it; the staff read withholds it,
///    *"following `list_my_receipt_products()`: naming the Vendor to a
///    shop-floor seller leaks the supply relationship."*
/// 2. **`campaign_status`.** The Owner read returns the stored management
///    status; the staff read does not.
///
/// ## What is not here, because the backend does not send it
///
/// No Retailer group, no other Retailer, no audience mode, no audience count, no
/// exclusivity key, no priority, no version number, no version id, no snapshot
/// id, no `created_by`, no audit metadata, and no organization id of any kind.
/// The only identifier carried at all is [campaignId], and its sole use is as an
/// address to an authorized read — see [RetailerCampaignRepository].
///
/// ## And no progress, because none exists
///
/// There is no units-sold field, no earned-coins field, no balance and no claim.
/// Every reward value on [reward] is the **offer**. A screen that wants to say
/// what someone has actually earned has nothing here to say it with, which is
/// the intended state until the calculation engine ships.
final class CampaignOffer extends Equatable {
  const CampaignOffer({
    required this.campaignId,
    required this.name,
    required this.description,
    required this.lifecycleState,
    required this.schedule,
    required this.performanceScope,
    required this.rewardRecipientScope,
    required this.productEligibility,
    required this.stackingMode,
    required this.reward,
  });

  /// `campaigns.id`.
  ///
  /// An **address**, and nothing else. It is passed to `get_my_*_campaign` and
  /// `list_my_*_campaign_products`, both of which re-derive the caller's
  /// Retailer from `auth.uid()` and return zero rows for an id that is not
  /// theirs. It is never displayed, never compared against anything to make a
  /// decision, and never sent as evidence of who the caller is.
  final String campaignId;

  /// `campaigns.name`. `NOT NULL`, trimmed, 1–150 characters.
  final String name;

  /// `campaigns.description`. Nullable — a campaign genuinely may have none, and
  /// null is rendered by omitting the section rather than by a placeholder.
  final String? description;

  /// `campaign_derived_state(...)`. Derived by the backend against the server's
  /// clock; never recomputed here.
  final CampaignLifecycleState lifecycleState;

  final CampaignSchedule schedule;

  /// Individual or Retailer-team measurement.
  final CampaignPerformanceScope performanceScope;

  /// Who the reward is paid to. One value in the deployed schema; see
  /// [CampaignRewardRecipientScope] for why it is a type anyway.
  final CampaignRewardRecipientScope rewardRecipientScope;

  /// Which products count, when that was decided, and how many are eligible for
  /// the **reading** Retailer.
  final CampaignProductEligibility productEligibility;

  final CampaignStackingMode stackingMode;

  /// The configured offer. Never an outcome.
  final CampaignReward reward;

  /// Whether the prominent zero-eligible-product notice applies.
  ///
  /// Both halves are required, and each answers a different question:
  ///
  /// * the count is zero — the Retailer has nothing that could earn; and
  /// * the campaign is running or about to — so the emptiness has a consequence.
  ///
  /// A finished, paused or cancelled campaign with zero eligible products gets
  /// no warning: it cannot reward anything either way, and a warning there would
  /// imply an action is available when none is. See
  /// [CampaignLifecycleState.warnsOnEmptyProducts].
  bool get showsEmptyProductWarning =>
      productEligibility.hasNoEligibleProducts &&
      lifecycleState.warnsOnEmptyProducts;

  @override
  List<Object?> get props => <Object?>[
    campaignId,
    name,
    description,
    lifecycleState,
    schedule,
    performanceScope,
    rewardRecipientScope,
    productEligibility,
    stackingMode,
    reward,
  ];
}
