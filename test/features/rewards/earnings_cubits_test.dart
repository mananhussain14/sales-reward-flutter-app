import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/retailer_read_problem.dart';
import 'package:sale_reward/features/rewards/domain/entities/campaign_reward_record.dart';
import 'package:sale_reward/features/rewards/domain/entities/campaign_target_progress.dart';
import 'package:sale_reward/features/rewards/domain/repositories/staff_earnings_repository.dart';
import 'package:sale_reward/features/rewards/presentation/bloc/campaign_earnings_cubit.dart';
import 'package:sale_reward/features/rewards/presentation/bloc/campaign_target_progress_cubit.dart';

import '../../support/campaign_fakes.dart';
import '../../support/earnings_fakes.dart';

void main() {
  late FakeStaffEarningsRepository repository;

  setUp(() => repository = FakeStaffEarningsRepository());

  SalesStaffEarningsCubit earningsCubit({int pageSize = 2}) {
    final SalesStaffEarningsCubit cubit = SalesStaffEarningsCubit(
      repository,
      pageSize: pageSize,
    );
    addTearDown(cubit.close);
    return cubit;
  }

  SalesStaffCampaignProgressCubit progressCubit() {
    final SalesStaffCampaignProgressCubit cubit =
        SalesStaffCampaignProgressCubit(repository);
    addTearDown(cubit.close);
    return cubit;
  }

  // -------------------------------------------------------------------------
  group('the earnings cubit reads both contracts', () {
    test('one load issues exactly one summary and one first page', () async {
      final SalesStaffEarningsCubit cubit = earningsCubit();
      await cubit.load();

      expect(repository.summaryCallCount, 1);
      expect(repository.rewardCallCount, 1);
      expect(cubit.state.phase, EarningsPhase.ready);
      expect(cubit.state.summary, isNotNull);
      expect(cubit.state.rewards, hasLength(1));
    });

    test('the first page carries NO cursor', () async {
      await earningsCubit().load();

      expect(repository.rewardRequests.single.beforeAwardedAt, isNull);
      expect(repository.rewardRequests.single.beforeRewardId, isNull);
    });

    test('the page size is fixed and inside the contract ceiling', () async {
      // The deployed function clamps p_limit to 1..100.
      final SalesStaffEarningsCubit cubit = SalesStaffEarningsCubit(repository);
      addTearDown(cubit.close);
      await cubit.load();

      expect(campaignRewardPageSize, 20);
      expect(repository.rewardRequests.single.limit, campaignRewardPageSize);
      expect(campaignRewardPageSize, lessThanOrEqualTo(100));
    });

    test('loadOnce reads once, and not again on a second call', () async {
      final SalesStaffEarningsCubit cubit = earningsCubit();
      await cubit.loadOnce();
      await cubit.loadOnce();

      expect(repository.rewardCallCount, 1);
    });

    test('a zero summary is held as zeros, not as an error', () async {
      repository.summaryResult = StaffEarningsSummaryLoaded(
        zeroEarningsSummary(),
      );
      final SalesStaffEarningsCubit cubit = earningsCubit();
      await cubit.load();

      expect(cubit.state.summary!.totalRewardCoins, 0);
      expect(cubit.state.summaryProblem, isNull);
      expect(cubit.state.summaryUnavailable, isFalse);
    });

    test('zero summary rows becomes the unavailable state', () async {
      repository.summaryResult = const StaffEarningsSummaryUnavailable();
      final SalesStaffEarningsCubit cubit = earningsCubit();
      await cubit.load();

      expect(cubit.state.summaryUnavailable, isTrue);
      expect(cubit.state.summary, isNull);
    });

    test('an empty history is a real answer, not a failure', () async {
      repository.firstPageResult = const StaffCampaignRewardsLoaded(
        rewards: <CampaignRewardRecord>[],
        hasMore: false,
      );
      final SalesStaffEarningsCubit cubit = earningsCubit();
      await cubit.load();

      expect(cubit.state.hasNoRewards, isTrue);
      expect(cubit.state.rewardsProblem, isNull);
      expect(cubit.state.canLoadOlder, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  group('the two reads cannot erase each other', () {
    test('a failed summary leaves the rewards on screen', () async {
      repository.summaryResult = const StaffEarningsSummaryFailed(
        RetailerReadProblem.unexpected,
      );
      final SalesStaffEarningsCubit cubit = earningsCubit();
      await cubit.load();

      expect(cubit.state.summary, isNull);
      expect(cubit.state.summaryProblem, RetailerReadProblem.unexpected);
      expect(cubit.state.rewards, hasLength(1));
    });

    test('a failed history leaves the totals on screen', () async {
      repository.firstPageResult = const StaffCampaignRewardsFailed(
        RetailerReadProblem.timeout,
      );
      final SalesStaffEarningsCubit cubit = earningsCubit();
      await cubit.load();

      expect(cubit.state.summary, isNotNull);
      expect(cubit.state.rewards, isNull);
      expect(cubit.state.historyFailedOutright, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  group('keyset pagination', () {
    Future<SalesStaffEarningsCubit> loadedWithTwoPages() async {
      repository.firstPageResult = StaffCampaignRewardsLoaded(
        rewards: <CampaignRewardRecord>[
          exampleReward(
            rewardId: rewardIdA,
            awardedAt: DateTime.utc(2026, 8, 5),
          ),
          exampleReward(
            rewardId: rewardIdB,
            awardedAt: DateTime.utc(2026, 8, 4),
          ),
        ],
        hasMore: true,
      );
      repository.olderPageResult = StaffCampaignRewardsLoaded(
        rewards: <CampaignRewardRecord>[
          exampleReward(
            rewardId: rewardIdC,
            awardedAt: DateTime.utc(2026, 8, 3),
          ),
        ],
        hasMore: false,
      );

      final SalesStaffEarningsCubit cubit = earningsCubit();
      await cubit.load();
      return cubit;
    }

    test('an older page passes BOTH the timestamp and the reward id', () async {
      final SalesStaffEarningsCubit cubit = await loadedWithTwoPages();
      await cubit.loadOlder();

      final RecordedRewardRequest older = repository.rewardRequests.last;
      // The cursor is the LAST row already shown — exactly the row the
      // contract's strict `<` predicate must exclude.
      expect(older.beforeAwardedAt, DateTime.utc(2026, 8, 4));
      expect(older.beforeRewardId, rewardIdB);
      expect(older.limit, 2);
    });

    test('the older page is appended, not replaced', () async {
      final SalesStaffEarningsCubit cubit = await loadedWithTwoPages();
      await cubit.loadOlder();

      expect(
        cubit.state.rewards!.map((CampaignRewardRecord r) => r.rewardId),
        <String>[rewardIdA, rewardIdB, rewardIdC],
      );
    });

    test('a short older page hides the control', () async {
      final SalesStaffEarningsCubit cubit = await loadedWithTwoPages();
      expect(cubit.state.canLoadOlder, isTrue);

      await cubit.loadOlder();

      expect(cubit.state.canLoadOlder, isFalse);
      expect(cubit.state.reachedEndOfHistory, isTrue);
    });

    test('a duplicate reward id is never added twice', () async {
      final SalesStaffEarningsCubit cubit = await loadedWithTwoPages();
      // A page that repeats a row already on screen — impossible through the
      // strict keyset predicate, and filtered anyway.
      repository.olderPageResult = StaffCampaignRewardsLoaded(
        rewards: <CampaignRewardRecord>[
          exampleReward(
            rewardId: rewardIdB,
            awardedAt: DateTime.utc(2026, 8, 4),
          ),
          exampleReward(
            rewardId: rewardIdC,
            awardedAt: DateTime.utc(2026, 8, 3),
          ),
        ],
        hasMore: false,
      );

      await cubit.loadOlder();

      expect(
        cubit.state.rewards!.map((CampaignRewardRecord r) => r.rewardId),
        <String>[rewardIdA, rewardIdB, rewardIdC],
      );
    });

    test(
      'a second press while a page is in flight issues one request',
      () async {
        final SalesStaffEarningsCubit cubit = await loadedWithTwoPages();

        repository.manual = true;
        final int before = repository.rewardCallCount;

        final Future<void> first = cubit.loadOlder();
        final Future<void> second = cubit.loadOlder();

        expect(repository.rewardCallCount, before + 1);

        repository.completeRewards(
          StaffCampaignRewardsLoaded(
            rewards: <CampaignRewardRecord>[exampleReward(rewardId: rewardIdC)],
            hasMore: false,
          ),
        );
        await first;
        await second;

        expect(repository.rewardCallCount, before + 1);
      },
    );

    test('a pagination failure preserves the rewards AND the totals', () async {
      final SalesStaffEarningsCubit cubit = await loadedWithTwoPages();
      repository.olderPageResult = const StaffCampaignRewardsFailed(
        RetailerReadProblem.network,
      );

      await cubit.loadOlder();

      expect(cubit.state.rewards, hasLength(2));
      expect(cubit.state.summary, isNotNull);
      expect(cubit.state.olderProblem, RetailerReadProblem.network);
      // The button stays available, because the page that failed can be
      // retried.
      expect(cubit.state.canLoadOlder, isTrue);
    });

    test(
      'loadOlder is a no-op when there is nothing behind the list',
      () async {
        final SalesStaffEarningsCubit cubit = earningsCubit();
        await cubit.load();
        final int before = repository.rewardCallCount;

        await cubit.loadOlder();

        expect(repository.rewardCallCount, before);
      },
    );

    test('a refresh restarts from the newest reward, with no cursor', () async {
      final SalesStaffEarningsCubit cubit = await loadedWithTwoPages();
      await cubit.loadOlder();

      await cubit.refresh();

      expect(repository.rewardRequests.last.beforeAwardedAt, isNull);
      expect(repository.rewardRequests.last.beforeRewardId, isNull);
    });

    test('no request ever carries an offset — there is no such parameter', () {
      // Stated structurally: the recorded request type has exactly three
      // fields, and none of them is an offset or a page number.
      const RecordedRewardRequest request = (
        limit: 20,
        beforeAwardedAt: null,
        beforeRewardId: null,
      );
      expect(request.limit, 20);
    });
  });

  // -------------------------------------------------------------------------
  group('session isolation', () {
    test('clear empties the totals, the history and the cursor', () async {
      final SalesStaffEarningsCubit cubit = earningsCubit();
      await cubit.load();
      expect(cubit.state.summary, isNotNull);

      cubit.clear();

      expect(cubit.state.summary, isNull);
      expect(cubit.state.rewards, isNull);
      expect(cubit.state.cursor, isNull);
      expect(cubit.state.phase, EarningsPhase.initial);
    });

    test('an answer arriving after a clear is dropped', () async {
      repository.manual = true;
      final SalesStaffEarningsCubit cubit = earningsCubit();

      final Future<void> inFlight = cubit.load();
      cubit.clear();
      repository.completeRewards();
      await inFlight;

      expect(cubit.state.rewards, isNull);
      expect(cubit.state.phase, EarningsPhase.initial);
    });
  });

  // -------------------------------------------------------------------------
  group('the target-progress cubit', () {
    test('keys the rows by campaign id', () async {
      repository.progressResult = StaffCampaignTargetProgressLoaded(
        <CampaignTargetProgress>[
          exampleTargetProgress(campaignId: campaignIdA),
          exampleTargetProgress(campaignId: campaignIdB, campaignName: 'Other'),
        ],
      );
      final SalesStaffCampaignProgressCubit cubit = progressCubit();
      await cubit.load();

      expect(cubit.state.forCampaign(campaignIdA), isNotNull);
      expect(cubit.state.forCampaign(campaignIdB), isNotNull);
      expect(
        cubit.state.forCampaign('11111111-1111-4111-8111-111111111111'),
        isNull,
      );
    });

    test('two campaigns sharing a NAME stay distinct', () async {
      // Joining by name would collapse them. The id is the key.
      repository.progressResult =
          StaffCampaignTargetProgressLoaded(<CampaignTargetProgress>[
            exampleTargetProgress(
              campaignId: campaignIdA,
              campaignName: 'Summer Push',
              progressUnits: 5,
            ),
            exampleTargetProgress(
              campaignId: campaignIdB,
              campaignName: 'Summer Push',
              progressUnits: 20,
            ),
          ]);
      final SalesStaffCampaignProgressCubit cubit = progressCubit();
      await cubit.load();

      expect(cubit.state.forCampaign(campaignIdA)!.progressUnits, 5);
      expect(cubit.state.forCampaign(campaignIdB)!.progressUnits, 20);
    });

    test('an empty answer is ready with no rows, never a failure', () async {
      final SalesStaffCampaignProgressCubit cubit = progressCubit();
      await cubit.load();

      expect(cubit.state.phase, CampaignTargetProgressPhase.ready);
      expect(cubit.state.byCampaignId, isEmpty);
      expect(cubit.state.hasFailedOutright, isFalse);
    });

    test('a failure with nothing loaded is reported as such', () async {
      repository.progressResult = const StaffCampaignTargetProgressFailed(
        RetailerReadProblem.unexpected,
      );
      final SalesStaffCampaignProgressCubit cubit = progressCubit();
      await cubit.load();

      expect(cubit.state.hasFailedOutright, isTrue);
      // And still returns null for every campaign, so no bar is drawn from a
      // read that did not happen.
      expect(cubit.state.forCampaign(campaignIdA), isNull);
    });

    test('loadOnce reads once', () async {
      final SalesStaffCampaignProgressCubit cubit = progressCubit();
      await cubit.loadOnce();
      await cubit.loadOnce();

      expect(repository.progressCallCount, 1);
    });

    test('clear empties the progress and advances the token', () async {
      final SalesStaffCampaignProgressCubit cubit = progressCubit();
      await cubit.load();
      final int token = cubit.requestToken;

      cubit.clear();

      expect(cubit.state.byCampaignId, isNull);
      expect(cubit.state.phase, CampaignTargetProgressPhase.initial);
      expect(cubit.requestToken, greaterThan(token));
    });
  });
}
