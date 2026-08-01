import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sale_reward/app/shells/retailer_owner/retailer_owner_navigation.dart';
import 'package:sale_reward/app/shells/retailer_owner/retailer_owner_shell.dart';
import 'package:sale_reward/app/shells/sales_staff/sales_staff_navigation.dart';
import 'package:sale_reward/app/shells/sales_staff/sales_staff_shell.dart';
import 'package:sale_reward/features/auth/domain/entities/auth_user.dart';
import 'package:sale_reward/features/auth/domain/entities/lifecycle_access_state.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/auth/presentation/pages/access_denied_page.dart';
import 'package:sale_reward/features/auth/presentation/pages/login_page.dart';
import 'package:sale_reward/features/campaigns/presentation/retailer_owner/pages/retailer_owner_campaigns_page.dart';
import 'package:sale_reward/features/campaigns/presentation/sales_staff/pages/sales_staff_campaigns_page.dart';
import 'package:sale_reward/features/campaigns/presentation/shared/campaign_card.dart';

import '../../support/campaign_fakes.dart';
import '../../support/fakes.dart';
import '../../support/lifecycle_access_fakes.dart';
import '../../support/pump_app.dart';

/// A second signed-in person, at a different Retailer.
const AuthUser otherUser = AuthUser(id: 'user-2', email: 'other@example.com');

/// The campaign screens sit **inside** the existing session and lifecycle
/// protections, and this file proves they neither weaken nor bypass them.
///
/// Nothing in the campaign feature subscribes to auth, resolves a portal
/// context, or decides whether a caller may be here. It is routed like every
/// other destination and cleared like every other private cubit.
void main() {
  Future<void> goTo(WidgetTester tester, String location) async {
    GoRouter.of(tester.element(find.byType(Navigator).first)).go(location);
    await tester.pumpAndSettle();
  }

  Future<void> sendAppToBackgroundAndResume(WidgetTester tester) async {
    for (final AppLifecycleState state in <AppLifecycleState>[
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
  }

  // -------------------------------------------------------------------------
  group('mid-session revalidation still applies on a campaign screen', () {
    testWidgets(
      'a Retailer deactivated while the app is backgrounded blocks the Owner '
      'on the Campaigns tab',
      (WidgetTester tester) async {
        final FakeLifecycleAccessRepository lifecycleAccess =
            FakeLifecycleAccessRepository()
              ..resolveWith(LifecycleAccessState.organizationInactive);

        final PumpedApp app = await pumpAppInRole(
          tester,
          PortalKind.retailerOwner,
          lifecycleAccess: lifecycleAccess,
        );
        await goTo(tester, RetailerOwnerNavigation.campaigns);
        expect(find.byType(RetailerOwnerCampaignsPage), findsOneWidget);

        // The Vendor deactivated the Retailer while the app was backgrounded.
        app.portal.result = deniedResult;
        await sendAppToBackgroundAndResume(tester);
        await tester.pumpAndSettle();

        // The existing revalidation runs, unchanged: the campaign screen has no
        // say in it and does not delay it.
        expect(app.portal.resolveCallCount, 2);
        expect(find.byType(AccessDeniedPage), findsOneWidget);
        expect(find.text('Retailer inactive'), findsOneWidget);
        expect(find.byType(RetailerOwnerCampaignsPage), findsNothing);
        expect(find.byType(RetailerOwnerShell), findsNothing);
      },
    );

    testWidgets(
      'a deactivated Sales Staff member cannot continue on the Campaigns tab',
      (WidgetTester tester) async {
        final FakeLifecycleAccessRepository lifecycleAccess =
            FakeLifecycleAccessRepository()
              ..resolveWith(LifecycleAccessState.membershipInactive);

        final PumpedApp app = await pumpAppInRole(
          tester,
          PortalKind.salesStaff,
          lifecycleAccess: lifecycleAccess,
        );
        await goTo(tester, SalesStaffNavigation.campaigns);
        expect(find.byType(SalesStaffCampaignsPage), findsOneWidget);

        app.portal.result = deniedResult;
        await sendAppToBackgroundAndResume(tester);
        await tester.pumpAndSettle();

        expect(app.portal.resolveCallCount, 2);
        expect(find.byType(AccessDeniedPage), findsOneWidget);
        expect(find.text('Account inactive'), findsOneWidget);
        expect(find.byType(SalesStaffCampaignsPage), findsNothing);
        expect(find.byType(SalesStaffShell), findsNothing);
      },
    );

    testWidgets(
      'a deactivated Retailer blocks its Sales Staff on the Campaigns tab',
      (WidgetTester tester) async {
        // The Retailer, not the individual: the same denial reaches everyone
        // who resolves through that organization.
        final FakeLifecycleAccessRepository lifecycleAccess =
            FakeLifecycleAccessRepository()
              ..resolveWith(LifecycleAccessState.organizationInactive);

        final PumpedApp app = await pumpAppInRole(
          tester,
          PortalKind.salesStaff,
          lifecycleAccess: lifecycleAccess,
        );
        await goTo(tester, SalesStaffNavigation.campaigns);

        app.portal.result = deniedResult;
        await sendAppToBackgroundAndResume(tester);
        await tester.pumpAndSettle();

        expect(find.byType(AccessDeniedPage), findsOneWidget);
        expect(find.text('Retailer inactive'), findsOneWidget);
        expect(find.byType(SalesStaffCampaignsPage), findsNothing);
      },
    );

    testWidgets('an open campaign detail is left behind too', (
      WidgetTester tester,
    ) async {
      final FakeLifecycleAccessRepository lifecycleAccess =
          FakeLifecycleAccessRepository()
            ..resolveWith(LifecycleAccessState.membershipInactive);

      final PumpedApp app = await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
        lifecycleAccess: lifecycleAccess,
      );
      await goTo(tester, RetailerOwnerNavigation.campaignDetail(campaignIdA));
      expect(find.text('Summer Push'), findsWidgets);

      app.portal.result = deniedResult;
      await sendAppToBackgroundAndResume(tester);
      await tester.pumpAndSettle();

      expect(find.byType(AccessDeniedPage), findsOneWidget);
      // The campaign's own terms are gone with the shell.
      expect(find.text('Summer Push'), findsNothing);
    });

    testWidgets('signing out clears the campaign screen', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
      );
      await goTo(tester, RetailerOwnerNavigation.campaigns);
      expect(find.byType(CampaignCard), findsOneWidget);

      app.auth.emitSignedOut();
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(CampaignCard), findsNothing);
      expect(find.text('Summer Push'), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  group('campaign state does not survive a change of identity', () {
    testWidgets('another Retailer Owner never sees the previous one\'s '
        'campaigns', (WidgetTester tester) async {
      final FakeRetailerCampaignRepository campaigns =
          FakeRetailerCampaignRepository();
      final PumpedApp app = await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
        retailerCampaigns: campaigns,
      );
      await goTo(tester, RetailerOwnerNavigation.campaigns);
      expect(find.text('Summer Push'), findsOneWidget);

      // A different Owner, at a different Retailer, in the same shell — the
      // transition the shell's identity listener exists for, because the route
      // never leaves `/retailer-owner/...` and the element survives.
      app.portal.result = otherRetailerOwnerResult();
      app.auth.emitSignedIn(otherUser);
      await tester.pumpAndSettle();

      // Which Vendor targets a Retailer, and on what terms, is a commercial
      // fact about one relationship. It must not appear under another session.
      expect(find.text('Summer Push'), findsNothing);
      expect(find.byType(CampaignCard), findsNothing);
    });

    testWidgets('a stale campaign read cannot repopulate the new session', (
      WidgetTester tester,
    ) async {
      final FakeRetailerCampaignRepository campaigns =
          FakeRetailerCampaignRepository()..manual = true;
      final PumpedApp app = await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
        retailerCampaigns: campaigns,
      );

      GoRouter.of(
        tester.element(find.byType(Navigator).first),
      ).go(RetailerOwnerNavigation.campaigns);
      await tester.pump();
      await tester.pump();
      expect(campaigns.pendingCount, 1);

      // The session changes while the read is still in flight.
      app.portal.result = otherRetailerOwnerResult();
      app.auth.emitSignedIn(otherUser);
      await tester.pumpAndSettle();

      // The previous identity's answer lands afterwards, and is dropped: the
      // request token advanced when the shell cleared the cubit.
      campaigns.complete();
      await tester.pumpAndSettle();

      expect(find.text('Summer Push'), findsNothing);
      expect(find.byType(CampaignCard), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  group('the campaign feature adds no session machinery of its own', () {
    testWidgets('entering a shell issues no campaign read', (
      WidgetTester tester,
    ) async {
      final FakeRetailerCampaignRepository owner =
          FakeRetailerCampaignRepository();
      final FakeStaffCampaignRepository seller = FakeStaffCampaignRepository();

      await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
        retailerCampaigns: owner,
        staffCampaigns: seller,
      );

      // The cubits are provided, not loaded. The tab a user actually opens is
      // the one that issues an RPC.
      expect(owner.callCount, 0);
      expect(owner.detailCallCount, 0);
      // And a Retailer Owner shell never touches the seller contract at all.
      expect(seller.callCount, 0);
      expect(seller.detailCallCount, 0);
    });

    testWidgets('a Sales Staff shell never calls the Retailer Owner contract', (
      WidgetTester tester,
    ) async {
      final FakeRetailerCampaignRepository owner =
          FakeRetailerCampaignRepository();
      final FakeStaffCampaignRepository seller = FakeStaffCampaignRepository();

      await pumpAppInRole(
        tester,
        PortalKind.salesStaff,
        retailerCampaigns: owner,
        staffCampaigns: seller,
      );
      await goTo(tester, SalesStaffNavigation.campaigns);
      await goTo(tester, SalesStaffNavigation.campaignDetail(campaignIdA));

      expect(seller.callCount, greaterThan(0));
      expect(seller.detailCallCount, greaterThan(0));
      // CAMPAIGNS_VIEW_ASSIGNED is mapped to RETAILER_OWNER alone, and this
      // shell has no path to it.
      expect(owner.callCount, 0);
      expect(owner.detailCallCount, 0);
    });

    testWidgets('a Retailer Owner shell never calls the seller contract', (
      WidgetTester tester,
    ) async {
      final FakeRetailerCampaignRepository owner =
          FakeRetailerCampaignRepository();
      final FakeStaffCampaignRepository seller = FakeStaffCampaignRepository();

      await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
        retailerCampaigns: owner,
        staffCampaigns: seller,
      );
      await goTo(tester, RetailerOwnerNavigation.campaigns);
      await goTo(tester, RetailerOwnerNavigation.campaignDetail(campaignIdA));

      expect(owner.callCount, greaterThan(0));
      expect(owner.detailCallCount, greaterThan(0));
      expect(seller.callCount, 0);
      expect(seller.detailCallCount, 0);
    });
  });
}
