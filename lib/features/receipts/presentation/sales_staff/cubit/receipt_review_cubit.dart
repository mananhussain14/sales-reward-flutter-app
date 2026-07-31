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

  bool _started = false;
  bool _polling = false;
  bool _appActive = true;
  bool _draftSeeded = false;
  bool _amountsSeeded = false;
  int _pollsUsed = 0;
  ReceiptReviewPhase _phaseBeforeConfirm = ReceiptReviewPhase.succeeded;

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
      await _loadConfirmation();
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
    if (!state.canEdit) {
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
    if (!state.canEdit) {
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
