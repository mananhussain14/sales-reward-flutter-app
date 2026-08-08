import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_file.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_product.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_rejection_reason.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_shop.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_submission.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_submission_outcome.dart';
import 'package:sale_reward/features/receipts/domain/repositories/receipt_result.dart';
import 'package:sale_reward/features/receipts/domain/services/receipt_image_source.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/cubit/receipt_submission_cubit.dart';

import '../../support/receipt_fakes.dart';

void main() {
  late FakeReceiptRepository repository;
  late FakeReceiptImageSource images;
  late int historyRefreshes;

  ReceiptSubmissionCubit build() => ReceiptSubmissionCubit(
    repository: repository,
    imageSource: images,
    onSubmissionSettled: () => historyRefreshes++,
  );

  /// A cubit already loaded, with a shop chosen and no image yet.
  ///
  /// A chosen shop is a **prerequisite** of the image picker, not a field
  /// beside it, so every test that reaches [ReceiptSubmissionCubit.chooseImage]
  /// has to settle one first. The default fixture carries two assigned shops,
  /// which is deliberately the case where nothing is chosen automatically.
  Future<ReceiptSubmissionCubit> withShop() async {
    final ReceiptSubmissionCubit cubit = build();
    await cubit.load();
    cubit.selectShop(shopAUuid);
    expect(cubit.state.canChooseFile, isTrue);
    return cubit;
  }

  /// A cubit already loaded, with a shop and a valid receipt chosen.
  Future<ReceiptSubmissionCubit> armed() async {
    final ReceiptSubmissionCubit cubit = await withShop();
    await cubit.chooseImage(ReceiptImageOrigin.gallery);
    expect(cubit.state.canSubmit, isTrue);
    return cubit;
  }

  setUp(() {
    repository = FakeReceiptRepository();
    images = FakeReceiptImageSource();
    historyRefreshes = 0;
  });

  group('loading', () {
    test('starts in initial loading', () {
      expect(build().state.phase, ReceiptSubmissionPhase.initialLoading);
    });

    test('loads shops and products, each with zero arguments', () async {
      final ReceiptSubmissionCubit cubit = build();
      await cubit.load();

      expect(repository.assignedShopsCallCount, 1);
      expect(repository.receiptProductsCallCount, 1);
      expect(cubit.state.phase, ReceiptSubmissionPhase.ready);
      expect(cubit.state.shops, <ReceiptShop>[shopA, shopB]);
      expect(cubit.state.products, <ReceiptProduct>[productA, productB]);
    });

    test('no shops assigned is a ready form, not a failure', () async {
      repository.shopsResult = const ReceiptReadSuccess<List<ReceiptShop>>(
        <ReceiptShop>[],
      );

      final ReceiptSubmissionCubit cubit = build();
      await cubit.load();

      expect(cubit.state.phase, ReceiptSubmissionPhase.ready);
      expect(cubit.state.shops, isEmpty);
      expect(cubit.state.loadFailure, isNull);
      expect(cubit.state.canSubmit, isFalse);
    });

    test('an empty product catalogue does not block submission', () async {
      repository.productsResult =
          const ReceiptReadSuccess<List<ReceiptProduct>>(<ReceiptProduct>[]);

      final ReceiptSubmissionCubit cubit = build();
      await cubit.load();

      expect(cubit.state.phase, ReceiptSubmissionPhase.ready);
      expect(cubit.state.products, isEmpty);
      expect(cubit.state.productsFailure, isNull);
    });

    test('a shop failure blocks the form and offers a retry', () async {
      repository.shopsResult = unavailableRead<List<ReceiptShop>>();

      final ReceiptSubmissionCubit cubit = build();
      await cubit.load();

      expect(cubit.state.phase, ReceiptSubmissionPhase.loadFailed);
      expect(cubit.state.loadFailure, isA<UnavailableFailure>());
    });

    test('a denial is a denial, not an empty shop list', () async {
      repository.shopsResult = deniedRead<List<ReceiptShop>>();

      final ReceiptSubmissionCubit cubit = build();
      await cubit.load();

      expect(cubit.state.phase, ReceiptSubmissionPhase.loadFailed);
      expect(cubit.state.loadFailure, isA<DeniedFailure>());
    });

    test('a product failure degrades one section only', () async {
      repository.productsResult = unavailableRead<List<ReceiptProduct>>();

      final ReceiptSubmissionCubit cubit = build();
      await cubit.load();

      expect(cubit.state.phase, ReceiptSubmissionPhase.ready);
      expect(cubit.state.shops, isNotEmpty);
      expect(cubit.state.productsFailure, isA<UnavailableFailure>());
      expect(cubit.state.loadFailure, isNull);
    });

    test('a reload keeps a chosen receipt', () async {
      final ReceiptSubmissionCubit cubit = await armed();
      final ReceiptFile chosen = cubit.state.file!;

      await cubit.load();

      expect(cubit.state.file, same(chosen));
      expect(cubit.state.phase, ReceiptSubmissionPhase.fileSelected);
    });

    test('a shop that disappears between loads stops being selected', () async {
      final ReceiptSubmissionCubit cubit = build();
      repository.shopsResult = const ReceiptReadSuccess<List<ReceiptShop>>(
        <ReceiptShop>[shopA, shopB, shopC],
      );
      await cubit.load();
      cubit.selectShop(shopAUuid);

      // Down to two, not to one: a list of one is selected automatically, which
      // would hide the clearing this test is about.
      repository.shopsResult = const ReceiptReadSuccess<List<ReceiptShop>>(
        <ReceiptShop>[shopB, shopC],
      );
      await cubit.load();

      expect(cubit.state.selectedShopId, isNull);
      expect(cubit.state.selectedShop, isNull);
    });

    test('a still-assigned shop survives a reload', () async {
      final ReceiptSubmissionCubit cubit = build();
      await cubit.load();
      cubit.selectShop(shopBUuid);

      await cubit.load();

      expect(cubit.state.selectedShop, shopB);
    });
  });

  group('exactly one assigned shop', () {
    setUp(() {
      repository.shopsResult = oneShopAssigned();
    });

    test('is selected when the list loads, without being asked', () async {
      final ReceiptSubmissionCubit cubit = build();

      await cubit.load();

      expect(cubit.state.selectedShopId, shopAUuid);
      expect(cubit.state.selectedShop, shopA);
      expect(cubit.state.hasSingleShop, isTrue);
      expect(cubit.state.requiresShopChoice, isFalse);
      expect(cubit.state.isShopSelectionPending, isFalse);
    });

    test('the id comes from the assigned list and nowhere else', () async {
      final ReceiptSubmissionCubit cubit = build();

      await cubit.load();

      // The only source of a shop id in this cubit is the zero-argument RPC the
      // repository wraps. Nothing is derived, defaulted or remembered.
      expect(repository.assignedShopsCallCount, 1);
      expect(
        cubit.state.shops.map((ReceiptShop shop) => shop.shopId),
        contains(cubit.state.selectedShopId),
      );
    });

    test('leaves the image picker open immediately', () async {
      final ReceiptSubmissionCubit cubit = build();

      await cubit.load();

      expect(cubit.state.canChooseFile, isTrue);

      await cubit.chooseImage(ReceiptImageOrigin.camera);

      expect(cubit.state.phase, ReceiptSubmissionPhase.fileSelected);
      expect(cubit.state.canSubmit, isTrue);
    });

    test('submits the automatically selected shop id', () async {
      final ReceiptSubmissionCubit cubit = build();
      await cubit.load();
      await cubit.chooseImage(ReceiptImageOrigin.gallery);

      await cubit.submit();

      expect(repository.submitCallCount, 1);
      expect(repository.lastSubmittedShopId, shopAUuid);
      expect(cubit.state.phase, ReceiptSubmissionPhase.success);
    });

    test('dropping from several shops to one selects the survivor', () async {
      final ReceiptSubmissionCubit cubit = build();
      repository.shopsResult = const ReceiptReadSuccess<List<ReceiptShop>>(
        <ReceiptShop>[shopA, shopB],
      );
      await cubit.load();
      cubit.selectShop(shopAUuid);

      // shopA is unassigned; only shopB remains.
      repository.shopsResult = oneShopAssigned(shopB);
      await cubit.load();

      expect(cubit.state.selectedShop, shopB);
      expect(cubit.state.canChooseFile, isTrue);
    });

    test('gaining a second shop drops back to an unanswered choice', () async {
      final ReceiptSubmissionCubit cubit = build();
      await cubit.load();
      expect(cubit.state.selectedShop, shopA);

      repository.shopsResult = const ReceiptReadSuccess<List<ReceiptShop>>(
        <ReceiptShop>[shopA, shopB],
      );
      await cubit.load();

      // shopA is still assigned, so the existing selection stands rather than
      // being thrown away — but it is now a choice the person owns.
      expect(cubit.state.selectedShop, shopA);
      expect(cubit.state.requiresShopChoice, isTrue);
    });
  });

  group('no assigned shops', () {
    setUp(() {
      repository.shopsResult = noShopsAssigned();
    });

    test('nothing is selected and the picker stays shut', () async {
      final ReceiptSubmissionCubit cubit = build();

      await cubit.load();

      expect(cubit.state.phase, ReceiptSubmissionPhase.ready);
      expect(cubit.state.hasShops, isFalse);
      expect(cubit.state.selectedShop, isNull);
      expect(cubit.state.canChooseFile, isFalse);
      expect(cubit.state.canSubmit, isFalse);
      // Not "pending": there is no choice waiting to be made, so nothing is
      // locked — the whole form is replaced upstream.
      expect(cubit.state.isShopSelectionPending, isFalse);
    });

    test('an image cannot be picked at all', () async {
      final ReceiptSubmissionCubit cubit = build();
      await cubit.load();

      await cubit.chooseImage(ReceiptImageOrigin.gallery);

      expect(images.pickCallCount, 0);
      expect(cubit.state.file, isNull);
      expect(repository.submitCallCount, 0);
    });
  });

  group('several assigned shops', () {
    test('nothing is preselected', () async {
      final ReceiptSubmissionCubit cubit = build();

      await cubit.load();

      expect(cubit.state.shops, <ReceiptShop>[shopA, shopB]);
      expect(cubit.state.selectedShopId, isNull);
      expect(cubit.state.selectedShop, isNull);
      expect(cubit.state.requiresShopChoice, isTrue);
      expect(cubit.state.isShopSelectionPending, isTrue);
    });

    test('the picker is shut until a shop is chosen', () async {
      final ReceiptSubmissionCubit cubit = build();
      await cubit.load();

      expect(cubit.state.canChooseFile, isFalse);

      await cubit.chooseImage(ReceiptImageOrigin.camera);

      // Refused by the cubit itself, not merely hidden by the screen: the
      // picker was never opened.
      expect(images.pickCallCount, 0);
      expect(cubit.state.file, isNull);
    });

    test('choosing a shop opens the picker', () async {
      final ReceiptSubmissionCubit cubit = build();
      await cubit.load();

      cubit.selectShop(shopBUuid);

      expect(cubit.state.isShopSelectionPending, isFalse);
      expect(cubit.state.canChooseFile, isTrue);

      await cubit.chooseImage(ReceiptImageOrigin.gallery);

      expect(images.pickCallCount, 1);
      expect(cubit.state.phase, ReceiptSubmissionPhase.fileSelected);
    });

    test('changing shop keeps the chosen image', () async {
      final ReceiptSubmissionCubit cubit = await armed();
      final ReceiptFile chosen = cubit.state.file!;

      cubit.selectShop(shopBUuid);

      expect(cubit.state.selectedShop, shopB);
      expect(cubit.state.file, same(chosen));
      expect(cubit.state.phase, ReceiptSubmissionPhase.fileSelected);
      expect(cubit.state.canSubmit, isTrue);
      // The picker was opened once, for the original pick. Changing shop does
      // not re-open it and does not discard what it returned.
      expect(images.pickCallCount, 1);
    });

    test('the final shop is the one submitted', () async {
      final ReceiptSubmissionCubit cubit = await armed();
      final ReceiptFile chosen = cubit.state.file!;

      // Chosen under shopA, then moved to shopB.
      cubit.selectShop(shopBUuid);
      await cubit.submit();

      expect(repository.submitCallCount, 1);
      expect(repository.lastSubmittedShopId, shopBUuid);
      // The same photograph, filed against the shop chosen last.
      expect(repository.lastSubmittedFile, same(chosen));
    });
  });

  group('shop selection', () {
    test('selects a shop from the loaded list', () async {
      final ReceiptSubmissionCubit cubit = build();
      await cubit.load();

      cubit.selectShop(shopBUuid);

      expect(cubit.state.selectedShop, shopB);
    });

    test('an id that is not in the list is ignored', () async {
      final ReceiptSubmissionCubit cubit = build();
      await cubit.load();

      cubit.selectShop('00000000-0000-0000-0000-000000000000');

      expect(cubit.state.selectedShopId, isNull);
    });
  });

  group('choosing a receipt', () {
    test(
      'a valid image is accepted and the type comes from the bytes',
      () async {
        final ReceiptSubmissionCubit cubit = await withShop();

        await cubit.chooseImage(ReceiptImageOrigin.camera);

        expect(images.origins, <ReceiptImageOrigin>[ReceiptImageOrigin.camera]);
        expect(cubit.state.phase, ReceiptSubmissionPhase.fileSelected);
        expect(cubit.state.file!.imageType.mimeType, 'image/png');
        expect(cubit.state.stage, isNull);
      },
    );

    test(
      'an unsupported file is refused and does not become the selection',
      () async {
        final ReceiptSubmissionCubit cubit = await armed();
        final ReceiptFile good = cubit.state.file!;

        images.nextImage = PickedReceiptImage(
          fileName: 'receipt.jpg',
          bytes: pdfBytes(),
        );
        await cubit.chooseImage(ReceiptImageOrigin.gallery);

        expect(cubit.state.phase, ReceiptSubmissionPhase.rejected);
        expect(cubit.state.rejection, ReceiptRejectionReason.unsupportedType);
        // The good selection survives a bad pick.
        expect(cubit.state.file, same(good));
      },
    );

    test('an oversized file is refused before any upload', () async {
      final ReceiptSubmissionCubit cubit = await withShop();

      images.nextImage = PickedReceiptImage(
        fileName: 'huge.png',
        bytes: pngBytes(length: maxReceiptFileBytes + 1),
      );
      await cubit.chooseImage(ReceiptImageOrigin.gallery);

      expect(cubit.state.rejection, ReceiptRejectionReason.tooLarge);
      expect(repository.submitCallCount, 0);
    });

    test('cancelling leaves an existing selection untouched', () async {
      final ReceiptSubmissionCubit cubit = await armed();
      final ReceiptFile chosen = cubit.state.file!;

      images.nextImage = null;
      await cubit.chooseImage(ReceiptImageOrigin.gallery);

      expect(cubit.state.file, same(chosen));
      expect(cubit.state.phase, ReceiptSubmissionPhase.fileSelected);
    });

    test('a picker failure is retryable, never a denial', () async {
      final ReceiptSubmissionCubit cubit = await withShop();

      images.throwOnPick = true;
      await cubit.chooseImage(ReceiptImageOrigin.camera);

      expect(cubit.state.phase, ReceiptSubmissionPhase.retryable);
      expect(cubit.state.phase, isNot(ReceiptSubmissionPhase.denied));
    });

    test('replacing swaps the file and clears a previous result', () async {
      final ReceiptSubmissionCubit cubit = await armed();
      final ReceiptFile first = cubit.state.file!;

      images.nextImage = PickedReceiptImage(
        fileName: 'other.jpg',
        bytes: jpegBytes(),
      );
      await cubit.chooseImage(ReceiptImageOrigin.gallery);

      expect(cubit.state.file, isNot(same(first)));
      expect(cubit.state.file!.fileName, 'other.jpg');
      expect(cubit.state.submissionId, isNull);
    });

    test('removing clears the file and returns to an empty form', () async {
      final ReceiptSubmissionCubit cubit = await armed();

      cubit.removeFile();

      expect(cubit.state.file, isNull);
      expect(cubit.state.phase, ReceiptSubmissionPhase.ready);
      expect(cubit.state.canSubmit, isFalse);
    });
  });

  group('submitting', () {
    test('sends exactly the chosen shop id and the chosen file', () async {
      final ReceiptSubmissionCubit cubit = await armed();
      final ReceiptFile chosen = cubit.state.file!;

      await cubit.submit();

      expect(repository.submitCallCount, 1);
      expect(repository.lastSubmittedShopId, shopAUuid);
      expect(repository.lastSubmittedFile, same(chosen));
    });

    test('a success reads the row back with the returned id', () async {
      final ReceiptSubmissionCubit cubit = await armed();

      await cubit.submit();

      expect(repository.submissionCallCount, 1);
      expect(repository.lastRequestedSubmissionId, submissionUuid);
      expect(cubit.state.phase, ReceiptSubmissionPhase.success);
      expect(cubit.state.submissionId, submissionUuid);
      expect(cubit.state.submission, submittedRow);
      expect(cubit.state.stage, ReceiptUploadStage.complete);
      expect(cubit.state.detailUnavailable, isFalse);
    });

    test(
      'the displayed status is the database\'s, not the HTTP code\'s',
      () async {
        // A 200 proves the function accepted it. What the row *says* comes from
        // get_my_receipt_submission, and the cubit shows that and only that.
        repository.submissionResult = ReceiptReadSuccess<ReceiptSubmission?>(
          submittedRow,
        );

        final ReceiptSubmissionCubit cubit = await armed();
        await cubit.submit();

        expect(cubit.state.submission!.status.isSubmitted, isTrue);
      },
    );

    test('a confirmed success clears the receipt from memory', () async {
      final ReceiptSubmissionCubit cubit = await armed();

      await cubit.submit();

      expect(cubit.state.file, isNull);
      expect(cubit.state.canSubmit, isFalse);
    });

    test('a failed detail read does not downgrade a success', () async {
      repository.submissionResult = unavailableRead<ReceiptSubmission?>();

      final ReceiptSubmissionCubit cubit = await armed();
      await cubit.submit();

      expect(cubit.state.phase, ReceiptSubmissionPhase.success);
      expect(cubit.state.submissionId, submissionUuid);
      expect(cubit.state.submission, isNull);
      expect(cubit.state.detailUnavailable, isTrue);
    });

    test('zero rows from the detail read is also still a success', () async {
      repository.submissionResult =
          const ReceiptReadSuccess<ReceiptSubmission?>(null);

      final ReceiptSubmissionCubit cubit = await armed();
      await cubit.submit();

      expect(cubit.state.phase, ReceiptSubmissionPhase.success);
      expect(cubit.state.detailUnavailable, isTrue);
    });

    test('the history is refreshed after a success', () async {
      final ReceiptSubmissionCubit cubit = await armed();

      await cubit.submit();

      expect(historyRefreshes, 1);
    });

    test('progress moves through the stages in order', () async {
      repository.manualSubmit = true;
      final ReceiptSubmissionCubit cubit = await armed();

      final List<ReceiptUploadStage?> seen = <ReceiptUploadStage?>[];
      final StreamSubscription<ReceiptSubmissionState> subscription = cubit
          .stream
          .listen((ReceiptSubmissionState state) => seen.add(state.stage));

      final Future<void> pending = cubit.submit();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.stage, ReceiptUploadStage.uploading);

      repository.completeSubmit();
      await pending;
      // Stream events are delivered asynchronously; let the last one land.
      await Future<void>.delayed(Duration.zero);

      expect(
        seen,
        containsAllInOrder(<ReceiptUploadStage>[
          ReceiptUploadStage.uploading,
          ReceiptUploadStage.confirming,
          ReceiptUploadStage.complete,
        ]),
      );
      await subscription.cancel();
    });

    test('a second tap while one is in flight is ignored', () async {
      repository.manualSubmit = true;
      final ReceiptSubmissionCubit cubit = await armed();

      final Future<void> first = cubit.submit();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.canSubmit, isFalse);
      await cubit.submit();
      await cubit.submit();

      expect(repository.submitCallCount, 1);
      expect(repository.pendingSubmitCount, 1);

      repository.completeSubmit();
      await first;
      expect(repository.submitCallCount, 1);
    });

    test('nothing is submitted without a shop', () async {
      final ReceiptSubmissionCubit cubit = build();
      await cubit.load();
      await cubit.chooseImage(ReceiptImageOrigin.gallery);

      await cubit.submit();

      // Two assigned shops and none chosen, so the picker never opened either —
      // the guard sits in front of the image, not only in front of the send.
      expect(images.pickCallCount, 0);
      expect(cubit.state.file, isNull);
      expect(repository.submitCallCount, 0);
    });

    test('nothing is submitted without a receipt', () async {
      final ReceiptSubmissionCubit cubit = build();
      await cubit.load();
      cubit.selectShop(shopAUuid);

      await cubit.submit();

      expect(repository.submitCallCount, 0);
    });
  });

  group('submission outcomes', () {
    test(
      '409 is a duplicate that cannot be retried with the same file',
      () async {
        repository.submitOutcome = const ReceiptSubmissionDuplicate();
        final ReceiptSubmissionCubit cubit = await armed();

        await cubit.submit();

        expect(cubit.state.phase, ReceiptSubmissionPhase.duplicate);
        // The duplicate index is keyed on the hash and the submitter, so the same
        // bytes would be refused at any shop.
        expect(cubit.state.canSubmit, isFalse);
        cubit.selectShop(shopBUuid);
        expect(cubit.state.canSubmit, isFalse);
        // A different receipt clears it.
        images.nextImage = PickedReceiptImage(
          fileName: 'other.jpg',
          bytes: jpegBytes(),
        );
        await cubit.chooseImage(ReceiptImageOrigin.gallery);
        expect(cubit.state.canSubmit, isTrue);
      },
    );

    test(
      '403 keeps the receipt and allows another shop to be chosen',
      () async {
        repository.submitOutcome = const ReceiptSubmissionDenied();
        final ReceiptSubmissionCubit cubit = await armed();

        await cubit.submit();

        expect(cubit.state.phase, ReceiptSubmissionPhase.denied);
        expect(cubit.state.file, isNotNull);
        expect(cubit.state.canSubmit, isTrue);
      },
    );

    test('401 ends the flow rather than offering a doomed retry', () async {
      repository.submitOutcome = const ReceiptSubmissionUnauthenticated();
      final ReceiptSubmissionCubit cubit = await armed();

      await cubit.submit();

      expect(cubit.state.phase, ReceiptSubmissionPhase.unauthenticated);
      expect(cubit.state.canSubmit, isFalse);
      // And it is not a permission problem.
      expect(cubit.state.phase, isNot(ReceiptSubmissionPhase.denied));
    });

    test('400 carries the reason and keeps the receipt', () async {
      repository.submitOutcome = const ReceiptSubmissionRefused(
        ReceiptRejectionReason.tooLarge,
      );
      final ReceiptSubmissionCubit cubit = await armed();

      await cubit.submit();

      expect(cubit.state.phase, ReceiptSubmissionPhase.rejected);
      expect(cubit.state.rejection, ReceiptRejectionReason.tooLarge);
      expect(cubit.state.file, isNotNull);
    });

    test('502 is retryable with the same photo', () async {
      repository.submitOutcome = const ReceiptSubmissionUploadFailed();
      final ReceiptSubmissionCubit cubit = await armed();

      await cubit.submit();

      expect(cubit.state.phase, ReceiptSubmissionPhase.retryable);
      expect(cubit.state.canSubmit, isTrue);

      repository.submitOutcome = const ReceiptSubmissionAccepted(
        submissionUuid,
      );
      await cubit.submit();

      expect(repository.submitCallCount, 2);
      expect(cubit.state.phase, ReceiptSubmissionPhase.success);
    });

    test('503 is retryable and never a denial', () async {
      repository.submitOutcome = const ReceiptSubmissionUnavailable();
      final ReceiptSubmissionCubit cubit = await armed();

      await cubit.submit();

      expect(cubit.state.phase, ReceiptSubmissionPhase.retryable);
    });

    test(
      'an unconfirmed result never resends and refreshes the history',
      () async {
        repository.submitOutcome = const ReceiptSubmissionUnconfirmed();
        final ReceiptSubmissionCubit cubit = await armed();

        await cubit.submit();

        expect(cubit.state.phase, ReceiptSubmissionPhase.unconfirmed);
        // Exactly one attempt was made, and the receipt is kept so the person can
        // decide for themselves after checking the list.
        expect(repository.submitCallCount, 1);
        expect(cubit.state.file, isNotNull);
        expect(historyRefreshes, 1);
        // No detail read: there is no id to read.
        expect(repository.submissionCallCount, 0);
      },
    );

    test(
      'an unconfirmed result still allows a deliberate second attempt',
      () async {
        repository.submitOutcome = const ReceiptSubmissionUnconfirmed();
        final ReceiptSubmissionCubit cubit = await armed();
        await cubit.submit();

        expect(cubit.state.canSubmit, isTrue);
        await cubit.submit();
        expect(repository.submitCallCount, 2);
      },
    );
  });

  group('finishing and clearing', () {
    test(
      'starting another keeps the loaded context and clears the result',
      () async {
        final ReceiptSubmissionCubit cubit = await armed();
        await cubit.submit();

        cubit.startAnother();

        expect(cubit.state.phase, ReceiptSubmissionPhase.ready);
        expect(cubit.state.shops, isNotEmpty);
        expect(cubit.state.products, isNotEmpty);
        expect(cubit.state.submissionId, isNull);
        expect(cubit.state.submission, isNull);
        expect(cubit.state.file, isNull);
      },
    );

    test('clear drops every piece of private data', () async {
      final ReceiptSubmissionCubit cubit = await armed();
      await cubit.submit();

      cubit.clear();

      expect(cubit.state.shops, isEmpty);
      expect(cubit.state.products, isEmpty);
      expect(cubit.state.file, isNull);
      expect(cubit.state.selectedShopId, isNull);
      expect(cubit.state.submission, isNull);
      expect(cubit.state.submissionId, isNull);
    });

    test('closing while a submission is in flight commits nothing', () async {
      repository.manualSubmit = true;
      final ReceiptSubmissionCubit cubit = await armed();

      final Future<void> pending = cubit.submit();
      await Future<void>.delayed(Duration.zero);
      await cubit.close();

      repository.completeSubmit();
      await pending;

      // No emit after close, and no detail read for a cubit nobody is watching.
      expect(repository.submissionCallCount, 0);
    });
  });

  group('camera capability', () {
    test(
      'is a presentation hint read straight from the image source',
      () async {
        expect(build().supportsCamera, isTrue);

        images = FakeReceiptImageSource(supportsCamera: false);
        expect(build().supportsCamera, isFalse);
      },
    );
  });
}
