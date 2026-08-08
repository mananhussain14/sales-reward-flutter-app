import 'package:sale_reward/features/receipts/domain/entities/receipt_product_proposal_line.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_product_selection.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_with_products_outcome.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_with_products_result.dart';
import 'dart:async';

import 'package:sale_reward/features/receipts/domain/entities/extracted_value.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_civil_date.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_civil_time.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_confirmation.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_confirmation_entry_mode.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_confirmation_field.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_confirmation_input.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_confirmation_outcome.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_confirmation_result.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_currency_minor_unit.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_failure_code.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_line_item.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_problem.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_request_outcome.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_request_result.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_status.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_warning_code.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_image_preview.dart';
import 'package:sale_reward/features/receipts/domain/repositories/receipt_extraction_repository.dart';
import 'package:sale_reward/features/receipts/domain/repositories/receipt_extraction_result.dart';

/// The receipt the review fixtures are about.
const String reviewSubmissionId = '3f1c9c2a-5b7e-4c1d-9a2b-6d8e0f1a2b3c';
const String reviewExtractionId = '7a2b4c6d-8e0f-4a1b-9c2d-3e4f5a6b7c8d';
const String reviewConfirmationId = 'b1c2d3e4-f5a6-4b7c-8d9e-0f1a2b3c4d5e';

/// A successful reading of a two-minor-unit AED receipt.
///
/// The ordinary case, so a test that departs from it says so. Every value is a
/// domain entity: no fixture here is a raw map, because no raw map ever reaches
/// this layer in the real application either.
ReceiptExtraction succeededExtraction({
  ReceiptExtractionStatus status = ReceiptExtractionStatus.succeeded,
  int attemptNumber = 1,
  int attemptsUsed = 1,
  int attemptsRemaining = 2,
  bool retryAllowed = false,
  bool manualConfirmationAllowed = true,
  bool confirmationExists = false,
  ReceiptExtractionFailureCode? failureCode,
  List<ReceiptExtractionWarningCode> warningCodes =
      const <ReceiptExtractionWarningCode>[],
  ExtractedValue<int> total = const ExtractedValue<int>(
    value: 12550,
    sourceText: 'AED 125.50',
    confidence: 0.96,
  ),
  ExtractedValue<String> merchantName = const ExtractedValue<String>(
    value: 'Marina Pharmacy',
    sourceText: 'MARINA  PHARMACY LLC',
    confidence: 0.94,
  ),
  ExtractedValue<String> currencyCode = const ExtractedValue<String>(
    value: 'AED',
    sourceText: 'AED',
    confidence: 0.99,
  ),
  int? currencyMinorUnit = 2,
  int lineItemCount = 2,
}) {
  return ReceiptExtraction(
    submissionId: reviewSubmissionId,
    extractionId: reviewExtractionId,
    status: status,
    attemptNumber: attemptNumber,
    attemptsUsed: attemptsUsed,
    attemptsRemaining: attemptsRemaining,
    retryAllowed: retryAllowed,
    manualConfirmationAllowed: manualConfirmationAllowed,
    confirmationExists: confirmationExists,
    failureCode: failureCode,
    requestedAt: DateTime.utc(2026, 7, 25, 9, 30),
    completedAt: DateTime.utc(2026, 7, 25, 9, 30, 4),
    merchantName: merchantName,
    documentNumber: const ExtractedValue<String>(
      value: 'INV-2026/004512',
      sourceText: 'Invoice INV-2026/004512',
      confidence: 0.88,
    ),
    transactionDate: const ExtractedValue<ReceiptCivilDate>(
      value: ReceiptCivilDate(2026, 7, 25),
      sourceText: '25/07/2026',
      confidence: 0.97,
    ),
    transactionTime: const ExtractedValue<ReceiptCivilTime>(
      value: ReceiptCivilTime(9, 24),
      sourceText: '09:24',
      confidence: 0.81,
    ),
    currencyCode: currencyCode,
    currencyMinorUnit: currencyMinorUnit,
    total: total,
    subtotal: const ExtractedValue<int>(
      value: 11952,
      sourceText: '119.52',
      confidence: 0.9,
    ),
    taxTotal: const ExtractedValue<int>(
      value: 598,
      sourceText: '5.98',
      confidence: 0.9,
    ),
    warningCodes: warningCodes,
    lineItemCount: lineItemCount,
  );
}

/// An attempt that is still in flight.
ReceiptExtraction openExtraction({
  ReceiptExtractionStatus status = ReceiptExtractionStatus.queued,
}) {
  return ReceiptExtraction(
    submissionId: reviewSubmissionId,
    extractionId: reviewExtractionId,
    status: status,
    attemptNumber: 1,
    attemptsUsed: 1,
    attemptsRemaining: 2,
    retryAllowed: false,
    // Blocked while an attempt is open — one of the only two things that block
    // it, and neither is a mode gate.
    manualConfirmationAllowed: false,
    confirmationExists: false,
    requestedAt: DateTime.utc(2026, 7, 25, 9, 30),
    merchantName: const ExtractedValue<String>(),
    documentNumber: const ExtractedValue<String>(),
    transactionDate: const ExtractedValue<ReceiptCivilDate>(),
    transactionTime: const ExtractedValue<ReceiptCivilTime>(),
    currencyCode: const ExtractedValue<String>(),
    total: const ExtractedValue<int>(),
    subtotal: const ExtractedValue<int>(),
    taxTotal: const ExtractedValue<int>(),
    warningCodes: const <ReceiptExtractionWarningCode>[],
    lineItemCount: 0,
  );
}

/// An attempt that ended without a reading.
ReceiptExtraction failedExtraction({
  ReceiptExtractionFailureCode code =
      ReceiptExtractionFailureCode.imageNotAReceipt,
  int attemptsUsed = 1,
  int attemptsRemaining = 2,
  bool retryAllowed = true,
}) {
  return ReceiptExtraction(
    submissionId: reviewSubmissionId,
    extractionId: reviewExtractionId,
    status: ReceiptExtractionStatus.failed,
    attemptNumber: attemptsUsed,
    attemptsUsed: attemptsUsed,
    attemptsRemaining: attemptsRemaining,
    retryAllowed: retryAllowed,
    manualConfirmationAllowed: true,
    confirmationExists: false,
    failureCode: code,
    requestedAt: DateTime.utc(2026, 7, 25, 9, 30),
    completedAt: DateTime.utc(2026, 7, 25, 9, 30, 6),
    merchantName: const ExtractedValue<String>(),
    documentNumber: const ExtractedValue<String>(),
    transactionDate: const ExtractedValue<ReceiptCivilDate>(),
    transactionTime: const ExtractedValue<ReceiptCivilTime>(),
    currencyCode: const ExtractedValue<String>(),
    total: const ExtractedValue<int>(),
    subtotal: const ExtractedValue<int>(),
    taxTotal: const ExtractedValue<int>(),
    warningCodes: const <ReceiptExtractionWarningCode>[],
    lineItemCount: 0,
  );
}

ReceiptExtractionRequestResult requestResult({
  ReceiptExtractionRequestOutcome outcome =
      ReceiptExtractionRequestOutcome.succeeded,
  int attemptsUsed = 1,
  int attemptsRemaining = 2,
  bool retryAllowed = false,
  bool manualConfirmationAllowed = true,
  ReceiptExtraction? extraction,
}) {
  return ReceiptExtractionRequestResult(
    outcome: outcome,
    attemptsUsed: attemptsUsed,
    attemptsRemaining: attemptsRemaining,
    retryAllowed: retryAllowed,
    manualConfirmationAllowed: manualConfirmationAllowed,
    extraction: extraction,
  );
}

ReceiptConfirmation storedConfirmation({
  ReceiptConfirmationEntryMode entryMode =
      ReceiptConfirmationEntryMode.extracted,
  List<ReceiptConfirmationField> changedFields =
      const <ReceiptConfirmationField>[],
}) {
  return ReceiptConfirmation(
    confirmationId: reviewConfirmationId,
    entryMode: entryMode,
    changedFields: changedFields,
    sourceExtractionId: reviewExtractionId,
    transactionDate: const ReceiptCivilDate(2026, 7, 25),
    transactionTime: const ReceiptCivilTime(9, 24),
    currencyCode: 'AED',
    currencyMinorUnit: 2,
    totalMinor: 12550,
    subtotalMinor: 11952,
    taxTotalMinor: 598,
    merchantName: 'Marina Pharmacy',
    documentNumber: 'INV-2026/004512',
    confirmedAt: DateTime.utc(2026, 7, 25, 10, 2),
  );
}

/// One answer from `confirm_receipt_with_products`.
///
/// Defaults to the ordinary `CONFIRMED`, so a test that wants
/// `ALREADY_CONFIRMED`, `CONFLICT` or a token this build cannot read says so
/// rather than assembling four fields to get back to the common case.
ReceiptExtractionResult<ReceiptWithProductsResult> withProductsResult({
  ReceiptWithProductsOutcome outcome = ReceiptWithProductsOutcome.confirmed,
  int lineCount = 1,
  bool changed = true,
  String? confirmationId = reviewConfirmationId,
}) {
  return ReceiptExtractionSuccess<ReceiptWithProductsResult>(
    ReceiptWithProductsResult(
      outcome: outcome,
      // Null on the conflict branch, which is the branch that deliberately
      // identifies nothing — mirrored here so a test cannot accidentally prove
      // the screen hides an id the RPC never sent.
      confirmationId: outcome == ReceiptWithProductsOutcome.conflict
          ? null
          : confirmationId,
      lineCount: lineCount,
      changed: changed,
    ),
  );
}

/// A stored proposal, as `get_my_receipt_product_proposal` returns one.
const List<ReceiptProductProposalLine> storedProposalLines =
    <ReceiptProductProposalLine>[
      ReceiptProductProposalLine(
        lineNumber: 1,
        quantity: 2,
        productCode: 'SKU-A',
        productName: 'Product A',
        productStatus: 'ACTIVE',
      ),
    ];

/// The four widths the seeded list actually contains, as the lookup returns
/// them. There is no map here: these are fixtures for a fake, and the real
/// client asks the backend for every one of them.
ReceiptExtractionResult<ReceiptCurrencyMinorUnit?> currencyWidth(
  String code,
  int minorUnit,
) {
  return ReceiptExtractionSuccess<ReceiptCurrencyMinorUnit?>(
    ReceiptCurrencyMinorUnit(currencyCode: code, minorUnit: minorUnit),
  );
}

/// Zero rows: this system does not accept that currency.
const ReceiptExtractionResult<ReceiptCurrencyMinorUnit?> unsupportedCurrency =
    ReceiptExtractionSuccess<ReceiptCurrencyMinorUnit?>(null);

const List<ReceiptExtractionLineItem> reviewLineItems =
    <ReceiptExtractionLineItem>[
      ReceiptExtractionLineItem(
        lineNumber: 1,
        description: 'Paracetamol 500mg',
        descriptionSourceText: 'PARACETAMOL 500MG  x2',
        quantity: 2,
        unitPriceMinor: 1250,
        lineTotalMinor: 2500,
        confidence: 0.87,
      ),
      ReceiptExtractionLineItem(
        lineNumber: 2,
        description: 'Vitamin D3',
        quantity: 1,
        lineTotalMinor: 10050,
      ),
    ];

/// Ten lines, each missing something different.
///
/// Long enough to prove nothing truncates it, and deliberately ragged so the
/// "a field the provider did not read is not invented" rule is exercised by
/// ordinary data rather than by one contrived row:
///
/// * 1 — everything read, and a description long enough to wrap on a phone.
/// * 2 — no quantity. It must not become 1.
/// * 3 — no unit price. It must not become the amount divided by the quantity.
/// * 4 — no line total. It must not become the unit price times the quantity.
/// * 5 — no description at all.
/// * 6 — a **zero** unit price and a **zero** amount. Zero is a reading, not a
///   gap, and it is written as a figure.
/// * 7 — a fractional quantity, the one genuinely non-integer value there is.
/// * 8 — only a description; every figure absent.
/// * 9, 10 — ordinary, so the tail of the list is plainly present.
const List<ReceiptExtractionLineItem> tenMixedLineItems =
    <ReceiptExtractionLineItem>[
      ReceiptExtractionLineItem(
        lineNumber: 1,
        description: 'Front and rear brake cables, stainless, with ferrules',
        quantity: 1,
        unitPriceMinor: 10000,
        lineTotalMinor: 10000,
      ),
      ReceiptExtractionLineItem(
        lineNumber: 2,
        description: 'Chain lubricant',
        unitPriceMinor: 850,
        lineTotalMinor: 850,
      ),
      ReceiptExtractionLineItem(
        lineNumber: 3,
        description: 'Handlebar tape',
        quantity: 2,
        lineTotalMinor: 3000,
      ),
      ReceiptExtractionLineItem(
        lineNumber: 4,
        description: 'Inner tube 700x25',
        quantity: 3,
        unitPriceMinor: 600,
      ),
      // 17.00 rather than 15.00 on purpose: line 3's amount divided by its
      // quantity is 15.00, and that figure must appear nowhere in the panel for
      // the "a unit price is never derived" assertion to mean anything.
      ReceiptExtractionLineItem(
        lineNumber: 5,
        quantity: 1,
        unitPriceMinor: 1700,
        lineTotalMinor: 1700,
      ),
      ReceiptExtractionLineItem(
        lineNumber: 6,
        description: 'Promotional water bottle',
        quantity: 1,
        unitPriceMinor: 0,
        lineTotalMinor: 0,
      ),
      ReceiptExtractionLineItem(
        lineNumber: 7,
        description: 'Cable housing',
        quantity: 1.5,
        unitPriceMinor: 400,
        lineTotalMinor: 600,
      ),
      ReceiptExtractionLineItem(lineNumber: 8, description: 'Workshop labour'),
      ReceiptExtractionLineItem(
        lineNumber: 9,
        description: 'Bar end plugs',
        quantity: 2,
        unitPriceMinor: 250,
        lineTotalMinor: 500,
      ),
      ReceiptExtractionLineItem(
        lineNumber: 10,
        description: 'Disc brake pads',
        quantity: 1,
        unitPriceMinor: 2200,
        lineTotalMinor: 2200,
      ),
    ];

/// One fully-populated line, for the currency-width tests.
///
/// The same integers under every width: `1` at 0 decimals, `1.000` at 3. What
/// changes between those tests is only the currency the *reading* reported.
const List<ReceiptExtractionLineItem> oneCompleteLineItem =
    <ReceiptExtractionLineItem>[
      ReceiptExtractionLineItem(
        lineNumber: 1,
        description: 'Front and rear brake cables',
        quantity: 1,
        unitPriceMinor: 1000,
        lineTotalMinor: 1000,
      ),
    ];

/// One line whose integer reads very differently under two currencies.
///
/// `1250` is AED 12.50 at the extraction's own width of two, and ¥1250 at JPY's
/// zero — a hundredfold difference from one edit to a form field. That gap is
/// the whole subject of the line-item ownership tests, which is why the fixture
/// is a single line: the assertion is about which currency described it, not
/// about how many there were.
const List<ReceiptExtractionLineItem> oneScaledLineItem =
    <ReceiptExtractionLineItem>[
      ReceiptExtractionLineItem(
        lineNumber: 1,
        description: 'Paracetamol 500mg',
        descriptionSourceText: 'PARACETAMOL 500MG',
        quantity: 1,
        lineTotalMinor: 1250,
      ),
    ];

/// A scriptable [ReceiptExtractionRepository] that never touches a socket.
///
/// Every method records its calls, so a test can assert that a **mutating**
/// operation happened exactly once. The queues let one test drive a whole
/// `QUEUED → PROCESSING → SUCCEEDED` sequence without a timer or a real clock.
class FakeReceiptExtractionRepository implements ReceiptExtractionRepository {
  FakeReceiptExtractionRepository({
    this.requestResults,
    this.extractionResults,
    this.confirmResults,
    this.confirmationResults,
    this.previewResults,
    this.lineItemResults,
    this.confirmWithProductsResults,
    this.productProposalResults,
  });

  /// Answers for successive `requestExtraction` calls. The last one repeats.
  List<ReceiptExtractionResult<ReceiptExtractionRequestResult>>? requestResults;

  /// Answers for successive `extraction` calls. The last one repeats.
  List<ReceiptExtractionResult<ReceiptExtraction>>? extractionResults;

  List<ReceiptExtractionResult<ReceiptConfirmationResult>>? confirmResults;
  List<ReceiptExtractionResult<ReceiptConfirmation?>>? confirmationResults;
  List<ReceiptExtractionResult<ReceiptImagePreview>>? previewResults;
  List<ReceiptExtractionResult<List<ReceiptExtractionLineItem>>>?
  lineItemResults;

  /// Phase 1D-B. Answers for successive atomic header-and-products
  /// confirmations, and for successive proposal reads. The last one repeats.
  List<ReceiptExtractionResult<ReceiptWithProductsResult>>?
  confirmWithProductsResults;
  List<ReceiptExtractionResult<List<ReceiptProductProposalLine>>>?
  productProposalResults;

  /// Every atomic confirmation this fake was asked to perform.
  ///
  /// A list, not a counter, so a test can assert BOTH that a double tap
  /// produced exactly one call and that the one call carried the right lines.
  final List<
    ({ReceiptConfirmationInput input, ReceiptProductSelection selection})
  >
  confirmWithProductsCalls =
      <({ReceiptConfirmationInput input, ReceiptProductSelection selection})>[];

  final List<String> productProposalCalls = <String>[];

  /// A gate a test may hold open so the atomic write stays genuinely in flight.
  ///
  /// The only way to observe "a second act while the first is still
  /// travelling", and the pending and slow states, without a sleep-and-hope.
  Completer<ReceiptExtractionResult<ReceiptWithProductsResult>>?
  confirmWithProductsGate;

  /// Answers for successive currency lookups, keyed by normalized code. A code
  /// with no entry answers `null`, which is the backend's "unsupported".
  final Map<String, ReceiptExtractionResult<ReceiptCurrencyMinorUnit?>>
  currencyResults =
      <String, ReceiptExtractionResult<ReceiptCurrencyMinorUnit?>>{};

  /// Completers a test may hold open, so two lookups can be in flight at once
  /// and settled out of order. This is what makes the stale-response race
  /// reproducible without a timer.
  final Map<
    String,
    Completer<ReceiptExtractionResult<ReceiptCurrencyMinorUnit?>>
  >
  currencyGates =
      <String, Completer<ReceiptExtractionResult<ReceiptCurrencyMinorUnit?>>>{};

  final List<String> requestedIds = <String>[];
  final List<String> extractionIds = <String>[];
  final List<String> previewIds = <String>[];
  final List<String> lineItemIds = <String>[];
  final List<String> confirmationIds = <String>[];
  final List<String> currencyCodes = <String>[];
  final List<ReceiptConfirmationInput> confirmInputs =
      <ReceiptConfirmationInput>[];

  int _previewMints = 0;

  T _next<T>(List<T>? queue, int callIndex, T fallback) {
    if (queue == null || queue.isEmpty) {
      return fallback;
    }
    return queue[callIndex < queue.length ? callIndex : queue.length - 1];
  }

  @override
  Future<ReceiptExtractionResult<ReceiptExtractionRequestResult>>
  requestExtraction(String submissionId) async {
    final int index = requestedIds.length;
    requestedIds.add(submissionId);
    return _next<ReceiptExtractionResult<ReceiptExtractionRequestResult>>(
      requestResults,
      index,
      ReceiptExtractionSuccess<ReceiptExtractionRequestResult>(
        requestResult(extraction: succeededExtraction()),
      ),
    );
  }

  @override
  Future<ReceiptExtractionResult<ReceiptExtraction>> extraction(
    String submissionId,
  ) async {
    final int index = extractionIds.length;
    extractionIds.add(submissionId);
    return _next<ReceiptExtractionResult<ReceiptExtraction>>(
      extractionResults,
      index,
      ReceiptExtractionSuccess<ReceiptExtraction>(succeededExtraction()),
    );
  }

  @override
  Future<ReceiptExtractionResult<List<ReceiptExtractionLineItem>>> lineItems(
    String submissionId,
  ) async {
    final int index = lineItemIds.length;
    lineItemIds.add(submissionId);
    return _next<ReceiptExtractionResult<List<ReceiptExtractionLineItem>>>(
      lineItemResults,
      index,
      const ReceiptExtractionSuccess<List<ReceiptExtractionLineItem>>(
        reviewLineItems,
      ),
    );
  }

  @override
  Future<ReceiptExtractionResult<ReceiptImagePreview>> imagePreview(
    String submissionId,
  ) async {
    final int index = previewIds.length;
    previewIds.add(submissionId);
    _previewMints++;
    return _next<ReceiptExtractionResult<ReceiptImagePreview>>(
      previewResults,
      index,
      // A different URL on every mint, and the SAME expiry — which is exactly
      // the case that makes two previews compare equal, and exactly what the
      // revision counter exists to survive.
      ReceiptExtractionSuccess<ReceiptImagePreview>(
        ReceiptImagePreview(
          url: 'https://example.invalid/preview/$_previewMints',
          expiresInSeconds: 120,
        ),
      ),
    );
  }

  @override
  Future<ReceiptExtractionResult<ReceiptCurrencyMinorUnit?>> currencyMinorUnit(
    String currencyCode,
  ) {
    currencyCodes.add(currencyCode);
    final Completer<ReceiptExtractionResult<ReceiptCurrencyMinorUnit?>>? gate =
        currencyGates[currencyCode];
    if (gate != null) {
      return gate.future;
    }
    return Future<ReceiptExtractionResult<ReceiptCurrencyMinorUnit?>>.value(
      currencyResults[currencyCode] ??
          const ReceiptExtractionSuccess<ReceiptCurrencyMinorUnit?>(null),
    );
  }

  @override
  Future<ReceiptExtractionResult<ReceiptConfirmationResult>> confirm(
    ReceiptConfirmationInput input,
  ) async {
    final int index = confirmInputs.length;
    confirmInputs.add(input);
    return _next<ReceiptExtractionResult<ReceiptConfirmationResult>>(
      confirmResults,
      index,
      const ReceiptExtractionSuccess<ReceiptConfirmationResult>(
        ReceiptConfirmationResult(
          outcome: ReceiptConfirmationOutcome.confirmed,
          confirmationId: reviewConfirmationId,
          entryMode: ReceiptConfirmationEntryMode.extracted,
          changedFields: <ReceiptConfirmationField>[],
        ),
      ),
    );
  }

  @override
  Future<ReceiptExtractionResult<ReceiptConfirmation?>> confirmation(
    String submissionId,
  ) async {
    final int index = confirmationIds.length;
    confirmationIds.add(submissionId);
    return _next<ReceiptExtractionResult<ReceiptConfirmation?>>(
      confirmationResults,
      index,
      ReceiptExtractionSuccess<ReceiptConfirmation?>(storedConfirmation()),
    );
  }

  @override
  Future<ReceiptExtractionResult<ReceiptWithProductsResult>>
  confirmWithProducts(
    ReceiptConfirmationInput input,
    ReceiptProductSelection selection,
  ) async {
    confirmWithProductsCalls.add((input: input, selection: selection));
    final Completer<ReceiptExtractionResult<ReceiptWithProductsResult>>? gate =
        confirmWithProductsGate;
    if (gate != null) {
      return gate.future;
    }
    final List<ReceiptExtractionResult<ReceiptWithProductsResult>>? queue =
        confirmWithProductsResults;
    if (queue == null || queue.isEmpty) {
      return const ReceiptExtractionFailed<ReceiptWithProductsResult>(
        ExtractionNetworkProblem(),
      );
    }
    return queue.length == 1 ? queue.first : queue.removeAt(0);
  }

  @override
  Future<ReceiptExtractionResult<List<ReceiptProductProposalLine>>>
  productProposal(String submissionId) async {
    productProposalCalls.add(submissionId);
    final List<ReceiptExtractionResult<List<ReceiptProductProposalLine>>>?
    queue = productProposalResults;
    if (queue == null || queue.isEmpty) {
      return const ReceiptExtractionSuccess<List<ReceiptProductProposalLine>>(
        <ReceiptProductProposalLine>[],
      );
    }
    return queue.length == 1 ? queue.first : queue.removeAt(0);
  }
}

/// A repository whose every call refuses with one problem.
class RefusingReceiptExtractionRepository
    implements ReceiptExtractionRepository {
  RefusingReceiptExtractionRepository(this.problem);

  final ReceiptExtractionProblem problem;

  @override
  Future<ReceiptExtractionResult<ReceiptExtractionRequestResult>>
  requestExtraction(String submissionId) async =>
      ReceiptExtractionFailed<ReceiptExtractionRequestResult>(problem);

  @override
  Future<ReceiptExtractionResult<ReceiptExtraction>> extraction(
    String submissionId,
  ) async => ReceiptExtractionFailed<ReceiptExtraction>(problem);

  @override
  Future<ReceiptExtractionResult<List<ReceiptExtractionLineItem>>> lineItems(
    String submissionId,
  ) async => ReceiptExtractionFailed<List<ReceiptExtractionLineItem>>(problem);

  @override
  Future<ReceiptExtractionResult<ReceiptImagePreview>> imagePreview(
    String submissionId,
  ) async => ReceiptExtractionFailed<ReceiptImagePreview>(problem);

  @override
  Future<ReceiptExtractionResult<ReceiptCurrencyMinorUnit?>> currencyMinorUnit(
    String currencyCode,
  ) async => ReceiptExtractionFailed<ReceiptCurrencyMinorUnit?>(problem);

  @override
  Future<ReceiptExtractionResult<ReceiptConfirmationResult>> confirm(
    ReceiptConfirmationInput input,
  ) async => ReceiptExtractionFailed<ReceiptConfirmationResult>(problem);

  @override
  Future<ReceiptExtractionResult<ReceiptConfirmation?>> confirmation(
    String submissionId,
  ) async => ReceiptExtractionFailed<ReceiptConfirmation?>(problem);

  @override
  Future<ReceiptExtractionResult<ReceiptWithProductsResult>>
  confirmWithProducts(
    ReceiptConfirmationInput input,
    ReceiptProductSelection selection,
  ) async => const ReceiptExtractionFailed<ReceiptWithProductsResult>(
    ExtractionNetworkProblem(),
  );

  @override
  Future<ReceiptExtractionResult<List<ReceiptProductProposalLine>>>
  productProposal(String submissionId) async =>
      const ReceiptExtractionFailed<List<ReceiptProductProposalLine>>(
        ExtractionNetworkProblem(),
      );
}
