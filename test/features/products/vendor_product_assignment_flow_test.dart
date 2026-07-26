import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sale_reward/app/navigation/role_destination.dart';
import 'package:sale_reward/app/shells/vendor/vendor_navigation.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/core/widgets/widgets.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_assigned_retailer.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_detail.dart';
import 'package:sale_reward/features/products/domain/repositories/vendor_product_write_result.dart';
import 'package:sale_reward/features/products/presentation/vendor/widgets/vendor_product_assignment_tile.dart';
import 'package:sale_reward/features/products/presentation/vendor/widgets/vendor_product_copy.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_summary.dart';
import 'package:sale_reward/features/retailers/domain/repositories/vendor_retailer_result.dart';

import '../../support/fakes.dart';
import '../../support/pump_app.dart';
import '../../support/vendor_product_fakes.dart';
import '../../support/vendor_retailer_fakes.dart';

/// Drives Vendor Product **assignment management** through the real application:
/// real router, real shell, real cubits, over fakes that never touch Supabase.
///
/// The espresso product is pointed at a five-row history that covers every state
/// the surface has to get right in one screen:
///
/// | Retailer | assignment | Retailer / relationship | control |
/// | --- | --- | --- | --- |
/// | Harbour Provisions | active | suspended / suspended | Withdraw |
/// | Northwind Retail | active | active / active | Withdraw |
/// | Old Town Grocers | inactive | deactivated / **no row** | none |
/// | Riverside Foods | inactive | active / active | Reactivate |
/// | Summit Stores | inactive | active / suspended | none |
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

/// Confirms the open dialog by pressing its [label] action.
///
/// Scoped to the [AlertDialog]: the picker is a plain [Dialog] whose rows carry
/// buttons with the same words, so an unscoped finder would match a row rather
/// than the confirmation — and tapping the wrong one would reopen the dialog.
Future<void> confirm(WidgetTester tester, String label) async {
  final Finder action = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.widgetWithText(TextButton, label),
  );
  expect(action, findsOneWidget);
  await tester.tap(action);
  await tester.pumpAndSettle();
}

/// Confirms without settling, for a write that is held in flight.
///
/// `pumpAndSettle` cannot be used once a button is spinning: the progress
/// indicator animates indefinitely by design, so settling would time out rather
/// than converge. Three frames is enough for the dialog to close and the
/// in-flight state to be painted.
Future<void> confirmWithoutSettling(WidgetTester tester, String label) async {
  final Finder action = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.widgetWithText(TextButton, label),
  );
  expect(action, findsOneWidget);
  await tester.tap(action);
  for (int i = 0; i < 3; i++) {
    await tester.pump();
  }
}

Future<void> dismiss(WidgetTester tester, String label) async {
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

/// The action control on the assignment row for [retailerName].
Finder rowAction(String retailerName, String label) => find.descendant(
  of: find.ancestor(
    of: find.text(retailerName),
    matching: find.byType(VendorProductAssignmentTile),
  ),
  matching: find.widgetWithText(SrButton, label),
);

void main() {
  FakeVendorRetailerRepository directory() {
    final FakeVendorRetailerRepository retailers =
        FakeVendorRetailerRepository();
    retailers.retailersResult =
        VendorRetailerReadSuccess<List<VendorRetailerSummary>>(
          assignmentDirectory,
        );
    return retailers;
  }

  Future<PumpedApp> onEspresso(
    WidgetTester tester, {
    FakeVendorProductRepository? products,
    FakeVendorRetailerRepository? retailers,
    bool productIsActive = true,
    Size surface = phoneSurface,
  }) async {
    final FakeVendorProductRepository productRepository =
        products ?? FakeVendorProductRepository();
    useAssignmentFixtures(productRepository, productIsActive: productIsActive);

    final PumpedApp app = await pumpAppInRole(
      tester,
      PortalKind.vendorSuperAdmin,
      surface: surface,
      vendorProducts: productRepository,
      retailers: retailers ?? directory(),
    );
    await goTo(tester, VendorNavigation.productDetailPath(espressoProductUuid));
    return app;
  }

  /// Opens the Retailer picker.
  Future<void> openPicker(WidgetTester tester) async {
    await tapVisible(
      tester,
      find.widgetWithText(SrButton, VendorProductCopy.assignRetailer),
    );
  }

  group('what the assignment section offers', () {
    testWidgets('a Vendor Super Admin gets the Assign Retailer control', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      expect(
        find.widgetWithText(SrButton, VendorProductCopy.assignRetailer),
        findsOneWidget,
      );
    });

    testWidgets('every historical row is still rendered', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      expect(find.byType(VendorProductAssignmentTile), findsNWidgets(5));
      for (final String name in <String>[
        'Harbour Provisions',
        'Northwind Retail',
        'Old Town Grocers',
        'Riverside Foods',
        'Summit Stores',
      ]) {
        expect(find.text(name), findsOneWidget);
      }
    });

    testWidgets('an active assignment offers Withdraw', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      expect(
        rowAction('Northwind Retail', VendorProductCopy.withdrawAssignment),
        findsOneWidget,
      );
      expect(
        rowAction('Harbour Provisions', VendorProductCopy.withdrawAssignment),
        findsOneWidget,
      );
    });

    testWidgets('a suspended Retailer can still have its assignment ended', (
      WidgetTester tester,
    ) async {
      // The deployed withdrawal gate requires no status to be active, and this
      // is exactly the case it exists for.
      await onEspresso(tester);

      expect(
        rowAction('Harbour Provisions', VendorProductCopy.withdrawAssignment),
        findsOneWidget,
      );
    });

    testWidgets(
      'an inactive assignment to an eligible Retailer offers Reactivate',
      (WidgetTester tester) async {
        await onEspresso(tester);

        expect(
          rowAction('Riverside Foods', VendorProductCopy.reactivateAssignment),
          findsOneWidget,
        );
      },
    );

    testWidgets('an ineligible inactive assignment offers no control', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      expect(
        rowAction('Summit Stores', VendorProductCopy.reactivateAssignment),
        findsNothing,
      );
      expect(
        rowAction('Summit Stores', VendorProductCopy.withdrawAssignment),
        findsNothing,
      );
      // Not a disabled button: a sentence, so a reader learns why.
      expect(
        find.text(VendorProductCopy.reactivateUnavailable),
        findsOneWidget,
      );
    });

    testWidgets('a missing relationship gets its own explanation', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      expect(
        find.text(VendorProductCopy.reactivateUnavailableNoRelationship),
        findsOneWidget,
      );
      expect(
        rowAction('Old Town Grocers', VendorProductCopy.reactivateAssignment),
        findsNothing,
      );
    });

    testWidgets('there is no delete, remove or bulk control anywhere', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      for (final String forbidden in <String>[
        'Delete assignment',
        'Remove assignment',
        'Unassign',
        'Assign all',
        'Select all',
      ]) {
        expect(
          find.widgetWithText(SrButton, forbidden),
          findsNothing,
          reason: 'a "$forbidden" control is on the assignment surface',
        );
      }
      expect(find.byType(Checkbox), findsNothing);
    });
  });

  group('an inactive product', () {
    testWidgets('offers no Assign control, and says why once', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester, productIsActive: false);

      expect(
        find.widgetWithText(SrButton, VendorProductCopy.assignRetailer),
        findsNothing,
      );
      expect(
        find.text(VendorProductCopy.assignUnavailableInactive),
        findsOneWidget,
      );
    });

    testWidgets('offers no Reactivate either', (WidgetTester tester) async {
      await onEspresso(tester, productIsActive: false);

      expect(
        rowAction('Riverside Foods', VendorProductCopy.reactivateAssignment),
        findsNothing,
      );
    });

    testWidgets('still allows an active assignment to be withdrawn', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester, productIsActive: false);

      expect(
        rowAction('Northwind Retail', VendorProductCopy.withdrawAssignment),
        findsOneWidget,
      );
    });

    testWidgets('keeps every assignment row and both counts', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester, productIsActive: false);

      expect(find.byType(VendorProductAssignmentTile), findsNWidgets(5));
      expect(find.textContaining('5 Retailer assignments'), findsWidgets);
    });
  });

  group('withdrawing an assignment', () {
    testWidgets('it asks first, and cancelling sends nothing', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository products =
          FakeVendorProductRepository();
      await onEspresso(tester, products: products);

      await tapVisible(
        tester,
        rowAction('Northwind Retail', VendorProductCopy.withdrawAssignment),
      );
      expect(find.byType(AlertDialog), findsOneWidget);
      await dismiss(tester, VendorProductCopy.cancel);

      expect(products.submittedAssignments, isEmpty);
    });

    testWidgets('the confirmation names the Retailer', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      await tapVisible(
        tester,
        rowAction('Northwind Retail', VendorProductCopy.withdrawAssignment),
      );

      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('Northwind Retail'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the confirmation promises history, not deletion', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      await tapVisible(
        tester,
        rowAction('Northwind Retail', VendorProductCopy.withdrawAssignment),
      );

      final String body = tester
          .widget<Text>(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.textContaining('Nothing is deleted.'),
            ),
          )
          .data!;

      expect(body, contains('becomes inactive'));
      expect(body, contains('Nothing is deleted.'));
      expect(body, contains('stays in this product’s history'));
      expect(body, contains('keeps the date it was assigned'));
      expect(body, contains('still counts'));
      expect(body, contains('product stays in your catalogue'));
      expect(body, contains('relationship with the Retailer is not affected'));
      for (final String forbidden in <String>[
        'permanently',
        'cannot be undone',
        'erase',
        'remove',
      ]) {
        expect(
          body.toLowerCase().contains(forbidden),
          isFalse,
          reason: 'the withdrawal confirmation says "$forbidden"',
        );
      }
    });

    testWidgets('confirming sends the Retailer organization id, and no more', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository products =
          FakeVendorProductRepository();
      await onEspresso(tester, products: products);

      await tapVisible(
        tester,
        rowAction('Northwind Retail', VendorProductCopy.withdrawAssignment),
      );
      await confirm(tester, VendorProductCopy.withdrawAssignment);

      expect(products.submittedAssignments.length, 1);
      expect(products.submittedAssignments.single.isWithdrawal, isTrue);
      expect(
        products.submittedAssignments.single.request.retailerOrganizationId,
        northwindOrgId,
      );
      expect(
        products.submittedAssignments.single.request.props,
        <Object?>[espressoProductUuid, northwindOrgId],
        reason: 'the payload is two addresses and nothing else',
      );
    });

    testWidgets('no relationship id is ever sent', (WidgetTester tester) async {
      final FakeVendorProductRepository products =
          FakeVendorProductRepository();
      await onEspresso(tester, products: products);

      await tapVisible(
        tester,
        rowAction('Northwind Retail', VendorProductCopy.withdrawAssignment),
      );
      await confirm(tester, VendorProductCopy.withdrawAssignment);

      expect(
        products.submittedAssignments.single.request.props.contains(
          northwindRelationshipId,
        ),
        isFalse,
      );
    });

    testWidgets('it acknowledges the withdrawal without saying "deleted"', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      await tapVisible(
        tester,
        rowAction('Northwind Retail', VendorProductCopy.withdrawAssignment),
      );
      await confirm(tester, VendorProductCopy.withdrawAssignment);

      expect(find.text(VendorProductCopy.withdrawnTitle), findsOneWidget);
      expect(find.textContaining('nothing was deleted'), findsOneWidget);
    });

    testWidgets('a double confirmation cannot write twice', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository products = FakeVendorProductRepository()
        ..manualAssignmentWrites = true;
      await onEspresso(tester, products: products);

      await tapVisible(
        tester,
        rowAction('Northwind Retail', VendorProductCopy.withdrawAssignment),
      );
      await confirmWithoutSettling(
        tester,
        VendorProductCopy.withdrawAssignment,
      );

      // The control is disabled while the write is in flight, and the cubit
      // refuses a second call regardless. Its visible word has changed to the
      // progress label, which is how the row says which pairing is being
      // written without disabling every other one.
      final SrButton button = tester.widget<SrButton>(
        rowAction('Northwind Retail', VendorProductCopy.withdrawing),
      );
      expect(button.onPressed, isNull);
      expect(button.loading, isTrue);
      expect(products.submittedAssignments.length, 1);

      products.completeAssignment();
      await tester.pumpAndSettle();
      expect(products.submittedAssignments.length, 1);
    });
  });

  group('reactivating an assignment', () {
    testWidgets('the confirmation states that the assigned date is reset', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      await tapVisible(
        tester,
        rowAction('Riverside Foods', VendorProductCopy.reactivateAssignment),
      );

      final String body = tester
          .widget<Text>(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.textContaining('becomes active again'),
            ),
          )
          .data!;

      expect(body, contains('reused rather than duplicated'));
      expect(body, contains('assigned date is reset'));
      expect(body, contains('when this assignment started'));
    });

    testWidgets(
      'confirming reaches the assign function, not the withdrawal one',
      (WidgetTester tester) async {
        final FakeVendorProductRepository products =
            FakeVendorProductRepository();
        await onEspresso(tester, products: products);

        await tapVisible(
          tester,
          rowAction('Riverside Foods', VendorProductCopy.reactivateAssignment),
        );
        await confirm(tester, VendorProductCopy.reactivateAssignment);

        expect(products.submittedAssignments.single.isWithdrawal, isFalse);
        expect(
          products.submittedAssignments.single.request.retailerOrganizationId,
          riversideOrgId,
        );
      },
    );

    testWidgets('its acknowledgement mentions the new activation time', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      await tapVisible(
        tester,
        rowAction('Riverside Foods', VendorProductCopy.reactivateAssignment),
      );
      await confirm(tester, VendorProductCopy.reactivateAssignment);

      expect(find.text(VendorProductCopy.reactivatedTitle), findsOneWidget);
      expect(find.textContaining('moment it was reactivated'), findsOneWidget);
    });
  });

  group('assigning a new Retailer', () {
    testWidgets('the picker lists every Retailer, with its own state', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester, surface: tabletSurface);
      await openPicker(tester);

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text(VendorProductCopy.assignSheetTitle), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text(VendorProductCopy.candidateAssignable),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text(VendorProductCopy.candidateAlreadyAssigned),
        ),
        findsWidgets,
      );
    });

    testWidgets('an already-assigned Retailer carries no control', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester, surface: tabletSurface);
      await openPicker(tester);

      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text(VendorProductCopy.candidateAlreadyAssigned),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.widgetWithText(
            SrButton,
            VendorProductCopy.candidateAssignAction,
          ),
        ),
        // Lakeside alone: Northwind and Harbour already hold the product,
        // Riverside is a reactivation rather than a fresh assignment, and Summit
        // and Old Town are not eligible.
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.widgetWithText(
            SrButton,
            VendorProductCopy.candidateReactivateAction,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('an inactive historical pairing is distinguishable', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester, surface: tabletSurface);
      await openPicker(tester);

      expect(
        find.text(VendorProductCopy.candidateReactivatable),
        findsOneWidget,
      );
      expect(
        find.text(VendorProductCopy.candidateRelationshipUnavailable),
        findsOneWidget,
      );
      expect(find.text(VendorProductCopy.candidateIneligible), findsOneWidget);
    });

    testWidgets('no internal identifier is displayed', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester, surface: tabletSurface);
      await openPicker(tester);

      for (final String id in <String>[
        lakesideOrgId,
        lakesideRelationshipId,
        espressoProductUuid,
      ]) {
        expect(find.textContaining(id), findsNothing);
      }
    });

    testWidgets('assigning sends the chosen Retailer organization id', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository products =
          FakeVendorProductRepository();
      await onEspresso(tester, products: products, surface: tabletSurface);
      await openPicker(tester);

      await tapVisible(
        tester,
        find
            .descendant(
              of: find.ancestor(
                of: find.text('Lakeside Market'),
                matching: find.byType(Padding),
              ),
              matching: find.widgetWithText(
                SrButton,
                VendorProductCopy.candidateAssignAction,
              ),
            )
            .first,
      );
      await confirm(tester, VendorProductCopy.assignConfirmAction);

      expect(products.submittedAssignments.length, 1);
      expect(products.submittedAssignments.single.isWithdrawal, isFalse);
      expect(
        products.submittedAssignments.single.request.retailerOrganizationId,
        lakesideOrgId,
      );
    });

    testWidgets('the picker closes and the product acknowledges the write', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester, surface: tabletSurface);
      await openPicker(tester);

      await tapVisible(
        tester,
        find
            .descendant(
              of: find.ancestor(
                of: find.text('Lakeside Market'),
                matching: find.byType(Padding),
              ),
              matching: find.widgetWithText(
                SrButton,
                VendorProductCopy.candidateAssignAction,
              ),
            )
            .first,
      );
      await confirm(tester, VendorProductCopy.assignConfirmAction);

      expect(find.byType(Dialog), findsNothing);
      expect(find.text(VendorProductCopy.assignedTitle), findsOneWidget);
    });

    testWidgets(
      'cancelling the confirmation writes nothing and keeps the list',
      (WidgetTester tester) async {
        final FakeVendorProductRepository products =
            FakeVendorProductRepository();
        await onEspresso(tester, products: products, surface: tabletSurface);
        await openPicker(tester);

        await tapVisible(
          tester,
          find
              .descendant(
                of: find.ancestor(
                  of: find.text('Lakeside Market'),
                  matching: find.byType(Padding),
                ),
                matching: find.widgetWithText(
                  SrButton,
                  VendorProductCopy.candidateAssignAction,
                ),
              )
              .first,
        );
        await dismiss(tester, VendorProductCopy.cancel);

        expect(products.submittedAssignments, isEmpty);
        expect(find.byType(Dialog), findsOneWidget);
      },
    );

    testWidgets('search narrows the picker locally', (
      WidgetTester tester,
    ) async {
      final FakeVendorRetailerRepository retailers = directory();
      await onEspresso(tester, retailers: retailers, surface: tabletSurface);
      await openPicker(tester);

      await tester.enterText(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(TextField),
        ),
        'lakeside',
      );
      await tester.pumpAndSettle();

      // Scoped to the dialog: the product's own history is still rendered
      // behind it, and it is deliberately not filtered by the picker's search.
      Finder inPicker(String name) =>
          find.descendant(of: find.byType(Dialog), matching: find.text(name));

      expect(inPicker('Lakeside Market'), findsOneWidget);
      expect(inPicker('Summit Stores'), findsNothing);
      expect(
        find.byType(VendorProductAssignmentTile),
        findsNWidgets(5),
        reason: 'the history below is never narrowed by the picker',
      );
      expect(
        retailers.retailersCallCount,
        1,
        reason: 'nothing typed is sent to the backend',
      );
    });

    testWidgets('a directory outage is not an empty Retailer list', (
      WidgetTester tester,
    ) async {
      final FakeVendorRetailerRepository retailers =
          FakeVendorRetailerRepository();
      retailers.retailersResult =
          const VendorRetailerReadFailure<List<VendorRetailerSummary>>(
            UnavailableFailure(),
          );
      await onEspresso(tester, retailers: retailers, surface: tabletSurface);
      await openPicker(tester);

      expect(
        find.text(VendorProductCopy.candidatesUnavailableTitle),
        findsOneWidget,
      );
      expect(find.text(VendorProductCopy.candidatesEmptyTitle), findsNothing);
    });

    testWidgets('reopening the picker re-reads eligibility', (
      WidgetTester tester,
    ) async {
      final FakeVendorRetailerRepository retailers = directory();
      await onEspresso(tester, retailers: retailers, surface: tabletSurface);

      await openPicker(tester);
      await dismiss2(tester);
      await openPicker(tester);

      expect(retailers.retailersCallCount, 2);
    });
  });

  group('after a successful write, the backend is re-read', () {
    testWidgets('both canonical reads and the catalogue are refreshed', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository products =
          FakeVendorProductRepository();
      await onEspresso(tester, products: products);

      final int detailBefore = products.detailCallCount;
      final int assignmentsBefore = products.assignmentsCallCount;
      final int listBefore = products.productsCallCount;

      await tapVisible(
        tester,
        rowAction('Northwind Retail', VendorProductCopy.withdrawAssignment),
      );
      await confirm(tester, VendorProductCopy.withdrawAssignment);

      expect(products.detailCallCount, detailBefore + 1);
      expect(products.assignmentsCallCount, assignmentsBefore + 1);
      expect(
        products.productsCallCount,
        listBefore + 1,
        reason: 'active_assignment_count moved on the catalogue too',
      );
    });

    testWidgets('the counts on screen are the backend\'s, not a local tally', (
      WidgetTester tester,
    ) async {
      // The fake does not simulate storage: the re-read returns the SAME five
      // rows and the SAME counts. A client that had decremented anything would
      // now disagree with the row it just read back.
      await onEspresso(tester);

      await tapVisible(
        tester,
        rowAction('Northwind Retail', VendorProductCopy.withdrawAssignment),
      );
      await confirm(tester, VendorProductCopy.withdrawAssignment);

      expect(find.byType(VendorProductAssignmentTile), findsNWidgets(5));
      expect(find.textContaining('5 Retailer assignments'), findsWidgets);
      expect(find.textContaining('2 currently active'), findsWidgets);
    });

    testWidgets('no inactive row is dropped by a write', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      await tapVisible(
        tester,
        rowAction('Riverside Foods', VendorProductCopy.reactivateAssignment),
      );
      await confirm(tester, VendorProductCopy.reactivateAssignment);

      expect(find.text('Old Town Grocers'), findsOneWidget);
      expect(find.text('Summit Stores'), findsOneWidget);
    });

    testWidgets('the product\'s own fields and status are untouched', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      await tapVisible(
        tester,
        rowAction('Northwind Retail', VendorProductCopy.withdrawAssignment),
      );
      await confirm(tester, VendorProductCopy.withdrawAssignment);

      expect(find.text('ESP-1000'), findsOneWidget);
      expect(find.text('5012345678900'), findsOneWidget);
      expect(find.text('Harvest Roasters'), findsWidgets);
      // Still active, and still offering deactivation rather than activation.
      expect(
        find.widgetWithText(SrButton, VendorProductCopy.deactivate),
        findsOneWidget,
      );
    });

    testWidgets('no product-record write is issued by an assignment', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository products =
          FakeVendorProductRepository();
      await onEspresso(tester, products: products);

      await tapVisible(
        tester,
        rowAction('Northwind Retail', VendorProductCopy.withdrawAssignment),
      );
      await confirm(tester, VendorProductCopy.withdrawAssignment);

      expect(products.submittedEdits, isEmpty);
      expect(products.submittedStatusChanges, isEmpty);
      expect(products.submittedDrafts, isEmpty);
    });
  });

  group('refusals are safe and specific', () {
    testWidgets('a denial names no permission and no Retailer state', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository products = FakeVendorProductRepository()
        ..withdrawResult = const VendorProductWriteFailure<void>(
          DeniedFailure(),
        );
      await onEspresso(tester, products: products);

      await tapVisible(
        tester,
        rowAction('Northwind Retail', VendorProductCopy.withdrawAssignment),
      );
      await confirm(tester, VendorProductCopy.withdrawAssignment);

      expect(
        find.text(VendorProductCopy.assignmentFailedTitle),
        findsOneWidget,
      );
      expect(
        find.text(VendorProductCopy.assignmentDeniedTitle),
        findsOneWidget,
      );
      for (final String forbidden in <String>[
        'PRODUCT_RETAILER_ASSIGN',
        'PRODUCTS_MANAGE',
        '42501',
        'vendor_product_retailer_assignments',
        'suspended',
      ]) {
        expect(
          find.textContaining(forbidden),
          findsNothing,
          reason: 'a refusal exposed "$forbidden"',
        );
      }
    });

    testWidgets('an ineligible product gets the one message that helps', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository products = FakeVendorProductRepository()
        ..assignResult = const VendorProductWriteFailure<void>(
          NotReadyFailure(),
        );
      await onEspresso(tester, products: products);

      await tapVisible(
        tester,
        rowAction('Riverside Foods', VendorProductCopy.reactivateAssignment),
      );
      await confirm(tester, VendorProductCopy.reactivateAssignment);

      expect(find.text(VendorProductCopy.assignNotReadyTitle), findsOneWidget);
    });

    testWidgets('a refusal leaves the history exactly as it was', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository products = FakeVendorProductRepository()
        ..withdrawResult = const VendorProductWriteFailure<void>(
          UnavailableFailure(),
        );
      await onEspresso(tester, products: products);
      final int detailBefore = products.detailCallCount;

      await tapVisible(
        tester,
        rowAction('Northwind Retail', VendorProductCopy.withdrawAssignment),
      );
      await confirm(tester, VendorProductCopy.withdrawAssignment);

      expect(find.byType(VendorProductAssignmentTile), findsNWidgets(5));
      expect(
        products.detailCallCount,
        detailBefore,
        reason: 'nothing was written, so nothing needs re-reading',
      );
      expect(
        rowAction('Northwind Retail', VendorProductCopy.withdrawAssignment),
        findsOneWidget,
        reason: 'the action is offered again',
      );
    });

    testWidgets('a session that ended is not worded as a denial', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository products = FakeVendorProductRepository()
        ..withdrawResult = const VendorProductWriteFailure<void>(
          UnauthenticatedFailure(),
        );
      await onEspresso(tester, products: products);

      await tapVisible(
        tester,
        rowAction('Northwind Retail', VendorProductCopy.withdrawAssignment),
      );
      await confirm(tester, VendorProductCopy.withdrawAssignment);

      expect(find.text(VendorProductCopy.writeSignedOutTitle), findsOneWidget);
    });
  });

  group('partial success', () {
    testWidgets('a write that landed is never reported as failed', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository products =
          FakeVendorProductRepository();
      await onEspresso(tester, products: products);
      // The write succeeds; the canonical detail re-read then does not.
      products.detailResult = unavailableProductRead<VendorProductDetail?>();

      await tapVisible(
        tester,
        rowAction('Northwind Retail', VendorProductCopy.withdrawAssignment),
      );
      await confirm(tester, VendorProductCopy.withdrawAssignment);

      expect(
        find.text(VendorProductCopy.staleAfterAssignmentTitle),
        findsOneWidget,
      );
      expect(
        find.text(VendorProductCopy.assignmentFailedTitle),
        findsNothing,
        reason: 'the mutation succeeded; only the picture of it is stale',
      );
    });

    testWidgets('the existing history stays on screen', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository products =
          FakeVendorProductRepository();
      await onEspresso(tester, products: products);
      products.assignmentsResult =
          unavailableProductRead<List<VendorProductAssignedRetailer>>();

      await tapVisible(
        tester,
        rowAction('Northwind Retail', VendorProductCopy.withdrawAssignment),
      );
      await confirm(tester, VendorProductCopy.withdrawAssignment);

      expect(
        find.text(VendorProductCopy.staleAfterAssignmentTitle),
        findsOneWidget,
      );
      expect(find.byType(VendorProductAssignmentTile), findsNWidgets(5));
    });

    testWidgets('it offers a Reload, and the Reload re-reads both', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository products =
          FakeVendorProductRepository();
      await onEspresso(tester, products: products);
      products.assignmentsResult =
          unavailableProductRead<List<VendorProductAssignedRetailer>>();

      await tapVisible(
        tester,
        rowAction('Northwind Retail', VendorProductCopy.withdrawAssignment),
      );
      await confirm(tester, VendorProductCopy.withdrawAssignment);

      products.assignmentsResult = null;
      final int detailBefore = products.detailCallCount;
      final int assignmentsBefore = products.assignmentsCallCount;
      final int writesBefore = products.submittedAssignments.length;

      await tapVisible(
        tester,
        find.widgetWithText(SrButton, VendorProductCopy.reload),
      );

      expect(products.detailCallCount, detailBefore + 1);
      expect(products.assignmentsCallCount, assignmentsBefore + 1);
      expect(
        products.submittedAssignments.length,
        writesBefore,
        reason: 'a reload is never a re-write',
      );
      expect(
        find.text(VendorProductCopy.staleAfterAssignmentTitle),
        findsNothing,
      );
    });

    testWidgets('an unconfirmed answer neither claims nor denies the change', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository products = FakeVendorProductRepository()
        ..withdrawResult = const VendorProductWriteUnconfirmed<void>();
      await onEspresso(tester, products: products);

      await tapVisible(
        tester,
        rowAction('Northwind Retail', VendorProductCopy.withdrawAssignment),
      );
      await confirm(tester, VendorProductCopy.withdrawAssignment);

      expect(
        find.text(VendorProductCopy.assignmentUnconfirmedTitle),
        findsOneWidget,
      );
      expect(find.text(VendorProductCopy.assignmentFailedTitle), findsNothing);
      expect(products.submittedAssignments.length, 1);
    });
  });

  group('navigation', () {
    testWidgets('assignment management stays on the product route', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);
      final String before = currentLocation(tester);

      await tapVisible(
        tester,
        rowAction('Northwind Retail', VendorProductCopy.withdrawAssignment),
      );
      await confirm(tester, VendorProductCopy.withdrawAssignment);

      expect(currentLocation(tester), before);
      expect(before, VendorNavigation.productDetailPath(espressoProductUuid));
    });

    testWidgets('there is no assignment route beneath the product', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      await goTo(
        tester,
        '${VendorNavigation.productDetailPath(espressoProductUuid)}/assignments',
      );

      // No such route is declared, so nothing renders an assignment surface of
      // its own: assignment management lives inside the product screen, and a
      // dedicated route would be a second place for it to exist.
      expect(find.byType(VendorProductAssignmentTile), findsNothing);
      expect(
        find.widgetWithText(SrButton, VendorProductCopy.assignRetailer),
        findsNothing,
      );
    });

    testWidgets('the Products destination stays selected', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester, surface: desktopSurface);

      final RoleNavigation model = VendorNavigation.model;
      final int productsIndex = model.destinations.indexWhere(
        (RoleDestination d) => d.path == VendorNavigation.products,
      );

      expect(model.indexForLocation(currentLocation(tester)), productsIndex);
    });
  });

  group('the other three roles', () {
    for (final PortalKind kind in <PortalKind>[
      PortalKind.retailerOwner,
      PortalKind.retailerManager,
      PortalKind.salesStaff,
    ]) {
      testWidgets('$kind cannot reach the assignment surface', (
        WidgetTester tester,
      ) async {
        final FakeVendorProductRepository products =
            FakeVendorProductRepository();
        useAssignmentFixtures(products);

        await pumpAppInRole(
          tester,
          kind,
          surface: tabletSurface,
          vendorProducts: products,
          retailers: directory(),
        );
        await goTo(
          tester,
          VendorNavigation.productDetailPath(espressoProductUuid),
        );

        expect(
          find.widgetWithText(SrButton, VendorProductCopy.assignRetailer),
          findsNothing,
        );
        expect(
          find.widgetWithText(SrButton, VendorProductCopy.withdrawAssignment),
          findsNothing,
        );
        expect(products.submittedAssignments, isEmpty);
      });
    }
  });

  group('accessibility', () {
    testWidgets('the assignment actions are spoken with their subject', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      expect(
        semanticsContaining(
          '${VendorProductCopy.withdrawSemantics} Northwind Retail.',
        ),
        findsOneWidget,
      );
      expect(
        semanticsContaining(
          '${VendorProductCopy.reactivateSemantics} Riverside Foods.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the Assign control is spoken as what it opens', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      expect(
        semanticsContaining(VendorProductCopy.assignRetailerSemantics),
        findsOneWidget,
      );
    });

    testWidgets('an unavailable reactivation is spoken as a full sentence', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester);

      expect(
        semanticsContaining(VendorProductCopy.reactivateUnavailable),
        findsWidgets,
      );
    });

    testWidgets('a picker row is spoken as name, state and history', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester, surface: tabletSurface);
      await openPicker(tester);

      expect(
        semanticsContaining(
          'Riverside Foods. ${VendorProductCopy.candidateReactivatable}',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the picker heading is marked as a header', (
      WidgetTester tester,
    ) async {
      await onEspresso(tester, surface: tabletSurface);
      await openPicker(tester);

      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is Semantics && (widget.properties.header ?? false),
        ),
        findsWidgets,
      );
    });

    testWidgets('the action controls are reachable as buttons', (
      WidgetTester tester,
    ) async {
      // They sit OUTSIDE the row's collapsed description, so a screen reader can
      // reach them and a keyboard can focus them.
      await onEspresso(tester);

      final Finder button = find.ancestor(
        of: rowAction('Northwind Retail', VendorProductCopy.withdrawAssignment),
        matching: find.byWidgetPredicate(
          (Widget widget) =>
              widget is Semantics && (widget.properties.button ?? false),
        ),
      );
      expect(button, findsWidgets);
    });
  });

  group('responsive and themed', () {
    for (final Size surface in <Size>[
      smallPhoneSurface,
      phoneSurface,
      tabletSurface,
      desktopSurface,
    ]) {
      testWidgets('the assignment section fits ${surface.width.toInt()}px', (
        WidgetTester tester,
      ) async {
        await onEspresso(tester, surface: surface);

        expect(tester.takeException(), isNull);
      });

      testWidgets('the picker fits ${surface.width.toInt()}px', (
        WidgetTester tester,
      ) async {
        await onEspresso(tester, surface: surface);
        await openPicker(tester);

        expect(tester.takeException(), isNull);
      });
    }

    for (final ThemeMode mode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
      testWidgets('the assignment section renders in $mode', (
        WidgetTester tester,
      ) async {
        final FakeVendorProductRepository products =
            FakeVendorProductRepository();
        useAssignmentFixtures(products);

        await pumpApp(
          tester,
          initialUser: testUser,
          portalResult: resolvedResult(PortalKind.vendorSuperAdmin),
          themeMode: mode,
          vendorProducts: products,
          retailers: directory(),
        );
        await goTo(
          tester,
          VendorNavigation.productDetailPath(espressoProductUuid),
        );

        expect(find.byType(VendorProductAssignmentTile), findsNWidgets(5));
        expect(tester.takeException(), isNull);
      });

      testWidgets('the picker renders in $mode', (WidgetTester tester) async {
        final FakeVendorProductRepository products =
            FakeVendorProductRepository();
        useAssignmentFixtures(products);

        await pumpApp(
          tester,
          initialUser: testUser,
          portalResult: resolvedResult(PortalKind.vendorSuperAdmin),
          themeMode: mode,
          surface: tabletSurface,
          vendorProducts: products,
          retailers: directory(),
        );
        await goTo(
          tester,
          VendorNavigation.productDetailPath(espressoProductUuid),
        );
        await openPicker(tester);

        expect(find.byType(Dialog), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('session isolation', () {
    testWidgets('signing out clears the assignment acknowledgement', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onEspresso(tester);

      await tapVisible(
        tester,
        rowAction('Northwind Retail', VendorProductCopy.withdrawAssignment),
      );
      await confirm(tester, VendorProductCopy.withdrawAssignment);
      expect(find.text(VendorProductCopy.withdrawnTitle), findsOneWidget);

      app.auth.emitSignedOut();
      await tester.pumpAndSettle();

      expect(find.text(VendorProductCopy.withdrawnTitle), findsNothing);
      expect(find.text('Northwind Retail'), findsNothing);
    });

    testWidgets('signing out closes an open picker\'s data', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onEspresso(tester, surface: tabletSurface);
      await openPicker(tester);
      expect(find.text('Lakeside Market'), findsOneWidget);

      app.auth.emitSignedOut();
      await tester.pumpAndSettle();

      expect(find.text('Lakeside Market'), findsNothing);
    });

    testWidgets('a stale assignment answer never lands in a new session', (
      WidgetTester tester,
    ) async {
      final FakeVendorProductRepository products = FakeVendorProductRepository()
        ..manualAssignmentWrites = true;
      final PumpedApp app = await onEspresso(tester, products: products);

      await tapVisible(
        tester,
        rowAction('Northwind Retail', VendorProductCopy.withdrawAssignment),
      );
      await confirmWithoutSettling(
        tester,
        VendorProductCopy.withdrawAssignment,
      );

      app.auth.emitSignedOut();
      await tester.pumpAndSettle();

      products.completeAssignment();
      await tester.pumpAndSettle();

      expect(find.text(VendorProductCopy.withdrawnTitle), findsNothing);
    });
  });
}

/// Closes the picker by its own Close action.
Future<void> dismiss2(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(Dialog),
      matching: find.widgetWithText(TextButton, VendorProductCopy.close),
    ),
  );
  await tester.pumpAndSettle();
}
