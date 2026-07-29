import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sale_reward/app/router/app_router.dart';
import 'package:sale_reward/app/shells/retailer_manager/retailer_manager_navigation.dart';
import 'package:sale_reward/app/shells/retailer_owner/retailer_owner_navigation.dart';
import 'package:sale_reward/app/shells/sales_staff/sales_staff_navigation.dart';
import 'package:sale_reward/app/shells/vendor/vendor_navigation.dart';
import 'package:sale_reward/core/widgets/widgets.dart';
import 'package:sale_reward/features/auth/domain/entities/auth_user.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/auth/presentation/bloc/session_bloc.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_detail.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_shop.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_summary.dart';
import 'package:sale_reward/features/retailers/domain/repositories/vendor_retailer_result.dart';
import 'package:sale_reward/features/retailers/presentation/vendor/pages/vendor_retailer_detail_page.dart';
import 'package:sale_reward/features/retailers/presentation/vendor/pages/vendor_retailers_page.dart';
import 'package:sale_reward/features/retailers/presentation/vendor/widgets/vendor_retailer_card.dart';
import 'package:sale_reward/features/retailers/presentation/vendor/widgets/vendor_retailer_copy.dart';
import 'package:sale_reward/features/retailers/presentation/vendor/widgets/vendor_retailer_shop_tile.dart';

import '../../support/fakes.dart';
import '../../support/pump_app.dart';
import '../../support/vendor_retailer_fakes.dart';

/// Drives the Vendor Retailer screens through the real application: real
/// router, real shell, real cubits, over a fake repository that never touches
/// Supabase.

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
///
/// The directory is a long scrolling page, so a card below the fold is not
/// hit-testable until it has been brought on screen — which is exactly what a
/// person does before tapping it.
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

/// A second signed-in person, so a user switch is a real change of identity
/// rather than the same session emitted twice.
const AuthUser secondUser = AuthUser(id: 'user-2', email: 'pat@example.com');

void main() {
  /// Signs in as a Vendor Super Admin and opens the Retailers directory.
  Future<PumpedApp> onDirectory(
    WidgetTester tester, {
    FakeVendorRetailerRepository? retailers,
    Size surface = phoneSurface,
  }) async {
    final PumpedApp app = await pumpAppInRole(
      tester,
      PortalKind.vendorSuperAdmin,
      surface: surface,
      retailers: retailers,
    );
    await goTo(tester, VendorNavigation.retailers);
    return app;
  }

  group('route isolation', () {
    test('the guard sends every other role away from both routes', () {
      // The pure redirect function is the whole state machine, so pinning it
      // covers the manual-URL case for every role at once.
      for (final PortalKind kind in <PortalKind>[
        PortalKind.retailerOwner,
        PortalKind.retailerManager,
        PortalKind.salesStaff,
      ]) {
        final SessionState session = SessionActive(contextFor(kind));
        final String home = sessionHome(session);

        expect(redirectFor(session, VendorNavigation.retailers), home);
        expect(
          redirectFor(
            session,
            VendorNavigation.retailerDetailPath(northwindRelationshipUuid),
          ),
          home,
        );
      }
    });

    test('a Vendor Super Admin is allowed into both', () {
      final SessionState session = SessionActive(
        contextFor(PortalKind.vendorSuperAdmin),
      );

      expect(redirectFor(session, VendorNavigation.retailers), isNull);
      expect(
        redirectFor(
          session,
          VendorNavigation.retailerDetailPath(northwindRelationshipUuid),
        ),
        isNull,
      );
    });

    test('a signed-out caller is sent to login, not to the directory', () {
      expect(
        redirectFor(const SessionUnauthenticated(), VendorNavigation.retailers),
        '/login',
      );
    });

    test('the detail route lives under the Retailers path', () {
      expect(
        VendorNavigation.retailerDetailPath(northwindRelationshipUuid),
        '/vendor/retailers/$northwindRelationshipUuid',
      );
      expect(
        VendorNavigation.retailerDetailPath(
          northwindRelationshipUuid,
        ).startsWith(VendorNavigation.retailers),
        isTrue,
      );
    });

    testWidgets('a Retailer Owner cannot reach the Vendor Retailer routes', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.retailerOwner);

      await goTo(tester, VendorNavigation.retailers);
      expect(find.byType(VendorRetailersPage), findsNothing);

      await goTo(
        tester,
        VendorNavigation.retailerDetailPath(northwindRelationshipUuid),
      );
      expect(find.byType(VendorRetailerDetailPage), findsNothing);
      expect(currentLocation(tester), RetailerOwnerNavigation.overview);
    });

    testWidgets('a Retailer Manager cannot reach them either', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.retailerManager);

      await goTo(
        tester,
        VendorNavigation.retailerDetailPath(northwindRelationshipUuid),
      );

      expect(find.byType(VendorRetailerDetailPage), findsNothing);
      expect(currentLocation(tester), RetailerManagerNavigation.staff);
    });

    testWidgets('Sales Staff cannot reach them either', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.salesStaff);

      await goTo(tester, VendorNavigation.retailers);

      expect(find.byType(VendorRetailersPage), findsNothing);
      expect(currentLocation(tester), SalesStaffNavigation.submit);
    });

    testWidgets('no other role even reads the Vendor Retailer RPCs', (
      WidgetTester tester,
    ) async {
      final FakeVendorRetailerRepository repository =
          FakeVendorRetailerRepository();

      await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
        retailers: repository,
      );
      await goTo(tester, VendorNavigation.retailers);

      // The shell that owns the cubits is never built for this role, so no
      // Retailer read is ever issued on their behalf.
      expect(repository.retailersCallCount, 0);
      expect(repository.detailCallCount, 0);
    });
  });

  group('the directory', () {
    testWidgets('a Vendor Super Admin reaches it and sees their Retailers', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onDirectory(tester);

      expect(find.byType(VendorRetailersPage), findsOneWidget);
      expect(find.text('Northwind Retail'), findsOneWidget);
      expect(find.text('Contoso Stores'), findsOneWidget);
      // One read for the whole screen; the shell loaded it once.
      expect(app.retailers.retailersCallCount, 1);
      expect(app.retailers.shopsCallCount, 0);
    });

    testWidgets('shows a loading skeleton before the first answer', (
      WidgetTester tester,
    ) async {
      final FakeVendorRetailerRepository repository =
          FakeVendorRetailerRepository()..manualRetailers = true;

      await pumpAppInRole(
        tester,
        PortalKind.vendorSuperAdmin,
        retailers: repository,
      );
      GoRouter.of(
        tester.element(find.byType(Navigator).first),
      ).go(VendorNavigation.retailers);
      // Two frames: one for the router to swap the route, one for the page to
      // build. Deliberately not pumpAndSettle — the skeleton shimmers forever
      // by design, so settling would time out.
      await tester.pump();
      await tester.pump();

      expect(find.byType(SrLoadingView), findsOneWidget);
      expect(find.byType(VendorRetailerCard), findsNothing);

      repository.completeRetailers();
      await tester.pumpAndSettle();

      expect(find.byType(SrLoadingView), findsNothing);
      expect(find.byType(VendorRetailerCard), findsNWidgets(2));
    });

    testWidgets('every row is visibly actionable', (WidgetTester tester) async {
      await onDirectory(tester);

      // Three affordances, so the row reads as openable whether a user scans
      // shapes, reads words, or uses assistive technology.
      expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(2));
      expect(find.text(VendorRetailerCopy.openDetails), findsNWidgets(2));
      for (final VendorRetailerCard card
          in tester.widgetList<VendorRetailerCard>(
            find.byType(VendorRetailerCard),
          )) {
        expect(card.onOpen, isNotNull);
      }
    });

    testWidgets('the card carries a spoken summary and an open hint', (
      WidgetTester tester,
    ) async {
      await onDirectory(tester);

      expect(semanticsContaining('Northwind Retail'), findsWidgets);
      expect(semanticsContaining('Relationship Active'), findsWidgets);
      expect(semanticsContaining('4 shops · 3 active'), findsWidgets);

      final Semantics semantics = tester.widget<Semantics>(
        semanticsContaining('Northwind Retail').first,
      );
      expect(semantics.properties.button, isTrue);
      expect(semantics.properties.hint, VendorRetailerCopy.openDetails);
      // The relationship id is an address, not display data.
      expect(
        semantics.properties.label,
        isNot(contains(northwindRelationshipUuid)),
      );
    });

    testWidgets('both statuses and the owner state are shown per row', (
      WidgetTester tester,
    ) async {
      await onDirectory(tester);

      expect(find.text('Relationship: Active'), findsOneWidget);
      // Stored SUSPENDED, shown "Inactive" — the word has to match the verb of
      // the Vendor control that writes it (Deactivate / Reactivate).
      expect(find.text('Relationship: Inactive'), findsOneWidget);
      expect(find.text('Relationship: Suspended'), findsNothing);
      expect(find.text('Retailer: Active'), findsNWidgets(2));
      expect(find.text('Owner active'), findsOneWidget);
      expect(find.text('No owner'), findsOneWidget);
    });

    testWidgets('shop counts and the onboarding date are shown', (
      WidgetTester tester,
    ) async {
      await onDirectory(tester);

      expect(find.text('4 shops · 3 active'), findsOneWidget);
      expect(find.text('0 shops · 0 active'), findsOneWidget);
      expect(find.text('Onboarded 12 Mar 2026'), findsOneWidget);
    });

    testWidgets('the totals come from the trusted counts', (
      WidgetTester tester,
    ) async {
      await onDirectory(tester);

      expect(find.text('Connected Retailers'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3 active'), findsOneWidget);
    });

    testWidgets('an empty directory says so, and does not read as a failure', (
      WidgetTester tester,
    ) async {
      final FakeVendorRetailerRepository repository =
          FakeVendorRetailerRepository()
            ..retailersResult =
                const VendorRetailerReadSuccess<List<VendorRetailerSummary>>(
                  <VendorRetailerSummary>[],
                );

      await onDirectory(tester, retailers: repository);

      expect(find.text(VendorRetailerCopy.emptyTitle), findsOneWidget);
      expect(find.byType(VendorRetailerCard), findsNothing);
      // No retry, because nothing failed.
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('a failed first read offers a retry that works', (
      WidgetTester tester,
    ) async {
      final FakeVendorRetailerRepository repository =
          FakeVendorRetailerRepository()
            ..retailersResult =
                unavailableRetailerRead<List<VendorRetailerSummary>>();

      await onDirectory(tester, retailers: repository);

      expect(find.byType(SrFailureView), findsOneWidget);
      expect(find.text('Could not load this'), findsOneWidget);

      repository.retailersResult =
          VendorRetailerReadSuccess<List<VendorRetailerSummary>>(
            <VendorRetailerSummary>[northwindSummary],
          );
      await tapVisible(tester, find.text('Try again'));

      expect(find.byType(VendorRetailerCard), findsOneWidget);
    });

    testWidgets('a denial never offers a retry', (WidgetTester tester) async {
      final FakeVendorRetailerRepository repository =
          FakeVendorRetailerRepository()
            ..retailersResult =
                deniedRetailerRead<List<VendorRetailerSummary>>();

      await onDirectory(tester, retailers: repository);

      expect(find.text('Not available to this account'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('refreshing re-reads without blanking the rows', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onDirectory(tester);

      await tester.tap(find.text(VendorRetailerCopy.refresh));
      await tester.pump();

      // Rows stay while the refresh runs.
      expect(find.byType(VendorRetailerCard), findsNWidgets(2));

      await tester.pumpAndSettle();
      expect(app.retailers.retailersCallCount, 2);
    });

    testWidgets('a failed refresh keeps the rows and warns', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onDirectory(tester);
      app.retailers.retailersResult =
          unavailableRetailerRead<List<VendorRetailerSummary>>();

      await tapVisible(tester, find.text(VendorRetailerCopy.refresh));

      expect(find.byType(VendorRetailerCard), findsNWidgets(2));
      expect(find.text(VendorRetailerCopy.staleListTitle), findsOneWidget);
    });

    testWidgets('a local search narrows the loaded rows only', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onDirectory(tester);

      await tester.enterText(find.byType(TextField).first, 'contoso');
      await tester.pumpAndSettle();

      expect(find.text('Contoso Stores'), findsOneWidget);
      expect(find.text('Northwind Retail'), findsNothing);
      expect(find.text('Showing 1 of 2'), findsOneWidget);
      // Nothing was sent anywhere.
      expect(app.retailers.retailersCallCount, 1);
    });

    testWidgets('a search matching nothing offers a way back', (
      WidgetTester tester,
    ) async {
      await onDirectory(tester);

      await tester.enterText(find.byType(TextField).first, 'zzzz');
      await tester.pumpAndSettle();

      expect(find.text(VendorRetailerCopy.noMatchesTitle), findsOneWidget);

      await tapVisible(
        tester,
        find.text(VendorRetailerCopy.clearFilters).first,
      );

      expect(find.byType(VendorRetailerCard), findsNWidgets(2));
    });

    testWidgets('status chips offer only the statuses actually present', (
      WidgetTester tester,
    ) async {
      await onDirectory(tester, surface: tabletSurface);

      expect(find.widgetWithText(SrButton, 'All'), findsOneWidget);
      expect(find.widgetWithText(SrButton, 'Active'), findsOneWidget);
      expect(find.widgetWithText(SrButton, 'Inactive'), findsOneWidget);
      expect(find.widgetWithText(SrButton, 'Suspended'), findsNothing);
      // Nothing in the fixture is deactivated, so no chip offers it — and
      // "Deactivated" stays its own distinct word, not collapsed into
      // "Inactive".
      expect(find.widgetWithText(SrButton, 'Deactivated'), findsNothing);

      await tapVisible(tester, find.widgetWithText(SrButton, 'Inactive'));

      expect(find.text('Contoso Stores'), findsOneWidget);
      expect(find.text('Northwind Retail'), findsNothing);
    });
  });

  group('opening a Retailer', () {
    testWidgets('tapping a row opens its own relationship', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onDirectory(tester);

      await tapVisible(tester, find.text('Northwind Retail'));

      expect(find.byType(VendorRetailerDetailPage), findsOneWidget);
      expect(app.retailers.requestedDetailIds, <String>[
        northwindRelationshipUuid,
      ]);
      expect(app.retailers.requestedShopIds, <String>[
        northwindRelationshipUuid,
      ]);
    });

    testWidgets('the detail renders every field the contract returns', (
      WidgetTester tester,
    ) async {
      await onDirectory(tester);
      await tapVisible(tester, find.text('Northwind Retail'));

      expect(find.text('Northwind Retail'), findsOneWidget);
      expect(find.text('Relationship: Active'), findsOneWidget);
      expect(find.text('Retailer: Active'), findsOneWidget);
      // Twice: once as the header badge, once as a labelled fact in Overview.
      expect(find.text('Owner active'), findsNWidgets(2));
      // The Retailer's country, and again on the one shop that records it.
      expect(find.text('AE'), findsNWidgets(2));
      expect(find.text('AED'), findsOneWidget);
      expect(find.text('4 shops · 3 active'), findsWidgets);
      expect(find.text('12 Mar 2026'), findsOneWidget);
    });

    testWidgets('the raw relationship id is not put on screen', (
      WidgetTester tester,
    ) async {
      await onDirectory(tester);
      await tapVisible(tester, find.text('Northwind Retail'));

      expect(find.textContaining(northwindRelationshipUuid), findsNothing);
      expect(find.textContaining(northwindOrganizationUuid), findsNothing);
    });

    testWidgets('the shops are listed, active and inactive alike', (
      WidgetTester tester,
    ) async {
      await onDirectory(tester);
      await tapVisible(tester, find.text('Northwind Retail'));

      expect(find.byType(VendorRetailerShopTile), findsNWidgets(2));
      expect(find.text('Marina Mall'), findsOneWidget);
      expect(find.text('Airport Kiosk'), findsOneWidget);
      // Status is stated in words, never by colour alone. A SUSPENDED shop
      // reads "Inactive" for the same reason a SUSPENDED relationship does.
      expect(find.text('Active'), findsWidgets);
      expect(find.text('Inactive'), findsWidgets);
      expect(find.text('Suspended'), findsNothing);
      expect(find.text('MM-01'), findsOneWidget);
      expect(find.text('Dubai'), findsOneWidget);
      // The nullable columns of the second shop are said out loud.
      expect(find.text('Not recorded'), findsNWidgets(3));
    });

    testWidgets('a Retailer with no shops says so', (
      WidgetTester tester,
    ) async {
      final FakeVendorRetailerRepository repository =
          FakeVendorRetailerRepository()
            ..detailResult = VendorRetailerReadSuccess<VendorRetailerDetail?>(
              contosoDetail,
            )
            ..shopsResult =
                const VendorRetailerReadSuccess<List<VendorRetailerShop>>(
                  <VendorRetailerShop>[],
                );

      await onDirectory(tester, retailers: repository);
      await tapVisible(tester, find.text('Contoso Stores'));

      expect(find.text(VendorRetailerCopy.shopsEmptyTitle), findsOneWidget);
      expect(find.byType(VendorRetailerShopTile), findsNothing);
      // A Retailer with no country or currency still renders.
      expect(find.text('Not recorded'), findsNWidgets(2));
    });

    testWidgets('a shop failure degrades only that section, and retries', (
      WidgetTester tester,
    ) async {
      final FakeVendorRetailerRepository repository =
          FakeVendorRetailerRepository()
            ..shopsResult = unavailableRetailerRead<List<VendorRetailerShop>>();

      await onDirectory(tester, retailers: repository);
      await tapVisible(tester, find.text('Northwind Retail'));

      // The Retailer's own facts are untouched.
      expect(find.text('Northwind Retail'), findsOneWidget);
      expect(find.text('AED'), findsOneWidget);
      expect(
        find.text(VendorRetailerCopy.shopsUnavailableTitle),
        findsOneWidget,
      );

      repository.shopsResult =
          const VendorRetailerReadSuccess<List<VendorRetailerShop>>(
            <VendorRetailerShop>[marinaShop],
          );
      await tapVisible(tester, find.text(VendorRetailerCopy.retryShops));

      expect(find.byType(VendorRetailerShopTile), findsOneWidget);
      // The detail was never re-read.
      expect(repository.detailCallCount, 1);
    });

    testWidgets('a detail outage offers a retry that works', (
      WidgetTester tester,
    ) async {
      final FakeVendorRetailerRepository repository =
          FakeVendorRetailerRepository()
            ..detailResult = unavailableRetailerRead<VendorRetailerDetail?>();

      await onDirectory(tester, retailers: repository);
      await tapVisible(tester, find.text('Northwind Retail'));

      expect(find.byType(SrFailureView), findsOneWidget);

      repository.detailResult =
          VendorRetailerReadSuccess<VendorRetailerDetail?>(northwindDetail);
      await tapVisible(tester, find.text('Try again'));

      expect(find.text('Northwind Retail'), findsOneWidget);
      expect(find.byType(VendorRetailerShopTile), findsNWidgets(2));
    });

    testWidgets('going back keeps the directory already loaded', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onDirectory(tester);

      await tapVisible(tester, find.text('Northwind Retail'));
      await tapVisible(tester, find.text(VendorRetailerCopy.backToList));

      expect(find.byType(VendorRetailersPage), findsOneWidget);
      expect(find.byType(VendorRetailerCard), findsNWidgets(2));
      // No skeleton, and no second directory read.
      expect(app.retailers.retailersCallCount, 1);
    });
  });

  group('a relationship this caller may not read', () {
    testWidgets('a manually typed foreign id shows one safe state', (
      WidgetTester tester,
    ) async {
      final FakeVendorRetailerRepository repository =
          FakeVendorRetailerRepository()
            ..detailResult =
                const VendorRetailerReadSuccess<VendorRetailerDetail?>(null);

      await onDirectory(tester, retailers: repository);
      await goTo(
        tester,
        VendorNavigation.retailerDetailPath(foreignRelationshipUuid),
      );

      expect(find.text(VendorRetailerCopy.detailNotFoundTitle), findsOneWidget);
      // Says nothing about existence or ownership.
      expect(find.textContaining('another Vendor'), findsNothing);
      expect(find.textContaining('exists'), findsNothing);
      // Not an outage: no retry.
      expect(find.text('Try again'), findsNothing);
      // And no shop read was chased.
      expect(repository.shopsCallCount, 0);
    });

    testWidgets('a malformed id in the URL reaches the same state', (
      WidgetTester tester,
    ) async {
      // The real repository refuses the id shape before any request leaves the
      // client (`vendor_retailer_repository_test.dart` pins that); what matters
      // here is that the screen it produces is the *same* one a well-formed
      // foreign id produces, so the two are not distinguishable by looking.
      final FakeVendorRetailerRepository repository =
          FakeVendorRetailerRepository();

      await onDirectory(tester, retailers: repository);
      await goTo(tester, '${VendorNavigation.retailers}/not-a-uuid');

      expect(find.text(VendorRetailerCopy.detailNotFoundTitle), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(repository.shopsCallCount, 0);
    });

    testWidgets('the safe state offers a way back to the directory', (
      WidgetTester tester,
    ) async {
      final FakeVendorRetailerRepository repository =
          FakeVendorRetailerRepository()
            ..detailResult =
                const VendorRetailerReadSuccess<VendorRetailerDetail?>(null);

      await onDirectory(tester, retailers: repository);
      await goTo(
        tester,
        VendorNavigation.retailerDetailPath(foreignRelationshipUuid),
      );

      await tapVisible(tester, find.text(VendorRetailerCopy.backToList).last);

      expect(find.byType(VendorRetailersPage), findsOneWidget);
    });
  });

  group('session isolation', () {
    testWidgets('signing out clears the directory', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onDirectory(tester);
      expect(find.text('Northwind Retail'), findsOneWidget);

      app.auth.emitSignedOut();
      await tester.pumpAndSettle();

      expect(find.byType(VendorRetailersPage), findsNothing);
      expect(find.text('Northwind Retail'), findsNothing);
      expect(find.text('Contoso Stores'), findsNothing);
    });

    testWidgets('an open Retailer is cleared on sign-out too', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onDirectory(tester);
      await tapVisible(tester, find.text('Northwind Retail'));
      expect(find.text('AED'), findsOneWidget);

      app.auth.emitSignedOut();
      await tester.pumpAndSettle();

      expect(find.byType(VendorRetailerDetailPage), findsNothing);
      expect(find.text('AED'), findsNothing);
      expect(find.text('Northwind Retail'), findsNothing);
    });

    testWidgets('a new Vendor never sees the previous one\'s Retailers', (
      WidgetTester tester,
    ) async {
      final FakeVendorRetailerRepository repository =
          FakeVendorRetailerRepository();
      final PumpedApp app = await onDirectory(tester, retailers: repository);
      expect(find.text('Northwind Retail'), findsOneWidget);

      // The next person's directory, under the same role.
      repository.retailersResult =
          VendorRetailerReadSuccess<List<VendorRetailerSummary>>(
            <VendorRetailerSummary>[contosoSummary],
          );
      app.auth.emitSignedIn(secondUser);
      await tester.pumpAndSettle();

      expect(find.text('Northwind Retail'), findsNothing);
      expect(find.text('Contoso Stores'), findsOneWidget);
      expect(repository.retailersCallCount, 2);
    });

    testWidgets('a search term does not survive a session change', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onDirectory(tester);
      await tester.enterText(find.byType(TextField).first, 'northwind');
      await tester.pumpAndSettle();
      expect(find.text('Showing 1 of 2'), findsOneWidget);

      app.auth.emitSignedIn(secondUser);
      await tester.pumpAndSettle();

      // A search term is a fragment of a Retailer name.
      expect(find.text('Showing 1 of 2'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty,
      );
    });
  });

  group('responsive and themed', () {
    for (final (String name, Size surface) in <(String, Size)>[
      ('a small phone', smallPhoneSurface),
      ('a phone', phoneSurface),
      ('a tablet', tabletSurface),
      ('a desktop browser', desktopSurface),
    ]) {
      testWidgets('the directory lays out on $name without overflowing', (
        WidgetTester tester,
      ) async {
        await onDirectory(tester, surface: surface);

        expect(find.byType(VendorRetailerCard), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      });

      testWidgets('a Retailer detail lays out on $name without overflowing', (
        WidgetTester tester,
      ) async {
        await onDirectory(tester, surface: surface);
        await tapVisible(tester, find.text('Northwind Retail'));

        expect(find.byType(VendorRetailerShopTile), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('wide screens use more than one column', (
      WidgetTester tester,
    ) async {
      await onDirectory(tester, surface: desktopSurface);

      final List<Offset> positions = tester
          .widgetList<VendorRetailerCard>(find.byType(VendorRetailerCard))
          .map(
            (VendorRetailerCard card) => tester.getTopLeft(find.byWidget(card)),
          )
          .toList();

      // Two cards on the same row rather than stacked.
      expect(positions[0].dy, positions[1].dy);
      expect(positions[0].dx, lessThan(positions[1].dx));
    });

    testWidgets('a phone stacks the cards', (WidgetTester tester) async {
      await onDirectory(tester, surface: phoneSurface);

      final List<Offset> positions = tester
          .widgetList<VendorRetailerCard>(find.byType(VendorRetailerCard))
          .map(
            (VendorRetailerCard card) => tester.getTopLeft(find.byWidget(card)),
          )
          .toList();

      expect(positions[0].dx, positions[1].dx);
      expect(positions[0].dy, lessThan(positions[1].dy));
    });

    for (final ThemeMode mode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
      testWidgets('the directory renders in $mode', (
        WidgetTester tester,
      ) async {
        await pumpApp(
          tester,
          initialUser: testUser,
          portalResult: resolvedResult(PortalKind.vendorSuperAdmin),
          themeMode: mode,
        );
        await goTo(tester, VendorNavigation.retailers);

        expect(find.byType(VendorRetailerCard), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      });

      testWidgets('a Retailer detail renders in $mode', (
        WidgetTester tester,
      ) async {
        await pumpApp(
          tester,
          initialUser: testUser,
          portalResult: resolvedResult(PortalKind.vendorSuperAdmin),
          themeMode: mode,
        );
        await goTo(tester, VendorNavigation.retailers);
        await tapVisible(tester, find.text('Northwind Retail'));

        expect(find.byType(VendorRetailerShopTile), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
