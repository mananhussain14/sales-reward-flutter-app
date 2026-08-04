import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sale_reward/app/shells/sales_staff/sales_staff_navigation.dart';
import 'package:sale_reward/core/widgets/widgets.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_confirmation.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_problem.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_product_proposal_line.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_with_products_outcome.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_with_products_result.dart';
import 'package:sale_reward/features/receipts/domain/repositories/receipt_extraction_result.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/pages/sales_staff_receipt_review_page.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/cubit/receipt_review_cubit.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/widgets/receipt_final_confirmation_section.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/widgets/receipt_review_copy.dart';

import '../../support/pump_app.dart';
import '../../support/receipt_review_fakes.dart';

/// The final confirmation section, driven through the real screen.
///
/// Every test here goes through the real router, the real shell and both real
/// cubits over fakes. Nothing asserts on a constructor argument: the behaviour
/// being protected is what a person can actually reach with a finger, and an
/// assertion on what a widget was handed would keep passing while the screen
/// offered a control it should not have.
void main() {
  Finder semanticsLabelled(String label) => find.byWidgetPredicate(
    (Widget widget) => widget is Semantics && widget.properties.label == label,
    description: 'Semantics labelled "$label"',
  );

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> open(
    WidgetTester tester,
    FakeReceiptExtractionRepository extraction, {
    Size surface = phoneSurface,
  }) async {
    await pumpAppInRole(
      tester,
      PortalKind.salesStaff,
      receiptExtraction: extraction,
      surface: surface,
    );
    final BuildContext context = tester.element(find.byType(Scaffold).first);
    GoRouter.of(context).go(SalesStaffNavigation.review(reviewSubmissionId));
    await tester.pumpAndSettle();
  }

  Future<void> chooseFirstProduct(WidgetTester tester) =>
      tapVisible(tester, find.text('Add').first);

  Future<void> confirm(WidgetTester tester) =>
      tapVisible(tester, find.text(ReceiptReviewCopy.confirmAction));

  /// The confirm control, as the tree actually holds it.
  SrButton confirmButton(WidgetTester tester) => tester.widget<SrButton>(
    find.descendant(
      of: find.byType(ReceiptFinalConfirmationSection),
      matching: find.byWidgetPredicate(
        (Widget widget) =>
            widget is SrButton &&
            widget.label == ReceiptReviewCopy.confirmAction,
      ),
    ),
  );

  /// A repository that answers the write with [result] and, by default, has a
  /// stored proposal to hand back afterwards.
  ///
  /// The stored rows matter even for tests that never look at them: since this
  /// unit, a settled write is followed by an authoritative read, and a fixture
  /// with no rows would put the screen into the "we could not load the lines"
  /// state rather than the success state it means to exercise. A test that
  /// wants the empty answer sets `productProposalResults` itself.
  FakeReceiptExtractionRepository answering(
    ReceiptExtractionResult<ReceiptWithProductsResult> result,
  ) {
    return FakeReceiptExtractionRepository(
      confirmWithProductsResults:
          <ReceiptExtractionResult<ReceiptWithProductsResult>>[result],
      productProposalResults:
          <ReceiptExtractionResult<List<ReceiptProductProposalLine>>>[
            const ReceiptExtractionSuccess<List<ReceiptProductProposalLine>>(
              storedProposalLines,
            ),
          ],
    );
  }

  group('the confirm control', () {
    testWidgets('is disabled until a product is chosen', (tester) async {
      final FakeReceiptExtractionRepository extraction = answering(
        withProductsResult(),
      );
      await open(tester, extraction);

      // Structurally disabled — a null callback, not a dimmed control that
      // still fires.
      expect(confirmButton(tester).onPressed, isNull);
      expect(
        find.text('Choose at least one product to confirm this receipt.'),
        findsOneWidget,
      );

      await confirm(tester);
      expect(extraction.confirmWithProductsCalls, isEmpty);

      await chooseFirstProduct(tester);
      expect(confirmButton(tester).onPressed, isNotNull);
    });

    testWidgets('shows the line count and the total quantity', (tester) async {
      final FakeReceiptExtractionRepository extraction = answering(
        withProductsResult(),
      );
      await open(tester, extraction);
      await chooseFirstProduct(tester);

      expect(find.text('1 product line'), findsOneWidget);
      expect(find.text('1 item in total'), findsOneWidget);

      // A second product, and a quantity bump, both reach the summary.
      await tapVisible(tester, find.text('Add').first);
      await tapVisible(tester, find.byIcon(Icons.add_circle_outline).first);

      expect(find.text('2 product lines'), findsOneWidget);
      expect(find.text('3 items in total'), findsOneWidget);
    });
  });

  group('while the write is pending', () {
    late Completer<ReceiptExtractionResult<ReceiptWithProductsResult>> gate;
    late FakeReceiptExtractionRepository extraction;

    /// Starts the write and leaves it in flight.
    ///
    /// The gate is created HERE rather than in a `setUp`, and that is not a
    /// style choice: `setUp` runs outside the fake-async zone `testWidgets`
    /// installs, so a completer built there resolves onto a microtask queue the
    /// binding never flushes and the write would hang for the whole test.
    ///
    /// It pumps once rather than settling, because the pending control carries
    /// a running spinner and the slow-notice timer is armed — settling would
    /// never return, which is exactly the state being tested.
    Future<void> startWrite(WidgetTester tester) async {
      gate = Completer<ReceiptExtractionResult<ReceiptWithProductsResult>>();
      extraction = FakeReceiptExtractionRepository()
        ..confirmWithProductsGate = gate;

      await open(tester, extraction);
      await chooseFirstProduct(tester);

      final Finder button = find.text(ReceiptReviewCopy.confirmAction);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pump();
    }

    Future<void> finish(WidgetTester tester) async {
      gate.complete(withProductsResult());
      await tester.pumpAndSettle();
    }

    testWidgets('the confirm control cannot fire again', (tester) async {
      await startWrite(tester);

      expect(extraction.confirmWithProductsCalls, hasLength(1));
      expect(confirmButton(tester).onPressed, isNull);

      // A second deliberate tap, mid-flight.
      await tester.tap(find.byType(SrButton).last, warnIfMissed: false);
      await tester.pump();
      expect(extraction.confirmWithProductsCalls, hasLength(1));

      await finish(tester);
    });

    testWidgets('the pending sentence names both halves', (tester) async {
      await startWrite(tester);

      expect(find.text(ReceiptReviewCopy.confirmPending), findsWidgets);

      await finish(tester);
    });

    testWidgets('every transaction field is disabled', (tester) async {
      await startWrite(tester);

      final Iterable<TextField> fields = tester.widgetList<TextField>(
        find.byType(TextField),
      );
      expect(fields, isNotEmpty);
      for (final TextField field in fields) {
        expect(field.enabled, isFalse);
      }

      await finish(tester);
    });

    testWidgets('search, selection and the steppers are all gone', (
      tester,
    ) async {
      await startWrite(tester);

      // The search field disappears rather than merely greying: a read-only
      // catalogue offers no affordance that could imply it is still editable.
      expect(find.byType(SrSearchField), findsNothing);
      // No stepper, and no remove control.
      expect(find.byIcon(Icons.add_circle_outline), findsNothing);
      expect(find.byIcon(Icons.remove_circle_outline), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      // The chosen quantity is still readable — frozen, not thrown away.
      expect(find.text('Products on this receipt'), findsOneWidget);

      await finish(tester);
    });

    testWidgets('the slow notice appears only after the delay', (tester) async {
      await startWrite(tester);

      expect(find.text(ReceiptReviewCopy.confirmSlow), findsNothing);

      await tester.pump(const Duration(seconds: 2));
      expect(find.text(ReceiptReviewCopy.confirmSlow), findsNothing);

      await tester.pump(const Duration(seconds: 3));
      expect(find.text(ReceiptReviewCopy.confirmSlow), findsOneWidget);

      // The notice added no control and sent nothing.
      expect(extraction.confirmWithProductsCalls, hasLength(1));
      expect(find.text(ReceiptReviewCopy.statusCheckAction), findsNothing);

      await finish(tester);
    });

    testWidgets('the pending state is announced', (tester) async {
      await startWrite(tester);

      final Iterable<Semantics> live = tester
          .widgetList<Semantics>(
            find.descendant(
              of: find.byType(ReceiptFinalConfirmationSection),
              matching: find.byType(Semantics),
            ),
          )
          .where((Semantics s) => s.properties.liveRegion ?? false);
      expect(live, isNotEmpty);

      await finish(tester);
    });
  });

  group('authoritative success', () {
    testWidgets('says the proposal is final and that nothing else happened', (
      tester,
    ) async {
      final FakeReceiptExtractionRepository extraction = answering(
        withProductsResult(lineCount: 1),
      );
      await open(tester, extraction);
      await chooseFirstProduct(tester);
      await confirm(tester);

      expect(find.text('Receipt and products recorded'), findsOneWidget);
      expect(
        find.textContaining('This proposal is final and cannot be changed.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('No campaign, reward or coins were created by it.'),
        findsOneWidget,
      );
    });

    testWidgets('removes the confirmation control entirely', (tester) async {
      final FakeReceiptExtractionRepository extraction = answering(
        withProductsResult(),
      );
      await open(tester, extraction);
      await chooseFirstProduct(tester);
      await confirm(tester);

      expect(find.text(ReceiptReviewCopy.confirmAction), findsNothing);
      // And no status check either: nothing is in doubt.
      expect(find.text(ReceiptReviewCopy.statusCheckAction), findsNothing);
      expect(find.byType(SrSearchField), findsNothing);
    });

    testWidgets('ALREADY_CONFIRMED never claims a new record', (tester) async {
      final FakeReceiptExtractionRepository extraction = answering(
        withProductsResult(
          outcome: ReceiptWithProductsOutcome.alreadyConfirmed,
          changed: false,
        ),
      );
      await open(tester, extraction);
      await chooseFirstProduct(tester);
      await confirm(tester);

      expect(find.text('This receipt was already recorded'), findsOneWidget);
      expect(find.text('Receipt and products recorded'), findsNothing);
      expect(find.textContaining('nothing was duplicated'), findsOneWidget);
    });
  });

  group('conflict', () {
    Future<FakeReceiptExtractionRepository> conflicted(
      WidgetTester tester,
    ) async {
      final FakeReceiptExtractionRepository extraction = answering(
        withProductsResult(
          outcome: ReceiptWithProductsOutcome.conflict,
          changed: false,
          lineCount: 4,
        ),
      );
      await open(tester, extraction);
      await chooseFirstProduct(tester);
      await confirm(tester);
      return extraction;
    }

    testWidgets('explains what is known and offers only a read', (
      tester,
    ) async {
      final FakeReceiptExtractionRepository extraction = await conflicted(
        tester,
      );

      expect(
        find.text('This receipt already has a different confirmation'),
        findsOneWidget,
      );
      expect(find.text(ReceiptReviewCopy.statusCheckAction), findsOneWidget);
      // No resend, no retry control of any kind.
      expect(find.text(ReceiptReviewCopy.confirmAction), findsNothing);
      expect(extraction.confirmWithProductsCalls, hasLength(1));
    });

    testWidgets('names nobody and shows no backend text', (tester) async {
      await conflicted(tester);

      for (final String forbidden in <String>[
        reviewConfirmationId,
        'confirm_receipt_with_products',
        'p_lines',
        '23505',
        'CONFLICT',
        'vendor_products',
        'receipt_confirmation_products',
      ]) {
        expect(find.textContaining(forbidden), findsNothing, reason: forbidden);
      }
    });

    testWidgets('keeps every mutation control disabled', (tester) async {
      await conflicted(tester);

      expect(find.byType(SrSearchField), findsNothing);
      expect(find.byIcon(Icons.add_circle_outline), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      for (final TextField field in tester.widgetList<TextField>(
        find.byType(TextField),
      )) {
        expect(field.enabled, isFalse);
      }
    });
  });

  group('an unreadable result', () {
    Future<FakeReceiptExtractionRepository> uncertain(
      WidgetTester tester, {
      ReceiptExtractionResult<ReceiptWithProductsResult>? result,
    }) async {
      final FakeReceiptExtractionRepository extraction = answering(
        result ??
            const ReceiptExtractionFailed<ReceiptWithProductsResult>(
              ExtractionNetworkProblem(),
            ),
      );
      await open(tester, extraction);
      await chooseFirstProduct(tester);
      await confirm(tester);
      return extraction;
    }

    testWidgets('a transport fault claims neither success nor failure', (
      tester,
    ) async {
      await uncertain(tester);

      expect(find.text(ReceiptReviewCopy.confirmUnverified), findsOneWidget);
      expect(find.text('Receipt and products recorded'), findsNothing);
      expect(find.text(ReceiptReviewCopy.confirmAction), findsNothing);
      expect(find.text(ReceiptReviewCopy.statusCheckAction), findsOneWidget);
    });

    testWidgets('an outcome this build cannot read is the same', (
      tester,
    ) async {
      await uncertain(
        tester,
        result: withProductsResult(
          outcome: ReceiptWithProductsOutcome.unknown,
          changed: false,
        ),
      );

      expect(find.text(ReceiptReviewCopy.confirmUnverified), findsOneWidget);
      expect(find.text('Receipt and products recorded'), findsNothing);
      expect(find.text(ReceiptReviewCopy.statusCheckAction), findsOneWidget);
    });

    testWidgets('the status check reads, and never writes', (tester) async {
      final FakeReceiptExtractionRepository extraction = await uncertain(
        tester,
      );

      await tapVisible(tester, find.text(ReceiptReviewCopy.statusCheckAction));

      expect(extraction.productProposalCalls, hasLength(1));
      expect(extraction.confirmWithProductsCalls, hasLength(1));
      expect(extraction.confirmInputs, isEmpty);
    });

    testWidgets('a check proving nothing is stored reopens the screen', (
      tester,
    ) async {
      final FakeReceiptExtractionRepository extraction = answering(
        const ReceiptExtractionFailed<ReceiptWithProductsResult>(
          ExtractionNetworkProblem(),
        ),
      );
      // Both reads answer, and both say nothing is there. Only then.
      extraction.productProposalResults =
          <ReceiptExtractionResult<List<ReceiptProductProposalLine>>>[
            const ReceiptExtractionSuccess<List<ReceiptProductProposalLine>>(
              <ReceiptProductProposalLine>[],
            ),
          ];
      extraction.confirmationResults =
          const <ReceiptExtractionResult<ReceiptConfirmation?>>[
            ReceiptExtractionSuccess<ReceiptConfirmation?>(null),
          ];

      await open(tester, extraction);
      await chooseFirstProduct(tester);
      await confirm(tester);
      await tapVisible(tester, find.text(ReceiptReviewCopy.statusCheckAction));

      expect(find.text('Nothing was stored for this receipt'), findsOneWidget);
      // Editable again, with the chosen product exactly where it was left —
      // and still no second write.
      expect(find.text(ReceiptReviewCopy.confirmAction), findsOneWidget);
      expect(find.byType(SrSearchField), findsOneWidget);
      expect(find.text('1 product line'), findsOneWidget);
      expect(extraction.confirmWithProductsCalls, hasLength(1));
    });

    testWidgets('a check that finds a header-only receipt appends nothing', (
      tester,
    ) async {
      final FakeReceiptExtractionRepository extraction = answering(
        const ReceiptExtractionFailed<ReceiptWithProductsResult>(
          ExtractionNetworkProblem(),
        ),
      );
      extraction.productProposalResults =
          <ReceiptExtractionResult<List<ReceiptProductProposalLine>>>[
            const ReceiptExtractionSuccess<List<ReceiptProductProposalLine>>(
              <ReceiptProductProposalLine>[],
            ),
          ];

      await open(tester, extraction);
      await chooseFirstProduct(tester);
      await confirm(tester);
      await tapVisible(tester, find.text(ReceiptReviewCopy.statusCheckAction));

      expect(
        find.text('This receipt was confirmed without products'),
        findsOneWidget,
      );
      expect(find.text(ReceiptReviewCopy.confirmAction), findsNothing);
      expect(extraction.confirmWithProductsCalls, hasLength(1));
      expect(extraction.confirmInputs, isEmpty);
    });

    testWidgets('no backend diagnostic reaches the screen', (tester) async {
      await uncertain(
        tester,
        result: const ReceiptExtractionFailed<ReceiptWithProductsResult>(
          ExtractionServiceUnavailableProblem(),
        ),
      );

      for (final String forbidden in <String>[
        'PostgrestException',
        'SQLSTATE',
        '22023',
        '42501',
        'confirm_receipt_with_products',
        'get_my_receipt_product_proposal',
        'p_lines',
        'ExtractionServiceUnavailableProblem',
      ]) {
        expect(find.textContaining(forbidden), findsNothing, reason: forbidden);
      }
    });
  });

  group('layout and accessibility', () {
    for (final Size surface in <Size>[
      smallPhoneSurface,
      phoneSurface,
      tabletSurface,
    ]) {
      testWidgets('the conflict state lays out without overflowing at '
          '${surface.width.toInt()}px', (tester) async {
        final FakeReceiptExtractionRepository extraction = answering(
          withProductsResult(
            outcome: ReceiptWithProductsOutcome.conflict,
            changed: false,
          ),
        );
        await open(tester, extraction, surface: surface);
        await chooseFirstProduct(tester);
        await confirm(tester);

        expect(tester.takeException(), isNull);
        expect(find.byType(SalesStaffReceiptReviewPage), findsOneWidget);
        expect(find.text(ReceiptReviewCopy.statusCheckAction), findsOneWidget);
      });
    }

    /// Pumps the section on its own, so a long sentence is measured against the
    /// widget this unit added rather than against the whole screen — the review
    /// page carries several older panels whose behaviour at extreme text scales
    /// is not this unit's to change.
    Future<void> pumpSection(
      WidgetTester tester,
      ReceiptProductSubmission submission, {
      double textScale = 1.0,
    }) async {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpThemed(
        tester,
        SingleChildScrollView(
          child: ReceiptFinalConfirmationSection(
            state: ReceiptReviewState(
              submissionId: reviewSubmissionId,
              manualConfirmationAllowed: true,
              phase: ReceiptReviewPhase.succeeded,
              productSubmission: submission,
            ),
            lineCount: 12,
            totalQuantity: 144,
            onConfirm: () {},
            onCheckStatus: () {},
          ),
        ),
        surface: smallPhoneSurface,
      );
    }

    for (final ReceiptProductSubmission submission
        in <ReceiptProductSubmission>[
          const ReceiptProductSubmission(),
          const ReceiptProductSubmission(
            status: ReceiptProductSubmissionStatus.pending,
            isSlow: true,
          ),
          ReceiptProductSubmission(
            status: ReceiptProductSubmissionStatus.settled,
            result: const ReceiptWithProductsResult(
              outcome: ReceiptWithProductsOutcome.confirmed,
              lineCount: 12,
              changed: true,
            ),
          ),
          const ReceiptProductSubmission(
            status: ReceiptProductSubmissionStatus.conflict,
          ),
          const ReceiptProductSubmission(
            status: ReceiptProductSubmissionStatus.uncertain,
          ),
        ]) {
      testWidgets(
        'the ${submission.status.name} copy fits a narrow phone at 1.6x',
        (tester) async {
          await pumpSection(tester, submission, textScale: 1.6);

          expect(tester.takeException(), isNull);
          // The summary wraps rather than truncating: both facts survive.
          expect(find.text('12 product lines'), findsOneWidget);
          expect(find.text('144 items in total'), findsOneWidget);
        },
      );
    }

    testWidgets('both actions carry a spoken label', (tester) async {
      final FakeReceiptExtractionRepository extraction = answering(
        withProductsResult(
          outcome: ReceiptWithProductsOutcome.conflict,
          changed: false,
        ),
      );
      await open(tester, extraction);
      await chooseFirstProduct(tester);

      expect(semanticsLabelled('Confirm this receipt'), findsWidgets);

      await confirm(tester);
      expect(
        semanticsLabelled('Check what is stored for this receipt'),
        findsWidgets,
      );
    });
  });
}
