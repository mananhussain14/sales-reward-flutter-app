import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_confirmation.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_confirmation_input.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_problem.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_product.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_product_proposal_line.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_product_proposal_snapshot.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_product_selection.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_with_products_outcome.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_with_products_result.dart';
import 'package:sale_reward/features/receipts/domain/entities/selected_receipt_product.dart';
import 'package:sale_reward/features/receipts/domain/repositories/receipt_extraction_result.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/cubit/receipt_review_cubit.dart';
import 'package:sale_reward/features/receipts/data/models/receipt_product_lines_body.dart';
import 'package:sale_reward/features/receipts/data/models/receipt_with_products_request_body.dart';

import '../../support/receipt_fakes.dart';
import '../../support/receipt_review_fakes.dart';

/// The atomic header-and-products confirmation, at the state layer.
///
/// Everything here drives the real [ReceiptReviewCubit] over the fake
/// repository. Nothing touches a socket, a hosted RPC, a timer that runs in real
/// time, or a platform channel.
///
/// ## What these are really about
///
/// One RPC writes a confirmation, its product proposal and the Audit Log in one
/// transaction, and none of it can ever be changed afterwards. So the assertions
/// that matter are not "does the happy path work" but the four ways a client can
/// do damage: sending twice, sending the wrong thing, telling somebody it worked
/// when nobody knows, and handing back an editable form for a receipt that is
/// already immutable.
void main() {
  Future<void> instant(Duration duration) async {}

  Future<void> settle([int turns = 200]) async {
    for (int i = 0; i < turns; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  ReceiptReviewCubit build(
    FakeReceiptExtractionRepository repository, {
    Duration slowNoticeDelay = const Duration(milliseconds: 20),
  }) {
    return ReceiptReviewCubit(
      repository: repository,
      submissionId: reviewSubmissionId,
      delay: instant,
      slowNoticeDelay: slowNoticeDelay,
    );
  }

  /// A cubit sitting exactly where a person would press confirm: a successful
  /// reading, a seeded draft, and AED's width already settled from the reading
  /// itself.
  Future<ReceiptReviewCubit> ready(
    FakeReceiptExtractionRepository repository, {
    Duration slowNoticeDelay = const Duration(milliseconds: 20),
  }) async {
    final ReceiptReviewCubit cubit = build(
      repository,
      slowNoticeDelay: slowNoticeDelay,
    );
    await cubit.start();
    await settle();
    expect(cubit.state.canConfirm, isTrue);
    return cubit;
  }

  FakeReceiptExtractionRepository answering(
    ReceiptExtractionResult<ReceiptWithProductsResult> result,
  ) {
    return FakeReceiptExtractionRepository(
      confirmWithProductsResults:
          <ReceiptExtractionResult<ReceiptWithProductsResult>>[result],
    );
  }

  ReceiptProductProposalSnapshot snapshotOf(
    List<SelectedReceiptProduct> products, {
    Set<String>? catalogue,
  }) {
    return ReceiptProductProposalSnapshot(
      selection: ReceiptProductSelection(products: products),
      catalogueProductIds:
          catalogue ??
          products.map((SelectedReceiptProduct p) => p.productId).toSet(),
    );
  }

  SelectedReceiptProduct chosen(ReceiptProduct product, {int quantity = 1}) =>
      SelectedReceiptProduct.fromCatalogue(product, quantity: quantity);

  final ReceiptProductProposalSnapshot twoProducts = snapshotOf(
    <SelectedReceiptProduct>[
      chosen(productA, quantity: 3),
      chosen(productB, quantity: 2),
    ],
  );

  // ---- Validation ----------------------------------------------------------

  group('validation, before anything is sent', () {
    test('a proposal with no products is refused and sends nothing', () async {
      final FakeReceiptExtractionRepository repository = answering(
        withProductsResult(),
      );
      final ReceiptReviewCubit cubit = await ready(repository);

      await cubit.confirmWithProducts(ReceiptProductProposalSnapshot.empty);

      expect(repository.confirmWithProductsCalls, isEmpty);
      expect(repository.confirmInputs, isEmpty);
      expect(
        cubit.state.productSubmission.selectionProblem,
        ReceiptProductSelectionProblem.noProductsSelected,
      );
      // A definite, locally detected failure: the screen is editable again.
      expect(cubit.state.productSubmission.isEditable, isTrue);
      expect(cubit.state.canEditTransaction, isTrue);
      await cubit.close();
    });

    test('a quantity outside 1–100 is refused, never clamped', () async {
      final FakeReceiptExtractionRepository repository = answering(
        withProductsResult(),
      );
      final ReceiptReviewCubit cubit = await ready(repository);

      await cubit.confirmWithProducts(
        snapshotOf(<SelectedReceiptProduct>[
          const SelectedReceiptProduct(
            productId: productAUuid,
            productCode: 'SKU-100',
            productName: 'Chocolate Bar 50g',
            quantity: 250,
          ),
        ]),
      );

      expect(repository.confirmWithProductsCalls, isEmpty);
      expect(
        cubit.state.productSubmission.selectionProblem,
        ReceiptProductSelectionProblem.invalidQuantity,
      );
      await cubit.close();
    });

    test('more than fifty lines is refused, and nothing is dropped', () async {
      final FakeReceiptExtractionRepository repository = answering(
        withProductsResult(),
      );
      final ReceiptReviewCubit cubit = await ready(repository);

      final List<SelectedReceiptProduct> fiftyOne = <SelectedReceiptProduct>[
        for (int i = 0; i < maxReceiptProductLines + 1; i++)
          SelectedReceiptProduct(
            productId: 'product-$i',
            productCode: 'SKU-$i',
            productName: 'Product $i',
            quantity: 1,
          ),
      ];

      await cubit.confirmWithProducts(snapshotOf(fiftyOne));

      expect(repository.confirmWithProductsCalls, isEmpty);
      expect(
        cubit.state.productSubmission.selectionProblem,
        ReceiptProductSelectionProblem.tooManyProducts,
      );
      await cubit.close();
    });

    test('a duplicate product id is refused, and never merged', () async {
      final FakeReceiptExtractionRepository repository = answering(
        withProductsResult(),
      );
      final ReceiptReviewCubit cubit = await ready(repository);

      await cubit.confirmWithProducts(
        snapshotOf(<SelectedReceiptProduct>[
          chosen(productA, quantity: 2),
          chosen(productA, quantity: 5),
        ]),
      );

      expect(repository.confirmWithProductsCalls, isEmpty);
      expect(
        cubit.state.productSubmission.selectionProblem,
        ReceiptProductSelectionProblem.duplicateProduct,
      );
      await cubit.close();
    });

    test('a product that never came from the catalogue is refused', () async {
      final FakeReceiptExtractionRepository repository = answering(
        withProductsResult(),
      );
      final ReceiptReviewCubit cubit = await ready(repository);

      await cubit.confirmWithProducts(
        snapshotOf(
          <SelectedReceiptProduct>[chosen(productA)],
          catalogue: <String>{productBUuid},
        ),
      );

      expect(repository.confirmWithProductsCalls, isEmpty);
      expect(
        cubit.state.productSubmission.selectionProblem,
        ReceiptProductSelectionProblem.notInCatalogue,
      );
      await cubit.close();
    });

    test(
      'a transaction fault and a product fault are reported together',
      () async {
        final FakeReceiptExtractionRepository repository = answering(
          withProductsResult(),
        );
        final ReceiptReviewCubit cubit = await ready(repository);

        cubit.setTotal('');
        await cubit.confirmWithProducts(ReceiptProductProposalSnapshot.empty);

        // BOTH, in one pass. Reporting the total and then stopping would leave
        // somebody to fix it, press confirm again, and only then be told about
        // the products.
        expect(
          cubit.state.fieldProblems[ReceiptReviewField.total],
          ReceiptReviewFieldProblem.missing,
        );
        expect(
          cubit.state.productSubmission.selectionProblem,
          ReceiptProductSelectionProblem.noProductsSelected,
        );
        expect(repository.confirmWithProductsCalls, isEmpty);
        await cubit.close();
      },
    );

    test('a refusal leaves every typed transaction value intact', () async {
      final FakeReceiptExtractionRepository repository = answering(
        withProductsResult(),
      );
      final ReceiptReviewCubit cubit = await ready(repository);

      cubit.setTotal('19.99');
      cubit.setMerchantName('Corner Shop');
      cubit.setDocumentNumber('INV-77');
      await cubit.confirmWithProducts(ReceiptProductProposalSnapshot.empty);

      expect(cubit.state.draft.totalText, '19.99');
      expect(cubit.state.draft.merchantName, 'Corner Shop');
      expect(cubit.state.draft.documentNumber, 'INV-77');
      expect(cubit.state.draft.currencyCode, 'AED');
      await cubit.close();
    });

    test(
      'a transaction refusal leaves the chosen products untouched',
      () async {
        final FakeReceiptExtractionRepository repository = answering(
          withProductsResult(),
        );
        final ReceiptReviewCubit cubit = await ready(repository);

        cubit.setTotal('');
        await cubit.confirmWithProducts(twoProducts);

        // The proposal was sound; only the total was not. Nothing about the
        // products was recorded as wrong, and nothing was removed — the
        // snapshot is the caller's and this cubit never held it.
        expect(cubit.state.productSubmission.selectionProblem, isNull);
        expect(cubit.state.productSubmission.isEditable, isTrue);
        expect(twoProducts.selection.lineCount, 2);
        expect(repository.confirmWithProductsCalls, isEmpty);
        await cubit.close();
      },
    );
  });

  // ---- The atomic write ----------------------------------------------------

  group('the atomic write', () {
    test('one confirm calls the combined RPC exactly once', () async {
      final FakeReceiptExtractionRepository repository = answering(
        withProductsResult(),
      );
      final ReceiptReviewCubit cubit = await ready(repository);

      await cubit.confirmWithProducts(twoProducts);

      expect(repository.confirmWithProductsCalls, hasLength(1));
      await cubit.close();
    });

    test('the header-only confirmation is never called', () async {
      final FakeReceiptExtractionRepository repository = answering(
        withProductsResult(),
      );
      final ReceiptReviewCubit cubit = await ready(repository);

      await cubit.confirmWithProducts(twoProducts);

      // Writing the header first would create a receipt that can never acquire
      // products: the combined RPC answers CONFLICT to every attempt to top one
      // up.
      expect(repository.confirmInputs, isEmpty);
      await cubit.close();
    });

    test('products reach the repository in selection order', () async {
      final FakeReceiptExtractionRepository repository = answering(
        withProductsResult(),
      );
      final ReceiptReviewCubit cubit = await ready(repository);

      await cubit.confirmWithProducts(twoProducts);

      final ReceiptProductSelection sent =
          repository.confirmWithProductsCalls.single.selection;
      // Order IS the line numbering: the database derives `line_number` from
      // array position, so a re-sort here would be a different proposal.
      expect(
        sent.products.map((SelectedReceiptProduct p) => p.productId).toList(),
        <String>[productAUuid, productBUuid],
      );
      await cubit.close();
    });

    test('every quantity stays an int', () async {
      final FakeReceiptExtractionRepository repository = answering(
        withProductsResult(),
      );
      final ReceiptReviewCubit cubit = await ready(repository);

      await cubit.confirmWithProducts(twoProducts);

      for (final SelectedReceiptProduct product
          in repository.confirmWithProductsCalls.single.selection.products) {
        expect(product.quantity, isA<int>());
        expect(product.quantity, isNot(isA<double>()));
      }
      expect(
        repository.confirmWithProductsCalls.single.selection.products
            .map((SelectedReceiptProduct p) => p.quantity)
            .toList(),
        <int>[3, 2],
      );
      await cubit.close();
    });

    test('the serialized lines carry product_id and quantity only', () async {
      final FakeReceiptExtractionRepository repository = answering(
        withProductsResult(),
      );
      final ReceiptReviewCubit cubit = await ready(repository);

      await cubit.confirmWithProducts(twoProducts);

      final List<Map<String, Object>> lines = buildReceiptProductLines(
        repository.confirmWithProductsCalls.single.selection,
      );
      expect(lines, hasLength(2));
      for (final Map<String, Object> line in lines) {
        expect(line.keys.toSet(), receiptProductLineKeys);
      }
      // Named individually as well, because a set comparison would pass if both
      // sides gained the same forbidden key.
      for (final String forbidden in <String>[
        'product_name',
        'product_code',
        'barcode',
        'brand',
        'product_status',
        'line_number',
        'vendor_id',
        'retailer_id',
        'shop_id',
        'staff_id',
        'actor_id',
        'campaign_id',
        'reward_id',
      ]) {
        expect(
          lines.any((Map<String, Object> line) => line.containsKey(forbidden)),
          isFalse,
          reason: forbidden,
        );
      }
      await cubit.close();
    });

    test('the whole request carries the eleven approved parameters', () async {
      final FakeReceiptExtractionRepository repository = answering(
        withProductsResult(),
      );
      final ReceiptReviewCubit cubit = await ready(repository);

      cubit.setTotal('19.99');
      await cubit.confirmWithProducts(twoProducts);

      final ({
        ReceiptConfirmationInput input,
        ReceiptProductSelection selection,
      })
      call = repository.confirmWithProductsCalls.single;
      final Map<String, Object?> params = buildReceiptWithProductsParams(
        call.input,
        call.selection,
      );

      expect(params.keys.toSet(), receiptWithProductsParameters);
      expect(params.keys, hasLength(11));
      await cubit.close();
    });

    test('the transaction fields map across exactly', () async {
      final FakeReceiptExtractionRepository repository = answering(
        withProductsResult(),
      );
      final ReceiptReviewCubit cubit = await ready(repository);

      cubit.setTotal('19.99');
      cubit.setSubtotal('18.00');
      cubit.setTax('1.99');
      cubit.setMerchantName('  Corner Shop  ');
      cubit.setDocumentNumber('INV-77');
      await cubit.confirmWithProducts(twoProducts);

      final ReceiptConfirmationInput sent =
          repository.confirmWithProductsCalls.single.input;
      expect(sent.submissionId, reviewSubmissionId);
      expect(sent.currencyCode, 'AED');
      expect(sent.currencyMinorUnit, 2);
      expect(sent.totalMinor, 1999);
      expect(sent.subtotalMinor, 1800);
      expect(sent.taxTotalMinor, 199);
      // Trimmed, never re-cased and never invented.
      expect(sent.merchantName, 'Corner Shop');
      expect(sent.documentNumber, 'INV-77');
      expect(sent.transactionDate.iso, '2026-07-25');
      expect(sent.transactionTime?.iso, '09:24:00');
      await cubit.close();
    });

    test('an empty optional amount is sent as null, never as zero', () async {
      final FakeReceiptExtractionRepository repository = answering(
        withProductsResult(),
      );
      final ReceiptReviewCubit cubit = await ready(repository);

      cubit.setSubtotal('');
      cubit.setTax('');
      await cubit.confirmWithProducts(twoProducts);

      final ReceiptConfirmationInput sent =
          repository.confirmWithProductsCalls.single.input;
      expect(sent.subtotalMinor, isNull);
      expect(sent.taxTotalMinor, isNull);
      await cubit.close();
    });

    test('the submitted snapshot is the one that was sent', () async {
      final FakeReceiptExtractionRepository repository = answering(
        withProductsResult(),
      );
      final ReceiptReviewCubit cubit = await ready(repository);

      await cubit.confirmWithProducts(twoProducts);

      expect(
        cubit.state.productSubmission.submitted,
        repository.confirmWithProductsCalls.single.selection,
      );
      expect(
        cubit.state.productSubmission.submittedInput,
        repository.confirmWithProductsCalls.single.input,
      );
      await cubit.close();
    });
  });

  // ---- Double submission ---------------------------------------------------

  group('double submission', () {
    /// Holds the write open so a second act genuinely overlaps the first.
    FakeReceiptExtractionRepository gated(
      Completer<ReceiptExtractionResult<ReceiptWithProductsResult>> gate,
    ) {
      return FakeReceiptExtractionRepository()..confirmWithProductsGate = gate;
    }

    test('two taps produce one repository call', () async {
      final Completer<ReceiptExtractionResult<ReceiptWithProductsResult>> gate =
          Completer<ReceiptExtractionResult<ReceiptWithProductsResult>>();
      final FakeReceiptExtractionRepository repository = gated(gate);
      final ReceiptReviewCubit cubit = await ready(repository);

      final Future<void> first = cubit.confirmWithProducts(twoProducts);
      final Future<void> second = cubit.confirmWithProducts(twoProducts);
      await settle(5);

      expect(repository.confirmWithProductsCalls, hasLength(1));

      gate.complete(withProductsResult());
      await first;
      await second;
      await settle(5);

      expect(repository.confirmWithProductsCalls, hasLength(1));
      await cubit.close();
    });

    test('a submit after settling is ignored', () async {
      final FakeReceiptExtractionRepository repository = answering(
        withProductsResult(),
      );
      final ReceiptReviewCubit cubit = await ready(repository);

      await cubit.confirmWithProducts(twoProducts);
      await cubit.confirmWithProducts(twoProducts);
      await cubit.confirmWithProducts(twoProducts);

      expect(repository.confirmWithProductsCalls, hasLength(1));
      await cubit.close();
    });

    test('the selection cannot change once the write has started', () async {
      final Completer<ReceiptExtractionResult<ReceiptWithProductsResult>> gate =
          Completer<ReceiptExtractionResult<ReceiptWithProductsResult>>();
      final FakeReceiptExtractionRepository repository = gated(gate);
      final ReceiptReviewCubit cubit = await ready(repository);

      final Future<void> pending = cubit.confirmWithProducts(twoProducts);
      await settle(5);

      // A second, different proposal offered mid-flight changes nothing: the
      // value already travelling is the one that will be written.
      await cubit.confirmWithProducts(
        snapshotOf(<SelectedReceiptProduct>[chosen(productB, quantity: 99)]),
      );
      expect(repository.confirmWithProductsCalls, hasLength(1));
      expect(
        repository.confirmWithProductsCalls.single.selection.products,
        hasLength(2),
      );
      expect(cubit.state.productSubmission.submitted, twoProducts.selection);

      gate.complete(withProductsResult());
      await pending;
      await settle(5);
      await cubit.close();
    });

    test('the transaction fields cannot change once it has started', () async {
      final Completer<ReceiptExtractionResult<ReceiptWithProductsResult>> gate =
          Completer<ReceiptExtractionResult<ReceiptWithProductsResult>>();
      final FakeReceiptExtractionRepository repository = gated(gate);
      final ReceiptReviewCubit cubit = await ready(repository);

      cubit.setTotal('19.99');
      final Future<void> pending = cubit.confirmWithProducts(twoProducts);
      await settle(5);

      expect(cubit.state.canEditTransaction, isFalse);
      cubit.setTotal('1.00');
      cubit.setMerchantName('Somewhere Else');
      expect(cubit.state.draft.totalText, '19.99');
      expect(cubit.state.draft.merchantName, 'Marina Pharmacy');
      // And the request that is travelling is untouched by either attempt.
      expect(repository.confirmWithProductsCalls.single.input.totalMinor, 1999);

      gate.complete(withProductsResult());
      await pending;
      await settle(5);
      await cubit.close();
    });

    test('closing the cubit suppresses a late reply', () async {
      final Completer<ReceiptExtractionResult<ReceiptWithProductsResult>> gate =
          Completer<ReceiptExtractionResult<ReceiptWithProductsResult>>();
      final FakeReceiptExtractionRepository repository = gated(gate);
      final ReceiptReviewCubit cubit = await ready(repository);

      final Future<void> pending = cubit.confirmWithProducts(twoProducts);
      await settle(5);
      await cubit.close();

      gate.complete(withProductsResult());
      // The emit would throw on a closed cubit if the guard were missing, so
      // completing without error is the assertion.
      await expectLater(pending, completes);
      expect(repository.confirmWithProductsCalls, hasLength(1));
    });
  });

  // ---- Pending and the slow notice -----------------------------------------

  group('pending, and the slow notice', () {
    test('pending appears immediately, and freezes both halves', () async {
      final Completer<ReceiptExtractionResult<ReceiptWithProductsResult>> gate =
          Completer<ReceiptExtractionResult<ReceiptWithProductsResult>>();
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository()..confirmWithProductsGate = gate;
      final ReceiptReviewCubit cubit = await ready(repository);

      final Future<void> pending = cubit.confirmWithProducts(twoProducts);
      await settle(3);

      expect(cubit.state.productSubmission.isPending, isTrue);
      expect(cubit.state.productSubmission.isSlow, isFalse);
      // Every mutation capability is off, and the final control cannot fire.
      expect(cubit.state.productSubmission.isEditable, isFalse);
      expect(cubit.state.canEditTransaction, isFalse);
      expect(cubit.state.canSubmitProposal, isFalse);

      gate.complete(withProductsResult());
      await pending;
      await settle(5);
      await cubit.close();
    });

    test('the slow notice appears only after the configured delay', () async {
      final Completer<ReceiptExtractionResult<ReceiptWithProductsResult>> gate =
          Completer<ReceiptExtractionResult<ReceiptWithProductsResult>>();
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository()..confirmWithProductsGate = gate;
      final ReceiptReviewCubit cubit = await ready(
        repository,
        slowNoticeDelay: const Duration(milliseconds: 40),
      );

      final Future<void> pending = cubit.confirmWithProducts(twoProducts);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(cubit.state.productSubmission.isSlow, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(cubit.state.productSubmission.isSlow, isTrue);
      // Still pending, still one call. The notice changed presentation and
      // nothing else.
      expect(cubit.state.productSubmission.isPending, isTrue);
      expect(repository.confirmWithProductsCalls, hasLength(1));

      gate.complete(withProductsResult());
      await pending;
      await settle(5);
      await cubit.close();
    });

    test(
      'the slow notice sends nothing, retries nothing, polls nothing',
      () async {
        final Completer<ReceiptExtractionResult<ReceiptWithProductsResult>>
        gate = Completer<ReceiptExtractionResult<ReceiptWithProductsResult>>();
        final FakeReceiptExtractionRepository repository =
            FakeReceiptExtractionRepository()..confirmWithProductsGate = gate;
        final ReceiptReviewCubit cubit = await ready(
          repository,
          slowNoticeDelay: const Duration(milliseconds: 10),
        );

        final int readsBefore = repository.extractionIds.length;
        final Future<void> pending = cubit.confirmWithProducts(twoProducts);
        await Future<void>.delayed(const Duration(milliseconds: 120));

        expect(cubit.state.productSubmission.isSlow, isTrue);
        // No second write, no proposal read, no confirmation read, no extra
        // extraction poll: the notice is a sentence and nothing else.
        expect(repository.confirmWithProductsCalls, hasLength(1));
        expect(repository.confirmInputs, isEmpty);
        expect(repository.productProposalCalls, isEmpty);
        expect(repository.confirmationIds, isEmpty);
        expect(repository.extractionIds.length, readsBefore);
        // And the request is still in flight — nothing cancelled or failed it.
        expect(cubit.state.productSubmission.isPending, isTrue);
        expect(cubit.state.canEditTransaction, isFalse);

        gate.complete(withProductsResult());
        await pending;
        await settle(5);
        await cubit.close();
      },
    );

    test('an authoritative answer clears the slow notice', () async {
      final FakeReceiptExtractionRepository repository = answering(
        withProductsResult(),
      );
      final ReceiptReviewCubit cubit = await ready(
        repository,
        slowNoticeDelay: const Duration(milliseconds: 10),
      );

      await cubit.confirmWithProducts(twoProducts);
      expect(cubit.state.productSubmission.isSettled, isTrue);

      // Well past the delay. The timer was cancelled, not merely ignored.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(cubit.state.productSubmission.isSlow, isFalse);
      await cubit.close();
    });

    test('closing cancels the slow notice', () async {
      final Completer<ReceiptExtractionResult<ReceiptWithProductsResult>> gate =
          Completer<ReceiptExtractionResult<ReceiptWithProductsResult>>();
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository()..confirmWithProductsGate = gate;
      final ReceiptReviewCubit cubit = await ready(
        repository,
        slowNoticeDelay: const Duration(milliseconds: 10),
      );

      final Future<void> pending = cubit.confirmWithProducts(twoProducts);
      await settle(3);
      await cubit.close();

      // A timer that fired into a closed cubit would throw here.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      gate.complete(withProductsResult());
      await expectLater(pending, completes);
    });
  });

  // ---- The three deployed outcomes -----------------------------------------

  group('CONFIRMED', () {
    Future<ReceiptReviewCubit> confirmed(
      FakeReceiptExtractionRepository repository,
    ) async {
      final ReceiptReviewCubit cubit = await ready(repository);
      await cubit.confirmWithProducts(twoProducts);
      return cubit;
    }

    test('stops pending and freezes both halves', () async {
      final FakeReceiptExtractionRepository repository = answering(
        withProductsResult(lineCount: 2),
      );
      final ReceiptReviewCubit cubit = await confirmed(repository);

      expect(cubit.state.productSubmission.isPending, isFalse);
      expect(cubit.state.productSubmission.isSettled, isTrue);
      expect(cubit.state.productSubmission.isEditable, isFalse);
      expect(cubit.state.canEditTransaction, isFalse);
      expect(cubit.state.canSubmitProposal, isFalse);
      await cubit.close();
    });

    test('stores the authoritative result', () async {
      final FakeReceiptExtractionRepository repository = answering(
        withProductsResult(lineCount: 2),
      );
      final ReceiptReviewCubit cubit = await confirmed(repository);

      final ReceiptWithProductsResult? result =
          cubit.state.productSubmission.result;
      expect(result?.outcome, ReceiptWithProductsOutcome.confirmed);
      expect(result?.changed, isTrue);
      expect(result?.lineCount, 2);
      expect(result?.confirmationId, reviewConfirmationId);
      await cubit.close();
    });

    test('issues no second call of any kind', () async {
      final FakeReceiptExtractionRepository repository = answering(
        withProductsResult(),
      );
      final ReceiptReviewCubit cubit = await confirmed(repository);

      await cubit.confirmWithProducts(twoProducts);
      // Exactly one READ follows the write — the authoritative proposal load,
      // which is what the submitted display is built from.
      expect(repository.productProposalCalls, hasLength(1));

      await cubit.checkReceiptStatus();

      // No second WRITE of any kind, and no second read either: a settled
      // write is not an uncertain one, so the status check is not even
      // offered.
      expect(repository.confirmWithProductsCalls, hasLength(1));
      expect(repository.confirmInputs, isEmpty);
      expect(cubit.state.productSubmission.needsStatusCheck, isFalse);
      expect(repository.productProposalCalls, hasLength(1));
      await cubit.close();
    });
  });

  group('ALREADY_CONFIRMED', () {
    test('is authoritative success and freezes editing', () async {
      final FakeReceiptExtractionRepository repository = answering(
        withProductsResult(
          outcome: ReceiptWithProductsOutcome.alreadyConfirmed,
          changed: false,
          lineCount: 2,
        ),
      );
      final ReceiptReviewCubit cubit = await ready(repository);

      await cubit.confirmWithProducts(twoProducts);

      expect(cubit.state.productSubmission.isSettled, isTrue);
      expect(cubit.state.productSubmission.isEditable, isFalse);
      expect(cubit.state.canEditTransaction, isFalse);
      await cubit.close();
    });

    test('never claims a new record was created', () async {
      final FakeReceiptExtractionRepository repository = answering(
        withProductsResult(
          outcome: ReceiptWithProductsOutcome.alreadyConfirmed,
          changed: false,
        ),
      );
      final ReceiptReviewCubit cubit = await ready(repository);

      await cubit.confirmWithProducts(twoProducts);

      // `changed` is the backend's word for it, and the copy reads that word
      // rather than assuming success means creation.
      expect(cubit.state.productSubmission.result?.changed, isFalse);
      await cubit.close();
    });

    test('creates no second repository call', () async {
      final FakeReceiptExtractionRepository repository = answering(
        withProductsResult(
          outcome: ReceiptWithProductsOutcome.alreadyConfirmed,
          changed: false,
        ),
      );
      final ReceiptReviewCubit cubit = await ready(repository);

      await cubit.confirmWithProducts(twoProducts);
      await cubit.confirmWithProducts(twoProducts);

      expect(repository.confirmWithProductsCalls, hasLength(1));
      await cubit.close();
    });
  });

  group('CONFLICT', () {
    Future<ReceiptReviewCubit> conflicted(
      FakeReceiptExtractionRepository repository,
    ) async {
      final ReceiptReviewCubit cubit = await ready(repository);
      await cubit.confirmWithProducts(twoProducts);
      return cubit;
    }

    test('stops pending, and never retries', () async {
      final FakeReceiptExtractionRepository repository = answering(
        withProductsResult(
          outcome: ReceiptWithProductsOutcome.conflict,
          changed: false,
          lineCount: 3,
        ),
      );
      final ReceiptReviewCubit cubit = await conflicted(repository);

      expect(cubit.state.productSubmission.isPending, isFalse);
      expect(cubit.state.productSubmission.isConflict, isTrue);
      expect(repository.confirmWithProductsCalls, hasLength(1));

      // Not even after another deliberate act: the write is frozen.
      await cubit.confirmWithProducts(twoProducts);
      expect(repository.confirmWithProductsCalls, hasLength(1));
      await cubit.close();
    });

    test('exposes the status check and keeps mutation disabled', () async {
      final FakeReceiptExtractionRepository repository = answering(
        withProductsResult(
          outcome: ReceiptWithProductsOutcome.conflict,
          changed: false,
        ),
      );
      final ReceiptReviewCubit cubit = await conflicted(repository);

      expect(cubit.state.productSubmission.needsStatusCheck, isTrue);
      expect(cubit.state.productSubmission.canCheckStatus, isTrue);
      expect(cubit.state.productSubmission.isEditable, isFalse);
      expect(cubit.state.canEditTransaction, isFalse);
      await cubit.close();
    });

    test('carries no identity and no backend text', () async {
      final FakeReceiptExtractionRepository repository = answering(
        withProductsResult(
          outcome: ReceiptWithProductsOutcome.conflict,
          changed: false,
        ),
      );
      final ReceiptReviewCubit cubit = await conflicted(repository);

      // The RPC deliberately returns no confirmation id on this branch, so a
      // refusal cannot be used to learn another submission's id — and there is
      // nowhere in the state for an actor, a name or a message to live.
      expect(cubit.state.productSubmission.result?.confirmationId, isNull);
      expect(cubit.state.productSubmission.problem, isNull);
      expect(cubit.state.problem, isNull);
      await cubit.close();
    });
  });

  // ---- An outcome this build cannot read -----------------------------------

  group('an unknown outcome', () {
    test('is neither success nor an ordinary failure', () async {
      final FakeReceiptExtractionRepository repository = answering(
        withProductsResult(
          outcome: ReceiptWithProductsOutcome.unknown,
          changed: false,
        ),
      );
      final ReceiptReviewCubit cubit = await ready(repository);

      await cubit.confirmWithProducts(twoProducts);

      expect(cubit.state.productSubmission.isSettled, isFalse);
      expect(cubit.state.productSubmission.isUncertain, isTrue);
      // Not handed back as editable either: the write may well have committed.
      expect(cubit.state.productSubmission.isEditable, isFalse);
      expect(cubit.state.canEditTransaction, isFalse);
      await cubit.close();
    });

    test('does not retry, and offers the status check', () async {
      final FakeReceiptExtractionRepository repository = answering(
        withProductsResult(
          outcome: ReceiptWithProductsOutcome.unknown,
          changed: false,
        ),
      );
      final ReceiptReviewCubit cubit = await ready(repository);

      await cubit.confirmWithProducts(twoProducts);
      await cubit.confirmWithProducts(twoProducts);

      expect(repository.confirmWithProductsCalls, hasLength(1));
      expect(cubit.state.productSubmission.canCheckStatus, isTrue);
      await cubit.close();
    });

    test(
      'every deployed outcome maps somewhere, and only two are success',
      () async {
        // A source-level exhaustive sweep. A token the database adds later
        // parses as `unknown` and lands in `uncertain`, so it can never become
        // success by default — and if somebody adds a fourth enum value without
        // deciding what it means, this fails and names it.
        final Map<ReceiptWithProductsOutcome, ReceiptProductSubmissionStatus>
        expected = <ReceiptWithProductsOutcome, ReceiptProductSubmissionStatus>{
          ReceiptWithProductsOutcome.confirmed:
              ReceiptProductSubmissionStatus.settled,
          ReceiptWithProductsOutcome.alreadyConfirmed:
              ReceiptProductSubmissionStatus.settled,
          ReceiptWithProductsOutcome.conflict:
              ReceiptProductSubmissionStatus.conflict,
          ReceiptWithProductsOutcome.unknown:
              ReceiptProductSubmissionStatus.uncertain,
        };
        expect(
          expected.keys.toSet(),
          ReceiptWithProductsOutcome.values.toSet(),
          reason:
              'A new outcome must be given a status here before it can reach '
              'the screen.',
        );

        for (final MapEntry<
              ReceiptWithProductsOutcome,
              ReceiptProductSubmissionStatus
            >
            entry
            in expected.entries) {
          final FakeReceiptExtractionRepository repository = answering(
            withProductsResult(outcome: entry.key, changed: false),
          );
          final ReceiptReviewCubit cubit = await ready(repository);
          await cubit.confirmWithProducts(twoProducts);

          expect(
            cubit.state.productSubmission.status,
            entry.value,
            reason: entry.key.name,
          );
          await cubit.close();
        }
      },
    );
  });

  // ---- Transport uncertainty ------------------------------------------------

  group('transport uncertainty', () {
    const List<ReceiptExtractionProblem> uncertain = <ReceiptExtractionProblem>[
      ExtractionNetworkProblem(),
      ExtractionServiceUnavailableProblem(),
      ExtractionMalformedResponseProblem(),
      ExtractionUnknownProblem(),
    ];

    const List<ReceiptExtractionProblem> definite = <ReceiptExtractionProblem>[
      ExtractionInvalidRequestProblem(ExtractionInvalidReason.unknown),
      ExtractionCurrencyScaleMismatchProblem(),
    ];

    test(
      'a fault with no decision is never success and never failure',
      () async {
        for (final ReceiptExtractionProblem problem in uncertain) {
          final FakeReceiptExtractionRepository repository = answering(
            ReceiptExtractionFailed<ReceiptWithProductsResult>(problem),
          );
          final ReceiptReviewCubit cubit = await ready(repository);

          await cubit.confirmWithProducts(twoProducts);

          expect(
            cubit.state.productSubmission.isSettled,
            isFalse,
            reason: '$problem',
          );
          expect(
            cubit.state.productSubmission.isUncertain,
            isTrue,
            reason: '$problem',
          );
          // The submit control stays shut, and nothing was retried or polled.
          expect(cubit.state.canSubmitProposal, isFalse, reason: '$problem');
          expect(repository.confirmWithProductsCalls, hasLength(1));
          expect(repository.productProposalCalls, isEmpty);
          await cubit.close();
        }
      },
    );

    test('the submitted snapshots are retained', () async {
      final FakeReceiptExtractionRepository repository = answering(
        const ReceiptExtractionFailed<ReceiptWithProductsResult>(
          ExtractionNetworkProblem(),
        ),
      );
      final ReceiptReviewCubit cubit = await ready(repository);

      await cubit.confirmWithProducts(twoProducts);

      expect(cubit.state.productSubmission.submitted, twoProducts.selection);
      expect(cubit.state.productSubmission.submittedInput, isNotNull);
      await cubit.close();
    });

    test('the status check is exposed', () async {
      final FakeReceiptExtractionRepository repository = answering(
        const ReceiptExtractionFailed<ReceiptWithProductsResult>(
          ExtractionNetworkProblem(),
        ),
      );
      final ReceiptReviewCubit cubit = await ready(repository);

      await cubit.confirmWithProducts(twoProducts);

      expect(cubit.state.productSubmission.canCheckStatus, isTrue);
      await cubit.close();
    });

    test('no raw provider text is retained anywhere', () async {
      final FakeReceiptExtractionRepository repository = answering(
        const ReceiptExtractionFailed<ReceiptWithProductsResult>(
          ExtractionNetworkProblem(),
        ),
      );
      final ReceiptReviewCubit cubit = await ready(repository);

      await cubit.confirmWithProducts(twoProducts);

      // The problem is a typed discriminant with no fields; there is nowhere
      // for a SQLSTATE, a hint or a stack trace to be kept.
      expect(
        cubit.state.productSubmission.problem,
        isA<ExtractionNetworkProblem>(),
      );
      expect(
        cubit.state.productSubmission.problem!.props,
        isEmpty,
        reason: 'A problem that carried a payload could carry backend text.',
      );
      await cubit.close();
    });

    test('a definite server refusal returns the form, editable', () async {
      for (final ReceiptExtractionProblem problem in definite) {
        final FakeReceiptExtractionRepository repository = answering(
          ReceiptExtractionFailed<ReceiptWithProductsResult>(problem),
        );
        final ReceiptReviewCubit cubit = await ready(repository);

        cubit.setTotal('19.99');
        await cubit.confirmWithProducts(twoProducts);

        // The database answered, and an exception raised inside the function
        // rolls the whole transaction back — so nothing is stored and it is
        // safe to hand the form back.
        expect(
          cubit.state.productSubmission.isUncertain,
          isFalse,
          reason: '$problem',
        );
        expect(
          cubit.state.productSubmission.isEditable,
          isTrue,
          reason: '$problem',
        );
        expect(cubit.state.canEditTransaction, isTrue, reason: '$problem');
        // And the typed values survived.
        expect(cubit.state.draft.totalText, '19.99');
        expect(repository.confirmWithProductsCalls, hasLength(1));
        await cubit.close();
      }
    });

    test(
      'a terminal refusal blocks the screen rather than reopening it',
      () async {
        final FakeReceiptExtractionRepository repository = answering(
          const ReceiptExtractionFailed<ReceiptWithProductsResult>(
            ExtractionForbiddenProblem(),
          ),
        );
        final ReceiptReviewCubit cubit = await ready(repository);

        await cubit.confirmWithProducts(twoProducts);

        expect(cubit.state.phase, ReceiptReviewPhase.blocked);
        expect(cubit.state.productSubmission.isUncertain, isFalse);
        await cubit.close();
      },
    );
  });

  // ---- The manual status check ---------------------------------------------

  group('the manual status check', () {
    Future<ReceiptReviewCubit> uncertainCubit(
      FakeReceiptExtractionRepository repository,
    ) async {
      final ReceiptReviewCubit cubit = await ready(repository);
      await cubit.confirmWithProducts(twoProducts);
      expect(cubit.state.productSubmission.isUncertain, isTrue);
      return cubit;
    }

    FakeReceiptExtractionRepository uncertainRepository({
      List<ReceiptExtractionResult<List<ReceiptProductProposalLine>>>? proposal,
      List<ReceiptExtractionResult<ReceiptConfirmation?>>? confirmation,
    }) {
      return FakeReceiptExtractionRepository(
        confirmWithProductsResults:
            <ReceiptExtractionResult<ReceiptWithProductsResult>>[
              const ReceiptExtractionFailed<ReceiptWithProductsResult>(
                ExtractionNetworkProblem(),
              ),
            ],
        productProposalResults: proposal,
        confirmationResults: confirmation,
      );
    }

    test('it never calls a write method', () async {
      final FakeReceiptExtractionRepository repository = uncertainRepository(
        proposal: <ReceiptExtractionResult<List<ReceiptProductProposalLine>>>[
          const ReceiptExtractionSuccess<List<ReceiptProductProposalLine>>(
            storedProposalLines,
          ),
        ],
      );
      final ReceiptReviewCubit cubit = await uncertainCubit(repository);

      await cubit.checkReceiptStatus();

      // The one write that happened is the one the person asked for, before
      // the check. The check added none.
      expect(repository.confirmWithProductsCalls, hasLength(1));
      expect(repository.confirmInputs, isEmpty);
      expect(repository.requestedIds, hasLength(1));
      await cubit.close();
    });

    test('a double tap produces one read sequence', () async {
      final FakeReceiptExtractionRepository repository = uncertainRepository(
        proposal: <ReceiptExtractionResult<List<ReceiptProductProposalLine>>>[
          const ReceiptExtractionSuccess<List<ReceiptProductProposalLine>>(
            storedProposalLines,
          ),
        ],
      );
      final ReceiptReviewCubit cubit = await uncertainCubit(repository);

      final Future<void> first = cubit.checkReceiptStatus();
      final Future<void> second = cubit.checkReceiptStatus();
      await first;
      await second;

      expect(repository.productProposalCalls, hasLength(1));
      await cubit.close();
    });

    test('a confirmation with a proposal becomes authoritative', () async {
      final FakeReceiptExtractionRepository repository = uncertainRepository(
        proposal: <ReceiptExtractionResult<List<ReceiptProductProposalLine>>>[
          const ReceiptExtractionSuccess<List<ReceiptProductProposalLine>>(
            storedProposalLines,
          ),
        ],
      );
      final ReceiptReviewCubit cubit = await uncertainCubit(repository);

      await cubit.checkReceiptStatus();

      expect(cubit.state.productSubmission.isSettled, isTrue);
      expect(
        cubit.state.productSubmission.statusCheck,
        ReceiptProductStatusCheckOutcome.storedWithProposal,
      );
      expect(cubit.state.productSubmission.isEditable, isFalse);
      // A stored proposal settles the question in one read: the confirmation
      // read is not needed and is not made.
      expect(repository.confirmationIds, isEmpty);
      await cubit.close();
    });

    test('a confirmation without a proposal is the legacy state', () async {
      final FakeReceiptExtractionRepository repository = uncertainRepository(
        proposal: <ReceiptExtractionResult<List<ReceiptProductProposalLine>>>[
          const ReceiptExtractionSuccess<List<ReceiptProductProposalLine>>(
            <ReceiptProductProposalLine>[],
          ),
        ],
        confirmation: <ReceiptExtractionResult<ReceiptConfirmation?>>[
          ReceiptExtractionSuccess<ReceiptConfirmation?>(storedConfirmation()),
        ],
      );
      final ReceiptReviewCubit cubit = await uncertainCubit(repository);

      await cubit.checkReceiptStatus();

      expect(
        cubit.state.productSubmission.statusCheck,
        ReceiptProductStatusCheckOutcome.legacyHeaderOnly,
      );
      expect(cubit.state.productSubmission.foundLegacyHeaderOnly, isTrue);
      // NOTHING is appended and nothing is resent: a header-only confirmation
      // can never acquire products.
      expect(repository.confirmWithProductsCalls, hasLength(1));
      expect(cubit.state.productSubmission.isEditable, isFalse);
      await cubit.close();
    });

    test(
      'neither stored reopens the form, with everything preserved',
      () async {
        final FakeReceiptExtractionRepository repository = uncertainRepository(
          proposal: <ReceiptExtractionResult<List<ReceiptProductProposalLine>>>[
            const ReceiptExtractionSuccess<List<ReceiptProductProposalLine>>(
              <ReceiptProductProposalLine>[],
            ),
          ],
          confirmation: const <ReceiptExtractionResult<ReceiptConfirmation?>>[
            ReceiptExtractionSuccess<ReceiptConfirmation?>(null),
          ],
        );
        final ReceiptReviewCubit cubit = await ready(repository);
        cubit.setTotal('19.99');
        cubit.setMerchantName('Corner Shop');
        await cubit.confirmWithProducts(twoProducts);

        await cubit.checkReceiptStatus();

        // BOTH reads answered, and both said nothing is stored. Only then.
        expect(
          cubit.state.productSubmission.statusCheck,
          ReceiptProductStatusCheckOutcome.nothingStored,
        );
        expect(cubit.state.productSubmission.isEditable, isTrue);
        expect(cubit.state.canEditTransaction, isTrue);
        expect(cubit.state.canSubmitProposal, isTrue);
        // Every typed value is exactly where it was left.
        expect(cubit.state.draft.totalText, '19.99');
        expect(cubit.state.draft.merchantName, 'Corner Shop');
        await cubit.close();
      },
    );

    test('an unreadable proposal read stays uncertain', () async {
      final FakeReceiptExtractionRepository repository = uncertainRepository(
        proposal: <ReceiptExtractionResult<List<ReceiptProductProposalLine>>>[
          const ReceiptExtractionFailed<List<ReceiptProductProposalLine>>(
            ExtractionNetworkProblem(),
          ),
        ],
      );
      final ReceiptReviewCubit cubit = await uncertainCubit(repository);

      await cubit.checkReceiptStatus();

      expect(cubit.state.productSubmission.isUncertain, isTrue);
      expect(
        cubit.state.productSubmission.statusCheck,
        ReceiptProductStatusCheckOutcome.unreadable,
      );
      expect(cubit.state.productSubmission.isEditable, isFalse);
      // Offered again, by hand. Never on a timer, and never as a loop.
      expect(cubit.state.productSubmission.canCheckStatus, isTrue);
      expect(repository.productProposalCalls, hasLength(1));
      await cubit.close();
    });

    test('an unreadable confirmation read stays uncertain', () async {
      final FakeReceiptExtractionRepository repository = uncertainRepository(
        proposal: <ReceiptExtractionResult<List<ReceiptProductProposalLine>>>[
          const ReceiptExtractionSuccess<List<ReceiptProductProposalLine>>(
            <ReceiptProductProposalLine>[],
          ),
        ],
        confirmation: const <ReceiptExtractionResult<ReceiptConfirmation?>>[
          ReceiptExtractionFailed<ReceiptConfirmation?>(
            ExtractionServiceUnavailableProblem(),
          ),
        ],
      );
      final ReceiptReviewCubit cubit = await uncertainCubit(repository);

      await cubit.checkReceiptStatus();

      expect(cubit.state.productSubmission.isUncertain, isTrue);
      expect(cubit.state.productSubmission.isEditable, isFalse);
      await cubit.close();
    });

    test('a missing or foreign receipt reads as nothing stored', () async {
      // The backend makes "no confirmation", "not yours" and "does not exist"
      // one answer. This asserts the client preserves that collapse rather than
      // splitting it into an existence oracle.
      final FakeReceiptExtractionRepository repository = uncertainRepository(
        proposal: <ReceiptExtractionResult<List<ReceiptProductProposalLine>>>[
          const ReceiptExtractionSuccess<List<ReceiptProductProposalLine>>(
            <ReceiptProductProposalLine>[],
          ),
        ],
        confirmation: const <ReceiptExtractionResult<ReceiptConfirmation?>>[
          ReceiptExtractionSuccess<ReceiptConfirmation?>(null),
        ],
      );
      final ReceiptReviewCubit cubit = await uncertainCubit(repository);

      await cubit.checkReceiptStatus();

      expect(
        cubit.state.productSubmission.statusCheck,
        ReceiptProductStatusCheckOutcome.nothingStored,
      );
      // Nothing about another receipt, another owner or another Retailer is
      // recorded — there is no field for one.
      expect(cubit.state.confirmation, isNull);
      await cubit.close();
    });

    test('it does not poll: one tap is one read sequence', () async {
      final FakeReceiptExtractionRepository repository = uncertainRepository(
        proposal: <ReceiptExtractionResult<List<ReceiptProductProposalLine>>>[
          const ReceiptExtractionFailed<List<ReceiptProductProposalLine>>(
            ExtractionNetworkProblem(),
          ),
        ],
      );
      final ReceiptReviewCubit cubit = await uncertainCubit(repository);

      await cubit.checkReceiptStatus();
      await settle(50);

      expect(repository.productProposalCalls, hasLength(1));
      expect(repository.confirmationIds, isEmpty);
      await cubit.close();
    });

    test('it is refused entirely while the outcome is not in doubt', () async {
      final FakeReceiptExtractionRepository repository = answering(
        withProductsResult(),
      );
      final ReceiptReviewCubit cubit = await ready(repository);

      // Before any write.
      await cubit.checkReceiptStatus();
      expect(repository.productProposalCalls, isEmpty);

      await cubit.confirmWithProducts(twoProducts);
      // The write's own authoritative reload, and nothing else.
      final int afterWrite = repository.productProposalCalls.length;
      expect(afterWrite, 1);

      // And after an authoritative success the check adds nothing.
      await cubit.checkReceiptStatus();
      expect(repository.productProposalCalls, hasLength(afterWrite));
      await cubit.close();
    });
  });
}
