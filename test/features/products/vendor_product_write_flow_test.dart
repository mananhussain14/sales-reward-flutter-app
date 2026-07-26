import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sale_reward/app/router/app_router.dart';
import 'package:sale_reward/app/shells/vendor/vendor_navigation.dart';
import 'package:sale_reward/core/widgets/widgets.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/auth/presentation/bloc/session_bloc.dart';
import 'package:sale_reward/core/result/read_result.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_detail.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_draft.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_edit.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_status.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_status_change.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_summary.dart';
import 'package:sale_reward/features/products/domain/repositories/vendor_product_write_result.dart';
import 'package:sale_reward/features/products/presentation/vendor/pages/vendor_product_create_page.dart';
import 'package:sale_reward/features/products/presentation/vendor/pages/vendor_product_detail_page.dart';
import 'package:sale_reward/features/products/presentation/vendor/pages/vendor_product_edit_page.dart';
import 'package:sale_reward/features/products/presentation/vendor/pages/vendor_products_page.dart';
import 'package:sale_reward/features/products/presentation/vendor/widgets/vendor_product_copy.dart';
import 'package:sale_reward/core/errors/failure.dart';

import '../../support/fakes.dart';
import '../../support/pump_app.dart';
import '../../support/vendor_product_fakes.dart';

/// Drives the Vendor Product **write** screens through the real application: real
/// router, real shell, real cubits, over a fake repository that never touches
/// Supabase.

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

/// Types into the field whose visible label starts with [label].
Future<void> enterField(WidgetTester tester, String label, String value) async {
  final Finder field = find.ancestor(
    of: find.byWidgetPredicate(
      (Widget widget) =>
          widget is RichText && widget.text.toPlainText().startsWith(label),
    ),
    matching: find.byType(SrTextField),
  );
  await tester.ensureVisible(field.first);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(of: field.first, matching: find.byType(TextField)),
    value,
  );
  await tester.pumpAndSettle();
}

/// Confirms the open dialog by pressing its [label] action.
///
/// Scoped to the [AlertDialog]: `SrButton` renders a `TextButton` internally, so an
/// unscoped `widgetWithText(TextButton, …)` would match the page's own status control
/// as well as the dialog's — and tapping the wrong one would reopen the dialog rather
/// than confirm it.
Future<void> confirm(WidgetTester tester, String label) async {
  final Finder action = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.widgetWithText(TextButton, label),
  );
  expect(action, findsOneWidget);
  await tester.tap(action);
  await tester.pumpAndSettle();
}

Finder semanticsContaining(String fragment) => find.byWidgetPredicate(
  (Widget widget) =>
      widget is Semantics &&
      (widget.properties.label?.contains(fragment) ?? false),
  description: 'Semantics whose label contains "$fragment"',
);

void main() {
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

  Future<PumpedApp> onCreateForm(
    WidgetTester tester, {
    FakeVendorProductRepository? products,
    Size surface = phoneSurface,
  }) async {
    final PumpedApp app = await onCatalogue(
      tester,
      products: products,
      surface: surface,
    );
    await tapVisible(tester, find.text(VendorProductCopy.addProduct).first);
    return app;
  }

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

  Future<PumpedApp> onEditForm(
    WidgetTester tester, {
    FakeVendorProductRepository? products,
    Size surface = phoneSurface,
  }) async {
    final PumpedApp app = await onEspresso(
      tester,
      products: products,
      surface: surface,
    );
    await tapVisible(tester, find.text(VendorProductCopy.edit));
    return app;
  }

  /// Fills the create form with a valid product.
  Future<void> fillCreateForm(
    WidgetTester tester, {
    String code = 'flat-white-500',
    String name = '  Flat White   Blend 500g  ',
    String barcode = ' 501 234-567-8924 ',
    String brand = 'Harvest Roasters',
    String description = 'A milk-forward blend.',
  }) async {
    await enterField(tester, VendorProductCopy.codeLabel, code);
    await enterField(tester, VendorProductCopy.nameLabel, name);
    await enterField(tester, VendorProductCopy.barcodeLabel, barcode);
    await enterField(tester, VendorProductCopy.brandLabel, brand);
    await enterField(tester, VendorProductCopy.descriptionLabel, description);
  }

  group('route isolation', () {
    test('the guard sends every other role away from both write routes', () {
      for (final PortalKind kind in <PortalKind>[
        PortalKind.retailerOwner,
        PortalKind.retailerManager,
        PortalKind.salesStaff,
      ]) {
        final SessionState session = SessionActive(contextFor(kind));
        final String home = sessionHome(session);

        expect(redirectFor(session, VendorNavigation.productCreate), home);
        expect(
          redirectFor(
            session,
            VendorNavigation.productEditPath(espressoProductUuid),
          ),
          home,
        );
      }
    });

    test('a Vendor Super Admin is allowed into both', () {
      final SessionState session = SessionActive(
        contextFor(PortalKind.vendorSuperAdmin),
      );

      expect(redirectFor(session, VendorNavigation.productCreate), isNull);
      expect(
        redirectFor(
          session,
          VendorNavigation.productEditPath(espressoProductUuid),
        ),
        isNull,
      );
    });

    test('a signed-out caller is sent to login, not to a form', () {
      expect(
        redirectFor(
          const SessionUnauthenticated(),
          VendorNavigation.productCreate,
        ),
        '/login',
      );
      expect(
        redirectFor(
          const SessionUnauthenticated(),
          VendorNavigation.productEditPath(espressoProductUuid),
        ),
        '/login',
      );
    });

    test('the paths are nested under the catalogue', () {
      expect(VendorNavigation.productCreate, '/vendor/products/new');
      expect(
        VendorNavigation.productEditPath(espressoProductUuid),
        '/vendor/products/$espressoProductUuid/edit',
      );
    });

    test('the create path can never be mistaken for a product id', () {
      // The literal segment is `new`, which is not 8-4-4-4-12 hexadecimal, so no real
      // product id can be shadowed by it.
      expect(VendorNavigation.productCreate.endsWith('/new'), isTrue);
      expect(
        RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
          r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch('new'),
        isFalse,
      );
    });

    test('no assignment write route exists', () {
      // Assignment writes are a separate milestone on a separate permission.
      final String navigation = VendorNavigation.products;
      for (final String forbidden in <String>[
        '$navigation/assign',
        '$navigation/$espressoProductUuid/assign',
        '$navigation/$espressoProductUuid/retailers/assign',
      ]) {
        expect(
          VendorNavigation.productCreate == forbidden ||
              VendorNavigation.productEditPath(espressoProductUuid) ==
                  forbidden,
          isFalse,
        );
      }
    });

    testWidgets('Products stays selected for create and edit', (
      WidgetTester tester,
    ) async {
      // `indexForLocation` takes the longest matching prefix, so both write routes
      // keep the catalogue's destination highlighted.
      final int products = VendorNavigation.model.indexForLocation(
        VendorNavigation.products,
      );

      expect(
        VendorNavigation.model.indexForLocation(VendorNavigation.productCreate),
        products,
      );
      expect(
        VendorNavigation.model.indexForLocation(
          VendorNavigation.productEditPath(espressoProductUuid),
        ),
        products,
      );
    });

    testWidgets('a Retailer Owner cannot reach either form', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.retailerOwner);
      await goTo(tester, VendorNavigation.productCreate);

      expect(find.byType(VendorProductCreatePage), findsNothing);
      expect(currentLocation(tester), isNot(startsWith('/vendor')));

      await goTo(tester, VendorNavigation.productEditPath(espressoProductUuid));
      expect(find.byType(VendorProductEditPage), findsNothing);
    });

    testWidgets('a Retailer Manager cannot either', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.retailerManager);
      await goTo(tester, VendorNavigation.productCreate);

      expect(find.byType(VendorProductCreatePage), findsNothing);
      expect(currentLocation(tester), isNot(startsWith('/vendor')));
    });

    testWidgets('Sales Staff cannot either', (WidgetTester tester) async {
      await pumpAppInRole(tester, PortalKind.salesStaff);
      await goTo(tester, VendorNavigation.productEditPath(espressoProductUuid));

      expect(find.byType(VendorProductEditPage), findsNothing);
      expect(currentLocation(tester), isNot(startsWith('/vendor')));
    });

    testWidgets('no other role writes a product', (WidgetTester tester) async {
      for (final PortalKind kind in <PortalKind>[
        PortalKind.retailerOwner,
        PortalKind.retailerManager,
        PortalKind.salesStaff,
      ]) {
        final FakeVendorProductRepository repository =
            FakeVendorProductRepository();
        await pumpAppInRole(tester, kind, vendorProducts: repository);
        await goTo(tester, VendorNavigation.productCreate);
        await goTo(
          tester,
          VendorNavigation.productEditPath(espressoProductUuid),
        );

        expect(repository.submittedDrafts, isEmpty);
        expect(repository.submittedEdits, isEmpty);
        expect(repository.submittedStatusChanges, isEmpty);
      }
    });
  });

  group('reaching the create form', () {
    testWidgets('Add product is visible to a Vendor Super Admin', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);

      expect(
        find.widgetWithText(SrButton, VendorProductCopy.addProduct),
        findsOneWidget,
      );
      expect(
        semanticsContaining(VendorProductCopy.addProduct),
        findsAtLeastNWidgets(1),
      );
    });

    testWidgets('it opens the create route', (WidgetTester tester) async {
      await onCreateForm(tester);

      expect(find.byType(VendorProductCreatePage), findsOneWidget);
      expect(currentLocation(tester), VendorNavigation.productCreate);
    });

    testWidgets('the empty catalogue offers it too', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository()
            ..productsResult = const ReadSuccess<List<VendorProductSummary>>(
              <VendorProductSummary>[],
            );

      await onCatalogue(tester, products: repository);

      expect(find.text(VendorProductCopy.emptyTitle), findsOneWidget);
      await tapVisible(tester, find.text(VendorProductCopy.addProduct).first);
      expect(find.byType(VendorProductCreatePage), findsOneWidget);
    });

    testWidgets('the shell stays visible around the form', (
      WidgetTester tester,
    ) async {
      await onCreateForm(tester, surface: desktopSurface);

      // The permanent side panel is the shell; the form renders inside it.
      expect(find.byType(VendorProductCreatePage), findsOneWidget);
      expect(find.text('Dashboard'), findsWidgets);
      expect(find.text('Audit Logs'), findsWidgets);
    });

    testWidgets('typing a URL straight to it works', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.vendorSuperAdmin);
      await goTo(tester, VendorNavigation.productCreate);

      expect(find.byType(VendorProductCreatePage), findsOneWidget);
    });

    testWidgets('browser back returns to the loaded catalogue', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onCreateForm(tester);
      final int reads = app.vendorProducts.productsCallCount;

      await tapVisible(tester, find.text(VendorProductCopy.backToList).first);

      expect(find.byType(VendorProductsPage), findsOneWidget);
      expect(find.text('Espresso Blend 1kg'), findsOneWidget);
      // Coming back renders rows already held.
      expect(app.vendorProducts.productsCallCount, reads);
    });
  });

  group('the create form', () {
    testWidgets('it shows exactly the five product fields', (
      WidgetTester tester,
    ) async {
      await onCreateForm(tester);

      for (final String label in <String>[
        VendorProductCopy.codeLabel,
        VendorProductCopy.nameLabel,
        VendorProductCopy.barcodeLabel,
        VendorProductCopy.brandLabel,
        VendorProductCopy.descriptionLabel,
      ]) {
        expect(
          find.byWidgetPredicate(
            (Widget widget) =>
                widget is RichText &&
                widget.text.toPlainText().startsWith(label),
          ),
          findsAtLeastNWidgets(1),
          reason: 'the create form has no "$label" field',
        );
      }
      expect(find.byType(SrTextField), findsNWidgets(5));
    });

    testWidgets(
      'the two required fields are marked, the three optional ones too',
      (WidgetTester tester) async {
        await onCreateForm(tester);

        // A visible asterisk and a visible "(optional)" — requirement is never
        // signalled by colour or placement alone.
        final Iterable<String> labels = tester
            .widgetList<RichText>(find.byType(RichText))
            .map((RichText r) => r.text.toPlainText());

        expect(
          labels.where((String l) => l.startsWith(VendorProductCopy.codeLabel)),
          anyElement(contains('*')),
        );
        expect(
          labels.where((String l) => l.startsWith(VendorProductCopy.nameLabel)),
          anyElement(contains('*')),
        );
        for (final String optional in <String>[
          VendorProductCopy.barcodeLabel,
          VendorProductCopy.brandLabel,
          VendorProductCopy.descriptionLabel,
        ]) {
          expect(
            labels.where((String l) => l.startsWith(optional)),
            anyElement(contains('(optional)')),
            reason: '"$optional" is not marked optional',
          );
        }
      },
    );

    testWidgets('there is NO status selector', (WidgetTester tester) async {
      // A new product is ACTIVE, decided by the function; there is no
      // initial-status argument to offer a choice over.
      await onCreateForm(tester);

      expect(find.text(VendorProductCopy.statusLabel), findsNothing);
      expect(find.byType(DropdownButton<Object?>), findsNothing);
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(Radio<Object?>), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('Active'), findsNothing);
      expect(find.text('Inactive'), findsNothing);
    });

    testWidgets('there is NO Vendor, Retailer or assignment control', (
      WidgetTester tester,
    ) async {
      await onCreateForm(tester);

      for (final String forbidden in <String>[
        'Vendor organization',
        'Assign',
        'Retailer',
        'Assign to Retailer',
        'Price',
        'Stock',
        'Quantity',
        'Image',
        'Upload',
        'Reward',
        'Campaign',
      ]) {
        expect(
          find.text(forbidden),
          findsNothing,
          reason: 'the create form offers "$forbidden"',
        );
      }
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('the actions are Create and Cancel, and nothing else', (
      WidgetTester tester,
    ) async {
      await onCreateForm(tester);

      for (final SrButton button in tester.widgetList<SrButton>(
        find.byType(SrButton),
      )) {
        expect(
          <String>[
            VendorProductCopy.createSubmit,
            VendorProductCopy.cancel,
            VendorProductCopy.backToList,
          ].contains(button.label),
          isTrue,
          reason: 'an unexpected control "${button.label}" is on the form',
        );
      }
    });

    testWidgets('every action carries a spoken label', (
      WidgetTester tester,
    ) async {
      await onCreateForm(tester);

      expect(
        semanticsContaining(VendorProductCopy.createSubmit),
        findsAtLeastNWidgets(1),
      );
      expect(
        semanticsContaining(VendorProductCopy.cancel),
        findsAtLeastNWidgets(1),
      );
    });

    testWidgets('Cancel returns to the catalogue without writing', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onCreateForm(tester);
      await fillCreateForm(tester);

      await tapVisible(tester, find.text(VendorProductCopy.cancel));

      expect(find.byType(VendorProductsPage), findsOneWidget);
      expect(app.vendorProducts.submittedDrafts, isEmpty);
    });
  });

  group('create validation', () {
    testWidgets('an empty submission shows both required messages', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onCreateForm(tester);

      await tapVisible(tester, find.text(VendorProductCopy.createSubmit));

      expect(find.text('Enter a product code.'), findsOneWidget);
      expect(find.text('Enter a product name.'), findsOneWidget);
      // Nothing left the client.
      expect(app.vendorProducts.submittedDrafts, isEmpty);
    });

    testWidgets('a bad barcode is reported under its own field', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onCreateForm(tester);
      await fillCreateForm(tester, barcode: '123');

      await tapVisible(tester, find.text(VendorProductCopy.createSubmit));

      expect(
        find.text('Enter a barcode of 8 to 14 digits, or leave it blank.'),
        findsOneWidget,
      );
      expect(app.vendorProducts.submittedDrafts, isEmpty);
    });

    testWidgets('no validation message names a table or a SQLSTATE', (
      WidgetTester tester,
    ) async {
      await onCreateForm(tester);
      await tapVisible(tester, find.text(VendorProductCopy.createSubmit));

      for (final String forbidden in <String>[
        'vendor_products',
        'check constraint',
        'violates',
        '23514',
        '23505',
        '42501',
        'PostgrestException',
        'PRODUCTS_MANAGE',
      ]) {
        expect(find.textContaining(forbidden), findsNothing);
      }
    });
  });

  group('a successful create', () {
    testWidgets('it sends the five normalized values', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onCreateForm(tester);
      await fillCreateForm(tester);

      await tapVisible(tester, find.text(VendorProductCopy.createSubmit));

      expect(app.vendorProducts.submittedDrafts.length, 1);
      final VendorProductDraft sent = app.vendorProducts.submittedDrafts.single;
      expect(sent.productCode, 'FLAT-WHITE-500');
      expect(sent.productName, 'Flat White Blend 500g');
      expect(sent.barcode, '5012345678924');
      expect(sent.brand, 'Harvest Roasters');
      expect(sent.description, 'A milk-forward blend.');
    });

    testWidgets('it navigates to the canonical product detail', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onCreateForm(tester);
      await fillCreateForm(tester);

      await tapVisible(tester, find.text(VendorProductCopy.createSubmit));

      expect(find.byType(VendorProductDetailPage), findsOneWidget);
      expect(
        currentLocation(tester),
        VendorNavigation.productDetailPath(createdProductUuid),
      );
      // Read from the backend, not echoed from the form.
      expect(
        app.vendorProducts.requestedDetailIds,
        contains(createdProductUuid),
      );
    });

    testWidgets('the values on screen are the backend\'s, not the form\'s', (
      WidgetTester tester,
    ) async {
      // The fixture's canonical row deliberately differs in casing from what is
      // typed, so a screen that echoed the form would visibly differ.
      await onCreateForm(tester);
      await fillCreateForm(tester);
      await tapVisible(tester, find.text(VendorProductCopy.createSubmit));

      expect(find.text('Flat White Blend 500g'), findsAtLeastNWidgets(1));
      expect(find.text('FLAT-WHITE-500'), findsOneWidget);
      expect(find.text('5012345678924'), findsOneWidget);
    });

    testWidgets('the new product is ACTIVE, as the backend reported', (
      WidgetTester tester,
    ) async {
      await onCreateForm(tester);
      await fillCreateForm(tester);
      await tapVisible(tester, find.text(VendorProductCopy.createSubmit));

      expect(find.text('Status: Active'), findsAtLeastNWidgets(1));
    });

    testWidgets('a success acknowledgement is shown on the product', (
      WidgetTester tester,
    ) async {
      await onCreateForm(tester);
      await fillCreateForm(tester);
      await tapVisible(tester, find.text(VendorProductCopy.createSubmit));

      expect(find.text(VendorProductCopy.createdTitle), findsOneWidget);
      expect(find.text(VendorProductCopy.createdBody), findsOneWidget);
    });

    testWidgets('no Retailer assignment is claimed', (
      WidgetTester tester,
    ) async {
      // A create writes no assignment row, and nothing here fabricates a count.
      await onCreateForm(tester);
      await fillCreateForm(tester);
      await tapVisible(tester, find.text(VendorProductCopy.createSubmit));

      expect(
        find.text(VendorProductCopy.assignmentsEmptyTitle),
        findsOneWidget,
      );
      expect(
        find.textContaining('No Retailer assignments'),
        findsAtLeastNWidgets(1),
      );
    });

    testWidgets('the catalogue is refreshed', (WidgetTester tester) async {
      final PumpedApp app = await onCreateForm(tester);
      final int before = app.vendorProducts.productsCallCount;
      await fillCreateForm(tester);

      await tapVisible(tester, find.text(VendorProductCopy.createSubmit));

      expect(app.vendorProducts.productsCallCount, greaterThan(before));
    });

    testWidgets('a double tap creates one product', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository()..manualCreate = true;
      await onCreateForm(tester, products: repository);
      await fillCreateForm(tester);

      final Finder submit = find.widgetWithText(
        SrButton,
        VendorProductCopy.createSubmit,
      );
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pump();
      expect(repository.pendingCreateCount, 1);

      // The control is disabled while the call is in flight, and now carries its
      // progress label — so a second press cannot become a second product.
      await tester.tap(
        find.widgetWithText(SrButton, VendorProductCopy.createSubmitting),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(repository.pendingCreateCount, 1);

      repository.completeCreate();
      await tester.pumpAndSettle();

      expect(repository.submittedDrafts.length, 1);
    });

    testWidgets('progress is shown while the call is in flight', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository()..manualCreate = true;
      await onCreateForm(tester, products: repository);
      await fillCreateForm(tester);

      await tester.ensureVisible(
        find.widgetWithText(SrButton, VendorProductCopy.createSubmit),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(SrButton, VendorProductCopy.createSubmit),
      );
      await tester.pump();

      expect(find.text(VendorProductCopy.createSubmitting), findsOneWidget);

      repository.completeCreate();
      await tester.pumpAndSettle();
    });
  });

  group('create refusals', () {
    testWidgets('a duplicate code is reported under the code field', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository()
            ..createResult = const VendorProductWriteFailure<String>(
              DuplicateFailure(field: 'productCode'),
            );
      await onCreateForm(tester, products: repository);
      await fillCreateForm(tester);

      await tapVisible(tester, find.text(VendorProductCopy.createSubmit));

      expect(
        find.text('A product with this code already exists.'),
        findsOneWidget,
      );
      expect(
        find.text('A product with this barcode already exists.'),
        findsNothing,
      );
      // Still on the form, with another attempt available.
      expect(find.byType(VendorProductCreatePage), findsOneWidget);
    });

    testWidgets('a duplicate barcode is reported under the barcode field', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository()
            ..createResult = const VendorProductWriteFailure<String>(
              DuplicateFailure(field: 'barcode'),
            );
      await onCreateForm(tester, products: repository);
      await fillCreateForm(tester);

      await tapVisible(tester, find.text(VendorProductCopy.createSubmit));

      expect(
        find.text('A product with this barcode already exists.'),
        findsOneWidget,
      );
      expect(
        find.text('A product with this code already exists.'),
        findsNothing,
      );
    });

    testWidgets('neither duplicate message mentions another Vendor', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository()
            ..createResult = const VendorProductWriteFailure<String>(
              DuplicateFailure(field: 'productCode'),
            );
      await onCreateForm(tester, products: repository);
      await fillCreateForm(tester);
      await tapVisible(tester, find.text(VendorProductCopy.createSubmit));

      for (final String forbidden in <String>[
        'another Vendor',
        'another organization',
        'Northwind',
        'Harbour',
      ]) {
        expect(find.textContaining(forbidden), findsNothing);
      }
    });

    testWidgets('a denial is one safe message naming no permission', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository()
            ..createResult = const VendorProductWriteFailure<String>(
              DeniedFailure(),
            );
      await onCreateForm(tester, products: repository);
      await fillCreateForm(tester);

      await tapVisible(tester, find.text(VendorProductCopy.createSubmit));

      expect(find.text(VendorProductCopy.writeDeniedTitle), findsOneWidget);
      for (final String forbidden in <String>[
        'PRODUCTS_MANAGE',
        'permission',
        '42501',
        'insufficient_privilege',
      ]) {
        expect(find.textContaining(forbidden), findsNothing);
      }
    });

    testWidgets('a transport failure is retryable and keeps the typed values', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository()
            ..createResult = const VendorProductWriteFailure<String>(
              UnavailableFailure(),
            );
      await onCreateForm(tester, products: repository);
      await fillCreateForm(tester);

      await tapVisible(tester, find.text(VendorProductCopy.createSubmit));

      expect(
        find.text(VendorProductCopy.writeUnavailableTitle),
        findsOneWidget,
      );
      // Nothing was written, so a second attempt is legitimate and costs nothing.
      expect(find.text('FLAT-WHITE-500'), findsOneWidget);

      repository.createResult = null;
      await tapVisible(tester, find.text(VendorProductCopy.createSubmit));
      expect(find.byType(VendorProductDetailPage), findsOneWidget);
    });

    testWidgets('no refusal navigates anywhere', (WidgetTester tester) async {
      for (final Failure failure in <Failure>[
        const DeniedFailure(),
        const UnavailableFailure(),
        const InvalidFailure(),
        const DuplicateFailure(field: 'barcode'),
      ]) {
        final FakeVendorProductRepository repository =
            FakeVendorProductRepository()
              ..createResult = VendorProductWriteFailure<String>(failure);
        await onCreateForm(tester, products: repository);
        await fillCreateForm(tester);
        await tapVisible(tester, find.text(VendorProductCopy.createSubmit));

        expect(currentLocation(tester), VendorNavigation.productCreate);
        expect(find.byType(VendorProductDetailPage), findsNothing);
      }
    });
  });

  group('a create that succeeded whose id could not be read', () {
    Future<PumpedApp> unconfirmedCreate(WidgetTester tester) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository()
            ..createResult = const VendorProductWriteUnconfirmed<String>();
      final PumpedApp app = await onCreateForm(tester, products: repository);
      await fillCreateForm(tester);
      await tapVisible(tester, find.text(VendorProductCopy.createSubmit));
      return app;
    }

    testWidgets('it is presented as a success, never as a failure', (
      WidgetTester tester,
    ) async {
      await unconfirmedCreate(tester);

      expect(
        find.text(VendorProductCopy.createUnconfirmedTitle),
        findsOneWidget,
      );
      expect(find.text(VendorProductCopy.writeUnavailableTitle), findsNothing);
      expect(find.text(VendorProductCopy.writeDeniedTitle), findsNothing);
    });

    testWidgets('it says not to create the product again', (
      WidgetTester tester,
    ) async {
      await unconfirmedCreate(tester);

      expect(
        find.text(VendorProductCopy.createUnconfirmedBody),
        findsOneWidget,
      );
    });

    testWidgets('the Create control is gone, so no duplicate is invited', (
      WidgetTester tester,
    ) async {
      await unconfirmedCreate(tester);

      expect(
        find.widgetWithText(SrButton, VendorProductCopy.createSubmit),
        findsNothing,
      );
      expect(
        find.widgetWithText(SrButton, VendorProductCopy.goToCatalogue),
        findsOneWidget,
      );
    });

    testWidgets('the catalogue is refreshed, and it is the way forward', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await unconfirmedCreate(tester);
      expect(app.vendorProducts.productsCallCount, greaterThan(1));

      await tapVisible(tester, find.text(VendorProductCopy.goToCatalogue));
      expect(find.byType(VendorProductsPage), findsOneWidget);
    });
  });

  group('reaching the edit form', () {
    testWidgets('Edit is offered on a product detail', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      expect(
        find.widgetWithText(SrButton, VendorProductCopy.edit),
        findsOneWidget,
      );
      expect(
        semanticsContaining(VendorProductCopy.edit),
        findsAtLeastNWidgets(1),
      );
    });

    testWidgets('it opens the edit route', (WidgetTester tester) async {
      await onEditForm(tester);

      expect(find.byType(VendorProductEditPage), findsOneWidget);
      expect(
        currentLocation(tester),
        VendorNavigation.productEditPath(espressoProductUuid),
      );
    });

    testWidgets('a deep link straight to it loads the product', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await pumpAppInRole(
        tester,
        PortalKind.vendorSuperAdmin,
      );
      await goTo(tester, VendorNavigation.productEditPath(espressoProductUuid));

      expect(find.byType(VendorProductEditPage), findsOneWidget);
      expect(
        app.vendorProducts.requestedDetailIds,
        contains(espressoProductUuid),
      );
      expect(find.text(VendorProductCopy.editTitle), findsOneWidget);
    });

    testWidgets('entering it from the product issues no second read', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onEspresso(tester);
      final int reads = app.vendorProducts.detailCallCount;

      await tapVisible(tester, find.text(VendorProductCopy.edit));

      expect(app.vendorProducts.detailCallCount, reads);
    });

    testWidgets('Back returns to the product', (WidgetTester tester) async {
      await onEditForm(tester);

      await tapVisible(
        tester,
        find.text(VendorProductCopy.backToProduct).first,
      );

      expect(find.byType(VendorProductDetailPage), findsOneWidget);
      expect(
        currentLocation(tester),
        VendorNavigation.productDetailPath(espressoProductUuid),
      );
    });
  });

  group('the edit form', () {
    testWidgets('it is seeded from the canonical product', (
      WidgetTester tester,
    ) async {
      await onEditForm(tester);

      expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .map((TextField f) => f.controller?.text),
        containsAll(<String>[
          'Espresso Blend 1kg',
          '5012345678900',
          'Harvest Roasters',
          'A dark roast blend for espresso machines.',
        ]),
      );
    });

    testWidgets('the product code is read-only context, not an input', (
      WidgetTester tester,
    ) async {
      await onEditForm(tester);

      // Visible, so a person knows which product they are editing…
      expect(find.text('ESP-1000'), findsOneWidget);
      expect(find.text(VendorProductCopy.codeReadOnlyHint), findsOneWidget);
      // …and there are only four editable controls.
      expect(find.byType(SrTextField), findsNWidgets(4));
      expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .map((TextField f) => f.controller?.text),
        isNot(contains('ESP-1000')),
      );
    });

    testWidgets('the read-only code is spoken as read-only', (
      WidgetTester tester,
    ) async {
      await onEditForm(tester);

      expect(
        semanticsContaining(VendorProductCopy.codeReadOnlySemantics),
        findsOneWidget,
      );
    });

    testWidgets('there is no status control on the edit form', (
      WidgetTester tester,
    ) async {
      // The edit RPC never writes `status`, so a control for it would be a promise no
      // RPC can keep.
      await onEditForm(tester);

      expect(find.byType(Switch), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(DropdownButton<Object?>), findsNothing);
      expect(
        find.widgetWithText(SrButton, VendorProductCopy.deactivate),
        findsNothing,
      );
      expect(
        find.widgetWithText(SrButton, VendorProductCopy.activate),
        findsNothing,
      );
    });

    testWidgets('there is no assignment or delete control either', (
      WidgetTester tester,
    ) async {
      await onEditForm(tester);

      for (final String forbidden in <String>[
        'Delete',
        'Remove',
        'Assign',
        'Withdraw',
        'Unassign',
        VendorProductCopy.addProduct,
      ]) {
        expect(
          find.widgetWithText(SrButton, forbidden),
          findsNothing,
          reason: 'the edit form offers "$forbidden"',
        );
      }
    });

    testWidgets('a null optional seeds an empty control', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);
      await tapVisible(tester, find.text('Decaf Ground 500g'));
      await tapVisible(tester, find.text(VendorProductCopy.edit));

      final Iterable<String?> values = tester
          .widgetList<TextField>(find.byType(TextField))
          .map((TextField f) => f.controller?.text);

      // "Not recorded" is how a null is rendered on the detail screen; it must never
      // reach a form that is saved back.
      expect(values, isNot(contains(VendorProductCopy.notRecorded)));
      expect(values.where((String? v) => v != null && v.isEmpty).length, 3);
    });

    testWidgets('an inactive product is editable', (WidgetTester tester) async {
      await onCatalogue(tester);
      await tapVisible(tester, find.text('Seasonal Roast 250g'));
      await tapVisible(tester, find.text(VendorProductCopy.edit));

      expect(find.byType(VendorProductEditPage), findsOneWidget);
      expect(
        find.widgetWithText(SrButton, VendorProductCopy.save),
        findsOneWidget,
      );
    });
  });

  group('a successful edit', () {
    testWidgets('it sends the id and four values, and never the code', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onEditForm(tester);
      await enterField(tester, VendorProductCopy.nameLabel, 'Renamed Blend');

      await tapVisible(tester, find.text(VendorProductCopy.save));

      expect(app.vendorProducts.submittedEdits.length, 1);
      final ({String productId, VendorProductEdit edit}) sent =
          app.vendorProducts.submittedEdits.single;
      expect(sent.productId, espressoProductUuid);
      expect(sent.edit.productName, 'Renamed Blend');
      expect(sent.edit.barcode, '5012345678900');
      // No code anywhere on the request.
      for (final String? value in <String?>[
        sent.edit.productName,
        sent.edit.barcode,
        sent.edit.brand,
        sent.edit.description,
      ]) {
        expect(value, isNot('ESP-1000'));
      }
    });

    testWidgets('clearing the optionals sends nulls', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onEditForm(tester);
      await enterField(tester, VendorProductCopy.barcodeLabel, '');
      await enterField(tester, VendorProductCopy.brandLabel, '');
      await enterField(tester, VendorProductCopy.descriptionLabel, '');

      await tapVisible(tester, find.text(VendorProductCopy.save));

      final VendorProductEdit sent =
          app.vendorProducts.submittedEdits.single.edit;
      expect(sent.barcode, isNull);
      expect(sent.brand, isNull);
      expect(sent.description, isNull);
    });

    testWidgets('it returns to the product and acknowledges the save', (
      WidgetTester tester,
    ) async {
      await onEditForm(tester);
      await enterField(tester, VendorProductCopy.nameLabel, 'Renamed Blend');

      await tapVisible(tester, find.text(VendorProductCopy.save));

      expect(find.byType(VendorProductDetailPage), findsOneWidget);
      expect(
        currentLocation(tester),
        VendorNavigation.productDetailPath(espressoProductUuid),
      );
      expect(find.text(VendorProductCopy.updatedTitle), findsOneWidget);
    });

    testWidgets(
      'the canonical detail is re-read, and the catalogue refreshed',
      (WidgetTester tester) async {
        final PumpedApp app = await onEditForm(tester);
        final int detailReads = app.vendorProducts.detailCallCount;
        final int listReads = app.vendorProducts.productsCallCount;

        await tapVisible(tester, find.text(VendorProductCopy.save));

        expect(app.vendorProducts.detailCallCount, greaterThan(detailReads));
        expect(app.vendorProducts.productsCallCount, greaterThan(listReads));
      },
    );

    testWidgets('the assigned-Retailer section is not re-read', (
      WidgetTester tester,
    ) async {
      // An edit touches no assignment row, so a second companion read would spend a
      // call to learn nothing.
      final PumpedApp app = await onEditForm(tester);
      final int assignmentReads = app.vendorProducts.assignmentsCallCount;

      await tapVisible(tester, find.text(VendorProductCopy.save));

      expect(app.vendorProducts.assignmentsCallCount, assignmentReads);
      // And every row is still on screen, unchanged.
      expect(find.text('Northwind Retail'), findsOneWidget);
      expect(find.text('Harbour Provisions'), findsOneWidget);
      expect(find.text('Old Town Grocers'), findsOneWidget);
    });

    testWidgets('a double tap saves once', (WidgetTester tester) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository()..manualUpdate = true;
      await onEditForm(tester, products: repository);

      final Finder save = find.widgetWithText(SrButton, VendorProductCopy.save);
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pump();
      expect(repository.pendingUpdateCount, 1);

      await tester.tap(
        find.widgetWithText(SrButton, VendorProductCopy.saving),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(repository.pendingUpdateCount, 1);

      repository.completeUpdate();
      await tester.pumpAndSettle();
      expect(repository.submittedEdits.length, 1);
    });

    testWidgets('progress is shown while saving', (WidgetTester tester) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository()..manualUpdate = true;
      await onEditForm(tester, products: repository);

      await tester.ensureVisible(
        find.widgetWithText(SrButton, VendorProductCopy.save),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SrButton, VendorProductCopy.save));
      await tester.pump();

      expect(find.text(VendorProductCopy.saving), findsOneWidget);

      repository.completeUpdate();
      await tester.pumpAndSettle();
    });
  });

  group('edit refusals', () {
    testWidgets('a duplicate barcode is reported under its field', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository()
            ..updateResult = const VendorProductWriteFailure<void>(
              DuplicateFailure(field: 'barcode'),
            );
      await onEditForm(tester, products: repository);
      await enterField(tester, VendorProductCopy.barcodeLabel, '5012345678917');

      await tapVisible(tester, find.text(VendorProductCopy.save));

      expect(
        find.text('A product with this barcode already exists.'),
        findsOneWidget,
      );
      // Still on the form, with the typed values intact.
      expect(find.byType(VendorProductEditPage), findsOneWidget);
    });

    testWidgets('a denial is one safe message', (WidgetTester tester) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository()
            ..updateResult = const VendorProductWriteFailure<void>(
              DeniedFailure(),
            );
      await onEditForm(tester, products: repository);

      await tapVisible(tester, find.text(VendorProductCopy.save));

      expect(find.text(VendorProductCopy.writeDeniedTitle), findsOneWidget);
      expect(find.byType(VendorProductEditPage), findsOneWidget);
      for (final String forbidden in <String>['PRODUCTS_MANAGE', '42501']) {
        expect(find.textContaining(forbidden), findsNothing);
      }
    });

    testWidgets('a transport failure keeps the form and retries cleanly', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository()
            ..updateResult = const VendorProductWriteFailure<void>(
              UnavailableFailure(),
            );
      await onEditForm(tester, products: repository);
      await enterField(tester, VendorProductCopy.nameLabel, 'Renamed Blend');

      await tapVisible(tester, find.text(VendorProductCopy.save));
      expect(
        find.text(VendorProductCopy.writeUnavailableTitle),
        findsOneWidget,
      );

      repository.updateResult = null;
      await tapVisible(tester, find.text(VendorProductCopy.save));
      expect(find.byType(VendorProductDetailPage), findsOneWidget);
    });

    testWidgets('no refusal leaves the form', (WidgetTester tester) async {
      for (final Failure failure in <Failure>[
        const DeniedFailure(),
        const UnavailableFailure(),
        const InvalidFailure(),
      ]) {
        final FakeVendorProductRepository repository =
            FakeVendorProductRepository()
              ..updateResult = VendorProductWriteFailure<void>(failure);
        await onEditForm(tester, products: repository);
        await tapVisible(tester, find.text(VendorProductCopy.save));

        expect(
          currentLocation(tester),
          VendorNavigation.productEditPath(espressoProductUuid),
        );
      }
    });
  });

  group('a malformed product id in the edit route', () {
    testWidgets('it reaches one safe state, with no form', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);
      await goTo(tester, '${VendorNavigation.products}/not-a-uuid/edit');

      expect(find.text(VendorProductCopy.detailNotFoundTitle), findsOneWidget);
      // No form, therefore no reachable write.
      expect(find.byType(SrTextField), findsNothing);
      expect(
        find.widgetWithText(SrButton, VendorProductCopy.save),
        findsNothing,
      );
    });

    testWidgets('an unknown but well-formed id reaches the same state', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);
      await goTo(tester, VendorNavigation.productEditPath(unknownProductUuid));

      expect(find.text(VendorProductCopy.detailNotFoundTitle), findsOneWidget);
      // Never worded as somebody else's product.
      for (final String forbidden in <String>[
        'another Vendor',
        'belongs to',
        'does not exist',
      ]) {
        expect(find.textContaining(forbidden), findsNothing);
      }
    });

    testWidgets('no write is attempted for either', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onCatalogue(tester);

      await goTo(tester, '${VendorNavigation.products}/not-a-uuid/edit');
      await goTo(tester, VendorNavigation.productEditPath(unknownProductUuid));

      expect(app.vendorProducts.submittedEdits, isEmpty);
    });

    testWidgets('it offers a way back to the catalogue', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);
      await goTo(tester, '${VendorNavigation.products}/not-a-uuid/edit');

      await tapVisible(tester, find.text(VendorProductCopy.backToList).last);
      expect(find.byType(VendorProductsPage), findsOneWidget);
    });
  });

  group('the status action', () {
    testWidgets('an ACTIVE product offers Deactivate only', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      expect(
        find.widgetWithText(SrButton, VendorProductCopy.deactivate),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(SrButton, VendorProductCopy.activate),
        findsNothing,
      );
      expect(
        find.text(VendorProductCopy.statusSectionActiveDescription),
        findsOneWidget,
      );
    });

    testWidgets('an INACTIVE product offers Activate only', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);
      await tapVisible(tester, find.text('Seasonal Roast 250g'));

      expect(
        find.widgetWithText(SrButton, VendorProductCopy.activate),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(SrButton, VendorProductCopy.deactivate),
        findsNothing,
      );
      expect(
        find.text(VendorProductCopy.statusSectionInactiveDescription),
        findsOneWidget,
      );
    });

    testWidgets('it is visually separate from Edit', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      // Its own section with its own heading, rather than a control beside Edit.
      expect(find.text(VendorProductCopy.statusSectionTitle), findsOneWidget);
      expect(
        semanticsContaining(VendorProductCopy.deactivateSemantics),
        findsAtLeastNWidgets(1),
      );
    });

    testWidgets('a confirmation is required, and Cancel calls nothing', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onEspresso(tester);

      await tapVisible(tester, find.text(VendorProductCopy.deactivate));

      expect(
        find.text(VendorProductCopy.deactivateConfirmTitle),
        findsOneWidget,
      );
      expect(
        find.text(VendorProductCopy.deactivateConfirmBody),
        findsOneWidget,
      );

      await tapVisible(tester, find.text(VendorProductCopy.cancel));

      expect(app.vendorProducts.submittedStatusChanges, isEmpty);
      // And the status is untouched.
      expect(find.text('Status: Active'), findsAtLeastNWidgets(1));
    });

    testWidgets('the deactivation confirmation tells the truth', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);
      await tapVisible(tester, find.text(VendorProductCopy.deactivate));

      final String body = VendorProductCopy.deactivateConfirmBody;
      // The four claims the backend proves.
      expect(body, contains('nothing is deleted'));
      expect(body, contains('history'));
      expect(body, contains('existing Retailer assignments are kept'));
      expect(body, contains('activate it again'));
      // And nothing about receipts, which the backend audit does not prove.
      expect(body.contains('receipt'), isFalse);
      expect(body.contains('Receipt'), isFalse);
    });

    testWidgets('a confirmed deactivation sends INACTIVE', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onEspresso(tester);

      await tapVisible(tester, find.text(VendorProductCopy.deactivate));
      await confirm(tester, VendorProductCopy.deactivate);

      expect(app.vendorProducts.submittedStatusChanges.length, 1);
      expect(
        app.vendorProducts.submittedStatusChanges.single.change,
        VendorProductStatusChange.deactivate,
      );
      expect(
        app.vendorProducts.submittedStatusChanges.single.productId,
        espressoProductUuid,
      );
    });

    testWidgets('a confirmed activation sends ACTIVE', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onCatalogue(tester);
      await tapVisible(tester, find.text('Seasonal Roast 250g'));

      await tapVisible(tester, find.text(VendorProductCopy.activate));
      await confirm(tester, VendorProductCopy.activate);

      expect(
        app.vendorProducts.submittedStatusChanges.single.change,
        VendorProductStatusChange.activate,
      );
    });

    testWidgets('the visible status changes only from the re-read row', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository();
      await onEspresso(tester, products: repository);

      // What the backend will report once the product is deactivated.
      repository.knownDetails =
          Map<String, VendorProductDetail>.of(repository.knownDetails)
            ..[espressoProductUuid] = VendorProductDetail(
              productId: espressoProductUuid,
              productCode: 'ESP-1000',
              barcode: '5012345678900',
              productName: 'Espresso Blend 1kg',
              brand: 'Harvest Roasters',
              description: 'A dark roast blend for espresso machines.',
              status: VendorProductStatus.inactive,
              assignmentCount: 3,
              activeAssignmentCount: 2,
              createdAt: espressoCreatedAt,
              updatedAt: espressoUpdatedAt,
            );

      await tapVisible(tester, find.text(VendorProductCopy.deactivate));
      await confirm(tester, VendorProductCopy.deactivate);

      expect(find.text('Status: Inactive'), findsAtLeastNWidgets(1));
      expect(find.text(VendorProductCopy.statusChangedTitle), findsOneWidget);
      // And now the opposite action is offered.
      expect(
        find.widgetWithText(SrButton, VendorProductCopy.activate),
        findsOneWidget,
      );
    });

    testWidgets('the catalogue is refreshed', (WidgetTester tester) async {
      final PumpedApp app = await onEspresso(tester);
      final int before = app.vendorProducts.productsCallCount;

      await tapVisible(tester, find.text(VendorProductCopy.deactivate));
      await confirm(tester, VendorProductCopy.deactivate);

      expect(app.vendorProducts.productsCallCount, greaterThan(before));
    });

    testWidgets('assignment rows are not re-read and not changed', (
      WidgetTester tester,
    ) async {
      // set_vendor_product_status does not cascade — not even an assignment row's
      // `updated_at` — so nothing here re-reads, recounts or hides one.
      final PumpedApp app = await onEspresso(tester);
      final int assignmentReads = app.vendorProducts.assignmentsCallCount;

      await tapVisible(tester, find.text(VendorProductCopy.deactivate));
      await confirm(tester, VendorProductCopy.deactivate);

      expect(app.vendorProducts.assignmentsCallCount, assignmentReads);
      expect(find.text('Northwind Retail'), findsOneWidget);
      expect(find.text('Harbour Provisions'), findsOneWidget);
      expect(find.text('Old Town Grocers'), findsOneWidget);
      expect(
        find.textContaining('3 Retailer assignments'),
        findsAtLeastNWidgets(1),
      );
    });

    testWidgets('a repeated confirmation sends one request', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository()..manualStatus = true;
      await onEspresso(tester, products: repository);

      await tapVisible(tester, find.text(VendorProductCopy.deactivate));
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(
            TextButton,
            VendorProductCopy.deactivate,
          ),
        ),
      );
      await tester.pump();
      expect(repository.pendingStatusCount, 1);

      // The action is disabled while the call is in flight, and now carries its
      // progress label.
      await tester.tap(
        find.widgetWithText(SrButton, VendorProductCopy.deactivating),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(repository.pendingStatusCount, 1);

      repository.completeStatus();
      await tester.pumpAndSettle();
      expect(repository.submittedStatusChanges.length, 1);
    });

    testWidgets('progress is shown while the detail stays visible', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository()..manualStatus = true;
      await onEspresso(tester, products: repository);

      await tapVisible(tester, find.text(VendorProductCopy.deactivate));
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(
            TextButton,
            VendorProductCopy.deactivate,
          ),
        ),
      );
      await tester.pump();

      expect(find.text(VendorProductCopy.deactivating), findsOneWidget);
      // Every field is still legible.
      expect(find.text('ESP-1000'), findsOneWidget);
      expect(find.text('Espresso Blend 1kg'), findsAtLeastNWidgets(1));

      repository.completeStatus();
      await tester.pumpAndSettle();
    });

    testWidgets('a failure preserves the previous status', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository()
            ..statusResult = const VendorProductWriteFailure<void>(
              UnavailableFailure(),
            );
      await onEspresso(tester, products: repository);

      await tapVisible(tester, find.text(VendorProductCopy.deactivate));
      await confirm(tester, VendorProductCopy.deactivate);

      expect(find.text(VendorProductCopy.statusFailedTitle), findsOneWidget);
      // Nothing flipped.
      expect(find.text('Status: Active'), findsAtLeastNWidgets(1));
      expect(
        find.widgetWithText(SrButton, VendorProductCopy.deactivate),
        findsOneWidget,
      );
      expect(find.text(VendorProductCopy.statusChangedTitle), findsNothing);
    });

    testWidgets('a denial is safe and names no permission', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository()
            ..statusResult = const VendorProductWriteFailure<void>(
              DeniedFailure(),
            );
      await onEspresso(tester, products: repository);

      await tapVisible(tester, find.text(VendorProductCopy.deactivate));
      await confirm(tester, VendorProductCopy.deactivate);

      expect(find.text(VendorProductCopy.writeDeniedTitle), findsOneWidget);
      for (final String forbidden in <String>[
        'PRODUCTS_MANAGE',
        '42501',
        'insufficient_privilege',
      ]) {
        expect(find.textContaining(forbidden), findsNothing);
      }
    });

    testWidgets('there is no Delete action beside it', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      for (final String forbidden in <String>[
        'Delete',
        'Delete product',
        'Remove product',
        'Archive',
      ]) {
        expect(find.widgetWithText(SrButton, forbidden), findsNothing);
        expect(find.widgetWithText(TextButton, forbidden), findsNothing);
      }
    });
  });

  group('a write that landed and a read that did not', () {
    testWidgets('the save is acknowledged and the staleness admitted', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository();
      await onEditForm(tester, products: repository);

      // The write succeeds; the follow-up canonical read does not.
      repository.detailResult = unavailableProductRead();
      await tapVisible(tester, find.text(VendorProductCopy.save));

      // Never "the save failed".
      expect(find.text(VendorProductCopy.updatedTitle), findsOneWidget);
      expect(find.text(VendorProductCopy.staleAfterWriteTitle), findsOneWidget);
      expect(find.text(VendorProductCopy.writeUnavailableTitle), findsNothing);
      expect(find.text(VendorProductCopy.statusFailedTitle), findsNothing);
    });

    testWidgets('the product already on screen is kept', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository();
      await onEditForm(tester, products: repository);

      repository.detailResult = unavailableProductRead();
      await tapVisible(tester, find.text(VendorProductCopy.save));

      expect(find.text('ESP-1000'), findsOneWidget);
      expect(find.text('Espresso Blend 1kg'), findsAtLeastNWidgets(1));
      expect(find.text('Northwind Retail'), findsOneWidget);
    });

    testWidgets('a Reload is offered, and it works', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository();
      await onEditForm(tester, products: repository);

      repository.detailResult = unavailableProductRead();
      await tapVisible(tester, find.text(VendorProductCopy.save));
      expect(
        find.widgetWithText(SrButton, VendorProductCopy.reload),
        findsOneWidget,
      );
      expect(
        semanticsContaining(VendorProductCopy.reloadSemantics),
        findsAtLeastNWidgets(1),
      );

      repository.detailResult = null;
      await tapVisible(tester, find.text(VendorProductCopy.reload));

      expect(find.text(VendorProductCopy.staleAfterWriteTitle), findsNothing);
      // The acknowledgement stays, because the change did happen.
      expect(find.text(VendorProductCopy.updatedTitle), findsOneWidget);
    });

    testWidgets('the same holds after a status change', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository();
      await onEspresso(tester, products: repository);

      repository.detailResult = unavailableProductRead();
      await tapVisible(tester, find.text(VendorProductCopy.deactivate));
      await confirm(tester, VendorProductCopy.deactivate);

      expect(find.text(VendorProductCopy.statusChangedTitle), findsOneWidget);
      expect(find.text(VendorProductCopy.staleAfterWriteTitle), findsOneWidget);
      expect(find.text(VendorProductCopy.statusFailedTitle), findsNothing);
      // The previous status is still shown rather than an optimistic guess.
      expect(find.text('Status: Active'), findsAtLeastNWidgets(1));
    });

    testWidgets('an unconfirmed void write says so without claiming a save', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository()
            ..updateResult = const VendorProductWriteUnconfirmed<void>();
      await onEditForm(tester, products: repository);

      await tapVisible(tester, find.text(VendorProductCopy.save));

      expect(
        find.text(VendorProductCopy.unconfirmedWriteTitle),
        findsOneWidget,
      );
      expect(find.text(VendorProductCopy.writeUnavailableTitle), findsNothing);
      // And the canonical values are on screen.
      expect(find.text('ESP-1000'), findsOneWidget);
    });
  });

  group('session isolation', () {
    testWidgets('signing out clears a half-typed create form', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onCreateForm(tester);
      await fillCreateForm(tester);
      expect(find.byType(VendorProductCreatePage), findsOneWidget);

      app.auth.emitSignedOut();
      await tester.pumpAndSettle();

      expect(find.byType(VendorProductCreatePage), findsNothing);
      expect(find.text('FLAT-WHITE-500'), findsNothing);
      expect(find.text('Flat White Blend 500g'), findsNothing);
    });

    testWidgets('signing out clears a seeded edit form', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onEditForm(tester);
      expect(find.text('ESP-1000'), findsOneWidget);

      app.auth.emitSignedOut();
      await tester.pumpAndSettle();

      expect(find.byType(VendorProductEditPage), findsNothing);
      expect(find.text('ESP-1000'), findsNothing);
    });

    testWidgets('a new Vendor sees no acknowledgement from the previous one', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository();
      final PumpedApp app = await onEspresso(tester, products: repository);

      await tapVisible(tester, find.text(VendorProductCopy.deactivate));
      await confirm(tester, VendorProductCopy.deactivate);
      expect(find.text(VendorProductCopy.statusChangedTitle), findsOneWidget);

      app.auth.emitSignedOut();
      await tester.pumpAndSettle();

      expect(find.text(VendorProductCopy.statusChangedTitle), findsNothing);
    });

    testWidgets('a stale create answer never navigates the new session', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository repository =
          FakeVendorProductRepository()..manualCreate = true;
      final PumpedApp app = await onCreateForm(tester, products: repository);
      await fillCreateForm(tester);

      await tester.ensureVisible(
        find.widgetWithText(SrButton, VendorProductCopy.createSubmit),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(SrButton, VendorProductCopy.createSubmit),
      );
      await tester.pump();
      expect(repository.pendingCreateCount, 1);

      // The signed-in person changes while the create is in flight.
      app.auth.emitSignedOut();
      await tester.pumpAndSettle();

      repository.completeCreate();
      await tester.pumpAndSettle();

      // The previous Vendor's product was never opened under the new session.
      expect(find.byType(VendorProductDetailPage), findsNothing);
      expect(currentLocation(tester), isNot(contains(createdProductUuid)));
    });
  });

  group('responsive, themed and accessible', () {
    for (final Size surface in <Size>[
      smallPhoneSurface,
      phoneSurface,
      tabletSurface,
      desktopSurface,
    ]) {
      testWidgets('the create form does not overflow at ${surface.width}', (
        WidgetTester tester,
      ) async {
        await onCreateForm(tester, surface: surface);
        await fillCreateForm(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the edit form does not overflow at ${surface.width}', (
        WidgetTester tester,
      ) async {
        await onEditForm(tester, surface: surface);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the status section does not overflow at ${surface.width}', (
        WidgetTester tester,
      ) async {
        await onEspresso(tester, surface: surface);
        await tapVisible(tester, find.text(VendorProductCopy.deactivate));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the form is capped so it does not stretch on a desktop', (
      WidgetTester tester,
    ) async {
      await onCreateForm(tester, surface: desktopSurface);

      final SrPageBody body = tester.widget<SrPageBody>(
        find.byType(SrPageBody),
      );
      expect(body.maxWidth, lessThan(desktopSurface.width));
    });

    testWidgets('the confirmation dialog is readable under large text', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester, surface: smallPhoneSurface);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();

      await tapVisible(tester, find.text(VendorProductCopy.deactivate));

      expect(
        find.text(VendorProductCopy.deactivateConfirmTitle),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    for (final ThemeMode mode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
      testWidgets('the create form renders in $mode', (
        WidgetTester tester,
      ) async {
        await pumpApp(
          tester,
          initialUser: testUser,
          portalResult: resolvedResult(PortalKind.vendorSuperAdmin),
          themeMode: mode,
        );
        await goTo(tester, VendorNavigation.productCreate);

        expect(find.byType(VendorProductCreatePage), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the edit form renders in $mode', (
        WidgetTester tester,
      ) async {
        await pumpApp(
          tester,
          initialUser: testUser,
          portalResult: resolvedResult(PortalKind.vendorSuperAdmin),
          themeMode: mode,
        );
        await goTo(
          tester,
          VendorNavigation.productEditPath(espressoProductUuid),
        );

        expect(find.byType(VendorProductEditPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the page headings are marked as headers', (
      WidgetTester tester,
    ) async {
      await onCreateForm(tester);

      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is Semantics && (widget.properties.header ?? false),
        ),
        findsAtLeastNWidgets(1),
      );
    });

    testWidgets('a validation message is not signalled by colour alone', (
      WidgetTester tester,
    ) async {
      await onCreateForm(tester);
      await tapVisible(tester, find.text(VendorProductCopy.createSubmit));

      // The message itself is text, beneath the control it describes.
      expect(find.text('Enter a product code.'), findsOneWidget);
    });
  });
}
