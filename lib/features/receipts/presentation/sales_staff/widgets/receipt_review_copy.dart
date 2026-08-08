import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/receipt_confirmation_entry_mode.dart';
import '../../../domain/entities/receipt_confirmation_field.dart';
import '../../../domain/entities/receipt_extraction_failure_code.dart';
import '../../../domain/entities/receipt_extraction_problem.dart';
import '../../../domain/entities/receipt_extraction_warning_code.dart';
import '../../../domain/entities/receipt_product_selection.dart';
import '../../../domain/entities/selected_receipt_product.dart';
import '../cubit/receipt_review_cubit.dart';

/// One piece of user-facing feedback: a tone, a headline and a sentence.
final class ReceiptReviewNotice {
  const ReceiptReviewNotice({
    required this.tone,
    required this.title,
    required this.message,
  });

  final SrAlertTone tone;
  final String title;
  final String message;
}

/// Every sentence the review screen can show, in one place.
///
/// ## Nothing here is derived from a backend string
///
/// The copy is selected by a **discriminant** — a phase, a closed vocabulary
/// token, a typed problem. No Postgres message, SQLSTATE, Edge Function body,
/// storage path, provider name, operation id, claim token or URL is ever
/// interpolated, because none of them reaches this layer to be interpolated.
///
/// ## The raw vocabulary never reaches a screen
///
/// Warning codes, failure codes, entry modes and changed-field names all arrive
/// as enums and leave as sentences. A token this build does not recognise gets
/// neutral copy rather than its own string: showing somebody
/// `SUBTOTAL_TAX_TOTAL_MISMATCH` would be leaking an implementation detail in
/// place of an explanation.
///
/// ## An outage never reads as a denial
///
/// [ReceiptReviewPhase.unreachable] says nothing about permission and offers a
/// retry; [ReceiptReviewPhase.blocked] offers none. Telling somebody they lack
/// access when the network merely failed is both wrong and alarming.
abstract final class ReceiptReviewCopy {
  static const String pageDescription =
      'Check what we read from your invoice / receipt, correct anything that '
      'is wrong, '
      'and confirm it.';

  // ---- Attempt status ------------------------------------------------------

  /// The short label shown in the status badge.
  static String statusLabel(ReceiptReviewPhase phase) => switch (phase) {
    ReceiptReviewPhase.initial || ReceiptReviewPhase.requesting => 'Starting',
    ReceiptReviewPhase.queued => 'Queued',
    ReceiptReviewPhase.processing => 'Reading',
    ReceiptReviewPhase.succeeded => 'Ready to review',
    ReceiptReviewPhase.failed => 'Could not read',
    ReceiptReviewPhase.exhausted => 'No attempts left',
    ReceiptReviewPhase.unavailable => 'Reading unavailable',
    ReceiptReviewPhase.confirming => 'Confirming',
    ReceiptReviewPhase.confirmed => 'Confirmed',
    ReceiptReviewPhase.unreachable => 'Not available just now',
    ReceiptReviewPhase.blocked => 'Unavailable',
  };

  static SrTone statusTone(ReceiptReviewPhase phase) => switch (phase) {
    ReceiptReviewPhase.succeeded => SrTone.indigo,
    ReceiptReviewPhase.confirmed => SrTone.emerald,
    ReceiptReviewPhase.failed || ReceiptReviewPhase.exhausted => SrTone.amber,
    ReceiptReviewPhase.blocked => SrTone.red,
    ReceiptReviewPhase.initial ||
    ReceiptReviewPhase.requesting ||
    ReceiptReviewPhase.queued ||
    ReceiptReviewPhase.processing ||
    ReceiptReviewPhase.confirming ||
    ReceiptReviewPhase.unavailable ||
    ReceiptReviewPhase.unreachable => SrTone.slate,
  };

  /// The sentence under the status, or null when the phase speaks for itself.
  static String? statusDescription(ReceiptReviewState state) =>
      switch (state.phase) {
        ReceiptReviewPhase.requesting =>
          'Asking for your invoice / receipt to be read. This does not take '
              'long.',
        ReceiptReviewPhase.queued =>
          'Your invoice / receipt is in the queue. This screen updates on '
              'its own.',
        ReceiptReviewPhase.processing =>
          'Reading your invoice / receipt now. This screen updates on its own.',
        ReceiptReviewPhase.succeeded =>
          'Check every value against the printed invoice / receipt before you '
              'confirm.',
        ReceiptReviewPhase.exhausted =>
          'This invoice / receipt has used all three reading attempts. You '
              'can still '
              'type the details in yourself.',
        ReceiptReviewPhase.unavailable =>
          'Reading invoices / receipts is not available right now. You can '
              'type the '
              'details in yourself.',
        ReceiptReviewPhase.confirmed =>
          'These details are recorded and cannot be changed.',
        _ => null,
      };

  // ---- Failure -------------------------------------------------------------

  /// Why an attempt ended without a reading.
  ///
  /// Three client codes and no more. The backend stores ten and shows three on
  /// purpose: the other seven describe our infrastructure rather than this
  /// person's receipt, and the action in every one of those cases is identical.
  static ReceiptReviewNotice failureNotice(ReceiptExtractionFailureCode? code) {
    return switch (code) {
      ReceiptExtractionFailureCode.imageNotAReceipt => const ReceiptReviewNotice(
        tone: SrAlertTone.warning,
        title: 'That photo does not look like an invoice / receipt',
        message:
            'Take another photo of the printed invoice / receipt, making sure '
            'the whole '
            'invoice / receipt is in frame.',
      ),
      ReceiptExtractionFailureCode.imageUnusable => const ReceiptReviewNotice(
        tone: SrAlertTone.warning,
        title: 'We could not use that image',
        message:
            'The photo is too blurred, too dark or too small to read. Take '
            'another one in better light and hold the phone steady.',
      ),
      ReceiptExtractionFailureCode.extractionUnavailable ||
      ReceiptExtractionFailureCode.unknown ||
      null => const ReceiptReviewNotice(
        tone: SrAlertTone.warning,
        title: 'We could not read this invoice / receipt',
        message:
            'Nothing is wrong with your photo. You can try again, or type the '
            'details in yourself.',
      ),
    };
  }

  // ---- Warnings ------------------------------------------------------------

  /// A safe review hint, in words.
  ///
  /// **None of these blocks anything.** They exist to draw the eye to a figure
  /// worth a second look, and for no other purpose.
  static String warningLabel(
    ReceiptExtractionWarningCode code,
  ) => switch (code) {
    ReceiptExtractionWarningCode.lowConfidenceTotal =>
      'Check the total carefully — we were not confident reading it.',
    ReceiptExtractionWarningCode.lowConfidenceDate =>
      'Check the date carefully — we were not confident reading it.',
    ReceiptExtractionWarningCode.missingMerchantName =>
      'We could not find a shop name on the invoice / receipt.',
    ReceiptExtractionWarningCode.missingDocumentNumber =>
      'We could not find an invoice / receipt number.',
    ReceiptExtractionWarningCode.missingTransactionTime =>
      'We could not find a time on the invoice / receipt.',
    ReceiptExtractionWarningCode.subtotalTaxTotalMismatch =>
      'The subtotal and tax do not add up to the total. That is often '
          'normal — check the figures anyway.',
    ReceiptExtractionWarningCode.ambiguousAmountFormat =>
      'An amount was printed in a way we could not read exactly. Please '
          'type it in yourself.',
    ReceiptExtractionWarningCode.negativeAmountRejected =>
      'An amount came out negative, so we left it blank. Please type it in.',
    ReceiptExtractionWarningCode.zeroTotal =>
      'The total reads as zero. Check that against the printed '
          'invoice / receipt.',
    ReceiptExtractionWarningCode.dateInFuture =>
      'The date is in the future. Check it against the printed '
          'invoice / receipt.',
    ReceiptExtractionWarningCode.currencyInferredFromDefault =>
      'No currency was printed, so we assumed one. Check it.',
    ReceiptExtractionWarningCode.multipleTotalsFound =>
      'More than one total was printed. Check which one is right.',
    // A hint this build does not recognise. Rendered generically rather
    // than as its raw token.
    ReceiptExtractionWarningCode.unknown =>
      'Something on this invoice / receipt is worth a second look.',
  };

  // ---- Confirmation --------------------------------------------------------

  /// How a confirmation's values came to be. Server-derived, never computed
  /// here: the comparison rules live in SQL and are deliberately forgiving
  /// about casing and punctuation.
  static String entryModeLabel(ReceiptConfirmationEntryMode? mode) =>
      switch (mode) {
        ReceiptConfirmationEntryMode.manual => 'Typed in',
        ReceiptConfirmationEntryMode.extracted =>
          'As read from the invoice / receipt',
        ReceiptConfirmationEntryMode.mixed => 'Read, with your corrections',
        ReceiptConfirmationEntryMode.unknown || null => 'Recorded',
      };

  /// One corrected field, in words.
  static String changedFieldLabel(ReceiptConfirmationField field) =>
      switch (field) {
        ReceiptConfirmationField.currencyCode => 'Currency',
        ReceiptConfirmationField.documentNumber => 'Invoice / receipt no.',
        ReceiptConfirmationField.merchantName => 'Shop name',
        ReceiptConfirmationField.subtotalMinor => 'Subtotal',
        ReceiptConfirmationField.taxTotalMinor => 'Tax',
        ReceiptConfirmationField.totalMinor => 'Total',
        ReceiptConfirmationField.transactionDate => 'Date',
        ReceiptConfirmationField.transactionTime => 'Time',
        ReceiptConfirmationField.unknown => 'Another detail',
      };

  // ---- The currency's decimal width ----------------------------------------

  /// The hint beside an amount field.
  ///
  /// **Claims nothing before the backend has answered.** The unresolved case is
  /// the important one: saying "up to 2 decimal places" while the width is
  /// unknown is how somebody comes to type `10.00` for a ¥1000 receipt, and the
  /// sentence would be a guess dressed as an instruction.
  static String amountHint(int? minorDigits) => switch (minorDigits) {
    null => 'Enter a supported currency to determine decimal places.',
    0 => 'Whole numbers only for this currency.',
    _ => 'Up to $minorDigits decimal places, as printed.',
  };

  /// The one line under the currency field about where its width has reached.
  ///
  /// Null while nothing needs saying — an empty field, or a resolved width the
  /// amount hints already state.
  static String? currencyStatus(ReceiptReviewState state) {
    final ReceiptCurrencyResolution currency = state.currency;
    if (!state.hasCurrencyShape) {
      return null;
    }
    return switch (currency.phase) {
      ReceiptCurrencyPhase.resolving => 'Checking this currency…',
      ReceiptCurrencyPhase.failed =>
        'We could not check this currency just now. Nothing was lost — try '
            'again.',
      ReceiptCurrencyPhase.unresolved =>
        'This currency has not been checked yet.',
      // The unsupported case is the field's own error, and the resolved case is
      // already said beside every amount.
      ReceiptCurrencyPhase.unsupported || ReceiptCurrencyPhase.resolved => null,
    };
  }

  // ---- Form errors ---------------------------------------------------------

  static String fieldError(
    ReceiptReviewField field,
    ReceiptReviewFieldProblem problem,
  ) {
    return switch (problem) {
      ReceiptReviewFieldProblem.missing => switch (field) {
        ReceiptReviewField.transactionDate =>
          'Choose the date on the invoice / receipt.',
        ReceiptReviewField.currencyCode => 'Enter the currency.',
        ReceiptReviewField.total => 'Enter the total on the invoice / receipt.',
        _ => 'This is required.',
      },
      ReceiptReviewFieldProblem.invalidCurrency =>
        'Use the three-letter currency code, such as AED.',
      // Three letters, but not one this system accepts. It says what to do and
      // does not name a table, a list or how many currencies there are.
      ReceiptReviewFieldProblem.unsupportedCurrency =>
        'We cannot record invoices / receipts in that currency. Check the '
            'code on the invoice / receipt.',
      ReceiptReviewFieldProblem.notANumber =>
        'Enter the amount using digits and one decimal point.',
      ReceiptReviewFieldProblem.tooPrecise =>
        'That is more decimal places than this currency uses.',
      ReceiptReviewFieldProblem.outOfRange =>
        'That amount is outside the range we can record.',
      ReceiptReviewFieldProblem.tooLong => 'That is too long.',
      ReceiptReviewFieldProblem.dateTooEarly =>
        'That date is too far in the past to be an invoice / receipt date.',
    };
  }

  // ---- The atomic header-and-products confirmation -------------------------

  /// The label on the one final confirmation control.
  static const String confirmAction = 'Confirm invoice / receipt and products';

  /// What is said while the immutable write is in flight.
  ///
  /// It names **both** halves on purpose: one call writes the transaction and
  /// the product proposal together, and a sentence that mentioned only the
  /// receipt would understate what is about to become unchangeable.
  static const String confirmPending =
      'Confirming invoice / receipt and products…';

  /// Shown once the request has outlived [slowConfirmationNotice].
  ///
  /// The second sentence is the whole point of the first. A slow immutable
  /// write is the moment somebody reaches for the button again, and this is the
  /// only thing standing between them and a second deliberate act.
  static const String confirmSlow =
      'This is taking longer than expected. Do not submit again.';

  /// Shown when the result is genuinely unknown.
  ///
  /// Neither "it worked" nor "it failed", because neither is known. No SQLSTATE,
  /// no provider message, no hint and no stack trace: none of them reaches this
  /// layer to be shown.
  static const String confirmUnverified =
      'The confirmation result could not be verified. Do not submit again.';

  /// The one manual recovery affordance. A read, never a resend.
  static const String statusCheckAction = 'Check invoice / receipt status';

  /// Why a proposal was refused before anything was sent.
  ///
  /// Every one of these is a *local* pre-check, so the sentence says what to do
  /// rather than what a server thought. None of them removed, merged, clamped
  /// or reordered anything — and each says so, because a person who chose fifty
  /// products needs to know their list is intact.
  static String productError(ReceiptProductSelectionProblem problem) =>
      switch (problem) {
        ReceiptProductSelectionProblem.noProductsSelected =>
          'Add at least one product before confirming. An invoice / receipt '
              'cannot be '
              'submitted without its products.',
        ReceiptProductSelectionProblem.tooManyProducts =>
          'An invoice / receipt can carry at most $maxReceiptProductLines '
              'products. '
              'Remove some before confirming — nothing was removed for you.',
        ReceiptProductSelectionProblem.invalidQuantity =>
          'Every quantity must be a whole number between '
              '$minReceiptProductQuantity and $maxReceiptProductQuantity. '
              'Nothing was changed for you.',
        ReceiptProductSelectionProblem.duplicateProduct =>
          'A product is listed twice. Remove the extra line — the quantities '
              'were not merged for you.',
        ReceiptProductSelectionProblem.notInCatalogue =>
          'A chosen product is no longer in your product list. Remove it and '
              'choose again.',
      };

  /// The panel above the final confirmation control, or null while the proposal
  /// is simply being built.
  ///
  /// One notice at a time, in the order that matters: what was refused before
  /// sending, then what is happening now, then what was answered.
  static ReceiptReviewNotice? productSubmissionNotice(
    ReceiptProductSubmission submission,
  ) {
    final ReceiptProductSelectionProblem? refused = submission.selectionProblem;
    if (refused != null) {
      return ReceiptReviewNotice(
        tone: SrAlertTone.warning,
        title: 'Check the products on this invoice / receipt',
        message: productError(refused),
      );
    }

    return switch (submission.status) {
      ReceiptProductSubmissionStatus.idle =>
        submission.statusCheck == ReceiptProductStatusCheckOutcome.nothingStored
            ? const ReceiptReviewNotice(
                tone: SrAlertTone.info,
                title: 'Nothing was stored for this invoice / receipt',
                message:
                    'We found no confirmation and no products for it. Your '
                    'details and your chosen products are exactly as you left '
                    'them, and you can confirm when you are ready.',
              )
            : null,

      ReceiptProductSubmissionStatus.pending => ReceiptReviewNotice(
        tone: SrAlertTone.info,
        title: confirmPending,
        message: submission.isSlow
            ? confirmSlow
            : 'The invoice / receipt details and the products are being '
                  'recorded '
                  'together. This cannot be undone once it finishes.',
      ),

      ReceiptProductSubmissionStatus.settled => _settledNotice(submission),

      // Says what is known and nothing more. It does NOT say the receipt is
      // unconfirmed, does not name whoever confirmed it, does not describe what
      // differs, and offers no resend: a proposal is immutable and there is no
      // correction path to offer.
      ReceiptProductSubmissionStatus.conflict =>
        submission.statusCheck ==
                ReceiptProductStatusCheckOutcome.legacyHeaderOnly
            ? const ReceiptReviewNotice(
                tone: SrAlertTone.warning,
                title: 'This invoice / receipt was confirmed without products',
                message:
                    'Its details are already recorded and cannot be changed, '
                    'and products cannot be added to it now. Nothing you '
                    'entered was sent again.',
              )
            : const ReceiptReviewNotice(
                tone: SrAlertTone.warning,
                title:
                    'This invoice / receipt already has a different confirmation',
                message:
                    'Nothing was recorded by this attempt and nothing was '
                    'overwritten. Check what is stored for this '
                    'invoice / receipt before doing anything else.',
              ),

      ReceiptProductSubmissionStatus.uncertain => ReceiptReviewNotice(
        tone: SrAlertTone.warning,
        title: 'We could not confirm what happened',
        message:
            submission.statusCheck ==
                ReceiptProductStatusCheckOutcome.unreadable
            ? '$confirmUnverified We could not read the stored state either — '
                  'you can check again in a moment.'
            : confirmUnverified,
      ),
    };
  }

  /// The success sentence, which is careful about two separate things.
  ///
  /// It never claims a record was created when the answer was that one already
  /// existed, and it states plainly that nothing downstream happened: no
  /// campaign was matched, no reward was granted and no coins were issued.
  /// Phase 1D-B writes an assertion about what was bought and nothing else, and
  /// a staff member who assumed otherwise would be told a reward was coming
  /// that is not.
  static ReceiptReviewNotice _settledNotice(
    ReceiptProductSubmission submission,
  ) {
    // `changed` is the backend's own word, and the only thing that separates
    // "this call wrote it" from "it was already there".
    final bool created = submission.result?.changed ?? false;

    const String finality =
        'This proposal is final and cannot be changed. '
        'No campaign, reward or coins were created by it.';
    final String what = created
        ? 'The invoice / receipt details and the products you chose are now '
              'recorded '
              'together.'
        : 'The same details and the same products were already stored, so '
              'nothing was duplicated.';

    return ReceiptReviewNotice(
      tone: SrAlertTone.success,
      title: created
          ? 'Invoice / receipt and products recorded'
          : 'This invoice / receipt was already recorded',
      message: '$what $finality',
    );
  }

  // ---- The stored, immutable proposal --------------------------------------

  /// The heading over the submitted proposal. A word, never a colour alone.
  static const String submittedTitle = 'Products submitted';

  static const String submittedStatusBadge = 'Submitted';

  /// The four things a staff member must understand about what they just did.
  ///
  /// Each is a separate sentence because each is a separate fact, and running
  /// them together is how the important one gets skimmed past. The second is
  /// the one that changes behaviour: a Claim Reviewer accepts or rejects the
  /// **whole** list, so a single wrong line costs the entire proposal.
  static const String submittedFinality =
      'This product list is final. It cannot be edited, removed, reordered or '
      'submitted again.';

  static const String submittedWholeListReview =
      'A Claim Reviewer will accept or reject the complete list. If one line is '
      'wrong, the whole list can be rejected.';

  static const String submittedReceiptSeparate =
      'Checking the invoice / receipt photo itself is a separate decision, '
      'made on its '
      'own.';

  static const String submittedNoRewards =
      'No campaign was evaluated, and no reward or coins were created.';

  /// Shown while the stored proposal is being read.
  static const String submittedLoading = 'Loading the submitted products…';

  /// Shown when the read did not deliver.
  ///
  /// It is careful to say the *lines* could not be loaded, not that there are
  /// none: the confirmation is authoritative and stays so, and this sentence
  /// must never read as "your products were lost".
  static const String submittedUnreadable =
      'Your invoice / receipt and products are recorded. We could not load '
      'the submitted '
      'lines just now — nothing was lost, and nothing was sent again.';

  /// The heading for a receipt confirmed before Phase 1D-B existed.
  static const String legacyTitle =
      'This invoice / receipt was confirmed without products';

  /// What a header-only confirmation means, in four plain facts.
  ///
  /// Deliberately not phrased as an error and deliberately offering no remedy:
  /// it is a legal historical state, the confirmation is immutable, and there
  /// is no path in this flow that could add products to it. An affordance here
  /// could only ever fail.
  static const String legacyExplanation =
      'Its transaction details were recorded through the earlier flow, before '
      'products were part of an invoice / receipt. No product list was '
      'submitted with it, '
      'and products cannot be added to it now.';

  static const String legacyConsequence =
      'This invoice / receipt cannot go forward for product-based campaign '
      'qualification. '
      'No campaign, reward or coins were created.';

  // ---- Problems ------------------------------------------------------------

  /// Why a call produced no answer.
  ///
  /// Every case is a *call* that did not deliver, never a state the backend
  /// reported: a failed extraction, exhausted attempts and a shut gate are all
  /// ordinary answers and none of them appears here.
  static ReceiptReviewNotice problemNotice(ReceiptExtractionProblem problem) {
    return switch (problem) {
      ExtractionUnauthenticatedProblem() => const ReceiptReviewNotice(
        tone: SrAlertTone.error,
        title: 'Your session has ended',
        message: 'Sign in again to carry on reviewing this invoice / receipt.',
      ),
      // Deliberately says nothing about *why*, and never "that is not yours":
      // the backend answers an unknown receipt, somebody else's, and another
      // Retailer's identically, and splitting them here would recreate the
      // existence oracle SQL is careful to deny.
      ExtractionForbiddenProblem() ||
      ExtractionNotFoundProblem() => const ReceiptReviewNotice(
        tone: SrAlertTone.warning,
        title: 'This invoice / receipt is not available to you',
        message:
            'You can only review invoices / receipts you submitted yourself. '
            'Go back to '
            'your submissions and pick one from there.',
      ),
      ExtractionInvalidRequestProblem() => const ReceiptReviewNotice(
        tone: SrAlertTone.warning,
        title: 'Those details could not be accepted',
        message: 'Check the values you entered and try confirming again.',
      ),
      // SQLSTATE `22023`, and the words say nothing of the sort: no code, no
      // Postgres message, no expected number, no table. Nothing was recorded
      // and nothing is resent — the width has to be established again first,
      // which is why this asks for a look rather than promising a retry.
      ExtractionCurrencyScaleMismatchProblem() => const ReceiptReviewNotice(
        tone: SrAlertTone.warning,
        title: 'Check the currency and amounts',
        message:
            'The currency rules changed or could not be verified. Nothing was '
            'recorded. Check the currency and amounts, then try again.',
      ),
      ExtractionServiceUnavailableProblem() ||
      ExtractionUnknownProblem() => const ReceiptReviewNotice(
        tone: SrAlertTone.warning,
        title: 'We could not reach the service',
        message: 'Nothing was lost. Try again in a moment.',
      ),
      ExtractionNetworkProblem() => const ReceiptReviewNotice(
        tone: SrAlertTone.warning,
        title: 'No connection',
        message: 'Check your connection and try again. Nothing was sent twice.',
      ),
      ExtractionMalformedResponseProblem() => const ReceiptReviewNotice(
        tone: SrAlertTone.warning,
        title: 'We could not read the reply',
        message:
            'This app may need updating. Try again, and tell your manager if '
            'it keeps happening.',
      ),
    };
  }

  /// The notice shown above the form, or null when nothing needs saying.
  static ReceiptReviewNotice? noticeFor(ReceiptReviewState state) {
    if (state.confirmBlockedByExtraction) {
      return const ReceiptReviewNotice(
        tone: SrAlertTone.info,
        title: 'Still reading this invoice / receipt',
        message:
            'We are finishing the reading first. Nothing was recorded — try '
            'confirming again in a moment.',
      );
    }
    final ReceiptExtractionProblem? problem = state.problem;
    if (problem != null) {
      return problemNotice(problem);
    }
    if (state.pollBudgetSpent) {
      return const ReceiptReviewNotice(
        tone: SrAlertTone.info,
        title: 'This is taking longer than usual',
        message:
            'We stopped checking automatically. Tap Check again, or type the '
            'details in yourself.',
      );
    }
    return null;
  }
}
