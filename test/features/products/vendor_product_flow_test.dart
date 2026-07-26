import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sale_reward/app/navigation/role_destination.dart';
import 'package:sale_reward/app/router/app_router.dart';
import 'package:sale_reward/app/shells/retailer_manager/retailer_manager_navigation.dart';
import 'package:sale_reward/app/shells/retailer_owner/retailer_owner_navigation.dart';
import 'package:sale_reward/app/shells/sales_staff/sales_staff_navigation.dart';
import 'package:sale_reward/app/shells/vendor/vendor_navigation.dart';
import 'package:sale_reward/core/result/read_result.dart';
import 'package:sale_reward/core/widgets/widgets.dart';
import 'package:sale_reward/features/auth/domain/entities/auth_user.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/auth/presentation/bloc/session_bloc.dart';
import 'package:sale_reward/features/products/data/datasources/vendor_product_rpc_data_source.dart';
import 'package:sale_reward/features/products/data/repositories/supabase_vendor_product_repository.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_assigned_retailer.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_assignment_status.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_detail.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_status.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_summary.dart';
import 'package:sale_reward/features/products/presentation/vendor/pages/vendor_product_detail_page.dart';
import 'package:sale_reward/features/products/presentation/vendor/pages/vendor_products_page.dart';
import 'package:sale_reward/features/products/presentation/vendor/widgets/vendor_product_assignment_tile.dart';
import 'package:sale_reward/features/products/presentation/vendor/widgets/vendor_product_card.dart';
import 'package:sale_reward/features/products/presentation/vendor/widgets/vendor_product_copy.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_status.dart';
import 'package:sale_reward/features/retailers/presentation/vendor/pages/vendor_retailer_detail_page.dart';

import '../../support/fakes.dart';
import '../../support/pump_app.dart';
import '../../support/vendor_product_fakes.dart';

/// Drives the Vendor Product screens through the real application: real router,
/// real shell, real cubits, over a fake repository that never touches Supabase.

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

/// A second signed-in person, so a user switch is a real change of identity.
const AuthUser secondUser = AuthUser(id: 'user-2', email: 'pat@example.com');

void main() {
  /// Signs in as a Vendor Super Admin and opens the Products catalogue.
  Future<PumpedApp> onCatalogue(
    WidgetTester tester, {
    FakeVendorProductRepository? products,
    Size surface = phoneSurface,
  }) async {
    final PumpedApp app = await pumpAppInRole(
      tester,
      PortalKind.vendorSuperAdmin,
      surface: surface,
      vendorProducts: products,
    );
    await goTo(tester, VendorNavigation.products);
    return app;
  }

  /// Opens the fully populated product, which carries all three assignment
  /// cases.
  Future<PumpedApp> onEspresso(
    WidgetTester tester, {
    FakeVendorProductRepository? products,
    Size surface = phoneSurface,
  }) async {
    final PumpedApp app = await onCatalogue(
      tester,
      products: products,
      surface: surface,
    );
    await tapVisible(tester, find.text('Espresso Blend 1kg'));
    return app;
  }

  group('route isolation', () {
    test('the guard sends every other role away from both routes', () {
      for (final PortalKind kind in <PortalKind>[
        PortalKind.retailerOwner,
        PortalKind.retailerManager,
        PortalKind.salesStaff,
      ]) {
        final SessionState session = SessionActive(contextFor(kind));
        final String home = sessionHome(session);

        expect(redirectFor(session, VendorNavigation.products), home);
        expect(
          redirectFor(
            session,
            VendorNavigation.productDetailPath(espressoProductUuid),
          ),
          home,
        );
      }
    });

    test('a Vendor Super Admin is allowed into both', () {
      final SessionState session = SessionActive(
        contextFor(PortalKind.vendorSuperAdmin),
      );

      expect(redirectFor(session, VendorNavigation.products), isNull);
      expect(
        redirectFor(
          session,
          VendorNavigation.productDetailPath(espressoProductUuid),
        ),
        isNull,
      );
    });

    test('a signed-out caller is sent to login, not to the catalogue', () {
      expect(
        redirectFor(const SessionUnauthenticated(), VendorNavigation.products),
        '/login',
      );
    });

    test('the detail route is the product id under the Products path', () {
      expect(
        VendorNavigation.productDetailPath(espressoProductUuid),
        '/vendor/products/$espressoProductUuid',
      );
      expect(
        VendorNavigation.productDetailPath(
          espressoProductUuid,
        ).startsWith(VendorNavigation.products),
        isTrue,
      );
    });

    test('the route selector is never a product code, name or barcode', () {
      // The code is unique per Vendor, not globally, so it could not name one
      // row without a tenant beside it — the very input this contract refuses.
      final String path = VendorNavigation.productDetailPath(
        espressoProductUuid,
      );

      expect(path.contains('ESP-1000'), isFalse);
      expect(path.contains('Espresso'), isFalse);
      expect(path.contains('5012345678900'), isFalse);
      expect(path.endsWith(espressoProductUuid), isTrue);
    });

    test('Products stays the selected destination for list and detail', () {
      // Longest-prefix wins, so an open product does not fall back to Dashboard.
      final RoleNavigation model = VendorNavigation.model;
      final int productsIndex = model.destinations.indexWhere(
        (RoleDestination d) => d.path == VendorNavigation.products,
      );

      expect(model.indexForLocation(VendorNavigation.products), productsIndex);
      expect(
        model.indexForLocation(
          VendorNavigation.productDetailPath(espressoProductUuid),
        ),
        productsIndex,
      );
    });

    testWidgets('a Retailer Owner cannot reach the Vendor Product routes', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.retailerOwner);

      await goTo(tester, VendorNavigation.products);
      expect(find.byType(VendorProductsPage), findsNothing);

      await goTo(
        tester,
        VendorNavigation.productDetailPath(espressoProductUuid),
      );
      expect(find.byType(VendorProductDetailPage), findsNothing);
      expect(currentLocation(tester), RetailerOwnerNavigation.overview);
    });

    testWidgets('a Retailer Manager cannot reach them either', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.retailerManager);

      await goTo(
        tester,
        VendorNavigation.productDetailPath(espressoProductUuid),
      );

      expect(find.byType(VendorProductDetailPage), findsNothing);
      expect(currentLocation(tester), RetailerManagerNavigation.staff);
    });

    testWidgets('Sales Staff cannot reach them either', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.salesStaff);

      await goTo(tester, VendorNavigation.products);

      expect(find.byType(VendorProductsPage), findsNothing);
      expect(currentLocation(tester), SalesStaffNavigation.submit);
    });

    testWidgets('no other role even reads the Vendor Product RPCs', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository();

      await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
        vendorProducts: repository,
      );
      await goTo(tester, VendorNavigation.products);

      // The shell that owns the cubits is never built for this role.
      expect(repository.productsCallCount, 0);
      expect(repository.detailCallCount, 0);
      expect(repository.assignmentsCallCount, 0);
    });

    testWidgets('a product status never authorizes a route', (
      WidgetTester tester,
    ) async {
      // Reaching this screen is decided by the session's portal kind and, on
      // every call, by SQL — never by a status, a count or a name the backend
      // sent for display.
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository();

      await pumpAppInRole(
        tester,
        PortalKind.salesStaff,
        vendorProducts: repository,
      );
      await goTo(
        tester,
        VendorNavigation.productDetailPath(espressoProductUuid),
      );

      expect(find.text('Espresso Blend 1kg'), findsNothing);
      expect(repository.detailCallCount, 0);
    });
  });

  group('the catalogue', () {
    testWidgets('a Vendor Super Admin reaches it and sees every product', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onCatalogue(tester);

      expect(find.byType(VendorProductsPage), findsOneWidget);
      expect(find.byType(VendorProductCard), findsNWidgets(4));
      expect(find.text('Espresso Blend 1kg'), findsOneWidget);
      expect(find.text('Seasonal Roast 250g'), findsOneWidget);
      // One read for the whole screen, and no detail or assignment read.
      expect(app.vendorProducts.productsCallCount, 1);
      expect(app.vendorProducts.detailCallCount, 0);
      expect(app.vendorProducts.assignmentsCallCount, 0);
    });

    testWidgets('nothing is read until the catalogue is actually opened', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository();
      final PumpedApp app = await pumpAppInRole(
        tester,
        PortalKind.vendorSuperAdmin,
        vendorProducts: repository,
      );

      expect(repository.productsCallCount, 0);

      await goTo(tester, VendorNavigation.users);
      expect(repository.productsCallCount, 0);
      expect(app.vendorUsers.usersCallCount, 1);

      await goTo(tester, VendorNavigation.products);
      expect(repository.productsCallCount, 1);
    });

    testWidgets('shows a loading skeleton before the first answer', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository()..manualProducts = true;

      await pumpAppInRole(
        tester,
        PortalKind.vendorSuperAdmin,
        vendorProducts: repository,
      );
      GoRouter.of(
        tester.element(find.byType(Navigator).first),
      ).go(VendorNavigation.products);
      // Two frames: one for the router to swap the route, one for the page to
      // build. Deliberately not pumpAndSettle — the skeleton shimmers forever.
      await tester.pump();
      await tester.pump();

      expect(find.byType(SrLoadingView), findsOneWidget);
      expect(find.byType(VendorProductCard), findsNothing);

      repository.completeProducts();
      await tester.pumpAndSettle();

      expect(find.byType(SrLoadingView), findsNothing);
      expect(find.byType(VendorProductCard), findsNWidgets(4));
    });

    testWidgets('every card is visibly actionable', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);

      expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(4));
      expect(find.text(VendorProductCopy.openDetails), findsNWidgets(4));
      for (final VendorProductCard card in tester.widgetList<VendorProductCard>(
        find.byType(VendorProductCard),
      )) {
        expect(card.onOpen, isNotNull);
      }
    });

    testWidgets('a card shows code, barcode, brand, status and the count', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);

      expect(find.text('ESP-1000'), findsOneWidget);
      expect(find.text('5012345678900'), findsOneWidget);
      expect(find.text('Harvest Roasters'), findsWidgets);
      expect(find.text('Status: Active'), findsNWidgets(3));
      expect(find.text('Status: Inactive'), findsOneWidget);
      expect(find.text('2 Retailers currently hold this'), findsOneWidget);
      expect(find.text('Updated 2 Jun 2026'), findsOneWidget);
    });

    testWidgets('a null barcode and brand are omitted from the card', (
      WidgetTester tester,
    ) async {
      // The decaf product has neither. A "Not recorded" row on a card would
      // spend a line saying nothing; the detail screen states it explicitly.
      await onCatalogue(tester);

      final Finder decafCard = find.ancestor(
        of: find.text('Decaf Ground 500g'),
        matching: find.byType(VendorProductCard),
      );

      expect(
        find.descendant(
          of: decafCard,
          matching: find.text(VendorProductCopy.barcodeLabel),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: decafCard,
          matching: find.text(VendorProductCopy.brandLabel),
        ),
        findsNothing,
      );
      // The code is NOT NULL and is always shown.
      expect(
        find.descendant(of: decafCard, matching: find.text('DEC-2000')),
        findsOneWidget,
      );
    });

    testWidgets('the zero-assignment case is worded as a fact', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);

      expect(find.text('No Retailer currently holds this'), findsNWidgets(2));
    });

    testWidgets('the card count is never worded as a total', (
      WidgetTester tester,
    ) async {
      // The list read returns only the ACTIVE count, so a card may never imply
      // a total or a "n of m".
      await onCatalogue(tester);

      for (final String forbidden in <String>[
        'Retailer assignments',
        'of 3',
        'currently active',
        'total',
      ]) {
        expect(
          find.descendant(
            of: find.byType(VendorProductCard),
            matching: find.textContaining(forbidden),
          ),
          findsNothing,
          reason: 'a card implies "$forbidden"',
        );
      }
    });

    testWidgets('no image, thumbnail or category is rendered', (
      WidgetTester tester,
    ) async {
      // No product image exists anywhere in the product, and no category column
      // exists. A placeholder frame would advertise an image system.
      await onCatalogue(tester);

      expect(find.byType(Image), findsNothing);
      expect(find.byType(FadeInImage), findsNothing);
      expect(find.byIcon(Icons.image_outlined), findsNothing);
      expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
      for (final String forbidden in <String>[
        'Category',
        'Image',
        'Photo',
        'Price',
        'Reward',
        'Stock',
      ]) {
        expect(
          find.textContaining(forbidden),
          findsNothing,
          reason: 'the catalogue renders "$forbidden"',
        );
      }
    });

    testWidgets('the card carries a spoken summary and an open hint', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);

      expect(semanticsContaining('Espresso Blend 1kg'), findsWidgets);
      expect(semanticsContaining('Product status: Active'), findsWidgets);
      expect(semanticsContaining('Product code: ESP-1000'), findsWidgets);
      expect(
        semanticsContaining('2 Retailers currently hold this'),
        findsWidgets,
      );
      // An absent field is spoken as the neutral phrase rather than skipped.
      expect(
        semanticsContaining(
          '${VendorProductCopy.barcodeLabel}: ${VendorProductCopy.notRecorded}',
        ),
        findsWidgets,
      );
      // No uuid is ever spoken.
      final Semantics semantics = tester.widget<Semantics>(
        semanticsContaining('Espresso Blend 1kg').first,
      );
      expect(semantics.properties.label, isNot(contains(espressoProductUuid)));
    });

    testWidgets('the summary figures come from the returned rows', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);

      expect(find.text(VendorProductCopy.totalLabel), findsOneWidget);
      expect(find.text(VendorProductCopy.activeLabel), findsOneWidget);
      expect(find.text(VendorProductCopy.inactiveLabel), findsOneWidget);
      expect(
        find.text(VendorProductCopy.activeAssignmentsLabel),
        findsOneWidget,
      );
      expect(find.text('4'), findsOneWidget); // total products
      expect(find.text('1'), findsOneWidget); // inactive
    });

    testWidgets('an all-active catalogue shows no inactive card', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository()
            ..productsResult = ReadSuccess<List<VendorProductSummary>>(
              <VendorProductSummary>[espressoSummary, decafSummary],
            );

      await onCatalogue(tester, products: repository);

      expect(find.text(VendorProductCopy.inactiveLabel), findsNothing);
    });

    testWidgets('a Vendor with no products sees the empty state', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository()
            ..productsResult = const ReadSuccess<List<VendorProductSummary>>(
              <VendorProductSummary>[],
            );

      await onCatalogue(tester, products: repository);

      expect(find.text(VendorProductCopy.emptyTitle), findsOneWidget);
      expect(find.byType(VendorProductCard), findsNothing);
      expect(find.text('Try again'), findsNothing);
      // And it does not suggest adding one: this screen cannot.
      expect(find.textContaining('Add a product'), findsNothing);
      expect(find.textContaining('Create'), findsNothing);
    });

    testWidgets('a failed first read offers a retry that works', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository()
            ..productsResult =
                unavailableProductRead<List<VendorProductSummary>>();

      await onCatalogue(tester, products: repository);

      expect(find.byType(SrFailureView), findsOneWidget);
      expect(find.text('Could not load this'), findsOneWidget);

      repository.productsResult = ReadSuccess<List<VendorProductSummary>>(
        productCatalogueSummaries,
      );
      await tapVisible(tester, find.text('Try again'));

      expect(find.byType(VendorProductCard), findsNWidgets(4));
    });

    testWidgets('a denial never offers a retry and names no permission', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository()
            ..productsResult = deniedProductRead<List<VendorProductSummary>>();

      await onCatalogue(tester, products: repository);

      expect(find.text('Not available to this account'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      for (final String leak in <String>[
        'PRODUCTS_READ',
        'RETAILERS_READ',
        '42501',
        'vendor_products',
        'list_vendor_products',
        'permission',
      ]) {
        expect(
          find.textContaining(leak),
          findsNothing,
          reason: 'the denial leaks "$leak"',
        );
      }
    });

    testWidgets('refreshing re-reads without blanking the rows', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onCatalogue(tester);

      await tester.tap(find.text(VendorProductCopy.refresh));
      await tester.pump();

      expect(find.byType(VendorProductCard), findsNWidgets(4));

      await tester.pumpAndSettle();
      expect(app.vendorProducts.productsCallCount, 2);
    });

    testWidgets('a failed refresh keeps the rows and warns', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onCatalogue(tester);
      app.vendorProducts.productsResult =
          unavailableProductRead<List<VendorProductSummary>>();

      await tapVisible(tester, find.text(VendorProductCopy.refresh));

      expect(find.byType(VendorProductCard), findsNWidgets(4));
      expect(find.text(VendorProductCopy.staleListTitle), findsOneWidget);
    });

    testWidgets('the only write affordance is Add product', (
      WidgetTester tester,
    ) async {
      // The catalogue can create. It cannot edit, change a status, delete, assign
      // or withdraw — those either belong to one product's own screen or do not
      // exist at all — and an affordance, even a disabled one, would promise a
      // capability that is not there.
      await onCatalogue(tester);

      expect(
        find.widgetWithText(SrButton, VendorProductCopy.addProduct),
        findsOneWidget,
      );

      // Scoped to *controls*. The section prose legitimately uses words like
      // "withdrawn" to describe what an inactive assignment is, and a Retailer
      // status pill legitimately reads "Deactivated" — describing a state is not
      // offering an action. What must not exist is something a reader can press.
      for (final String forbidden in <String>[
        'Edit',
        'Delete',
        'Remove',
        'Activate',
        'Deactivate',
        'Assign',
        'Withdraw',
        'Upload',
        'Import',
      ]) {
        expect(
          find.widgetWithText(SrButton, forbidden),
          findsNothing,
          reason: 'the catalogue offers a "$forbidden" control',
        );
      }
      // And no press target beyond the cards, the refresh, the filters and Add.
      for (final SrButton button in tester.widgetList<SrButton>(
        find.byType(SrButton),
      )) {
        expect(
          <String>[
            VendorProductCopy.refresh,
            VendorProductCopy.refreshing,
            VendorProductCopy.clearFilters,
            VendorProductCopy.filterAll,
            VendorProductCopy.addProduct,
            'Active',
            'Inactive',
          ].contains(button.label),
          isTrue,
          reason: 'an unexpected control "${button.label}" is on the catalogue',
        );
      }
    });
  });

  group('search and filtering', () {
    testWidgets('a local search by name narrows the loaded rows only', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onCatalogue(tester);

      await tester.enterText(find.byType(TextField).first, 'espresso');
      await tester.pumpAndSettle();

      expect(find.text('Espresso Blend 1kg'), findsOneWidget);
      expect(find.text('Decaf Ground 500g'), findsNothing);
      expect(find.text('Showing 1 of 4'), findsOneWidget);
      // Nothing was sent anywhere.
      expect(app.vendorProducts.productsCallCount, 1);
    });

    testWidgets('a search by product code works', (WidgetTester tester) async {
      await onCatalogue(tester);

      await tester.enterText(find.byType(TextField).first, 'RET-3000');
      await tester.pumpAndSettle();

      expect(find.text('Seasonal Roast 250g'), findsOneWidget);
      expect(find.text('Showing 1 of 4'), findsOneWidget);
    });

    testWidgets('a search by barcode works', (WidgetTester tester) async {
      await onCatalogue(tester);

      await tester.enterText(find.byType(TextField).first, '5012345678900');
      await tester.pumpAndSettle();

      expect(find.text('Espresso Blend 1kg'), findsOneWidget);
      expect(find.text('Showing 1 of 4'), findsOneWidget);
    });

    testWidgets('a search by brand works and is case-insensitive', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);

      await tester.enterText(find.byType(TextField).first, 'harvest');
      await tester.pumpAndSettle();

      expect(find.text('Showing 3 of 4'), findsOneWidget);
      expect(find.text('Decaf Ground 500g'), findsNothing);
    });

    testWidgets('a search matching nothing offers a way back', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);

      await tester.enterText(find.byType(TextField).first, 'zzzz');
      await tester.pumpAndSettle();

      expect(find.text(VendorProductCopy.noMatchesTitle), findsOneWidget);

      await tapVisible(tester, find.text(VendorProductCopy.clearFilters).first);

      expect(find.byType(VendorProductCard), findsNWidgets(4));
    });

    testWidgets('the status filter row is offered and works', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester, surface: tabletSurface);

      expect(find.text(VendorProductCopy.statusFilterLabel), findsOneWidget);
      expect(find.widgetWithText(SrButton, 'All'), findsOneWidget);
      expect(find.widgetWithText(SrButton, 'Active'), findsOneWidget);
      expect(find.widgetWithText(SrButton, 'Inactive'), findsOneWidget);
      // Nothing has an unrecognised status in the fixture, so no chip offers it.
      expect(find.widgetWithText(SrButton, 'Unknown'), findsNothing);

      await tapVisible(tester, find.widgetWithText(SrButton, 'Inactive'));

      expect(find.text('Seasonal Roast 250g'), findsOneWidget);
      expect(find.text('Espresso Blend 1kg'), findsNothing);
    });

    testWidgets('search and filter combine', (WidgetTester tester) async {
      await onCatalogue(tester, surface: tabletSurface);

      await tester.enterText(find.byType(TextField).first, 'harvest');
      await tester.pumpAndSettle();
      await tapVisible(tester, find.widgetWithText(SrButton, 'Inactive'));

      expect(find.text('Showing 1 of 4'), findsOneWidget);
      expect(find.text('Seasonal Roast 250g'), findsOneWidget);
    });

    testWidgets('clearing restores the backend order exactly', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester, surface: tabletSurface);
      await tester.enterText(find.byType(TextField).first, 'harvest');
      await tester.pumpAndSettle();

      await tapVisible(tester, find.text(VendorProductCopy.clearFilters).first);

      final List<String> rendered = tester
          .widgetList<VendorProductCard>(find.byType(VendorProductCard))
          .map((VendorProductCard c) => c.product.productCode)
          .toList();

      expect(rendered, <String>[
        'ESP-1000',
        'DEC-2000',
        'NEW-4000',
        'RET-3000',
      ]);
    });

    testWidgets('the search hint says nothing is sent to the server', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);

      expect(find.text(VendorProductCopy.searchHint), findsOneWidget);
    });

    testWidgets('filter chips carry their subject in the semantics', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester, surface: tabletSurface);

      expect(semanticsContaining('Product status: Active'), findsWidgets);
      expect(
        semanticsContaining('${VendorProductCopy.statusFilterLabel}: All'),
        findsWidgets,
      );
    });
  });

  group('opening a product', () {
    testWidgets('tapping a card opens it, in the right order', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onEspresso(tester);

      expect(find.byType(VendorProductDetailPage), findsOneWidget);
      expect(app.vendorProducts.requestedDetailIds, <String>[
        espressoProductUuid,
      ]);
      expect(app.vendorProducts.requestedAssignmentIds, <String>[
        espressoProductUuid,
      ]);
      expect(app.vendorProducts.callLog, <String>[
        'products',
        'detail',
        'assignments',
      ]);
      expect(
        currentLocation(tester),
        VendorNavigation.productDetailPath(espressoProductUuid),
      );
    });

    testWidgets('the detail renders every field the contract returns', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      expect(find.text('Espresso Blend 1kg'), findsOneWidget);
      expect(find.text('Status: Active'), findsOneWidget);
      expect(find.text('ESP-1000'), findsOneWidget);
      expect(find.text('5012345678900'), findsOneWidget);
      expect(find.text('Harvest Roasters'), findsOneWidget);
      expect(
        find.text('A dark roast blend for espresso machines.'),
        findsOneWidget,
      );
      expect(find.text('18 Apr 2026'), findsOneWidget); // created
      expect(find.text('2 Jun 2026'), findsOneWidget); // updated
    });

    testWidgets('both assignment figures are stated, and distinguished', (
      WidgetTester tester,
    ) async {
      // `assignment_count` includes withdrawn rows, so it is never worded as
      // "Retailers currently assigned".
      await onEspresso(tester);

      expect(
        find.text('3 Retailer assignments · 2 currently active'),
        findsNWidgets(2),
      );
      for (final String forbidden in <String>[
        'Retailers currently assigned',
        '3 Retailers currently',
        '3 currently active',
      ]) {
        expect(
          find.textContaining(forbidden),
          findsNothing,
          reason: 'the detail says "$forbidden"',
        );
      }
    });

    testWidgets('a null barcode, brand and description say so explicitly', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);
      await tapVisible(tester, find.text('Decaf Ground 500g'));

      // Three "Not recorded" values — never a blank and never invented from the
      // product name.
      expect(find.text(VendorProductCopy.notRecorded), findsNWidgets(3));
      expect(find.text('DEC-2000'), findsOneWidget);
    });

    testWidgets('no identifier is put on screen', (WidgetTester tester) async {
      await onEspresso(tester);

      expect(find.textContaining(espressoProductUuid), findsNothing);
      expect(find.textContaining(northwindRelationshipId), findsNothing);
      expect(find.textContaining(northwindOrgId), findsNothing);
      expect(find.textContaining('Product ID'), findsNothing);
      expect(find.textContaining('Organization ID'), findsNothing);
    });

    testWidgets('the detail facts are spoken as label-and-value pairs', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      expect(
        semanticsContaining('${VendorProductCopy.codeLabel}: ESP-1000'),
        findsWidgets,
      );
      expect(
        semanticsContaining('${VendorProductCopy.statusLabel}: Active'),
        findsWidgets,
      );
      expect(
        semanticsContaining(
          '${VendorProductCopy.assignmentsLabel}: 3 Retailer assignments',
        ),
        findsWidgets,
      );
    });

    testWidgets('going back keeps the catalogue already loaded', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onEspresso(tester);

      await tapVisible(tester, find.text(VendorProductCopy.backToList));

      expect(find.byType(VendorProductsPage), findsOneWidget);
      expect(find.byType(VendorProductCard), findsNWidgets(4));
      // No skeleton, and no second catalogue read.
      expect(app.vendorProducts.productsCallCount, 1);
    });

    testWidgets('a browser-style back pop also returns to the loaded list', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onEspresso(tester);

      // What the hardware/browser back button drives.
      final NavigatorState navigator = tester.state<NavigatorState>(
        find.byType(Navigator).last,
      );
      navigator.pop();
      await tester.pumpAndSettle();

      expect(find.byType(VendorProductsPage), findsOneWidget);
      expect(find.byType(VendorProductCard), findsNWidgets(4));
      expect(app.vendorProducts.productsCallCount, 1);
      expect(currentLocation(tester), VendorNavigation.products);
    });

    testWidgets('a search survives a round trip into a product', (
      WidgetTester tester,
    ) async {
      // The list cubit belongs to the shell, so the narrowing is still applied
      // when the back gesture returns.
      await onCatalogue(tester);
      await tester.enterText(find.byType(TextField).first, 'espresso');
      await tester.pumpAndSettle();

      await tapVisible(tester, find.text('Espresso Blend 1kg'));
      await tapVisible(tester, find.text(VendorProductCopy.backToList));

      expect(find.text('Showing 1 of 4'), findsOneWidget);
    });

    testWidgets('the detail offers Edit and one status action, and no more', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      expect(
        find.widgetWithText(SrButton, VendorProductCopy.edit),
        findsOneWidget,
      );
      // An ACTIVE product offers Deactivate, and never both directions at once.
      expect(
        find.widgetWithText(SrButton, VendorProductCopy.deactivate),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(SrButton, VendorProductCopy.activate),
        findsNothing,
      );

      // Scoped to *controls*, for the same reason as the catalogue: "Retailer:
      // Deactivated" is a status this screen must state, and the assignment
      // section's description must be free to say that withdrawn assignments are
      // included.
      //
      // There is no deletion anywhere in this product — no control, no action, no
      // RPC and no `DELETE` in the schema — and no bulk assignment, because no
      // bulk function exists. The assignment controls that DO exist are named
      // below; "Unassign" is not among them, because the vocabulary is
      // *withdraw*.
      for (final String forbidden in <String>[
        'Delete',
        'Delete product',
        'Remove',
        'Archive',
        'Unassign',
        'Assign all Retailers',
        'Remove assignment',
        'Delete assignment',
        'Upload image',
        'Set price',
        'Add product',
      ]) {
        expect(
          find.widgetWithText(SrButton, forbidden),
          findsNothing,
          reason: 'the detail offers a "$forbidden" control',
        );
      }
      // Navigation, Edit, the one status action, and the assignment controls.
      // Nothing else.
      for (final SrButton button in tester.widgetList<SrButton>(
        find.byType(SrButton),
      )) {
        expect(
          <String>[
            VendorProductCopy.backToList,
            VendorProductCopy.viewRetailer,
            VendorProductCopy.edit,
            VendorProductCopy.deactivate,
            VendorProductCopy.assignRetailer,
            VendorProductCopy.withdrawAssignment,
            VendorProductCopy.reactivateAssignment,
          ].contains(button.label),
          isTrue,
          reason: 'an unexpected control "${button.label}" is on the detail',
        );
      }
    });
  });

  group('an inactive product', () {
    testWidgets('shows its status and keeps its assignments visible', (
      WidgetTester tester,
    ) async {
      // set_vendor_product_status does not cascade, so nothing may imply the
      // assignments are disabled.
      await onCatalogue(tester);
      await tapVisible(tester, find.text('Seasonal Roast 250g'));

      expect(find.text('Status: Inactive'), findsOneWidget);
      expect(find.text('Inactive'), findsOneWidget); // the labelled fact
      expect(find.byType(VendorProductAssignmentTile), findsOneWidget);
      expect(find.text('Northwind Retail'), findsOneWidget);
      expect(
        find.text('1 Retailer assignment · 1 currently active'),
        findsNWidgets(2),
      );
    });

    testWidgets('never implies its assignments are suspended', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);
      await tapVisible(tester, find.text('Seasonal Roast 250g'));

      for (final String forbidden in <String>[
        'assignments are disabled',
        'no longer available to',
        'Assignments paused',
        'not currently assignable',
      ]) {
        expect(find.textContaining(forbidden), findsNothing);
      }
      // The assignment's own status is what it is.
      expect(find.text('Active assignment'), findsOneWidget);
    });
  });

  group('the assigned-Retailers section', () {
    testWidgets('renders one row per assignment, in backend order', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      expect(find.byType(VendorProductAssignmentTile), findsNWidgets(3));
      final List<String> rendered = tester
          .widgetList<VendorProductAssignmentTile>(
            find.byType(VendorProductAssignmentTile),
          )
          .map((VendorProductAssignmentTile t) => t.assignment.retailerName)
          .toList();

      expect(rendered, <String>[
        'Harbour Provisions',
        'Northwind Retail',
        'Old Town Grocers',
      ]);
    });

    testWidgets('the rendered rows equal assignment_count', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      expect(
        tester.widgetList<VendorProductAssignmentTile>(
          find.byType(VendorProductAssignmentTile),
        ),
        hasLength(espressoDetail.assignmentCount),
      );
    });

    testWidgets('an inactive assignment is labelled as inactive', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      expect(find.text('Inactive assignment'), findsOneWidget);
      expect(find.text('Active assignment'), findsNWidgets(2));
      // Never called "not assigned" — the row exists because it once was.
      expect(find.textContaining('Not assigned'), findsNothing);
      expect(find.textContaining('currently assigned'), findsNothing);
    });

    testWidgets('all three statuses are shown with their own subjects', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      // The suspended Retailer with a suspended relationship and an ACTIVE
      // assignment — three independent facts, none inferred from another.
      expect(find.text('Retailer: Suspended'), findsOneWidget);
      expect(find.text('Relationship: Suspended'), findsOneWidget);
      expect(find.text('Retailer: Active'), findsOneWidget);
      expect(find.text('Relationship: Active'), findsOneWidget);
      expect(find.text('Retailer: Deactivated'), findsOneWidget);
    });

    testWidgets('both assignment dates are shown, correctly labelled', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      expect(
        find.textContaining('${VendorProductCopy.assignedOnLabel} 19 Apr 2026'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          '${VendorProductCopy.assignmentUpdatedLabel} 30 May 2026',
        ),
        findsOneWidget,
      );
      // Never presented as a withdrawal date — no such column exists.
      expect(find.textContaining('Withdrawn on'), findsNothing);
      expect(find.textContaining('withdrawn_at'), findsNothing);
    });

    testWidgets('a linkable row offers View Retailer', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      // Two of the three rows have a relationship id.
      expect(
        find.widgetWithText(SrButton, VendorProductCopy.viewRetailer),
        findsNWidgets(2),
      );
    });

    testWidgets('a suspended relationship is still linkable', (
      WidgetTester tester,
    ) async {
      // What makes a row un-openable is the absence of the row to open, never a
      // status — and the Retailer screen exists to explain a suspension.
      await onEspresso(tester);

      final Finder harbourTile = find.ancestor(
        of: find.text('Harbour Provisions'),
        matching: find.byType(VendorProductAssignmentTile),
      );

      expect(
        find.descendant(
          of: harbourTile,
          matching: find.text(VendorProductCopy.viewRetailer),
        ),
        findsOneWidget,
      );
    });

    testWidgets('View Retailer opens the Retailer detail by relationship_id', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      final Finder northwindTile = find.ancestor(
        of: find.text('Northwind Retail'),
        matching: find.byType(VendorProductAssignmentTile),
      );
      await tapVisible(
        tester,
        find.descendant(
          of: northwindTile,
          matching: find.text(VendorProductCopy.viewRetailer),
        ),
      );

      expect(find.byType(VendorRetailerDetailPage), findsOneWidget);
      // Addressed by the relationship id, never the organization id.
      expect(
        currentLocation(tester),
        VendorNavigation.retailerDetailPath(northwindRelationshipId),
      );
      expect(currentLocation(tester).contains(northwindOrgId), isFalse);
    });

    testWidgets('a null relationship_id shows the unavailable state instead', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      final Finder orphanTile = find.ancestor(
        of: find.text('Old Town Grocers'),
        matching: find.byType(VendorProductAssignmentTile),
      );

      expect(
        find.descendant(
          of: orphanTile,
          matching: find.text(VendorProductCopy.relationshipUnavailable),
        ),
        findsOneWidget,
      );
      // Not a disabled button — no button at all.
      expect(
        find.descendant(
          of: orphanTile,
          matching: find.text(VendorProductCopy.viewRetailer),
        ),
        findsNothing,
      );
    });

    testWidgets('the unlinkable row keeps every other fact', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      final Finder orphanTile = find.ancestor(
        of: find.text('Old Town Grocers'),
        matching: find.byType(VendorProductAssignmentTile),
      );

      expect(
        find.descendant(
          of: orphanTile,
          matching: find.text('Inactive assignment'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: orphanTile,
          matching: find.text('Retailer: Deactivated'),
        ),
        findsOneWidget,
      );
      // And no relationship pill, because there is no relationship row.
      expect(
        find.descendant(
          of: orphanTile,
          matching: find.textContaining('Relationship:'),
        ),
        findsNothing,
      );
    });

    testWidgets('the unlinkable state is explained once, above the rows', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      expect(
        find.text(VendorProductCopy.relationshipUnavailableNote),
        findsOneWidget,
      );
    });

    testWidgets('no note appears when every row is linkable', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);
      await tapVisible(tester, find.text('Seasonal Roast 250g'));

      expect(
        find.text(VendorProductCopy.relationshipUnavailableNote),
        findsNothing,
      );
    });

    testWidgets('an assignment row carries a full spoken summary', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      expect(semanticsContaining('Northwind Retail'), findsWidgets);
      expect(
        semanticsContaining('Assignment: Active assignment'),
        findsWidgets,
      );
      expect(semanticsContaining('Retailer: Suspended'), findsWidgets);
      expect(
        semanticsContaining(VendorProductCopy.relationshipUnavailableSemantics),
        findsWidgets,
      );
      expect(
        semanticsContaining(
          '${VendorProductCopy.viewRetailer}: Northwind Retail',
        ),
        findsWidgets,
      );
    });

    testWidgets('a product with no assignments shows the empty state', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onCatalogue(tester);
      await tapVisible(tester, find.text('Cold Brew Concentrate 1L'));

      expect(
        find.text(VendorProductCopy.assignmentsEmptyTitle),
        findsOneWidget,
      );
      expect(find.byType(VendorProductAssignmentTile), findsNothing);
      // The companion WAS called — the empty list is a real answer, not the
      // ambiguous one an unknown id would have produced.
      expect(app.vendorProducts.assignmentsCallCount, 1);
      expect(
        find.text('No Retailer assignments · None currently active'),
        findsOneWidget,
      );
    });

    testWidgets('the section says the list includes withdrawn assignments', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      expect(
        find.text(VendorProductCopy.assignmentsDescription),
        findsOneWidget,
      );
    });

    testWidgets('no Retailer owner, staff, shop or contact data is shown', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      for (final String forbidden in <String>[
        'Owner',
        'Invite',
        'Email',
        'Phone',
        'Shops',
        'Staff',
        'Receipt',
        'Sales',
      ]) {
        expect(
          find.descendant(
            of: find.byType(VendorProductAssignmentTile),
            matching: find.textContaining(forbidden),
          ),
          findsNothing,
          reason: 'an assignment row shows "$forbidden"',
        );
      }
    });

    testWidgets('a section failure keeps the product detail on screen', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository()
            ..assignmentsResult =
                unavailableProductRead<List<VendorProductAssignedRetailer>>();

      await onEspresso(tester, products: repository);

      expect(
        find.text(VendorProductCopy.assignmentsUnavailableTitle),
        findsOneWidget,
      );
      // The product's own facts came from a call that succeeded.
      expect(find.text('Status: Active'), findsOneWidget);
      expect(find.text('ESP-1000'), findsOneWidget);
      expect(
        find.text('3 Retailer assignments · 2 currently active'),
        findsOneWidget,
      );
    });

    testWidgets('its retry re-reads only the assignments', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository()
            ..assignmentsResult =
                unavailableProductRead<List<VendorProductAssignedRetailer>>();

      await onEspresso(tester, products: repository);
      expect(repository.detailCallCount, 1);

      repository.assignmentsResult = null;
      await tapVisible(tester, find.text(VendorProductCopy.retryAssignments));

      expect(repository.detailCallCount, 1);
      expect(repository.assignmentsCallCount, 2);
      expect(find.byType(VendorProductAssignmentTile), findsNWidgets(3));
    });

    testWidgets('a count mismatch is surfaced without dropping rows', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository()
            ..assignmentsResult =
                ReadSuccess<List<VendorProductAssignedRetailer>>(
                  <VendorProductAssignedRetailer>[espressoAssignments.first],
                );

      await onEspresso(tester, products: repository);

      expect(find.text(VendorProductCopy.countMismatchTitle), findsOneWidget);
      // Everything returned is still rendered, and both counts are unchanged.
      expect(find.byType(VendorProductAssignmentTile), findsOneWidget);
      expect(
        find.text('3 Retailer assignments · 2 currently active'),
        findsNWidgets(2),
      );
    });
  });

  group('a product this caller cannot address', () {
    testWidgets('a manually typed unknown id shows one safe state', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository()
            ..detailResult = const ReadSuccess<VendorProductDetail?>(null);

      await onCatalogue(tester, products: repository);
      await goTo(
        tester,
        VendorNavigation.productDetailPath(unknownProductUuid),
      );

      expect(find.text(VendorProductCopy.detailNotFoundTitle), findsOneWidget);
      // Says nothing about existence or ownership.
      expect(find.textContaining('another Vendor'), findsNothing);
      expect(find.textContaining('exists'), findsNothing);
      expect(find.textContaining('belongs to'), findsNothing);
      // Not an outage: no retry.
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('a malformed id in the URL reaches the same state', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);
      await goTo(tester, '${VendorNavigation.products}/not-a-uuid');

      expect(find.text(VendorProductCopy.detailNotFoundTitle), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('a malformed id makes ZERO detail and assignment RPC calls', (
      WidgetTester tester,
    ) async {
      // Driven through the **real** repository over a counting data source, so
      // the id-shape guard is genuinely in the path rather than stubbed out.
      int detailCalls = 0;
      int assignmentCalls = 0;
      int listCalls = 0;

      final SupabaseVendorProductRepository real =
          SupabaseVendorProductRepository(
            rpc: VendorProductRpcDataSource(
              products: () async {
                listCalls++;
                return productRows();
              },
              detail: (String productId) async {
                detailCalls++;
                return <Map<String, Object?>>[productDetailRow()];
              },
              assignedRetailers: (String productId) async {
                assignmentCalls++;
                return <Map<String, Object?>>[assignedRetailerRow()];
              },
            ),
            writes: unusedVendorProductWrites(),
            assignments: unusedVendorProductAssignments(),
          );

      await pumpAppInRole(
        tester,
        PortalKind.vendorSuperAdmin,
        vendorProductRepository: real,
      );
      await goTo(tester, VendorNavigation.products);
      expect(listCalls, 1);

      await goTo(tester, '${VendorNavigation.products}/not-a-uuid');

      // The whole point.
      expect(detailCalls, 0);
      expect(assignmentCalls, 0);
      expect(find.text(VendorProductCopy.detailNotFoundTitle), findsOneWidget);
      // And nothing raw leaked in place of the safe wording.
      expect(find.textContaining('22P02'), findsNothing);
      expect(find.textContaining('uuid'), findsNothing);
      expect(find.textContaining('PostgrestException'), findsNothing);
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('a valid unknown id calls detail once and assignments never', (
      WidgetTester tester,
    ) async {
      int detailCalls = 0;
      int assignmentCalls = 0;

      final SupabaseVendorProductRepository real =
          SupabaseVendorProductRepository(
            rpc: VendorProductRpcDataSource(
              products: () async => productRows(),
              detail: (String productId) async {
                detailCalls++;
                return const <Object?>[]; // zero rows
              },
              assignedRetailers: (String productId) async {
                assignmentCalls++;
                return const <Object?>[];
              },
            ),
            writes: unusedVendorProductWrites(),
            assignments: unusedVendorProductAssignments(),
          );

      await pumpAppInRole(
        tester,
        PortalKind.vendorSuperAdmin,
        vendorProductRepository: real,
      );
      await goTo(tester, VendorNavigation.products);
      await goTo(
        tester,
        VendorNavigation.productDetailPath(unknownProductUuid),
      );

      expect(detailCalls, 1);
      // The detail read is the authoritative existence check, so the companion
      // is never asked.
      expect(assignmentCalls, 0);
      expect(find.text(VendorProductCopy.detailNotFoundTitle), findsOneWidget);
    });

    testWidgets('the safe state offers a way back to the catalogue', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository()
            ..detailResult = const ReadSuccess<VendorProductDetail?>(null);

      await onCatalogue(tester, products: repository);
      await goTo(
        tester,
        VendorNavigation.productDetailPath(unknownProductUuid),
      );

      await tapVisible(tester, find.text(VendorProductCopy.backToList).last);

      expect(find.byType(VendorProductsPage), findsOneWidget);
    });

    testWidgets('a detail outage offers a retry that works', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository()
            ..detailResult = unavailableProductRead<VendorProductDetail?>();

      await onCatalogue(tester, products: repository);
      await goTo(
        tester,
        VendorNavigation.productDetailPath(espressoProductUuid),
      );

      expect(find.byType(SrFailureView), findsOneWidget);

      repository.detailResult = null;
      await tapVisible(tester, find.text('Try again'));

      expect(find.text('Espresso Blend 1kg'), findsOneWidget);
      expect(find.byType(VendorProductAssignmentTile), findsNWidgets(3));
    });
  });

  group('session isolation', () {
    testWidgets('signing out clears the catalogue', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onCatalogue(tester);
      expect(find.text('Espresso Blend 1kg'), findsOneWidget);

      app.auth.emitSignedOut();
      await tester.pumpAndSettle();

      expect(find.byType(VendorProductsPage), findsNothing);
      expect(find.text('Espresso Blend 1kg'), findsNothing);
      expect(find.text('ESP-1000'), findsNothing);
    });

    testWidgets('an open product and its Retailer names are cleared too', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onEspresso(tester);
      expect(find.text('Northwind Retail'), findsOneWidget);

      app.auth.emitSignedOut();
      await tester.pumpAndSettle();

      expect(find.byType(VendorProductDetailPage), findsNothing);
      expect(find.text('Northwind Retail'), findsNothing);
      expect(find.text('Old Town Grocers'), findsNothing);
    });

    testWidgets('a new Vendor never sees the previous one\'s catalogue', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository();
      final PumpedApp app = await onCatalogue(tester, products: repository);
      expect(find.text('ESP-1000'), findsOneWidget);

      repository.productsResult =
          ReadSuccess<List<VendorProductSummary>>(<VendorProductSummary>[
            VendorProductSummary(
              productId: unknownProductUuid,
              productCode: 'OTH-9000',
              barcode: null,
              productName: 'Another Vendor Product',
              brand: null,
              description: null,
              status: VendorProductStatus.active,
              activeAssignmentCount: 0,
              createdAt: espressoCreatedAt,
              updatedAt: espressoUpdatedAt,
            ),
          ]);
      app.auth.emitSignedIn(secondUser);
      await tester.pumpAndSettle();

      expect(find.text('ESP-1000'), findsNothing);
      expect(find.text('Espresso Blend 1kg'), findsNothing);
      expect(find.text('OTH-9000'), findsOneWidget);
      expect(repository.productsCallCount, 2);
    });

    testWidgets('a search term does not survive a session change', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onCatalogue(tester);
      await tester.enterText(find.byType(TextField).first, 'espresso');
      await tester.pumpAndSettle();
      expect(find.text('Showing 1 of 4'), findsOneWidget);

      app.auth.emitSignedIn(secondUser);
      await tester.pumpAndSettle();

      expect(find.text('Showing 1 of 4'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty,
      );
    });

    testWidgets('the Retailer, User and Role directories still clear too', (
      WidgetTester tester,
    ) async {
      // The Product milestone must not have displaced any earlier half.
      final PumpedApp app = await onCatalogue(tester);
      await goTo(tester, VendorNavigation.retailers);
      expect(find.text('Northwind Retail'), findsOneWidget);

      app.auth.emitSignedOut();
      await tester.pumpAndSettle();

      expect(find.text('Northwind Retail'), findsNothing);
    });
  });

  group('responsive and themed', () {
    for (final (String name, Size surface) in <(String, Size)>[
      ('a small phone', smallPhoneSurface),
      ('a phone', phoneSurface),
      ('a tablet', tabletSurface),
      ('a desktop browser', desktopSurface),
    ]) {
      testWidgets('the catalogue lays out on $name without overflowing', (
        WidgetTester tester,
      ) async {
        await onCatalogue(tester, surface: surface);

        expect(find.byType(VendorProductCard), findsNWidgets(4));
        expect(tester.takeException(), isNull);
      });

      testWidgets('a product detail lays out on $name without overflowing', (
        WidgetTester tester,
      ) async {
        await onEspresso(tester, surface: surface);

        expect(find.byType(VendorProductDetailPage), findsOneWidget);
        expect(find.byType(VendorProductAssignmentTile), findsNWidgets(3));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('long names and identifiers do not overflow a small phone', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository()
            ..productsResult =
                ReadSuccess<List<VendorProductSummary>>(<VendorProductSummary>[
                  VendorProductSummary(
                    productId: espressoProductUuid,
                    productCode:
                        'ESP-1000-EXTREMELY-LONG-INTERNAL-PRODUCT-CODE-VALUE',
                    barcode: '50123456789001234',
                    productName:
                        'Single Origin Ethiopian Yirgacheffe Whole Bean '
                        'Espresso Blend, One Kilogram Catering Pack',
                    brand: 'A Deliberately Long Brand Name For Wrapping',
                    description: null,
                    status: VendorProductStatus.active,
                    activeAssignmentCount: 4096,
                    createdAt: espressoCreatedAt,
                    updatedAt: espressoUpdatedAt,
                  ),
                ]);

      await onCatalogue(
        tester,
        products: repository,
        surface: smallPhoneSurface,
      );

      expect(find.byType(VendorProductCard), findsOneWidget);
      expect(find.text('4096 Retailers currently hold this'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long Retailer name wraps on a small phone', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository()
            ..assignmentsResult =
                ReadSuccess<List<VendorProductAssignedRetailer>>(
                  <VendorProductAssignedRetailer>[
                    VendorProductAssignedRetailer(
                      relationshipId: northwindRelationshipId,
                      retailerOrganizationId: northwindOrgId,
                      retailerName:
                          'Northwind Retail Group Holdings International '
                          'Trading Company Limited',
                      retailerStatus: VendorRetailerStatus.suspended,
                      relationshipStatus: VendorRetailerStatus.deactivated,
                      assignmentStatus: VendorProductAssignmentStatus.inactive,
                      assignedAt: DateTime.utc(2026, 4, 19),
                      assignmentUpdatedAt: DateTime.utc(2026, 5, 30),
                    ),
                  ],
                );

      await onEspresso(
        tester,
        products: repository,
        surface: smallPhoneSurface,
      );

      expect(find.byType(VendorProductAssignmentTile), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the catalogue survives large text scaling', (
      WidgetTester tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await onCatalogue(tester, surface: phoneSurface);

      expect(find.byType(VendorProductCard), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a product detail survives large text scaling', (
      WidgetTester tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await onEspresso(tester, surface: phoneSurface);

      expect(find.byType(VendorProductAssignmentTile), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('wide screens use more than one column', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester, surface: desktopSurface);

      final List<Offset> positions = tester
          .widgetList<VendorProductCard>(find.byType(VendorProductCard))
          .map(
            (VendorProductCard card) => tester.getTopLeft(find.byWidget(card)),
          )
          .toList();

      expect(positions[0].dy, positions[1].dy);
      expect(positions[0].dx, lessThan(positions[1].dx));
    });

    testWidgets('a phone stacks the cards', (WidgetTester tester) async {
      await onCatalogue(tester, surface: phoneSurface);

      final List<Offset> positions = tester
          .widgetList<VendorProductCard>(find.byType(VendorProductCard))
          .map(
            (VendorProductCard card) => tester.getTopLeft(find.byWidget(card)),
          )
          .toList();

      expect(positions[0].dx, positions[1].dx);
      expect(positions[0].dy, lessThan(positions[1].dy));
    });

    for (final ThemeMode mode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
      testWidgets('the catalogue renders in $mode', (
        WidgetTester tester,
      ) async {
        await pumpApp(
          tester,
          initialUser: testUser,
          portalResult: resolvedResult(PortalKind.vendorSuperAdmin),
          themeMode: mode,
        );
        await goTo(tester, VendorNavigation.products);

        expect(find.byType(VendorProductCard), findsNWidgets(4));
        expect(tester.takeException(), isNull);
      });

      testWidgets('a product detail with mixed assignments renders in $mode', (
        WidgetTester tester,
      ) async {
        await pumpApp(
          tester,
          initialUser: testUser,
          portalResult: resolvedResult(PortalKind.vendorSuperAdmin),
          themeMode: mode,
        );
        await goTo(tester, VendorNavigation.products);
        await tapVisible(tester, find.text('Espresso Blend 1kg'));

        expect(find.byType(VendorProductAssignmentTile), findsNWidgets(3));
        expect(find.text('Inactive assignment'), findsOneWidget);
        expect(
          find.text(VendorProductCopy.relationshipUnavailable),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
