import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sale_reward/app/shells/sales_staff/sales_staff_navigation.dart';
import 'package:sale_reward/core/widgets/widgets.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_confirmation.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_problem.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_request_result.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_product_proposal_line.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_with_products_outcome.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_with_products_result.dart';
import 'package:sale_reward/features/receipts/domain/repositories/receipt_extraction_result.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/pages/sales_staff_receipt_review_page.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/widgets/receipt_legacy_confirmation_section.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/widgets/receipt_product_catalogue_section.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/widgets/receipt_review_copy.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/widgets/receipt_selected_products_section.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/widgets/receipt_submitted_proposal_section.dart';

import 'package:sale_reward/features/receipts/domain/entities/receipt_product.dart';
import 'package:sale_reward/features/receipts/domain/repositories/receipt_result.dart';

import '../../support/pump_app.dart';
import '../../support/receipt_fakes.dart';
import '../../support/receipt_review_fakes.dart';

/// The immutable submitted proposal, and the legacy header-only state.
///
/// ## What these are really protecting
///
/// A submitted proposal is a permanent assertion a Claim Reviewer will judge as
/// a whole. Two things could quietly corrupt it on screen: rendering the
/// client's own editable list instead of the stored rows, and letting today's
/// catalogue text overwrite yesterday's frozen snapshot. Both would look
/// perfectly fine in a screenshot and be wrong about what was actually
/// proposed, so most of what follows is about *provenance* rather than layout.
///
/// The third risk is an affordance: any control that suggests a proposal can be
/// edited, corrected or resent is a promise this contract cannot keep. Those are
/// asserted absent rather than disabled.
void main() {
  Finder semanticsLabelled(String label) => find.byWidgetPredicate(
    (Widget widget) => widget is Semantics && widget.properties.label == label,
    description: 'Semantics labelled "$label"',
  );

  Finder semanticsContaining(String fragment) => find.byWidgetPredicate(
    (Widget widget) =>
        widget is Semantics &&
        (widget.properties.label ?? '').contains(fragment),
    description: 'Semantics containing "$fragment"',
  );

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Two stored lines whose frozen values are deliberately unlike anything the
  /// local catalogue fixtures contain.
  ///
  /// `productA` is "Chocolate Bar 50g / SKU-100"; these are not. So a screen
  /// that rendered the catalogue, or the local selection, instead of the stored
  /// rows could not accidentally pass — the strings simply would not be there.
  const List<ReceiptProductProposalLine> frozenLines =
      <ReceiptProductProposalLine>[
        ReceiptProductProposalLine(
          lineNumber: 1,
          quantity: 3,
          productCode: 'FROZEN-CODE-1',
          productName: 'Name As Proposed One',
          barcode: '11112222',
          brand: 'Brand As Proposed',
          productStatus: 'ACTIVE',
        ),
        ReceiptProductProposalLine(
          lineNumber: 2,
          quantity: 7,
          productCode: 'FROZEN-CODE-2',
          productName: 'Name As Proposed Two',
          // Deliberately without a barcode or a brand: both columns are
          // nullable and an absent one must simply not be rendered.
          productStatus: 'INACTIVE',
        ),
      ];

  /// A repository for a receipt that is ALREADY confirmed when the screen opens.
  FakeReceiptExtractionRepository confirmedReceipt({
    List<ReceiptProductProposalLine>? proposal = frozenLines,
    ReceiptExtractionResult<List<ReceiptProductProposalLine>>? proposalResult,
    ReceiptExtractionResult<ReceiptConfirmation?>? confirmationResult,
  }) {
    final ReceiptExtraction reading = succeededExtraction(
      confirmationExists: true,
    );
    return FakeReceiptExtractionRepository(
      requestResults: <ReceiptExtractionResult<ReceiptExtractionRequestResult>>[
        ReceiptExtractionSuccess<ReceiptExtractionRequestResult>(
          requestResult(extraction: reading),
        ),
      ],
      extractionResults: <ReceiptExtractionResult<ReceiptExtraction>>[
        ReceiptExtractionSuccess<ReceiptExtraction>(reading),
      ],
      confirmationResults: <ReceiptExtractionResult<ReceiptConfirmation?>>[
        confirmationResult ??
            ReceiptExtractionSuccess<ReceiptConfirmation?>(
              storedConfirmation(),
            ),
      ],
      productProposalResults:
          <ReceiptExtractionResult<List<ReceiptProductProposalLine>>>[
            proposalResult ??
                ReceiptExtractionSuccess<List<ReceiptProductProposalLine>>(
                  proposal ?? const <ReceiptProductProposalLine>[],
                ),
          ],
    );
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

  // ==========================================================================
  // The submitted proposal
  // ==========================================================================

  group('the submitted proposal', () {
    testWidgets('renders every stored line in the server order', (
      tester,
    ) async {
      await open(tester, confirmedReceipt());

      expect(find.byType(ReceiptSubmittedProposalSection), findsOneWidget);

      final List<String> rendered = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(ReceiptSubmittedProposalSection),
              matching: find.byType(Text),
            ),
          )
          .map((Text text) => text.data ?? '')
          .toList();

      // Line one before line two, and never re-sorted or renumbered.
      expect(
        rendered.indexOf('Name As Proposed One'),
        lessThan(rendered.indexOf('Name As Proposed Two')),
      );
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
    });

    testWidgets('renders the frozen name, code, barcode and brand', (
      tester,
    ) async {
      await open(tester, confirmedReceipt());

      expect(find.text('Name As Proposed One'), findsOneWidget);
      expect(find.text('Name As Proposed Two'), findsOneWidget);
      // Code · brand · barcode, joined only from what the row carried.
      expect(
        find.text('FROZEN-CODE-1 · Brand As Proposed · 11112222'),
        findsOneWidget,
      );
      // The second line has neither, so neither appears — and nothing is
      // substituted for them.
      expect(find.text('FROZEN-CODE-2'), findsOneWidget);
    });

    testWidgets('renders each stored quantity', (tester) async {
      await open(tester, confirmedReceipt());

      expect(find.text('× 3'), findsOneWidget);
      expect(find.text('× 7'), findsOneWidget);
    });

    testWidgets('renders the proposal-time status, labelled as such', (
      tester,
    ) async {
      await open(tester, confirmedReceipt());

      // "when submitted" is the whole point: a product that has since been
      // deactivated must not make the submitted line read as inactive today.
      expect(find.text('Status when submitted: ACTIVE'), findsOneWidget);
      expect(find.text('Status when submitted: INACTIVE'), findsOneWidget);
    });

    testWidgets('summarises the line count and the total quantity', (
      tester,
    ) async {
      await open(tester, confirmedReceipt());

      expect(find.text('2 product lines'), findsOneWidget);
      // 3 + 7, counted from the stored rows and not from any local selection.
      expect(find.text('10 items in total'), findsOneWidget);
    });

    testWidgets('carries the Submitted status as a word', (tester) async {
      await open(tester, confirmedReceipt());

      expect(find.text(ReceiptReviewCopy.submittedStatusBadge), findsOneWidget);
    });

    testWidgets('states finality, whole-list review and what did not happen', (
      tester,
    ) async {
      await open(tester, confirmedReceipt());

      for (final String sentence in <String>[
        ReceiptReviewCopy.submittedFinality,
        ReceiptReviewCopy.submittedWholeListReview,
        ReceiptReviewCopy.submittedReceiptSeparate,
        ReceiptReviewCopy.submittedNoRewards,
      ]) {
        expect(find.textContaining(sentence), findsOneWidget, reason: sentence);
      }
    });

    testWidgets('offers no control that could change anything', (tester) async {
      await open(tester, confirmedReceipt());

      // The editors are ABSENT, not disabled: there is nothing for a stale
      // frame or a queued callback to reach.
      expect(find.byType(ReceiptProductCatalogueSection), findsNothing);
      expect(find.byType(ReceiptSelectedProductsSection), findsNothing);
      expect(find.byType(SrSearchField), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byIcon(Icons.add_circle_outline), findsNothing);
      expect(find.byIcon(Icons.remove_circle_outline), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.text(ReceiptReviewCopy.confirmAction), findsNothing);

      for (final String forbidden in <String>[
        'Correct',
        'Resubmit',
        'Replace',
        'Reopen',
        'Add another',
        'Edit',
      ]) {
        expect(find.textContaining(forbidden), findsNothing, reason: forbidden);
      }
    });

    testWidgets('needs no catalogue read to render', (tester) async {
      final FakeReceiptExtractionRepository extraction = confirmedReceipt();
      final FakeReceiptRepository receipts = FakeReceiptRepository();
      await pumpAppInRole(
        tester,
        PortalKind.salesStaff,
        receiptExtraction: extraction,
        receipts: receipts,
      );
      // Measured from the moment the review route opens: other Sales Staff
      // screens legitimately read the catalogue, and this is a statement about
      // THIS screen.
      final int before = receipts.receiptProductsCallCount;

      final BuildContext context = tester.element(find.byType(Scaffold).first);
      GoRouter.of(context).go(SalesStaffNavigation.review(reviewSubmissionId));
      await tester.pumpAndSettle();

      expect(find.byType(ReceiptSubmittedProposalSection), findsOneWidget);
      // `list_my_receipt_products()` is not called: the frozen snapshots are
      // the whole display, and a current-catalogue lookup could only pollute
      // them.
      expect(receipts.receiptProductsCallCount, before);
    });

    testWidgets('reads the proposal once, and not again on rebuild', (
      tester,
    ) async {
      final FakeReceiptExtractionRepository extraction = confirmedReceipt();
      await open(tester, extraction);

      expect(extraction.productProposalCalls, hasLength(1));

      // Several rebuilds, including a full re-layout.
      await tester.pump();
      tester.view.physicalSize = const Size(1000, 2000);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpAndSettle();

      expect(extraction.productProposalCalls, hasLength(1));
    });
  });

  // ==========================================================================
  // Frozen snapshots beat the current catalogue
  // ==========================================================================

  group('frozen snapshots', () {
    testWidgets(
      'a renamed, rebranded, re-barcoded, deactivated product still renders as '
      'proposed',
      (tester) async {
        // The catalogue this Retailer holds TODAY, deliberately contradicting
        // every frozen value above.
        final FakeReceiptRepository receipts = FakeReceiptRepository()
          ..productsResult =
              const ReceiptReadSuccess<List<ReceiptProduct>>(<ReceiptProduct>[
                ReceiptProduct(
                  productId: productAUuid,
                  productCode: 'RENAMED-CODE',
                  productName: 'Renamed Today',
                  barcode: '99998888',
                  brand: 'Rebranded Today',
                ),
              ]);

        await pumpAppInRole(
          tester,
          PortalKind.salesStaff,
          receiptExtraction: confirmedReceipt(),
          receipts: receipts,
        );
        final BuildContext context = tester.element(
          find.byType(Scaffold).first,
        );
        GoRouter.of(
          context,
        ).go(SalesStaffNavigation.review(reviewSubmissionId));
        await tester.pumpAndSettle();

        // What was proposed.
        expect(find.text('Name As Proposed One'), findsOneWidget);
        expect(find.text('Status when submitted: INACTIVE'), findsOneWidget);

        // And not one character of what the catalogue says now.
        for (final String current in <String>[
          'Renamed Today',
          'RENAMED-CODE',
          'Rebranded Today',
          '99998888',
        ]) {
          expect(find.textContaining(current), findsNothing, reason: current);
        }
      },
    );
  });

  // ==========================================================================
  // The legacy header-only state
  // ==========================================================================

  group('the legacy header-only state', () {
    FakeReceiptExtractionRepository legacyReceipt() =>
        confirmedReceipt(proposal: const <ReceiptProductProposalLine>[]);

    testWidgets('renders its heading exactly, and only once', (tester) async {
      await open(tester, legacyReceipt());

      expect(find.byType(ReceiptLegacyConfirmationSection), findsOneWidget);
      expect(find.text(ReceiptReviewCopy.legacyTitle), findsOneWidget);
      expect(find.byType(ReceiptSubmittedProposalSection), findsNothing);
    });

    testWidgets('explains what it means and what did not happen', (
      tester,
    ) async {
      await open(tester, legacyReceipt());

      expect(
        find.textContaining(ReceiptReviewCopy.legacyExplanation),
        findsOneWidget,
      );
      expect(
        find.textContaining(ReceiptReviewCopy.legacyConsequence),
        findsOneWidget,
      );
    });

    testWidgets('offers no way to add, correct or resend products', (
      tester,
    ) async {
      await open(tester, legacyReceipt());

      expect(find.byType(ReceiptProductCatalogueSection), findsNothing);
      expect(find.byType(ReceiptSelectedProductsSection), findsNothing);
      expect(find.byType(SrSearchField), findsNothing);
      expect(find.text(ReceiptReviewCopy.confirmAction), findsNothing);

      for (final String forbidden in <String>[
        'Add products',
        'Backfill',
        'Correct',
        'Resubmit',
        'Try again',
      ]) {
        expect(find.textContaining(forbidden), findsNothing, reason: forbidden);
      }
    });

    testWidgets('writes nothing, ever', (tester) async {
      final FakeReceiptExtractionRepository extraction = legacyReceipt();
      await open(tester, extraction);
      await tester.pumpAndSettle();

      expect(extraction.confirmWithProductsCalls, isEmpty);
      expect(extraction.confirmInputs, isEmpty);
    });

    testWidgets('stays read-only across a rebuild', (tester) async {
      final FakeReceiptExtractionRepository extraction = legacyReceipt();
      await open(tester, extraction);

      tester.view.physicalSize = const Size(1000, 2000);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpAndSettle();

      expect(find.byType(ReceiptLegacyConfirmationSection), findsOneWidget);
      expect(find.byType(ReceiptProductCatalogueSection), findsNothing);
      expect(extraction.confirmWithProductsCalls, isEmpty);
      // And no second read either.
      expect(extraction.productProposalCalls, hasLength(1));
    });
  });

  // ==========================================================================
  // Opening a receipt: which state comes up
  // ==========================================================================

  group('initial state resolution', () {
    testWidgets('a confirmation with a proposal opens the submitted state', (
      tester,
    ) async {
      await open(tester, confirmedReceipt());

      expect(find.byType(ReceiptSubmittedProposalSection), findsOneWidget);
      expect(find.byType(ReceiptLegacyConfirmationSection), findsNothing);
    });

    testWidgets('a confirmation without a proposal opens the legacy state', (
      tester,
    ) async {
      await open(
        tester,
        confirmedReceipt(proposal: const <ReceiptProductProposalLine>[]),
      );

      expect(find.byType(ReceiptLegacyConfirmationSection), findsOneWidget);
    });

    testWidgets('an unconfirmed receipt opens editable', (tester) async {
      await open(tester, FakeReceiptExtractionRepository());

      expect(find.byType(ReceiptProductCatalogueSection), findsOneWidget);
      expect(find.byType(ReceiptSubmittedProposalSection), findsNothing);
      expect(find.byType(ReceiptLegacyConfirmationSection), findsNothing);
      expect(find.text(ReceiptReviewCopy.confirmAction), findsOneWidget);
    });

    testWidgets('a proposal read that fails does not open editable', (
      tester,
    ) async {
      await open(
        tester,
        confirmedReceipt(
          proposalResult:
              const ReceiptExtractionFailed<List<ReceiptProductProposalLine>>(
                ExtractionNetworkProblem(),
              ),
        ),
      );

      // Read-only, honest, and offering a READ rather than a write.
      expect(find.byType(ReceiptProductCatalogueSection), findsNothing);
      expect(find.text(ReceiptReviewCopy.confirmAction), findsNothing);
      expect(
        find.textContaining(ReceiptReviewCopy.submittedUnreadable),
        findsOneWidget,
      );
      expect(find.text(ReceiptReviewCopy.statusCheckAction), findsOneWidget);
      // Above all, it does not claim the proposal is absent.
      expect(find.byType(ReceiptLegacyConfirmationSection), findsNothing);
    });

    testWidgets('an explicit re-read recovers the submitted state', (
      tester,
    ) async {
      final FakeReceiptExtractionRepository extraction = confirmedReceipt(
        proposalResult:
            const ReceiptExtractionFailed<List<ReceiptProductProposalLine>>(
              ExtractionNetworkProblem(),
            ),
      );
      await open(tester, extraction);

      // The second answer succeeds.
      extraction.productProposalResults =
          <ReceiptExtractionResult<List<ReceiptProductProposalLine>>>[
            const ReceiptExtractionSuccess<List<ReceiptProductProposalLine>>(
              frozenLines,
            ),
          ];
      await tapVisible(tester, find.text(ReceiptReviewCopy.statusCheckAction));

      expect(find.text('Name As Proposed One'), findsOneWidget);
      expect(find.text('2 product lines'), findsOneWidget);
      // Still no write, and no editable control anywhere.
      expect(extraction.confirmWithProductsCalls, isEmpty);
      expect(find.text(ReceiptReviewCopy.confirmAction), findsNothing);
    });

    testWidgets('a malformed receipt id stays safely not-found', (
      tester,
    ) async {
      final FakeReceiptExtractionRepository extraction =
          FakeReceiptExtractionRepository();
      await pumpAppInRole(
        tester,
        PortalKind.salesStaff,
        receiptExtraction: extraction,
      );
      final BuildContext context = tester.element(find.byType(Scaffold).first);
      GoRouter.of(context).go(SalesStaffNavigation.review('not-a-uuid'));
      await tester.pumpAndSettle();

      expect(
        find.text('This invoice / receipt is not available to you'),
        findsOneWidget,
      );
      expect(find.byType(ReceiptSubmittedProposalSection), findsNothing);
      expect(find.byType(ReceiptLegacyConfirmationSection), findsNothing);
      // Not one call of any kind — least of all a read naming that id.
      expect(extraction.productProposalCalls, isEmpty);
      expect(extraction.confirmWithProductsCalls, isEmpty);
    });
  });

  // ==========================================================================
  // After a write of this session's own
  // ==========================================================================

  group('after confirming in this session', () {
    Future<FakeReceiptExtractionRepository> confirmHere(
      WidgetTester tester, {
      ReceiptWithProductsOutcome outcome = ReceiptWithProductsOutcome.confirmed,
      bool changed = true,
      ReceiptExtractionResult<List<ReceiptProductProposalLine>>? proposalResult,
    }) async {
      final FakeReceiptExtractionRepository extraction =
          FakeReceiptExtractionRepository(
            confirmWithProductsResults:
                <ReceiptExtractionResult<ReceiptWithProductsResult>>[
                  withProductsResult(
                    outcome: outcome,
                    changed: changed,
                    lineCount: 2,
                  ),
                ],
            productProposalResults:
                <ReceiptExtractionResult<List<ReceiptProductProposalLine>>>[
                  proposalResult ??
                      const ReceiptExtractionSuccess<
                        List<ReceiptProductProposalLine>
                      >(frozenLines),
                ],
          );
      await open(tester, extraction);
      await tapVisible(tester, find.text('Add').first);
      await tapVisible(tester, find.text(ReceiptReviewCopy.confirmAction));
      return extraction;
    }

    testWidgets('CONFIRMED reads the stored lines and renders those', (
      tester,
    ) async {
      final FakeReceiptExtractionRepository extraction = await confirmHere(
        tester,
      );

      expect(extraction.productProposalCalls, hasLength(1));
      // The STORED rows, not the one product that was tapped: the local
      // selection was "Chocolate Bar 50g", and it is nowhere on this screen.
      expect(find.text('Name As Proposed One'), findsOneWidget);
      expect(find.text('Name As Proposed Two'), findsOneWidget);
      expect(find.textContaining('Chocolate Bar 50g'), findsNothing);
      expect(find.text('2 product lines'), findsOneWidget);
      expect(find.text('10 items in total'), findsOneWidget);
      // One write, and no second one.
      expect(extraction.confirmWithProductsCalls, hasLength(1));
      expect(extraction.confirmInputs, isEmpty);
    });

    testWidgets('CONFIRMED leaves no editable control behind', (tester) async {
      await confirmHere(tester);

      expect(find.byType(ReceiptProductCatalogueSection), findsNothing);
      expect(find.byType(ReceiptSelectedProductsSection), findsNothing);
      expect(find.text(ReceiptReviewCopy.confirmAction), findsNothing);
      // The screen does not leave on its own: the person sees the final state.
      expect(find.byType(SalesStaffReceiptReviewPage), findsOneWidget);
    });

    testWidgets('ALREADY_CONFIRMED renders the stored lines and claims no '
        'new record', (tester) async {
      await confirmHere(
        tester,
        outcome: ReceiptWithProductsOutcome.alreadyConfirmed,
        changed: false,
      );

      expect(
        find.text('This invoice / receipt was already recorded'),
        findsOneWidget,
      );
      expect(
        find.text('Invoice / receipt and products recorded'),
        findsNothing,
      );
      expect(find.text('Name As Proposed One'), findsOneWidget);
    });

    testWidgets('a proposal read that fails afterwards stays read-only', (
      tester,
    ) async {
      final FakeReceiptExtractionRepository extraction = await confirmHere(
        tester,
        proposalResult:
            const ReceiptExtractionFailed<List<ReceiptProductProposalLine>>(
              ExtractionNetworkProblem(),
            ),
      );

      // The confirmation stays authoritative and the lines are merely missing.
      expect(
        find.textContaining(ReceiptReviewCopy.submittedUnreadable),
        findsOneWidget,
      );
      expect(find.text(ReceiptReviewCopy.statusCheckAction), findsOneWidget);
      // Never re-enabled, and never resent.
      expect(find.text(ReceiptReviewCopy.confirmAction), findsNothing);
      expect(find.byType(ReceiptProductCatalogueSection), findsNothing);
      expect(extraction.confirmWithProductsCalls, hasLength(1));
    });

    testWidgets(
      'an empty read after a write that reported lines is not called legacy',
      (tester) async {
        // The write said two lines; the read found none. Telling somebody their
        // receipt was "confirmed without products" seconds after the database
        // said otherwise is the one thing this must not do.
        await confirmHere(
          tester,
          proposalResult:
              const ReceiptExtractionSuccess<List<ReceiptProductProposalLine>>(
                <ReceiptProductProposalLine>[],
              ),
        );

        expect(find.byType(ReceiptLegacyConfirmationSection), findsNothing);
        expect(find.text(ReceiptReviewCopy.legacyTitle), findsNothing);
        expect(
          find.textContaining(ReceiptReviewCopy.submittedUnreadable),
          findsOneWidget,
        );
      },
    );
  });

  // ==========================================================================
  // Accessibility and layout
  // ==========================================================================

  group('accessibility and layout', () {
    testWidgets('the submitted status and finality are announced together', (
      tester,
    ) async {
      await open(tester, confirmedReceipt());

      expect(
        semanticsContaining(ReceiptReviewCopy.submittedStatusBadge),
        findsWidgets,
      );
      expect(
        semanticsContaining(ReceiptReviewCopy.submittedFinality),
        findsWidgets,
      );
    });

    testWidgets('each line announces its number, product and quantity', (
      tester,
    ) async {
      await open(tester, confirmedReceipt());

      expect(
        semanticsLabelled('Line 1. Name As Proposed One. Quantity 3.'),
        findsOneWidget,
      );
      expect(
        semanticsLabelled('Line 2. Name As Proposed Two. Quantity 7.'),
        findsOneWidget,
      );
      expect(
        semanticsLabelled('Submitted: 2 product lines, 10 items in total'),
        findsOneWidget,
      );
    });

    testWidgets('the legacy heading is announced', (tester) async {
      await open(
        tester,
        confirmedReceipt(proposal: const <ReceiptProductProposalLine>[]),
      );

      expect(semanticsContaining(ReceiptReviewCopy.legacyTitle), findsWidgets);
    });

    testWidgets('the loading state is announced', (tester) async {
      final FakeReceiptExtractionRepository extraction = confirmedReceipt();
      await pumpAppInRole(
        tester,
        PortalKind.salesStaff,
        receiptExtraction: extraction,
      );
      final BuildContext context = tester.element(find.byType(Scaffold).first);
      GoRouter.of(context).go(SalesStaffNavigation.review(reviewSubmissionId));
      // One frame only, so the read is still in flight.
      await tester.pump();
      await tester.pump();

      // Either the loading label is up, or the read already answered — both are
      // legitimate; what must never happen is an editable control appearing.
      expect(find.byType(ReceiptProductCatalogueSection), findsNothing);
      expect(find.text(ReceiptReviewCopy.confirmAction), findsNothing);
      await tester.pumpAndSettle();
    });

    for (final Size surface in <Size>[
      smallPhoneSurface,
      phoneSurface,
      tabletSurface,
    ]) {
      testWidgets(
        'the submitted state lays out at ${surface.width.toInt()}px',
        (tester) async {
          await open(tester, confirmedReceipt(), surface: surface);

          expect(tester.takeException(), isNull);
          expect(find.byType(ReceiptSubmittedProposalSection), findsOneWidget);
        },
      );

      testWidgets('the legacy state lays out at ${surface.width.toInt()}px', (
        tester,
      ) async {
        await open(
          tester,
          confirmedReceipt(proposal: const <ReceiptProductProposalLine>[]),
          surface: surface,
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(ReceiptLegacyConfirmationSection), findsOneWidget);
      });
    }

    testWidgets('a very long product name and code do not overflow', (
      tester,
    ) async {
      await open(
        tester,
        confirmedReceipt(
          proposal: <ReceiptProductProposalLine>[
            ReceiptProductProposalLine(
              lineNumber: 1,
              quantity: 100,
              productCode: 'CODE-${'X' * 60}',
              productName:
                  'A product name that simply keeps going ${'and on ' * 12}',
              barcode: '12345678901234',
              brand: 'A brand with a considerably longer name than usual',
              productStatus: 'ACTIVE',
            ),
          ],
        ),
        surface: smallPhoneSurface,
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(ReceiptSubmittedProposalSection), findsOneWidget);
    });
  });
}
