import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/app/navigation/role_destination.dart';
import 'package:sale_reward/app/navigation/role_navigation_registry.dart';
import 'package:sale_reward/app/shells/retailer_manager/retailer_manager_shell.dart';
import 'package:sale_reward/app/shells/retailer_owner/retailer_owner_shell.dart';
import 'package:sale_reward/app/shells/sales_staff/sales_staff_shell.dart';
import 'package:sale_reward/app/shells/vendor/vendor_shell.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/dashboard/presentation/retailer_owner/pages/retailer_owner_overview_page.dart';
import 'package:sale_reward/features/dashboard/presentation/vendor/pages/vendor_dashboard_page.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/pages/sales_staff_submit_page.dart';
import 'package:sale_reward/features/staff/presentation/retailer_manager/pages/retailer_manager_staff_page.dart';

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
  PortalKind.retailerManager: RetailerManagerStaffPage,
  PortalKind.salesStaff: SalesStaffSubmitPage,
};

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
      expect(find.text('SOON'), findsNWidgets(6));
    });
  });

  group('shell navigation', () {
    testWidgets('tapping a destination moves within the same shell', (
      tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.salesStaff);
      expect(find.text('Submit a receipt'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.receipt_long_outlined).first);
      await tester.pumpAndSettle();

      expect(find.text('My receipts'), findsOneWidget);
      expect(find.byType(SalesStaffShell), findsOneWidget);
    });
  });
}
