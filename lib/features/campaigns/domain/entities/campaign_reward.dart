import 'package:equatable/equatable.dart';

/// What a campaign's rule counts.
///
/// `campaign_rules.metric_type`, constrained by `campaign_rules_metric_allowed`
/// to a single value. The migration is explicit that the vocabulary was **not**
/// widened in advance:
///
/// > *`UNITS_SOLD` is the only permitted metric: no percentage-of-value reward
/// > exists in this milestone, and admitting the vocabulary for one before the
/// > rounding, currency and reversal decisions are made would be a promise the
/// > schema cannot keep.*
///
/// Carried as a type for the same reason as [CampaignRewardRecipientScope]: the
/// day a value metric is added, every `switch` on this type stops compiling,
/// where a validated string would keep saying "units" about money.
enum CampaignMetricType {
  /// Eligible units sold.
  unitsSold('UNITS_SOLD');

  const CampaignMetricType(this.code);

  final String code;

  /// The metric [raw] names, or null if this build does not recognise it.
  static CampaignMetricType? tryFromCode(String raw) {
    for (final CampaignMetricType metric in values) {
      if (metric.code == raw) {
        return metric;
      }
    }
    return null;
  }
}

/// The shape of a campaign's reward rule.
///
/// `campaign_rules.rule_type`, constrained by `campaign_rules_type_allowed`.
/// Used by the parser to decide which [CampaignReward] variant to build; the
/// variant is what the rest of the application sees.
enum CampaignRewardRuleType {
  /// A rate per eligible unit.
  perUnitCoins('PER_UNIT_COINS'),

  /// A single bonus for reaching a threshold.
  targetBonus('TARGET_BONUS');

  const CampaignRewardRuleType(this.code);

  final String code;

  /// The rule type [raw] names, or null if this build does not recognise it.
  static CampaignRewardRuleType? tryFromCode(String raw) {
    for (final CampaignRewardRuleType type in values) {
      if (type.code == raw) {
        return type;
      }
    }
    return null;
  }
}

/// The largest amount any coin column in the deployed schema may hold.
///
/// `1,000,000,000`, enforced on `coins_per_unit`, `max_reward_coins` and
/// `reward_coins` by three separate `_within_ceiling` constraints. The migration
/// explains the bound as overflow safety for a future reward engine: the largest
/// configurable rate multiplied by more units than any integer column in the
/// schema can hold is still under `bigint` max.
///
/// It is re-applied here as a **parse** rule, not as arithmetic. Nothing in this
/// feature multiplies anything; a value above the ceiling simply cannot have
/// come from the deployed contract, so a response carrying one is not this shape
/// and is refused rather than rendered.
const int campaignCoinCeiling = 1000000000;

/// The **offer** a campaign makes.
///
/// ## This is a configuration, not an outcome
///
/// Every value here is what the Vendor configured: a rate, a target, a bonus, a
/// cap. None of it says what anyone has sold, earned, accrued or been paid. The
/// migration closes on exactly this point —
///
/// > *Nothing in this file matches a receipt to a product, evaluates a rule,
/// > resolves an exclusivity contest, computes progress, credits a coin, moves a
/// > balance, or records a claim or a payout. The reward columns are read and
/// > returned as the OFFER a campaign makes.*
///
/// — and this type carries no progress field, no earned field and no balance
/// field, so no screen can render one and no future edit can add one without
/// changing this file. Every screen that shows a reward also shows
/// `CampaignCopy.engineNotice`, which says the calculation is not connected yet.
///
/// ## Sealed, because the two rules are not the same fact with a flag
///
/// A [CampaignPerUnitReward] has a rate and no target; a [CampaignTargetReward]
/// has a target and a bonus and, by the `campaign_rules_rate_paired`
/// constraint, provably no rate. One class with four nullable numbers would make
/// "a target bonus with a per-unit rate" representable, and every wording branch
/// would have to re-derive which fields to trust.
sealed class CampaignReward extends Equatable {
  const CampaignReward({required this.metric, required this.maxRewardCoins});

  /// What is counted. `UNITS_SOLD` for every rule the deployed schema allows.
  final CampaignMetricType metric;

  /// The optional ceiling on what this rule may pay across the whole campaign
  /// period. Null means uncapped.
  ///
  /// Applies to **either** rule type — the column is on `campaign_rules`, not on
  /// the tier — which is why it lives on this base rather than on one variant.
  final int? maxRewardCoins;

  bool get isCapped => maxRewardCoins != null;
}

/// A rate per eligible unit.
///
/// `coins_per_unit` is `NOT NULL` for this rule type by the
/// `campaign_rules_rate_paired` equivalence, and strictly positive and within
/// the ceiling by two more constraints. All three are re-checked at the parse
/// boundary.
final class CampaignPerUnitReward extends CampaignReward {
  const CampaignPerUnitReward({
    required this.coinsPerUnit,
    required super.maxRewardCoins,
    required super.metric,
  });

  /// Coins earned per eligible unit sold. `1 .. campaignCoinCeiling`.
  final int coinsPerUnit;

  @override
  List<Object?> get props => <Object?>[coinsPerUnit, maxRewardCoins, metric];
}

/// A single bonus for reaching a threshold.
///
/// The threshold and the bonus live on `campaign_rule_tiers` at `tier_number =
/// 1`, which both contracts join. `campaign_rules_rate_paired` guarantees this
/// rule carries **no** `coins_per_unit`, which is why there is no such field
/// here to be null.
///
/// How the threshold should be read depends on the campaign's
/// `CampaignPerformanceScope`, and that is deliberately **not** stored on this
/// type: the same "25 units" is a personal goal under `INDIVIDUAL_STAFF` and a
/// shop-wide one under `RETAILER_TEAM`, and the wording layer already has the
/// scope from the campaign it is describing. Duplicating it here would create
/// two places for the two facts to disagree.
final class CampaignTargetReward extends CampaignReward {
  const CampaignTargetReward({
    required this.thresholdUnits,
    required this.rewardCoins,
    required super.maxRewardCoins,
    required super.metric,
  });

  /// Eligible units that must be reached. `>= 1`.
  final int thresholdUnits;

  /// What reaching the threshold pays. `1 .. campaignCoinCeiling`.
  final int rewardCoins;

  @override
  List<Object?> get props => <Object?>[
    thresholdUnits,
    rewardCoins,
    maxRewardCoins,
    metric,
  ];
}
