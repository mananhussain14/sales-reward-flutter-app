part of 'receipt_review_cubit.dart';

/// Where the review of one receipt has reached.
///
/// One enum rather than a sealed hierarchy, for the same reason
/// [ReceiptSubmissionPhase] is one: every phase shares the same surrounding
/// data — the attempt, the counters, the preview, the draft the person has been
/// typing into — and all of it must survive a failure rather than be thrown
/// away and reloaded.
enum ReceiptReviewPhase {
  /// Nothing has been asked for yet.
  initial,

  /// `request-receipt-extraction` is in flight. **Mutating**, and never
  /// retried on its own.
  requesting,

  /// An attempt exists and no worker has claimed it.
  queued,

  /// A worker holds the job.
  processing,

  /// The reading is stored. The extracted values are shown and are editable.
  succeeded,

  /// The attempt ended without a reading. `failure_code` says which of the
  /// three client-visible reasons applies.
  failed,

  /// All three attempts are spent. Manual confirmation may still be open.
  exhausted,

  /// No attempt was created and the backend deliberately did not say why.
  ///
  /// A shut gate and broken infrastructure are one answer on this contract, so
  /// there is no separate "runtime disabled" phase to sit beside this one.
  unavailable,

  /// `confirm_receipt_extraction` is in flight.
  confirming,

  /// A confirmation exists for this receipt. Terminal, and immutable.
  confirmed,

  /// The call produced no answer and asking again is reasonable.
  unreachable,

  /// The caller may not read this receipt, or has no session. Terminal: there
  /// is nothing on this screen that retrying would fix.
  blocked,
}

/// Where the short-lived image capability has reached.
enum ReceiptPreviewPhase { idle, loading, ready, failed }

/// Where the authoritative decimal width for the typed currency has reached.
///
/// A width is a property of a currency and only the backend knows it. Until one
/// of these reaches [resolved] **for the code currently in the field**, no typed
/// amount may become an integer, no decimal width may be claimed in the copy,
/// and no confirmation may be sent.
enum ReceiptCurrencyPhase {
  /// Nothing has been established, and nothing has been asked. Also where a
  /// half-typed code sits, and where a rejected scale is put back.
  unresolved,

  /// `get_receipt_currency_minor_unit` is in flight. A pure read.
  resolving,

  /// A width is known, and [ReceiptCurrencyResolution.resolvedCode] says which
  /// code it belongs to.
  resolved,

  /// The backend returned zero rows: this system will not accept that currency.
  /// Blocking, and never retried on a timer.
  unsupported,

  /// The lookup produced no answer. Recoverable, and the person may ask again.
  failed,
}

/// The authoritative decimal width for one currency code, and how it got here.
///
/// ## The width is bound to the code it was resolved for
///
/// [minorUnitFor] compares codes rather than handing out [minorUnit], which is
/// what makes carrying JOD's three decimals over to a newly typed AED
/// impossible to express. The moment somebody edits the currency field the
/// answer becomes null again — no invalidation step has to run and none can be
/// forgotten.
final class ReceiptCurrencyResolution extends Equatable {
  const ReceiptCurrencyResolution({
    this.phase = ReceiptCurrencyPhase.unresolved,
    this.requestedCode = '',
    this.resolvedCode,
    this.minorUnit,
    this.problem,
  });

  final ReceiptCurrencyPhase phase;

  /// The normalized code this resolution is about — what was typed, trimmed and
  /// upper-cased, at the moment the lookup was started.
  final String requestedCode;

  /// The normalized code the backend answered for. Never assumed to equal
  /// [requestedCode]: an answer about a different code is not this currency's
  /// width, and is refused rather than adopted.
  final String? resolvedCode;

  /// `0`, `2`, `3` or `4`. Never defaulted, and never present unless [phase] is
  /// [ReceiptCurrencyPhase.resolved].
  final int? minorUnit;

  /// Why the lookup produced no answer. A typed problem, never backend text.
  final ReceiptExtractionProblem? problem;

  /// The authoritative width for [code], or null when there is none **for that
  /// exact code**.
  int? minorUnitFor(String code) {
    if (phase != ReceiptCurrencyPhase.resolved) {
      return null;
    }
    final String? resolved = resolvedCode;
    final int? unit = minorUnit;
    if (resolved == null || unit == null || resolved != code) {
      return null;
    }
    return unit;
  }

  @override
  List<Object?> get props => <Object?>[
    phase,
    requestedCode,
    resolvedCode,
    minorUnit,
    problem,
  ];
}

/// One editable field of the confirmation form.
enum ReceiptReviewField {
  transactionDate,
  transactionTime,
  currencyCode,
  merchantName,
  documentNumber,
  total,
  subtotal,
  tax,
}

/// Why one field was refused before anything was sent.
///
/// A form-field discriminant and never backend text. Every rule below is
/// enforced again in SQL, and the backend's answer is the one that counts.
enum ReceiptReviewFieldProblem {
  missing,
  invalidCurrency,

  /// Three letters, but not a currency this system accepts — the backend
  /// returned zero rows for it. A membership answer, and the only one this
  /// client has: it carries no list of its own.
  ///
  /// Derived from [ReceiptReviewState.currencyProblem] rather than stored in
  /// `fieldProblems`, because an edit clears a field's stored problem and this
  /// one must outlive every keystroke that does not change the code.
  unsupportedCurrency,

  notANumber,
  tooPrecise,
  outOfRange,
  tooLong,
  dateTooEarly,
}

/// The values the person is confirming, exactly as they have been typed.
///
/// Held as text for the three amounts, because that is what a text field
/// contains and converting on every keystroke would fight the person editing
/// it. The conversion to **integer minor units** happens once, on confirm, in
/// [parseMinorUnits] — and never through a `double`.
///
/// The date and the time are civil values rather than text: both are chosen
/// from a picker, so there is no free-form string to misparse, and neither ever
/// becomes a `DateTime`.
final class ReceiptReviewDraft extends Equatable {
  const ReceiptReviewDraft({
    this.transactionDate,
    this.transactionTime,
    this.currencyCode = '',
    this.merchantName = '',
    this.documentNumber = '',
    this.totalText = '',
    this.subtotalText = '',
    this.taxText = '',
  });

  /// Seeds the form from a stored reading.
  ///
  /// A field the provider could not resolve is left **empty** rather than
  /// guessed at: an extracted null with its source text intact is exactly the
  /// case where the person must read the paper and type the figure themselves,
  /// and pre-filling a zero there would invite them to confirm a total the
  /// receipt never carried.
  ///
  /// [digits] is nullable, and null leaves all three amounts **empty**. An
  /// extraction that reported no `currency_minor_unit` has told us the integers
  /// but not the scale, and rendering `1000` as `10.00` on that basis is exactly
  /// the guess this correction removes. The amounts are filled in once — and
  /// only once — the width has been resolved, by `_seedAmountsIfPending`.
  factory ReceiptReviewDraft.fromExtraction(
    ReceiptExtraction extraction,
    int? digits,
  ) {
    return ReceiptReviewDraft(
      transactionDate: extraction.transactionDate.value,
      transactionTime: extraction.transactionTime.value,
      currencyCode: extraction.currencyCode.value ?? '',
      merchantName: extraction.merchantName.value ?? '',
      documentNumber: extraction.documentNumber.value ?? '',
      totalText: _amountText(extraction.total.value, digits),
      subtotalText: _amountText(extraction.subtotal.value, digits),
      taxText: _amountText(extraction.taxTotal.value, digits),
    );
  }

  static String _amountText(int? minor, int? digits) =>
      minor == null || digits == null ? '' : formatMinorUnits(minor, digits);

  final ReceiptCivilDate? transactionDate;
  final ReceiptCivilTime? transactionTime;
  final String currencyCode;
  final String merchantName;
  final String documentNumber;
  final String totalText;
  final String subtotalText;
  final String taxText;

  ReceiptReviewDraft copyWith({
    ReceiptCivilDate? transactionDate,
    ReceiptCivilTime? transactionTime,
    bool clearTransactionTime = false,
    String? currencyCode,
    String? merchantName,
    String? documentNumber,
    String? totalText,
    String? subtotalText,
    String? taxText,
  }) {
    return ReceiptReviewDraft(
      transactionDate: transactionDate ?? this.transactionDate,
      transactionTime: clearTransactionTime
          ? null
          : (transactionTime ?? this.transactionTime),
      currencyCode: currencyCode ?? this.currencyCode,
      merchantName: merchantName ?? this.merchantName,
      documentNumber: documentNumber ?? this.documentNumber,
      totalText: totalText ?? this.totalText,
      subtotalText: subtotalText ?? this.subtotalText,
      taxText: taxText ?? this.taxText,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    transactionDate,
    transactionTime,
    currencyCode,
    merchantName,
    documentNumber,
    totalText,
    subtotalText,
    taxText,
  ];
}

/// Everything the review screen renders from.
///
/// ## The preview URL is a field, and deliberately not a prop
///
/// [preview] carries a live capability that expires in about two minutes. It is
/// excluded from [props] so that it can never reach an equality comparison or
/// the `toString` a debug build prints — the same posture
/// [ReceiptImagePreview] itself takes one level down.
///
/// That exclusion creates a problem which [previewRevision] exists to solve: two
/// freshly minted previews with the same expiry compare equal, so a re-mint
/// would emit a state Bloc considers identical and the image would never
/// refresh. The revision is a plain counter — no secret, no id, nothing derived
/// from the URL — and it changes on every successful mint, which is what makes
/// the rebuild happen without the credential participating in equality.

/// Where the atomic header-and-products confirmation has reached.
///
/// Deliberately separate from [ReceiptReviewPhase]: a phase describes the
/// extraction lifecycle, and conflating "the write may or may not have
/// committed" with "the reading failed" is how a client ends up resending an
/// immutable financial write.
enum ReceiptProductSubmissionStatus {
  /// Nothing has been sent.
  idle,

  /// `confirm_receipt_with_products` is in flight. **Immutable, and never
  /// retried automatically.**
  pending,

  /// The database answered `CONFIRMED` or `ALREADY_CONFIRMED`. Terminal.
  settled,

  /// The database answered `CONFLICT`. Nothing was written by this call, and
  /// nothing was overwritten — but what is stored is not what was sent, so the
  /// only honest next step is to read the stored state.
  conflict,

  /// The result is genuinely unknown: a transport fault, an unreadable answer,
  /// or an outcome token this build does not recognise. The write may have
  /// committed. Never rendered as success, never as failure.
  uncertain,
}

/// What one manual "Check receipt status" read established.
///
/// Four answers and no fifth. Note especially what [nothingStored] is **not**:
/// it is not "the receipt does not exist" and not "the receipt is not yours".
/// `get_my_receipt_product_proposal` and `get_my_receipt_confirmation` both
/// return zero rows for an unreadable receipt and for an unwritten one alike,
/// and that collapse is deliberate — a client that split the two would rebuild
/// the existence oracle SQL is careful to deny.
enum ReceiptProductStatusCheckOutcome {
  /// A confirmation **and** a product proposal are stored. Authoritative, and
  /// the flow is finished whoever wrote them.
  storedWithProposal,

  /// A confirmation is stored with no product proposal — the header-only shape
  /// created before Phase 1D-B. Nothing may be appended to it: the RPC answers
  /// `CONFLICT` to any attempt to top one up. Its own presentation is a later
  /// unit.
  legacyHeaderOnly,

  /// Neither is stored. The only outcome that may return the screen to
  /// editable, and only because both reads answered.
  nothingStored,

  /// A read did not deliver an answer. Nothing is concluded; the check may be
  /// asked for again, by hand.
  unreadable,
}

/// Where the read of the **stored** product proposal has reached.
///
/// Deliberately separate from [ReceiptProductSubmissionStatus]: one describes a
/// write that may or may not have committed, this one describes what the
/// database says is recorded. Conflating them is how a screen ends up rendering
/// a client's own editable list as though it were the immutable record.
enum ReceiptProposalPhase {
  /// Nothing has been read, and nothing is claimed.
  initial,

  /// `get_my_receipt_product_proposal` is in flight. A pure read.
  loading,

  /// Rows came back. These are the frozen proposal-time values and they are the
  /// only thing the submitted display may render.
  loaded,

  /// Zero rows, with a confirmation known to exist: the header-only shape
  /// created before Phase 1D-B. A legal historical state, not an error, and one
  /// that can never be topped up through this flow.
  legacyHeaderOnly,

  /// The read produced no answer. **Not** "there is no proposal": the two are
  /// different facts and only one of them may reopen anything.
  unreadable,
}

/// How the stored proposal came to be read. Presentation and diagnosis only —
/// no behaviour branches on it, because a stored proposal is the same immutable
/// record however it was discovered.
enum ReceiptProposalSource {
  /// The screen opened on a receipt that was already confirmed.
  initialLoad,

  /// This session's own `confirm_receipt_with_products` answered `CONFIRMED`.
  newConfirmation,

  /// It answered `ALREADY_CONFIRMED`.
  alreadyConfirmed,

  /// A person pressed "Check receipt status".
  statusCheck,
}

/// The immutable product proposal exactly as the database holds it.
///
/// ## Every value here is frozen at proposal time
///
/// The lines are `product_*_at_proposal` snapshots the database copied out of
/// `vendor_products` when the proposal was written. A later rename, rebrand,
/// barcode reassignment, deactivation or un-assignment does not change them,
/// and nothing on this screen looks the current catalogue up to "improve" them:
/// what was proposed is the whole point, and a display that drifted to today's
/// catalogue would be describing a different assertion from the one a Claim
/// Reviewer will judge.
///
/// ## It is authoritative over the local selection
///
/// The editable selection a person built is a proposal; this is the record. If
/// the two ever disagree, this one is right and the difference is not an error
/// to report — it simply means the stored proposal was written by an earlier
/// act.
final class ReceiptStoredProposal extends Equatable {
  const ReceiptStoredProposal({
    this.phase = ReceiptProposalPhase.initial,
    this.lines = const <ReceiptProductProposalLine>[],
    this.source,
    this.problem,
  });

  final ReceiptProposalPhase phase;

  /// The stored lines, in the database's own `line_number` order.
  final List<ReceiptProductProposalLine> lines;

  final ReceiptProposalSource? source;

  /// Why the read produced no answer. A typed discriminant, never backend text.
  final ReceiptExtractionProblem? problem;

  bool get isLoading => phase == ReceiptProposalPhase.loading;

  bool get isLoaded => phase == ReceiptProposalPhase.loaded;

  bool get isLegacyHeaderOnly => phase == ReceiptProposalPhase.legacyHeaderOnly;

  bool get isUnreadable => phase == ReceiptProposalPhase.unreadable;

  /// Whether the database has answered definitively, one way or the other.
  bool get isResolved => isLoaded || isLegacyHeaderOnly;

  /// The authoritative number of stored lines. Counted from the rows, never
  /// from the client's own selection.
  int get lineCount => lines.length;

  int get totalQuantity => lines.fold<int>(
    0,
    (int sum, ReceiptProductProposalLine line) => sum + line.quantity,
  );

  ReceiptStoredProposal copyWith({
    ReceiptProposalPhase? phase,
    List<ReceiptProductProposalLine>? lines,
    ReceiptProposalSource? source,
    ReceiptExtractionProblem? problem,
    bool clearProblem = false,
  }) {
    return ReceiptStoredProposal(
      phase: phase ?? this.phase,
      lines: lines ?? this.lines,
      source: source ?? this.source,
      problem: clearProblem ? null : (problem ?? this.problem),
    );
  }

  @override
  List<Object?> get props => <Object?>[phase, lines, source, problem];
}

/// The atomic product-proposal submission, and what is known about it.
final class ReceiptProductSubmission extends Equatable {
  const ReceiptProductSubmission({
    this.status = ReceiptProductSubmissionStatus.idle,
    this.isSlow = false,
    this.result,
    this.submitted,
    this.submittedInput,
    this.problem,
    this.selectionProblem,
    this.isCheckingStatus = false,
    this.statusCheck,
  });

  final ReceiptProductSubmissionStatus status;

  /// True once the request has been in flight longer than
  /// [slowConfirmationNotice]. Presentation only: it cancels nothing, retries
  /// nothing and claims nothing.
  final bool isSlow;

  /// The authoritative answer, when there is one.
  final ReceiptWithProductsResult? result;

  /// The exact ordered selection that was sent.
  ///
  /// Retained through conflict and uncertainty on purpose: the person must be
  /// able to see what they submitted while they find out whether it landed.
  final ReceiptProductSelection? submitted;

  /// The exact transaction header that was sent, beside the products it was
  /// sent with. Retained for the same reason, and never re-derived from the
  /// draft — the draft is what a form holds, this is what a request carried.
  final ReceiptConfirmationInput? submittedInput;

  /// Why the call produced no authoritative answer. A typed discriminant, never
  /// backend text.
  final ReceiptExtractionProblem? problem;

  /// Why the proposal was refused **before** anything was sent. A definite
  /// client-side failure: zero repository calls happened, and the screen goes
  /// back to editable with every typed value and every chosen product intact.
  final ReceiptProductSelectionProblem? selectionProblem;

  /// True while the manual status check is reading. Guarded independently of
  /// the write, so a status check can never become a second submission.
  final bool isCheckingStatus;

  /// What the last manual status check established, or null when none has run.
  final ReceiptProductStatusCheckOutcome? statusCheck;

  /// A status check found a confirmation with no product proposal.
  bool get foundLegacyHeaderOnly =>
      statusCheck == ReceiptProductStatusCheckOutcome.legacyHeaderOnly;

  bool get isPending => status == ReceiptProductSubmissionStatus.pending;

  bool get isSettled => status == ReceiptProductSubmissionStatus.settled;

  bool get isConflict => status == ReceiptProductSubmissionStatus.conflict;

  bool get isUncertain => status == ReceiptProductSubmissionStatus.uncertain;

  /// Whether the outcome is unresolved in a way only the database can answer.
  bool get needsStatusCheck =>
      status == ReceiptProductSubmissionStatus.conflict ||
      status == ReceiptProductSubmissionStatus.uncertain;

  /// Whether the manual status check may be started now.
  ///
  /// Guarded **independently** of the write guard: a status check is a pure
  /// read and its own double-tap protection must not borrow the write's.
  bool get canCheckStatus => needsStatusCheck && !isCheckingStatus;

  /// Whether the proposal may still be edited.
  ///
  /// False from the moment a write starts and, once it has settled, forever.
  /// A conflict or an uncertain result also freezes it — the write may have
  /// landed, and editing a proposal that might already be immutable would be
  /// editing a record that cannot change.
  bool get isEditable => status == ReceiptProductSubmissionStatus.idle;

  ReceiptProductSubmission copyWith({
    ReceiptProductSubmissionStatus? status,
    bool? isSlow,
    ReceiptWithProductsResult? result,
    bool clearResult = false,
    ReceiptProductSelection? submitted,
    bool clearSubmitted = false,
    ReceiptConfirmationInput? submittedInput,
    ReceiptExtractionProblem? problem,
    bool clearProblem = false,
    ReceiptProductSelectionProblem? selectionProblem,
    bool clearSelectionProblem = false,
    bool? isCheckingStatus,
    ReceiptProductStatusCheckOutcome? statusCheck,
    bool clearStatusCheck = false,
  }) {
    return ReceiptProductSubmission(
      status: status ?? this.status,
      isSlow: isSlow ?? this.isSlow,
      result: clearResult ? null : (result ?? this.result),
      submitted: clearSubmitted ? null : (submitted ?? this.submitted),
      submittedInput: clearSubmitted
          ? null
          : (submittedInput ?? this.submittedInput),
      problem: clearProblem ? null : (problem ?? this.problem),
      selectionProblem: clearSelectionProblem
          ? null
          : (selectionProblem ?? this.selectionProblem),
      isCheckingStatus: isCheckingStatus ?? this.isCheckingStatus,
      statusCheck: clearStatusCheck ? null : (statusCheck ?? this.statusCheck),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    isSlow,
    result,
    submitted,
    submittedInput,
    problem,
    selectionProblem,
    isCheckingStatus,
    statusCheck,
  ];
}

/// How long a confirmation may run before the person is told it is merely slow.
///
/// Presentation only. Mirrors the Web milestone's own notice delay so both
/// clients say the same thing at the same moment.
const Duration slowConfirmationNotice = Duration(seconds: 4);

final class ReceiptReviewState extends Equatable {
  const ReceiptReviewState({
    required this.submissionId,
    this.phase = ReceiptReviewPhase.initial,
    this.extraction,
    this.outcome,
    this.attemptsUsed = 0,
    this.attemptsRemaining = 0,
    this.retryAllowed = false,
    this.manualConfirmationAllowed = false,
    this.lineItems = const <ReceiptExtractionLineItem>[],
    this.confirmation,
    this.confirmationResult,
    this.problem,
    this.confirmBlockedByExtraction = false,
    this.preview,
    this.previewPhase = ReceiptPreviewPhase.idle,
    this.previewRevision = 0,
    this.previewProblem,
    this.draft = const ReceiptReviewDraft(),
    this.currency = const ReceiptCurrencyResolution(),
    this.fieldProblems =
        const <ReceiptReviewField, ReceiptReviewFieldProblem>{},
    this.pollBudgetSpent = false,
    this.productSubmission = const ReceiptProductSubmission(),
    this.storedProposal = const ReceiptStoredProposal(),
  });

  /// The receipt under review. The only handle this screen holds.
  final String submissionId;

  final ReceiptReviewPhase phase;

  /// The latest attempt, when one exists.
  final ReceiptExtraction? extraction;

  /// What the last `request-receipt-extraction` call actually did.
  final ReceiptExtractionRequestOutcome? outcome;

  /// `attempts_used` — a fact about persisted rows, never an availability
  /// signal. Nothing on this screen derives a retry affordance from it.
  final int attemptsUsed;

  /// `greatest(0, 3 - attempts_used)`. Also a fact, also not availability.
  final int attemptsRemaining;

  /// The **only** field that carries availability. Read, never reconstructed.
  final bool retryAllowed;

  /// Whether the person may type the values in themselves.
  final bool manualConfirmationAllowed;

  /// The line items of a successful attempt, in the backend's own order.
  final List<ReceiptExtractionLineItem> lineItems;

  /// The stored confirmation, once one exists.
  final ReceiptConfirmation? confirmation;

  /// What the confirm call returned. Its entry mode and changed fields are the
  /// backend's, never re-derived here.
  final ReceiptConfirmationResult? confirmationResult;

  /// Why the last call produced no answer.
  final ReceiptExtractionProblem? problem;

  /// True when a confirm attempt was refused because an attempt is in flight.
  final bool confirmBlockedByExtraction;

  /// The short-lived capability. **Never** in [props]; see the class comment.
  final ReceiptImagePreview? preview;

  final ReceiptPreviewPhase previewPhase;

  /// Increments on every successful mint. Not secret, not derived from the URL.
  final int previewRevision;

  final ReceiptExtractionProblem? previewProblem;

  final ReceiptReviewDraft draft;

  /// Where the authoritative width for the typed currency has reached.
  final ReceiptCurrencyResolution currency;

  final Map<ReceiptReviewField, ReceiptReviewFieldProblem> fieldProblems;

  /// True once the bounded poll budget was spent with the attempt still open.
  /// The screen then offers an explicit "check again" instead of polling on.
  final bool pollBudgetSpent;

  /// The atomic product-proposal submission for this receipt.
  final ReceiptProductSubmission productSubmission;

  /// The immutable proposal the database holds, once it has been read.
  final ReceiptStoredProposal storedProposal;

  /// Whether an attempt is genuinely in flight, which is the only condition
  /// under which polling may run.
  bool get isAwaitingExtraction =>
      phase == ReceiptReviewPhase.queued ||
      phase == ReceiptReviewPhase.processing;

  /// Whether the screen is doing something the person must not interrupt.
  bool get isBusy =>
      phase == ReceiptReviewPhase.requesting ||
      phase == ReceiptReviewPhase.confirming;

  /// Whether a reading is stored and safe to present as extracted values.
  bool get hasReading => extraction?.hasReading ?? false;

  /// Whether the confirmation form may be shown and edited.
  ///
  /// The backend's own boolean, never re-derived: a failed attempt, an
  /// exhausted receipt and a receipt whose gate is shut are all confirmable,
  /// because manual confirmation never consults either mode gate.
  bool get canEdit =>
      manualConfirmationAllowed &&
      phase != ReceiptReviewPhase.confirmed &&
      phase != ReceiptReviewPhase.confirming &&
      phase != ReceiptReviewPhase.blocked;

  /// The currency code as it will be sent: trimmed and upper-cased.
  String get normalizedCurrencyCode => draft.currencyCode.trim().toUpperCase();

  /// Whether what is typed could be a currency code at all. The *shape* rule;
  /// which codes exist is the backend's answer and this client carries no list.
  bool get hasCurrencyShape => _currencyShape.hasMatch(normalizedCurrencyCode);

  /// The authoritative width for the code currently in the field, or null.
  ///
  /// Null the instant somebody edits the currency, because the resolution is
  /// bound to the code it was resolved for. There is no fallback behind this
  /// and no assumed two: null means the amounts cannot be converted yet.
  int? get resolvedMinorUnit => currency.minorUnitFor(normalizedCurrencyCode);

  /// Whether a width is established for exactly the code being confirmed.
  bool get isCurrencyResolved => resolvedMinorUnit != null;

  /// The currency the **reading itself** reported, exactly as it was stored.
  ///
  /// This is not [normalizedCurrencyCode] and must never be confused with it.
  /// That one is a proposal somebody is typing; this one is a finished fact
  /// about integers a provider already wrote. The line-item panel describes
  /// those integers and so uses these two, while the confirmation form resolves
  /// and uses its own — see [ReceiptReviewLineItems].
  String? get extractionCurrencyCode => extraction?.currencyCode.value;

  /// The `currency_minor_unit` the **reading itself** reported, or null when it
  /// reported none.
  ///
  /// Deliberately **not** [resolvedMinorUnit]. A width the backend resolved for
  /// the currency in the form is an answer about the *confirmation*, and letting
  /// it arrive here would mean a lookup for a code somebody typed silently
  /// supplying a scale for integers it knows nothing about. A reading that
  /// carried no width has none, and no later lookup gives it one.
  int? get extractionMinorUnit => extraction?.currencyMinorUnit;

  /// The currency field's resolution error, or null when there is none.
  ///
  /// Only ever "this system does not accept that currency". A width still being
  /// established is not a mistake anybody made and is never shown as one — the
  /// amount fields say so neutrally instead.
  ReceiptReviewFieldProblem? get currencyProblem =>
      currency.phase == ReceiptCurrencyPhase.unsupported &&
          currency.requestedCode == normalizedCurrencyCode
      ? ReceiptReviewFieldProblem.unsupportedCurrency
      : null;

  /// Whether asking the backend for this currency's width is worth offering.
  ///
  /// A recoverable lookup failure, or a width that has been put back to
  /// unresolved — after `22023`, most importantly. Never offered for an
  /// unsupported code, where asking again would give the same answer, and never
  /// for a code still being typed.
  bool get canResolveCurrency =>
      canEdit &&
      hasCurrencyShape &&
      (currency.phase == ReceiptCurrencyPhase.failed ||
          currency.phase == ReceiptCurrencyPhase.unresolved);

  /// Whether the confirm control may fire.
  ///
  /// The width is part of this and not a later check: a confirmation carries the
  /// scale its integers were built with, and a control that fired without one
  /// could only send a guess.
  bool get canConfirm => canEdit && !isBusy && isCurrencyResolved;

  /// Whether the transaction fields may be typed into.
  ///
  /// [canEdit] is the extraction's answer — is manual confirmation open at all.
  /// This narrows it by the *submission's* answer: from the instant the atomic
  /// write starts, and for every state it can reach afterwards, the header is
  /// as frozen as the products it was sent with. The two are one immutable
  /// assertion and neither half may move once it is on its way.
  bool get canEditTransaction => canEdit && productSubmission.isEditable;

  /// Whether the one final confirmation control may fire.
  ///
  /// Deliberately **not** a statement about the products: whether a proposal is
  /// well formed is answered by the snapshot the page hands over, at the moment
  /// it hands it over, and a control that consulted a second copy of that rule
  /// here could disagree with the one that actually runs. The empty case is the
  /// exception — a submit with nothing chosen is refused by the control itself,
  /// because a person must not be invited to press it.
  bool get canSubmitProposal =>
      canConfirm && productSubmission.isEditable && !isProductSubmissionBusy;

  /// Whether the atomic write or its status check is occupying the screen.
  bool get isProductSubmissionBusy =>
      productSubmission.isPending || productSubmission.isCheckingStatus;

  /// Whether this receipt is finished: an immutable confirmation exists — or
  /// has just been written — and the screen presents stored state only.
  ///
  /// Three independent ways to be here, because a person can arrive at a
  /// finished receipt three ways: opening one that was already confirmed,
  /// confirming one just now, and discovering through a status check that one
  /// was confirmed after all. All three end in the same read-only screen, and
  /// none of them offers a way back.
  bool get isReceiptFinished =>
      phase == ReceiptReviewPhase.confirmed ||
      productSubmission.isSettled ||
      storedProposal.isResolved;

  /// Whether re-reading the stored proposal is worth offering.
  ///
  /// Only when a confirmation is known to exist and the read did not deliver.
  /// A pure read, which is the whole reason it may be offered as a retry at
  /// all — and it is offered by hand, never on a timer.
  bool get canReloadStoredProposal =>
      isReceiptFinished && storedProposal.isUnreadable;

  /// Whether a further attempt may be asked for.
  ///
  /// [retryAllowed] alone. Never `attemptsRemaining > 0`, which would offer a
  /// retry while the provider was switched off.
  bool get canRetry => retryAllowed && !isBusy;

  /// Whether the confirmation is settled and nothing further may be edited.
  bool get isSettled => phase == ReceiptReviewPhase.confirmed;

  ReceiptReviewState copyWith({
    ReceiptReviewPhase? phase,
    ReceiptExtraction? extraction,
    ReceiptExtractionRequestOutcome? outcome,
    int? attemptsUsed,
    int? attemptsRemaining,
    bool? retryAllowed,
    bool? manualConfirmationAllowed,
    List<ReceiptExtractionLineItem>? lineItems,
    ReceiptConfirmation? confirmation,
    ReceiptConfirmationResult? confirmationResult,
    ReceiptExtractionProblem? problem,
    bool clearProblem = false,
    bool? confirmBlockedByExtraction,
    ReceiptImagePreview? preview,
    bool clearPreview = false,
    ReceiptPreviewPhase? previewPhase,
    int? previewRevision,
    ReceiptExtractionProblem? previewProblem,
    bool clearPreviewProblem = false,
    ReceiptReviewDraft? draft,
    ReceiptCurrencyResolution? currency,
    Map<ReceiptReviewField, ReceiptReviewFieldProblem>? fieldProblems,
    bool? pollBudgetSpent,
    ReceiptProductSubmission? productSubmission,
    ReceiptStoredProposal? storedProposal,
  }) {
    return ReceiptReviewState(
      submissionId: submissionId,
      phase: phase ?? this.phase,
      extraction: extraction ?? this.extraction,
      outcome: outcome ?? this.outcome,
      attemptsUsed: attemptsUsed ?? this.attemptsUsed,
      attemptsRemaining: attemptsRemaining ?? this.attemptsRemaining,
      retryAllowed: retryAllowed ?? this.retryAllowed,
      manualConfirmationAllowed:
          manualConfirmationAllowed ?? this.manualConfirmationAllowed,
      lineItems: lineItems ?? this.lineItems,
      confirmation: confirmation ?? this.confirmation,
      confirmationResult: confirmationResult ?? this.confirmationResult,
      problem: clearProblem ? null : (problem ?? this.problem),
      confirmBlockedByExtraction:
          confirmBlockedByExtraction ?? this.confirmBlockedByExtraction,
      preview: clearPreview ? null : (preview ?? this.preview),
      previewPhase: previewPhase ?? this.previewPhase,
      previewRevision: previewRevision ?? this.previewRevision,
      previewProblem: clearPreviewProblem
          ? null
          : (previewProblem ?? this.previewProblem),
      draft: draft ?? this.draft,
      currency: currency ?? this.currency,
      fieldProblems: fieldProblems ?? this.fieldProblems,
      pollBudgetSpent: pollBudgetSpent ?? this.pollBudgetSpent,
      productSubmission: productSubmission ?? this.productSubmission,
      storedProposal: storedProposal ?? this.storedProposal,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    submissionId,
    phase,
    extraction,
    outcome,
    attemptsUsed,
    attemptsRemaining,
    retryAllowed,
    manualConfirmationAllowed,
    lineItems,
    confirmation,
    confirmationResult,
    problem,
    confirmBlockedByExtraction,
    // `preview` is deliberately ABSENT. See the class comment: the revision
    // below is what makes a re-mint emit, without the credential ever reaching
    // an equality check or a debug `toString`.
    previewPhase,
    previewRevision,
    previewProblem,
    draft,
    currency,
    fieldProblems,
    pollBudgetSpent,
    productSubmission,
    storedProposal,
  ];
}
