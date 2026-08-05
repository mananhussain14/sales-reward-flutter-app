import 'package:equatable/equatable.dart';

import '../../../campaigns/domain/entities/campaign_measurement.dart';

/// One row of `get_my_campaign_target_progress()`.
///
/// ## Only `TARGET_BONUS` campaigns produce one
///
/// The contract joins `campaign_rules ... and r.rule_type = 'TARGET_BONUS'`, so
/// a `PER_UNIT_COINS` campaign has no row here at all — *"a `PER_UNIT_COINS`
/// campaign has no threshold to progress towards, and showing one a progress bar
/// would be inventing a goal the Vendor never set."* Nothing in this client
/// restates that rule; a campaign with no row simply gets no progress indicator.
///
/// ## What the contract deliberately withholds, and is therefore absent here
///
/// * **No `cap_subject_type` and no `cap_subject_id`.** They are internal
///   accumulator keys. There is no field for either, so no screen can render
///   one.
/// * **No `target_bonus_awarded`.** It is a per-*subject* flag: under
///   `RETAILER_TEAM` it goes true when **any** team member crosses, which a
///   seller would read as "I was paid". [bonusAwardedToMe] is the column that
///   arrives instead, reconstructed in SQL from the existence of a
///   `TARGET_BONUS` reward whose beneficiary is the caller.
/// * **No `coins_awarded_total`.** Under `RETAILER_TEAM` it is the whole team's
///   coins and would be mistaken for personal earnings. The earnings summary is
///   the only place a coin total belongs.
///
/// ## `campaign_version_id` is returned and not carried
///
/// The contract returns it; nothing here holds it, so no version key can reach
/// state or a screen. [campaignId] is the join key the campaign list and the
/// campaign detail both use, and it is the only identifier this type carries.
final class CampaignTargetProgress extends Equatable {
  const CampaignTargetProgress({
    required this.campaignId,
    required this.campaignName,
    required this.performanceScope,
    required this.targetUnits,
    required this.configuredRewardCoins,
    required this.progressUnits,
    required this.targetReached,
    required this.bonusAwardedToMe,
  });

  /// The campaign this progress belongs to.
  ///
  /// The **only** safe join key between this contract and
  /// `list_my_staff_campaigns()`. Both reads apply the same frozen
  /// `campaign_eligible_retailers` targeting, the same published-version join
  /// and the same `ACTIVE`/`SCHEDULED` filter, *"so the rows join one-to-one on
  /// campaign_id"*. Joining on a name would collapse two campaigns that happen
  /// to share one.
  final String campaignId;

  /// Carried for the earnings-side screens and for the semantic label, never to
  /// re-identify the campaign. [campaignId] is what joins.
  final String campaignName;

  /// Whose units [progressUnits] counts.
  ///
  /// `INDIVIDUAL_STAFF` → the signed-in seller's own qualifying units.
  /// `RETAILER_TEAM` → the whole Retailer's. The distinction decides every word
  /// on the indicator, which is why the contract returns it.
  final CampaignPerformanceScope performanceScope;

  /// `campaign_rule_tiers.threshold_units`. At least 1 in the schema.
  final int targetUnits;

  /// `campaign_rule_tiers.reward_coins` — what the Vendor **configured** for
  /// crossing the target. Not what anyone was paid.
  final int configuredRewardCoins;

  /// `campaign_subject_accumulators.units_counted_total`, or 0 when no
  /// qualifying sale has been applied yet.
  ///
  /// A `bigint` in the contract, so it is read through the safe-integer reader
  /// rather than assumed to fit.
  final int progressUnits;

  /// Whether the subject has reached [targetUnits].
  ///
  /// **Read, never recomputed.** The database decides this; comparing
  /// [progressUnits] against [targetUnits] here would put a second definition of
  /// "reached" on the device, and the client's copy would be the one nobody
  /// noticed had drifted.
  final bool targetReached;

  /// Whether a `TARGET_BONUS` reward exists whose beneficiary is the caller.
  ///
  /// The single fact that lets a team target be described truthfully: under
  /// `RETAILER_TEAM` the target can be reached by the team while somebody else
  /// took the bonus, and this is false in exactly that case.
  final bool bonusAwardedToMe;

  /// Whether the target was reached but the bonus went to another team member.
  ///
  /// Two stored booleans and no arithmetic. It exists so the wording rule lives
  /// in one place rather than being re-derived at every call site.
  bool get reachedByTeamWithoutMe =>
      targetReached && !bonusAwardedToMe && performanceScope.isTeam;

  /// How full a progress bar should be drawn, `0.0`–`1.0`.
  ///
  /// A **display ratio**, not a reward calculation: nothing downstream of it
  /// decides whether anything was earned. [targetReached] and
  /// [bonusAwardedToMe] carry every claim about money, and both are the
  /// database's.
  ///
  /// Clamped, because [progressUnits] legitimately exceeds [targetUnits] once a
  /// target has been passed and a bar past its end draws nothing meaningful.
  double get completionFraction {
    if (targetUnits < 1) {
      return 0;
    }
    final double ratio = progressUnits / targetUnits;
    return ratio.clamp(0.0, 1.0);
  }

  @override
  List<Object?> get props => <Object?>[
    campaignId,
    campaignName,
    performanceScope,
    targetUnits,
    configuredRewardCoins,
    progressUnits,
    targetReached,
    bonusAwardedToMe,
  ];
}
