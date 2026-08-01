import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sale_reward/app/shells/retailer_manager/retailer_manager_navigation.dart';
import 'package:sale_reward/app/shells/retailer_owner/retailer_owner_navigation.dart';
import 'package:sale_reward/app/shells/sales_staff/sales_staff_navigation.dart';
import 'package:sale_reward/core/errors/retailer_read_problem.dart';
import 'package:sale_reward/core/widgets/widgets.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_lifecycle_state.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_measurement.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_product.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_product_eligibility.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_reward.dart';
import 'package:sale_reward/features/campaigns/domain/entities/retailer_campaign.dart';
import 'package:sale_reward/features/campaigns/domain/entities/staff_campaign.dart';
import 'package:sale_reward/features/campaigns/domain/repositories/retailer_campaign_repository.dart';
import 'package:sale_reward/features/campaigns/domain/repositories/staff_campaign_repository.dart';
import 'package:sale_reward/features/campaigns/presentation/retailer_owner/pages/retailer_owner_campaign_detail_page.dart';
import 'package:sale_reward/features/campaigns/presentation/retailer_owner/pages/retailer_owner_campaigns_page.dart';
import 'package:sale_reward/features/campaigns/presentation/sales_staff/pages/sales_staff_campaign_detail_page.dart';
import 'package:sale_reward/features/campaigns/presentation/sales_staff/pages/sales_staff_campaigns_page.dart';
import 'package:sale_reward/features/campaigns/presentation/shared/campaign_card.dart';
import 'package:sale_reward/features/campaigns/presentation/shared/campaign_copy.dart';
import 'package:sale_reward/features/campaigns/presentation/shared/campaign_detail_view.dart';

import '../../support/campaign_fakes.dart';
import '../../support/pump_app.dart';

/// Drives both campaign experiences through the real application: real router,
/// real shells, real cubits, over fakes that never touch Supabase.
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

  // =========================================================================
  group('Retailer Owner campaign list', () {
    testWidgets('the Campaigns destination routes to the list', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.retailerOwner);

      await goTo(tester, RetailerOwnerNavigation.campaigns);

      expect(find.byType(RetailerOwnerCampaignsPage), findsOneWidget);
      expect(find.text(CampaignCopy.title), findsWidgets);
    });

    testWidgets('opening the tab issues exactly one read', (
      WidgetTester tester,
    ) async {
      final FakeRetailerCampaignRepository campaigns =
          FakeRetailerCampaignRepository();
      await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
        retailerCampaigns: campaigns,
      );

      // Entering the shell reads nothing: the cubit is provided, not loaded.
      expect(campaigns.callCount, 0);

      await goTo(tester, RetailerOwnerNavigation.campaigns);
      expect(campaigns.callCount, 1);

      // Leaving and returning reads nothing — `loadOnce` is a no-op once the
      // phase has left `initial`.
      await goTo(tester, RetailerOwnerNavigation.products);
      await goTo(tester, RetailerOwnerNavigation.campaigns);
      expect(campaigns.callCount, 1);
    });

    testWidgets('shows a skeleton while the first read is in flight', (
      WidgetTester tester,
    ) async {
      final FakeRetailerCampaignRepository campaigns =
          FakeRetailerCampaignRepository()..manual = true;
      await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
        retailerCampaigns: campaigns,
      );

      GoRouter.of(
        tester.element(find.byType(Navigator).first),
      ).go(RetailerOwnerNavigation.campaigns);
      await tester.pump();
      await tester.pump();

      // Skeletons, not spinners, are this product's loading language.
      expect(find.byType(SrSkeleton), findsWidgets);
      expect(find.byType(CampaignCard), findsNothing);

      campaigns.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CampaignCard), findsOneWidget);
    });

    testWidgets('an empty answer is an empty state, not an error', (
      WidgetTester tester,
    ) async {
      final FakeRetailerCampaignRepository campaigns =
          FakeRetailerCampaignRepository()
            ..nextCampaigns = <RetailerCampaign>[];
      await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
        retailerCampaigns: campaigns,
      );

      await goTo(tester, RetailerOwnerNavigation.campaigns);

      expect(find.byType(SrEmptyState), findsOneWidget);
      expect(find.text(CampaignCopy.emptyTitle), findsOneWidget);
      expect(find.text(CampaignCopy.retailerEmptyBody), findsOneWidget);
      // A real answer, never dressed as a failure.
      expect(find.byType(SrRetailerProblemView), findsNothing);
    });

    testWidgets('a denial is a retryable problem view, not an empty list', (
      WidgetTester tester,
    ) async {
      final FakeRetailerCampaignRepository campaigns =
          FakeRetailerCampaignRepository()
            ..listResult = const RetailerCampaignsFailed(
              RetailerReadProblem.denied,
            );
      await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
        retailerCampaigns: campaigns,
      );

      await goTo(tester, RetailerOwnerNavigation.campaigns);

      expect(find.byType(SrRetailerProblemView), findsOneWidget);
      expect(find.byType(CampaignCard), findsNothing);
      // Never the "no campaigns yet" copy: a refusal and an empty catalogue are
      // opposite claims. (`SrRetailerProblemView` renders through
      // `SrEmptyState`, so the widget type alone cannot tell them apart — the
      // copy can.)
      expect(find.text(CampaignCopy.emptyTitle), findsNothing);
      expect(find.text(CampaignCopy.retailerEmptyBody), findsNothing);
    });

    testWidgets('a card carries every fact and no fake progress', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.retailerOwner);
      await goTo(tester, RetailerOwnerNavigation.campaigns);

      expect(find.text('Summer Push'), findsOneWidget);
      expect(find.textContaining('Northwind Trading'), findsOneWidget);
      expect(
        find.text('Earn 10 coins per eligible unit, up to 100 coins.'),
        findsOneWidget,
      );
      expect(find.text('Individual'), findsOneWidget);
      expect(find.text('3 eligible products'), findsOneWidget);
      expect(find.text('Running'), findsOneWidget);

      // No progress bar and no earned balance anywhere on the list.
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('earned'), findsNothing);
    });

    testWidgets('sections group by lifecycle state, and empties are omitted', (
      WidgetTester tester,
    ) async {
      final FakeRetailerCampaignRepository campaigns =
          FakeRetailerCampaignRepository()
            ..nextCampaigns =
                <CampaignLifecycleState>[
                  CampaignLifecycleState.active,
                  CampaignLifecycleState.ended,
                ].map((CampaignLifecycleState state) {
                  return exampleRetailerCampaign(
                    offer: exampleOffer(
                      lifecycleState: state,
                      name: 'Campaign ${state.name}',
                    ),
                  );
                }).toList();

      await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
        retailerCampaigns: campaigns,
      );
      await goTo(tester, RetailerOwnerNavigation.campaigns);

      Finder heading(String title) => find.descendant(
        of: find.byType(SrSectionHeader),
        matching: find.text(title),
      );

      expect(heading('Running now'), findsOneWidget);
      expect(heading('Finished'), findsOneWidget);
      // Never a heading with nothing under it. Asserted against the heading
      // widget rather than the raw text, because a status badge legitimately
      // uses some of the same words.
      expect(heading('Paused'), findsNothing);
      expect(heading('Cancelled'), findsNothing);
      expect(heading('Starting soon'), findsNothing);
      expect(find.byType(SrSectionHeader), findsNWidgets(2));
    });

    testWidgets('the list states that results are not connected yet', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.retailerOwner);
      await goTo(tester, RetailerOwnerNavigation.campaigns);

      expect(find.text(CampaignCopy.engineNotice), findsOneWidget);
    });

    testWidgets('there is no Vendor management action anywhere', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.retailerOwner);
      await goTo(tester, RetailerOwnerNavigation.campaigns);

      for (final String action in <String>[
        'Edit',
        'Publish',
        'Pause',
        'Resume',
        'New version',
        'Cancel',
        'Create campaign',
        'New campaign',
      ]) {
        expect(find.text(action), findsNothing, reason: action);
      }
    });
  });

  // =========================================================================
  group('Retailer Owner campaign detail', () {
    testWidgets('tapping a card opens the detail for that campaign', (
      WidgetTester tester,
    ) async {
      final FakeRetailerCampaignRepository campaigns =
          FakeRetailerCampaignRepository();
      await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
        retailerCampaigns: campaigns,
      );
      await goTo(tester, RetailerOwnerNavigation.campaigns);

      await tapVisible(tester, find.byType(CampaignCard));

      expect(find.byType(RetailerOwnerCampaignDetailPage), findsOneWidget);
      // The id the card carried is exactly what the read was addressed with,
      // and it is the only value transmitted.
      expect(campaigns.requestedCampaignIds, <String>[campaignIdA]);
      // The detail is pushed on top of the list rather than replacing it, so
      // the list is still on the navigator stack (offstage) and Back pops
      // straight to it — asserted by the back-navigation test below.
    });

    testWidgets('the whole card is one semantic button', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.retailerOwner);
      await goTo(tester, RetailerOwnerNavigation.campaigns);

      final Finder label = semanticsContaining('Summer Push. Running.');
      expect(label, findsOneWidget);
      expect(tester.widget<Semantics>(label).properties.button, isTrue);
    });

    testWidgets('renders every section in the specified order', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.retailerOwner);
      await goTo(tester, RetailerOwnerNavigation.campaigns);
      await tapVisible(tester, find.byType(CampaignCard));

      expect(find.byType(CampaignDetailView), findsOneWidget);
      expect(find.text('Summer Push'), findsOneWidget);
      expect(find.textContaining('Northwind Trading'), findsOneWidget);
      expect(find.text(CampaignCopy.rewardSectionTitle), findsOneWidget);
      expect(find.text(CampaignCopy.measurementSectionTitle), findsOneWidget);
      expect(find.text(CampaignCopy.productsSectionTitle), findsOneWidget);
      expect(find.text(CampaignCopy.scheduleSectionTitle), findsOneWidget);
      expect(find.text(CampaignCopy.stackingSectionTitle), findsOneWidget);
      expect(find.text(CampaignCopy.engineNotice), findsOneWidget);
    });

    testWidgets('lists the eligible products, and shows the campaign zone', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.retailerOwner);
      await goTo(tester, RetailerOwnerNavigation.campaigns);
      await tapVisible(tester, find.byType(CampaignCard));

      expect(find.text('Summer Cooler 500ml'), findsOneWidget);
      expect(find.text('Summer Cooler 1L'), findsOneWidget);
      expect(find.text('Asia/Dubai'), findsOneWidget);
      expect(
        find.text(CampaignCopy.timeZoneNote('Asia/Dubai')),
        findsOneWidget,
      );
    });

    testWidgets('an unauthorized or unknown id is a safe not-found', (
      WidgetTester tester,
    ) async {
      final FakeRetailerCampaignRepository campaigns =
          FakeRetailerCampaignRepository()
            ..detailResult = const RetailerCampaignDetailMissing();
      await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
        retailerCampaigns: campaigns,
      );

      await goTo(tester, RetailerOwnerNavigation.campaignDetail(campaignIdB));

      expect(find.text(CampaignCopy.notFoundTitle), findsOneWidget);
      expect(find.text(CampaignCopy.notFoundBody), findsOneWidget);
      // No retry: the backend answered, and it will answer the same way.
      expect(find.text('Try again'), findsNothing);
      expect(find.byType(CampaignDetailView), findsNothing);
      // And nothing about the campaign leaks — not even that it exists.
      expect(find.text('Summer Push'), findsNothing);
    });

    testWidgets('a malformed id reaches the identical screen', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.retailerOwner);

      await goTo(tester, '${RetailerOwnerNavigation.campaigns}/not-a-uuid');

      expect(find.text(CampaignCopy.notFoundTitle), findsOneWidget);
    });

    testWidgets('back returns to the list and re-reads it', (
      WidgetTester tester,
    ) async {
      final FakeRetailerCampaignRepository campaigns =
          FakeRetailerCampaignRepository();
      await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
        retailerCampaigns: campaigns,
      );
      await goTo(tester, RetailerOwnerNavigation.campaigns);
      expect(campaigns.callCount, 1);

      await tapVisible(tester, find.byType(CampaignCard));
      await tapVisible(tester, find.text(CampaignCopy.backToCampaigns));

      expect(find.byType(RetailerOwnerCampaignDetailPage), findsNothing);
      expect(find.byType(RetailerOwnerCampaignsPage), findsOneWidget);
      // The canonical refresh: a campaign can be paused or superseded while its
      // detail is open, so the list asks the backend again rather than trusting
      // what it had on the way in.
      expect(campaigns.callCount, 2);
    });

    testWidgets('the detail carries no Vendor management action', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.retailerOwner);
      await goTo(tester, RetailerOwnerNavigation.campaigns);
      await tapVisible(tester, find.byType(CampaignCard));

      for (final String action in <String>[
        'Edit',
        'Publish',
        'Pause',
        'Resume',
        'New version',
        'Cancel',
      ]) {
        expect(find.text(action), findsNothing, reason: action);
      }
    });
  });

  // =========================================================================
  group('Sales Staff campaigns', () {
    testWidgets('the Campaigns destination routes to the seller list', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.salesStaff);

      await goTo(tester, SalesStaffNavigation.campaigns);

      expect(find.byType(SalesStaffCampaignsPage), findsOneWidget);
    });

    testWidgets('Submit remains the landing tab', (WidgetTester tester) async {
      await pumpAppInRole(tester, PortalKind.salesStaff);

      expect(currentLocation(tester), SalesStaffNavigation.submit);
    });

    testWidgets('a seller card shows no Vendor', (WidgetTester tester) async {
      await pumpAppInRole(tester, PortalKind.salesStaff);
      await goTo(tester, SalesStaffNavigation.campaigns);

      expect(find.text('Summer Push'), findsOneWidget);
      // The contract withholds the Vendor NAME, so no card carries one and no
      // placeholder stands in for it.
      expect(find.textContaining('Northwind'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(CampaignCard),
          matching: find.textContaining('${CampaignCopy.vendorLabel} ·'),
        ),
        findsNothing,
      );
    });

    testWidgets('individual wording is the seller sentence', (
      WidgetTester tester,
    ) async {
      final FakeStaffCampaignRepository campaigns =
          FakeStaffCampaignRepository()
            ..nextCampaigns = <StaffCampaign>[
              exampleStaffCampaign(
                offer: exampleOffer(
                  performanceScope: CampaignPerformanceScope.individualStaff,
                ),
              ),
            ];

      await pumpAppInRole(
        tester,
        PortalKind.salesStaff,
        staffCampaigns: campaigns,
      );
      await goTo(tester, SalesStaffNavigation.campaigns);
      await tapVisible(tester, find.byType(CampaignCard));

      expect(
        find.text('Your eligible sales are measured separately.'),
        findsOneWidget,
      );
    });

    testWidgets('Retailer-team wording is the shared-target sentence', (
      WidgetTester tester,
    ) async {
      final FakeStaffCampaignRepository campaigns =
          FakeStaffCampaignRepository()
            ..detailResult = StaffCampaignDetailLoaded(
              campaign: exampleStaffCampaign(
                offer: exampleOffer(
                  performanceScope: CampaignPerformanceScope.retailerTeam,
                  reward: const CampaignTargetReward(
                    thresholdUnits: 25,
                    rewardCoins: 2500,
                    maxRewardCoins: null,
                    metric: CampaignMetricType.unitsSold,
                  ),
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
          'Eligible Sales Staff sales in your Retailer contribute to the '
          'shared Retailer target.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'When your Retailer reaches 25 eligible units, contributing Sales '
          'Staff share the configured 2,500-coin reward according to the '
          'campaign rules.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('selected-product wording appears for a snapshot campaign', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.salesStaff);
      await goTo(tester, SalesStaffNavigation.campaignDetail(campaignIdA));

      expect(
        find.text(
          CampaignCopy.eligibilitySentence(
            CampaignProductScope.selectedProducts,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('live-temporal wording appears for an all-products campaign', (
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
          CampaignCopy.eligibilitySentence(
            CampaignProductScope.allEligibleProducts,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a seller sees no Retailer Owner or Vendor action', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.salesStaff);
      await goTo(tester, SalesStaffNavigation.campaigns);

      for (final String action in <String>[
        'Edit',
        'Publish',
        'Pause',
        'Resume',
        'Cancel',
        'New version',
        'Invite',
        'Deactivate',
        'Manage shops',
      ]) {
        expect(find.text(action), findsNothing, reason: action);
      }
    });

    testWidgets('a paused campaign is the same not-found as an unknown id', (
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
      await goTo(tester, SalesStaffNavigation.campaignDetail(campaignIdA));

      expect(find.text(CampaignCopy.notFoundTitle), findsOneWidget);
      // Nothing hints that the campaign exists and has been paused.
      expect(find.textContaining('paused'), findsNothing);
      expect(find.textContaining('Paused'), findsNothing);
    });

    testWidgets('the seller detail routes back to the seller list', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.salesStaff);
      await goTo(tester, SalesStaffNavigation.campaigns);
      await tapVisible(tester, find.byType(CampaignCard));
      expect(find.byType(SalesStaffCampaignDetailPage), findsOneWidget);

      await tapVisible(tester, find.text(CampaignCopy.backToCampaigns));

      expect(find.byType(SalesStaffCampaignDetailPage), findsNothing);
      expect(find.byType(SalesStaffCampaignsPage), findsOneWidget);
    });
  });

  // =========================================================================
  group('the zero-eligible-product warning', () {
    Future<void> pumpWithCount(
      WidgetTester tester,
      int count, {
      CampaignLifecycleState state = CampaignLifecycleState.active,
    }) async {
      final FakeRetailerCampaignRepository campaigns =
          FakeRetailerCampaignRepository()
            ..nextCampaigns = <RetailerCampaign>[
              exampleRetailerCampaign(
                offer: exampleOffer(
                  lifecycleState: state,
                  eligibleProductCount: count,
                ),
              ),
            ]
            ..detailResult = RetailerCampaignDetailLoaded(
              campaign: exampleRetailerCampaign(
                offer: exampleOffer(
                  lifecycleState: state,
                  eligibleProductCount: count,
                ),
              ),
              products: count == 0
                  ? const <CampaignProduct>[]
                  : exampleCampaignProducts,
            );

      await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
        retailerCampaigns: campaigns,
      );
      await goTo(tester, RetailerOwnerNavigation.campaigns);
    }

    testWidgets('appears on the card at zero', (WidgetTester tester) async {
      await pumpWithCount(tester, 0);

      expect(find.text(CampaignCopy.noProductsCardNote), findsOneWidget);
      // The accurate count is preserved, not rounded away or hidden.
      expect(find.text('No eligible products'), findsOneWidget);
      // And the campaign is still listed.
      expect(find.byType(CampaignCard), findsOneWidget);
    });

    testWidgets('appears prominently on the detail at zero', (
      WidgetTester tester,
    ) async {
      await pumpWithCount(tester, 0);
      await tapVisible(tester, find.byType(CampaignCard));

      expect(find.text(CampaignCopy.noProductsTitle), findsOneWidget);
      expect(find.text(CampaignCopy.noProductsBody), findsOneWidget);
      // Icon and text, not colour alone.
      expect(find.byIcon(Icons.warning_amber_rounded), findsWidgets);
    });

    testWidgets('is absent above zero, on both surfaces', (
      WidgetTester tester,
    ) async {
      await pumpWithCount(tester, 1);

      expect(find.text(CampaignCopy.noProductsCardNote), findsNothing);
      expect(find.text('1 eligible product'), findsOneWidget);

      await tapVisible(tester, find.byType(CampaignCard));
      expect(find.text(CampaignCopy.noProductsBody), findsNothing);
    });

    testWidgets('is absent for a finished campaign with zero products', (
      WidgetTester tester,
    ) async {
      // It cannot reward anything either way, so a warning would imply a
      // consequence that does not follow.
      await pumpWithCount(tester, 0, state: CampaignLifecycleState.ended);

      expect(find.text(CampaignCopy.noProductsCardNote), findsNothing);

      await tapVisible(tester, find.byType(CampaignCard));
      expect(find.text(CampaignCopy.noProductsBody), findsNothing);
      // The honest count is still shown.
      expect(find.text('No eligible products'), findsWidgets);
    });

    testWidgets('appears for a scheduled campaign with zero products', (
      WidgetTester tester,
    ) async {
      await pumpWithCount(tester, 0, state: CampaignLifecycleState.scheduled);

      expect(find.text(CampaignCopy.noProductsCardNote), findsOneWidget);
    });
  });

  // =========================================================================
  group('layout and text scaling', () {
    testWidgets('a very long campaign name does not overflow', (
      WidgetTester tester,
    ) async {
      final FakeRetailerCampaignRepository campaigns =
          FakeRetailerCampaignRepository()
            ..nextCampaigns = <RetailerCampaign>[
              exampleRetailerCampaign(
                offer: exampleOffer(
                  // 150 characters is the schema maximum for a campaign name.
                  name: 'A' * 150,
                ),
              ),
            ];

      await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
        retailerCampaigns: campaigns,
        surface: smallPhoneSurface,
      );
      await goTo(tester, RetailerOwnerNavigation.campaigns);

      expect(tester.takeException(), isNull);
      expect(find.byType(CampaignCard), findsOneWidget);
    });

    testWidgets('a long Vendor name and date range do not overflow', (
      WidgetTester tester,
    ) async {
      final FakeRetailerCampaignRepository campaigns =
          FakeRetailerCampaignRepository()
            ..nextCampaigns = <RetailerCampaign>[
              exampleRetailerCampaign(
                vendorName: 'An Extremely Long Vendor Organization Name Ltd',
                offer: exampleOffer(evergreen: true),
              ),
            ];

      await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
        retailerCampaigns: campaigns,
        surface: smallPhoneSurface,
      );
      await goTo(tester, RetailerOwnerNavigation.campaigns);

      expect(tester.takeException(), isNull);
    });

    testWidgets('primary content survives a large text scale', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
        surface: smallPhoneSurface,
      );
      await goTo(tester, RetailerOwnerNavigation.campaigns);

      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // The campaign is still identifiable at double scale.
      expect(find.text('Summer Push'), findsOneWidget);
    });

    testWidgets('the detail survives a large text scale', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
        surface: smallPhoneSurface,
      );
      await goTo(tester, RetailerOwnerNavigation.campaignDetail(campaignIdA));

      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(CampaignDetailView), findsOneWidget);
    });
  });

  // =========================================================================
  group('route isolation', () {
    testWidgets('the Retailer Manager has no campaign route', (
      WidgetTester tester,
    ) async {
      // CAMPAIGNS_VIEW_ASSIGNED is mapped to RETAILER_OWNER alone, so there is
      // no Manager destination and no Manager route to one.
      await pumpAppInRole(tester, PortalKind.retailerManager);

      await goTo(tester, '${RetailerManagerNavigation.prefix}/campaigns');

      expect(find.byType(RetailerOwnerCampaignsPage), findsNothing);
      expect(find.byType(SalesStaffCampaignsPage), findsNothing);
    });

    testWidgets('a seller cannot reach the Retailer Owner campaign route', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.salesStaff);

      await goTo(tester, RetailerOwnerNavigation.campaigns);

      expect(find.byType(RetailerOwnerCampaignsPage), findsNothing);
      expect(
        currentLocation(tester),
        isNot(startsWith(RetailerOwnerNavigation.prefix)),
      );
    });

    testWidgets('an Owner cannot reach the Sales Staff campaign route', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.retailerOwner);

      await goTo(tester, SalesStaffNavigation.campaigns);

      expect(find.byType(SalesStaffCampaignsPage), findsNothing);
      expect(
        currentLocation(tester),
        isNot(startsWith(SalesStaffNavigation.prefix)),
      );
    });
  });
}
