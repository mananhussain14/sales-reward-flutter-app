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
import 'package:sale_reward/features/campaigns/presentation/shared/campaign_copy.dart';
import 'package:sale_reward/features/home/presentation/sales_staff/pages/sales_staff_home_page.dart';
import 'package:sale_reward/features/home/presentation/sales_staff/widgets/sales_staff_add_receipt_cta.dart';
import 'package:sale_reward/features/home/presentation/sales_staff/widgets/sales_staff_home_copy.dart';
import 'package:sale_reward/features/home/presentation/sales_staff/widgets/sales_staff_next_reward_hero.dart';
import 'package:sale_reward/features/home/presentation/sales_staff/widgets/sales_staff_opportunity_card.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/pages/sales_staff_submit_page.dart';
import 'package:sale_reward/features/rewards/domain/entities/campaign_target_progress.dart';
import 'package:sale_reward/features/rewards/domain/repositories/staff_earnings_repository.dart';
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
    await tester.tap(finder, warnIfMissed: false);
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

  /// A per-unit campaign first and a target campaign second, so the hero rule's
  /// first filter has to reach past the backend's first row.
  List<StaffCampaign> targetAndPerUnit() => <StaffCampaign>[
    exampleStaffCampaign(
      offer: exampleOffer(campaignId: campaignIdA, name: 'Everyday Coins'),
    ),
    exampleStaffCampaign(
      offer: exampleOffer(
        campaignId: campaignIdB,
        name: 'Personal Target',
        reward: const CampaignTargetReward(
          thresholdUnits: 25,
          rewardCoins: 2500,
          maxRewardCoins: null,
          metric: CampaignMetricType.unitsSold,
        ),
      ),
    ),
  ];

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

    testWidgets('the greeting is one compact row naming the Retailer', (
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
  group('the next-reward hero', () {
    testWidgets('leads the screen with the first running target campaign', (
      WidgetTester tester,
    ) async {
      await openHome(
        tester,
        campaigns: targetAndPerUnit(),
        progress: <CampaignTargetProgress>[
          exampleTargetProgress(campaignId: campaignIdB),
        ],
      );

      expect(find.byType(SalesStaffNextRewardHero), findsOneWidget);
      // The target campaign is second in the backend order and still wins,
      // because "running AND has a target" is the first filter.
      expect(
        find.descendant(
          of: find.byType(SalesStaffNextRewardHero),
          matching: find.text('Personal Target'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows the gauge, both numbers and the remainder', (
      WidgetTester tester,
    ) async {
      await openHome(
        tester,
        progress: <CampaignTargetProgress>[
          exampleTargetProgress(progressUnits: 12, targetUnits: 25),
        ],
      );

      expect(find.byType(SrProgressRing), findsWidgets);
      expect(find.text(SalesStaffHomeCopy.heroEyebrowNext), findsOneWidget);
      expect(find.text(EarningsCopy.personalProgressLabel), findsOneWidget);
      // The numerator and denominator, never replaced by the percentage.
      expect(find.text('12 of 25 units'), findsOneWidget);
      expect(find.text('48%'), findsOneWidget);
      expect(
        find.text('13 more eligible units to reach your target.'),
        findsOneWidget,
      );
      // What reaching it pays, from the stored configured amount.
      expect(find.text(EarningsCopy.coins(2500)), findsWidgets);
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
      expect(find.text(SalesStaffHomeCopy.heroEyebrowReached), findsOneWidget);
      expect(find.text('Target reached — reward recorded.'), findsOneWidget);
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

    testWidgets('a bonus awarded to somebody else is never claimed by me', (
      WidgetTester tester,
    ) async {
      await openHome(
        tester,
        progress: <CampaignTargetProgress>[teamProgressBonusToSomebodyElse()],
      );

      expect(find.text('The team has reached the target.'), findsOneWidget);
      expect(visibleText(tester), isNot(contains('You were awarded')));
    });

    testWidgets('the hero is announced with its values and its percentage', (
      WidgetTester tester,
    ) async {
      await openHome(
        tester,
        progress: <CampaignTargetProgress>[
          exampleTargetProgress(progressUnits: 2, targetUnits: 3),
        ],
      );

      expect(semanticsContaining('2 of 3 units, 67 percent'), findsWidgets);
    });

    testWidgets('a campaign with no target shows the offer instead', (
      WidgetTester tester,
    ) async {
      await openHome(tester);

      expect(find.byType(SalesStaffNextRewardHero), findsOneWidget);
      expect(find.text(SalesStaffHomeCopy.heroEyebrowRunning), findsOneWidget);
      // No gauge is drawn where the backend returned no row.
      expect(find.text(SalesStaffHomeCopy.heroOfTarget), findsNothing);
    });

    testWidgets('the hero opens its campaign', (WidgetTester tester) async {
      await openHome(tester);

      await tapVisible(tester, find.text(SalesStaffHomeCopy.heroAction));

      expect(
        currentLocation(tester),
        SalesStaffNavigation.campaignDetail(campaignIdA),
      );
    });

    testWidgets('no campaigns at all is an empty hero, never a failure', (
      WidgetTester tester,
    ) async {
      await openHome(tester, campaigns: <StaffCampaign>[]);

      expect(find.text(SalesStaffHomeCopy.heroEmptyTitle), findsOneWidget);
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
      expect(find.text(SalesStaffHomeCopy.heroEmptyTitle), findsNothing);
    });
  });

  // =========================================================================
  group('the campaign coins strip', () {
    testWidgets('shows the authoritative total, labelled as earned', (
      WidgetTester tester,
    ) async {
      await openHome(tester);
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

      // The total and the this-month pill are both zero, and both render as
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

    testWidgets('the strip routes to the earnings screen', (
      WidgetTester tester,
    ) async {
      await openHome(tester);

      await tapVisible(tester, find.text(SalesStaffHomeCopy.coinsSectionTitle));

      expect(currentLocation(tester), SalesStaffNavigation.earnings);
    });
  });

  // =========================================================================
  group('the opportunity carousel', () {
    testWidgets('carries every campaign except the one in the hero', (
      WidgetTester tester,
    ) async {
      await openHome(tester, campaigns: targetAndPerUnit());

      expect(find.text(SalesStaffHomeCopy.carouselTitle), findsOneWidget);
      // Two campaigns, one of which is the hero.
      expect(find.byType(SalesStaffOpportunityCard), findsOneWidget);
    });

    testWidgets('a long list is capped, and the cap is stated', (
      WidgetTester tester,
    ) async {
      await openHome(
        tester,
        campaigns: <StaffCampaign>[
          for (int i = 0; i < 9; i++)
            exampleStaffCampaign(
              offer: exampleOffer(campaignId: campaignIdA, name: 'Campaign $i'),
            ),
        ],
      );

      // Nine campaigns: one in the hero, six offered in the strip — of which
      // the horizontal list builds only what fits — and the truncation stated
      // rather than silent.
      expect(find.byType(SalesStaffOpportunityCard), findsWidgets);
      expect(find.text(SalesStaffHomeCopy.showingSome(6, 8)), findsOneWidget);
    });

    testWidgets('the section routes to the full campaign list', (
      WidgetTester tester,
    ) async {
      await openHome(tester, campaigns: targetAndPerUnit());

      await tapVisible(
        tester,
        find.text(SalesStaffHomeCopy.viewAllCampaigns).first,
      );

      expect(currentLocation(tester), SalesStaffNavigation.campaigns);
    });

    testWidgets('a card opens its own campaign', (WidgetTester tester) async {
      await openHome(
        tester,
        campaigns: <StaffCampaign>[
          exampleStaffCampaign(
            offer: exampleOffer(campaignId: campaignIdA, name: 'Hero'),
          ),
          exampleStaffCampaign(
            offer: exampleOffer(campaignId: campaignIdB, name: 'In the strip'),
          ),
        ],
      );

      await tapVisible(tester, find.byType(SalesStaffOpportunityCard).first);

      expect(
        currentLocation(tester),
        SalesStaffNavigation.campaignDetail(campaignIdB),
      );
    });
  });

  // =========================================================================
  group('campaign types look different from one another', () {
    /// Puts [campaign] in the carousel by giving the hero something else.
    Future<void> openWithCard(
      WidgetTester tester,
      StaffCampaign campaign, {
      List<CampaignTargetProgress> progress = const <CampaignTargetProgress>[],
    }) => openHome(
      tester,
      campaigns: <StaffCampaign>[
        exampleStaffCampaign(
          offer: exampleOffer(campaignId: campaignIdA, name: 'Hero campaign'),
        ),
        campaign,
      ],
      // The hero rule prefers the first running campaign WITH a target, so the
      // hero is given one of its own — otherwise a campaign under test that has
      // progress would be promoted out of the strip and into the hero.
      progress: <CampaignTargetProgress>[
        exampleTargetProgress(campaignId: campaignIdA),
        ...progress,
      ],
    );

    testWidgets('a per-unit card leads with its rate', (
      WidgetTester tester,
    ) async {
      await openWithCard(
        tester,
        exampleStaffCampaign(
          offer: exampleOffer(
            campaignId: campaignIdB,
            name: 'Everyday Coins',
            reward: const CampaignPerUnitReward(
              coinsPerUnit: 10,
              maxRewardCoins: null,
              metric: CampaignMetricType.unitsSold,
            ),
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(SalesStaffOpportunityCard),
          matching: find.text('per eligible unit'),
        ),
        findsOneWidget,
      );
      expect(find.text(EarningsCopy.coins(10)), findsWidgets);
    });

    testWidgets('a target card carries a mini gauge and the remainder', (
      WidgetTester tester,
    ) async {
      await openWithCard(
        tester,
        exampleStaffCampaign(
          offer: exampleOffer(campaignId: campaignIdB, name: 'Stretch Target'),
        ),
        progress: <CampaignTargetProgress>[
          exampleTargetProgress(
            campaignId: campaignIdB,
            progressUnits: 5,
            targetUnits: 50,
          ),
        ],
      );

      expect(
        find.descendant(
          of: find.byType(SalesStaffOpportunityCard),
          matching: find.text('5 of 50 units'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(SalesStaffOpportunityCard),
          matching: find.byType(SrProgressRing),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a team target card names the team and who was paid', (
      WidgetTester tester,
    ) async {
      await openWithCard(
        tester,
        exampleStaffCampaign(
          offer: exampleOffer(campaignId: campaignIdB, name: 'Team Target'),
        ),
        progress: <CampaignTargetProgress>[
          teamProgressBonusToSomebodyElse(campaignId: campaignIdB),
        ],
      );

      expect(find.text(EarningsCopy.teamProgressLabel), findsWidgets);
      expect(find.text(EarningsCopy.teamBonusAwardedElsewhere), findsOneWidget);
    });

    testWidgets('a scheduled card shows its start date, not progress', (
      WidgetTester tester,
    ) async {
      await openWithCard(
        tester,
        exampleStaffCampaign(
          offer: exampleOffer(
            campaignId: campaignIdB,
            name: 'Next Month Launch',
            lifecycleState: CampaignLifecycleState.scheduled,
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(SalesStaffOpportunityCard),
          matching: find.text(CampaignCopy.startsLabel),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a capped card states the maximum, and only then', (
      WidgetTester tester,
    ) async {
      await openWithCard(
        tester,
        exampleStaffCampaign(
          offer: exampleOffer(
            campaignId: campaignIdB,
            name: 'Capped Boost',
            reward: const CampaignPerUnitReward(
              coinsPerUnit: 10,
              maxRewardCoins: 5000,
              metric: CampaignMetricType.unitsSold,
            ),
          ),
        ),
      );

      expect(find.text(EarningsCopy.coins(5000)), findsWidgets);
    });

    testWidgets('an exclusive card carries an exclusivity pill', (
      WidgetTester tester,
    ) async {
      await openWithCard(
        tester,
        exampleStaffCampaign(
          offer: exampleOffer(
            campaignId: campaignIdB,
            name: 'Exclusive',
            stackingMode: CampaignStackingMode.exclusive,
          ),
        ),
      );

      expect(
        find.text(CampaignCopy.stackingLabel(CampaignStackingMode.exclusive)),
        findsWidgets,
      );
    });

    testWidgets('snapshot eligibility is marked on the card', (
      WidgetTester tester,
    ) async {
      await openWithCard(
        tester,
        exampleStaffCampaign(
          offer: exampleOffer(campaignId: campaignIdB, name: 'Snapshot rules'),
        ),
      );

      expect(find.text('Snapshot'), findsWidgets);
    });
  });

  // =========================================================================
  group('the Add receipt call to action', () {
    testWidgets('floats on a phone and opens the submission screen', (
      WidgetTester tester,
    ) async {
      await openHome(tester);

      expect(find.byType(SalesStaffAddReceiptBar), findsOneWidget);
      await tapVisible(tester, find.text(SalesStaffHomeCopy.addReceipt));

      expect(currentLocation(tester), SalesStaffNavigation.submit);
      expect(find.byType(SalesStaffSubmitPage), findsOneWidget);
    });

    testWidgets('carries supporting copy that promises nothing', (
      WidgetTester tester,
    ) async {
      await openHome(tester);

      expect(find.text(SalesStaffHomeCopy.addReceiptHint), findsOneWidget);
      // "to qualify", never "to earn".
      expect(
        SalesStaffHomeCopy.addReceiptHint.toLowerCase(),
        isNot(contains('earn')),
      );
    });

    testWidgets('never overlaps the bottom navigation', (
      WidgetTester tester,
    ) async {
      await openHome(tester);

      final Rect pill = tester.getRect(find.byType(SalesStaffAddReceiptPill));
      final Rect bar = tester.getRect(find.byType(NavigationBar));

      expect(
        pill.bottom,
        lessThanOrEqualTo(bar.top),
        reason: 'the floating action must sit above the bottom bar',
      );
    });

    testWidgets('never overlaps the hero action', (WidgetTester tester) async {
      // The two controls do different things; a thumb between them must not be
      // ambiguous. The hero action is left-aligned and the pill right-aligned.
      await openHome(tester);

      final Rect pill = tester.getRect(find.byType(SalesStaffAddReceiptPill));
      final Rect action = tester.getRect(
        find.widgetWithText(SrButton, SalesStaffHomeCopy.heroAction),
      );

      expect(pill.overlaps(action), isFalse);
    });

    testWidgets('moves into the header where the shell has a rail', (
      WidgetTester tester,
    ) async {
      await openHome(tester, surface: tabletSurface);

      // No floating pill to sit above a bottom bar that is not there.
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
  group('navigation', () {
    testWidgets('a phone gets a bottom bar with all five destinations', (
      WidgetTester tester,
    ) async {
      await openHome(tester);

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      for (final String label in <String>[
        'Home',
        'Submit',
        'History',
        'Campaigns',
        'Earnings',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
    });

    testWidgets('a tablet promotes to a rail', (WidgetTester tester) async {
      await openHome(tester, surface: tabletSurface);

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
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
          campaigns: targetAndPerUnit(),
          progress: <CampaignTargetProgress>[exampleTargetProgress()],
        );

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the desktop layout keeps a reading measure', (
      WidgetTester tester,
    ) async {
      await openHome(tester, surface: desktopSurface);

      // The hero must not be stretched across a 1280px browser.
      final Rect hero = tester.getRect(find.byType(SalesStaffNextRewardHero));
      expect(hero.width, lessThan(desktopSurface.width - 200));
    });

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
      // The numbers stay readable, and the gauge never replaces them.
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
