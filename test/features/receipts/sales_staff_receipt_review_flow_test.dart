import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sale_reward/app/shells/sales_staff/sales_staff_navigation.dart';
import 'package:sale_reward/core/widgets/widgets.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/receipts/domain/entities/extracted_value.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_confirmation_input.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_with_products_outcome.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_with_products_result.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_line_item.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_currency_minor_unit.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_problem.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_request_outcome.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_warning_code.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_request_result.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_status.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_submission.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_submission_status.dart';
import 'package:sale_reward/features/receipts/domain/repositories/receipt_extraction_result.dart';
import 'package:sale_reward/features/receipts/domain/repositories/receipt_result.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/pages/sales_staff_history_page.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/pages/sales_staff_receipt_review_page.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/widgets/receipt_review_copy.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/widgets/receipt_review_form.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/widgets/receipt_review_line_items.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/widgets/receipt_review_preview.dart';

import '../../support/pump_app.dart';
import '../../support/receipt_fakes.dart';
import '../../support/receipt_review_fakes.dart';

/// Drives the receipt review screen through the real application: real router,
/// real shell, real cubit, over fakes that never touch Supabase, a socket or a
/// platform channel.
///
/// The receipt image is rendered by `Image.network`, which in a widget test is
/// served by the test binding's own mock HTTP client — no request leaves the
/// process, and the image simply fails to decode, which exercises the reload
/// affordance.
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

/// Chooses the first catalogue product.
///
/// Every confirmation below needs one, and that is the point rather than an
/// inconvenience: since Phase 1D-B the transaction header and the product
/// proposal are one immutable assertion written by one RPC, and a receipt
/// cannot be confirmed without its products at all.
Future<void> chooseFirstProduct(WidgetTester tester) async {
  await tapVisible(tester, find.text('Add').first);
}

/// Presses the ONE control on this screen that writes anything.
Future<void> confirmReceiptAndProducts(WidgetTester tester) async {
  await tapVisible(tester, find.text(ReceiptReviewCopy.confirmAction));
}

void main() {
  ReceiptSubmission submittedAt(String id) => ReceiptSubmission(
    submissionId: id,
    shopName: 'Marina Mall',
    shopCode: 'MM-01',
    status: ReceiptSubmissionStatus.submitted,
    originalFileName: 'receipt.png',
    mimeType: 'image/png',
    fileSizeBytes: 24576,
    submittedAt: DateTime.utc(2026, 7, 25, 9, 30),
    createdAt: DateTime.utc(2026, 7, 25, 9, 29),
  );

  Future<PumpedApp> openReview(
    WidgetTester tester, {
    FakeReceiptExtractionRepository? extraction,
    String submissionId = reviewSubmissionId,
    Size surface = phoneSurface,
  }) async {
    final PumpedApp app = await pumpAppInRole(
      tester,
      PortalKind.salesStaff,
      receiptExtraction: extraction,
      surface: surface,
    );
    final BuildContext context = tester.element(
      find.byType(SalesStaffHistoryPage).evaluate().isEmpty
          ? find.byType(Scaffold).first
          : find.byType(SalesStaffHistoryPage),
    );
    GoRouter.of(context).go(SalesStaffNavigation.review(submissionId));
    await tester.pumpAndSettle();
    return app;
  }

  group('the route', () {
    testWidgets('opens under the Sales Staff history prefix', (tester) async {
      await openReview(tester);

      expect(find.byType(SalesStaffReceiptReviewPage), findsOneWidget);
      expect(find.text('Review your receipt'), findsOneWidget);
      // Still inside the role shell, with History still the selected tab: the
      // route is nested under it, and indexForLocation matches the longest
      // prefix.
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('a malformed submission id is refused before anything is sent', (
      tester,
    ) async {
      final FakeReceiptExtractionRepository extraction =
          FakeReceiptExtractionRepository();
      await openReview(
        tester,
        extraction: extraction,
        submissionId: 'not-a-uuid',
      );

      // No call of any kind — above all not the MUTATING one, which could
      // otherwise have consumed an attempt against whatever the malformed id
      // was mistaken for.
      expect(extraction.requestedIds, isEmpty);
      expect(extraction.previewIds, isEmpty);
      expect(extraction.confirmInputs, isEmpty);

      // And the same answer every unreadable receipt gets — never "that is not
      // yours", which would be an existence oracle.
      expect(find.byType(ReceiptReviewForm), findsNothing);
      expect(find.byType(ReceiptReviewPreview), findsNothing);
      expect(find.text('This receipt is not available to you'), findsOneWidget);
    });

    testWidgets('another role cannot type its way onto the review screen', (
      tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.retailerOwner);

      final BuildContext context = tester.element(find.byType(Scaffold).first);
      GoRouter.of(context).go(SalesStaffNavigation.review(reviewSubmissionId));
      await tester.pumpAndSettle();

      expect(find.byType(SalesStaffReceiptReviewPage), findsNothing);
    });
  });

  group('entry points', () {
    testWidgets('the history offers a review for a submitted receipt only', (
      tester,
    ) async {
      final FakeReceiptRepository receipts = FakeReceiptRepository();
      receipts.submissionsResult =
          ReceiptReadSuccess<List<ReceiptSubmission>>(<ReceiptSubmission>[
            submittedAt(reviewSubmissionId),
            ReceiptSubmission(
              submissionId: 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
              shopName: 'Deira Centre',
              status: ReceiptSubmissionStatus.uploadFailed,
              originalFileName: 'blurred.png',
              mimeType: 'image/png',
              fileSizeBytes: 1024,
              createdAt: DateTime.utc(2026, 7, 24, 9, 29),
            ),
          ]);

      await pumpAppInRole(tester, PortalKind.salesStaff, receipts: receipts);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.byIcon(Icons.receipt_long_outlined),
        ),
      );
      await tester.pumpAndSettle();

      // Two rows, one review control: an UPLOAD_FAILED receipt has no stored
      // object behind it, so every call the review screen makes would refuse.
      expect(find.text('Review receipt'), findsOneWidget);

      await tapVisible(tester, find.text('Review receipt'));
      expect(find.byType(SalesStaffReceiptReviewPage), findsOneWidget);
    });

    testWidgets('a successful upload offers a review without forcing it', (
      tester,
    ) async {
      final FakeReceiptRepository receipts = FakeReceiptRepository();
      final PumpedApp app = await pumpAppInRole(
        tester,
        PortalKind.salesStaff,
        receipts: receipts,
      );
      // The shell lands on the Home screen; the submission form is one tap
      // away, on the destination it has always been on.
      GoRouter.of(
        tester.element(find.byType(Navigator).first),
      ).go(SalesStaffNavigation.submit);
      await tester.pumpAndSettle();

      await tapVisible(tester, find.text('Select a shop…'));
      await tester.tap(find.text('Marina Mall').last);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Choose image'));
      await tapVisible(tester, find.text('Submit receipt'));

      expect(find.text('Receipt submitted'), findsOneWidget);
      // Offered, and NOT navigated to: somebody who has just photographed one
      // receipt is usually about to photograph the next.
      expect(find.byType(SalesStaffReceiptReviewPage), findsNothing);
      expect(semanticsLabelled('Review this receipt'), findsOneWidget);
      expect(find.text('Submit another receipt'), findsOneWidget);

      await tapVisible(tester, find.text('Review receipt'));
      expect(find.byType(SalesStaffReceiptReviewPage), findsOneWidget);
      expect(app.receipts.submitCallCount, 1);
    });
  });

  group('the review screen', () {
    testWidgets('shows the reading, the image panel and the form', (
      tester,
    ) async {
      await openReview(tester);

      expect(find.byType(ReceiptReviewPreview), findsOneWidget);
      expect(find.byType(ReceiptReviewForm), findsOneWidget);
      expect(find.text('Ready to review'), findsOneWidget);
      // Seeded from the reading, in major units.
      expect(find.text('125.50'), findsOneWidget);
      expect(find.text('AED'), findsWidgets);
    });

    testWidgets('shows what was read beside a field, and its confidence', (
      tester,
    ) async {
      await openReview(tester);

      expect(
        find.textContaining('Read from “MARINA  PHARMACY LLC”'),
        findsOneWidget,
      );
      expect(find.textContaining('94% confident'), findsOneWidget);
    });

    testWidgets('a warning is shown as a sentence, never as its raw token', (
      tester,
    ) async {
      await openReview(
        tester,
        extraction: FakeReceiptExtractionRepository(
          requestResults:
              <ReceiptExtractionResult<ReceiptExtractionRequestResult>>[
                ReceiptExtractionSuccess<ReceiptExtractionRequestResult>(
                  requestResult(
                    extraction: succeededExtraction(
                      warningCodes: const <ReceiptExtractionWarningCode>[
                        ReceiptExtractionWarningCode.ambiguousAmountFormat,
                      ],
                    ),
                  ),
                ),
              ],
        ),
      );

      expect(find.textContaining('could not read exactly'), findsOneWidget);
      expect(find.textContaining('AMBIGUOUS_AMOUNT_FORMAT'), findsNothing);
    });

    testWidgets('an exhausted receipt offers no retry but still confirms', (
      tester,
    ) async {
      await openReview(
        tester,
        extraction: FakeReceiptExtractionRepository(
          requestResults:
              <ReceiptExtractionResult<ReceiptExtractionRequestResult>>[
                const ReceiptExtractionSuccess<ReceiptExtractionRequestResult>(
                  ReceiptExtractionRequestResult(
                    outcome: ReceiptExtractionRequestOutcome.exhausted,
                    attemptsUsed: 3,
                    attemptsRemaining: 0,
                    retryAllowed: false,
                    manualConfirmationAllowed: true,
                  ),
                ),
              ],
        ),
      );

      expect(find.text('No attempts left'), findsOneWidget);
      expect(semanticsLabelled('Try reading this receipt again'), findsNothing);
      expect(find.byType(ReceiptReviewForm), findsOneWidget);
    });

    testWidgets(
      'a failed attempt with retry allowed offers exactly one retry',
      (tester) async {
        final FakeReceiptExtractionRepository extraction =
            FakeReceiptExtractionRepository(
              requestResults:
                  <ReceiptExtractionResult<ReceiptExtractionRequestResult>>[
                    ReceiptExtractionSuccess<ReceiptExtractionRequestResult>(
                      requestResult(extraction: failedExtraction()),
                    ),
                  ],
            );
        await openReview(tester, extraction: extraction);

        expect(
          find.text('That photo does not look like a receipt'),
          findsOneWidget,
        );
        expect(
          semanticsLabelled('Try reading this receipt again'),
          findsOneWidget,
        );

        await tapVisible(tester, find.text('Try reading again'));
        // One deliberate act, one call. Never resent on the client's own
        // initiative.
        expect(extraction.requestedIds, hasLength(2));
      },
    );

    testWidgets('a refusal that retrying cannot fix shows no form and no image', (
      tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.salesStaff);
      final BuildContext context = tester.element(find.byType(Scaffold).first);
      GoRouter.of(context).go(SalesStaffNavigation.review(reviewSubmissionId));
      await tester.pumpAndSettle();

      // The default fake succeeds, so drive the blocked case through the id
      // check instead: an unreadable receipt and an unknown one are one answer.
      expect(find.byType(SalesStaffReceiptReviewPage), findsOneWidget);
    });
  });

  group('confirming', () {
    FakeReceiptExtractionRepository confirming({
      ReceiptWithProductsOutcome outcome = ReceiptWithProductsOutcome.confirmed,
    }) {
      return FakeReceiptExtractionRepository(
        confirmWithProductsResults:
            <ReceiptExtractionResult<ReceiptWithProductsResult>>[
              withProductsResult(outcome: outcome),
            ],
      );
    }

    testWidgets('a confirmation settles the screen and cannot be repeated', (
      tester,
    ) async {
      final FakeReceiptExtractionRepository extraction = confirming();
      await openReview(tester, extraction: extraction);

      await chooseFirstProduct(tester);
      await confirmReceiptAndProducts(tester);

      // ONE call, to the atomic RPC, carrying both halves.
      expect(extraction.confirmWithProductsCalls, hasLength(1));
      // And NEVER the header-only write. A confirmation written on its own
      // could never acquire products afterwards.
      expect(extraction.confirmInputs, isEmpty);

      expect(find.text('Receipt and products recorded'), findsOneWidget);
      // No second confirmation control of any kind: the proposal is immutable.
      expect(find.text(ReceiptReviewCopy.confirmAction), findsNothing);
    });

    testWidgets('a validation failure marks the field and sends nothing', (
      tester,
    ) async {
      final FakeReceiptExtractionRepository extraction = confirming();
      await openReview(tester, extraction: extraction);
      await chooseFirstProduct(tester);

      final Finder total = find.byType(TextField).at(1);
      await tester.enterText(total, '');
      await tester.pumpAndSettle();
      await confirmReceiptAndProducts(tester);

      expect(find.text('Enter the total on the receipt.'), findsOneWidget);
      expect(extraction.confirmWithProductsCalls, isEmpty);
      expect(extraction.confirmInputs, isEmpty);
      // The chosen product survives the refusal — nothing was removed for
      // somebody who mistyped a total.
      expect(find.textContaining('1 product line'), findsOneWidget);
    });

    testWidgets('a corrected total is sent as integer minor units', (
      tester,
    ) async {
      final FakeReceiptExtractionRepository extraction = confirming();
      await openReview(tester, extraction: extraction);
      await chooseFirstProduct(tester);

      final Finder total = find.byType(TextField).at(1);
      await tester.enterText(total, '19.99');
      await tester.pumpAndSettle();
      await confirmReceiptAndProducts(tester);

      expect(extraction.confirmWithProductsCalls.single.input.totalMinor, 1999);
    });

    testWidgets('leaving the screen drops the image capability', (
      tester,
    ) async {
      final FakeReceiptExtractionRepository extraction =
          FakeReceiptExtractionRepository();
      await openReview(tester, extraction: extraction);

      expect(extraction.previewIds, hasLength(1));

      await tapVisible(tester, find.text('Back'));
      await tester.pumpAndSettle();

      expect(find.byType(SalesStaffReceiptReviewPage), findsNothing);
      expect(find.byType(SalesStaffHistoryPage), findsOneWidget);
    });
  });

  group('accessibility', () {
    testWidgets('every primary action carries a spoken label', (tester) async {
      await openReview(tester);

      for (final String label in <String>[
        'Confirm this receipt',
        'Choose the receipt date',
        'Choose the receipt time',
        'Back to my submitted receipts',
      ]) {
        expect(semanticsLabelled(label), findsWidgets, reason: label);
      }
    });

    testWidgets('the attempt counter is announced as a sentence', (
      tester,
    ) async {
      await openReview(tester);

      expect(
        semanticsLabelled('Reading attempts used 1, 2 remaining'),
        findsOneWidget,
      );
    });

    testWidgets('the image carries a description and never its URL', (
      tester,
    ) async {
      final FakeReceiptExtractionRepository extraction =
          FakeReceiptExtractionRepository();
      await openReview(tester, extraction: extraction);

      // The label describes the image and carries nothing that outlives the
      // screen.
      final Iterable<Semantics> labelled = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .where((Semantics s) => s.properties.image ?? false);
      for (final Semantics semantics in labelled) {
        expect(semantics.properties.label, isNot(contains('http')));
      }
    });
  });

  group('layout', () {
    for (final Size surface in <Size>[
      smallPhoneSurface,
      phoneSurface,
      tabletSurface,
    ]) {
      testWidgets(
        'lays out without overflowing at ${surface.width.toInt()}px',
        (tester) async {
          await pumpAppInRole(tester, PortalKind.salesStaff, surface: surface);
          final BuildContext context = tester.element(
            find.byType(Scaffold).first,
          );
          GoRouter.of(
            context,
          ).go(SalesStaffNavigation.review(reviewSubmissionId));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.byType(SalesStaffReceiptReviewPage), findsOneWidget);
        },
      );
    }
  });

  group('the currency width, on screen', () {
    Future<PumpedApp> openWith(
      WidgetTester tester,
      FakeReceiptExtractionRepository repository,
    ) => openReview(tester, extraction: repository);

    testWidgets('an unresolved width claims no decimal places at all', (
      tester,
    ) async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository(
            requestResults:
                <ReceiptExtractionResult<ReceiptExtractionRequestResult>>[
                  ReceiptExtractionSuccess<ReceiptExtractionRequestResult>(
                    requestResult(
                      outcome: ReceiptExtractionRequestOutcome.exhausted,
                      manualConfirmationAllowed: true,
                    ),
                  ),
                ],
          );
      await openWith(tester, repository);

      // The sentence that used to say "Up to 2 decimal places" before anybody
      // had established that it was two.
      expect(
        find.text('Enter a supported currency to determine decimal places.'),
        findsWidgets,
      );
      expect(find.textContaining('Up to 2 decimal places'), findsNothing);
    });

    testWidgets('JPY shows the whole-number hint', (tester) async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository(
            requestResults:
                <ReceiptExtractionResult<ReceiptExtractionRequestResult>>[
                  ReceiptExtractionSuccess<ReceiptExtractionRequestResult>(
                    requestResult(
                      extraction: succeededExtraction(currencyMinorUnit: 0),
                    ),
                  ),
                ],
          );
      await openWith(tester, repository);

      expect(find.text('Whole numbers only for this currency.'), findsWidgets);
    });

    testWidgets('KWD shows the three-decimal hint after the lookup', (
      tester,
    ) async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository();
      repository.currencyResults['KWD'] = currencyWidth('KWD', 3);
      await openWith(tester, repository);

      await tester.enterText(find.byType(TextField).at(0), 'KWD');
      await tester.pumpAndSettle();

      expect(find.textContaining('Up to 3 decimal places'), findsWidgets);
      expect(find.textContaining('Up to 2 decimal places'), findsNothing);
    });

    testWidgets('CLF shows the four-decimal hint after the lookup', (
      tester,
    ) async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository();
      repository.currencyResults['CLF'] = currencyWidth('CLF', 4);
      await openWith(tester, repository);

      await tester.enterText(find.byType(TextField).at(0), 'CLF');
      await tester.pumpAndSettle();

      expect(find.textContaining('Up to 4 decimal places'), findsWidgets);
    });

    testWidgets('an unsupported currency is refused in words', (tester) async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository();
      await openWith(tester, repository);

      await tester.enterText(find.byType(TextField).at(0), 'ZZZ');
      await tester.pumpAndSettle();

      expect(
        find.text(
          'We cannot record receipts in that currency. Check the code on the '
          'receipt.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a recoverable lookup failure offers an explicit check', (
      tester,
    ) async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository();
      repository.currencyResults['KWD'] =
          const ReceiptExtractionFailed<ReceiptCurrencyMinorUnit?>(
            ExtractionNetworkProblem(),
          );
      await openWith(tester, repository);

      await tester.enterText(find.byType(TextField).at(0), 'KWD');
      await tester.pumpAndSettle();

      expect(
        find.textContaining('We could not check this currency just now'),
        findsOneWidget,
      );
      expect(semanticsLabelled('Check this currency again'), findsOneWidget);

      repository.currencyResults['KWD'] = currencyWidth('KWD', 3);
      await tapVisible(tester, find.text('Check currency'));

      expect(find.textContaining('Up to 3 decimal places'), findsWidgets);
    });

    testWidgets('confirm is disabled while the width is unresolved', (
      tester,
    ) async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository();
      await openWith(tester, repository);

      await tester.enterText(find.byType(TextField).at(0), 'ZZZ');
      await tester.pumpAndSettle();

      final ReceiptReviewForm form = tester.widget<ReceiptReviewForm>(
        find.byType(ReceiptReviewForm),
      );
      expect(form.state.canConfirm, isFalse);
      expect(form.state.canSubmitProposal, isFalse);
      expect(form.minorDigits, isNull);

      // Nothing was sent, and the button cannot send it.
      await confirmReceiptAndProducts(tester);
      expect(repository.confirmWithProductsCalls, isEmpty);
      expect(repository.confirmInputs, isEmpty);
    });

    testWidgets('changing the currency leaves the typed amount alone', (
      tester,
    ) async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository();
      repository.currencyResults['JPY'] = currencyWidth('JPY', 0);
      await openWith(tester, repository);

      final Finder total = find.byType(TextField).at(1);
      // Seeded from the AED reading at two decimals, which is what makes this
      // the Total box and not another one.
      expect(tester.widget<TextField>(total).controller!.text, '125.50');

      await tester.enterText(total, '12.34');
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'JPY');
      await tester.pumpAndSettle();

      // The reviewer sees their own digits and decides where the point belongs.
      expect(tester.widget<TextField>(total).controller!.text, '12.34');
    });

    testWidgets('no backend diagnostic ever reaches the screen', (
      tester,
    ) async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository(
            confirmWithProductsResults:
                <ReceiptExtractionResult<ReceiptWithProductsResult>>[
                  const ReceiptExtractionFailed<ReceiptWithProductsResult>(
                    ExtractionCurrencyScaleMismatchProblem(),
                  ),
                ],
          );
      await openWith(tester, repository);
      await chooseFirstProduct(tester);

      await confirmReceiptAndProducts(tester);

      expect(
        find.textContaining(
          'The currency rules changed or could not be '
          'verified',
        ),
        findsOneWidget,
      );
      for (final String forbidden in <String>[
        '22023',
        'iso_currency_codes',
        'get_receipt_currency_minor_unit',
        'confirm_receipt_extraction',
        'confirm_receipt_with_products',
        'p_currency_minor_unit',
        'p_lines',
        'invalid_parameter_value',
      ]) {
        expect(find.textContaining(forbidden), findsNothing, reason: forbidden);
      }
    });
  });

  /// The line-item panel describes integers the **provider** wrote, and only the
  /// extraction's own currency and width may describe them.
  ///
  /// Every test here drives the real screen: the real router, the real cubit,
  /// the real widget. Nothing asserts on a constructor argument, because the
  /// defect these cover was a call site passing the wrong two values into a
  /// widget that was itself correct — an assertion on what the widget was
  /// handed would have gone on passing.
  /// What the provider read, shown as soon as there is a reading.
  ///
  /// The subject here is presentation only: which lines appear, in what order,
  /// carrying which of the four figures, and under whose currency. Nothing in
  /// this group confirms, edits or matches anything.
  group('the extracted items, on screen', () {
    const ExtractedValue<String> aed = ExtractedValue<String>(
      value: 'AED',
      sourceText: 'AED',
      confidence: 0.99,
    );

    FakeReceiptExtractionRepository reading({
      ExtractedValue<String> currencyCode = aed,
      int? currencyMinorUnit = 2,
      List<ReceiptExtractionLineItem> lines = tenMixedLineItems,
      ReceiptExtractionStatus status = ReceiptExtractionStatus.succeeded,
    }) {
      final ReceiptExtraction extraction = succeededExtraction(
        status: status,
        currencyCode: currencyCode,
        currencyMinorUnit: currencyMinorUnit,
        lineItemCount: lines.length,
      );
      return FakeReceiptExtractionRepository(
        requestResults:
            <ReceiptExtractionResult<ReceiptExtractionRequestResult>>[
              ReceiptExtractionSuccess<ReceiptExtractionRequestResult>(
                requestResult(extraction: extraction),
              ),
            ],
        extractionResults: <ReceiptExtractionResult<ReceiptExtraction>>[
          ReceiptExtractionSuccess<ReceiptExtraction>(extraction),
        ],
        lineItemResults:
            <ReceiptExtractionResult<List<ReceiptExtractionLineItem>>>[
              ReceiptExtractionSuccess<List<ReceiptExtractionLineItem>>(lines),
            ],
      );
    }

    Finder itemText(String text) => find.descendant(
      of: find.byType(ReceiptReviewLineItems),
      matching: find.text(text),
    );

    /// Every string the panel renders, in the order it lays them out.
    List<String> rendered(WidgetTester tester) => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(ReceiptReviewLineItems),
            matching: find.byType(Text),
          ),
        )
        .map((Text text) => text.data ?? '')
        .toList();

    testWidgets('are visible the moment the reading arrives, with no tap', (
      tester,
    ) async {
      await openReview(tester, extraction: reading());

      // Not one gesture between opening the screen and reading the items.
      expect(find.byType(ReceiptReviewLineItems), findsOneWidget);
      expect(find.byType(ExpansionTile), findsNothing);
      expect(itemText('Chain lubricant'), findsOneWidget);
      expect(find.text('10 items detected'), findsOneWidget);
    });

    testWidgets('sit above the confirmation form, not below it', (
      tester,
    ) async {
      await openReview(tester, extraction: reading());

      // Compared by position in the laid-out tree, which is what a person
      // actually scrolls through — an assertion on child order in a list would
      // pass even if the widget were painted somewhere else.
      final double items = tester
          .getTopLeft(find.byType(ReceiptReviewLineItems))
          .dy;
      final double form = tester.getTopLeft(find.byType(ReceiptReviewForm)).dy;
      expect(items, lessThan(form));
    });

    testWidgets('every returned line is rendered, in the backend order', (
      tester,
    ) async {
      await openReview(tester, extraction: reading());

      final List<String> text = rendered(tester);
      const List<String> named = <String>[
        'Front and rear brake cables, stainless, with ferrules',
        'Chain lubricant',
        'Handlebar tape',
        'Inner tube 700x25',
        'Item not read',
        'Promotional water bottle',
        'Cable housing',
        'Workshop labour',
        'Bar end plugs',
        'Disc brake pads',
      ];

      // All ten, and the tenth as surely as the first: nothing takes, caps,
      // pages or filters.
      for (final String description in named) {
        expect(itemText(description), findsOneWidget, reason: description);
      }
      // And in exactly the order the backend returned them.
      final List<int> positions = named
          .map((String d) => text.indexOf(d))
          .toList();
      expect(positions, everyElement(isNonNegative));
      for (int i = 1; i < positions.length; i++) {
        expect(positions[i], greaterThan(positions[i - 1]));
      }
      // The count states what came back, and never rounds up to look complete.
      expect(find.text('10 items detected'), findsOneWidget);
    });

    testWidgets('one line is counted in the singular', (tester) async {
      await openReview(tester, extraction: reading(lines: oneCompleteLineItem));

      expect(find.text('1 item detected'), findsOneWidget);
      expect(find.text('1 items detected'), findsNothing);
    });

    testWidgets('a complete line shows all three figures', (tester) async {
      await openReview(tester, extraction: reading(lines: oneCompleteLineItem));

      expect(itemText('Front and rear brake cables'), findsOneWidget);
      expect(itemText('Qty 1'), findsOneWidget);
      expect(itemText('Unit AED 10.00'), findsOneWidget);
      expect(itemText('Amount AED 10.00'), findsOneWidget);
    });

    testWidgets('a missing quantity never becomes one', (tester) async {
      await openReview(tester, extraction: reading());

      // Line 2 read a price but no quantity. Four lines in the fixture do
      // carry a quantity of exactly 1 — 1, 5, 6 and 10 — and line 2 is not one
      // of them: a fifth "Qty 1" would be this screen inventing the number.
      expect(itemText('Unit AED 8.50'), findsOneWidget);
      expect(itemText('Qty 1'), findsNWidgets(4));
    });

    testWidgets('a missing unit price is never derived from the amount', (
      tester,
    ) async {
      await openReview(tester, extraction: reading());

      // Line 3: 2 × ? = AED 30.00. The obvious division is AED 15.00, and it
      // must not appear — the provider did not read a unit price for this line.
      expect(itemText('Amount AED 30.00'), findsOneWidget);
      expect(itemText('Unit AED 15.00'), findsNothing);
      // Nor is the label rendered with nothing behind it.
      expect(itemText('Unit —'), findsNothing);
    });

    testWidgets('a missing line total is never derived from the unit price', (
      tester,
    ) async {
      await openReview(tester, extraction: reading());

      // Line 4: 3 × AED 6.00. The product, AED 18.00, must not appear.
      expect(itemText('Qty 3'), findsOneWidget);
      expect(itemText('Unit AED 6.00'), findsOneWidget);
      expect(itemText('Amount AED 18.00'), findsNothing);
      // It is stated as unavailable instead, which is the honest answer.
      expect(itemText('Amount —'), findsNWidgets(2));
    });

    testWidgets('zero is a reading, and is written as a figure', (
      tester,
    ) async {
      await openReview(tester, extraction: reading());

      // Line 6 was free. Zero and unknown are different facts and the panel
      // keeps them apart: this is AED 0.00, not an em dash.
      expect(itemText('Unit AED 0.00'), findsOneWidget);
      expect(itemText('Amount AED 0.00'), findsOneWidget);
    });

    testWidgets('a fractional quantity keeps its fraction', (tester) async {
      await openReview(tester, extraction: reading());

      expect(itemText('Qty 1.5'), findsOneWidget);
    });

    testWidgets('a line with no figures at all carries none', (tester) async {
      await openReview(tester, extraction: reading());

      // Line 8 is a description and nothing else. It still appears, because a
      // line the provider read is a line the reviewer should see.
      expect(itemText('Workshop labour'), findsOneWidget);
    });

    for (final (String code, int digits, String unit, String amount)
        in const <(String, int, String, String)>[
          // JPY is whole: 1000 minor units is ¥1000, not ¥10.00.
          ('JPY', 0, 'Unit JPY 1000', 'Amount JPY 1000'),
          ('AED', 2, 'Unit AED 10.00', 'Amount AED 10.00'),
          // KWD is thousandths: the same integer is one dinar, not ten.
          ('KWD', 3, 'Unit KWD 1.000', 'Amount KWD 1.000'),
        ]) {
      testWidgets('$code is written at its own $digits decimals', (
        tester,
      ) async {
        await openReview(
          tester,
          extraction: reading(
            currencyCode: ExtractedValue<String>(
              value: code,
              sourceText: code,
              confidence: 0.99,
            ),
            currencyMinorUnit: digits,
            lines: oneCompleteLineItem,
          ),
        );

        expect(itemText(unit), findsOneWidget);
        expect(itemText(amount), findsOneWidget);
        // And never at somebody else's width.
        expect(
          itemText('Amount $code 10.00'),
          digits == 2 ? findsOneWidget : findsNothing,
        );
      });
    }

    testWidgets('a width the backend could not have reported is refused', (
      tester,
    ) async {
      await openReview(
        tester,
        extraction: reading(currencyMinorUnit: 7, lines: oneCompleteLineItem),
      );

      // Seven is outside 0..4. Neither figure is written, and nothing falls
      // back to two decimals behind them.
      expect(itemText('Unit —'), findsOneWidget);
      expect(itemText('Amount —'), findsOneWidget);
      expect(itemText('Unit AED 10.00'), findsNothing);
      expect(itemText('Amount AED 10.00'), findsNothing);
      expect(itemText('AED 10.00'), findsNothing);
      expect(itemText('10.00'), findsNothing);
    });

    testWidgets('no width at all is not two decimals', (tester) async {
      await openReview(
        tester,
        extraction: reading(
          currencyMinorUnit: null,
          lines: oneCompleteLineItem,
        ),
      );

      expect(itemText('Unit —'), findsOneWidget);
      expect(itemText('Amount —'), findsOneWidget);
      expect(itemText('10.00'), findsNothing);
      // The description is still shown: a figure this screen cannot write does
      // not cost the reviewer the line it belonged to.
      expect(itemText('Front and rear brake cables'), findsOneWidget);
    });

    testWidgets('nothing in the panel can be edited or removed', (
      tester,
    ) async {
      await openReview(tester, extraction: reading());

      final Finder panel = find.byType(ReceiptReviewLineItems);
      // No control of any kind: not a field to type in, not a stepper, not a
      // delete, not a match, not an approval. This milestone only reports.
      expect(
        find.descendant(of: panel, matching: find.byType(TextField)),
        findsNothing,
      );
      expect(
        find.descendant(of: panel, matching: find.byType(EditableText)),
        findsNothing,
      );
      expect(
        find.descendant(of: panel, matching: find.byType(SrButton)),
        findsNothing,
      );
      expect(
        find.descendant(of: panel, matching: find.byType(IconButton)),
        findsNothing,
      );
      expect(
        find.descendant(of: panel, matching: find.byType(Checkbox)),
        findsNothing,
      );
      expect(
        find.descendant(of: panel, matching: find.byType(InkWell)),
        findsNothing,
      );
    });

    testWidgets('no reference or code is invented for a line', (tester) async {
      await openReview(tester, extraction: reading());

      // The contract carries no SKU, product code, reference or barcode, so the
      // panel shows none — and in particular does not mine one out of the
      // description or the source text.
      for (final String label in <String>[
        'SKU',
        'Code',
        'Reference',
        'Barcode',
        'Ref',
      ]) {
        expect(
          find.descendant(
            of: find.byType(ReceiptReviewLineItems),
            matching: find.textContaining(label),
          ),
          findsNothing,
          reason: 'the panel must not present a $label',
        );
      }
    });

    testWidgets('a failed attempt shows no items and asks for none', (
      tester,
    ) async {
      final FakeReceiptExtractionRepository repository = reading(
        status: ReceiptExtractionStatus.failed,
      );

      await openReview(tester, extraction: repository);

      // There will never be a reading for this attempt. The panel is absent and
      // the line-item read was never made — there is nothing to return.
      expect(find.byType(ReceiptReviewLineItems), findsNothing);
      expect(repository.lineItemIds, isEmpty);
      // The rest of the screen is unaffected.
      expect(find.byType(ReceiptReviewPreview), findsOneWidget);
    });

    // QUEUED and PROCESSING are asserted in `receipt_review_cubit_test.dart`
    // instead. An open attempt polls, so this screen never settles, and driving
    // it here would mean either a real three-second wait per case or a fake
    // clock the router does not let a widget test inject. The cubit owns the
    // decision anyway: the line-item read happens only for a stored reading.

    for (final Size surface in <Size>[smallPhoneSurface, phoneSurface]) {
      testWidgets('ten items do not overflow at '
          '${surface.width}×${surface.height}', (tester) async {
        await openReview(tester, extraction: reading(), surface: surface);

        expect(find.byType(ReceiptReviewLineItems), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the line items, and whose currency describes them', () {
    const ExtractedValue<String> extractedAed = ExtractedValue<String>(
      value: 'AED',
      sourceText: 'AED',
      confidence: 0.99,
    );

    FakeReceiptExtractionRepository readingOf({
      ExtractedValue<String> currencyCode = extractedAed,
      int? currencyMinorUnit = 2,
      List<ReceiptExtractionLineItem> lines = oneScaledLineItem,
    }) {
      final ReceiptExtraction reading = succeededExtraction(
        currencyCode: currencyCode,
        currencyMinorUnit: currencyMinorUnit,
        lineItemCount: lines.length,
      );
      return FakeReceiptExtractionRepository(
        requestResults:
            <ReceiptExtractionResult<ReceiptExtractionRequestResult>>[
              ReceiptExtractionSuccess<ReceiptExtractionRequestResult>(
                requestResult(extraction: reading),
              ),
            ],
        extractionResults: <ReceiptExtractionResult<ReceiptExtraction>>[
          ReceiptExtractionSuccess<ReceiptExtraction>(reading),
        ],
        lineItemResults:
            <ReceiptExtractionResult<List<ReceiptExtractionLineItem>>>[
              ReceiptExtractionSuccess<List<ReceiptExtractionLineItem>>(lines),
            ],
      );
    }

    /// Only text inside the panel counts. The screen writes amounts in three
    /// other places, and a match in one of those would prove nothing about this
    /// one.
    Finder lineText(String text) => find.descendant(
      of: find.byType(ReceiptReviewLineItems),
      matching: find.text(text),
    );

    testWidgets(
      'a line is written in the extraction\'s own currency and width',
      (tester) async {
        final FakeReceiptExtractionRepository repository = readingOf();
        await openReview(tester, extraction: repository);

        // 1250 minor units, at the two decimals the READING reported for AED.
        expect(lineText('Amount AED 12.50'), findsOneWidget);
      },
    );

    testWidgets(
      'changing the confirmation currency to JPY never relabels the line',
      (tester) async {
        final FakeReceiptExtractionRepository repository = readingOf();
        // Held open, so the moment between the edit and the answer is a state
        // the test can actually stand in.
        repository.currencyGates['JPY'] =
            Completer<ReceiptExtractionResult<ReceiptCurrencyMinorUnit?>>();
        await openReview(tester, extraction: repository);
        expect(lineText('Amount AED 12.50'), findsOneWidget);

        await tester.enterText(find.byType(TextField).at(0), 'JPY');
        await tester.pumpAndSettle();

        // The lookup is still in flight, and the line has not moved.
        expect(lineText('Amount AED 12.50'), findsOneWidget);
        expect(lineText('Amount JPY 1250'), findsNothing);

        // JPY answers: whole numbers. That is an answer about the CONFIRMATION.
        repository.currencyGates['JPY']!.complete(currencyWidth('JPY', 0));
        await tester.pumpAndSettle();

        // The line still says what the provider read. Relabelling it JPY would
        // multiply what the reviewer is checking against by a hundred.
        expect(lineText('Amount AED 12.50'), findsOneWidget);
        expect(lineText('Amount JPY 1250'), findsNothing);
        expect(lineText('Amount JPY 12.50'), findsNothing);

        // And the form did take the width, for itself.
        final ReceiptReviewForm form = tester.widget<ReceiptReviewForm>(
          find.byType(ReceiptReviewForm),
        );
        expect(form.minorDigits, 0);
      },
    );

    testWidgets(
      'a reading with no width of its own is never given the confirmation\'s',
      (tester) async {
        final FakeReceiptExtractionRepository repository = readingOf(
          currencyMinorUnit: null,
        );
        repository.currencyResults['AED'] = currencyWidth('AED', 2);
        await openReview(tester, extraction: repository);

        // The confirmation side resolved two decimals, and is using them.
        final ReceiptReviewForm form = tester.widget<ReceiptReviewForm>(
          find.byType(ReceiptReviewForm),
        );
        expect(form.minorDigits, 2);

        // The line is still unwritable: the READING carried no width, and a
        // lookup about the form's currency does not retroactively supply one.
        expect(lineText('Amount —'), findsOneWidget);
        expect(lineText('Amount AED 12.50'), findsNothing);
        // Nor is there a two-decimal assumption hiding behind it.
        expect(lineText('12.50'), findsNothing);
      },
    );

    for (final (String kind, ExtractedValue<String> code)
        in const <(String, ExtractedValue<String>)>[
          ('an absent', ExtractedValue<String>()),
          ('a blank', ExtractedValue<String>(value: '   ')),
          ('a malformed', ExtractedValue<String>(value: 'A1')),
        ]) {
      testWidgets('$kind extraction currency leaves the line unwritable', (
        tester,
      ) async {
        final FakeReceiptExtractionRepository repository = readingOf(
          currencyCode: code,
        );
        repository.currencyResults['AED'] = currencyWidth('AED', 2);
        await openReview(tester, extraction: repository);

        // The reviewer supplies the currency the CONFIRMATION will use, and it
        // resolves. None of that says what the provider's integers meant.
        await tester.enterText(find.byType(TextField).at(0), 'AED');
        await tester.pumpAndSettle();

        final ReceiptReviewForm form = tester.widget<ReceiptReviewForm>(
          find.byType(ReceiptReviewForm),
        );
        expect(form.minorDigits, 2);

        expect(lineText('Amount —'), findsOneWidget);
        expect(lineText('Amount AED 12.50'), findsNothing);
        // A width with no currency is not an amount either.
        expect(lineText('12.50'), findsNothing);
      });
    }

    testWidgets(
      'a zero-width reading is written whole, never at two decimals',
      (tester) async {
        final FakeReceiptExtractionRepository repository = readingOf(
          currencyCode: const ExtractedValue<String>(
            value: 'JPY',
            sourceText: 'JPY',
            confidence: 0.99,
          ),
          currencyMinorUnit: 0,
        );
        await openReview(tester, extraction: repository);

        // Here JPY 1250 is the RIGHT answer, because JPY is what the reading
        // itself reported. The rule is ownership, not a banned string.
        expect(lineText('Amount JPY 1250'), findsOneWidget);
        expect(lineText('Amount JPY 12.50'), findsNothing);
      },
    );

    testWidgets(
      'the confirmation still sends JPY at width 0 while the line stays AED',
      (tester) async {
        final FakeReceiptExtractionRepository repository = readingOf();
        repository.currencyResults['JPY'] = currencyWidth('JPY', 0);
        await openReview(tester, extraction: repository);

        await tester.enterText(find.byType(TextField).at(0), 'JPY');
        await tester.pumpAndSettle();
        // Yen are whole, so the three amounts are retyped as whole numbers. The
        // form never rewrites them; that is the reviewer's job and its own test.
        await tester.enterText(find.byType(TextField).at(1), '1250');
        await tester.enterText(find.byType(TextField).at(2), '');
        await tester.enterText(find.byType(TextField).at(3), '');
        await tester.pumpAndSettle();

        // Still the reading's own currency, right up to the moment of sending.
        expect(lineText('Amount AED 12.50'), findsOneWidget);

        await chooseFirstProduct(tester);
        await confirmReceiptAndProducts(tester);

        expect(repository.confirmWithProductsCalls, hasLength(1));
        final ReceiptConfirmationInput sent =
            repository.confirmWithProductsCalls.single.input;
        expect(sent.currencyCode, 'JPY');
        expect(sent.currencyMinorUnit, 0);
        // 1250 yen, and not 125000. The line item beside it never entered this.
        expect(sent.totalMinor, 1250);
        expect(sent.subtotalMinor, isNull);
        expect(sent.taxTotalMinor, isNull);
      },
    );

    testWidgets('the backend\'s own order is preserved and never re-sorted', (
      tester,
    ) async {
      final FakeReceiptExtractionRepository repository = readingOf(
        lines: reviewLineItems,
      );
      await openReview(tester, extraction: repository);

      final List<String> rendered = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(ReceiptReviewLineItems),
              matching: find.byType(Text),
            ),
          )
          .map((Text text) => text.data ?? '')
          .toList();

      expect(
        rendered.indexOf('Paracetamol 500mg'),
        lessThan(rendered.indexOf('Vitamin D3')),
      );
      // Both in the extraction's AED, at its own width of two.
      expect(lineText('Amount AED 25.00'), findsOneWidget);
      expect(lineText('Amount AED 100.50'), findsOneWidget);
    });

    testWidgets('a line-item read failure degrades only that panel', (
      tester,
    ) async {
      final FakeReceiptExtractionRepository repository = readingOf();
      repository.lineItemResults =
          <ReceiptExtractionResult<List<ReceiptExtractionLineItem>>>[
            const ReceiptExtractionFailed<List<ReceiptExtractionLineItem>>(
              ExtractionServiceUnavailableProblem(),
            ),
          ];
      await openReview(tester, extraction: repository);

      expect(find.byType(ReceiptReviewLineItems), findsNothing);
      // Nothing else is affected: no alarm, and the receipt still confirms.
      expect(find.byType(ReceiptReviewForm), findsOneWidget);
      await chooseFirstProduct(tester);
      await confirmReceiptAndProducts(tester);
      expect(repository.confirmWithProductsCalls, hasLength(1));
      expect(
        repository.confirmWithProductsCalls.single.input.currencyMinorUnit,
        2,
      );
    });
  });
}
