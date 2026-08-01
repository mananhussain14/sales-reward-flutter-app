import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/receipt_confirmation_entry_mode.dart';
import '../../../domain/entities/receipt_confirmation_field.dart';
import '../../../domain/entities/receipt_extraction_failure_code.dart';
import '../../../domain/entities/receipt_extraction_problem.dart';
import '../../../domain/entities/receipt_extraction_warning_code.dart';
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
      'Check what we read from your receipt, correct anything that is wrong, '
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
          'Asking for your receipt to be read. This does not take long.',
        ReceiptReviewPhase.queued =>
          'Your receipt is in the queue. This screen updates on its own.',
        ReceiptReviewPhase.processing =>
          'Reading your receipt now. This screen updates on its own.',
        ReceiptReviewPhase.succeeded =>
          'Check every value against the paper receipt before you confirm.',
        ReceiptReviewPhase.exhausted =>
          'This receipt has used all three reading attempts. You can still '
              'type the details in yourself.',
        ReceiptReviewPhase.unavailable =>
          'Reading receipts is not available right now. You can type the '
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
        title: 'That photo does not look like a receipt',
        message:
            'Take another photo of the printed receipt, making sure the whole '
            'receipt is in frame.',
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
        title: 'We could not read this receipt',
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
      'We could not find a shop name on the receipt.',
    ReceiptExtractionWarningCode.missingDocumentNumber =>
      'We could not find a receipt number.',
    ReceiptExtractionWarningCode.missingTransactionTime =>
      'We could not find a time on the receipt.',
    ReceiptExtractionWarningCode.subtotalTaxTotalMismatch =>
      'The subtotal and tax do not add up to the total. That is often '
          'normal — check the figures anyway.',
    ReceiptExtractionWarningCode.ambiguousAmountFormat =>
      'An amount was printed in a way we could not read exactly. Please '
          'type it in yourself.',
    ReceiptExtractionWarningCode.negativeAmountRejected =>
      'An amount came out negative, so we left it blank. Please type it in.',
    ReceiptExtractionWarningCode.zeroTotal =>
      'The total reads as zero. Check that against the paper receipt.',
    ReceiptExtractionWarningCode.dateInFuture =>
      'The date is in the future. Check it against the paper receipt.',
    ReceiptExtractionWarningCode.currencyInferredFromDefault =>
      'No currency was printed, so we assumed one. Check it.',
    ReceiptExtractionWarningCode.multipleTotalsFound =>
      'More than one total was printed. Check which one is right.',
    // A hint this build does not recognise. Rendered generically rather
    // than as its raw token.
    ReceiptExtractionWarningCode.unknown =>
      'Something on this receipt is worth a second look.',
  };

  // ---- Confirmation --------------------------------------------------------

  /// How a confirmation's values came to be. Server-derived, never computed
  /// here: the comparison rules live in SQL and are deliberately forgiving
  /// about casing and punctuation.
  static String entryModeLabel(ReceiptConfirmationEntryMode? mode) =>
      switch (mode) {
        ReceiptConfirmationEntryMode.manual => 'Typed in',
        ReceiptConfirmationEntryMode.extracted => 'As read from the receipt',
        ReceiptConfirmationEntryMode.mixed => 'Read, with your corrections',
        ReceiptConfirmationEntryMode.unknown || null => 'Recorded',
      };

  /// One corrected field, in words.
  static String changedFieldLabel(ReceiptConfirmationField field) =>
      switch (field) {
        ReceiptConfirmationField.currencyCode => 'Currency',
        ReceiptConfirmationField.documentNumber => 'Receipt number',
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
        ReceiptReviewField.transactionDate => 'Choose the date on the receipt.',
        ReceiptReviewField.currencyCode => 'Enter the currency.',
        ReceiptReviewField.total => 'Enter the total on the receipt.',
        _ => 'This is required.',
      },
      ReceiptReviewFieldProblem.invalidCurrency =>
        'Use the three-letter currency code, such as AED.',
      // Three letters, but not one this system accepts. It says what to do and
      // does not name a table, a list or how many currencies there are.
      ReceiptReviewFieldProblem.unsupportedCurrency =>
        'We cannot record receipts in that currency. Check the code on the '
            'receipt.',
      ReceiptReviewFieldProblem.notANumber =>
        'Enter the amount using digits and one decimal point.',
      ReceiptReviewFieldProblem.tooPrecise =>
        'That is more decimal places than this currency uses.',
      ReceiptReviewFieldProblem.outOfRange =>
        'That amount is outside the range we can record.',
      ReceiptReviewFieldProblem.tooLong => 'That is too long.',
      ReceiptReviewFieldProblem.dateTooEarly =>
        'That date is too far in the past to be a receipt date.',
    };
  }

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
        message: 'Sign in again to carry on reviewing this receipt.',
      ),
      // Deliberately says nothing about *why*, and never "that is not yours":
      // the backend answers an unknown receipt, somebody else's, and another
      // Retailer's identically, and splitting them here would recreate the
      // existence oracle SQL is careful to deny.
      ExtractionForbiddenProblem() ||
      ExtractionNotFoundProblem() => const ReceiptReviewNotice(
        tone: SrAlertTone.warning,
        title: 'This receipt is not available to you',
        message:
            'You can only review receipts you submitted yourself. Go back to '
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
        title: 'Still reading this receipt',
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
