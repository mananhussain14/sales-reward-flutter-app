import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sale_reward/app/shells/retailer_manager/retailer_manager_navigation.dart';
import 'package:sale_reward/app/shells/retailer_owner/retailer_owner_navigation.dart';
import 'package:sale_reward/app/shells/sales_staff/sales_staff_navigation.dart';
import 'package:sale_reward/app/shells/vendor/vendor_navigation.dart';
import 'package:sale_reward/core/widgets/widgets.dart';
import 'package:sale_reward/features/auth/domain/entities/auth_user.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/dashboard/domain/repositories/retailer_owner_overview_repository.dart';
import 'package:sale_reward/features/dashboard/presentation/retailer_owner/pages/retailer_owner_overview_page.dart';
import 'package:sale_reward/features/dashboard/presentation/retailer_owner/widgets/retailer_owner_overview_copy.dart';
import 'package:sale_reward/features/dashboard/presentation/retailer_owner/widgets/retailer_shop_count_card.dart';
import 'package:sale_reward/features/home/presentation/sales_staff/pages/sales_staff_home_page.dart';
import 'package:sale_reward/features/staff/presentation/retailer/pages/retailer_staff_page.dart';

import '../../support/fakes.dart';
import '../../support/pump_app.dart';
import '../../support/retailer_owner_overview_fakes.dart';

/// Drives the Retailer Owner Overview through the real application: real
/// router, real shell, real cubit, over a fake repository that never touches
/// Supabase.
void main() {
  /// Fully unmounts the application between two pumps in one test.
  ///
  /// [SaleRewardApp] carries no key, so a second `pumpWidget` of the same type
  /// reuses the existing `State` — and with it the *first* pump's repositories,
  /// silently making the second half of a loop assert against the first half's
  /// fakes. Pumping an empty tree first forces `initState` to run again.
  Future<void> unmountApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  /// Navigates the live router, as a deep link or a typed URL would.
  Future<void> goTo(WidgetTester tester, String location) async {
    GoRouter.of(tester.element(find.byType(Navigator).first)).go(location);
    await tester.pumpAndSettle();
  }

  /// Where the router actually ended up.
  String currentLocation(WidgetTester tester) => GoRouter.of(
    tester.element(find.byType(Navigator).first),
  ).routeInformationProvider.value.uri.path;

  /// The shop-count card carrying [label].
  Finder shopCard(String label) => find.byWidgetPredicate(
    (Widget widget) => widget is RetailerShopCountCard && widget.label == label,
    description: 'RetailerShopCountCard labelled "$label"',
  );

  /// Any [Semantics] whose label contains [fragment].
  Finder semanticsContaining(String fragment) => find.byWidgetPredicate(
    (Widget widget) =>
        widget is Semantics &&
        (widget.properties.label?.contains(fragment) ?? false),
    description: 'Semantics whose label contains "$fragment"',
  );

  Future<PumpedApp> onOverview(
    WidgetTester tester, {
    FakeRetailerOwnerOverviewRepository? overview,
    Size surface = phoneSurface,
  }) => pumpAppInRole(
    tester,
    PortalKind.retailerOwner,
    surface: surface,
    retailerOverview: overview,
  );

  // -------------------------------------------------------------------------
  group('routing', () {
    testWidgets('a Retailer Owner lands on the Overview', (
      WidgetTester tester,
    ) async {
      await onOverview(tester);

      expect(currentLocation(tester), RetailerOwnerNavigation.overview);
      expect(find.byType(RetailerOwnerOverviewPage), findsOneWidget);
    });

    testWidgets('a Retailer Manager lands on Staff, never the Owner Overview', (
      WidgetTester tester,
    ) async {
      // The Owner Overview RPC hard-filters RETAILER_OWNER, so sending a
      // Manager there would bounce them straight off it.
      await pumpAppInRole(tester, PortalKind.retailerManager);

      expect(currentLocation(tester), RetailerManagerNavigation.staff);
      expect(find.byType(RetailerStaffPage), findsOneWidget);
      expect(find.byType(RetailerOwnerOverviewPage), findsNothing);
    });

    testWidgets('a Manager typing the Owner Overview URL is sent back', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await pumpAppInRole(
        tester,
        PortalKind.retailerManager,
      );

      await goTo(tester, RetailerOwnerNavigation.overview);

      expect(currentLocation(tester), RetailerManagerNavigation.staff);
      expect(find.byType(RetailerOwnerOverviewPage), findsNothing);
      // And the Owner's read was never issued on their behalf.
      expect(app.retailerOverview.callCount, 0);
    });

    testWidgets('the Sales Staff route is preserved', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await pumpAppInRole(tester, PortalKind.salesStaff);

      expect(currentLocation(tester), SalesStaffNavigation.home);
      expect(find.byType(SalesStaffHomePage), findsOneWidget);
      expect(app.retailerOverview.callCount, 0);
    });

    testWidgets('the Vendor route is preserved', (WidgetTester tester) async {
      final PumpedApp app = await pumpAppInRole(
        tester,
        PortalKind.vendorSuperAdmin,
        surface: desktopSurface,
      );

      expect(currentLocation(tester), VendorNavigation.dashboard);
      // The Retailer read is never issued in a Vendor session.
      expect(app.retailerOverview.callCount, 0);
    });

    testWidgets('a Sales Staff user cannot reach the Owner Overview', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await pumpAppInRole(tester, PortalKind.salesStaff);

      await goTo(tester, RetailerOwnerNavigation.overview);

      expect(currentLocation(tester), SalesStaffNavigation.home);
      expect(app.retailerOverview.callCount, 0);
    });

    testWidgets('NONE enters access-denied and issues no read', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await pumpApp(
        tester,
        initialUser: testUser,
        portalResult: deniedResult,
      );

      expect(currentLocation(tester), '/access-denied');
      expect(app.retailerOverview.callCount, 0);
    });

    testWidgets('a denied user typing the Overview URL does not loop', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester, initialUser: testUser, portalResult: deniedResult);

      await goTo(tester, RetailerOwnerNavigation.overview);

      // Settles rather than redirecting forever.
      expect(currentLocation(tester), '/access-denied');
      expect(tester.takeException(), isNull);
    });
  });

  // -------------------------------------------------------------------------
  group('the loaded overview', () {
    testWidgets('renders all seven canonical values', (
      WidgetTester tester,
    ) async {
      await onOverview(tester);

      expect(find.text('Northwind Retail'), findsWidgets);
      expect(find.text('AE'), findsOneWidget);
      expect(find.text('AED'), findsOneWidget);
      // Both statuses, rendered as labels rather than backend tokens.
      expect(find.text('Active'), findsNWidgets(2));
      expect(find.text('ACTIVE'), findsNothing);

      expect(
        shopCard(RetailerOwnerOverviewCopy.totalShopsLabel),
        findsOneWidget,
      );
      expect(
        shopCard(RetailerOwnerOverviewCopy.activeShopsLabel),
        findsOneWidget,
      );
      expect(find.text('12'), findsOneWidget);
      expect(find.text('9'), findsOneWidget);
    });

    testWidgets('reads the RPC exactly once on entry', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onOverview(tester);
      expect(app.retailerOverview.callCount, 1);
    });

    testWidgets('a Retailer with no shops shows two honest zeros', (
      WidgetTester tester,
    ) async {
      final FakeRetailerOwnerOverviewRepository repo =
          FakeRetailerOwnerOverviewRepository()
            ..nextOverview = newRetailerOverview;
      await onOverview(tester, overview: repo);

      expect(find.text('Fresh Start Trading'), findsWidgets);
      expect(find.text('0'), findsNWidgets(2));
      // A real answer, not an error and not an empty state.
      expect(find.byType(SrEmptyState), findsNothing);
    });

    testWidgets('an unrecorded country and currency say so', (
      WidgetTester tester,
    ) async {
      final FakeRetailerOwnerOverviewRepository repo =
          FakeRetailerOwnerOverviewRepository()
            ..nextOverview = unrecordedCodesOverview;
      await onOverview(tester, overview: repo);

      expect(
        find.text(RetailerOwnerOverviewCopy.notRecorded),
        findsNWidgets(2),
      );
    });

    testWidgets('a suspended organization is flagged above the values', (
      WidgetTester tester,
    ) async {
      final FakeRetailerOwnerOverviewRepository repo =
          FakeRetailerOwnerOverviewRepository()
            ..nextOverview = suspendedRetailerOverview;
      await onOverview(tester, overview: repo);

      expect(
        find.text(RetailerOwnerOverviewCopy.inactiveTitle),
        findsOneWidget,
      );
      expect(find.text('Suspended'), findsOneWidget);
      // The row is still shown: the user is entitled to see it.
      expect(find.text('Paused Traders'), findsWidgets);
    });

    testWidgets('a suspended membership is flagged too', (
      WidgetTester tester,
    ) async {
      final FakeRetailerOwnerOverviewRepository repo =
          FakeRetailerOwnerOverviewRepository()
            ..nextOverview = suspendedMembershipOverview;
      await onOverview(tester, overview: repo);

      expect(
        find.text(RetailerOwnerOverviewCopy.inactiveTitle),
        findsOneWidget,
      );
    });

    testWidgets('an active account carries no warning', (
      WidgetTester tester,
    ) async {
      await onOverview(tester);
      expect(find.text(RetailerOwnerOverviewCopy.inactiveTitle), findsNothing);
    });

    testWidgets('no raw UUID is anywhere on the screen', (
      WidgetTester tester,
    ) async {
      await onOverview(tester);

      final Iterable<String> texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((Text t) => t.data ?? '')
          .toList();

      final RegExp uuid = RegExp(
        r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
        r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
      );
      for (final String text in texts) {
        expect(uuid.hasMatch(text), isFalse, reason: 'rendered a UUID: $text');
      }
    });
  });

  // -------------------------------------------------------------------------
  group('loading', () {
    testWidgets('shows a skeleton before the first answer, never a blank', (
      WidgetTester tester,
    ) async {
      final FakeRetailerOwnerOverviewRepository repo =
          FakeRetailerOwnerOverviewRepository()..manual = true;

      await pumpApp(
        tester,
        initialUser: testUser,
        portalResult: resolvedResult(PortalKind.retailerOwner),
        retailerOverview: repo,
        settle: false,
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(SrSkeleton), findsWidgets);
      expect(find.byType(RetailerShopCountCard), findsNothing);

      repo.complete();
      await tester.pumpAndSettle();
      expect(find.byType(RetailerShopCountCard), findsNWidgets(2));
    });
  });

  // -------------------------------------------------------------------------
  group('refresh', () {
    testWidgets('the header button re-reads and updates the figures', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onOverview(tester);
      expect(find.text('12'), findsOneWidget);

      app.retailerOverview.nextOverview = otherRetailerOverview;
      await tester.tap(find.text(RetailerOwnerOverviewCopy.refresh));
      await tester.pumpAndSettle();

      expect(app.retailerOverview.callCount, 2);
      expect(find.text('Southgate Stores'), findsWidgets);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('12'), findsNothing);
    });

    testWidgets('a failed refresh keeps the figures and says they are stale', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onOverview(tester);

      app.retailerOverview.result = const RetailerOverviewFailed(
        RetailerOverviewProblem.network,
      );
      await tester.tap(find.text(RetailerOwnerOverviewCopy.refresh));
      await tester.pumpAndSettle();

      expect(find.text(RetailerOwnerOverviewCopy.staleTitle), findsOneWidget);
      // The figures stay: they are still the last thing the backend said.
      expect(find.text('12'), findsOneWidget);
      expect(find.text('9'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('ineligible and failure states', () {
    testWidgets('zero rows shows the no-workspace state with no retry', (
      WidgetTester tester,
    ) async {
      final FakeRetailerOwnerOverviewRepository repo =
          FakeRetailerOwnerOverviewRepository()
            ..result = const RetailerOverviewIneligible();
      await onOverview(tester, overview: repo);

      expect(
        find.text(RetailerOwnerOverviewCopy.ineligibleTitle),
        findsOneWidget,
      );
      // No retry: a second identical call returns the same nothing.
      expect(find.text('Try again'), findsNothing);
      // And absolutely no cards.
      expect(find.byType(RetailerShopCountCard), findsNothing);
    });

    testWidgets('a denial offers no retry and names no permission', (
      WidgetTester tester,
    ) async {
      final FakeRetailerOwnerOverviewRepository repo =
          FakeRetailerOwnerOverviewRepository()
            ..result = const RetailerOverviewFailed(
              RetailerOverviewProblem.denied,
            );
      await onOverview(tester, overview: repo);

      expect(
        find.text(
          RetailerOwnerOverviewCopy.problemCopy(
            RetailerOverviewProblem.denied,
          ).title,
        ),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsNothing);
      expect(find.textContaining('RETAILER_PORTAL_READ'), findsNothing);
      expect(find.textContaining('42501'), findsNothing);
      expect(find.byType(RetailerShopCountCard), findsNothing);
    });

    testWidgets('a network failure offers a retry that re-reads', (
      WidgetTester tester,
    ) async {
      final FakeRetailerOwnerOverviewRepository repo =
          FakeRetailerOwnerOverviewRepository()
            ..result = const RetailerOverviewFailed(
              RetailerOverviewProblem.network,
            );
      await onOverview(tester, overview: repo);

      expect(find.text('Could not reach SalesReward'), findsOneWidget);
      expect(repo.callCount, 1);

      repo.result = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(repo.callCount, 2);
      expect(find.byType(RetailerShopCountCard), findsNWidgets(2));
    });

    testWidgets('a malformed response is not shown as a connection problem', (
      WidgetTester tester,
    ) async {
      final FakeRetailerOwnerOverviewRepository repo =
          FakeRetailerOwnerOverviewRepository()
            ..result = const RetailerOverviewFailed(
              RetailerOverviewProblem.malformed,
            );
      await onOverview(tester, overview: repo);

      expect(find.text('Could not read your overview'), findsOneWidget);
      expect(find.textContaining('Check your connection'), findsNothing);
      // And never an empty overview.
      expect(find.byType(RetailerShopCountCard), findsNothing);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('a timeout is distinguished from an unexpected failure', (
      WidgetTester tester,
    ) async {
      for (final (RetailerOverviewProblem problem, String title)
          in <(RetailerOverviewProblem, String)>[
            (RetailerOverviewProblem.timeout, 'This took too long'),
            (RetailerOverviewProblem.unexpected, 'Something went wrong'),
          ]) {
        await unmountApp(tester);
        final FakeRetailerOwnerOverviewRepository repo =
            FakeRetailerOwnerOverviewRepository()
              ..result = RetailerOverviewFailed(problem);
        await onOverview(tester, overview: repo);

        expect(find.text(title), findsOneWidget, reason: problem.name);
      }
    });

    testWidgets('no failure state leaks a backend detail', (
      WidgetTester tester,
    ) async {
      for (final RetailerOverviewProblem problem
          in RetailerOverviewProblem.values) {
        await unmountApp(tester);
        final FakeRetailerOwnerOverviewRepository repo =
            FakeRetailerOwnerOverviewRepository()
              ..result = RetailerOverviewFailed(problem);
        await onOverview(tester, overview: repo);

        final String screen = tester
            .widgetList<Text>(find.byType(Text))
            .map((Text t) => t.data ?? '')
            .join(' ');

        for (final String forbidden in <String>[
          '42501',
          'PostgrestException',
          'SQLSTATE',
          'public.',
          'auth.uid',
          'retailer_shops',
          'organization_members',
          'get_retailer_owner_portal_context',
        ]) {
          expect(
            screen.contains(forbidden),
            isFalse,
            reason: '${problem.name} leaked "$forbidden"',
          );
        }
      }
    });
  });

  // -------------------------------------------------------------------------
  group('session isolation', () {
    const AuthUser secondUser = AuthUser(id: 'user-2', email: 'b@example.com');

    testWidgets('Retailer Owner A to Retailer Owner B replaces the overview', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onOverview(tester);
      expect(find.text('Northwind Retail'), findsWidgets);

      app.retailerOverview.nextOverview = otherRetailerOverview;
      app.portal.result = otherRetailerOwnerResult();
      app.auth.emitSignedIn(secondUser);
      await tester.pumpAndSettle();

      // A's organization is gone, not merely overlaid.
      expect(find.text('Northwind Retail'), findsNothing);
      expect(find.text('12'), findsNothing);
      expect(find.text('Southgate Stores'), findsWidgets);
      expect(app.retailerOverview.callCount, 2);
    });

    testWidgets('an Owner who becomes ineligible loses the previous values', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onOverview(tester);
      expect(find.text('Northwind Retail'), findsWidgets);

      app.retailerOverview.result = const RetailerOverviewIneligible();
      app.portal.result = otherRetailerOwnerResult();
      app.auth.emitSignedIn(secondUser);
      await tester.pumpAndSettle();

      expect(find.text('Northwind Retail'), findsNothing);
      expect(
        find.text(RetailerOwnerOverviewCopy.ineligibleTitle),
        findsOneWidget,
      );
    });

    testWidgets('signing out clears the overview', (WidgetTester tester) async {
      final PumpedApp app = await onOverview(tester);
      expect(find.text('Northwind Retail'), findsWidgets);

      app.auth.emitSignedOut();
      await tester.pumpAndSettle();

      expect(currentLocation(tester), '/login');
      expect(find.text('Northwind Retail'), findsNothing);
      expect(find.byType(RetailerShopCountCard), findsNothing);
    });

    testWidgets('Retailer Owner to Sales Staff leaves nothing behind', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onOverview(tester);
      expect(find.text('Northwind Retail'), findsWidgets);

      app.portal.result = resolvedResult(PortalKind.salesStaff);
      app.auth.emitSignedIn(secondUser);
      await tester.pumpAndSettle();

      expect(currentLocation(tester), SalesStaffNavigation.home);
      expect(find.byType(RetailerShopCountCard), findsNothing);
      expect(find.text('12'), findsNothing);
    });

    testWidgets('Vendor to Retailer Owner does not carry Vendor state over', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await pumpAppInRole(
        tester,
        PortalKind.vendorSuperAdmin,
        surface: desktopSurface,
      );
      expect(app.retailerOverview.callCount, 0);

      app.portal.result = resolvedResult(PortalKind.retailerOwner);
      app.auth.emitSignedIn(secondUser);
      await tester.pumpAndSettle();

      expect(currentLocation(tester), RetailerOwnerNavigation.overview);
      expect(find.byType(RetailerOwnerOverviewPage), findsOneWidget);
      expect(app.retailerOverview.callCount, 1);
      // No Vendor figure survived into the Retailer session.
      expect(find.text('1204'), findsNothing);
      expect(find.text('1,204'), findsNothing);
    });

    testWidgets('a stale answer cannot land after a role switch', (
      WidgetTester tester,
    ) async {
      // The race the request token exists to close: Owner A's read is still in
      // flight when the session becomes Sales Staff.
      final FakeRetailerOwnerOverviewRepository repo =
          FakeRetailerOwnerOverviewRepository()..manual = true;

      final PumpedApp app = await pumpApp(
        tester,
        initialUser: testUser,
        portalResult: resolvedResult(PortalKind.retailerOwner),
        retailerOverview: repo,
        settle: false,
      );
      await tester.pump();
      await tester.pump();
      expect(repo.pendingCount, 1);

      app.portal.result = resolvedResult(PortalKind.salesStaff);
      app.auth.emitSignedIn(secondUser);
      await tester.pumpAndSettle();

      // A's answer arrives now, into somebody else's session.
      repo.complete();
      await tester.pumpAndSettle();

      expect(currentLocation(tester), SalesStaffNavigation.home);
      expect(find.text('Northwind Retail'), findsNothing);
      expect(find.byType(RetailerShopCountCard), findsNothing);
    });

    testWidgets('an identical re-emitted session does not re-read', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onOverview(tester);
      expect(app.retailerOverview.callCount, 1);

      // The shape a same-user token refresh takes. Nothing changed, so nothing
      // is cleared and nothing is re-fetched.
      app.auth.emitTokenRefreshed(testUser);
      await tester.pumpAndSettle();

      expect(app.retailerOverview.callCount, 1);
      expect(find.text('Northwind Retail'), findsWidgets);
    });
  });

  // -------------------------------------------------------------------------
  group('capability-aware navigation', () {
    testWidgets('all four destinations show when every hint is on', (
      WidgetTester tester,
    ) async {
      await onOverview(tester);

      for (final String label in <String>[
        'Overview',
        'Shops',
        'Staff',
        'Products',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
    });

    testWidgets('a false hint hides its destination', (
      WidgetTester tester,
    ) async {
      await pumpApp(
        tester,
        initialUser: testUser,
        portalResult: ownerWithoutShopsResult(),
      );

      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Shops'),
        ),
        findsNothing,
      );
    });

    testWidgets('a false Overview hint never blocks the Overview read', (
      WidgetTester tester,
    ) async {
      // Capability hints are presentation only. The screen's own RPC is the
      // authority, and it is still called.
      final FakeRetailerOwnerOverviewRepository repo =
          FakeRetailerOwnerOverviewRepository();

      await pumpApp(
        tester,
        initialUser: testUser,
        portalResult: ownerWithoutOverviewHintResult(),
        retailerOverview: repo,
      );

      expect(repo.callCount, 1);
    });

    testWidgets('upcoming destinations are labelled as app-only gaps', (
      WidgetTester tester,
    ) async {
      await onOverview(tester);
      await tester.dragUntilVisible(
        find.text(RetailerOwnerOverviewCopy.upcomingTitle),
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(RetailerOwnerOverviewCopy.upcomingTitle),
        findsOneWidget,
      );
      // Never "unavailable on SalesReward" — these all work on the web portal.
      expect(
        find.text(RetailerOwnerOverviewCopy.upcomingDescription),
        findsOneWidget,
      );
    });
  });

  // -------------------------------------------------------------------------
  group('responsive and accessible', () {
    for (final (String name, Size surface) in <(String, Size)>[
      ('a small Android phone', smallPhoneSurface),
      ('a phone', phoneSurface),
      ('a tablet', tabletSurface),
      ('a desktop browser', desktopSurface),
    ]) {
      testWidgets('$name lays out without overflowing', (
        WidgetTester tester,
      ) async {
        await onOverview(tester, surface: surface);

        expect(find.byType(RetailerOwnerOverviewPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a phone uses the bottom bar and a desktop the rail', (
      WidgetTester tester,
    ) async {
      await onOverview(tester);
      expect(find.byType(NavigationBar), findsOneWidget);

      await unmountApp(tester);
      await onOverview(tester, surface: desktopSurface);
      expect(find.byType(NavigationRail), findsOneWidget);
    });

    testWidgets('each shop count is one readable sentence', (
      WidgetTester tester,
    ) async {
      await onOverview(tester);

      expect(
        semanticsContaining('${RetailerOwnerOverviewCopy.totalShopsLabel}: 12'),
        findsOneWidget,
      );
      expect(
        semanticsContaining('${RetailerOwnerOverviewCopy.activeShopsLabel}: 9'),
        findsOneWidget,
      );
    });

    testWidgets('each status is announced by its label, not a colour', (
      WidgetTester tester,
    ) async {
      await onOverview(tester);

      expect(
        semanticsContaining(
          '${RetailerOwnerOverviewCopy.retailerStatusLabel}: Active',
        ),
        findsOneWidget,
      );
      expect(
        semanticsContaining(
          '${RetailerOwnerOverviewCopy.membershipStatusLabel}: Active',
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders in both themes', (WidgetTester tester) async {
      for (final ThemeMode mode in <ThemeMode>[
        ThemeMode.light,
        ThemeMode.dark,
      ]) {
        await unmountApp(tester);
        await pumpApp(
          tester,
          initialUser: testUser,
          portalResult: resolvedResult(PortalKind.retailerOwner),
          themeMode: mode,
        );
        expect(find.byType(RetailerOwnerOverviewPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });
}
