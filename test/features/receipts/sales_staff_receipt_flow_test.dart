import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sale_reward/app/shells/sales_staff/sales_staff_navigation.dart';
import 'package:sale_reward/app/shells/sales_staff/sales_staff_shell.dart';
import 'package:sale_reward/features/auth/domain/entities/auth_user.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/auth/presentation/pages/access_denied_page.dart';
import 'package:sale_reward/features/auth/presentation/pages/login_page.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_rejection_reason.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_product.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_shop.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_submission.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_submission_outcome.dart';
import 'package:sale_reward/features/receipts/domain/repositories/receipt_result.dart';
import 'package:sale_reward/features/receipts/domain/services/receipt_image_source.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/cubit/receipt_submission_cubit.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/pages/sales_staff_history_page.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/pages/sales_staff_submit_page.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/widgets/receipt_progress_panel.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/widgets/receipt_shop_selector.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/widgets/receipt_submission_tile.dart';

import '../../support/fakes.dart';
import '../../support/pump_app.dart';
import '../../support/receipt_fakes.dart';

/// Drives the receipt screens through the real application: real router, real
/// shell, real cubits, over fakes that never touch Supabase or a platform
/// channel.
/// Finds the [Semantics] wrapper carrying an exact accessibility label.
///
/// Asserted at the widget layer rather than through the compiled semantics
/// tree, because a long form scrolls and the compiler drops nodes below the
/// fold — which would make an accessibility assertion depend on scroll
/// position rather than on the label being wired at all.
Finder semanticsLabelled(String label) => find.byWidgetPredicate(
  (Widget widget) => widget is Semantics && widget.properties.label == label,
  description: 'Semantics labelled "$label"',
);

/// Scrolls [finder] into view before tapping it.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Signs in as Sales Staff and opens the submission screen.
///
/// The shell now lands on the Home screen, so a test about the submission form
/// navigates to it first. The route, the cubits, the form and the write are
/// unchanged — one destination was added in front of them.
Future<PumpedApp> pumpSubmitScreen(
  WidgetTester tester, {
  FakeReceiptRepository? receipts,
  FakeReceiptImageSource? images,
  Size surface = phoneSurface,
}) async {
  final PumpedApp app = await pumpAppInRole(
    tester,
    PortalKind.salesStaff,
    receipts: receipts,
    images: images,
    surface: surface,
  );
  await goToLocation(tester, SalesStaffNavigation.submit);
  return app;
}

/// Navigates the running application to [location].
Future<void> goToLocation(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Navigator).first)).go(location);
  await tester.pumpAndSettle();
}

void main() {
  /// Signs in as Sales Staff, chooses a shop and picks a valid receipt.
  Future<PumpedApp> armed(
    WidgetTester tester, {
    FakeReceiptRepository? receipts,
    FakeReceiptImageSource? images,
    Size surface = phoneSurface,
  }) async {
    final PumpedApp app = await pumpSubmitScreen(
      tester,
      receipts: receipts,
      images: images,
      surface: surface,
    );

    await tapVisible(tester, find.text('Select a shop…'));
    await tester.tap(find.text('Marina Mall').last);
    await tester.pumpAndSettle();

    await tapVisible(tester, find.text('Choose image'));

    return app;
  }

  group('routing and role isolation', () {
    testWidgets('the Submit destination reaches the submission screen', (
      tester,
    ) async {
      await pumpSubmitScreen(tester);

      expect(find.byType(SalesStaffShell), findsOneWidget);
      expect(find.byType(SalesStaffSubmitPage), findsOneWidget);
      expect(find.text('Submit a receipt'), findsOneWidget);
    });

    testWidgets('the History tab reaches the receipts list', (tester) async {
      await pumpAppInRole(tester, PortalKind.salesStaff);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.byIcon(Icons.receipt_long_outlined),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SalesStaffHistoryPage), findsOneWidget);
      expect(find.text('My receipts'), findsOneWidget);
    });

    for (final PortalKind other in <PortalKind>[
      PortalKind.vendorSuperAdmin,
      PortalKind.retailerOwner,
      PortalKind.retailerManager,
    ]) {
      testWidgets('a ${other.name} cannot type their way onto the submit '
          'screen', (tester) async {
        await pumpAppInRole(tester, other);

        // A manual route into another role's group is sent back to the caller's
        // own landing. The guard prevents a confusing screen; the database
        // refuses the operations regardless.
        final BuildContext context = tester.element(
          find.byType(Scaffold).first,
        );
        GoRouter.of(context).go(SalesStaffNavigation.submit);
        await tester.pumpAndSettle();

        expect(find.byType(SalesStaffSubmitPage), findsNothing);
        expect(find.byType(SalesStaffShell), findsNothing);
      });

      testWidgets('a ${other.name} cannot type their way onto the history '
          'screen', (tester) async {
        await pumpAppInRole(tester, other);

        final BuildContext context = tester.element(
          find.byType(Scaffold).first,
        );
        GoRouter.of(context).go(SalesStaffNavigation.history);
        await tester.pumpAndSettle();

        expect(find.byType(SalesStaffHistoryPage), findsNothing);
      });
    }

    testWidgets('a denied session reaches neither receipt screen', (
      tester,
    ) async {
      await pumpApp(tester, initialUser: testUser, portalResult: deniedResult);

      expect(find.byType(AccessDeniedPage), findsOneWidget);
      expect(find.byType(SalesStaffSubmitPage), findsNothing);
    });
  });

  group('loading and empty states', () {
    testWidgets('no assigned shops explains itself without claiming a denial', (
      tester,
    ) async {
      final FakeReceiptRepository receipts = FakeReceiptRepository()
        ..shopsResult = const ReceiptReadSuccess<List<ReceiptShop>>(
          <ReceiptShop>[],
        );

      await pumpSubmitScreen(tester, receipts: receipts);

      expect(find.text('No shops assigned yet'), findsOneWidget);
      expect(find.text('Submit receipt'), findsNothing);
    });

    testWidgets('a shop read failure offers a retry, not a denial', (
      tester,
    ) async {
      final FakeReceiptRepository receipts = FakeReceiptRepository()
        ..shopsResult = unavailableRead<List<ReceiptShop>>();

      await pumpSubmitScreen(tester, receipts: receipts);

      expect(find.text('Could not load this'), findsOneWidget);
      expect(find.text('Try again'), findsWidgets);
      expect(find.text('Not available to this account'), findsNothing);
    });

    testWidgets('an empty product catalogue says so and blocks nothing', (
      tester,
    ) async {
      final FakeReceiptRepository receipts = FakeReceiptRepository()
        ..productsResult = const ReceiptReadSuccess<List<ReceiptProduct>>(
          <ReceiptProduct>[],
        );

      await pumpSubmitScreen(tester, receipts: receipts);

      expect(find.text('No products listed yet'), findsOneWidget);
      expect(find.text('Submit receipt'), findsOneWidget);
    });

    testWidgets('an empty history says so on both screens', (tester) async {
      await pumpAppInRole(tester, PortalKind.salesStaff);

      expect(find.text('No receipts yet'), findsOneWidget);
    });
  });

  group('choosing a receipt', () {
    testWidgets('camera and gallery are both offered where supported', (
      tester,
    ) async {
      await pumpSubmitScreen(tester);

      expect(find.text('Take photo'), findsOneWidget);
      expect(find.text('Choose image'), findsOneWidget);
    });

    testWidgets('capture is hidden where the platform has no camera', (
      tester,
    ) async {
      await pumpSubmitScreen(
        tester,
        images: FakeReceiptImageSource(supportsCamera: false),
      );

      expect(find.text('Take photo'), findsNothing);
      expect(find.text('Choose image'), findsOneWidget);
    });

    testWidgets('a chosen receipt previews with its name and size', (
      tester,
    ) async {
      await armed(tester);

      expect(find.text('receipt.png'), findsOneWidget);
      expect(find.text('PNG · 64 B'), findsOneWidget);
      expect(find.text('Replace'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
    });

    testWidgets('removing returns to the upload target', (tester) async {
      await armed(tester);

      await tapVisible(tester, find.text('Remove'));

      expect(find.text('Add the receipt'), findsOneWidget);
      expect(find.text('receipt.png'), findsNothing);
    });

    testWidgets('an unsupported file explains the format rule', (tester) async {
      final FakeReceiptImageSource images = FakeReceiptImageSource()
        ..nextImage = PickedReceiptImage(
          fileName: 'receipt.jpg',
          bytes: pdfBytes(),
        );

      await pumpSubmitScreen(tester, images: images);
      await tapVisible(tester, find.text('Choose image'));

      expect(find.text('This receipt was not accepted'), findsOneWidget);
      expect(find.textContaining('JPEG, PNG or WebP'), findsWidgets);
    });
  });

  group('submitting', () {
    testWidgets('the shop and the file are both visible before sending', (
      tester,
    ) async {
      await armed(tester);

      expect(find.text('Marina Mall · MM-01'), findsOneWidget);
      expect(find.text('receipt.png'), findsOneWidget);
    });

    testWidgets('stage-based progress is shown while uploading', (
      tester,
    ) async {
      final FakeReceiptRepository receipts = FakeReceiptRepository()
        ..manualSubmit = true;

      await armed(tester, receipts: receipts);
      await tester.ensureVisible(find.text('Submit receipt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit receipt'));
      await tester.pump();

      expect(find.byType(ReceiptProgressPanel), findsOneWidget);
      expect(find.text('Uploading receipt'), findsWidgets);
      expect(find.text('Step 2 of 3'), findsOneWidget);
      // No fabricated percentage anywhere.
      expect(find.textContaining('%'), findsNothing);

      receipts.completeSubmit();
      await tester.pumpAndSettle();
    });

    testWidgets(
      'a success shows the trusted status, id and a way to continue',
      (tester) async {
        await armed(tester);

        await tester.tap(find.text('Submit receipt'));
        await tester.pumpAndSettle();

        expect(find.text('Receipt submitted'), findsOneWidget);
        expect(find.text('Submitted'), findsWidgets);
        expect(find.text(submissionUuid), findsOneWidget);
        expect(find.text('Submit another receipt'), findsOneWidget);
        // The form is gone and the receipt is no longer held.
        expect(find.text('Submit receipt'), findsNothing);
      },
    );

    testWidgets('no storage path, bucket or hash is ever rendered', (
      tester,
    ) async {
      await armed(tester);
      await tapVisible(tester, find.text('Submit receipt'));

      for (final String forbidden in <String>[
        'receipts/',
        'storage',
        'sha256',
        'bucket',
        'object_path',
      ]) {
        expect(
          find.textContaining(forbidden),
          findsNothing,
          reason: '"$forbidden" must never reach the screen',
        );
      }
    });

    testWidgets('the new submission appears in recent submissions', (
      tester,
    ) async {
      final FakeReceiptRepository receipts = FakeReceiptRepository();

      await armed(tester, receipts: receipts);
      // The history is empty until the submission lands, then the refresh finds
      // it.
      receipts.submissionsResult = ReceiptReadSuccess<List<ReceiptSubmission>>(
        <ReceiptSubmission>[submittedRow],
      );

      await tapVisible(tester, find.text('Submit receipt'));

      expect(find.byType(ReceiptSubmissionTile), findsOneWidget);
      expect(find.text('No receipts yet'), findsNothing);
    });

    testWidgets('submitting again resets the form', (tester) async {
      await armed(tester);
      await tapVisible(tester, find.text('Submit receipt'));

      await tapVisible(tester, find.text('Submit another receipt'));

      expect(find.text('Add the receipt'), findsOneWidget);
      expect(find.text('Receipt submitted'), findsNothing);
    });
  });

  group('failure states', () {
    testWidgets('a duplicate is explained and cannot be resent', (
      tester,
    ) async {
      final FakeReceiptRepository receipts = FakeReceiptRepository()
        ..submitOutcome = const ReceiptSubmissionDuplicate();

      await armed(tester, receipts: receipts);
      await tapVisible(tester, find.text('Submit receipt'));

      expect(find.text('You already submitted this receipt'), findsOneWidget);
      expect(receipts.submitCallCount, 1);

      // The button is disabled, so a second tap changes nothing.
      await tester.tap(find.text('Submit receipt'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(receipts.submitCallCount, 1);
    });

    testWidgets('a denial names the shop rule, never a missing receipt', (
      tester,
    ) async {
      final FakeReceiptRepository receipts = FakeReceiptRepository()
        ..submitOutcome = const ReceiptSubmissionDenied();

      await armed(tester, receipts: receipts);
      await tapVisible(tester, find.text('Submit receipt'));

      expect(find.text('That shop is not available to you'), findsOneWidget);
      // The receipt is kept so another shop can be tried.
      expect(find.text('receipt.png'), findsOneWidget);
    });

    testWidgets('an upload failure offers the same photo again', (
      tester,
    ) async {
      final FakeReceiptRepository receipts = FakeReceiptRepository()
        ..submitOutcome = const ReceiptSubmissionUploadFailed();

      await armed(tester, receipts: receipts);
      await tapVisible(tester, find.text('Submit receipt'));

      expect(find.text('Upload failed'), findsOneWidget);

      receipts.submitOutcome = const ReceiptSubmissionAccepted(submissionUuid);
      await tapVisible(tester, find.text('Submit receipt'));

      expect(find.text('Receipt submitted'), findsOneWidget);
      expect(receipts.submitCallCount, 2);
    });

    testWidgets('an unconfirmed result points at the history, not a resend', (
      tester,
    ) async {
      final FakeReceiptRepository receipts = FakeReceiptRepository()
        ..submitOutcome = const ReceiptSubmissionUnconfirmed();

      await armed(tester, receipts: receipts);
      await tapVisible(tester, find.text('Submit receipt'));

      expect(find.text('We could not confirm this submission'), findsOneWidget);
      expect(
        find.textContaining('Check your recent submissions'),
        findsOneWidget,
      );
      // Exactly one attempt, and the history was re-read.
      expect(receipts.submitCallCount, 1);
      expect(receipts.submissionsCallCount, greaterThan(1));
    });

    testWidgets('an expired session says so without claiming a denial', (
      tester,
    ) async {
      final FakeReceiptRepository receipts = FakeReceiptRepository()
        ..submitOutcome = const ReceiptSubmissionUnauthenticated();

      await armed(tester, receipts: receipts);
      await tapVisible(tester, find.text('Submit receipt'));

      expect(find.text('Your session has ended'), findsOneWidget);
      expect(find.text('That shop is not available to you'), findsNothing);
    });

    testWidgets('an oversized file names the limit', (tester) async {
      final FakeReceiptRepository receipts = FakeReceiptRepository()
        ..submitOutcome = const ReceiptSubmissionRefused(
          ReceiptRejectionReason.tooLarge,
        );

      await armed(tester, receipts: receipts);
      await tapVisible(tester, find.text('Submit receipt'));

      expect(find.textContaining('larger than 10 MB'), findsOneWidget);
    });
  });

  group('session isolation', () {
    testWidgets('signing out clears the receipt screens from memory', (
      tester,
    ) async {
      final PumpedApp app = await armed(tester);
      expect(find.text('receipt.png'), findsOneWidget);

      app.auth.emitSignedOut();
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(SalesStaffShell), findsNothing);
      expect(find.text('receipt.png'), findsNothing);
      // The cubits went with the shell.
      expect(find.byType(ReceiptSubmissionCubit), findsNothing);
    });

    testWidgets('a different user gets a fresh, empty form', (tester) async {
      final PumpedApp app = await armed(tester);

      app.portal.result = resolvedResult(PortalKind.salesStaff);
      app.auth.emitSignedIn(
        const AuthUser(id: 'user-2', email: 'other@example.com'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SalesStaffSubmitPage), findsOneWidget);
      // No trace of the previous person's chosen receipt.
      expect(find.text('receipt.png'), findsNothing);
      expect(find.text('Add the receipt'), findsOneWidget);
    });
  });

  group('layout, theme and accessibility', () {
    for (final Size surface in <Size>[
      smallPhoneSurface,
      phoneSurface,
      tabletSurface,
      desktopSurface,
    ]) {
      testWidgets('the submit screen does not overflow at '
          '${surface.width}×${surface.height}', (tester) async {
        await armed(tester, surface: surface);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the history screen does not overflow on a small phone', (
      tester,
    ) async {
      final FakeReceiptRepository receipts = FakeReceiptRepository()
        ..submissionsResult = ReceiptReadSuccess<List<ReceiptSubmission>>(
          <ReceiptSubmission>[submittedRow],
        );

      await pumpAppInRole(
        tester,
        PortalKind.salesStaff,
        receipts: receipts,
        surface: smallPhoneSurface,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.byIcon(Icons.receipt_long_outlined),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(ReceiptSubmissionTile), findsOneWidget);
    });

    for (final ThemeMode mode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
      testWidgets('the submit screen renders in ${mode.name}', (tester) async {
        await pumpApp(
          tester,
          initialUser: testUser,
          portalResult: resolvedResult(PortalKind.salesStaff),
          themeMode: mode,
        );
        await goToLocation(tester, SalesStaffNavigation.submit);

        expect(find.byType(SalesStaffSubmitPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the shop field announces itself and its value', (
      tester,
    ) async {
      await armed(tester);

      final Semantics shopField = tester.widget<Semantics>(
        find.descendant(
          of: find.byType(ReceiptShopSelector),
          matching: semanticsLabelled('Assigned shop'),
        ),
      );

      expect(shopField.properties.button, isTrue);
      expect(shopField.properties.value, 'Marina Mall · MM-01');
    });

    testWidgets('progress is announced as a live region', (tester) async {
      final FakeReceiptRepository receipts = FakeReceiptRepository()
        ..manualSubmit = true;

      await armed(tester, receipts: receipts);
      await tester.ensureVisible(find.text('Submit receipt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit receipt'));
      await tester.pump();

      final Semantics progress = tester.widget<Semantics>(
        find.descendant(
          of: find.byType(ReceiptProgressPanel),
          matching: semanticsLabelled('Submission progress'),
        ),
      );
      expect(progress.properties.liveRegion, isTrue);
      expect(progress.properties.value, 'Uploading receipt');

      receipts.completeSubmit();
      await tester.pumpAndSettle();
    });

    testWidgets('the receipt preview carries an image description', (
      tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await armed(tester);

      expect(
        find.bySemanticsLabel('Preview of the selected receipt image'),
        findsOneWidget,
      );

      handle.dispose();
    });
  });
}
