import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sale_reward/app/shells/sales_staff/sales_staff_navigation.dart';
import 'package:sale_reward/core/errors/retailer_read_problem.dart';
import 'package:sale_reward/core/widgets/widgets.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_lifecycle_state.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_measurement.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_reward.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_stacking_mode.dart';
import 'package:sale_reward/features/campaigns/domain/entities/staff_campaign.dart';
import 'package:sale_reward/features/campaigns/domain/repositories/staff_campaign_repository.dart';
import 'package:sale_reward/features/campaigns/presentation/shared/campaign_card.dart';
import 'package:sale_reward/features/campaigns/presentation/shared/campaign_copy.dart';
import 'package:sale_reward/features/home/presentation/sales_staff/pages/sales_staff_home_page.dart';
import 'package:sale_reward/features/home/presentation/sales_staff/widgets/sales_staff_add_receipt_cta.dart';
import 'package:sale_reward/features/home/presentation/sales_staff/widgets/sales_staff_home_copy.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/pages/sales_staff_submit_page.dart';
import 'package:sale_reward/features/rewards/domain/entities/campaign_target_progress.dart';
import 'package:sale_reward/features/rewards/domain/repositories/staff_earnings_repository.dart';
import 'package:sale_reward/features/rewards/presentation/widgets/campaign_target_progress_view.dart';
import 'package:sale_reward/features/rewards/presentation/widgets/earnings_copy.dart';

import '../../support/campaign_fakes.dart';
import '../../support/earnings_fakes.dart';
import '../../support/pump_app.dart';

/// Drives the redesigned Sales Staff experience through the real application:
/// real router, real shell, real cubits, over fakes that never touch Supabase.
///
/// The redesign is a **presentation** milestone, so what these tests defend is
/// what the screens say and how they behave — not the contracts, which the
/// campaign, earnings and receipt suites already cover. Two properties recur and
/// are worth naming once:
///
/// * **Nothing is fabricated.** Every number on the home screen traces to a
///   value a fake returned. There is no streak, no rank, no countdown, no
///   prediction and no personal statistic anywhere on it.
/// * **Nothing is a balance.** The coin figure is labelled as earned and carries
///   the same qualifying notice the earnings screen does.
void main() {
  String currentLocation(WidgetTester tester) => GoRouter.of(
    tester.element(find.byType(Navigator).first),
  ).routeInformationProvider.value.uri.path;

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Every rendered `Text` on screen, joined — for asserting that a phrase is
  /// **absent** without depending on where it would have been.
  String visibleText(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((Text t) => t.data ?? '')
      .join('\n');

  Finder semanticsContaining(String fragment) => find.byWidgetPredicate(
    (Widget widget) =>
        widget is Semantics &&
        (widget.properties.label?.contains(fragment) ?? false),
    description: 'Semantics whose label contains "$fragment"',
  );

  /// Signs in as Sales Staff and lands on the home screen.
  Future<PumpedApp> openHome(
    WidgetTester tester, {
    List<StaffCampaign>? campaigns,
    List<CampaignTargetProgress> progress = const <CampaignTargetProgress>[],
    StaffEarningsSummaryResult? summary,
    StaffCampaignsResult? campaignsResult,
    Size surface = phoneSurface,
  }) async {
    final FakeStaffCampaignRepository campaignRepository =
        FakeStaffCampaignRepository()
          ..listResult = campaignsResult
          ..nextCampaigns =
              campaigns ?? <StaffCampaign>[exampleStaffCampaign()];
    final FakeStaffEarningsRepository earningsRepository =
        FakeStaffEarningsRepository()
          ..progressResult = StaffCampaignTargetProgressLoaded(progress)
          ..summaryResult =
              summary ?? StaffEarningsSummaryLoaded(exampleEarningsSummary());

    return pumpAppInRole(
      tester,
      PortalKind.salesStaff,
      staffCampaigns: campaignRepository,
      staffEarnings: earningsRepository,
      surface: surface,
    );
  }

  // =========================================================================
  group('the landing screen', () {
    testWidgets('a seller lands on Home, not on the submission form', (
      WidgetTester tester,
    ) async {
      await openHome(tester);

      expect(currentLocation(tester), SalesStaffNavigation.home);
      expect(find.byType(SalesStaffHomePage), findsOneWidget);
      expect(find.byType(SalesStaffSubmitPage), findsNothing);
    });

    testWidgets('the greeting names the Retailer from the session context', (
      WidgetTester tester,
    ) async {
      await openHome(tester);

      expect(find.text(SalesStaffHomeCopy.greeting), findsOneWidget);
      // "Example Org" is the organization the trusted session context carries —
      // never a value read back from a campaign, a reward or a receipt.
      expect(
        find.text(SalesStaffHomeCopy.forRetailer('Example Org')),
        findsOneWidget,
      );
    });

    testWidgets('the motivating line is shown when a campaign is running', (
      WidgetTester tester,
    ) async {
      await openHome(tester);

      expect(find.text(SalesStaffHomeCopy.greetingLine), findsOneWidget);
    });

    testWidgets('the motivating line changes when there is no campaign', (
      WidgetTester tester,
    ) async {
      // The encouragement must never sit directly above a section that says
      // there is nothing to earn from.
      await openHome(tester, campaigns: <StaffCampaign>[]);

      expect(find.text(SalesStaffHomeCopy.greetingLine), findsNothing);
      expect(
        find.text(SalesStaffHomeCopy.greetingLineNoCampaigns),
        findsOneWidget,
      );
    });

    testWidgets('no personal statistic is invented', (
      WidgetTester tester,
    ) async {
      await openHome(tester);

      final String rendered = visibleText(tester).toLowerCase();
      for (final String forbidden in <String>[
        'streak',
        'rank',
        'leaderboard',
        'compared with',
        'last week',
        'on track to',
        'you will earn',
        'days left',
      ]) {
        expect(rendered, isNot(contains(forbidden)), reason: forbidden);
      }
    });
  });

  // =========================================================================
  group('the campaign coins panel', () {
    testWidgets('shows the authoritative total, labelled as earned', (
      WidgetTester tester,
    ) async {
      await openHome(tester);
      // The count-up settles on the stored value.
      await tester.pumpAndSettle();

      expect(find.text(SalesStaffHomeCopy.coinsSectionTitle), findsOneWidget);
      expect(find.text(EarningsCopy.coins(2530)), findsOneWidget);
    });

    testWidgets('carries the wallet notice, so nothing reads as a balance', (
      WidgetTester tester,
    ) async {
      await openHome(tester);

      expect(find.text(EarningsCopy.walletNotice), findsOneWidget);

      // The notice is the ONE place these words legitimately appear — it names
      // wallet, payout and redemption in order to say none of them exists yet.
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

    testWidgets('a zero total renders as zero, not as an error', (
      WidgetTester tester,
    ) async {
      await openHome(
        tester,
        summary: StaffEarningsSummaryLoaded(zeroEarningsSummary()),
      );
      await tester.pumpAndSettle();

      // The total and the this-month figure are both zero, and both render as
      // zero. A seller who has earned nothing has earned nothing.
      expect(find.text(EarningsCopy.coins(0)), findsNWidgets(2));
    });

    testWidgets('an unreadable summary says so rather than showing zeros', (
      WidgetTester tester,
    ) async {
      await openHome(
        tester,
        summary: const StaffEarningsSummaryFailed(RetailerReadProblem.network),
      );

      expect(find.text(SalesStaffHomeCopy.coinsUnavailable), findsOneWidget);
      // "You earned nothing" and "we could not tell" are opposite claims.
      expect(find.text(EarningsCopy.coins(0)), findsNothing);
    });

    testWidgets('the panel routes to the earnings screen', (
      WidgetTester tester,
    ) async {
      await openHome(tester);

      await tapVisible(tester, find.text(SalesStaffHomeCopy.coinsAction));

      expect(currentLocation(tester), SalesStaffNavigation.earnings);
    });
  });

  // =========================================================================
  group('the active opportunity section', () {
    testWidgets('running campaigns are highlighted in the backend order', (
      WidgetTester tester,
    ) async {
      await openHome(
        tester,
        campaigns: <StaffCampaign>[
          exampleStaffCampaign(
            offer: exampleOffer(campaignId: campaignIdA, name: 'First Listed'),
          ),
          exampleStaffCampaign(
            offer: exampleOffer(campaignId: campaignIdB, name: 'Second Listed'),
          ),
        ],
      );

      expect(find.text(SalesStaffHomeCopy.opportunitiesTitle), findsOneWidget);
      expect(find.byType(CampaignCard), findsNWidgets(2));

      final double first = tester.getTopLeft(find.text('First Listed')).dy;
      final double second = tester.getTopLeft(find.text('Second Listed')).dy;
      expect(
        first,
        lessThan(second),
        reason: 'the backend order is preserved, not re-ranked',
      );
    });

    testWidgets('a scheduled campaign is shown under its own heading', (
      WidgetTester tester,
    ) async {
      await openHome(
        tester,
        campaigns: <StaffCampaign>[
          exampleStaffCampaign(
            offer: exampleOffer(
              lifecycleState: CampaignLifecycleState.scheduled,
              name: 'Autumn Launch',
            ),
          ),
        ],
      );

      // The heading and the status pill say the same words, which is the
      // point: the group and its members agree.
      expect(find.text(SalesStaffHomeCopy.upcomingTitle), findsWidgets);
      expect(find.text(SalesStaffHomeCopy.opportunitiesTitle), findsNothing);
      expect(
        find.text(
          CampaignCopy.lifecycleLabel(CampaignLifecycleState.scheduled),
        ),
        findsWidgets,
      );
    });

    testWidgets('a long list is capped, and the cap is stated', (
      WidgetTester tester,
    ) async {
      await openHome(
        tester,
        campaigns: <StaffCampaign>[
          for (int i = 0; i < 5; i++)
            exampleStaffCampaign(
              offer: exampleOffer(campaignId: campaignIdA, name: 'Campaign $i'),
            ),
        ],
      );

      expect(find.byType(CampaignCard), findsNWidgets(3));
      // Silent truncation would read as the whole list.
      expect(find.text(SalesStaffHomeCopy.showingSome(3, 5)), findsOneWidget);
    });

    testWidgets('no campaigns is an empty state, never a failure', (
      WidgetTester tester,
    ) async {
      await openHome(tester, campaigns: <StaffCampaign>[]);

      expect(find.text(SalesStaffHomeCopy.campaignsEmptyTitle), findsOneWidget);
      expect(
        find.text(SalesStaffHomeCopy.campaignsUnavailableTitle),
        findsNothing,
      );
    });

    testWidgets('an unreadable campaign read is never shown as emptiness', (
      WidgetTester tester,
    ) async {
      await openHome(
        tester,
        campaignsResult: const StaffCampaignsFailed(
          RetailerReadProblem.network,
        ),
      );

      expect(
        find.text(SalesStaffHomeCopy.campaignsUnavailableTitle),
        findsOneWidget,
      );
      expect(find.text(SalesStaffHomeCopy.campaignsEmptyTitle), findsNothing);
    });

    testWidgets('the section routes to the full campaign list', (
      WidgetTester tester,
    ) async {
      await openHome(tester);

      await tapVisible(
        tester,
        find.text(SalesStaffHomeCopy.viewAllCampaigns).first,
      );

      expect(currentLocation(tester), SalesStaffNavigation.campaigns);
    });
  });

  // =========================================================================
  group('target progress on the landing screen', () {
    testWidgets('an individual target shows the ring, the numbers and the '
        'remainder', (WidgetTester tester) async {
      await openHome(
        tester,
        progress: <CampaignTargetProgress>[
          exampleTargetProgress(progressUnits: 12, targetUnits: 25),
        ],
      );

      expect(find.byType(CampaignTargetProgressView), findsOneWidget);
      expect(find.byType(SrProgressRing), findsOneWidget);
      expect(find.text(EarningsCopy.personalProgressLabel), findsOneWidget);
      // The numerator and the denominator, never replaced by the percentage.
      expect(find.text('12 of 25 units'), findsOneWidget);
      expect(find.text('48%'), findsOneWidget);
      expect(
        find.text('13 more eligible units to reach your target.'),
        findsOneWidget,
      );
    });

    testWidgets('a per-unit campaign gets no ring at all', (
      WidgetTester tester,
    ) async {
      // The contract returns no row for one, so there is no goal to draw.
      await openHome(tester);

      expect(find.byType(CampaignTargetProgressView), findsNothing);
      expect(find.byType(SrProgressRing), findsNothing);
    });

    testWidgets('progress past the target keeps the real numbers', (
      WidgetTester tester,
    ) async {
      await openHome(
        tester,
        progress: <CampaignTargetProgress>[
          exampleTargetProgress(
            progressUnits: 9,
            targetUnits: 8,
            targetReached: true,
            bonusAwardedToMe: true,
          ),
        ],
      );

      // The ring saturates; the facts do not. A target must never look smaller
      // than it is, and a numerator must never be rounded down to fit a
      // drawing.
      expect(find.text('9 of 8 units'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text(EarningsCopy.targetReached), findsOneWidget);
    });

    testWidgets('a team target says so, and never claims the units are mine', (
      WidgetTester tester,
    ) async {
      await openHome(
        tester,
        progress: <CampaignTargetProgress>[
          exampleTargetProgress(
            performanceScope: CampaignPerformanceScope.retailerTeam,
          ),
        ],
      );

      expect(find.text(EarningsCopy.teamProgressLabel), findsOneWidget);
      expect(find.text(EarningsCopy.personalProgressLabel), findsNothing);
      expect(
        find.text('13 more eligible units to reach the team target.'),
        findsOneWidget,
      );
    });

    testWidgets('a bonus awarded to me is stated as mine', (
      WidgetTester tester,
    ) async {
      await openHome(
        tester,
        progress: <CampaignTargetProgress>[
          exampleTargetProgress(
            progressUnits: 30,
            targetReached: true,
            bonusAwardedToMe: true,
          ),
        ],
      );

      expect(find.text('Target reached — reward recorded.'), findsOneWidget);
      expect(
        visibleText(tester),
        isNot(contains('awarded to another team member')),
      );
    });

    testWidgets('a bonus awarded to somebody else is never claimed by me', (
      WidgetTester tester,
    ) async {
      await openHome(
        tester,
        progress: <CampaignTargetProgress>[teamProgressBonusToSomebodyElse()],
      );

      expect(find.text('The team has reached the target.'), findsOneWidget);
      expect(find.text(EarningsCopy.teamBonusAwardedElsewhere), findsOneWidget);
      expect(visibleText(tester), isNot(contains('You were awarded')));
    });

    testWidgets('the ring is announced with its values and its percentage', (
      WidgetTester tester,
    ) async {
      await openHome(
        tester,
        progress: <CampaignTargetProgress>[
          exampleTargetProgress(progressUnits: 2, targetUnits: 3),
        ],
      );

      // The required form: the scope, both numbers, then the percentage.
      expect(semanticsContaining('2 of 3 units, 67 percent'), findsOneWidget);
    });
  });

  // =========================================================================
  group('the Add receipt call to action', () {
    testWidgets('is pinned on a phone and opens the submission screen', (
      WidgetTester tester,
    ) async {
      await openHome(tester);

      expect(find.byType(SalesStaffAddReceiptBar), findsOneWidget);
      await tapVisible(tester, find.text(SalesStaffHomeCopy.addReceipt));

      expect(currentLocation(tester), SalesStaffNavigation.submit);
      expect(find.byType(SalesStaffSubmitPage), findsOneWidget);
    });

    testWidgets('moves into the header where the shell has a rail', (
      WidgetTester tester,
    ) async {
      await openHome(tester, surface: tabletSurface);

      // No pinned bar to sit above a bottom bar that is not there.
      expect(find.byType(SalesStaffAddReceiptBar), findsNothing);
      expect(find.byType(SalesStaffAddReceiptButton), findsOneWidget);
    });

    testWidgets('carries an accessible name of its own', (
      WidgetTester tester,
    ) async {
      await openHome(tester);

      expect(
        semanticsContaining(SalesStaffHomeCopy.addReceiptSemanticLabel),
        findsWidgets,
      );
    });
  });

  // =========================================================================
  group('campaign types on a card', () {
    Future<void> openWith(WidgetTester tester, StaffCampaign campaign) =>
        openHome(tester, campaigns: <StaffCampaign>[campaign]);

    testWidgets('a per-unit campaign names its rate and its rule', (
      WidgetTester tester,
    ) async {
      await openWith(
        tester,
        exampleStaffCampaign(
          offer: exampleOffer(
            reward: const CampaignPerUnitReward(
              coinsPerUnit: 10,
              maxRewardCoins: null,
              metric: CampaignMetricType.unitsSold,
            ),
          ),
        ),
      );

      expect(find.text(CampaignCopy.perUnitTypeLabel), findsOneWidget);
      expect(
        find.textContaining('Earn 10 coins per eligible unit'),
        findsOneWidget,
      );
      // No cap wording where the contract exposes no cap.
      expect(visibleText(tester), isNot(contains('Campaign maximum')));
    });

    testWidgets('a capped campaign states the maximum, and only then', (
      WidgetTester tester,
    ) async {
      await openWith(
        tester,
        exampleStaffCampaign(
          offer: exampleOffer(
            reward: const CampaignPerUnitReward(
              coinsPerUnit: 10,
              maxRewardCoins: 5000,
              metric: CampaignMetricType.unitsSold,
            ),
          ),
        ),
      );

      expect(
        find.text(CampaignCopy.campaignMaximumLabel(5000)),
        findsOneWidget,
      );
    });

    testWidgets('a target campaign is labelled as one', (
      WidgetTester tester,
    ) async {
      await openWith(
        tester,
        exampleStaffCampaign(
          offer: exampleOffer(
            reward: const CampaignTargetReward(
              thresholdUnits: 25,
              rewardCoins: 2500,
              maxRewardCoins: null,
              metric: CampaignMetricType.unitsSold,
            ),
          ),
        ),
      );

      expect(find.text(CampaignCopy.targetTypeLabel), findsOneWidget);
    });

    testWidgets('an exclusive campaign says it does not combine', (
      WidgetTester tester,
    ) async {
      await openWith(
        tester,
        exampleStaffCampaign(
          offer: exampleOffer(stackingMode: CampaignStackingMode.exclusive),
        ),
      );

      expect(
        find.text(CampaignCopy.stackingLabel(CampaignStackingMode.exclusive)),
        findsOneWidget,
      );
    });

    testWidgets('a combinable campaign says so instead', (
      WidgetTester tester,
    ) async {
      await openWith(
        tester,
        exampleStaffCampaign(
          offer: exampleOffer(stackingMode: CampaignStackingMode.stackable),
        ),
      );

      expect(
        find.text(CampaignCopy.stackingLabel(CampaignStackingMode.stackable)),
        findsOneWidget,
      );
    });

    testWidgets('a Retailer-team campaign names the scope on the card', (
      WidgetTester tester,
    ) async {
      await openWith(
        tester,
        exampleStaffCampaign(
          offer: exampleOffer(
            performanceScope: CampaignPerformanceScope.retailerTeam,
          ),
        ),
      );

      expect(
        find.text(
          CampaignCopy.measurementLabel(CampaignPerformanceScope.retailerTeam),
        ),
        findsOneWidget,
      );
    });
  });

  // =========================================================================
  group('layout, motion and accessibility', () {
    for (final Size surface in <Size>[
      smallPhoneSurface,
      phoneSurface,
      tabletSurface,
      desktopSurface,
    ]) {
      testWidgets('the home screen does not overflow at '
          '${surface.width}×${surface.height}', (WidgetTester tester) async {
        await openHome(
          tester,
          surface: surface,
          progress: <CampaignTargetProgress>[exampleTargetProgress()],
        );

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the home screen survives a large text scale', (
      WidgetTester tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await openHome(
        tester,
        surface: smallPhoneSurface,
        progress: <CampaignTargetProgress>[exampleTargetProgress()],
      );

      expect(tester.takeException(), isNull);
      // The numbers stay readable, and the ring never replaces them.
      expect(find.text('12 of 25 units'), findsOneWidget);
    });

    testWidgets('reduced motion settles the screen immediately', (
      WidgetTester tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      await openHome(
        tester,
        progress: <CampaignTargetProgress>[exampleTargetProgress()],
      );
      // One frame, no settling: under reduced motion every animation collapses
      // to its end state, so the real figures are on screen already.
      await tester.pump();

      expect(find.text(EarningsCopy.coins(2530)), findsOneWidget);
      expect(find.text('12 of 25 units'), findsOneWidget);
      expect(find.text('48%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in dark mode', (WidgetTester tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await openHome(tester);

      expect(find.byType(SalesStaffHomePage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
