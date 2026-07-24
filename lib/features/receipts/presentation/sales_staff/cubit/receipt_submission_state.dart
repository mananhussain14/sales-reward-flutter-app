part of 'receipt_submission_cubit.dart';

/// Where a submission has reached.
///
/// One enum rather than a sealed hierarchy, because every phase shares the same
/// surrounding data — the shops, the products, the chosen shop and the chosen
/// file all outlive a failure and must not be re-fetched to recover from one.
/// A sealed state per phase would have to carry all of it in every case, or
/// throw it away and reload; both are worse.
enum ReceiptSubmissionPhase {
  /// The shops and the product reference list are being read.
  initialLoading,

  /// The assigned-shop read failed. The form cannot be shown, because a receipt
  /// is always submitted against one assigned shop.
  loadFailed,

  /// Loaded, with no receipt chosen yet.
  ready,

  /// A receipt image has been chosen and accepted by the client-side pre-check.
  fileSelected,

  /// A picked image is being read and checked.
  validating,

  /// The multipart request is in flight, or its result is being confirmed.
  /// [ReceiptSubmissionState.stage] says which.
  submitting,

  /// `200 submitted`. The receipt is stored.
  success,

  /// `409` — this person already submitted these exact bytes.
  duplicate,

  /// `403` — the chosen shop is not one this person may submit against.
  denied,

  /// `401` — the session ended. Signing in again is the only way forward.
  unauthenticated,

  /// `400` — the file or the shop id was refused.
  /// [ReceiptSubmissionState.rejection] says which.
  rejected,

  /// `502`/`503`, or a client-side pick failure. Definitely did not complete,
  /// and safe to try again.
  retryable,

  /// The transport gave no answer this client can trust. The receipt **may**
  /// have been stored, so the app never resends on its own.
  unconfirmed,
}

/// The four stages a submission passes through.
///
/// Stage-based, not percentage-based, and deliberately so. Neither
/// `package:http`'s browser client nor its IO client exposes reliable upload
/// progress for a multipart body across Android, iOS and web, so any percentage
/// this app displayed would be invented. A stage that is *true* beats a number
/// that is not.
enum ReceiptUploadStage {
  /// Reading and checking the chosen image.
  preparing,

  /// The multipart request is in flight.
  uploading,

  /// Accepted; reading the stored row back with
  /// `get_my_receipt_submission(uuid)`.
  confirming,

  /// Done.
  complete;

  /// The label shown beside the progress indicator.
  String get label => switch (this) {
    preparing => 'Preparing receipt',
    uploading => 'Uploading receipt',
    confirming => 'Confirming submission',
    complete => 'Complete',
  };
}

/// Everything the submit screen renders from.
///
/// ## No raw backend map appears here
///
/// Every field is a domain entity, an enum or a primitive. A `Map<String,
/// dynamic>` from the SDK stops at the parser, so no widget can reach a column
/// the backend did not intend to expose, and no future edit can render one by
/// accident.
final class ReceiptSubmissionState extends Equatable {
  const ReceiptSubmissionState({
    this.phase = ReceiptSubmissionPhase.initialLoading,
    this.shops = const <ReceiptShop>[],
    this.products = const <ReceiptProduct>[],
    this.loadFailure,
    this.productsFailure,
    this.selectedShopId,
    this.file,
    this.stage,
    this.rejection,
    this.submissionId,
    this.submission,
    this.detailUnavailable = false,
  });

  final ReceiptSubmissionPhase phase;

  /// The caller's assigned shops. Empty is a legitimate answer and is rendered
  /// as "no shops assigned yet", never as a denial.
  final List<ReceiptShop> shops;

  /// Read-only reference data. Nothing chosen from it is ever submitted.
  final List<ReceiptProduct> products;

  /// Why the assigned-shop read failed. Set only in
  /// [ReceiptSubmissionPhase.loadFailed].
  final Failure? loadFailure;

  /// Why the product reference read failed.
  ///
  /// Kept separate from [loadFailure] on purpose: products are context, not a
  /// prerequisite, so their absence degrades one section rather than blocking a
  /// submission that would otherwise succeed.
  final Failure? productsFailure;

  final String? selectedShopId;

  /// The chosen receipt, held in memory only.
  final ReceiptFile? file;

  /// The stage to display while [phase] is
  /// [ReceiptSubmissionPhase.validating] or
  /// [ReceiptSubmissionPhase.submitting], and after success.
  final ReceiptUploadStage? stage;

  /// Why a file or shop was refused — by the client-side pre-check, or by the
  /// backend's `400`.
  final ReceiptRejectionReason? rejection;

  /// The id the Edge Function returned. Present on success even when the
  /// follow-up detail read did not succeed.
  final String? submissionId;

  /// The trusted row read back with `get_my_receipt_submission(uuid)`.
  final ReceiptSubmission? submission;

  /// True when the submission succeeded but the confirming read did not return
  /// the row.
  ///
  /// The submission is still a success — the function said so — and this only
  /// changes how much detail can be shown. It must never be rendered as a
  /// failure.
  final bool detailUnavailable;

  /// The shop the person picked, resolved against the loaded list.
  ReceiptShop? get selectedShop {
    final String? id = selectedShopId;
    if (id == null) {
      return null;
    }
    for (final ReceiptShop shop in shops) {
      if (shop.shopId == id) {
        return shop;
      }
    }
    return null;
  }

  /// Whether the screen is doing something the user must not interrupt.
  bool get isBusy =>
      phase == ReceiptSubmissionPhase.initialLoading ||
      phase == ReceiptSubmissionPhase.validating ||
      phase == ReceiptSubmissionPhase.submitting;

  /// Whether the submit button may fire.
  ///
  /// False while busy — which is the duplicate-tap guard's visible half; the
  /// cubit enforces the same rule again so a stale widget cannot get past it.
  ///
  /// False after a `409` as well: the duplicate index is keyed on the file's
  /// hash and the submitter, so resending the identical bytes can only ever
  /// produce the same answer. The way forward is a different receipt.
  bool get canSubmit {
    if (isBusy || file == null || selectedShop == null) {
      return false;
    }
    return switch (phase) {
      ReceiptSubmissionPhase.fileSelected ||
      ReceiptSubmissionPhase.rejected ||
      ReceiptSubmissionPhase.denied ||
      ReceiptSubmissionPhase.retryable ||
      ReceiptSubmissionPhase.unconfirmed => true,
      ReceiptSubmissionPhase.initialLoading ||
      ReceiptSubmissionPhase.loadFailed ||
      ReceiptSubmissionPhase.ready ||
      ReceiptSubmissionPhase.validating ||
      ReceiptSubmissionPhase.submitting ||
      ReceiptSubmissionPhase.success ||
      ReceiptSubmissionPhase.duplicate ||
      ReceiptSubmissionPhase.unauthenticated => false,
    };
  }

  /// Whether the person may choose or replace a receipt right now.
  bool get canChooseFile =>
      !isBusy &&
      phase != ReceiptSubmissionPhase.initialLoading &&
      phase != ReceiptSubmissionPhase.loadFailed &&
      phase != ReceiptSubmissionPhase.success;

  ReceiptSubmissionState copyWith({
    ReceiptSubmissionPhase? phase,
    List<ReceiptShop>? shops,
    List<ReceiptProduct>? products,
    Failure? loadFailure,
    bool clearLoadFailure = false,
    Failure? productsFailure,
    bool clearProductsFailure = false,
    String? selectedShopId,
    bool clearSelectedShop = false,
    ReceiptFile? file,
    bool clearFile = false,
    ReceiptUploadStage? stage,
    bool clearStage = false,
    ReceiptRejectionReason? rejection,
    bool clearRejection = false,
    String? submissionId,
    bool clearSubmissionId = false,
    ReceiptSubmission? submission,
    bool clearSubmission = false,
    bool? detailUnavailable,
  }) {
    return ReceiptSubmissionState(
      phase: phase ?? this.phase,
      shops: shops ?? this.shops,
      products: products ?? this.products,
      loadFailure: clearLoadFailure ? null : (loadFailure ?? this.loadFailure),
      productsFailure: clearProductsFailure
          ? null
          : (productsFailure ?? this.productsFailure),
      selectedShopId: clearSelectedShop
          ? null
          : (selectedShopId ?? this.selectedShopId),
      file: clearFile ? null : (file ?? this.file),
      stage: clearStage ? null : (stage ?? this.stage),
      rejection: clearRejection ? null : (rejection ?? this.rejection),
      submissionId: clearSubmissionId
          ? null
          : (submissionId ?? this.submissionId),
      submission: clearSubmission ? null : (submission ?? this.submission),
      detailUnavailable: detailUnavailable ?? this.detailUnavailable,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    phase,
    shops,
    products,
    loadFailure,
    productsFailure,
    selectedShopId,
    // ReceiptFile has identity equality on purpose: a new selection is always a
    // new object, so a replacement always emits, and up to 10 MiB of bytes are
    // never deep-compared.
    file,
    stage,
    rejection,
    submissionId,
    submission,
    detailUnavailable,
  ];
}
