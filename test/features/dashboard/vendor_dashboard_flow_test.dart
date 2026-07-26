import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sale_reward/app/router/app_router.dart';
import 'package:sale_reward/app/shells/base/placeholder_destination_page.dart';
import 'package:sale_reward/app/shells/vendor/vendor_navigation.dart';
import 'package:sale_reward/core/widgets/widgets.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/auth/domain/repositories/portal_context_repository.dart';
import 'package:sale_reward/features/auth/presentation/bloc/session_bloc.dart';
import 'package:sale_reward/features/dashboard/domain/entities/vendor_dashboard_summary.dart';
import 'package:sale_reward/features/dashboard/presentation/vendor/pages/vendor_dashboard_page.dart';
import 'package:sale_reward/features/dashboard/presentation/vendor/widgets/vendor_dashboard_copy.dart';
import 'package:sale_reward/features/dashboard/presentation/vendor/widgets/vendor_dashboard_metric_card.dart';
import 'package:sale_reward/features/products/presentation/vendor/pages/vendor_products_page.dart';
import 'package:sale_reward/features/retailers/presentation/vendor/pages/vendor_retailers_page.dart';
import 'package:sale_reward/features/roles/presentation/vendor/pages/vendor_roles_page.dart';
import 'package:sale_reward/features/users/presentation/vendor/pages/vendor_users_page.dart';

import '../../support/fakes.dart';
import '../../support/pump_app.dart';
import '../../support/vendor_dashboard_fakes.dart';

/// Drives the Vendor Dashboard through the real application: real router, real
/// shell, real cubit, over a fake repository that never touches Supabase.

/// Navigates the live router, as a deep link or a typed URL would.
Future<void> goTo(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Navigator).first)).go(location);
  await tester.pumpAndSettle();
}

/// Where the router actually ended up.
String currentLocation(WidgetTester tester) => GoRouter.of(
  tester.element(find.byType(Navigator).first),
).routeInformationProvider.value.uri.path;

/// Scrolls [finder] into view before tapping it.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Any [Semantics] whose label contains [fragment].
Finder semanticsContaining(String fragment) => find.byWidgetPredicate(
  (Widget widget) =>
      widget is Semantics &&
      (widget.properties.label?.contains(fragment) ?? false),
  description: 'Semantics whose label contains "$fragment"',
);

/// The metric card carrying [label].
Finder metricCard(String label) => find.byWidgetPredicate(
  (Widget widget) =>
      widget is VendorDashboardMetricCard && widget.label == label,
  description: 'VendorDashboardMetricCard labelled "$label"',
);

void main() {
  /// Signs in as a Vendor Super Admin and opens the Dashboard.
  Future<PumpedApp> onDashboard(
    WidgetTester tester, {
    FakeVendorDashboardRepository? dashboard,
    Size surface = phoneSurface,
  }) async {
    final PumpedApp app = await pumpAppInRole(
      tester,
      PortalKind.vendorSuperAdmin,
      surface: surface,
      vendorDashboard: dashboard,
    );
    await goTo(tester, VendorNavigation.dashboard);
    return app;
  }

  group('route isolation', () {
    test('the guard sends every other role away', () {
      for (final PortalKind kind in <PortalKind>[
        PortalKind.retailerOwner,
        PortalKind.retailerManager,
        PortalKind.salesStaff,
      ]) {
        final SessionState session = SessionActive(contextFor(kind));
        expect(
          redirectFor(session, VendorNavigation.dashboard),
          sessionHome(session),
        );
      }
    });

    test('a Vendor Super Admin is allowed in', () {
      expect(
        redirectFor(
          SessionActive(contextFor(PortalKind.vendorSuperAdmin)),
          VendorNavigation.dashboard,
        ),
        isNull,
      );
    });

    test('a signed-out caller is sent to login, not to the dashboard', () {
      expect(
        redirectFor(const SessionUnauthenticated(), VendorNavigation.dashboard),
        '/login',
      );
    });

    test('a denied session is sent to access-denied', () {
      expect(
        redirectFor(const SessionDenied(), VendorNavigation.dashboard),
        '/access-denied',
      );
    });

    test('the route is the established Vendor landing path', () {
      expect(VendorNavigation.dashboard, '/vendor/dashboard');
      expect(VendorNavigation.model.landingPath, VendorNavigation.dashboard);
    });

    testWidgets('a Retailer Owner typing the URL lands on their own home', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.retailerOwner);

      await goTo(tester, VendorNavigation.dashboard);

      expect(find.byType(VendorDashboardPage), findsNothing);
      expect(currentLocation(tester), isNot(VendorNavigation.dashboard));
    });

    testWidgets('a Retailer Manager typing the URL lands on their own home', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.retailerManager);

      await goTo(tester, VendorNavigation.dashboard);

      expect(find.byType(VendorDashboardPage), findsNothing);
    });

    testWidgets('a Sales Staff user typing the URL lands on their own home', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.salesStaff);

      await goTo(tester, VendorNavigation.dashboard);

      expect(find.byType(VendorDashboardPage), findsNothing);
    });

    testWidgets('there is no dashboard detail route beneath it', (
      WidgetTester tester,
    ) async {
      // The contract returns four scalars and nothing addressable.
      await onDashboard(tester);

      await goTo(tester, '${VendorNavigation.dashboard}/anything');

      expect(find.byType(VendorDashboardPage), findsNothing);
    });
  });

  group('the placeholder is gone', () {
    testWidgets('the route renders the real page, not a coming-soon card', (
      WidgetTester tester,
    ) async {
      await onDashboard(tester);

      expect(find.byType(VendorDashboardPage), findsOneWidget);
      expect(find.byType(PlaceholderDestinationPage), findsNothing);
    });

    testWidgets('the foundation-build placeholder copy is gone', (
      WidgetTester tester,
    ) async {
      await onDashboard(tester);

      expect(find.text('Foundation build'), findsNothing);
      expect(find.text('Shell ready'), findsNothing);
      expect(find.text('Data pending'), findsNothing);
      // The old placeholder rendered every figure as "Unavailable", which is
      // exactly what a real, non-nullable count must never look like.
      expect(find.text('Unavailable'), findsNothing);
    });

    testWidgets('the Dashboard destination stays selected on the route', (
      WidgetTester tester,
    ) async {
      await onDashboard(tester, surface: tabletSurface);

      final int selected = VendorNavigation.model.indexForLocation(
        VendorNavigation.dashboard,
      );
      expect(
        VendorNavigation.destinations[selected].label,
        VendorDashboardCopy.title,
      );
    });
  });

  group('the trusted organization name', () {
    testWidgets('comes from the session context', (WidgetTester tester) async {
      await pumpApp(
        tester,
        initialUser: testUser,
        portalResult: PortalContextResolved(
          contextFor(
            PortalKind.vendorSuperAdmin,
            organizationName: 'Northwind Trading',
          ),
        ),
      );
      await goTo(tester, VendorNavigation.dashboard);

      expect(find.text('Northwind Trading'), findsWidgets);
      expect(find.text(VendorDashboardCopy.organizationLabel), findsOneWidget);
    });

    testWidgets('is captioned, not presented as the scope of every figure', (
      WidgetTester tester,
    ) async {
      await onDashboard(tester);

      // The page title stays "Dashboard"; the organization is a caption beside
      // it, because two of the four figures are not that organization's.
      expect(find.text(VendorDashboardCopy.title), findsWidgets);
      expect(
        semanticsContaining(VendorDashboardCopy.organizationLabel),
        findsWidgets,
      );
    });
  });

  group('the four metric cards', () {
    testWidgets('all four render with their exact counts', (
      WidgetTester tester,
    ) async {
      await onDashboard(tester);

      expect(
        metricCard(VendorDashboardCopy.activeMembersLabel),
        findsOneWidget,
      );
      expect(metricCard(VendorDashboardCopy.auditEventsLabel), findsOneWidget);
      expect(
        metricCard(VendorDashboardCopy.activeRoleDefinitionsLabel),
        findsOneWidget,
      );
      expect(
        metricCard(VendorDashboardCopy.permissionDefinitionsLabel),
        findsOneWidget,
      );

      expect(find.text('7'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
      expect(find.text('18'), findsOneWidget);
      // Grouped in a fixed locale, exactly as the web renders it.
      expect(find.text('1,204'), findsOneWidget);
    });

    testWidgets('an all-zero tenant summary renders real zeros', (
      WidgetTester tester,
    ) async {
      final FakeVendorDashboardRepository repository =
          FakeVendorDashboardRepository()
            ..nextSummary = emptyTenantDashboardSummary;

      await onDashboard(tester, dashboard: repository);

      // `0` is a real answer for a brand-new Vendor, and the catalogue figures
      // stay non-zero beside it.
      expect(find.text('0'), findsNWidgets(2));
      expect(find.text('6'), findsOneWidget);
      expect(find.text('18'), findsOneWidget);
      expect(find.byType(SrFailureView), findsNothing);
    });

    testWidgets('the Vendor-scoped cards are labelled truthfully', (
      WidgetTester tester,
    ) async {
      await onDashboard(tester);

      expect(find.text(VendorDashboardCopy.activeMembersLabel), findsOneWidget);
      expect(find.text(VendorDashboardCopy.activeMembersHint), findsOneWidget);
      expect(find.text(VendorDashboardCopy.auditEventsLabel), findsOneWidget);
      expect(find.text(VendorDashboardCopy.auditEventsHint), findsOneWidget);
      expect(find.text(VendorDashboardCopy.vendorSectionTitle), findsOneWidget);
    });

    testWidgets('the catalogue cards are labelled as shared, not as yours', (
      WidgetTester tester,
    ) async {
      await onDashboard(tester);

      expect(
        find.text(VendorDashboardCopy.activeRoleDefinitionsLabel),
        findsOneWidget,
      );
      expect(
        find.text(VendorDashboardCopy.activeRoleDefinitionsHint),
        findsOneWidget,
      );
      expect(
        find.text(VendorDashboardCopy.permissionDefinitionsLabel),
        findsOneWidget,
      );
      expect(
        find.text(VendorDashboardCopy.permissionDefinitionsHint),
        findsOneWidget,
      );
      expect(
        find.text(VendorDashboardCopy.catalogueSectionTitle),
        findsOneWidget,
      );
    });

    testWidgets('no card claims a global figure belongs to this Vendor', (
      WidgetTester tester,
    ) async {
      await onDashboard(tester);

      for (final String forbidden in <String>[
        'Your roles',
        'Your active roles',
        'Vendor roles',
        'Roles assigned in this organization',
        'Your permissions',
        'Vendor permissions',
        'Assigned permissions',
        'Active permissions',
      ]) {
        expect(
          find.textContaining(forbidden),
          findsNothing,
          reason: 'a catalogue card must not read "$forbidden"',
        );
      }
    });

    testWidgets('the audit total is never called recent or windowed', (
      WidgetTester tester,
    ) async {
      await onDashboard(tester);

      for (final String forbidden in <String>[
        'Recent events',
        'Events today',
        'This week',
        'Last 30 days',
        'today',
      ]) {
        expect(
          find.textContaining(forbidden),
          findsNothing,
          reason: 'the audit card must not imply the window "$forbidden"',
        );
      }
      // And it says what it actually is.
      expect(find.text(VendorDashboardCopy.auditEventsNote), findsOneWidget);
    });

    testWidgets('the member card is never called profiles or all users', (
      WidgetTester tester,
    ) async {
      await onDashboard(tester);

      for (final String forbidden in <String>[
        'Active profiles',
        'Active users with roles',
        'Invited users',
        'All users',
      ]) {
        expect(find.textContaining(forbidden), findsNothing);
      }
    });

    testWidgets('every card carries a scope chip, not just a colour', (
      WidgetTester tester,
    ) async {
      await onDashboard(tester);

      expect(find.text(VendorDashboardCopy.vendorScopeChip), findsNWidgets(2));
      expect(
        find.text(VendorDashboardCopy.catalogueScopeChip),
        findsNWidgets(2),
      );
    });

    testWidgets('no fabricated metric appears', (WidgetTester tester) async {
      await onDashboard(tester);

      // Scoped to the page. The shell's drawer legitimately lists the six
      // unbuilt modules as "Soon" entries, and this assertion is about what the
      // *dashboard* claims to have counted.
      for (final String forbidden in <String>[
        'Retailers count',
        'Products count',
        'Shops',
        'Assignments',
        'Invitations',
        'Revenue',
        // Not the bare word "Sales": the product is named SalesReward, and the
        // page says so. What must be absent is a sales *figure*.
        'Sales total',
        'Sales volume',
        'Receipts',
        'Claims',
        'Coins',
        'Payouts',
        'Campaigns',
        'Reports',
        'Trend',
        'vs last',
        '%',
      ]) {
        expect(
          find.descendant(
            of: find.byType(VendorDashboardPage),
            matching: find.textContaining(forbidden),
          ),
          findsNothing,
          reason: 'the dashboard must not show "$forbidden"',
        );
      }
    });
  });

  group('accessibility semantics', () {
    testWidgets(
      'each card speaks its label, figure and scope as one sentence',
      (WidgetTester tester) async {
        await onDashboard(tester);

        expect(
          semanticsContaining(
            '${VendorDashboardCopy.activeMembersLabel}: 7. '
            '${VendorDashboardCopy.vendorScopeChip}.',
          ),
          findsOneWidget,
        );
        expect(
          semanticsContaining(
            '${VendorDashboardCopy.auditEventsLabel}: 1,204. '
            '${VendorDashboardCopy.vendorScopeChip}.',
          ),
          findsOneWidget,
        );
        expect(
          semanticsContaining(
            '${VendorDashboardCopy.activeRoleDefinitionsLabel}: 6. '
            '${VendorDashboardCopy.catalogueScopeChip}.',
          ),
          findsOneWidget,
        );
        expect(
          semanticsContaining(
            '${VendorDashboardCopy.permissionDefinitionsLabel}: 18. '
            '${VendorDashboardCopy.catalogueScopeChip}.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('the Refresh action is a labelled button', (
      WidgetTester tester,
    ) async {
      await onDashboard(tester);

      expect(semanticsContaining(VendorDashboardCopy.refresh), findsWidgets);
    });

    testWidgets('each quick link announces where it goes', (
      WidgetTester tester,
    ) async {
      await onDashboard(tester);

      for (final String label in <String>[
        VendorDashboardCopy.retailersLink,
        VendorDashboardCopy.usersLink,
        VendorDashboardCopy.rolesLink,
        VendorDashboardCopy.productsLink,
        VendorDashboardCopy.auditLogsLink,
      ]) {
        expect(
          semanticsContaining(VendorDashboardCopy.quickLinkSemantics(label)),
          findsOneWidget,
        );
      }
    });
  });

  group('loading, failure and retry', () {
    testWidgets('a skeleton stands in while the first read is in flight', (
      WidgetTester tester,
    ) async {
      final FakeVendorDashboardRepository repository =
          FakeVendorDashboardRepository()..manual = true;

      // The skeleton shimmers forever by design, so `pumpAndSettle` would time
      // out rather than converge — this pumps frames by hand instead.
      await pumpApp(
        tester,
        initialUser: testUser,
        portalResult: resolvedResult(PortalKind.vendorSuperAdmin),
        vendorDashboard: repository,
        settle: false,
      );
      for (int i = 0; i < 4; i++) {
        await tester.pump();
      }

      expect(find.byType(SrSkeletonScreen), findsWidgets);
      // Nothing is rendered as a figure while the answer is unknown.
      expect(find.text('7'), findsNothing);

      repository.complete();
      await tester.pumpAndSettle();
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('a failed first read offers a retry that can succeed', (
      WidgetTester tester,
    ) async {
      final FakeVendorDashboardRepository repository =
          FakeVendorDashboardRepository()
            ..result = unavailableDashboardRead<VendorDashboardSummary>();

      await onDashboard(tester, dashboard: repository);

      expect(find.byType(SrFailureView), findsOneWidget);
      expect(find.text('Could not load this'), findsOneWidget);
      // No card, and above all no zero-filled grid.
      expect(find.byType(VendorDashboardMetricCard), findsNothing);
      expect(find.text('0'), findsNothing);

      repository.result = null;
      await tapVisible(tester, find.text('Try again'));

      expect(find.byType(SrFailureView), findsNothing);
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('a denial offers no retry and names no permission', (
      WidgetTester tester,
    ) async {
      final FakeVendorDashboardRepository repository =
          FakeVendorDashboardRepository()
            ..result = deniedDashboardRead<VendorDashboardSummary>();

      await onDashboard(tester, dashboard: repository);

      expect(find.text('Not available to this account'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      // Never zero-filled cards.
      expect(find.byType(VendorDashboardMetricCard), findsNothing);

      for (final String leak in <String>[
        'ORGANIZATION_MEMBERS_READ',
        'RBAC_READ',
        'AUDIT_LOGS_READ',
        'VENDOR_SUPER_ADMIN',
        '42501',
        'organization_members',
        'audit_logs',
        'get_vendor_admin_dashboard_summary',
      ]) {
        expect(find.textContaining(leak), findsNothing);
      }
    });
  });

  group('refresh', () {
    testWidgets('the header button re-reads the summary', (
      WidgetTester tester,
    ) async {
      final FakeVendorDashboardRepository repository =
          FakeVendorDashboardRepository();

      await onDashboard(tester, dashboard: repository);
      expect(repository.callCount, 1);

      repository.nextSummary = otherVendorDashboardSummary;
      await tapVisible(tester, find.text(VendorDashboardCopy.refresh));

      expect(repository.callCount, 2);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      // Replaced whole: the previous tenant figures are gone.
      expect(find.text('7'), findsNothing);
      expect(find.text('1,204'), findsNothing);
    });

    testWidgets('a failed refresh keeps the figures and says so', (
      WidgetTester tester,
    ) async {
      final FakeVendorDashboardRepository repository =
          FakeVendorDashboardRepository();

      await onDashboard(tester, dashboard: repository);

      repository.result = unavailableDashboardRead<VendorDashboardSummary>();
      await tapVisible(tester, find.text(VendorDashboardCopy.refresh));

      expect(find.text(VendorDashboardCopy.staleTitle), findsOneWidget);
      // Non-blocking: every card is still there, with its previous figure.
      expect(find.byType(VendorDashboardMetricCard), findsNWidgets(4));
      expect(find.text('7'), findsOneWidget);
      expect(find.text('1,204'), findsOneWidget);
      expect(find.byType(SrFailureView), findsNothing);
    });

    testWidgets('a refresh after a failure clears the notice', (
      WidgetTester tester,
    ) async {
      final FakeVendorDashboardRepository repository =
          FakeVendorDashboardRepository();

      await onDashboard(tester, dashboard: repository);
      repository.result = unavailableDashboardRead<VendorDashboardSummary>();
      await tapVisible(tester, find.text(VendorDashboardCopy.refresh));
      expect(find.text(VendorDashboardCopy.staleTitle), findsOneWidget);

      repository.result = null;
      await tapVisible(tester, find.text(VendorDashboardCopy.refresh));

      expect(find.text(VendorDashboardCopy.staleTitle), findsNothing);
    });

    testWidgets('the dashboard can be pulled to refresh on a phone', (
      WidgetTester tester,
    ) async {
      final FakeVendorDashboardRepository repository =
          FakeVendorDashboardRepository();

      await onDashboard(tester, dashboard: repository);
      expect(repository.callCount, 1);

      await tester.fling(
        find.byType(RefreshIndicator),
        const Offset(0, 320),
        1000,
      );
      await tester.pumpAndSettle();

      expect(repository.callCount, 2);
    });
  });

  group('quick links', () {
    for (final ({String label, String path, Type page}) link
        in <({String label, String path, Type page})>[
          (
            label: VendorDashboardCopy.retailersLink,
            path: VendorNavigation.retailers,
            page: VendorRetailersPage,
          ),
          (
            label: VendorDashboardCopy.usersLink,
            path: VendorNavigation.users,
            page: VendorUsersPage,
          ),
          (
            label: VendorDashboardCopy.rolesLink,
            path: VendorNavigation.roles,
            page: VendorRolesPage,
          ),
          (
            label: VendorDashboardCopy.productsLink,
            path: VendorNavigation.products,
            page: VendorProductsPage,
          ),
        ]) {
      testWidgets('${link.label} opens ${link.path}', (
        WidgetTester tester,
      ) async {
        await onDashboard(tester, surface: tabletSurface);

        await tapVisible(tester, find.text(link.label).last);

        expect(currentLocation(tester), link.path);
        expect(find.byType(link.page), findsOneWidget);
      });
    }

    testWidgets('Audit Logs opens the audit feed', (WidgetTester tester) async {
      // Asserted separately: the drawer carries a destination with the same
      // label, so the tap has to be aimed at the shortcut card itself.
      await onDashboard(tester);

      await tapVisible(
        tester,
        find.descendant(
          of: find.byType(SrShortcutCard),
          matching: find.text(VendorDashboardCopy.auditLogsLink),
        ),
      );

      expect(currentLocation(tester), VendorNavigation.auditLogs);
    });

    testWidgets('exactly five links, and no unavailable destination', (
      WidgetTester tester,
    ) async {
      await onDashboard(tester);

      expect(find.byType(SrShortcutCard), findsNWidgets(5));

      for (final String unbuilt in <String>[
        'Campaigns',
        'Claims',
        'Coins',
        'Payouts',
        'Reports',
        'Settings',
      ]) {
        expect(
          find.descendant(
            of: find.byType(SrShortcutCard),
            matching: find.text(unbuilt),
          ),
          findsNothing,
          reason: '$unbuilt has no route, so no shortcut may point at it',
        );
      }
    });

    testWidgets('no quick link carries a figure', (WidgetTester tester) async {
      await onDashboard(tester);

      // The summary returns no Retailer, Product, shop, assignment or invitation
      // count, so a number on any shortcut would be one this screen invented.
      for (final Element element
          in find.byType(SrShortcutCard).evaluate().toList()) {
        final Iterable<Text> texts = find
            .descendant(
              of: find.byWidget(element.widget),
              matching: find.byType(Text),
            )
            .evaluate()
            .map((Element e) => e.widget as Text);

        for (final Text text in texts) {
          expect(
            RegExp(r'\d').hasMatch(text.data ?? ''),
            isFalse,
            reason: 'a quick link must carry no figure',
          );
        }
      }
    });
  });

  group('responsive and themed', () {
    for (final ({String name, Size size}) surface
        in <({String name, Size size})>[
          (name: 'a small phone', size: smallPhoneSurface),
          (name: 'a phone', size: phoneSurface),
          (name: 'a tablet', size: tabletSurface),
          (name: 'a desktop browser', size: desktopSurface),
        ]) {
      testWidgets(
        'the dashboard lays out on ${surface.name} without overflow',
        (WidgetTester tester) async {
          await onDashboard(tester, surface: surface.size);

          expect(tester.takeException(), isNull);
          expect(find.byType(VendorDashboardMetricCard), findsNWidgets(4));
        },
      );
    }

    testWidgets('large text scale does not overflow a small phone', (
      WidgetTester tester,
    ) async {
      useSurface(tester, smallPhoneSurface);
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await onDashboard(tester, surface: smallPhoneSurface);

      expect(tester.takeException(), isNull);
    });

    for (final ThemeMode mode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
      testWidgets('the dashboard renders in $mode', (
        WidgetTester tester,
      ) async {
        await pumpApp(
          tester,
          initialUser: testUser,
          portalResult: resolvedResult(PortalKind.vendorSuperAdmin),
          themeMode: mode,
        );
        await goTo(tester, VendorNavigation.dashboard);

        expect(find.byType(VendorDashboardMetricCard), findsNWidgets(4));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
