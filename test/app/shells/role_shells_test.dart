import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sale_reward/app/navigation/role_destination.dart';
import 'package:sale_reward/app/navigation/role_navigation_registry.dart';
import 'package:sale_reward/app/shells/retailer_manager/retailer_manager_shell.dart';
import 'package:sale_reward/app/shells/retailer_owner/retailer_owner_navigation.dart';
import 'package:sale_reward/app/shells/retailer_owner/retailer_owner_shell.dart';
import 'package:sale_reward/app/shells/sales_staff/sales_staff_navigation.dart';
import 'package:sale_reward/app/shells/sales_staff/sales_staff_shell.dart';
import 'package:sale_reward/app/shells/vendor/vendor_shell.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/campaigns/presentation/retailer_owner/pages/retailer_owner_campaigns_page.dart';
import 'package:sale_reward/features/campaigns/presentation/sales_staff/pages/sales_staff_campaigns_page.dart';
import 'package:sale_reward/features/dashboard/presentation/retailer_owner/pages/retailer_owner_overview_page.dart';
import 'package:sale_reward/features/dashboard/presentation/vendor/pages/vendor_dashboard_page.dart';
import 'package:sale_reward/features/home/presentation/sales_staff/pages/sales_staff_home_page.dart';
import 'package:sale_reward/features/home/presentation/sales_staff/widgets/sales_staff_home_copy.dart';
import 'package:sale_reward/features/staff/presentation/retailer/pages/retailer_staff_page.dart';

import '../../support/fakes.dart';
import '../../support/pump_app.dart';

const List<PortalKind> _shellKinds = <PortalKind>[
  PortalKind.vendorSuperAdmin,
  PortalKind.retailerOwner,
  PortalKind.retailerManager,
  PortalKind.salesStaff,
];

const Map<PortalKind, Type> _shellTypes = <PortalKind, Type>{
  PortalKind.vendorSuperAdmin: VendorShell,
  PortalKind.retailerOwner: RetailerOwnerShell,
  PortalKind.retailerManager: RetailerManagerShell,
  PortalKind.salesStaff: SalesStaffShell,
};

const Map<PortalKind, Type> _landingPages = <PortalKind, Type>{
  PortalKind.vendorSuperAdmin: VendorDashboardPage,
  PortalKind.retailerOwner: RetailerOwnerOverviewPage,
  PortalKind.retailerManager: RetailerStaffPage,
  PortalKind.salesStaff: SalesStaffHomePage,
};

Future<void> _goTo(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Navigator).first)).go(location);
  await tester.pumpAndSettle();
}

Future<void> _revealNavigation(WidgetTester tester, PortalKind kind) async {
  if (RoleNavigationRegistry.forRole(kind)!.chrome != RoleShellChrome.drawer) {
    return;
  }
  await tester.tap(find.byIcon(Icons.menu_rounded));
  await tester.pumpAndSettle();
}

void main() {
  group('every role builds its own shell', () {
    for (final PortalKind kind in _shellKinds) {
      final RoleNavigation navigation = RoleNavigationRegistry.forRole(kind)!;

      testWidgets('${kind.displayName} builds ${_shellTypes[kind]}', (
        tester,
      ) async {
        await pumpAppInRole(tester, kind);

        expect(find.byType(_shellTypes[kind]!), findsOneWidget);
        for (final Type other in _shellTypes.values) {
          if (other == _shellTypes[kind]) continue;
          expect(find.byType(other), findsNothing);
        }
      });

      testWidgets('${kind.displayName} lands on its documented page', (
        tester,
      ) async {
        await pumpAppInRole(tester, kind);
        expect(find.byType(_landingPages[kind]!), findsOneWidget);
      });

      testWidgets('${kind.displayName} captions the app bar with the org', (
        tester,
      ) async {
        await pumpAppInRole(tester, kind);
        // The context builder names the org "Example Org"; the app bar shows it
        // over the portal name.
        expect(find.text('Example Org'), findsWidgets);
        expect(find.text(navigation.portalName), findsWidgets);
      });

      testWidgets('${kind.displayName} offers all of its own destinations', (
        tester,
      ) async {
        await pumpAppInRole(tester, kind);
        await _revealNavigation(tester, kind);

        for (final RoleDestination d in navigation.destinations) {
          expect(
            find.text(d.label),
            findsWidgets,
            reason: '${d.label} is missing from ${kind.displayName}',
          );
        }
      });

      testWidgets('${kind.displayName} renders in dark mode too', (
        tester,
      ) async {
        tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

        await pumpAppInRole(tester, kind);
        expect(find.byType(_shellTypes[kind]!), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('no shell shows another role\'s destinations', () {
    for (final PortalKind kind in _shellKinds) {
      testWidgets('${kind.displayName} shell', (tester) async {
        final RoleNavigation navigation = RoleNavigationRegistry.forRole(kind)!;
        await pumpAppInRole(tester, kind);
        await _revealNavigation(tester, kind);

        final Set<String> ownLabels = navigation.destinations
            .map((RoleDestination d) => d.label)
            .toSet();

        for (final PortalKind other in _shellKinds) {
          if (other == kind) continue;
          for (final RoleDestination d in RoleNavigationRegistry.forRole(
            other,
          )!.destinations) {
            if (ownLabels.contains(d.label)) continue;
            expect(
              find.text(d.label),
              findsNothing,
              reason:
                  '"${d.label}" belongs to ${other.displayName}, not '
                  '${kind.displayName}',
            );
          }
        }
      });
    }
  });

  group('the app bar caption names the role, and never another role', () {
    // The caption is the one place a signed-in person is told which portal is
    // open. Every other name on screen (the org, the destinations) is the same
    // for a Retailer Owner and their seller, so a caption that reads
    // "Retailer Portal" inside the Sales Staff shell is indistinguishable from
    // being signed in as the wrong account.
    const Map<PortalKind, String> captions = <PortalKind, String>{
      PortalKind.vendorSuperAdmin: 'Vendor Admin',
      PortalKind.retailerOwner: 'Retailer Portal',
      PortalKind.retailerManager: 'Retailer Portal',
      PortalKind.salesStaff: 'Sales Staff Portal',
    };

    testWidgets('the Sales Staff shell renders "Sales Staff Portal"', (
      tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.salesStaff);

      expect(find.byType(SalesStaffShell), findsOneWidget);
      expect(find.text('Sales Staff Portal'), findsWidgets);
      // The Retailer caption must not appear anywhere in this shell.
      expect(find.text('Retailer Portal'), findsNothing);
      // The title is still the organization the backend named.
      expect(find.text('Example Org'), findsWidgets);
    });

    testWidgets('the Retailer Owner shell still renders "Retailer Portal"', (
      tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.retailerOwner);

      expect(find.byType(RetailerOwnerShell), findsOneWidget);
      expect(find.text('Retailer Portal'), findsWidgets);
      expect(find.text('Sales Staff Portal'), findsNothing);
      expect(find.text('Example Org'), findsWidgets);
    });

    for (final PortalKind kind in _shellKinds) {
      testWidgets('${kind.displayName} shows no other role\'s caption', (
        tester,
      ) async {
        await pumpAppInRole(tester, kind);

        expect(find.text(captions[kind]!), findsWidgets);
        for (final MapEntry<PortalKind, String> other in captions.entries) {
          if (other.value == captions[kind]) continue;
          expect(
            find.text(other.value),
            findsNothing,
            reason:
                '"${other.value}" belongs to ${other.key.displayName}, not '
                '${kind.displayName}',
          );
        }
      });
    }

    testWidgets('the caption survives navigation within the shell', (
      tester,
    ) async {
      // The caption comes from the role's navigation model, not from the page,
      // so moving off the landing tab must not change it.
      await pumpAppInRole(tester, PortalKind.salesStaff);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.byIcon(Icons.receipt_long_outlined),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sales Staff Portal'), findsWidgets);
      expect(find.text('Retailer Portal'), findsNothing);
    });

    testWidgets('both roles still reach their campaigns, correctly captioned', (
      tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.salesStaff);
      await _goTo(tester, SalesStaffNavigation.campaigns);

      expect(find.byType(SalesStaffCampaignsPage), findsOneWidget);
      expect(find.text('Sales Staff Portal'), findsWidgets);
      expect(find.text('Retailer Portal'), findsNothing);
    });

    testWidgets('the Retailer Owner campaign route keeps its own caption', (
      tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.retailerOwner);
      await _goTo(tester, RetailerOwnerNavigation.campaigns);

      expect(find.byType(RetailerOwnerCampaignsPage), findsOneWidget);
      expect(find.text('Retailer Portal'), findsWidgets);
      expect(find.text('Sales Staff Portal'), findsNothing);
    });
  });

  group('capability hides a destination', () {
    testWidgets('a Retailer Owner with view_shops false loses the Shops tab', (
      tester,
    ) async {
      // A well-formed owner has every capability; flip one off to prove the
      // filter is wired through the shell. It is a presentation hint only.
      await pumpApp(
        tester,
        initialUser: testUser,
        portalResult: ownerWithoutShopsResult(),
      );

      expect(find.byType(RetailerOwnerShell), findsOneWidget);

      // Scope to the navigation bar: the landing page body also mentions
      // "Shops", so an unscoped finder would be misleading.
      Finder inBar(String label) => find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      );
      expect(inBar('Overview'), findsOneWidget);
      expect(inBar('Staff'), findsOneWidget);
      expect(inBar('Products'), findsOneWidget);
      // Shops is hidden, but the shell is intact.
      expect(inBar('Shops'), findsNothing);
      // Sanity: a default owner context DOES carry view_shops.
      expect(
        contextFor(PortalKind.retailerOwner).capabilities.viewShops,
        isTrue,
      );
    });
  });

  group('chrome adapts to the viewport', () {
    testWidgets('a Retailer role uses a bottom bar on a phone', (tester) async {
      await pumpAppInRole(tester, PortalKind.retailerOwner);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('the same role promotes to a rail on a tablet', (tester) async {
      await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
        surface: tabletSurface,
      );
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('the Vendor uses a drawer with its "Soon" placeholders', (
      tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.vendorSuperAdmin);
      expect(find.byType(NavigationBar), findsNothing);

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(Drawer), findsOneWidget);
      expect(find.text('Audit Logs'), findsWidgets);
      // Five, not six: Settings became a real destination when the
      // company/profile screen shipped.
      expect(find.text('SOON'), findsNWidgets(5));
      expect(find.text('Settings'), findsWidgets);
    });
  });

  group('shell navigation', () {
    testWidgets('tapping a destination moves within the same shell', (
      tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.salesStaff);
      // The landing is the home screen; the greeting is its own.
      expect(find.text(SalesStaffHomeCopy.greeting), findsOneWidget);

      // Scoped to the bottom bar. The home screen renders real receipt content
      // of its own, so an unscoped icon finder could match the page rather than
      // the destination it is trying to tap.
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.byIcon(Icons.receipt_long_outlined),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('My invoices / receipts'), findsOneWidget);
      expect(find.byType(SalesStaffShell), findsOneWidget);
    });
  });
}
