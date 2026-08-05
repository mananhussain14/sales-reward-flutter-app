import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/parsing/rpc_row.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_measurement.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_reward.dart';
import 'package:sale_reward/features/rewards/data/models/earnings_parsers.dart';
import 'package:sale_reward/features/rewards/domain/entities/campaign_earnings_summary.dart';
import 'package:sale_reward/features/rewards/domain/entities/campaign_reward_record.dart';
import 'package:sale_reward/features/rewards/domain/entities/campaign_target_progress.dart';

import '../../support/campaign_fakes.dart';
import '../../support/earnings_fakes.dart';

/// The parse boundary for the three deployed earnings contracts.
///
/// These are amounts of money a person believes they have earned, so the tests
/// below are about one thing above all: a value this build cannot read must
/// **fail** rather than become a plausible number.
void main() {
  // -------------------------------------------------------------------------
  group('the seventeen-column reward contract', () {
    test('parses every column the client carries', () {
      final CampaignRewardRecord reward =
          EarningsParsers.parseCampaignRewardRow(campaignRewardRow());

      expect(reward.rewardId, rewardIdA);
      expect(reward.campaignName, 'Summer Push');
      expect(reward.receiptSubmissionId, receiptSubmissionIdA);
      expect(reward.shopName, 'Downtown Branch');
      expect(reward.saleAt, DateTime.utc(2026, 8, 1, 10, 30));
      expect(reward.awardedAt, DateTime.utc(2026, 8, 1, 11));
      expect(reward.ruleType, CampaignRewardRuleType.perUnitCoins);
      expect(reward.performanceScope, CampaignPerformanceScope.individualStaff);
      expect(reward.qualifyingItemCount, 2);
      expect(reward.qualifyingUnits, 3);
      expect(reward.coinsUncapped, 30);
      expect(reward.coinsCappedTo, isNull);
      expect(reward.rewardCoins, 30);
      expect(reward.thresholdUnits, isNull);
      expect(reward.configuredRewardCoins, isNull);
    });

    test('an empty page is a success, never a failure', () {
      expect(EarningsParsers.parseCampaignRewards(<Object?>[]), isEmpty);
    });

    test('receipt_submission_id is preserved as the sale reference', () {
      // It stands in for the verified sale id, which the contract deliberately
      // withholds. Losing it would leave a reward a seller cannot tie to
      // anything they did.
      final CampaignRewardRecord reward =
          EarningsParsers.parseCampaignRewardRow(campaignRewardRow());
      expect(reward.receiptSubmissionId, receiptSubmissionIdA);
      expect(reward.receiptReference, 'ABCD1234');
    });

    test('a malformed receipt id is refused rather than shortened', () {
      expect(
        () => EarningsParsers.parseCampaignRewardRow(
          campaignRewardRow(receiptSubmissionId: 'not-a-uuid'),
        ),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('a null shop is preserved as null, not blanked to a placeholder', () {
      // The contract left-joins `retailer_shops`, so a removed shop is a real
      // null and the card omits the row rather than dashing it.
      final CampaignRewardRecord reward =
          EarningsParsers.parseCampaignRewardRow(
            campaignRewardRow(shopName: null),
          );
      expect(reward.shopName, isNull);
    });

    test('a target reward carries its tier, a per-unit reward does not', () {
      final CampaignRewardRecord target =
          EarningsParsers.parseCampaignRewardRow(targetBonusRewardRow());
      expect(target.ruleType, CampaignRewardRuleType.targetBonus);
      expect(target.thresholdUnits, 25);
      expect(target.configuredRewardCoins, 2500);
    });

    test('a per-unit row carrying a target tier is refused', () {
      // `campaign_rewards_tier_paired` is an equivalence, so this row cannot be
      // stored — it describes two rules at once.
      expect(
        () => EarningsParsers.parseCampaignRewardRow(
          campaignRewardRow(thresholdUnits: 25, configuredRewardCoins: 2500),
        ),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('a target row with no tier is refused', () {
      expect(
        () => EarningsParsers.parseCampaignRewardRow(
          targetBonusRewardRow(thresholdUnits: null),
        ),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('a partially capped reward keeps BOTH stored amounts', () {
      // The migration keeps `coins_uncapped` beside `reward_coins` precisely so
      // a screen can explain the shortfall. Collapsing them here would take the
      // explanation away.
      final CampaignRewardRecord reward =
          EarningsParsers.parseCampaignRewardRow(cappedRewardRow());
      expect(reward.coinsUncapped, 100);
      expect(reward.coinsCappedTo, 40);
      expect(reward.rewardCoins, 40);
      expect(reward.wasReducedByCap, isTrue);
      expect(reward.coinsReducedByCap, 60);
    });

    test('a cap that did not bite is refused', () {
      // `campaign_rewards_capped_range` demands `coins_capped_to <
      // coins_uncapped`: a cap that changed nothing is indistinguishable from
      // no cap, so a row claiming one is not this shape.
      expect(
        () => EarningsParsers.parseCampaignRewardRow(
          cappedRewardRow(coinsUncapped: 100, coinsCappedTo: 100),
        ),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('a reward above its own uncapped amount is refused', () {
      expect(
        () => EarningsParsers.parseCampaignRewardRow(
          campaignRewardRow(coinsUncapped: 30, rewardCoins: 31),
        ),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('a zero reward is kept, because a real one can be zero', () {
      // Locked decision 6: a partial award is legal and `reward_coins` may be 0
      // when the qualification is real and the cap is exhausted.
      final CampaignRewardRecord reward =
          EarningsParsers.parseCampaignRewardRow(
            campaignRewardRow(
              coinsUncapped: 30,
              coinsCappedTo: 0,
              rewardCoins: 0,
            ),
          );
      expect(reward.rewardCoins, 0);
      expect(reward.wasReducedByCap, isTrue);
    });

    test('an unknown rule type is refused, never defaulted', () {
      expect(
        () => EarningsParsers.parseCampaignRewardRow(
          campaignRewardRow(ruleType: 'MYSTERY_RULE'),
        ),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('an unknown performance scope is refused', () {
      expect(
        () => EarningsParsers.parseCampaignRewardRow(
          campaignRewardRow(performanceScope: 'EVERYBODY'),
        ),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('a body that is not a list is refused', () {
      expect(
        () => EarningsParsers.parseCampaignRewards(<String, Object?>{}),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('one malformed row fails the whole page', () {
      // A history quietly short by one reward is worse than one that honestly
      // failed to load.
      expect(
        () => EarningsParsers.parseCampaignRewards(<Object?>[
          campaignRewardRow(),
          campaignRewardRow(campaignName: null),
        ]),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('an unrecognised extra key is ignored', () {
      final Map<String, Object?> row = campaignRewardRow()
        ..['some_future_column'] = 'whatever';
      expect(EarningsParsers.parseCampaignRewardRow(row).rewardCoins, 30);
    });
  });

  // -------------------------------------------------------------------------
  group('numeric safety', () {
    test('an integral double is accepted — JSON has one number type', () {
      expect(
        EarningsParsers.parseCampaignRewardRow(
          campaignRewardRow(coinsUncapped: 30.0, rewardCoins: 30.0),
        ).rewardCoins,
        30,
      );
    });

    test('a fractional amount is refused', () {
      expect(
        () => EarningsParsers.parseCampaignRewardRow(
          campaignRewardRow(coinsUncapped: 30.5, rewardCoins: 30.5),
        ),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('a numeric column arriving as TEXT is refused, never parsed', () {
      // `int.parse` on it would launder a wrong contract into a plausible
      // number.
      expect(
        () => EarningsParsers.parseCampaignRewardRow(
          campaignRewardRow(rewardCoins: '30'),
        ),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('a bigint beyond the safe integer range is refused, not rounded', () {
      // On the web an `int` IS a double, so anything above 2^53-1 is silently
      // rounded. Refusing it on every platform is what makes the two agree.
      expect(
        () => EarningsParsers.parseEarningsSummaryRow(
          earningsSummaryRow(
            totalRewardCoins: rewardSafeIntegerCeiling + 1,
            currentMonthRewardCoins: 0,
          ),
        ),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('exactly the safe ceiling is accepted', () {
      expect(
        EarningsParsers.parseEarningsSummaryRow(
          earningsSummaryRow(
            totalRewardCoins: rewardSafeIntegerCeiling,
            currentMonthRewardCoins: 0,
          ),
        ).totalRewardCoins,
        rewardSafeIntegerCeiling,
      );
    });

    test('an infinite or NaN amount is refused', () {
      for (final double value in <double>[
        double.infinity,
        double.negativeInfinity,
        double.nan,
      ]) {
        expect(
          () => EarningsParsers.parseCampaignRewardRow(
            campaignRewardRow(rewardCoins: value),
          ),
          throwsA(isA<RpcFormatException>()),
          reason: '$value',
        );
      }
    });

    test('a negative coin amount is refused', () {
      expect(
        () => EarningsParsers.parseCampaignRewardRow(
          campaignRewardRow(rewardCoins: -1),
        ),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('units outside the documented one-sale bound are refused', () {
      // `campaign_rewards_units_range` caps one sale's contribution at 5000.
      expect(
        () => EarningsParsers.parseCampaignRewardRow(
          campaignRewardRow(qualifyingUnits: 5001),
        ),
        throwsA(isA<RpcFormatException>()),
      );
      expect(
        () => EarningsParsers.parseCampaignRewardRow(
          campaignRewardRow(qualifyingUnits: 0),
        ),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('an item count above the evaluation bound is refused', () {
      expect(
        () => EarningsParsers.parseCampaignRewardRow(
          campaignRewardRow(qualifyingItemCount: 51),
        ),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('an uncapped amount above the schema ceiling is refused', () {
      expect(
        () => EarningsParsers.parseCampaignRewardRow(
          campaignRewardRow(
            coinsUncapped: rewardUncappedCeiling + 1,
            rewardCoins: 0,
          ),
        ),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('a boolean column arriving as anything else is refused', () {
      for (final Object? value in <Object?>[null, 1, 'true', 't']) {
        expect(
          () => EarningsParsers.parseCampaignTargetProgressRow(
            campaignTargetProgressRow(targetReached: value),
          ),
          throwsA(isA<RpcFormatException>()),
          reason: '$value',
        );
      }
    });
  });

  // -------------------------------------------------------------------------
  group('the earnings summary', () {
    test('parses all seven columns', () {
      final CampaignEarningsSummary? summary =
          EarningsParsers.parseEarningsSummary(<Object?>[earningsSummaryRow()]);

      expect(summary, isNotNull);
      expect(summary!.totalRewardCoins, 2530);
      expect(summary.currentMonthRewardCoins, 530);
      expect(summary.rewardedSaleCount, 4);
      expect(summary.rewardedCampaignCount, 2);
      expect(summary.latestRewardAt, DateTime.utc(2026, 8, 1, 11));
      expect(summary.currentMonthStartUtc, DateTime.utc(2026, 8));
      expect(summary.currentMonthEndUtc, DateTime.utc(2026, 9));
    });

    test('a summary of zeros parses as zeros, not as an error', () {
      final CampaignEarningsSummary? summary =
          EarningsParsers.parseEarningsSummary(<Object?>[
            earningsSummaryRow(
              totalRewardCoins: 0,
              currentMonthRewardCoins: 0,
              rewardedSaleCount: 0,
              rewardedCampaignCount: 0,
              latestRewardAt: null,
            ),
          ]);

      expect(summary, isNotNull);
      expect(summary!.totalRewardCoins, 0);
      expect(summary.currentMonthRewardCoins, 0);
      expect(summary.rewardedSaleCount, 0);
      expect(summary.rewardedCampaignCount, 0);
      expect(summary.latestRewardAt, isNull);
    });

    test('zero rows is null — NOT a summary of zeros', () {
      // "You have earned nothing" and "this surface is not yours" are different
      // statements. The repository turns this null into the second.
      expect(EarningsParsers.parseEarningsSummary(<Object?>[]), isNull);
    });

    test('more than one row is refused', () {
      expect(
        () => EarningsParsers.parseEarningsSummary(<Object?>[
          earningsSummaryRow(),
          earningsSummaryRow(),
        ]),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('a month total above the lifetime total is refused', () {
      // The month figure sums a subset of the same non-negative rows, so it
      // cannot exceed the total. A response where it does is not this shape.
      expect(
        () => EarningsParsers.parseEarningsSummaryRow(
          earningsSummaryRow(totalRewardCoins: 10, currentMonthRewardCoins: 11),
        ),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('a month window that does not advance is refused', () {
      expect(
        () => EarningsParsers.parseEarningsSummaryRow(
          earningsSummaryRow(
            currentMonthStartUtc: '2026-09-01T00:00:00Z',
            currentMonthEndUtc: '2026-09-01T00:00:00Z',
          ),
        ),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('a missing month bound is refused rather than assumed', () {
      expect(
        () => EarningsParsers.parseEarningsSummaryRow(
          earningsSummaryRow(currentMonthStartUtc: null),
        ),
        throwsA(isA<RpcFormatException>()),
      );
    });
  });

  // -------------------------------------------------------------------------
  group('target progress', () {
    test('parses the seven carried columns', () {
      final CampaignTargetProgress progress =
          EarningsParsers.parseCampaignTargetProgressRow(
            campaignTargetProgressRow(),
          );

      expect(progress.campaignId, campaignIdA);
      expect(progress.campaignName, 'Summer Push');
      expect(
        progress.performanceScope,
        CampaignPerformanceScope.individualStaff,
      );
      expect(progress.targetUnits, 25);
      expect(progress.configuredRewardCoins, 2500);
      expect(progress.progressUnits, 12);
      expect(progress.targetReached, isFalse);
      expect(progress.bonusAwardedToMe, isFalse);
    });

    test('an empty list is a success — no target campaign is running', () {
      expect(EarningsParsers.parseCampaignTargetProgress(<Object?>[]), isEmpty);
    });

    test('target_reached is READ, never recomputed from the numbers', () {
      // The database decides it. A client that compared the two numbers would
      // be a second definition of "reached", and the one nobody noticed had
      // drifted. This row is deliberately inconsistent to prove which wins.
      final CampaignTargetProgress progress =
          EarningsParsers.parseCampaignTargetProgressRow(
            campaignTargetProgressRow(progressUnits: 99, targetReached: false),
          );
      expect(progress.progressUnits, 99);
      expect(progress.targetReached, isFalse);
    });

    test('zero progress is preserved — no accumulator row yet', () {
      final CampaignTargetProgress progress =
          EarningsParsers.parseCampaignTargetProgressRow(
            campaignTargetProgressRow(progressUnits: 0),
          );
      expect(progress.progressUnits, 0);
      expect(progress.completionFraction, 0);
    });

    test('the bar fraction is clamped past the target', () {
      final CampaignTargetProgress progress =
          EarningsParsers.parseCampaignTargetProgressRow(
            campaignTargetProgressRow(
              progressUnits: 100,
              targetUnits: 25,
              targetReached: true,
            ),
          );
      expect(progress.completionFraction, 1.0);
    });

    test('a target below one is refused', () {
      expect(
        () => EarningsParsers.parseCampaignTargetProgressRow(
          campaignTargetProgressRow(targetUnits: 0),
        ),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('a malformed campaign id is refused — it is the join key', () {
      expect(
        () => EarningsParsers.parseCampaignTargetProgressRow(
          campaignTargetProgressRow(campaignId: 'nope'),
        ),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('the team-reached-without-me case is representable and derived', () {
      final CampaignTargetProgress progress =
          EarningsParsers.parseCampaignTargetProgressRow(
            campaignTargetProgressRow(
              performanceScope: 'RETAILER_TEAM',
              progressUnits: 30,
              targetReached: true,
              bonusAwardedToMe: false,
            ),
          );
      expect(progress.reachedByTeamWithoutMe, isTrue);

      // And an individual target that was reached without a recorded bonus is
      // NOT that case: there is no team to have taken it.
      final CampaignTargetProgress individual =
          EarningsParsers.parseCampaignTargetProgressRow(
            campaignTargetProgressRow(
              progressUnits: 30,
              targetReached: true,
              bonusAwardedToMe: false,
            ),
          );
      expect(individual.reachedByTeamWithoutMe, isFalse);
    });
  });
}
