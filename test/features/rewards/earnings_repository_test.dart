import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sale_reward/core/errors/retailer_read_problem.dart';
import 'package:sale_reward/features/rewards/data/datasources/staff_earnings_rpc_data_source.dart';
import 'package:sale_reward/features/rewards/data/repositories/supabase_staff_earnings_repository.dart';
import 'package:sale_reward/features/rewards/domain/entities/campaign_earnings_summary.dart';
import 'package:sale_reward/features/rewards/domain/repositories/staff_earnings_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/earnings_fakes.dart';

/// Records what each RPC was asked, so a test can prove the client sends a page
/// size and a cursor and **nothing else**.
class _Recorder {
  final List<({int limit, DateTime? beforeAwardedAt, String? beforeRewardId})>
  rewardRequests =
      <({int limit, DateTime? beforeAwardedAt, String? beforeRewardId})>[];
  int summaryCalls = 0;
  int progressCalls = 0;
}

void main() {
  late _Recorder recorder;

  setUp(() => recorder = _Recorder());

  StaffEarningsRpcDataSource source({
    Object? Function()? rewards,
    Object? Function()? summary,
    Object? Function()? progress,
    Future<Object?> Function()? rewardsFuture,
  }) {
    return StaffEarningsRpcDataSource(
      rewards:
          ({
            required int limit,
            DateTime? beforeAwardedAt,
            String? beforeRewardId,
          }) {
            recorder.rewardRequests.add((
              limit: limit,
              beforeAwardedAt: beforeAwardedAt,
              beforeRewardId: beforeRewardId,
            ));
            if (rewardsFuture != null) {
              return rewardsFuture();
            }
            return Future<Object?>.value(
              rewards?.call() ?? <Object?>[campaignRewardRow()],
            );
          },
      summary: () {
        recorder.summaryCalls++;
        return Future<Object?>.value(
          summary?.call() ?? <Object?>[earningsSummaryRow()],
        );
      },
      targetProgress: () {
        recorder.progressCalls++;
        return Future<Object?>.value(
          progress?.call() ?? <Object?>[campaignTargetProgressRow()],
        );
      },
    );
  }

  // -------------------------------------------------------------------------
  group('the exact deployed contract names', () {
    test('the three RPC names are the deployed ones, verbatim', () {
      expect(staffCampaignRewardsRpc, 'get_my_campaign_rewards');
      expect(staffEarningsSummaryRpc, 'get_my_campaign_earnings_summary');
      expect(staffCampaignTargetProgressRpc, 'get_my_campaign_target_progress');
    });

    test('the three parameter names are the deployed ones, verbatim', () {
      expect(rewardLimitParam, 'p_limit');
      expect(rewardBeforeAwardedAtParam, 'p_before_awarded_at');
      expect(rewardBeforeRewardIdParam, 'p_before_reward_id');
    });
  });

  // -------------------------------------------------------------------------
  group('the reward history read', () {
    test('parses a page into a loaded result', () async {
      final StaffCampaignRewardsResult result =
          await SupabaseStaffEarningsRepository(
            rpc: source(),
          ).getMyCampaignRewards(limit: campaignRewardPageSize);

      expect(result, isA<StaffCampaignRewardsLoaded>());
      expect((result as StaffCampaignRewardsLoaded).rewards, hasLength(1));
      expect(recorder.rewardRequests, hasLength(1));
    });

    test('the FIRST request carries null cursors', () async {
      await SupabaseStaffEarningsRepository(
        rpc: source(),
      ).getMyCampaignRewards(limit: campaignRewardPageSize);

      expect(recorder.rewardRequests.single.beforeAwardedAt, isNull);
      expect(recorder.rewardRequests.single.beforeRewardId, isNull);
      expect(recorder.rewardRequests.single.limit, campaignRewardPageSize);
    });

    test('an older request carries BOTH cursor halves', () async {
      final DateTime cursorAt = DateTime.utc(2026, 8, 1, 11);

      await SupabaseStaffEarningsRepository(rpc: source()).getMyCampaignRewards(
        limit: campaignRewardPageSize,
        beforeAwardedAt: cursorAt,
        beforeRewardId: rewardIdA,
      );

      expect(recorder.rewardRequests.single.beforeAwardedAt, cursorAt);
      expect(recorder.rewardRequests.single.beforeRewardId, rewardIdA);
    });

    test('half a cursor is reset to none rather than sent', () async {
      // The deployed guard answers a half cursor with the FIRST page, which a
      // screen appending it would render as duplicated rows.
      final SupabaseStaffEarningsRepository repository =
          SupabaseStaffEarningsRepository(rpc: source());

      await repository.getMyCampaignRewards(
        limit: campaignRewardPageSize,
        beforeAwardedAt: DateTime.utc(2026, 8, 1, 11),
      );
      await repository.getMyCampaignRewards(
        limit: campaignRewardPageSize,
        beforeRewardId: rewardIdA,
      );

      for (final r in recorder.rewardRequests) {
        expect(r.beforeAwardedAt, isNull);
        expect(r.beforeRewardId, isNull);
      }
    });

    test('a full page reports that another may exist', () async {
      final StaffCampaignRewardsResult result =
          await SupabaseStaffEarningsRepository(
            rpc: source(
              rewards: () => <Object?>[
                campaignRewardRow(campaignRewardId: rewardIdA),
                campaignRewardRow(campaignRewardId: rewardIdB),
              ],
            ),
          ).getMyCampaignRewards(limit: 2);

      expect((result as StaffCampaignRewardsLoaded).hasMore, isTrue);
    });

    test('a short page reports the end of the history', () async {
      final StaffCampaignRewardsResult result =
          await SupabaseStaffEarningsRepository(
            rpc: source(rewards: () => <Object?>[campaignRewardRow()]),
          ).getMyCampaignRewards(limit: 20);

      expect((result as StaffCampaignRewardsLoaded).hasMore, isFalse);
    });

    test('an empty page is a success, never a failure', () async {
      final StaffCampaignRewardsResult result =
          await SupabaseStaffEarningsRepository(
            rpc: source(rewards: () => <Object?>[]),
          ).getMyCampaignRewards(limit: campaignRewardPageSize);

      expect(result, isA<StaffCampaignRewardsLoaded>());
      expect((result as StaffCampaignRewardsLoaded).rewards, isEmpty);
      expect(result.hasMore, isFalse);
    });

    test('an unreadable response is malformed, never an empty page', () async {
      final StaffCampaignRewardsResult result =
          await SupabaseStaffEarningsRepository(
            rpc: source(rewards: () => <Object?>['not a row']),
          ).getMyCampaignRewards(limit: campaignRewardPageSize);

      expect(
        (result as StaffCampaignRewardsFailed).problem,
        RetailerReadProblem.malformed,
      );
    });
  });

  // -------------------------------------------------------------------------
  group('the summary read', () {
    test('parses one row into a loaded result', () async {
      final StaffEarningsSummaryResult result =
          await SupabaseStaffEarningsRepository(
            rpc: source(),
          ).getMyCampaignEarningsSummary();

      expect(
        (result as StaffEarningsSummaryLoaded).summary.totalRewardCoins,
        2530,
      );
      expect(recorder.summaryCalls, 1);
    });

    test('zero rows is UNAVAILABLE, not a summary of zeros', () async {
      final StaffEarningsSummaryResult result =
          await SupabaseStaffEarningsRepository(
            rpc: source(summary: () => <Object?>[]),
          ).getMyCampaignEarningsSummary();

      expect(result, isA<StaffEarningsSummaryUnavailable>());
    });

    test('a genuine row of zeros stays a loaded summary', () async {
      final StaffEarningsSummaryResult result =
          await SupabaseStaffEarningsRepository(
            rpc: source(
              summary: () => <Object?>[
                earningsSummaryRow(
                  totalRewardCoins: 0,
                  currentMonthRewardCoins: 0,
                  rewardedSaleCount: 0,
                  rewardedCampaignCount: 0,
                  latestRewardAt: null,
                ),
              ],
            ),
          ).getMyCampaignEarningsSummary();

      final CampaignEarningsSummary summary =
          (result as StaffEarningsSummaryLoaded).summary;
      expect(summary.totalRewardCoins, 0);
      expect(summary.latestRewardAt, isNull);
    });
  });

  // -------------------------------------------------------------------------
  group('the target-progress read', () {
    test('parses rows and keys them by campaign id', () async {
      final StaffCampaignTargetProgressResult result =
          await SupabaseStaffEarningsRepository(
            rpc: source(),
          ).getMyCampaignTargetProgress();

      final StaffCampaignTargetProgressLoaded loaded =
          result as StaffCampaignTargetProgressLoaded;
      expect(loaded.progress, hasLength(1));
      expect(loaded.byCampaignId.keys, <String>[
        loaded.progress.single.campaignId,
      ]);
      expect(recorder.progressCalls, 1);
    });

    test('an empty list is a success', () async {
      final StaffCampaignTargetProgressResult result =
          await SupabaseStaffEarningsRepository(
            rpc: source(progress: () => <Object?>[]),
          ).getMyCampaignTargetProgress();

      expect((result as StaffCampaignTargetProgressLoaded).progress, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  group('errors are classified, never rendered', () {
    test('42501 is a denial on every one of the three reads', () async {
      const PostgrestException denied = PostgrestException(
        message: 'permission denied for function get_my_campaign_rewards',
        code: '42501',
      );

      final SupabaseStaffEarningsRepository repository =
          SupabaseStaffEarningsRepository(
            rpc: StaffEarningsRpcDataSource(
              rewards:
                  ({
                    required int limit,
                    DateTime? beforeAwardedAt,
                    String? beforeRewardId,
                  }) => Future<Object?>.error(denied),
              summary: () => Future<Object?>.error(denied),
              targetProgress: () => Future<Object?>.error(denied),
            ),
          );

      expect(
        ((await repository.getMyCampaignRewards(limit: 20))
                as StaffCampaignRewardsFailed)
            .problem,
        RetailerReadProblem.denied,
      );
      expect(
        ((await repository.getMyCampaignEarningsSummary())
                as StaffEarningsSummaryFailed)
            .problem,
        RetailerReadProblem.denied,
      );
      expect(
        ((await repository.getMyCampaignTargetProgress())
                as StaffCampaignTargetProgressFailed)
            .problem,
        RetailerReadProblem.denied,
      );
    });

    test('an expired session is signedOut rather than a denial', () async {
      final StaffEarningsSummaryResult result =
          await SupabaseStaffEarningsRepository(
            rpc: StaffEarningsRpcDataSource(
              rewards:
                  ({
                    required int limit,
                    DateTime? beforeAwardedAt,
                    String? beforeRewardId,
                  }) => Future<Object?>.value(<Object?>[]),
              summary: () =>
                  Future<Object?>.error(const AuthException('JWT expired')),
              targetProgress: () => Future<Object?>.value(<Object?>[]),
            ),
          ).getMyCampaignEarningsSummary();

      expect(
        (result as StaffEarningsSummaryFailed).problem,
        RetailerReadProblem.signedOut,
      );
    });

    test('a transport failure is a network problem', () async {
      final StaffCampaignRewardsResult result =
          await SupabaseStaffEarningsRepository(
            rpc: source(
              rewardsFuture: () =>
                  Future<Object?>.error(http.ClientException('no route')),
            ),
          ).getMyCampaignRewards(limit: 20);

      expect(
        (result as StaffCampaignRewardsFailed).problem,
        RetailerReadProblem.network,
      );
    });

    test('a slow call is abandoned at the read timeout', () async {
      final StaffCampaignRewardsResult result =
          await SupabaseStaffEarningsRepository(
            rpc: source(
              rewardsFuture: () => Future<Object?>.delayed(
                const Duration(milliseconds: 50),
                () => <Object?>[campaignRewardRow()],
              ),
            ),
            timeout: const Duration(milliseconds: 1),
          ).getMyCampaignRewards(limit: 20);

      expect(
        (result as StaffCampaignRewardsFailed).problem,
        RetailerReadProblem.timeout,
      );
    });

    test('no problem member carries backend text', () {
      // The taxonomy is an enum. There is no field on it that could hold a
      // Postgres message, a SQLSTATE or an RPC name, which is what makes it
      // structurally impossible for one to reach a screen.
      for (final RetailerReadProblem problem in RetailerReadProblem.values) {
        expect(problem.name, isNotEmpty);
      }
      expect(RetailerReadProblem.values, hasLength(6));
    });
  });
}
