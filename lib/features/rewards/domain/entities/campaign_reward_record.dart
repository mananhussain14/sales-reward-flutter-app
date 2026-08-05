import 'package:equatable/equatable.dart';

import '../../../campaigns/domain/entities/campaign_measurement.dart';
import '../../../campaigns/domain/entities/campaign_reward.dart';

/// The keyset cursor into `get_my_campaign_rewards()`.
///
/// ## Both halves, or neither
///
/// The contract's predicate is `(w.awarded_at, w.id) < (p_before_awarded_at,
/// p_before_reward_id)`, and it is guarded by
/// `p_before_awarded_at is null or p_before_reward_id is null or (...)` — so
/// supplying **one** of the two silently returns the first page again, forever.
///
/// Holding the pair in a single type is what makes that unrepresentable: there
/// is no way to construct half a cursor, so no caller can accidentally send one.
final class CampaignRewardCursor extends Equatable {
  const CampaignRewardCursor({required this.awardedAt, required this.rewardId});

  /// The `awarded_at` of the last row already shown.
  final DateTime awardedAt;

  /// That row's `campaign_reward_id`, which is what makes the ordering total —
  /// two rewards awarded in the same instant cannot tie, so no row is visited
  /// twice and none is skipped.
  final String rewardId;

  @override
  List<Object?> get props => <Object?>[awardedAt, rewardId];
}

/// One row of the deployed seventeen-column `get_my_campaign_rewards()`
/// contract.
///
/// ## Every reward here is the caller's own
///
/// The contract filters on `beneficiary_profile_id = sales_staff_earnings_profile()`
/// and takes **no** parameter that names a person — *"no seller can reach
/// another's by any combination of arguments, because there is no argument that
/// names a person."* There is no beneficiary field on this type for the same
/// reason: every row is the reader's, so naming one would be noise at best.
///
/// ## What is absent, and why it matters
///
/// * **No `verified_sale_id`.** Migration 69 exists to keep that key out of a
///   client, resolving it in SQL from the receipt instead; the contract does not
///   return it, and there is no field here that could hold one.
/// * **No `campaign_sale_evaluation_id`, `cap_subject_type` or
///   `cap_subject_id`.** Internal evaluation and accumulator keys. Not returned,
///   not held.
/// * **No `campaign_version_id`.** Returned by the contract and deliberately not
///   carried — a version key addresses nothing this application can read, and
///   the same choice is recorded for `product_id` in the campaign product
///   parser.
///
/// [receiptSubmissionId] is the safe sale reference that arrives in place of the
/// verified sale: it is unique per verified sale, the seller submitted that
/// receipt themselves, and they already read it through
/// `get_my_receipt_submission`.
///
/// ## Nothing here computes a reward
///
/// [coinsUncapped], [coinsCappedTo] and [rewardCoins] are three **stored**
/// values. `reward_coins = coalesce(coins_capped_to, coins_uncapped)` is an
/// identity the table enforces, and this type asserts nothing about it and
/// re-derives none of it. [coinsReducedByCap] subtracts two stored values purely
/// to *describe* a difference the reader can already see; it decides nothing.
final class CampaignRewardRecord extends Equatable {
  const CampaignRewardRecord({
    required this.rewardId,
    required this.campaignName,
    required this.receiptSubmissionId,
    required this.shopName,
    required this.saleAt,
    required this.awardedAt,
    required this.ruleType,
    required this.performanceScope,
    required this.qualifyingItemCount,
    required this.qualifyingUnits,
    required this.coinsUncapped,
    required this.coinsCappedTo,
    required this.rewardCoins,
    required this.thresholdUnits,
    required this.configuredRewardCoins,
  });

  /// `campaign_reward_id`. Held because it is half the keyset cursor and
  /// because it is what de-duplicates an appended page. **Never rendered.**
  final String rewardId;

  final String campaignName;

  /// `receipt_submission_id` — the safe reference to the sale this reward paid
  /// on.
  ///
  /// Rendered **shortened**, never as a whole UUID, and never as a link: this
  /// application has no authorized Sales Staff receipt-detail route that takes
  /// a submission id from a reward, and adding one is a different feature.
  final String receiptSubmissionId;

  /// The shop the sale happened in, or null — the contract left-joins
  /// `retailer_shops`, so a shop that has since been removed yields null rather
  /// than dropping the reward.
  final String? shopName;

  /// `verified_sales.sale_at` — when the sale happened.
  final DateTime saleAt;

  /// When the reward was recorded. The primary sort key, and half the cursor.
  final DateTime awardedAt;

  /// Which rule paid: a per-unit rate, or a single target bonus.
  final CampaignRewardRuleType ruleType;

  /// Whether the campaign measured this seller or the whole Retailer team.
  ///
  /// Copied onto the reward row by the evaluator, so it is the scope that was in
  /// force when the reward was made rather than whatever the campaign says now.
  final CampaignPerformanceScope performanceScope;

  /// How many receipt lines qualified. From the evaluation, `0..50`.
  final int qualifyingItemCount;

  /// `units_counted` — the units this sale contributed, `1..5000`.
  final int qualifyingUnits;

  /// What the rule alone produced, before any cap.
  final int coinsUncapped;

  /// The ceiling the remaining headroom allowed, or null when no cap bit.
  ///
  /// Non-null **only** when a cap actually reduced the award: the schema refuses
  /// a `coins_capped_to` that is not strictly below [coinsUncapped], because a
  /// cap that changed nothing is indistinguishable from no cap.
  final int? coinsCappedTo;

  /// The authoritative payable amount. May legitimately be `0` when the
  /// qualification was real and the campaign cap was exhausted.
  final int rewardCoins;

  /// The target this bonus crossed, for a `TARGET_BONUS` row. Null for a
  /// per-unit row — the schema pairs the two exactly.
  final int? thresholdUnits;

  /// The bonus the Vendor configured, for a `TARGET_BONUS` row. Null for a
  /// per-unit row.
  final int? configuredRewardCoins;

  /// Whether the campaign maximum reduced this reward.
  ///
  /// The presence of [coinsCappedTo] is the database's own record of that, so
  /// this reads a stored fact rather than comparing amounts.
  bool get wasReducedByCap => coinsCappedTo != null;

  /// How many coins the cap removed.
  ///
  /// A subtraction of two **stored** values, used only to describe a difference
  /// that is already on screen. It is not a reward calculation: it decides
  /// nothing, and [rewardCoins] remains the only authoritative amount.
  int get coinsReducedByCap => coinsUncapped - rewardCoins;

  /// The first segment of the receipt reference, upper-cased.
  ///
  /// Eight hexadecimal characters is enough for a seller to match a reward
  /// against a receipt in their own history and far short of a value anybody
  /// could address something with.
  String get receiptReference {
    final String head = receiptSubmissionId.split('-').first;
    return head.toUpperCase();
  }

  @override
  List<Object?> get props => <Object?>[
    rewardId,
    campaignName,
    receiptSubmissionId,
    shopName,
    saleAt,
    awardedAt,
    ruleType,
    performanceScope,
    qualifyingItemCount,
    qualifyingUnits,
    coinsUncapped,
    coinsCappedTo,
    rewardCoins,
    thresholdUnits,
    configuredRewardCoins,
  ];
}
