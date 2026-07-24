import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/app/navigation/role_destination.dart';
import 'package:sale_reward/app/navigation/role_navigation_registry.dart';
import 'package:sale_reward/app/shells/retailer_manager/retailer_manager_shell.dart';
import 'package:sale_reward/app/shells/retailer_owner/retailer_owner_shell.dart';
import 'package:sale_reward/app/shells/sales_staff/sales_staff_shell.dart';
import 'package:sale_reward/app/shells/vendor/vendor_shell.dart';
import 'package:sale_reward/features/auth/domain/entities/app_role.dart';
import 'package:sale_reward/features/dashboard/presentation/retailer_owner/pages/retailer_owner_overview_page.dart';
import 'package:sale_reward/features/dashboard/presentation/vendor/pages/vendor_dashboard_page.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/pages/sales_staff_submit_page.dart';
import 'package:sale_reward/features/staff/presentation/retailer_manager/pages/retailer_manager_staff_page.dart';

import '../../support/pump_app.dart';

/// The shell widget each role must build, and no other.
const Map<AppRole, Type> _shellTypes = <AppRole, Type>{
  AppRole.vendorSuperAdmin: VendorShell,
  AppRole.retailerOwner: RetailerOwnerShell,
  AppRole.retailerManager: RetailerManagerShell,
  AppRole.salesStaff: SalesStaffShell,
};

/// The landing screen each role must arrive at.
const Map<AppRole, Type> _landingPages = <AppRole, Type>{
  AppRole.vendorSuperAdmin: VendorDashboardPage,
  AppRole.retailerOwner: RetailerOwnerOverviewPage,
  AppRole.retailerManager: RetailerManagerStaffPage,
  AppRole.salesStaff: SalesStaffSubmitPage,
};

/// Makes a shell's destinations visible.
///
/// A bottom bar and a rail render theirs immediately; a drawer hides them behind
/// the menu button.
Future<void> _revealNavigation(
  WidgetTester tester,
  RoleNavigation navigation,
) async {
  if (navigation.chrome != RoleShellChrome.drawer) {
    return;
  }
  await tester.tap(find.byIcon(Icons.menu_rounded));
  await tester.pumpAndSettle();
}

void main() {
  group('every role builds its own shell', () {
    for (final AppRole role in AppRole.values) {
      final RoleNavigation navigation = RoleNavigationRegistry.forRole(role);

      testWidgets('${role.displayName} builds ${_shellTypes[role]}', (
        tester,
      ) async {
        await pumpAppInRole(tester, role);

        expect(find.byType(_shellTypes[role]!), findsOneWidget);

        // Exactly one shell exists — no other role's is in the tree.
        for (final Type other in _shellTypes.values) {
          if (other == _shellTypes[role]) continue;
          expect(
            find.byType(other),
            findsNothing,
            reason: '$other must not appear inside a ${role.displayName} shell',
          );
        }
      });

      testWidgets('${role.displayName} lands on its documented landing path', (
        tester,
      ) async {
        await pumpAppInRole(tester, role);

        expect(
          find.byType(_landingPages[role]!),
          findsOneWidget,
          reason: 'landing must be ${navigation.landingPath}',
        );
        expect(
          find.text(role.displayName.toUpperCase()),
          findsWidgets,
          reason: 'the landing screen must state which role it belongs to',
        );
      });

      testWidgets('${role.displayName} captions itself with its portal', (
        tester,
      ) async {
        await pumpAppInRole(tester, role);

        // The app bar names the portal, never the role — matching the web.
        expect(find.text(navigation.portalName), findsWidgets);
      });

      testWidgets('${role.displayName} offers all of its own destinations', (
        tester,
      ) async {
        await pumpAppInRole(tester, role);
        await _revealNavigation(tester, navigation);

        for (final RoleDestination destination in navigation.destinations) {
          expect(
            find.text(destination.label),
            findsWidgets,
            reason: '${destination.label} is missing from ${role.displayName}',
          );
        }
      });

      testWidgets('${role.displayName} shows the preview banner', (
        tester,
      ) async {
        await pumpAppInRole(tester, role);

        // A locally chosen role must never look like a resolved one.
        expect(find.textContaining('Interface preview'), findsOneWidget);
        expect(find.textContaining('grants no access'), findsOneWidget);
      });

      testWidgets('${role.displayName} renders in dark mode too', (
        tester,
      ) async {
        tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

        await pumpAppInRole(tester, role);

        expect(find.byType(_shellTypes[role]!), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('no role shell exposes another role\'s destinations', () {
    for (final AppRole role in AppRole.values) {
      testWidgets('${role.displayName} shell', (tester) async {
        final RoleNavigation navigation = RoleNavigationRegistry.forRole(role);

        await pumpAppInRole(tester, role);
        await _revealNavigation(tester, navigation);

        final Set<String> ownLabels = navigation.destinations
            .map((RoleDestination d) => d.label)
            .toSet();

        for (final AppRole other in AppRole.values) {
          if (other == role) continue;

          for (final RoleDestination destination
              in RoleNavigationRegistry.forRole(other).destinations) {
            if (ownLabels.contains(destination.label)) {
              // A shared label (Products, Staff) is not a leak.
              continue;
            }
            expect(
              find.text(destination.label),
              findsNothing,
              reason:
                  '"${destination.label}" belongs to ${other.displayName} and '
                  'must not appear in the ${role.displayName} shell',
            );
          }
        }
      });
    }
  });

  group('shell chrome adapts to the viewport', () {
    testWidgets('a Retailer role uses bottom navigation on a phone', (
      tester,
    ) async {
      await pumpAppInRole(tester, AppRole.retailerOwner);

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('the same role promotes to a rail on a tablet', (tester) async {
      await pumpAppInRole(
        tester,
        AppRole.retailerOwner,
        surface: tabletSurface,
      );

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('Sales Staff keeps a concise two-item bar', (tester) async {
      await pumpAppInRole(tester, AppRole.salesStaff);

      final NavigationBar bar = tester.widget<NavigationBar>(
        find.byType(NavigationBar),
      );
      expect(bar.destinations, hasLength(2));
      // The primary write action is the landing tab.
      expect(bar.selectedIndex, 0);
      expect(find.text('Submit a receipt'), findsOneWidget);
    });

    testWidgets('the Vendor uses a drawer, not a crowded bottom bar', (
      tester,
    ) async {
      await pumpAppInRole(tester, AppRole.vendorSuperAdmin);

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byIcon(Icons.menu_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(Drawer), findsOneWidget);
      expect(find.text('Audit Logs'), findsWidgets);
    });

    testWidgets('the Vendor drawer keeps the "Soon" placeholders inert', (
      tester,
    ) async {
      await pumpAppInRole(tester, AppRole.vendorSuperAdmin);
      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Campaigns'), findsOneWidget);
      expect(find.text('SOON'), findsNWidgets(6));

      // Tapping one changes nothing: it is shown, never navigable.
      await tester.tap(find.text('Campaigns'));
      await tester.pumpAndSettle();

      expect(find.byType(VendorDashboardPage), findsOneWidget);
    });

    testWidgets('the Vendor drawer becomes a permanent panel on desktop', (
      tester,
    ) async {
      await pumpAppInRole(
        tester,
        AppRole.vendorSuperAdmin,
        surface: desktopSurface,
      );

      // No hamburger: the panel is already open beside the content.
      expect(find.byIcon(Icons.menu_rounded), findsNothing);
      expect(find.text('Dashboard'), findsWidgets);
    });
  });

  group('shell navigation', () {
    testWidgets('tapping a destination moves to that route', (tester) async {
      await pumpAppInRole(tester, AppRole.salesStaff);

      expect(find.text('Submit a receipt'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.receipt_long_outlined).first);
      await tester.pumpAndSettle();

      expect(find.text('My receipts'), findsOneWidget);
      expect(find.text('Submit a receipt'), findsNothing);

      // Still inside the Sales Staff shell.
      expect(find.byType(SalesStaffShell), findsOneWidget);
    });

    testWidgets('the drawer closes when a destination is chosen', (
      tester,
    ) async {
      await pumpAppInRole(tester, AppRole.vendorSuperAdmin);

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsOneWidget);

      await tester.tap(find.text('Retailers'));
      await tester.pumpAndSettle();

      expect(find.byType(Drawer), findsNothing);
      expect(find.text('Retailers'), findsWidgets);
    });
  });
}
