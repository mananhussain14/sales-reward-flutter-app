import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/receipt_civil_date.dart';
import '../../../domain/entities/receipt_civil_time.dart';
import '../../../domain/entities/receipt_confirmation.dart';
import '../../../domain/entities/receipt_confirmation_input.dart';
import '../../../domain/entities/receipt_confirmation_outcome.dart';
import '../../../domain/entities/receipt_confirmation_result.dart';
import '../../../domain/entities/receipt_currency_minor_unit.dart';
import '../../../domain/entities/receipt_extraction.dart';
import '../../../domain/entities/receipt_extraction_line_item.dart';
import '../../../domain/entities/receipt_extraction_problem.dart';
import '../../../domain/entities/receipt_extraction_request_outcome.dart';
import '../../../domain/entities/receipt_extraction_request_result.dart';
import '../../../domain/entities/receipt_extraction_status.dart';
import '../../../domain/entities/receipt_image_preview.dart';
import '../../../domain/entities/receipt_product_proposal_line.dart';
import '../../../domain/entities/receipt_product_proposal_snapshot.dart';
import '../../../domain/entities/receipt_product_selection.dart';
import '../../../domain/entities/receipt_with_products_outcome.dart';
import '../../../domain/entities/receipt_with_products_result.dart';
import '../../../domain/repositories/receipt_extraction_repository.dart';
import '../../../domain/repositories/receipt_extraction_result.dart';
import '../widgets/receipt_minor_units.dart';

part 'receipt_review_state.dart';

/// The earliest receipt date `confirm_receipt_extraction` accepts.
const ReceiptCivilDate earliestReceiptDate = ReceiptCivilDate(2000, 1, 1);

const int _maxMerchantNameLength = 255;
const int _maxDocumentNumberLength = 100;

final RegExp _currencyShape = RegExp(r'^[A-Z]{3}$');

/// Canonical UUID form: 8-4-4-4-12 hexadecimal, matched case-insensitively.
final RegExp _submissionIdShape = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Reviewing and confirming one receipt.
///
/// Page-scoped: the route builds it, the route disposes it, and disposal is what
/// stops the poll loop and drops the image capability. It is deliberately **not**
/// registered in the service locator and not held by the shell — two receipts
/// under review at once would be two polling loops and two drafts.
///
/// ## The polling rules, which are the whole of the lifecycle design
///
/// * A loop runs **only** while an attempt is genuinely `QUEUED` or
///   `PROCESSING`. An unrecognised status is never treated as open, because a
///   build that polled on a token it could not read would poll forever.
/// * There is **one** loop. [_polling] is the guard, so a rebuild, a resumed
///   app and a finished confirm cannot start a second.
/// * It is **bounded**. After [maxPolls] intervals the loop stops and the screen
///   offers an explicit "check again" — an attempt that has not moved in two
///   minutes is not going to be rescued by a third minute of requests.
/// * It stops on `SUCCEEDED`, on `FAILED`, on a settled confirmation, when the
///   app leaves the foreground, and when this cubit closes.
///
/// ## Nothing mutating is ever retried on its own
///
/// [requestExtraction] can consume one of the three attempts a receipt gets in
/// its lifetime and [confirm] writes a row that can never be changed. Both are
/// called exactly once per deliberate act, and a transport fault on either
/// stops there. Only [checkAgain] and [resolveCurrency] — both pure reads — are
/// offered as retries, and only because both are idempotent.
///
/// ## The currency's decimal width is resolved, never assumed
///
/// Amounts cross this contract as **integer minor units**, and how many minor
/// units make one major unit is a property of the currency: 2 for EUR, 0 for
/// JPY, 3 for KWD, 4 for CLF. This cubit therefore holds a small lifecycle of
/// its own, [ReceiptCurrencyResolution], and obeys four rules:
///
/// * A successful reading that carries `currency_minor_unit` **is** the answer
///   for its own currency, and no round trip is spent re-asking.
/// * Any other case — no reading, a reading with a null width, a currency the
///   person changed, a manual confirmation — is asked of
///   `get_receipt_currency_minor_unit`, and nothing is converted until it
///   answers.
/// * A width belongs to the code it was resolved for. Editing the currency
///   makes it unavailable **structurally**, through
///   [ReceiptCurrencyResolution.minorUnitFor], rather than through an
///   invalidation step somebody could forget to run.
/// * A late answer can never settle a code that is no longer typed. Every
///   lookup carries a generation, and the reply is checked against both the
///   generation and the code before it is believed.
class ReceiptReviewCubit extends Cubit<ReceiptReviewState> {
  ReceiptReviewCubit({
    required ReceiptExtractionRepository repository,
    required String submissionId,
    this.pollInterval = const Duration(seconds: 3),
    this.maxPolls = 40,
    this.slowNoticeDelay = slowConfirmationNotice,
    Future<void> Function(Duration duration) delay = _wait,
  }) : _repository = repository,
       _delay = delay,
       super(ReceiptReviewState(submissionId: submissionId));

  static Future<void> _wait(Duration duration) =>
      Future<void>.delayed(duration);

  final ReceiptExtractionRepository _repository;
  final Future<void> Function(Duration duration) _delay;

  /// The fixed gap between polls. Never backed off, never randomised: a fixed
  /// interval is what makes the bound below a number anybody can reason about.
  final Duration pollInterval;

  /// The most polls one open attempt may cost.
  final int maxPolls;

  /// How long the atomic confirmation may run before the person is told it is
  /// merely slow. Injectable so a test can reach the notice without waiting;
  /// it changes **presentation only**, at any value.
  final Duration slowNoticeDelay;

  bool _started = false;
  bool _polling = false;
  bool _appActive = true;
  bool _draftSeeded = false;
  bool _amountsSeeded = false;
  int _pollsUsed = 0;
  ReceiptReviewPhase _phaseBeforeConfirm = ReceiptReviewPhase.succeeded;

  /// Bumped by every act that starts or ends an atomic product confirmation, so
  /// a reply belonging to a request the screen has moved past is dropped before
  /// it can reach the state.
  int _productWriteGeneration = 0;

  /// The slow-notice timer, and the only timer in this cubit.
  ///
  /// Cancelled — not merely ignored — on an authoritative outcome, on an
  /// uncertain one, and on [close]. A notice that fired after the answer had
  /// arrived would be telling somebody to keep waiting for something that had
  /// already finished.
  Timer? _slowTimer;

  /// Bumped by every manual status check, for the same reason and independently
  /// of the write: the two are separate acts with separate guards.
  int _statusCheckGeneration = 0;

  /// Bumped by every read of the stored proposal, so a reply belonging to an
  /// abandoned read can never overwrite a newer answer.
  int _proposalGeneration = 0;

  /// Bumped by every lookup and by every act that abandons one.
  ///
  /// A reply whose generation is no longer current is discarded before it can
  /// reach the state — the JPY answer that lands after somebody has typed KWD is
  /// not KWD's width, and adopting it would mis-scale by a factor of a thousand.
  int _currencyGeneration = 0;

  /// Widths this backend has already answered, this screen, in memory.
  ///
  /// Nothing else may populate it: every entry came from
  /// `get_receipt_currency_minor_unit`. It is not persisted, does not survive
  /// the screen, and replaces no backend check — `confirm_receipt_extraction`
  /// verifies the declared width against its own authority regardless, and a
  /// `22023` evicts the entry that produced it.
  final Map<String, int> _resolvedWidths = <String, int>{};

  /// Codes whose width the backend has refused a confirmation for.
  ///
  /// The reading's own `currency_minor_unit` is a join the backend performed
  /// earlier; a `22023` is the backend saying that number is not the one it
  /// records now. So for these codes the shortcut is not taken again and the
  /// width is asked for afresh.
  final Set<String> _staleWidths = <String>{};

  /// Opens the review. Safe to call again; only the first call does anything.
  ///
  /// The guard is what makes this survive a rebuild: `initState` may run more
  /// than once for one logical screen, and a second
  /// `request-receipt-extraction` could consume a second attempt.
  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;

    // The id came out of a URL, which is a value a person can edit. A shape
    // that cannot be a submission id is refused HERE, so a typed or tampered
    // address costs no round trip at all — not even the mutating one.
    //
    // It is reported as the same refusal every unreadable receipt gets, which
    // is deliberate: the backend answers an unknown receipt, somebody else's
    // and another Retailer's identically, and a distinguishable local answer
    // would hand back an oracle SQL is careful to deny.
    //
    // This is NOT an authorization check. A perfectly well-formed id belonging
    // to somebody else passes it and is refused by
    // `assert_my_receipt_extraction_access`, under the caller's own token.
    if (!_submissionIdShape.hasMatch(state.submissionId)) {
      emit(
        state.copyWith(
          phase: ReceiptReviewPhase.blocked,
          problem: const ExtractionNotFoundProblem(),
        ),
      );
      return;
    }

    unawaited(loadPreview());
    await _requestExtraction();
  }

  /// Asks for another attempt, after an explicit tap.
  ///
  /// Refused unless the backend said `retry_allowed`. Never offered from
  /// `attempts_remaining`, which is a fact about persisted rows and says
  /// nothing about whether the provider is reachable.
  Future<void> retryExtraction() async {
    if (!state.canRetry) {
      return;
    }
    await _requestExtraction();
  }

  /// Re-reads the attempt after the poll budget was spent, or after a
  /// recoverable read failure. A read, so offering it as a retry is safe.
  Future<void> checkAgain() async {
    if (state.isBusy) {
      return;
    }
    emit(
      state.copyWith(
        pollBudgetSpent: false,
        clearProblem: true,
        confirmBlockedByExtraction: false,
      ),
    );
    await _readExtraction();
    _startPolling();
  }

  Future<void> _requestExtraction() async {
    emit(
      state.copyWith(
        phase: ReceiptReviewPhase.requesting,
        clearProblem: true,
        confirmBlockedByExtraction: false,
        pollBudgetSpent: false,
      ),
    );

    final ReceiptExtractionResult<ReceiptExtractionRequestResult> result =
        await _repository.requestExtraction(state.submissionId);
    if (isClosed) {
      return;
    }

    switch (result) {
      case ReceiptExtractionFailed<ReceiptExtractionRequestResult>(
        :final ReceiptExtractionProblem problem,
      ):
        // NOT resent. A request that vanished mid-flight may still have
        // consumed an attempt, and no layer beneath the person tapping the
        // button can decide that a second one is acceptable.
        emit(
          state.copyWith(phase: _phaseForProblem(problem), problem: problem),
        );

      case ReceiptExtractionSuccess<ReceiptExtractionRequestResult>(
        :final ReceiptExtractionRequestResult value,
      ):
        _pollsUsed = 0;
        // WHEN A PAYLOAD CAME BACK, THE PAYLOAD IS THE AUTHORITY.
        //
        // Both endpoints build every response by re-reading through the
        // caller's own RPC, so the nested row's flags are what the database
        // actually says about this attempt. The top-level `retry_allowed` is
        // additionally pinned to false on every branch that merely reports
        // pre-existing state, because a retry is not what those branches are
        // answering — reading it there would hide a retry the row permits.
        //
        // Preferring the row can never *widen* anything: SQL derives its
        // `retry_allowed` as "FAILED, attempts left, nothing active, nothing
        // succeeded, not confirmed, gate open", so it is already false for
        // every status but FAILED, and the Edge layer may only narrow it
        // further. With no payload there is no row to prefer, and the counters
        // the call itself reported are used.
        final ReceiptExtraction? row = value.extraction;
        emit(
          state.copyWith(
            outcome: value.outcome,
            attemptsUsed: row?.attemptsUsed ?? value.attemptsUsed,
            attemptsRemaining:
                row?.attemptsRemaining ?? value.attemptsRemaining,
            retryAllowed: row?.retryAllowed ?? value.retryAllowed,
            manualConfirmationAllowed:
                row?.manualConfirmationAllowed ??
                value.manualConfirmationAllowed,
            extraction: row,
            phase: _phaseForRequest(value),
          ),
        );
        await _afterExtractionChanged();
    }
  }

  /// One caller-scoped read of the attempt.
  Future<void> _readExtraction() async {
    final ReceiptExtractionResult<ReceiptExtraction> result = await _repository
        .extraction(state.submissionId);
    if (isClosed) {
      return;
    }

    switch (result) {
      case ReceiptExtractionFailed<ReceiptExtraction>(
        :final ReceiptExtractionProblem problem,
      ):
        emit(
          state.copyWith(phase: _phaseForProblem(problem), problem: problem),
        );

      case ReceiptExtractionSuccess<ReceiptExtraction>(
        :final ReceiptExtraction value,
      ):
        emit(
          state.copyWith(
            extraction: value,
            // The attempt's own counters are the authority once there is an
            // attempt to read: `retry_allowed` on the row has passed through
            // both gates, and the Edge layer may only ever narrow it.
            attemptsUsed: value.attemptsUsed,
            attemptsRemaining: value.attemptsRemaining,
            retryAllowed: value.retryAllowed,
            manualConfirmationAllowed: value.manualConfirmationAllowed,
            phase: _phaseForStatus(value),
            clearProblem: true,
          ),
        );
        await _afterExtractionChanged();
    }
  }

  /// Seeds the form, loads the line items and resolves a confirmation, once the
  /// attempt has moved.
  Future<void> _afterExtractionChanged() async {
    final ReceiptExtraction? extraction = state.extraction;

    if (state.phase == ReceiptReviewPhase.confirmed ||
        (extraction?.confirmationExists ?? false)) {
      // CONCURRENTLY, because neither read depends on the other and a person
      // opening a finished receipt should not wait for two round trips in
      // series. Together they resolve which finished receipt this is: a
      // confirmation with a proposal, or the header-only shape that predates
      // Phase 1D-B.
      await Future.wait<void>(<Future<void>>[
        _loadConfirmation(),
        _loadStoredProposal(source: ReceiptProposalSource.initialLoad),
      ]);
      return;
    }

    // Seeded ONLY from a stored reading. An open or failed attempt carries no
    // values, and seeding an empty draft from one would set the guard below and
    // then silently refuse to fill the form when a later attempt succeeded.
    if (extraction != null && extraction.hasReading) {
      _seedDraft(extraction);
      await _loadLineItems();
    }

    _startPolling();
  }

  void _seedDraft(ReceiptExtraction extraction) {
    if (_draftSeeded) {
      // Never overwrites what somebody has been typing. A poll that lands while
      // a correction is half-entered must not throw it away.
      return;
    }
    _draftSeeded = true;

    // The reading's own width, when it reported one and has not since been
    // refused. Null leaves the three amount boxes empty rather than rendering
    // the integers under a width nobody supplied; `_seedAmountsIfPending` fills
    // them the moment the lookup answers.
    final String code = (extraction.currencyCode.value ?? '')
        .trim()
        .toUpperCase();
    final int? width = _staleWidths.contains(code)
        ? null
        : extraction.currencyMinorUnit;
    if (width != null) {
      _amountsSeeded = true;
    }

    emit(
      state.copyWith(
        draft: ReceiptReviewDraft.fromExtraction(extraction, width),
      ),
    );
    unawaited(_resolveCurrency());
  }

  /// Fills the amount boxes once a width finally exists for the reading's own
  /// currency.
  ///
  /// Guarded three ways, because the one thing it must never do is move a digit
  /// somebody typed: it runs once, only for the reading's own currency, and only
  /// while all three boxes are still empty.
  void _seedAmountsIfPending() {
    if (_amountsSeeded) {
      return;
    }
    final ReceiptExtraction? extraction = state.extraction;
    final int? digits = state.resolvedMinorUnit;
    if (extraction == null || digits == null || !extraction.hasReading) {
      return;
    }
    final String extracted = (extraction.currencyCode.value ?? '')
        .trim()
        .toUpperCase();
    if (extracted.isEmpty || extracted != state.normalizedCurrencyCode) {
      // Somebody changed the currency before the width arrived. Re-rendering
      // the provider's integers under a different currency's scale would be
      // the mis-scaling in a new costume.
      return;
    }

    final ReceiptReviewDraft draft = state.draft;
    if (draft.totalText.isNotEmpty ||
        draft.subtotalText.isNotEmpty ||
        draft.taxText.isNotEmpty) {
      return;
    }

    _amountsSeeded = true;
    emit(
      state.copyWith(
        draft: draft.copyWith(
          totalText: ReceiptReviewDraft._amountText(
            extraction.total.value,
            digits,
          ),
          subtotalText: ReceiptReviewDraft._amountText(
            extraction.subtotal.value,
            digits,
          ),
          taxText: ReceiptReviewDraft._amountText(
            extraction.taxTotal.value,
            digits,
          ),
        ),
      ),
    );
  }

  Future<void> _loadLineItems() async {
    final ReceiptExtractionResult<List<ReceiptExtractionLineItem>> result =
        await _repository.lineItems(state.submissionId);
    if (isClosed) {
      return;
    }
    // An empty list is a real answer. A failure degrades this one section and
    // never the screen: line items are informational and gate nothing.
    if (result case ReceiptExtractionSuccess<List<ReceiptExtractionLineItem>>(
      :final List<ReceiptExtractionLineItem> value,
    )) {
      emit(state.copyWith(lineItems: value));
    }
  }

  Future<void> _loadConfirmation() async {
    final ReceiptExtractionResult<ReceiptConfirmation?> result =
        await _repository.confirmation(state.submissionId);
    if (isClosed) {
      return;
    }

    switch (result) {
      case ReceiptExtractionFailed<ReceiptConfirmation?>(
        :final ReceiptExtractionProblem problem,
      ):
        emit(
          state.copyWith(phase: _phaseForProblem(problem), problem: problem),
        );

      case ReceiptExtractionSuccess<ReceiptConfirmation?>(
        :final ReceiptConfirmation? value,
      ):
        emit(
          state.copyWith(
            confirmation: value,
            phase: ReceiptReviewPhase.confirmed,
            manualConfirmationAllowed: false,
            retryAllowed: false,
            clearProblem: true,
          ),
        );
    }
  }

  // ---- The stored, immutable proposal --------------------------------------

  /// Re-reads the stored proposal after an explicit tap.
  ///
  /// Offered only when a confirmation is known to exist and a previous read did
  /// not deliver. A **pure read**, which is the whole reason it may be offered
  /// as a retry at all — and it is offered by hand, never on a timer and never
  /// as a loop.
  Future<void> reloadStoredProposal() async {
    if (!state.canReloadStoredProposal) {
      return;
    }
    await _loadStoredProposal(
      source: state.storedProposal.source,
      // Whatever the write said still stands: a re-read that comes back empty
      // must not turn a confirmed proposal into a header-only receipt.
      expectedLines: state.productSubmission.result?.lineCount ?? 0,
    );
  }

  /// Reads `get_my_receipt_product_proposal` once.
  ///
  /// ## The database is the authority, and the local selection is not
  ///
  /// Nothing here reconstructs the display from the editable selection a person
  /// built. That list is a proposal; these rows are the record, and they carry
  /// the frozen `*_at_proposal` snapshots the database copied for itself. A
  /// screen that rendered the local list instead would show today's catalogue
  /// text over yesterday's assertion.
  ///
  /// ## Zero rows is answered by context, never by guessing
  ///
  /// The function returns zero rows for "no proposal", "not yours" and "does
  /// not exist" alike. Every caller already knows a confirmation exists — that
  /// is the only condition under which this runs — so zero rows ordinarily
  /// means the header-only shape, and is recorded as exactly that.
  ///
  /// [expectedLines] is the one exception, and it matters. When a write has
  /// just answered `CONFIRMED` or `ALREADY_CONFIRMED` it also said how many
  /// lines the stored confirmation carries. If that number is positive and the
  /// read comes back empty, the two disagree — and the write is the more
  /// recent, more specific answer. Calling that receipt "confirmed without
  /// products" would tell somebody their proposal had vanished seconds after
  /// the database said it was written. It is recorded as *unreadable* instead:
  /// the confirmation stays authoritative, the screen stays read-only, and the
  /// person is offered the read again.
  Future<void> _loadStoredProposal({
    ReceiptProposalSource? source,
    int expectedLines = 0,
  }) async {
    if (state.storedProposal.isLoading) {
      // One read at a time. This, plus `start()`'s own guard, is what stops a
      // rebuild turning a screen into a request-per-frame.
      return;
    }

    final int generation = ++_proposalGeneration;
    emit(
      state.copyWith(
        storedProposal: state.storedProposal.copyWith(
          phase: ReceiptProposalPhase.loading,
          source: source,
          clearProblem: true,
        ),
      ),
    );

    final ReceiptExtractionResult<List<ReceiptProductProposalLine>> result =
        await _repository.productProposal(state.submissionId);
    if (isClosed || generation != _proposalGeneration) {
      return;
    }

    switch (result) {
      case ReceiptExtractionFailed<List<ReceiptProductProposalLine>>(
        :final ReceiptExtractionProblem problem,
      ):
        // NOT "there is no proposal". The two are different facts and only one
        // of them may change what this screen offers.
        emit(
          state.copyWith(
            storedProposal: state.storedProposal.copyWith(
              phase: ReceiptProposalPhase.unreadable,
              problem: problem,
            ),
          ),
        );

      case ReceiptExtractionSuccess<List<ReceiptProductProposalLine>>(
        :final List<ReceiptProductProposalLine> value,
      ):
        final ReceiptProposalPhase phase;
        if (value.isNotEmpty) {
          phase = ReceiptProposalPhase.loaded;
        } else if (expectedLines > 0) {
          // The write said this confirmation carries lines and the read found
          // none. Not a legacy receipt — a disagreement, and one that must not
          // be resolved by telling somebody their products are not there.
          phase = ReceiptProposalPhase.unreadable;
        } else {
          phase = ReceiptProposalPhase.legacyHeaderOnly;
        }

        emit(
          state.copyWith(
            storedProposal: state.storedProposal.copyWith(
              phase: phase,
              lines: value,
              problem: phase == ReceiptProposalPhase.unreadable
                  ? const ExtractionMalformedResponseProblem()
                  : null,
              clearProblem: phase != ReceiptProposalPhase.unreadable,
            ),
          ),
        );
    }
  }

  // ---- Polling -------------------------------------------------------------

  void _startPolling() {
    if (!state.isAwaitingExtraction || _polling || !_appActive) {
      return;
    }
    unawaited(_pollLoop());
  }

  Future<void> _pollLoop() async {
    if (_polling) {
      return;
    }
    _polling = true;
    try {
      while (!isClosed &&
          _appActive &&
          state.isAwaitingExtraction &&
          _pollsUsed < maxPolls) {
        await _delay(pollInterval);
        if (isClosed || !_appActive || !state.isAwaitingExtraction) {
          return;
        }
        _pollsUsed++;
        await _readExtraction();
      }

      if (!isClosed && state.isAwaitingExtraction && _pollsUsed >= maxPolls) {
        emit(state.copyWith(pollBudgetSpent: true));
      }
    } finally {
      _polling = false;
    }
  }

  /// Pauses while the application is not in the foreground, and resumes when it
  /// returns.
  ///
  /// A backgrounded shop-floor phone must not keep asking: the requests would
  /// be answered into a screen nobody is looking at, and on a metered
  /// connection they are somebody's money.
  void setAppActive(bool active) {
    if (_appActive == active) {
      return;
    }
    _appActive = active;
    if (active) {
      _startPolling();
    }
  }

  // ---- The form ------------------------------------------------------------

  void setTransactionDate(ReceiptCivilDate date) => _editDraft(
    state.draft.copyWith(transactionDate: date),
    ReceiptReviewField.transactionDate,
  );

  void setTransactionTime(ReceiptCivilTime? time) => _editDraft(
    time == null
        ? state.draft.copyWith(clearTransactionTime: true)
        : state.draft.copyWith(transactionTime: time),
    ReceiptReviewField.transactionTime,
  );

  /// Records a currency edit and establishes that currency's width.
  ///
  /// **The previous width stops applying immediately** — it is bound to the code
  /// it was resolved for, so the moment this draft changes
  /// [ReceiptReviewState.resolvedMinorUnit] is null again and confirmation is
  /// closed. Nothing re-scales the amount text: the digits somebody typed stay
  /// exactly as typed, and it is for them to decide where the decimal point
  /// belongs under the new currency.
  void setCurrencyCode(String value) {
    if (!state.canEditTransaction) {
      return;
    }
    _editDraft(
      state.draft.copyWith(currencyCode: value),
      ReceiptReviewField.currencyCode,
    );
    unawaited(_resolveCurrency());
  }

  void setMerchantName(String value) => _editDraft(
    state.draft.copyWith(merchantName: value),
    ReceiptReviewField.merchantName,
  );

  void setDocumentNumber(String value) => _editDraft(
    state.draft.copyWith(documentNumber: value),
    ReceiptReviewField.documentNumber,
  );

  void setTotal(String value) => _editDraft(
    state.draft.copyWith(totalText: value),
    ReceiptReviewField.total,
  );

  void setSubtotal(String value) => _editDraft(
    state.draft.copyWith(subtotalText: value),
    ReceiptReviewField.subtotal,
  );

  void setTax(String value) =>
      _editDraft(state.draft.copyWith(taxText: value), ReceiptReviewField.tax);

  void _editDraft(ReceiptReviewDraft draft, ReceiptReviewField field) {
    // NOT `canEdit`. This is the state-level half of the submission freeze, and
    // it is the half that matters: a widget that is disabled can still deliver
    // a callback queued before the frame that disabled it, and the header a
    // request is carrying must not move underneath it.
    if (!state.canEditTransaction) {
      return;
    }
    final Map<ReceiptReviewField, ReceiptReviewFieldProblem> problems =
        Map<ReceiptReviewField, ReceiptReviewFieldProblem>.of(
          state.fieldProblems,
        )..remove(field);
    emit(state.copyWith(draft: draft, fieldProblems: problems));
  }

  // ---- The currency's decimal width ----------------------------------------

  /// How many decimal places the amount fields are being entered with, or
  /// **null** while that is not established.
  ///
  /// Null is a real answer and the screen must render it as one: no width is
  /// claimed, no amount is converted, and the confirm control does not fire.
  int? get minorDigits => state.resolvedMinorUnit;

  /// Asks the backend for the typed currency's width, after an explicit tap.
  ///
  /// A pure read, which is the whole reason it may be offered as a retry at all.
  /// It re-asks even for a code whose lookup already failed; it does not re-ask
  /// for one the backend has called unsupported, because the answer would be the
  /// same and asking would suggest otherwise.
  Future<void> resolveCurrency() async {
    if (!state.canResolveCurrency) {
      return;
    }
    await _resolveCurrency(force: true);
  }

  /// Establishes the width for whatever is in the currency field now.
  Future<void> _resolveCurrency({bool force = false}) async {
    final String code = state.normalizedCurrencyCode;

    if (!_currencyShape.hasMatch(code)) {
      // Mid-keystroke, or empty. Nothing is claimed and nothing is asked: a
      // lookup per character would be noise, and a width that flickered while
      // somebody typed would be worse than none.
      _currencyGeneration++;
      emit(
        state.copyWith(
          currency: ReceiptCurrencyResolution(requestedCode: code),
        ),
      );
      return;
    }

    final ReceiptCurrencyResolution current = state.currency;
    if (!force &&
        current.requestedCode == code &&
        current.phase != ReceiptCurrencyPhase.unresolved) {
      // Already settled, already being asked, or already refused — for this
      // exact code. This is what stops a rebuild, a re-seeded draft or an edit
      // to another field costing a round trip.
      return;
    }

    // The reading's own width, when the person is confirming the reading's own
    // currency. The backend joined it when it stored the attempt; asking again
    // would be a second round trip for an answer already in hand.
    final ReceiptExtraction? extraction = state.extraction;
    final int? extractedUnit = extraction?.currencyMinorUnit;
    final String extractedCode = (extraction?.currencyCode.value ?? '')
        .trim()
        .toUpperCase();
    if (extractedUnit != null &&
        extractedCode == code &&
        !_staleWidths.contains(code)) {
      _settleCurrency(code, extractedUnit);
      return;
    }

    final int? cached = _staleWidths.contains(code)
        ? null
        : _resolvedWidths[code];
    if (cached != null) {
      _settleCurrency(code, cached);
      return;
    }

    final int generation = ++_currencyGeneration;
    emit(
      state.copyWith(
        currency: ReceiptCurrencyResolution(
          phase: ReceiptCurrencyPhase.resolving,
          requestedCode: code,
        ),
      ),
    );

    final ReceiptExtractionResult<ReceiptCurrencyMinorUnit?> result =
        await _repository.currencyMinorUnit(code);

    // TWO GUARDS, and both are needed. The generation catches an answer that a
    // later act has abandoned; the code comparison catches the case where the
    // field has moved on to something this build never started a lookup for.
    // Either alone would leave a window in which JPY's zero could become KWD's
    // width.
    if (isClosed ||
        generation != _currencyGeneration ||
        state.normalizedCurrencyCode != code) {
      return;
    }

    switch (result) {
      case ReceiptExtractionFailed<ReceiptCurrencyMinorUnit?>(
        :final ReceiptExtractionProblem problem,
      ):
        // The draft is untouched. Nothing was converted, nothing was sent, and
        // the person may ask again.
        emit(
          state.copyWith(
            currency: ReceiptCurrencyResolution(
              phase: ReceiptCurrencyPhase.failed,
              requestedCode: code,
              problem: problem,
            ),
          ),
        );

      case ReceiptExtractionSuccess<ReceiptCurrencyMinorUnit?>(
        :final ReceiptCurrencyMinorUnit? value,
      ):
        if (value == null) {
          emit(
            state.copyWith(
              currency: ReceiptCurrencyResolution(
                phase: ReceiptCurrencyPhase.unsupported,
                requestedCode: code,
              ),
            ),
          );
          return;
        }
        if (value.currencyCode != code) {
          // An answer about a different code is not this currency's width. Read
          // as unreadable rather than adopted: the alternative is scaling one
          // currency's amounts by another's.
          emit(
            state.copyWith(
              currency: ReceiptCurrencyResolution(
                phase: ReceiptCurrencyPhase.failed,
                requestedCode: code,
                problem: const ExtractionMalformedResponseProblem(),
              ),
            ),
          );
          return;
        }
        _resolvedWidths[code] = value.minorUnit;
        _settleCurrency(code, value.minorUnit);
    }
  }

  void _settleCurrency(String code, int minorUnit) {
    emit(
      state.copyWith(
        currency: ReceiptCurrencyResolution(
          phase: ReceiptCurrencyPhase.resolved,
          requestedCode: code,
          resolvedCode: code,
          minorUnit: minorUnit,
        ),
      ),
    );
    _seedAmountsIfPending();
  }

  // ---- Confirmation --------------------------------------------------------

  /// Writes the confirmation. **Once**, and never automatically.
  ///
  /// A confirmation cannot be updated, deleted or revised. A resend after a lost
  /// reply cannot create a second row — the unique constraint settles it and the
  /// answer becomes `ALREADY_CONFIRMED` — but it is the person's explicit act,
  /// never this layer's.
  Future<void> confirm() async {
    if (!state.canEdit || state.isBusy) {
      return;
    }

    // The width is resolved against the code as it reads RIGHT NOW, and the two
    // must be about the same code: a width established for EUR must never scale
    // a total somebody has since relabelled JPY. Null means it is not
    // established, and nothing below converts anything without it.
    final String code = state.normalizedCurrencyCode;
    final int? digits = state.currency.minorUnitFor(code);

    final Map<ReceiptReviewField, ReceiptReviewFieldProblem> problems =
        validateDraft(state.draft, digits);
    if (problems.isNotEmpty) {
      emit(state.copyWith(fieldProblems: problems));
      return;
    }

    // The draft is otherwise sound but the currency's width is not settled.
    // Nothing is sent and nothing is marked wrong: the currency line beneath the
    // field is already saying whether it is being checked, could not be checked,
    // or is not accepted at all.
    if (digits == null) {
      return;
    }

    final ReceiptConfirmationInput? input = _inputFrom(
      state.draft,
      code,
      digits,
    );
    if (input == null) {
      return;
    }

    _phaseBeforeConfirm = state.phase;
    emit(
      state.copyWith(
        phase: ReceiptReviewPhase.confirming,
        fieldProblems: const <ReceiptReviewField, ReceiptReviewFieldProblem>{},
        clearProblem: true,
        confirmBlockedByExtraction: false,
      ),
    );

    final ReceiptExtractionResult<ReceiptConfirmationResult> result =
        await _repository.confirm(input);
    if (isClosed) {
      return;
    }

    switch (result) {
      case ReceiptExtractionFailed<ReceiptConfirmationResult>(
        :final ReceiptExtractionProblem problem,
      ):
        // `22023`: the width this request declared is not the one the backend
        // records. The resolved width is put back to unresolved and evicted
        // from memory, which closes the confirm control until the person asks
        // for it again — deliberately, because nothing here may resend a
        // confirmation, least of all one whose scale has just been refused.
        final bool scaleMismatch =
            problem is ExtractionCurrencyScaleMismatchProblem;
        if (scaleMismatch) {
          _resolvedWidths.remove(code);
          _staleWidths.add(code);
          _currencyGeneration++;
        }

        // The typed values stay on screen. Nothing is resent.
        final ReceiptReviewPhase phase = _isTerminal(problem)
            ? ReceiptReviewPhase.blocked
            : _phaseBeforeConfirm;
        emit(
          state.copyWith(
            phase: phase,
            problem: problem,
            currency: scaleMismatch
                ? ReceiptCurrencyResolution(requestedCode: code)
                : null,
          ),
        );

      case ReceiptExtractionSuccess<ReceiptConfirmationResult>(
        :final ReceiptConfirmationResult value,
      ):
        await _applyConfirmationResult(value);
    }
  }

  Future<void> _applyConfirmationResult(
    ReceiptConfirmationResult result,
  ) async {
    switch (result.outcome) {
      case ReceiptConfirmationOutcome.confirmed:
      case ReceiptConfirmationOutcome.alreadyConfirmed:
        emit(
          state.copyWith(
            confirmationResult: result,
            phase: ReceiptReviewPhase.confirmed,
            manualConfirmationAllowed: false,
            retryAllowed: false,
          ),
        );
        await _loadConfirmation();

      case ReceiptConfirmationOutcome.extractionInProgress:
        // The one rule that blocks a confirmation. Nothing was written, so the
        // form stays exactly as it was and the poll loop is resumed.
        emit(
          state.copyWith(
            phase: _phaseBeforeConfirm,
            confirmBlockedByExtraction: true,
            confirmationResult: result,
          ),
        );
        await _readExtraction();

      case ReceiptConfirmationOutcome.unknown:
        // Never read as confirmed. Telling somebody their receipt was confirmed
        // on the strength of a token this build could not read is the one
        // mistake this feature cannot undo.
        emit(
          state.copyWith(
            phase: _phaseBeforeConfirm,
            problem: const ExtractionMalformedResponseProblem(),
          ),
        );
    }
  }

  ReceiptConfirmationInput? _inputFrom(
    ReceiptReviewDraft draft,
    String currencyCode,
    int digits,
  ) {
    final ReceiptCivilDate? date = draft.transactionDate;
    final MinorUnitResult total = parseMinorUnits(draft.totalText, digits);
    if (date == null || total is! MinorUnitValue) {
      return null;
    }

    return ReceiptConfirmationInput(
      submissionId: state.submissionId,
      transactionDate: date,
      currencyCode: currencyCode,
      // The same integer that scaled the three amounts above, declared so the
      // backend can check it rather than infer it.
      currencyMinorUnit: digits,
      totalMinor: total.minor,
      merchantName: _blankToNull(draft.merchantName),
      documentNumber: _blankToNull(draft.documentNumber),
      transactionTime: draft.transactionTime,
      subtotalMinor: _optionalMinor(draft.subtotalText, digits),
      taxTotalMinor: _optionalMinor(draft.taxText, digits),
    );
  }

  static int? _optionalMinor(String text, int digits) {
    if (text.trim().isEmpty) {
      // Null, never zero. The comparison that derives `changed_fields` treats
      // them as different facts: zero tax is a fact, unknown tax is not.
      return null;
    }
    final MinorUnitResult result = parseMinorUnits(text, digits);
    return result is MinorUnitValue ? result.minor : null;
  }

  static String? _blankToNull(String value) {
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  // ---- The atomic header-and-products confirmation --------------------------

  /// Writes the transaction header **and** the product proposal, in one call.
  ///
  /// This is the whole of the new-receipt confirmation path, and it is the only
  /// thing on this screen that may write one. [confirm] — the header-only
  /// `confirm_receipt_extraction` — is deliberately left in place for the
  /// historical rows and the tests that describe them, and is deliberately no
  /// longer reachable from the screen: a header written on its own can never
  /// acquire products afterwards, because the combined RPC answers `CONFLICT`
  /// to every attempt to top one up. Calling it first would manufacture exactly
  /// the state the person was trying to avoid.
  ///
  /// ## The selection arrives as a value, and is read exactly once
  ///
  /// [snapshot] is a frozen reading taken by the page at the instant of the
  /// tap. This cubit never holds the selection cubit and never asks it for the
  /// list again, so nothing that happens in the widgets above — a stray
  /// callback, a rebuild, a late gesture — can change what is being written
  /// after it has started travelling.
  ///
  /// ## Never retried, and never sent twice
  ///
  /// One deliberate act, one call. A second [confirmWithProducts] while one is
  /// pending returns without touching the repository, and no failure branch
  /// below resends. A resend after a lost reply cannot duplicate anything —
  /// the database answers `ALREADY_CONFIRMED` — but it remains the person's
  /// explicit act, never this layer's.
  Future<void> confirmWithProducts(
    ReceiptProductProposalSnapshot snapshot,
  ) async {
    final ReceiptProductSubmission submission = state.productSubmission;
    // The structural half of the duplicate-submission guard. `isEditable` is
    // false for pending, settled, conflict and uncertain alike, so every state
    // a started write can reach refuses a second one — not merely the pending
    // one a button's `loading` flag would cover.
    if (!submission.isEditable || submission.isCheckingStatus) {
      return;
    }
    if (!state.canEdit || state.isBusy) {
      return;
    }

    final String code = state.normalizedCurrencyCode;
    final int? digits = state.currency.minorUnitFor(code);

    // BOTH halves are validated before either is acted on. Reporting the
    // transaction's faults and then stopping would leave somebody to fix the
    // date, press confirm again, and only then be told about the products.
    final Map<ReceiptReviewField, ReceiptReviewFieldProblem> problems =
        validateDraft(state.draft, digits);
    final ReceiptProductSelectionProblem? productProblem = snapshot.validate();

    if (problems.isNotEmpty || productProblem != null) {
      // ZERO repository calls, and nothing is thrown away: every typed value
      // stays in the draft, every chosen product stays in the selection cubit,
      // and the screen stays editable. A locally detected fault is a *definite*
      // failure — the request never left the device — so it is safe to hand the
      // form straight back.
      emit(
        state.copyWith(
          fieldProblems: problems,
          productSubmission: submission.copyWith(
            selectionProblem: productProblem,
            clearSelectionProblem: productProblem == null,
            clearProblem: true,
          ),
        ),
      );
      return;
    }

    // Sound, but the currency's width is not established. Nothing is sent and
    // nothing is marked wrong; the currency line under the field is already
    // saying whether it is being checked, could not be, or is not accepted.
    if (digits == null) {
      return;
    }

    final ReceiptConfirmationInput? input = _inputFrom(
      state.draft,
      code,
      digits,
    );
    if (input == null) {
      return;
    }

    final ReceiptProductSelection selection = snapshot.selection;
    final int generation = ++_productWriteGeneration;

    emit(
      state.copyWith(
        fieldProblems: const <ReceiptReviewField, ReceiptReviewFieldProblem>{},
        clearProblem: true,
        confirmBlockedByExtraction: false,
        // A whole new submission rather than a copyWith: the pending state
        // carries the two snapshots and nothing left over from an earlier
        // refusal.
        productSubmission: ReceiptProductSubmission(
          status: ReceiptProductSubmissionStatus.pending,
          submitted: selection,
          submittedInput: input,
        ),
      ),
    );
    _scheduleSlowNotice(generation);

    final ReceiptExtractionResult<ReceiptWithProductsResult> result =
        await _repository.confirmWithProducts(input, selection);
    if (isClosed || generation != _productWriteGeneration) {
      return;
    }
    // The answer has arrived, whatever it says. A "this is taking longer than
    // expected" landing after it would be telling somebody to keep waiting for
    // something that has already finished.
    _cancelSlowNotice();
    _productWriteGeneration++;

    switch (result) {
      case ReceiptExtractionFailed<ReceiptWithProductsResult>(
        :final ReceiptExtractionProblem problem,
      ):
        _applyProductWriteProblem(problem, code);

      case ReceiptExtractionSuccess<ReceiptWithProductsResult>(
        :final ReceiptWithProductsResult value,
      ):
        await _applyProductWriteResult(value);
    }
  }

  /// Shows the slow notice, if the request that asked for it is still the one
  /// in flight.
  ///
  /// **Presentation only.** It sends nothing, retries nothing, polls nothing,
  /// cancels no request, fails nothing and re-enables no control: the single
  /// `emit` below is the entire body of the callback.
  void _scheduleSlowNotice(int generation) {
    _slowTimer?.cancel();
    _slowTimer = Timer(slowNoticeDelay, () {
      _slowTimer = null;
      if (isClosed || generation != _productWriteGeneration) {
        return;
      }
      if (!state.productSubmission.isPending) {
        return;
      }
      emit(
        state.copyWith(
          productSubmission: state.productSubmission.copyWith(isSlow: true),
        ),
      );
    });
  }

  void _cancelSlowNotice() {
    _slowTimer?.cancel();
    _slowTimer = null;
  }

  /// Maps the three deployed outcomes, and refuses to map a fourth.
  Future<void> _applyProductWriteResult(
    ReceiptWithProductsResult result,
  ) async {
    final ReceiptProductSubmission submission = state.productSubmission;

    switch (result.outcome) {
      // Both are authoritative success, and the difference between them is
      // `changed` — which the copy reads, so that nobody is told a record was
      // created when the answer was that it already existed.
      case ReceiptWithProductsOutcome.confirmed:
      case ReceiptWithProductsOutcome.alreadyConfirmed:
        emit(
          state.copyWith(
            productSubmission: submission.copyWith(
              status: ReceiptProductSubmissionStatus.settled,
              isSlow: false,
              result: result,
              clearProblem: true,
              clearSelectionProblem: true,
            ),
          ),
        );
        // The write said what happened; this says what is STORED. The submitted
        // display is built from these rows and never from the editable
        // selection, so what a person is shown as final is what a Claim
        // Reviewer will see — frozen snapshots and the database's own order.
        //
        // A failure here does not undo anything: the confirmation stays
        // authoritative, the screen stays read-only, and the person is offered
        // the read again rather than the write.
        await _loadStoredProposal(
          source: result.outcome == ReceiptWithProductsOutcome.confirmed
              ? ReceiptProposalSource.newConfirmation
              : ReceiptProposalSource.alreadyConfirmed,
          // The database's own count, so an empty read can be told apart from
          // a receipt that genuinely has no proposal.
          expectedLines: result.lineCount,
        );

      // Something is stored that is not what was sent. Nothing was written by
      // this call and nothing was overwritten, and a proposal is immutable, so
      // there is no correction path and nothing here offers one.
      case ReceiptWithProductsOutcome.conflict:
        emit(
          state.copyWith(
            productSubmission: submission.copyWith(
              status: ReceiptProductSubmissionStatus.conflict,
              isSlow: false,
              result: result,
              clearProblem: true,
            ),
          ),
        );

      // A token this build does not know. NEVER read as confirmed and never as
      // an ordinary failure: the write may well have committed, and the only
      // honest next step is the read the person can ask for by hand.
      case ReceiptWithProductsOutcome.unknown:
        emit(
          state.copyWith(
            productSubmission: submission.copyWith(
              status: ReceiptProductSubmissionStatus.uncertain,
              isSlow: false,
              result: result,
              problem: const ExtractionMalformedResponseProblem(),
            ),
          ),
        );
    }
  }

  /// Splits a failed call into "the database refused" and "nobody knows".
  void _applyProductWriteProblem(
    ReceiptExtractionProblem problem,
    String code,
  ) {
    final ReceiptProductSubmission submission = state.productSubmission;

    if (_isUncertainWriteProblem(problem)) {
      // The write MAY have committed. Not success, not failure, not retried and
      // not polled — and the submitted snapshots are kept, because the person
      // must be able to see what they sent while they find out whether it
      // landed.
      emit(
        state.copyWith(
          productSubmission: submission.copyWith(
            status: ReceiptProductSubmissionStatus.uncertain,
            isSlow: false,
            problem: problem,
          ),
        ),
      );
      return;
    }

    // A definite refusal: the database answered, and an exception raised inside
    // the function rolled the whole transaction back — the confirmation, every
    // proposal line and the Audit Log together. Nothing is stored, so the form
    // may safely be handed back.
    //
    // `22023` gets the same treatment it gets on the header-only path: the
    // width is evicted and put back to unresolved, which closes the confirm
    // control until it has been established again. Nothing is resent.
    final bool scaleMismatch =
        problem is ExtractionCurrencyScaleMismatchProblem;
    if (scaleMismatch) {
      _resolvedWidths.remove(code);
      _staleWidths.add(code);
      _currencyGeneration++;
    }

    emit(
      state.copyWith(
        phase: _isTerminal(problem) ? ReceiptReviewPhase.blocked : state.phase,
        problem: problem,
        currency: scaleMismatch
            ? ReceiptCurrencyResolution(requestedCode: code)
            : null,
        productSubmission: submission.copyWith(
          status: ReceiptProductSubmissionStatus.idle,
          isSlow: false,
          problem: problem,
          clearSubmitted: true,
        ),
      ),
    );
  }

  /// Whether a failed atomic write leaves the outcome genuinely unknown.
  ///
  /// Written as an exhaustive switch over the sealed problem union rather than
  /// a chain of `is` tests, so a problem added later cannot default into
  /// "definitely failed" — which is the direction that loses money, because it
  /// hands somebody an editable form for a receipt that may already be
  /// immutably confirmed.
  static bool _isUncertainWriteProblem(ReceiptExtractionProblem problem) =>
      switch (problem) {
        // The server decided, and said so. A refusal raised inside the function
        // rolls back the whole transaction, so nothing is stored.
        ExtractionUnauthenticatedProblem() ||
        ExtractionForbiddenProblem() ||
        ExtractionNotFoundProblem() ||
        ExtractionInvalidRequestProblem() ||
        ExtractionCurrencyScaleMismatchProblem() => false,
        // No decision reached this device. A dropped socket, an unexpected
        // throw, or a `200` this build could not parse — in the last case the
        // write has almost certainly committed.
        ExtractionServiceUnavailableProblem() ||
        ExtractionNetworkProblem() ||
        ExtractionMalformedResponseProblem() ||
        ExtractionUnknownProblem() => true,
      };

  // ---- The manual status check ---------------------------------------------

  /// Reads what is actually stored, after an explicit tap.
  ///
  /// **Two reads and no write.** It never calls `confirm_receipt_with_products`
  /// and never calls `confirm_receipt_extraction`; there is no path from here
  /// to either, which is why it is safe to offer as an affordance at all.
  ///
  /// It is guarded by [ReceiptProductSubmission.canCheckStatus], which is a
  /// *separate* guard from the write's: a double tap here must be stopped by
  /// its own flag rather than by borrowing one that a settled write would also
  /// have set.
  ///
  /// ## The order of the two reads, and why the second one is conditional
  ///
  /// `get_my_receipt_product_proposal` answers first, because a non-empty
  /// proposal settles everything in one round trip. An **empty** proposal is
  /// ambiguous by design — it means "no proposal", "not yours" and "does not
  /// exist" alike — so `get_my_receipt_confirmation` is asked next to tell a
  /// header-only receipt from one with nothing stored at all. Neither read
  /// distinguishes an unreadable receipt from an unwritten one, and nothing
  /// here tries to: that collapse is what stops this screen confirming somebody
  /// else's receipt exists.
  Future<void> checkReceiptStatus() async {
    final ReceiptProductSubmission submission = state.productSubmission;
    if (!submission.canCheckStatus) {
      return;
    }

    final int generation = ++_statusCheckGeneration;
    emit(
      state.copyWith(
        productSubmission: submission.copyWith(
          isCheckingStatus: true,
          clearStatusCheck: true,
        ),
      ),
    );

    final ReceiptExtractionResult<List<ReceiptProductProposalLine>> proposal =
        await _repository.productProposal(state.submissionId);
    if (isClosed || generation != _statusCheckGeneration) {
      return;
    }

    switch (proposal) {
      case ReceiptExtractionFailed<List<ReceiptProductProposalLine>>(
        :final ReceiptExtractionProblem problem,
      ):
        _settleStatusCheck(
          ReceiptProductStatusCheckOutcome.unreadable,
          problem: problem,
        );
        return;

      case ReceiptExtractionSuccess<List<ReceiptProductProposalLine>>(
        :final List<ReceiptProductProposalLine> value,
      ):
        if (value.isNotEmpty) {
          // A stored proposal is the end of the question. Whether this call
          // wrote it or an earlier one did is not something the person needs to
          // act on: either way the receipt and its products are recorded and
          // nothing further may be sent.
          //
          // The rows this read already returned ARE the display — asking for
          // them a second time would be a round trip for an answer in hand.
          _settleStatusCheck(
            ReceiptProductStatusCheckOutcome.storedWithProposal,
            lines: value,
          );
          return;
        }
    }

    final ReceiptExtractionResult<ReceiptConfirmation?> confirmation =
        await _repository.confirmation(state.submissionId);
    if (isClosed || generation != _statusCheckGeneration) {
      return;
    }

    switch (confirmation) {
      case ReceiptExtractionFailed<ReceiptConfirmation?>(
        :final ReceiptExtractionProblem problem,
      ):
        _settleStatusCheck(
          ReceiptProductStatusCheckOutcome.unreadable,
          problem: problem,
        );

      case ReceiptExtractionSuccess<ReceiptConfirmation?>(
        :final ReceiptConfirmation? value,
      ):
        _settleStatusCheck(
          value == null
              ? ReceiptProductStatusCheckOutcome.nothingStored
              : ReceiptProductStatusCheckOutcome.legacyHeaderOnly,
          confirmation: value,
        );
    }
  }

  void _settleStatusCheck(
    ReceiptProductStatusCheckOutcome outcome, {
    ReceiptExtractionProblem? problem,
    ReceiptConfirmation? confirmation,
    List<ReceiptProductProposalLine>? lines,
  }) {
    final ReceiptProductSubmission submission = state.productSubmission;

    switch (outcome) {
      case ReceiptProductStatusCheckOutcome.storedWithProposal:
        emit(
          state.copyWith(
            productSubmission: submission.copyWith(
              status: ReceiptProductSubmissionStatus.settled,
              isCheckingStatus: false,
              isSlow: false,
              statusCheck: outcome,
              clearProblem: true,
            ),
            // The rows the check just read become the submitted display, so
            // discovering a proposal and confirming one land on exactly the
            // same screen, built from exactly the same frozen values.
            storedProposal: ReceiptStoredProposal(
              phase: ReceiptProposalPhase.loaded,
              lines: lines ?? const <ReceiptProductProposalLine>[],
              source: ReceiptProposalSource.statusCheck,
            ),
          ),
        );

      case ReceiptProductStatusCheckOutcome.legacyHeaderOnly:
        // A confirmation with no proposal. NOTHING is appended to it and
        // nothing is submitted again — the combined RPC answers `CONFLICT` to
        // any attempt to top one up, and a proposal is immutable regardless.
        // Recorded, frozen, and left for the unit that presents it.
        emit(
          state.copyWith(
            confirmation: confirmation,
            productSubmission: submission.copyWith(
              status: ReceiptProductSubmissionStatus.conflict,
              isCheckingStatus: false,
              isSlow: false,
              statusCheck: outcome,
              clearProblem: true,
            ),
            storedProposal: const ReceiptStoredProposal(
              phase: ReceiptProposalPhase.legacyHeaderOnly,
              source: ReceiptProposalSource.statusCheck,
            ),
          ),
        );

      case ReceiptProductStatusCheckOutcome.nothingStored:
        // The ONE outcome that reopens the form, and only because both reads
        // answered: no proposal and no confirmation. The draft is untouched and
        // the selection cubit is never cleared, so every typed value and every
        // chosen product is exactly where it was left.
        emit(
          state.copyWith(
            productSubmission: ReceiptProductSubmission(statusCheck: outcome),
            // Nothing is stored, so nothing is claimed about a proposal either.
            storedProposal: const ReceiptStoredProposal(),
          ),
        );

      case ReceiptProductStatusCheckOutcome.unreadable:
        // Nothing is concluded. The screen stays exactly as uncertain as it
        // was, no retry is scheduled and no loop is started; the person may ask
        // again by hand.
        emit(
          state.copyWith(
            productSubmission: submission.copyWith(
              isCheckingStatus: false,
              statusCheck: outcome,
              problem: problem,
            ),
          ),
        );
    }
  }

  // ---- The preview ---------------------------------------------------------

  /// Mints a fresh capability for the receipt image.
  ///
  /// Called on open, on an image load failure — the window is about two minutes
  /// and a resumed screen will have outlived it — and never on a timer. The URL
  /// is held in memory for exactly as long as this screen exists.
  Future<void> loadPreview() async {
    if (state.previewPhase == ReceiptPreviewPhase.loading) {
      return;
    }
    emit(
      state.copyWith(
        previewPhase: ReceiptPreviewPhase.loading,
        clearPreviewProblem: true,
      ),
    );

    final ReceiptExtractionResult<ReceiptImagePreview> result =
        await _repository.imagePreview(state.submissionId);
    if (isClosed) {
      return;
    }

    switch (result) {
      case ReceiptExtractionFailed<ReceiptImagePreview>(
        :final ReceiptExtractionProblem problem,
      ):
        emit(
          state.copyWith(
            previewPhase: ReceiptPreviewPhase.failed,
            previewProblem: problem,
            clearPreview: true,
          ),
        );

      case ReceiptExtractionSuccess<ReceiptImagePreview>(
        :final ReceiptImagePreview value,
      ):
        // The revision is what makes this emit. Two capabilities minted a
        // minute apart carry the same expiry and compare equal, and the URL is
        // deliberately not a prop, so without the counter the screen would keep
        // rendering a URL that had already died.
        emit(
          state.copyWith(
            preview: value,
            previewPhase: ReceiptPreviewPhase.ready,
            previewRevision: state.previewRevision + 1,
            clearPreviewProblem: true,
          ),
        );
    }
  }

  /// Drops the capability from memory.
  ///
  /// Called by the screen as it leaves, so the URL does not sit in a state
  /// object waiting for the cubit itself to be collected.
  void forgetPreview() {
    if (isClosed) {
      return;
    }
    emit(
      state.copyWith(
        clearPreview: true,
        previewPhase: ReceiptPreviewPhase.idle,
        clearPreviewProblem: true,
      ),
    );
  }

  @override
  Future<void> close() {
    // The loop reads `isClosed` before every emit and before every delay, so
    // closing is what ends it. Nothing else needs cancelling: there is no
    // timer, no subscription and no controller here.
    _appActive = false;
    // The one timer, cancelled rather than left to fire into a closed cubit.
    _cancelSlowNotice();
    // A reply still in flight is dropped by these as well as by `isClosed`, so
    // nothing that lands after the screen has gone can reach an emit.
    _productWriteGeneration++;
    _statusCheckGeneration++;
    _proposalGeneration++;
    return super.close();
  }

  // ---- Phase resolution ----------------------------------------------------

  ReceiptReviewPhase _phaseForRequest(ReceiptExtractionRequestResult result) {
    return switch (result.outcome) {
      ReceiptExtractionRequestOutcome.alreadyConfirmed =>
        ReceiptReviewPhase.confirmed,
      ReceiptExtractionRequestOutcome.exhausted => ReceiptReviewPhase.exhausted,
      ReceiptExtractionRequestOutcome.extractionUnavailable =>
        ReceiptReviewPhase.unavailable,
      ReceiptExtractionRequestOutcome.queued ||
      ReceiptExtractionRequestOutcome.active ||
      ReceiptExtractionRequestOutcome.succeeded =>
        result.extraction == null
            ? ReceiptReviewPhase.unavailable
            : _phaseForStatus(result.extraction!),
      // A token this build does not know. Never treated as an attempt having
      // been created, and never polled: a spinner for a job that does not exist
      // is worse than an honest dead end.
      ReceiptExtractionRequestOutcome.unknown => ReceiptReviewPhase.unavailable,
    };
  }

  ReceiptReviewPhase _phaseForStatus(ReceiptExtraction extraction) {
    if (extraction.confirmationExists) {
      return ReceiptReviewPhase.confirmed;
    }
    return switch (extraction.status) {
      ReceiptExtractionStatus.queued => ReceiptReviewPhase.queued,
      ReceiptExtractionStatus.processing => ReceiptReviewPhase.processing,
      ReceiptExtractionStatus.succeeded => ReceiptReviewPhase.succeeded,
      ReceiptExtractionStatus.failed =>
        extraction.attemptsRemaining == 0
            ? ReceiptReviewPhase.exhausted
            : ReceiptReviewPhase.failed,
      // Never open. A build that treated an unrecognised token as in-flight
      // would poll until its budget ran out and then say nothing useful.
      ReceiptExtractionStatus.unknown => ReceiptReviewPhase.unavailable,
    };
  }

  ReceiptReviewPhase _phaseForProblem(ReceiptExtractionProblem problem) =>
      _isTerminal(problem)
      ? ReceiptReviewPhase.blocked
      : ReceiptReviewPhase.unreachable;

  static bool _isTerminal(ReceiptExtractionProblem problem) =>
      problem is ExtractionUnauthenticatedProblem ||
      problem is ExtractionForbiddenProblem ||
      problem is ExtractionNotFoundProblem;
}

/// The first rule each field breaks, or an empty map when none does.
///
/// A pre-check in the spirit of the submission flow's file-size ceiling: it
/// saves a doomed round trip and lets the form mark a control immediately. It
/// does **not** make this client the authority — every rule is enforced again in
/// SQL, most obviously the currency, whose real check is a foreign key against a
/// 165-row seeded list this client does not carry.
///
/// [digits] is nullable, and null means the currency's width is not established.
/// The amount fields are then checked for **presence only**: whether `1.234` has
/// too many decimal places is a question about a currency, and answering it
/// without the currency's width would be the assumption this whole correction
/// removes. Nothing is converted and nothing may be confirmed in that state.
Map<ReceiptReviewField, ReceiptReviewFieldProblem> validateDraft(
  ReceiptReviewDraft draft,
  int? digits,
) {
  final Map<ReceiptReviewField, ReceiptReviewFieldProblem> problems =
      <ReceiptReviewField, ReceiptReviewFieldProblem>{};

  final ReceiptCivilDate? date = draft.transactionDate;
  if (date == null) {
    problems[ReceiptReviewField.transactionDate] =
        ReceiptReviewFieldProblem.missing;
  } else if (date.compareTo(earliestReceiptDate) < 0) {
    problems[ReceiptReviewField.transactionDate] =
        ReceiptReviewFieldProblem.dateTooEarly;
  }

  final String currency = draft.currencyCode.trim().toUpperCase();
  if (currency.isEmpty) {
    problems[ReceiptReviewField.currencyCode] =
        ReceiptReviewFieldProblem.missing;
  } else if (!_currencyShape.hasMatch(currency)) {
    problems[ReceiptReviewField.currencyCode] =
        ReceiptReviewFieldProblem.invalidCurrency;
  }

  final ReceiptReviewFieldProblem? total = _amountProblem(
    draft.totalText,
    digits,
    required: true,
  );
  if (total != null) {
    problems[ReceiptReviewField.total] = total;
  }

  final ReceiptReviewFieldProblem? subtotal = _amountProblem(
    draft.subtotalText,
    digits,
    required: false,
  );
  if (subtotal != null) {
    problems[ReceiptReviewField.subtotal] = subtotal;
  }

  final ReceiptReviewFieldProblem? tax = _amountProblem(
    draft.taxText,
    digits,
    required: false,
  );
  if (tax != null) {
    problems[ReceiptReviewField.tax] = tax;
  }

  if (draft.merchantName.trim().length > _maxMerchantNameLength) {
    problems[ReceiptReviewField.merchantName] =
        ReceiptReviewFieldProblem.tooLong;
  }
  if (draft.documentNumber.trim().length > _maxDocumentNumberLength) {
    problems[ReceiptReviewField.documentNumber] =
        ReceiptReviewFieldProblem.tooLong;
  }

  return problems;
}

ReceiptReviewFieldProblem? _amountProblem(
  String text,
  int? digits, {
  required bool required,
}) {
  if (text.trim().isEmpty) {
    // An empty required box is a rule that needs no currency to state.
    return required ? ReceiptReviewFieldProblem.missing : null;
  }
  if (digits == null) {
    return null;
  }
  final MinorUnitResult result = parseMinorUnits(text, digits);
  if (result is MinorUnitValue) {
    return null;
  }
  return switch ((result as MinorUnitRefusal).problem) {
    MinorUnitProblem.empty => ReceiptReviewFieldProblem.missing,
    MinorUnitProblem.notANumber => ReceiptReviewFieldProblem.notANumber,
    MinorUnitProblem.tooPrecise => ReceiptReviewFieldProblem.tooPrecise,
    MinorUnitProblem.outOfRange => ReceiptReviewFieldProblem.outOfRange,
  };
}
