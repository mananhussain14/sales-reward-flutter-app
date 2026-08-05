import 'dart:async';

import 'package:sale_reward/features/campaigns/domain/entities/campaign_measurement.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_reward.dart';
import 'package:sale_reward/features/rewards/domain/entities/campaign_earnings_summary.dart';
import 'package:sale_reward/features/rewards/domain/entities/campaign_reward_record.dart';
import 'package:sale_reward/features/rewards/domain/entities/campaign_target_progress.dart';
import 'package:sale_reward/features/rewards/domain/repositories/staff_earnings_repository.dart';

import 'campaign_fakes.dart';

// ---------------------------------------------------------------------------
// Raw rows, in the exact shape PostgREST renders the deployed contracts.
// ---------------------------------------------------------------------------

/// Well-formed reward ids, distinct so a pagination test can tell pages apart.
const String rewardIdA = '9a9a9a9a-1111-4222-8333-444444444444';
const String rewardIdB = '8b8b8b8b-1111-4222-8333-444444444444';
const String rewardIdC = '7c7c7c7c-1111-4222-8333-444444444444';

/// A well-formed receipt submission id.
const String receiptSubmissionIdA = 'abcd1234-5678-4999-8aaa-bbbbccccdddd';

/// One row of the deployed seventeen-column `get_my_campaign_rewards()`.
///
/// Every key the `returns table` clause declares — **including** the two the
/// client deliberately does not read, so a test can prove they are ignored
/// rather than merely absent from the fixture.
///
/// Defaults form a coherent `PER_UNIT_COINS` reward with no cap: 3 units at 10
/// coins each, uncapped and final both 30.
///
/// There is deliberately no `verified_sale_id` key and no
/// `beneficiary_profile_id` key: the contract returns neither, and a fixture
/// that invented one would let a test pass over a shape the backend cannot
/// produce.
Map<String, Object?> campaignRewardRow({
  Object? campaignRewardId = rewardIdA,
  Object? campaignId = campaignIdA,
  Object? campaignVersionId = 'cccccccc-1111-4222-8333-444444444444',
  Object? campaignName = 'Summer Push',
  Object? receiptSubmissionId = receiptSubmissionIdA,
  Object? shopName = 'Downtown Branch',
  Object? saleAt = '2026-08-01T10:30:00Z',
  Object? awardedAt = '2026-08-01T11:00:00Z',
  Object? ruleType = 'PER_UNIT_COINS',
  Object? performanceScope = 'INDIVIDUAL_STAFF',
  Object? qualifyingItemCount = 2,
  Object? qualifyingUnits = 3,
  Object? coinsUncapped = 30,
  Object? coinsCappedTo,
  Object? rewardCoins = 30,
  Object? thresholdUnits,
  Object? configuredRewardCoins,
}) {
  return <String, Object?>{
    'campaign_reward_id': campaignRewardId,
    'campaign_id': campaignId,
    'campaign_version_id': campaignVersionId,
    'campaign_name': campaignName,
    'receipt_submission_id': receiptSubmissionId,
    'shop_name': shopName,
    'sale_at': saleAt,
    'awarded_at': awardedAt,
    'rule_type': ruleType,
    'performance_scope': performanceScope,
    'qualifying_item_count': qualifyingItemCount,
    'qualifying_units': qualifyingUnits,
    'coins_uncapped': coinsUncapped,
    'coins_capped_to': coinsCappedTo,
    'reward_coins': rewardCoins,
    'threshold_units': thresholdUnits,
    'configured_reward_coins': configuredRewardCoins,
  };
}

/// A `TARGET_BONUS` reward row, with the tier half the schema pairs with it.
Map<String, Object?> targetBonusRewardRow({
  Object? campaignRewardId = rewardIdB,
  Object? thresholdUnits = 25,
  Object? configuredRewardCoins = 2500,
  Object? coinsUncapped = 2500,
  Object? coinsCappedTo,
  Object? rewardCoins = 2500,
  Object? performanceScope = 'RETAILER_TEAM',
}) {
  return campaignRewardRow(
    campaignRewardId: campaignRewardId,
    campaignName: 'Winter Target',
    ruleType: 'TARGET_BONUS',
    performanceScope: performanceScope,
    thresholdUnits: thresholdUnits,
    configuredRewardCoins: configuredRewardCoins,
    coinsUncapped: coinsUncapped,
    coinsCappedTo: coinsCappedTo,
    rewardCoins: rewardCoins,
  );
}

/// A partially capped `PER_UNIT_COINS` reward: 100 uncapped, reduced to 40.
Map<String, Object?> cappedRewardRow({
  Object? campaignRewardId = rewardIdC,
  Object? coinsUncapped = 100,
  Object? coinsCappedTo = 40,
  Object? rewardCoins = 40,
}) {
  return campaignRewardRow(
    campaignRewardId: campaignRewardId,
    qualifyingUnits: 10,
    coinsUncapped: coinsUncapped,
    coinsCappedTo: coinsCappedTo,
    rewardCoins: rewardCoins,
  );
}

/// One row of `get_my_campaign_earnings_summary()`.
Map<String, Object?> earningsSummaryRow({
  Object? totalRewardCoins = 2530,
  Object? currentMonthRewardCoins = 530,
  Object? rewardedSaleCount = 4,
  Object? rewardedCampaignCount = 2,
  Object? latestRewardAt = '2026-08-01T11:00:00Z',
  Object? currentMonthStartUtc = '2026-08-01T00:00:00Z',
  Object? currentMonthEndUtc = '2026-09-01T00:00:00Z',
}) {
  return <String, Object?>{
    'total_reward_coins': totalRewardCoins,
    'current_month_reward_coins': currentMonthRewardCoins,
    'rewarded_sale_count': rewardedSaleCount,
    'rewarded_campaign_count': rewardedCampaignCount,
    'latest_reward_at': latestRewardAt,
    'current_month_start_utc': currentMonthStartUtc,
    'current_month_end_utc': currentMonthEndUtc,
  };
}

/// One row of `get_my_campaign_target_progress()`.
///
/// Carries `campaign_version_id`, which the client deliberately does not read.
Map<String, Object?> campaignTargetProgressRow({
  Object? campaignId = campaignIdA,
  Object? campaignVersionId = 'cccccccc-1111-4222-8333-444444444444',
  Object? campaignName = 'Summer Push',
  Object? performanceScope = 'INDIVIDUAL_STAFF',
  Object? targetUnits = 25,
  Object? configuredRewardCoins = 2500,
  Object? progressUnits = 12,
  Object? targetReached = false,
  Object? bonusAwardedToMe = false,
}) {
  return <String, Object?>{
    'campaign_id': campaignId,
    'campaign_version_id': campaignVersionId,
    'campaign_name': campaignName,
    'performance_scope': performanceScope,
    'target_units': targetUnits,
    'configured_reward_coins': configuredRewardCoins,
    'progress_units': progressUnits,
    'target_reached': targetReached,
    'bonus_awarded_to_me': bonusAwardedToMe,
  };
}

// ---------------------------------------------------------------------------
// Domain builders, for tests above the parser.
// ---------------------------------------------------------------------------

CampaignEarningsSummary exampleEarningsSummary({
  int totalRewardCoins = 2530,
  int currentMonthRewardCoins = 530,
  int rewardedSaleCount = 4,
  int rewardedCampaignCount = 2,
  DateTime? latestRewardAt,

  /// Builds the never-rewarded case — `latest_reward_at` genuinely null — which
  /// a null [latestRewardAt] cannot express, because null there means "use the
  /// default".
  bool neverRewarded = false,
}) {
  return CampaignEarningsSummary(
    totalRewardCoins: totalRewardCoins,
    currentMonthRewardCoins: currentMonthRewardCoins,
    rewardedSaleCount: rewardedSaleCount,
    rewardedCampaignCount: rewardedCampaignCount,
    latestRewardAt: neverRewarded
        ? null
        : (latestRewardAt ?? DateTime.utc(2026, 8, 1, 11)),
    currentMonthStartUtc: DateTime.utc(2026, 8),
    currentMonthEndUtc: DateTime.utc(2026, 9),
  );
}

/// A summary of zeros — the true answer for a seller who has earned nothing.
CampaignEarningsSummary zeroEarningsSummary() => exampleEarningsSummary(
  totalRewardCoins: 0,
  currentMonthRewardCoins: 0,
  rewardedSaleCount: 0,
  rewardedCampaignCount: 0,
  neverRewarded: true,
);

CampaignRewardRecord exampleReward({
  String rewardId = rewardIdA,
  String campaignName = 'Summer Push',
  String receiptSubmissionId = receiptSubmissionIdA,
  String? shopName = 'Downtown Branch',
  DateTime? saleAt,
  DateTime? awardedAt,
  CampaignRewardRuleType ruleType = CampaignRewardRuleType.perUnitCoins,
  CampaignPerformanceScope performanceScope =
      CampaignPerformanceScope.individualStaff,
  int qualifyingItemCount = 2,
  int qualifyingUnits = 3,
  int coinsUncapped = 30,
  int? coinsCappedTo,
  int rewardCoins = 30,
  int? thresholdUnits,
  int? configuredRewardCoins,
}) {
  return CampaignRewardRecord(
    rewardId: rewardId,
    campaignName: campaignName,
    receiptSubmissionId: receiptSubmissionId,
    shopName: shopName,
    saleAt: saleAt ?? DateTime.utc(2026, 8, 1, 10, 30),
    awardedAt: awardedAt ?? DateTime.utc(2026, 8, 1, 11),
    ruleType: ruleType,
    performanceScope: performanceScope,
    qualifyingItemCount: qualifyingItemCount,
    qualifyingUnits: qualifyingUnits,
    coinsUncapped: coinsUncapped,
    coinsCappedTo: coinsCappedTo,
    rewardCoins: rewardCoins,
    thresholdUnits: thresholdUnits,
    configuredRewardCoins: configuredRewardCoins,
  );
}

/// A `TARGET_BONUS` reward, with the tier half the schema pairs with it.
CampaignRewardRecord exampleTargetBonusReward({
  String rewardId = rewardIdB,
  int thresholdUnits = 25,
  int configuredRewardCoins = 2500,
  int coinsUncapped = 2500,
  int? coinsCappedTo,
  int rewardCoins = 2500,
}) {
  return exampleReward(
    rewardId: rewardId,
    campaignName: 'Winter Target',
    ruleType: CampaignRewardRuleType.targetBonus,
    performanceScope: CampaignPerformanceScope.retailerTeam,
    coinsUncapped: coinsUncapped,
    coinsCappedTo: coinsCappedTo,
    rewardCoins: rewardCoins,
    thresholdUnits: thresholdUnits,
    configuredRewardCoins: configuredRewardCoins,
  );
}

/// A partially capped reward: 100 uncapped, reduced to 40.
CampaignRewardRecord exampleCappedReward({String rewardId = rewardIdC}) =>
    exampleReward(
      rewardId: rewardId,
      qualifyingUnits: 10,
      coinsUncapped: 100,
      coinsCappedTo: 40,
      rewardCoins: 40,
    );

CampaignTargetProgress exampleTargetProgress({
  String campaignId = campaignIdA,
  String campaignName = 'Summer Push',
  CampaignPerformanceScope performanceScope =
      CampaignPerformanceScope.individualStaff,
  int targetUnits = 25,
  int configuredRewardCoins = 2500,
  int progressUnits = 12,
  bool targetReached = false,
  bool bonusAwardedToMe = false,
}) {
  return CampaignTargetProgress(
    campaignId: campaignId,
    campaignName: campaignName,
    performanceScope: performanceScope,
    targetUnits: targetUnits,
    configuredRewardCoins: configuredRewardCoins,
    progressUnits: progressUnits,
    targetReached: targetReached,
    bonusAwardedToMe: bonusAwardedToMe,
  );
}

/// The case the milestone singles out: the **team** crossed the target and
/// somebody else took the bonus.
CampaignTargetProgress teamProgressBonusToSomebodyElse({
  String campaignId = campaignIdA,
}) => exampleTargetProgress(
  campaignId: campaignId,
  performanceScope: CampaignPerformanceScope.retailerTeam,
  progressUnits: 30,
  targetReached: true,
  bonusAwardedToMe: false,
);

// ---------------------------------------------------------------------------
// Repository fake.
// ---------------------------------------------------------------------------

/// What one call to [FakeStaffEarningsRepository.getMyCampaignRewards]
/// transmitted.
///
/// Recorded so a test can prove the FIRST request carries null cursors, that an
/// older request carries **both** halves, and that the page size is fixed —
/// which are the three properties keyset pagination depends on.
typedef RecordedRewardRequest = ({
  int limit,
  DateTime? beforeAwardedAt,
  String? beforeRewardId,
});

/// A hand-written [StaffEarningsRepository] fake.
///
/// Hand-written rather than mocked because these tests care about *how many
/// times* each contract was asked and *with what*, as much as what came back.
///
/// [manual] makes the reward read stay pending until completed by hand, so "a
/// second press while a page is in flight" and "an answer arriving after a
/// session change" are deterministic rather than a sleep-and-hope.
class FakeStaffEarningsRepository implements StaffEarningsRepository {
  StaffEarningsSummaryResult? summaryResult;
  StaffCampaignTargetProgressResult? progressResult;

  /// The answer for a request with **no** cursor.
  StaffCampaignRewardsResult? firstPageResult;

  /// The answer for a request that carries one. Falls back to
  /// [firstPageResult] when unset.
  StaffCampaignRewardsResult? olderPageResult;

  int summaryCallCount = 0;
  int progressCallCount = 0;
  int rewardCallCount = 0;

  bool manual = false;

  final List<RecordedRewardRequest> rewardRequests = <RecordedRewardRequest>[];

  final List<Completer<StaffCampaignRewardsResult>> _pendingRewards =
      <Completer<StaffCampaignRewardsResult>>[];

  int get pendingRewardCount => _pendingRewards.length;

  void completeRewards([StaffCampaignRewardsResult? override]) =>
      completeRewardsAt(0, override);

  void completeRewardsAt(int index, [StaffCampaignRewardsResult? override]) {
    _pendingRewards
        .removeAt(index)
        .complete(
          override ??
              firstPageResult ??
              StaffCampaignRewardsLoaded(
                rewards: <CampaignRewardRecord>[exampleReward()],
                hasMore: false,
              ),
        );
  }

  @override
  Future<StaffCampaignRewardsResult> getMyCampaignRewards({
    required int limit,
    DateTime? beforeAwardedAt,
    String? beforeRewardId,
  }) {
    rewardCallCount++;
    rewardRequests.add((
      limit: limit,
      beforeAwardedAt: beforeAwardedAt,
      beforeRewardId: beforeRewardId,
    ));

    if (manual) {
      final Completer<StaffCampaignRewardsResult> completer =
          Completer<StaffCampaignRewardsResult>();
      _pendingRewards.add(completer);
      return completer.future;
    }

    final bool isOlder = beforeAwardedAt != null && beforeRewardId != null;
    return Future<StaffCampaignRewardsResult>.value(
      (isOlder ? olderPageResult : null) ??
          firstPageResult ??
          StaffCampaignRewardsLoaded(
            rewards: <CampaignRewardRecord>[exampleReward()],
            hasMore: false,
          ),
    );
  }

  @override
  Future<StaffEarningsSummaryResult> getMyCampaignEarningsSummary() {
    summaryCallCount++;
    return Future<StaffEarningsSummaryResult>.value(
      summaryResult ?? StaffEarningsSummaryLoaded(exampleEarningsSummary()),
    );
  }

  @override
  Future<StaffCampaignTargetProgressResult> getMyCampaignTargetProgress() {
    progressCallCount++;
    return Future<StaffCampaignTargetProgressResult>.value(
      progressResult ??
          const StaffCampaignTargetProgressLoaded(<CampaignTargetProgress>[]),
    );
  }
}
