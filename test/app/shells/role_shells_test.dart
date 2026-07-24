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
/// A bottom bar and a rail render their destinations immediately; a drawer
/// hides them behind the menu button, so it has to be opened first.
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

        // And exactly one shell exists — no other role's shell is in the tree.
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

        // The screen states which role it belongs to — the page eyebrow and the
        // shell's brand caption both render the name in caps.
        expect(
          find.text(role.displayName.toUpperCase()),
          findsWidgets,
          reason: 'the landing screen must state which role it belongs to',
        );
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
    }
  });

  group('no role shell exposes another role\'s destinations', () {
    for (final AppRole role in AppRole.values) {
      testWidgets('${role.displayName} shell', (tester) async {
        final RoleNavigation navigation = RoleNavigationRegistry.forRole(role);

        await pumpAppInRole(tester, role);
        await _revealNavigation(tester, navigation);

        final Set<String> ownLabels = RoleNavigationRegistry.forRole(
          role,
        ).destinations.map((RoleDestination d) => d.label).toSet();

        for (final AppRole other in AppRole.values) {
          if (other == role) continue;

          for (final RoleDestination destination
              in RoleNavigationRegistry.forRole(other).destinations) {
            if (ownLabels.contains(destination.label)) {
              // Shared label (e.g. Products, Profile) — not a leak.
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
    testWidgets('a three-to-five destination role uses bottom navigation on a '
        'phone', (tester) async {
      await pumpAppInRole(tester, AppRole.salesStaff);

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('the same role promotes to a rail on a tablet', (tester) async {
      await pumpAppInRole(tester, AppRole.salesStaff, surface: tabletSurface);

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('the Vendor role uses a drawer, not a crowded bottom bar', (
      tester,
    ) async {
      await pumpAppInRole(tester, AppRole.vendorSuperAdmin);

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byIcon(Icons.menu_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(Drawer), findsOneWidget);
      expect(find.text('Audit logs'), findsWidgets);
    });
  });

  group('shell navigation', () {
    testWidgets('tapping a destination moves to that route', (tester) async {
      await pumpAppInRole(tester, AppRole.salesStaff);

      expect(find.text('Submit a receipt'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.history_rounded).first);
      await tester.pumpAndSettle();

      expect(find.text('My receipts'), findsOneWidget);
      expect(find.text('Submit a receipt'), findsNothing);

      // Still inside the Sales Staff shell.
      expect(find.byType(SalesStaffShell), findsOneWidget);
    });
  });
}
