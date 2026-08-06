import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sale_reward/app/shells/retailer_manager/retailer_manager_navigation.dart';
import 'package:sale_reward/app/shells/retailer_owner/retailer_owner_navigation.dart';
import 'package:sale_reward/app/shells/sales_staff/sales_staff_navigation.dart';
import 'package:sale_reward/app/shells/vendor/vendor_navigation.dart';
import 'package:sale_reward/core/errors/retailer_read_problem.dart';
import 'package:sale_reward/core/widgets/widgets.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_measurement.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_product_eligibility.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_product.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_reward.dart';
import 'package:sale_reward/features/campaigns/domain/entities/staff_campaign.dart';
import 'package:sale_reward/features/campaigns/domain/repositories/staff_campaign_repository.dart';
import 'package:sale_reward/features/campaigns/presentation/shared/campaign_card.dart';
import 'package:sale_reward/features/campaigns/presentation/shared/campaign_copy.dart';
import 'package:sale_reward/features/campaigns/presentation/shared/campaign_detail_view.dart';
import 'package:sale_reward/features/rewards/domain/entities/campaign_reward_record.dart';
import 'package:sale_reward/features/rewards/domain/entities/campaign_target_progress.dart';
import 'package:sale_reward/features/rewards/domain/repositories/staff_earnings_repository.dart';
import 'package:sale_reward/features/rewards/presentation/pages/sales_staff_earnings_page.dart';
import 'package:sale_reward/features/rewards/presentation/widgets/campaign_reward_card.dart';
import 'package:sale_reward/features/rewards/presentation/widgets/campaign_target_progress_view.dart';
import 'package:sale_reward/features/rewards/presentation/widgets/earnings_copy.dart';

import '../../support/campaign_fakes.dart';
import '../../support/earnings_fakes.dart';
import '../../support/pump_app.dart';

/// Drives the Sales Staff campaigns-and-earnings experience through the real
/// application: real router, real shell, real cubits, over fakes that never
/// touch Supabase.
void main() {
  Future<void> goTo(WidgetTester tester, String location) async {
    GoRouter.of(tester.element(find.byType(Navigator).first)).go(location);
    await tester.pumpAndSettle();
  }

  String currentLocation(WidgetTester tester) => GoRouter.of(
    tester.element(find.byType(Navigator).first),
  ).routeInformationProvider.value.uri.path;

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder semanticsContaining(String fragment) => find.byWidgetPredicate(
    (Widget widget) =>
        widget is Semantics &&
        (widget.properties.label?.contains(fragment) ?? false),
    description: 'Semantics whose label contains "$fragment"',
  );

  /// Every rendered `Text` on screen, joined — for asserting that a phrase is
  /// **absent** without depending on where it would have been.
  String visibleText(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((Text t) => t.data ?? '')
      .join('\n');

  // =========================================================================
  group('navigation', () {
    testWidgets('a seller sees both new destinations', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.salesStaff);

      expect(find.text('Campaigns'), findsWidgets);
      expect(find.text('Earnings'), findsWidgets);
    });

    testWidgets('the existing Receipts destinations are preserved', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.salesStaff);

      expect(find.text('Submit'), findsWidgets);
      expect(find.text('History'), findsWidgets);
      // Home is the landing tab now; Submit and History keep their routes and
      // their places in the bar.
      expect(currentLocation(tester), SalesStaffNavigation.home);
    });

    testWidgets('the Earnings destination routes to the earnings screen', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.salesStaff);

      await goTo(tester, SalesStaffNavigation.earnings);

      expect(find.byType(SalesStaffEarningsPage), findsOneWidget);
      expect(find.text(EarningsCopy.title), findsWidgets);
    });

    testWidgets('no other role offers an earnings destination', (
      WidgetTester tester,
    ) async {
      // Navigation is not authorization — STAFF_EARNINGS_VIEW is re-decided in
      // SQL on every read — but offering the entry would advertise a capability
      // the database will not grant.
      for (final List<dynamic> destinations in <List<dynamic>>[
        VendorNavigation.model.destinations,
        RetailerOwnerNavigation.model.destinations,
        RetailerManagerNavigation.model.destinations,
      ]) {
        for (final dynamic destination in destinations) {
          expect(
            (destination.label as String).toLowerCase(),
            isNot(contains('earning')),
          );
          expect(
            (destination.path as String?) ?? '',
            isNot(contains('earnings')),
          );
        }
      }
    });

    testWidgets('no other role can reach the earnings route by URL', (
      WidgetTester tester,
    ) async {
      for (final PortalKind role in <PortalKind>[
        PortalKind.vendorSuperAdmin,
        PortalKind.retailerOwner,
        PortalKind.retailerManager,
      ]) {
        await pumpAppInRole(tester, role);
        await goTo(tester, SalesStaffNavigation.earnings);

        expect(find.byType(SalesStaffEarningsPage), findsNothing);
        expect(
          currentLocation(tester),
          isNot(startsWith(SalesStaffNavigation.prefix)),
          reason: '$role',
        );
      }
    });

    testWidgets('the landing screen issues exactly one pair of reads', (
      WidgetTester tester,
    ) async {
      final FakeStaffEarningsRepository earnings =
          FakeStaffEarningsRepository();
      await pumpAppInRole(
        tester,
        PortalKind.salesStaff,
        staffEarnings: earnings,
      );

      // The shell lands on Home, which renders the earnings summary — so the
      // pair is read exactly once, on arrival, by the screen that shows it.
      // The cubits are still not loaded by the shell itself.
      expect(earnings.summaryCallCount, 1);
      expect(earnings.rewardCallCount, 1);

      // Opening the tab reads nothing more: `loadOnce` is a no-op once the
      // phase has left `initial`.
      await goTo(tester, SalesStaffNavigation.earnings);
      expect(earnings.summaryCallCount, 1);
      expect(earnings.rewardCallCount, 1);

      // Leaving and returning reads nothing either.
      await goTo(tester, SalesStaffNavigation.submit);
      await goTo(tester, SalesStaffNavigation.earnings);
      expect(earnings.summaryCallCount, 1);
      expect(earnings.rewardCallCount, 1);
    });
  });

  // =========================================================================
  group('the earnings summary', () {
    Future<FakeStaffEarningsRepository> openEarnings(
      WidgetTester tester, {
      FakeStaffEarningsRepository? earnings,
    }) async {
      final FakeStaffEarningsRepository repository =
          earnings ?? FakeStaffEarningsRepository();
      await pumpAppInRole(
        tester,
        PortalKind.salesStaff,
        staffEarnings: repository,
      );
      await goTo(tester, SalesStaffNavigation.earnings);
      return repository;
    }

    testWidgets('the five totals are rendered from the stored values', (
      WidgetTester tester,
    ) async {
      await openEarnings(tester);

      expect(find.text(EarningsCopy.totalCoinsLabel), findsOneWidget);
      // The hero carries the unit; the supporting tiles carry bare counts.
      expect(find.text(EarningsCopy.coins(2530)), findsOneWidget);

      expect(find.text(EarningsCopy.currentMonthLabel), findsOneWidget);
      expect(find.text('530'), findsOneWidget);

      expect(find.text(EarningsCopy.rewardedSalesLabel), findsOneWidget);
      expect(find.text('4'), findsOneWidget);

      expect(find.text(EarningsCopy.rewardedCampaignsLabel), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      expect(find.text(EarningsCopy.latestRewardLabel), findsOneWidget);
      expect(find.text('1 Aug 2026'), findsWidgets);
    });

    testWidgets('a zero summary renders zeros, not errors or placeholders', (
      WidgetTester tester,
    ) async {
      final FakeStaffEarningsRepository earnings = FakeStaffEarningsRepository()
        ..summaryResult = StaffEarningsSummaryLoaded(zeroEarningsSummary());
      await openEarnings(tester, earnings: earnings);

      // The hero at zero coins, three tiles at zero, and a latest-reward line
      // that says so in words. Zero is a real answer and renders as zero.
      expect(find.text(EarningsCopy.coins(0)), findsOneWidget);
      expect(find.text('0'), findsNWidgets(3));
      expect(find.text(EarningsCopy.latestRewardNever), findsOneWidget);
      expect(find.text('Unavailable'), findsNothing);
    });

    testWidgets('the wallet notice is shown', (WidgetTester tester) async {
      await openEarnings(tester);

      expect(find.text(EarningsCopy.walletNotice), findsOneWidget);
    });

    testWidgets('no value is labelled as a balance or a payout', (
      WidgetTester tester,
    ) async {
      await openEarnings(tester);

      // The notice is the ONE place these words legitimately appear — it names
      // wallet, payout and redemption in order to say none of them exists yet.
      // Everywhere else on the screen they are forbidden, so it is removed
      // before the scan rather than special-cased inside it.
      expect(find.text(EarningsCopy.walletNotice), findsOneWidget);
      final String rendered = visibleText(
        tester,
      ).toLowerCase().replaceAll(EarningsCopy.walletNotice.toLowerCase(), '');

      for (final String forbidden in <String>[
        'wallet',
        'balance',
        'redeem',
        'paid coins',
        'withdraw',
        'payout',
        'cash out',
        'ledger',
        'credit',
      ]) {
        expect(rendered, isNot(contains(forbidden)), reason: forbidden);
      }
    });

    testWidgets('zero summary rows shows a refusal, not a summary of zeros', (
      WidgetTester tester,
    ) async {
      final FakeStaffEarningsRepository earnings = FakeStaffEarningsRepository()
        ..summaryResult = const StaffEarningsSummaryUnavailable();
      await openEarnings(tester, earnings: earnings);

      expect(find.byType(SrRetailerProblemView), findsWidgets);
      expect(find.text(EarningsCopy.totalCoinsLabel), findsNothing);
    });
  });

  // =========================================================================
  group('the reward history', () {
    Future<void> openWith(
      WidgetTester tester,
      List<CampaignRewardRecord> rewards, {
      bool hasMore = false,
    }) async {
      final FakeStaffEarningsRepository earnings = FakeStaffEarningsRepository()
        ..firstPageResult = StaffCampaignRewardsLoaded(
          rewards: rewards,
          hasMore: hasMore,
        );
      await pumpAppInRole(
        tester,
        PortalKind.salesStaff,
        staffEarnings: earnings,
      );
      await goTo(tester, SalesStaffNavigation.earnings);
    }

    testWidgets('a per-unit reward shows units, amounts and the receipt', (
      WidgetTester tester,
    ) async {
      await openWith(tester, <CampaignRewardRecord>[exampleReward()]);

      expect(find.byType(CampaignRewardCard), findsOneWidget);
      expect(find.text('Summer Push'), findsWidgets);
      expect(
        find.text(EarningsCopy.ruleLabel(CampaignRewardRuleType.perUnitCoins)),
        findsOneWidget,
      );
      expect(find.text('3 units'), findsOneWidget);
      expect(find.text('2 products'), findsOneWidget);
      expect(find.text('30 coins'), findsOneWidget);
      // The receipt reference, shortened — never the whole submission id.
      expect(find.text('ABCD1234'), findsOneWidget);
      expect(find.text(receiptSubmissionIdA), findsNothing);
    });

    testWidgets('a partially capped reward shows both amounts and the reason', (
      WidgetTester tester,
    ) async {
      await openWith(tester, <CampaignRewardRecord>[exampleCappedReward()]);

      // BOTH stored values, and the sentence that names the difference.
      expect(find.text('100 coins'), findsOneWidget);
      expect(find.text('40 coins'), findsOneWidget);
      expect(find.text(EarningsCopy.reducedByCap), findsOneWidget);
      expect(find.text(EarningsCopy.uncappedLabel), findsOneWidget);
    });

    testWidgets('an uncapped reward shows no cap explanation', (
      WidgetTester tester,
    ) async {
      await openWith(tester, <CampaignRewardRecord>[exampleReward()]);

      expect(find.text(EarningsCopy.reducedByCap), findsNothing);
      expect(find.text(EarningsCopy.uncappedLabel), findsNothing);
    });

    testWidgets('a target-bonus reward shows its threshold and bonus', (
      WidgetTester tester,
    ) async {
      await openWith(tester, <CampaignRewardRecord>[
        exampleTargetBonusReward(),
      ]);

      expect(
        find.text(EarningsCopy.ruleLabel(CampaignRewardRuleType.targetBonus)),
        findsOneWidget,
      );
      expect(find.text(EarningsCopy.targetLabel), findsOneWidget);
      expect(find.text('25 units'), findsOneWidget);
      expect(find.text(EarningsCopy.configuredBonusLabel), findsOneWidget);
      expect(find.text('2,500 coins'), findsNWidgets(2));
    });

    testWidgets('a per-unit reward shows no target fields', (
      WidgetTester tester,
    ) async {
      await openWith(tester, <CampaignRewardRecord>[exampleReward()]);

      expect(find.text(EarningsCopy.targetLabel), findsNothing);
      expect(find.text(EarningsCopy.configuredBonusLabel), findsNothing);
    });

    testWidgets('no internal identifier is rendered anywhere', (
      WidgetTester tester,
    ) async {
      await openWith(tester, <CampaignRewardRecord>[
        exampleReward(),
        exampleTargetBonusReward(),
      ]);

      final String rendered = visibleText(tester);
      for (final String forbidden in <String>[
        rewardIdA,
        rewardIdB,
        receiptSubmissionIdA,
        campaignIdA,
        'verified_sale',
        'verifiedSale',
        'campaign_version',
        'accumulator',
        'beneficiary',
        'cap_subject',
      ]) {
        expect(rendered, isNot(contains(forbidden)), reason: forbidden);
      }
    });

    testWidgets('no unit or coin label is duplicated', (
      WidgetTester tester,
    ) async {
      await openWith(tester, <CampaignRewardRecord>[
        exampleTargetBonusReward(),
        exampleCappedReward(),
      ]);

      final String rendered = visibleText(tester).toLowerCase();
      expect(rendered, isNot(contains('coins coins')));
      expect(rendered, isNot(contains('units units')));
      expect(rendered, isNot(contains('coin coin')));
      expect(rendered, isNot(contains('unit unit')));
    });

    testWidgets('an empty history shows the specified empty state', (
      WidgetTester tester,
    ) async {
      await openWith(tester, <CampaignRewardRecord>[]);

      // The required sentence is verbatim; what follows it says what has to
      // happen next, and the empty state offers the one action a seller with no
      // rewards can take.
      expect(
        find.textContaining(EarningsCopy.historyEmptyBody),
        findsOneWidget,
      );
      expect(
        find.textContaining(EarningsCopy.historyEmptyHint),
        findsOneWidget,
      );
      expect(find.text(EarningsCopy.historyEmptyAction), findsOneWidget);
      expect(find.byType(CampaignRewardCard), findsNothing);
      expect(find.text(EarningsCopy.loadOlder), findsNothing);
    });

    testWidgets('one reward is announced as one utterance', (
      WidgetTester tester,
    ) async {
      await openWith(tester, <CampaignRewardRecord>[exampleCappedReward()]);

      expect(semanticsContaining(EarningsCopy.reducedByCap), findsOneWidget);
      expect(semanticsContaining('Summer Push'), findsWidgets);
    });
  });

  // =========================================================================
  group('pagination on screen', () {
    Future<FakeStaffEarningsRepository> openPaged(WidgetTester tester) async {
      final FakeStaffEarningsRepository earnings = FakeStaffEarningsRepository()
        ..firstPageResult = StaffCampaignRewardsLoaded(
          rewards: <CampaignRewardRecord>[
            exampleReward(
              rewardId: rewardIdA,
              awardedAt: DateTime.utc(2026, 8, 5),
            ),
          ],
          hasMore: true,
        )
        ..olderPageResult = StaffCampaignRewardsLoaded(
          rewards: <CampaignRewardRecord>[
            exampleReward(
              rewardId: rewardIdB,
              campaignName: 'Older Campaign',
              awardedAt: DateTime.utc(2026, 8, 4),
            ),
          ],
          hasMore: false,
        );
      await pumpAppInRole(
        tester,
        PortalKind.salesStaff,
        staffEarnings: earnings,
      );
      await goTo(tester, SalesStaffNavigation.earnings);
      return earnings;
    }

    testWidgets('the control appears only when another page may exist', (
      WidgetTester tester,
    ) async {
      await openPaged(tester);
      expect(find.text(EarningsCopy.loadOlder), findsWidgets);
    });

    testWidgets('pressing it appends the older page and hides the control', (
      WidgetTester tester,
    ) async {
      final FakeStaffEarningsRepository earnings = await openPaged(tester);

      await tapVisible(tester, find.text(EarningsCopy.loadOlder).first);

      expect(find.byType(CampaignRewardCard), findsNWidgets(2));
      expect(find.text('Older Campaign'), findsWidgets);
      expect(find.text(EarningsCopy.loadOlder), findsNothing);
      expect(find.text(EarningsCopy.historyEnd), findsOneWidget);

      // Two requests: the first with no cursor, the second with both halves.
      expect(earnings.rewardRequests, hasLength(2));
      expect(earnings.rewardRequests.first.beforeAwardedAt, isNull);
      expect(
        earnings.rewardRequests.last.beforeAwardedAt,
        DateTime.utc(2026, 8, 5),
      );
      expect(earnings.rewardRequests.last.beforeRewardId, rewardIdA);
    });

    testWidgets('a failed page keeps the rewards and the totals on screen', (
      WidgetTester tester,
    ) async {
      final FakeStaffEarningsRepository earnings = await openPaged(tester);
      earnings.olderPageResult = const StaffCampaignRewardsFailed(
        RetailerReadProblem.network,
      );

      await tapVisible(tester, find.text(EarningsCopy.loadOlder).first);

      expect(find.byType(CampaignRewardCard), findsOneWidget);
      expect(find.text(EarningsCopy.totalCoinsLabel), findsOneWidget);
      expect(find.text(EarningsCopy.coins(2530)), findsOneWidget);
      expect(find.text(EarningsCopy.olderFailedTitle), findsOneWidget);
      // Still retryable.
      expect(find.text(EarningsCopy.loadOlder), findsWidgets);
    });

    testWidgets('no database detail reaches the screen on a failure', (
      WidgetTester tester,
    ) async {
      final FakeStaffEarningsRepository earnings = FakeStaffEarningsRepository()
        ..firstPageResult = const StaffCampaignRewardsFailed(
          RetailerReadProblem.unexpected,
        )
        ..summaryResult = const StaffEarningsSummaryFailed(
          RetailerReadProblem.unexpected,
        );
      await pumpAppInRole(
        tester,
        PortalKind.salesStaff,
        staffEarnings: earnings,
      );
      await goTo(tester, SalesStaffNavigation.earnings);

      final String rendered = visibleText(tester).toLowerCase();
      for (final String forbidden in <String>[
        'postgrest',
        'sqlstate',
        '42501',
        'get_my_campaign',
        'campaign_rewards',
        'verified_sales',
        'exception',
        'null check',
      ]) {
        expect(rendered, isNot(contains(forbidden)), reason: forbidden);
      }
    });
  });

  // =========================================================================
  group('target progress on the campaign list', () {
    Future<void> openCampaigns(
      WidgetTester tester, {
      List<CampaignTargetProgress> progress = const <CampaignTargetProgress>[],
      StaffCampaignTargetProgressResult? progressResult,
      List<dynamic>? campaigns,
    }) async {
      final FakeStaffEarningsRepository earnings = FakeStaffEarningsRepository()
        ..progressResult =
            progressResult ?? StaffCampaignTargetProgressLoaded(progress);
      final FakeStaffCampaignRepository campaignRepository =
          FakeStaffCampaignRepository();
      if (campaigns != null) {
        campaignRepository.nextCampaigns = campaigns.cast();
      }

      await pumpAppInRole(
        tester,
        PortalKind.salesStaff,
        staffEarnings: earnings,
        staffCampaigns: campaignRepository,
      );
      await goTo(tester, SalesStaffNavigation.campaigns);
    }

    testWidgets('a per-unit campaign gets no progress indicator', (
      WidgetTester tester,
    ) async {
      // The contract returns no row for it, so there is nothing to draw.
      await openCampaigns(tester);

      expect(find.byType(CampaignCard), findsWidgets);
      expect(find.byType(CampaignTargetProgressView), findsNothing);
    });

    testWidgets('an individual target says "Your progress"', (
      WidgetTester tester,
    ) async {
      await openCampaigns(
        tester,
        progress: <CampaignTargetProgress>[exampleTargetProgress()],
      );

      expect(find.byType(CampaignTargetProgressView), findsOneWidget);
      expect(find.text(EarningsCopy.personalProgressLabel), findsOneWidget);
      expect(find.text(EarningsCopy.teamProgressLabel), findsNothing);
      expect(find.text('12 of 25 units'), findsOneWidget);
      expect(find.text(EarningsCopy.targetNotReached), findsOneWidget);
    });

    testWidgets('a Retailer team target says "Team progress"', (
      WidgetTester tester,
    ) async {
      await openCampaigns(
        tester,
        progress: <CampaignTargetProgress>[
          exampleTargetProgress(
            performanceScope: CampaignPerformanceScope.retailerTeam,
          ),
        ],
      );

      expect(find.text(EarningsCopy.teamProgressLabel), findsOneWidget);
      expect(find.text(EarningsCopy.personalProgressLabel), findsNothing);
    });

    testWidgets('a personal bonus is stated as the reader\'s own', (
      WidgetTester tester,
    ) async {
      await openCampaigns(
        tester,
        progress: <CampaignTargetProgress>[
          exampleTargetProgress(
            progressUnits: 30,
            targetReached: true,
            bonusAwardedToMe: true,
          ),
        ],
      );

      expect(find.text(EarningsCopy.targetReached), findsOneWidget);
      expect(
        find.textContaining('You were awarded the target bonus'),
        findsOneWidget,
      );
      expect(find.text(EarningsCopy.teamBonusAwardedElsewhere), findsNothing);
    });

    testWidgets(
      'a team target reached by somebody else is NOT claimed by the reader',
      (WidgetTester tester) async {
        await openCampaigns(
          tester,
          progress: <CampaignTargetProgress>[teamProgressBonusToSomebodyElse()],
        );

        expect(
          find.text(EarningsCopy.teamBonusAwardedElsewhere),
          findsOneWidget,
        );
        final String rendered = visibleText(tester);
        expect(rendered, isNot(contains('You were awarded')));
        expect(rendered, contains('awarded to another team member'));
      },
    );

    testWidgets('no accumulator or subject identifier is shown', (
      WidgetTester tester,
    ) async {
      await openCampaigns(
        tester,
        progress: <CampaignTargetProgress>[teamProgressBonusToSomebodyElse()],
      );

      final String rendered = visibleText(tester).toLowerCase();
      for (final String forbidden in <String>[
        'cap_subject',
        'subject id',
        'accumulator',
        'campaign_version',
        'retailer_team',
        'individual_staff',
        campaignIdA,
      ]) {
        expect(rendered, isNot(contains(forbidden)), reason: forbidden);
      }
    });

    testWidgets('a progress failure does not blank the campaign list', (
      WidgetTester tester,
    ) async {
      await openCampaigns(
        tester,
        progressResult: const StaffCampaignTargetProgressFailed(
          RetailerReadProblem.unexpected,
        ),
      );

      // The campaigns are a different contract and are still true.
      expect(find.byType(CampaignCard), findsWidgets);
      expect(find.byType(CampaignTargetProgressView), findsNothing);
      expect(find.text(CampaignCopy.progressUnavailableBody), findsOneWidget);
    });

    testWidgets('the empty campaign state is the specified sentence', (
      WidgetTester tester,
    ) async {
      final FakeStaffCampaignRepository campaigns =
          FakeStaffCampaignRepository()
            ..listResult = const StaffCampaignsLoaded(<StaffCampaign>[]);

      await pumpAppInRole(
        tester,
        PortalKind.salesStaff,
        staffCampaigns: campaigns,
      );
      await goTo(tester, SalesStaffNavigation.campaigns);

      expect(find.text(CampaignCopy.staffEmptyBody), findsOneWidget);
      expect(
        CampaignCopy.staffEmptyBody,
        'No active or upcoming campaigns are available for your shop.',
      );
    });

    testWidgets('a campaign read retry re-issues both contracts', (
      WidgetTester tester,
    ) async {
      final FakeStaffCampaignRepository campaigns =
          FakeStaffCampaignRepository()
            ..listResult = const StaffCampaignsFailed(
              RetailerReadProblem.unexpected,
            );
      final FakeStaffEarningsRepository earnings =
          FakeStaffEarningsRepository();

      await pumpAppInRole(
        tester,
        PortalKind.salesStaff,
        staffCampaigns: campaigns,
        staffEarnings: earnings,
      );
      await goTo(tester, SalesStaffNavigation.campaigns);

      expect(campaigns.callCount, 1);
      expect(earnings.progressCallCount, 1);

      await tapVisible(tester, find.text('Try again').first);

      expect(campaigns.callCount, 2);
      expect(earnings.progressCallCount, 2);
    });
  });

  // =========================================================================
  group('target progress on the campaign detail', () {
    testWidgets('the detail shows the progress for THIS campaign', (
      WidgetTester tester,
    ) async {
      final FakeStaffEarningsRepository earnings = FakeStaffEarningsRepository()
        ..progressResult =
            StaffCampaignTargetProgressLoaded(<CampaignTargetProgress>[
              exampleTargetProgress(campaignId: campaignIdA, progressUnits: 12),
              exampleTargetProgress(campaignId: campaignIdB, progressUnits: 99),
            ]);

      await pumpAppInRole(
        tester,
        PortalKind.salesStaff,
        staffEarnings: earnings,
      );
      // The list read is what populates the progress cubit; the detail selects
      // from it without issuing a second request.
      await goTo(tester, SalesStaffNavigation.campaigns);
      final int afterList = earnings.progressCallCount;

      await goTo(tester, SalesStaffNavigation.campaignDetail(campaignIdA));

      expect(find.byType(CampaignDetailView), findsOneWidget);
      expect(find.text(EarningsCopy.progressSectionTitle), findsOneWidget);
      expect(find.text('12 of 25 units'), findsOneWidget);
      expect(find.text('99 of 25 units'), findsNothing);
      expect(earnings.progressCallCount, afterList);
    });

    testWidgets('the team explanation is spelled out on the detail', (
      WidgetTester tester,
    ) async {
      final FakeStaffEarningsRepository earnings = FakeStaffEarningsRepository()
        ..progressResult = StaffCampaignTargetProgressLoaded(
          <CampaignTargetProgress>[teamProgressBonusToSomebodyElse()],
        );

      await pumpAppInRole(
        tester,
        PortalKind.salesStaff,
        staffEarnings: earnings,
      );
      await goTo(tester, SalesStaffNavigation.campaigns);
      await goTo(tester, SalesStaffNavigation.campaignDetail(campaignIdA));

      expect(
        find.text(
          EarningsCopy.progressExplanation(
            CampaignPerformanceScope.retailerTeam,
          ),
        ),
        findsOneWidget,
      );
      expect(find.text(EarningsCopy.teamBonusAwardedElsewhere), findsOneWidget);
    });

    testWidgets('the snapshot wording is rendered for a snapshot campaign', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.salesStaff);
      await goTo(tester, SalesStaffNavigation.campaignDetail(campaignIdA));

      expect(
        find.text(
          CampaignCopy.eligibilityHeading(
            CampaignProductEligibilityResolution.snapshot,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          CampaignCopy.eligibilityExplanation(
            CampaignProductEligibilityResolution.snapshot,
          ),
        ),
        findsOneWidget,
      );
      expect(
        CampaignCopy.eligibilityHeading(
          CampaignProductEligibilityResolution.snapshot,
        ),
        'Published campaign product selection',
      );
    });

    testWidgets('the live-temporal wording is rendered for an open campaign', (
      WidgetTester tester,
    ) async {
      final FakeStaffCampaignRepository campaigns =
          FakeStaffCampaignRepository()
            ..detailResult = StaffCampaignDetailLoaded(
              campaign: exampleStaffCampaign(
                offer: exampleOffer(
                  productScope: CampaignProductScope.allEligibleProducts,
                ),
              ),
              products: exampleCampaignProducts,
            );

      await pumpAppInRole(
        tester,
        PortalKind.salesStaff,
        staffCampaigns: campaigns,
      );
      await goTo(tester, SalesStaffNavigation.campaignDetail(campaignIdA));

      expect(
        find.text(
          CampaignCopy.eligibilityHeading(
            CampaignProductEligibilityResolution.liveTemporal,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          CampaignCopy.eligibilityExplanation(
            CampaignProductEligibilityResolution.liveTemporal,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('products render in the backend order, with no extra data', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.salesStaff);
      await goTo(tester, SalesStaffNavigation.campaignDetail(campaignIdA));

      final List<String> rendered = tester
          .widgetList<Text>(find.byType(Text))
          .map((Text t) => t.data ?? '')
          .toList();
      final int first = rendered.indexOf('Summer Cooler 500ml');
      final int second = rendered.indexOf('Summer Cooler 1L');
      expect(first, greaterThan(-1));
      expect(second, greaterThan(first));

      // Only the fields the contract returns. No price, stock, margin,
      // category or Vendor.
      final String all = rendered.join('\n').toLowerCase();
      for (final String forbidden in <String>[
        'price',
        'stock',
        'margin',
        'cost',
        'category',
        'vendor',
      ]) {
        expect(all, isNot(contains(forbidden)), reason: forbidden);
      }
    });

    testWidgets('an empty product list uses the seller wording', (
      WidgetTester tester,
    ) async {
      final FakeStaffCampaignRepository campaigns =
          FakeStaffCampaignRepository()
            ..detailResult = StaffCampaignDetailLoaded(
              campaign: exampleStaffCampaign(),
              products: const <CampaignProduct>[],
            );

      await pumpAppInRole(
        tester,
        PortalKind.salesStaff,
        staffCampaigns: campaigns,
      );
      await goTo(tester, SalesStaffNavigation.campaignDetail(campaignIdA));

      expect(find.text(CampaignCopy.staffProductsEmptyDetail), findsOneWidget);
      expect(
        CampaignCopy.staffProductsEmptyDetail,
        'No product list is available for this campaign.',
      );
      // And never the Retailer Owner's wording.
      expect(find.text(CampaignCopy.retailerProductsEmptyDetail), findsNothing);
    });

    testWidgets('a missing campaign is non-leaking', (
      WidgetTester tester,
    ) async {
      final FakeStaffCampaignRepository campaigns =
          FakeStaffCampaignRepository()
            ..detailResult = const StaffCampaignDetailMissing();

      await pumpAppInRole(
        tester,
        PortalKind.salesStaff,
        staffCampaigns: campaigns,
      );
      await goTo(tester, SalesStaffNavigation.campaignDetail(campaignIdB));

      expect(find.text(CampaignCopy.notFoundTitle), findsOneWidget);

      // The screen must not say WHY. An unknown id, another Retailer's
      // campaign, and one that has since been paused are one answer, and
      // telling them apart would let a reader learn which ids name real
      // campaigns somewhere else.
      final String rendered = visibleText(tester).toLowerCase();
      for (final String forbidden in <String>[
        'unauthorized',
        'not authorized',
        'not allowed',
        'permission',
        'denied',
        'another retailer',
        'paused',
        'cancelled',
        'does not exist',
        campaignIdB,
      ]) {
        expect(rendered, isNot(contains(forbidden)), reason: forbidden);
      }
      // And no retry: the backend answered, and it will answer the same way.
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('the maximum reward is stated once, not twice', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.salesStaff);
      await goTo(tester, SalesStaffNavigation.campaignDetail(campaignIdA));

      final String rendered = visibleText(tester);
      expect(
        'up to 100 coins'.allMatches(rendered).length,
        1,
        reason: 'the cap is named exactly once',
      );
      expect(rendered.toLowerCase(), isNot(contains('coins coins')));
      expect(rendered.toLowerCase(), isNot(contains('units units')));
    });
  });

  // =========================================================================
  group('layout and text scaling', () {
    testWidgets('the earnings screen fits a small Android phone', (
      WidgetTester tester,
    ) async {
      final FakeStaffEarningsRepository earnings = FakeStaffEarningsRepository()
        ..firstPageResult = StaffCampaignRewardsLoaded(
          rewards: <CampaignRewardRecord>[
            exampleCappedReward(),
            exampleTargetBonusReward(),
          ],
          hasMore: true,
        );

      await pumpAppInRole(
        tester,
        PortalKind.salesStaff,
        surface: smallPhoneSurface,
        staffEarnings: earnings,
      );
      await goTo(tester, SalesStaffNavigation.earnings);

      expect(tester.takeException(), isNull);
      expect(find.byType(CampaignRewardCard), findsWidgets);
    });

    testWidgets('a long campaign name and a large coin total do not overflow', (
      WidgetTester tester,
    ) async {
      final FakeStaffEarningsRepository earnings = FakeStaffEarningsRepository()
        ..summaryResult = StaffEarningsSummaryLoaded(
          exampleEarningsSummary(
            totalRewardCoins: 987654321,
            currentMonthRewardCoins: 123456,
          ),
        )
        ..firstPageResult = StaffCampaignRewardsLoaded(
          rewards: <CampaignRewardRecord>[
            exampleReward(
              campaignName: 'A' * 150,
              shopName: 'B' * 80,
              coinsUncapped: 5000000,
              rewardCoins: 5000000,
            ),
          ],
          hasMore: false,
        );

      await pumpAppInRole(
        tester,
        PortalKind.salesStaff,
        surface: smallPhoneSurface,
        staffEarnings: earnings,
      );
      await goTo(tester, SalesStaffNavigation.earnings);

      expect(tester.takeException(), isNull);
    });

    testWidgets('the earnings screen survives a large text scale', (
      WidgetTester tester,
    ) async {
      final FakeStaffEarningsRepository earnings = FakeStaffEarningsRepository()
        ..firstPageResult = StaffCampaignRewardsLoaded(
          rewards: <CampaignRewardRecord>[exampleCappedReward()],
          hasMore: true,
        );

      await pumpAppInRole(
        tester,
        PortalKind.salesStaff,
        staffEarnings: earnings,
      );
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await goTo(tester, SalesStaffNavigation.earnings);

      expect(tester.takeException(), isNull);
      expect(find.text(EarningsCopy.walletNotice), findsOneWidget);
    });

    testWidgets('the campaign detail survives a large text scale', (
      WidgetTester tester,
    ) async {
      final FakeStaffEarningsRepository earnings = FakeStaffEarningsRepository()
        ..progressResult = StaffCampaignTargetProgressLoaded(
          <CampaignTargetProgress>[teamProgressBonusToSomebodyElse()],
        );

      await pumpAppInRole(
        tester,
        PortalKind.salesStaff,
        staffEarnings: earnings,
      );
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await goTo(tester, SalesStaffNavigation.campaigns);
      await goTo(tester, SalesStaffNavigation.campaignDetail(campaignIdA));

      expect(tester.takeException(), isNull);
    });

    testWidgets('the progress indicator carries a semantic label', (
      WidgetTester tester,
    ) async {
      final FakeStaffEarningsRepository earnings = FakeStaffEarningsRepository()
        ..progressResult = StaffCampaignTargetProgressLoaded(
          <CampaignTargetProgress>[exampleTargetProgress()],
        );

      await pumpAppInRole(
        tester,
        PortalKind.salesStaff,
        staffEarnings: earnings,
      );
      await goTo(tester, SalesStaffNavigation.campaigns);

      // The label carries the whose, the current value and the target — a bare
      // percentage would say none of them.
      expect(
        semanticsContaining(EarningsCopy.personalProgressLabel),
        findsWidgets,
      );
      expect(semanticsContaining('12 of 25 units'), findsWidgets);
    });
  });

  // =========================================================================
  group('session isolation', () {
    testWidgets('a user switch empties the earnings screen', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await pumpAppInRole(tester, PortalKind.salesStaff);
      await goTo(tester, SalesStaffNavigation.earnings);
      expect(find.byType(CampaignRewardCard), findsWidgets);

      app.auth.emitSignedOut();
      await tester.pumpAndSettle();

      expect(find.byType(CampaignRewardCard), findsNothing);
      expect(find.byType(SalesStaffEarningsPage), findsNothing);
    });
  });
}
