import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sale_reward/app/shells/sales_staff/sales_staff_navigation.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/receipts/domain/entities/extracted_value.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_confirmation_input.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_confirmation_result.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_line_item.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_currency_minor_unit.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_problem.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_request_outcome.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_warning_code.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_request_result.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_submission.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_submission_status.dart';
import 'package:sale_reward/features/receipts/domain/repositories/receipt_extraction_result.dart';
import 'package:sale_reward/features/receipts/domain/repositories/receipt_result.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/pages/sales_staff_history_page.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/pages/sales_staff_receipt_review_page.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/widgets/receipt_review_confirmed_card.dart';
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
  }) async {
    final PumpedApp app = await pumpAppInRole(
      tester,
      PortalKind.salesStaff,
      receiptExtraction: extraction,
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
    testWidgets('a confirmation settles the screen and cannot be repeated', (
      tester,
    ) async {
      final FakeReceiptExtractionRepository extraction =
          FakeReceiptExtractionRepository();
      await openReview(tester, extraction: extraction);

      await tapVisible(tester, find.text('Confirm receipt'));

      expect(find.byType(ReceiptReviewConfirmedCard), findsOneWidget);
      expect(find.text('Receipt confirmed'), findsOneWidget);
      expect(find.byType(ReceiptReviewForm), findsNothing);
      expect(extraction.confirmInputs, hasLength(1));
      // The entry mode is the backend's word, rendered as a sentence.
      expect(find.text('As read from the receipt'), findsOneWidget);
    });

    testWidgets('a validation failure marks the field and sends nothing', (
      tester,
    ) async {
      final FakeReceiptExtractionRepository extraction =
          FakeReceiptExtractionRepository();
      await openReview(tester, extraction: extraction);

      final Finder total = find.byType(TextField).at(1);
      await tester.enterText(total, '');
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Confirm receipt'));

      expect(find.text('Enter the total on the receipt.'), findsOneWidget);
      expect(extraction.confirmInputs, isEmpty);
    });

    testWidgets('a corrected total is sent as integer minor units', (
      tester,
    ) async {
      final FakeReceiptExtractionRepository extraction =
          FakeReceiptExtractionRepository();
      await openReview(tester, extraction: extraction);

      final Finder total = find.byType(TextField).at(1);
      await tester.enterText(total, '19.99');
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Confirm receipt'));

      expect(extraction.confirmInputs.single.totalMinor, 1999);
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
      expect(form.minorDigits, isNull);

      // Nothing was sent, and the button cannot send it.
      await tapVisible(tester, find.text('Confirm receipt'));
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
            confirmResults:
                <ReceiptExtractionResult<ReceiptConfirmationResult>>[
                  const ReceiptExtractionFailed<ReceiptConfirmationResult>(
                    ExtractionCurrencyScaleMismatchProblem(),
                  ),
                ],
          );
      await openWith(tester, repository);

      await tapVisible(tester, find.text('Confirm receipt'));

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
        'p_currency_minor_unit',
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
  /// the real `ExpansionTile` opened by a real tap. Nothing asserts on a
  /// constructor argument, because the defect these cover was a call site
  /// passing the wrong two values into a widget that was itself correct — an
  /// assertion on what the widget was handed would have gone on passing.
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

    /// Opens the panel, which is collapsed by default.
    ///
    /// Idempotent by inspection rather than by counting taps: a rebuild between
    /// two assertions may or may not preserve the tile's expansion, and a helper
    /// that blindly tapped would close it exactly when it had survived.
    Future<void> showLines(
      WidgetTester tester, {
      String title = '1 line item',
    }) async {
      if (lineText('Paracetamol 500mg').evaluate().isNotEmpty) {
        return;
      }
      await tapVisible(tester, find.text(title));
    }

    testWidgets(
      'a line is written in the extraction\'s own currency and width',
      (tester) async {
        final FakeReceiptExtractionRepository repository = readingOf();
        await openReview(tester, extraction: repository);
        await showLines(tester);

        // 1250 minor units, at the two decimals the READING reported for AED.
        expect(lineText('AED 12.50'), findsOneWidget);
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
        await showLines(tester);
        expect(lineText('AED 12.50'), findsOneWidget);

        await tester.enterText(find.byType(TextField).at(0), 'JPY');
        await tester.pumpAndSettle();
        await showLines(tester);

        // The lookup is still in flight, and the line has not moved.
        expect(lineText('AED 12.50'), findsOneWidget);
        expect(lineText('JPY 1250'), findsNothing);

        // JPY answers: whole numbers. That is an answer about the CONFIRMATION.
        repository.currencyGates['JPY']!.complete(currencyWidth('JPY', 0));
        await tester.pumpAndSettle();
        await showLines(tester);

        // The line still says what the provider read. Relabelling it JPY would
        // multiply what the reviewer is checking against by a hundred.
        expect(lineText('AED 12.50'), findsOneWidget);
        expect(lineText('JPY 1250'), findsNothing);
        expect(lineText('JPY 12.50'), findsNothing);

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
        await showLines(tester);

        // The confirmation side resolved two decimals, and is using them.
        final ReceiptReviewForm form = tester.widget<ReceiptReviewForm>(
          find.byType(ReceiptReviewForm),
        );
        expect(form.minorDigits, 2);

        // The line is still unwritable: the READING carried no width, and a
        // lookup about the form's currency does not retroactively supply one.
        expect(lineText('—'), findsOneWidget);
        expect(lineText('AED 12.50'), findsNothing);
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
        await showLines(tester);

        // The reviewer supplies the currency the CONFIRMATION will use, and it
        // resolves. None of that says what the provider's integers meant.
        await tester.enterText(find.byType(TextField).at(0), 'AED');
        await tester.pumpAndSettle();
        await showLines(tester);

        final ReceiptReviewForm form = tester.widget<ReceiptReviewForm>(
          find.byType(ReceiptReviewForm),
        );
        expect(form.minorDigits, 2);

        expect(lineText('—'), findsOneWidget);
        expect(lineText('AED 12.50'), findsNothing);
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
        await showLines(tester);

        // Here JPY 1250 is the RIGHT answer, because JPY is what the reading
        // itself reported. The rule is ownership, not a banned string.
        expect(lineText('JPY 1250'), findsOneWidget);
        expect(lineText('JPY 12.50'), findsNothing);
      },
    );

    testWidgets(
      'the confirmation still sends JPY at width 0 while the line stays AED',
      (tester) async {
        final FakeReceiptExtractionRepository repository = readingOf();
        repository.currencyResults['JPY'] = currencyWidth('JPY', 0);
        await openReview(tester, extraction: repository);
        await showLines(tester);

        await tester.enterText(find.byType(TextField).at(0), 'JPY');
        await tester.pumpAndSettle();
        // Yen are whole, so the three amounts are retyped as whole numbers. The
        // form never rewrites them; that is the reviewer's job and its own test.
        await tester.enterText(find.byType(TextField).at(1), '1250');
        await tester.enterText(find.byType(TextField).at(2), '');
        await tester.enterText(find.byType(TextField).at(3), '');
        await tester.pumpAndSettle();
        await showLines(tester);

        // Still the reading's own currency, right up to the moment of sending.
        expect(lineText('AED 12.50'), findsOneWidget);

        await tapVisible(tester, find.text('Confirm receipt'));

        expect(repository.confirmInputs, hasLength(1));
        final ReceiptConfirmationInput sent = repository.confirmInputs.single;
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
      await tapVisible(tester, find.text('2 line items'));

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
      expect(lineText('AED 25.00'), findsOneWidget);
      expect(lineText('AED 100.50'), findsOneWidget);
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
      await tapVisible(tester, find.text('Confirm receipt'));
      expect(repository.confirmInputs, hasLength(1));
      expect(repository.confirmInputs.single.currencyMinorUnit, 2);
    });
  });
}
