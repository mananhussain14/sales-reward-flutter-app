import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/errors/failure.dart';
import '../../../domain/entities/receipt_file.dart';
import '../../../domain/entities/receipt_product.dart';
import '../../../domain/entities/receipt_rejection_reason.dart';
import '../../../domain/entities/receipt_shop.dart';
import '../../../domain/entities/receipt_submission.dart';
import '../../../domain/entities/receipt_submission_outcome.dart';
import '../../../domain/repositories/receipt_repository.dart';
import '../../../domain/repositories/receipt_result.dart';
import '../../../domain/services/receipt_image_source.dart';

part 'receipt_submission_state.dart';

/// Drives one receipt submission from an empty form to a confirmed row.
///
/// ## The flow, in order
///
/// 1. `list_my_assigned_receipt_shops()` and `list_my_receipt_products()`, in
///    parallel. Both take zero arguments.
/// 2. The person picks a shop and a receipt image. The image is checked
///    client-side for immediate feedback only.
/// 3. `POST submit-receipt` with `shop_id` and one file, and nothing else.
/// 4. On `200`, `get_my_receipt_submission(<the returned id>)` — so the status
///    shown is one the **database** returned, not one this client assumed from a
///    success code.
///
/// ## What it never does
///
/// * It never resends automatically. A `502` is a definite negative and offers a
///   retry the *person* takes; an unconfirmed transport failure offers a refresh
///   of the history first, because a silent second upload could create a second
///   submission of a receipt that already landed.
/// * It never turns an operational failure into a denial, or the reverse.
/// * It never decides that a submission succeeded. Only a `200` carrying a
///   well-formed id does, and only the database says what its status is.
/// * It never keeps a receipt image after a confirmed success, and never writes
///   one anywhere but memory.
final class ReceiptSubmissionCubit extends Cubit<ReceiptSubmissionState> {
  ReceiptSubmissionCubit({
    required ReceiptRepository repository,
    required ReceiptImageSource imageSource,
    this.onSubmissionSettled,
  }) : _repository = repository,
       _imageSource = imageSource,
       super(const ReceiptSubmissionState());

  final ReceiptRepository _repository;
  final ReceiptImageSource _imageSource;

  /// Called whenever the caller's submission history may have changed — after a
  /// success, and after an unconfirmed result where the receipt **may** have
  /// landed.
  ///
  /// A callback rather than a reference to the history cubit, so this class
  /// depends on nothing it does not use and a test can assert the refresh
  /// happened without building a second cubit.
  final void Function()? onSubmissionSettled;

  /// Whether camera capture should be offered on this platform. Presentation
  /// only.
  bool get supportsCamera => _imageSource.supportsCamera;

  /// Reads the shops and the product reference list.
  ///
  /// The two are independent: a product failure degrades one section, while a
  /// shop failure blocks the form, because a receipt is always submitted against
  /// one assigned shop.
  Future<void> load() async {
    emit(
      state.copyWith(
        phase: ReceiptSubmissionPhase.initialLoading,
        clearLoadFailure: true,
        clearProductsFailure: true,
      ),
    );

    final (
      ReceiptResult<List<ReceiptShop>> shopsResult,
      ReceiptResult<List<ReceiptProduct>> productsResult,
    ) = await (
      _repository.assignedShops(),
      _repository.receiptProducts(),
    ).wait;

    if (isClosed) {
      return;
    }

    switch (shopsResult) {
      case ReceiptReadFailure<List<ReceiptShop>>(:final Failure failure):
        emit(
          state.copyWith(
            phase: ReceiptSubmissionPhase.loadFailed,
            loadFailure: failure,
            shops: const <ReceiptShop>[],
            products: const <ReceiptProduct>[],
          ),
        );
        return;

      case ReceiptReadSuccess<List<ReceiptShop>>(
        :final List<ReceiptShop> value,
      ):
        final List<ReceiptProduct> products = switch (productsResult) {
          ReceiptReadSuccess<List<ReceiptProduct>>(
            :final List<ReceiptProduct> value,
          ) =>
            value,
          ReceiptReadFailure<List<ReceiptProduct>>() =>
            const <ReceiptProduct>[],
        };
        final Failure? productsFailure = switch (productsResult) {
          ReceiptReadFailure<List<ReceiptProduct>>(:final Failure failure) =>
            failure,
          ReceiptReadSuccess<List<ReceiptProduct>>() => null,
        };

        emit(
          state.copyWith(
            phase: ReceiptSubmissionPhase.ready,
            shops: value,
            products: products,
            clearLoadFailure: true,
            productsFailure: productsFailure,
            clearProductsFailure: productsFailure == null,
            // A shop that vanished from the list between loads must not stay
            // selected — it would be submitted and refused.
            clearSelectedShop:
                state.selectedShopId != null &&
                !value.any(
                  (ReceiptShop shop) => shop.shopId == state.selectedShopId,
                ),
          ),
        );

        // A file chosen before a reload survives it, so a retry after an outage
        // does not cost the person their photograph.
        if (state.file != null) {
          emit(state.copyWith(phase: ReceiptSubmissionPhase.fileSelected));
        }
    }
  }

  /// Chooses the shop this receipt belongs to.
  ///
  /// An id that is not in the loaded list is ignored. The backend would refuse
  /// it anyway; refusing it here keeps the visible selection and the submitted
  /// value from ever disagreeing.
  void selectShop(String shopId) {
    if (state.isBusy) {
      return;
    }
    if (!state.shops.any((ReceiptShop shop) => shop.shopId == shopId)) {
      return;
    }
    emit(
      state.copyWith(
        selectedShopId: shopId,
        // Choosing a different shop is a fresh attempt at the same receipt: a
        // previous `denied` or `rejected` no longer describes what will happen.
        phase: _phaseAfterEdit(),
        clearRejection: true,
      ),
    );
  }

  /// Opens the camera or the gallery and validates what comes back.
  Future<void> chooseImage(ReceiptImageOrigin origin) async {
    if (!state.canChooseFile) {
      return;
    }

    emit(
      state.copyWith(
        phase: ReceiptSubmissionPhase.validating,
        stage: ReceiptUploadStage.preparing,
        clearRejection: true,
      ),
    );

    final PickedReceiptImage? picked;
    try {
      picked = await _imageSource.pick(origin);
    } on ReceiptImagePickException {
      if (isClosed) {
        return;
      }
      // The picker itself failed. Operational, and safe to try again — never a
      // statement about permission.
      emit(
        state.copyWith(
          phase: ReceiptSubmissionPhase.retryable,
          clearStage: true,
        ),
      );
      return;
    }

    if (isClosed) {
      return;
    }

    if (picked == null) {
      // Cancelled. Any existing selection is left exactly as it was.
      emit(state.copyWith(phase: _phaseAfterEdit(), clearStage: true));
      return;
    }

    final ReceiptFileValidation validation = ReceiptFileValidator.validate(
      fileName: picked.fileName,
      bytes: picked.bytes,
    );

    switch (validation) {
      case ReceiptFileAccepted(:final ReceiptFile file):
        emit(
          state.copyWith(
            phase: ReceiptSubmissionPhase.fileSelected,
            file: file,
            clearStage: true,
            clearRejection: true,
            // A new receipt starts a new attempt; the previous result no longer
            // describes it.
            clearSubmissionId: true,
            clearSubmission: true,
            detailUnavailable: false,
          ),
        );

      case ReceiptFileRefused(:final ReceiptRejectionReason reason):
        // The refused file is deliberately NOT adopted, so a bad pick can never
        // replace a good selection the person already made.
        emit(
          state.copyWith(
            phase: ReceiptSubmissionPhase.rejected,
            rejection: reason,
            clearStage: true,
          ),
        );
    }
  }

  /// Discards the chosen receipt. An explicit user action, and the only way a
  /// selection is lost short of a confirmed success.
  void removeFile() {
    if (state.isBusy) {
      return;
    }
    emit(
      state.copyWith(
        phase: ReceiptSubmissionPhase.ready,
        clearFile: true,
        clearRejection: true,
        clearStage: true,
        clearSubmissionId: true,
        clearSubmission: true,
        detailUnavailable: false,
      ),
    );
  }

  /// Submits the chosen receipt for the chosen shop.
  ///
  /// The first line is the duplicate-tap guard: a second call while one is in
  /// flight returns immediately, so two taps can never become two submissions.
  Future<void> submit() async {
    if (!state.canSubmit) {
      return;
    }

    final ReceiptFile file = state.file!;
    final String shopId = state.selectedShop!.shopId;

    emit(
      state.copyWith(
        phase: ReceiptSubmissionPhase.submitting,
        stage: ReceiptUploadStage.uploading,
        clearRejection: true,
        clearSubmissionId: true,
        clearSubmission: true,
        detailUnavailable: false,
      ),
    );

    final ReceiptSubmissionOutcome outcome = await _repository.submitReceipt(
      shopId: shopId,
      file: file,
    );

    if (isClosed) {
      return;
    }

    switch (outcome) {
      case ReceiptSubmissionAccepted(:final String submissionId):
        await _confirm(submissionId);

      case ReceiptSubmissionDuplicate():
        emit(
          state.copyWith(
            phase: ReceiptSubmissionPhase.duplicate,
            clearStage: true,
          ),
        );

      case ReceiptSubmissionDenied():
        emit(
          state.copyWith(
            phase: ReceiptSubmissionPhase.denied,
            clearStage: true,
          ),
        );

      case ReceiptSubmissionUnauthenticated():
        emit(
          state.copyWith(
            phase: ReceiptSubmissionPhase.unauthenticated,
            clearStage: true,
          ),
        );

      case ReceiptSubmissionRefused(:final ReceiptRejectionReason reason):
        emit(
          state.copyWith(
            phase: ReceiptSubmissionPhase.rejected,
            rejection: reason,
            clearStage: true,
          ),
        );

      case ReceiptSubmissionUploadFailed():
      case ReceiptSubmissionUnavailable():
        emit(
          state.copyWith(
            phase: ReceiptSubmissionPhase.retryable,
            clearStage: true,
          ),
        );

      case ReceiptSubmissionUnconfirmed():
        // The receipt may already be stored. Nothing is resent; the history is
        // refreshed instead, because it is the only authority on what exists.
        emit(
          state.copyWith(
            phase: ReceiptSubmissionPhase.unconfirmed,
            clearStage: true,
          ),
        );
        onSubmissionSettled?.call();
    }
  }

  /// Reads the created row back and shows the status the database returned.
  ///
  /// A failure here does **not** downgrade the outcome. The function already
  /// said `submitted`, and the only thing a failed read costs is the detail —
  /// which [ReceiptSubmissionState.detailUnavailable] records.
  Future<void> _confirm(String submissionId) async {
    emit(
      state.copyWith(
        stage: ReceiptUploadStage.confirming,
        submissionId: submissionId,
      ),
    );

    final ReceiptResult<ReceiptSubmission?> result = await _repository
        .submission(submissionId);

    if (isClosed) {
      return;
    }

    final ReceiptSubmission? submission = switch (result) {
      ReceiptReadSuccess<ReceiptSubmission?>(:final ReceiptSubmission? value) =>
        value,
      ReceiptReadFailure<ReceiptSubmission?>() => null,
    };

    emit(
      state.copyWith(
        phase: ReceiptSubmissionPhase.success,
        stage: ReceiptUploadStage.complete,
        submissionId: submissionId,
        submission: submission,
        clearSubmission: submission == null,
        detailUnavailable: submission == null,
        // The receipt is stored. Holding the bytes any longer serves nothing and
        // risks submitting them twice.
        clearFile: true,
        clearRejection: true,
      ),
    );

    onSubmissionSettled?.call();
  }

  /// Clears the finished submission and returns to an empty form, keeping the
  /// shops and the product reference list.
  void startAnother() {
    emit(
      state.copyWith(
        phase: ReceiptSubmissionPhase.ready,
        clearFile: true,
        clearStage: true,
        clearRejection: true,
        clearSubmissionId: true,
        clearSubmission: true,
        detailUnavailable: false,
      ),
    );
  }

  /// Drops every piece of private data this cubit holds.
  ///
  /// Called when the signed-in person changes. The shell is torn down on a
  /// session change and this cubit closed with it, so the memory goes either
  /// way; clearing explicitly means the guarantee does not depend on the router
  /// happening to unmount the right subtree.
  void clear() {
    emit(const ReceiptSubmissionState(phase: ReceiptSubmissionPhase.ready));
  }

  /// The phase an edit returns to: a chosen file, or an empty form.
  ///
  /// Three phases survive an edit, because changing the shop does not change
  /// what they say. A confirmed success is history; an ended session is still
  /// ended; and a duplicate is keyed on the file's hash and the submitter, not
  /// on the shop, so the same bytes would be refused at any shop. Only a
  /// different receipt clears it.
  ReceiptSubmissionPhase _phaseAfterEdit() {
    if (state.phase == ReceiptSubmissionPhase.success ||
        state.phase == ReceiptSubmissionPhase.unauthenticated ||
        state.phase == ReceiptSubmissionPhase.duplicate) {
      return state.phase;
    }
    return state.file == null
        ? ReceiptSubmissionPhase.ready
        : ReceiptSubmissionPhase.fileSelected;
  }
}
