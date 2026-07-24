import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/receipt_rejection_reason.dart';
import '../cubit/receipt_submission_cubit.dart';

/// One piece of user-facing feedback: a tone, a headline and a sentence.
final class ReceiptNotice {
  const ReceiptNotice({
    required this.tone,
    required this.title,
    required this.message,
  });

  final SrAlertTone tone;
  final String title;
  final String message;
}

/// Every sentence this feature can show, in one place.
///
/// ## Nothing here is derived from a backend string
///
/// The copy is selected by a **discriminant** — a phase, or a rejection reason
/// from a fixed vocabulary. No Postgres message, Edge Function error, storage
/// path, bucket name, request id or stack trace is ever interpolated, because
/// none of them reaches this layer to be interpolated.
///
/// ## An outage never reads as a denial
///
/// [ReceiptSubmissionPhase.retryable] and
/// [ReceiptSubmissionPhase.unconfirmed] say nothing about permission, and
/// [ReceiptSubmissionPhase.denied] offers no retry. Telling someone they lack
/// access when the network merely failed is both wrong and alarming; telling
/// them to retry something that can only be refused wastes their time.
abstract final class ReceiptCopy {
  /// The notice for a settled phase, or null while nothing needs saying.
  static ReceiptNotice? noticeFor(ReceiptSubmissionState state) {
    return switch (state.phase) {
      ReceiptSubmissionPhase.duplicate => const ReceiptNotice(
        tone: SrAlertTone.warning,
        title: 'You already submitted this receipt',
        message:
            'This exact image is already on your submissions list. Choose a '
            'different receipt to submit.',
      ),

      ReceiptSubmissionPhase.denied => const ReceiptNotice(
        tone: SrAlertTone.warning,
        title: 'That shop is not available to you',
        // Deliberately one sentence for four different backend situations —
        // unassigned, inactive, another Retailer's, and nonexistent all return
        // one identical answer, and splitting them here would recreate the
        // existence oracle SQL is careful to deny.
        message:
            'You can only submit a receipt for a shop you are currently '
            'assigned to. Pick another shop, or ask your manager to check your '
            'assignments.',
      ),

      ReceiptSubmissionPhase.unauthenticated => const ReceiptNotice(
        tone: SrAlertTone.error,
        title: 'Your session has ended',
        message: 'Sign in again to submit this receipt.',
      ),

      ReceiptSubmissionPhase.rejected => ReceiptNotice(
        tone: SrAlertTone.error,
        title: 'This receipt was not accepted',
        message: rejectionMessage(state.rejection),
      ),

      ReceiptSubmissionPhase.retryable => const ReceiptNotice(
        tone: SrAlertTone.error,
        title: 'Upload failed',
        message:
            'The receipt did not finish uploading. Nothing was saved, so you '
            'can send the same photo again.',
      ),

      ReceiptSubmissionPhase.unconfirmed => const ReceiptNotice(
        tone: SrAlertTone.warning,
        title: 'We could not confirm this submission',
        // The one case where "try again" is not the first instruction. The
        // receipt may already be stored, and an automatic resend could create a
        // second submission of a receipt that already landed.
        message:
            'The connection dropped before we heard back, so this receipt may '
            'or may not have been saved. Check your recent submissions below '
            'before sending it again.',
      ),

      ReceiptSubmissionPhase.initialLoading ||
      ReceiptSubmissionPhase.loadFailed ||
      ReceiptSubmissionPhase.ready ||
      ReceiptSubmissionPhase.fileSelected ||
      ReceiptSubmissionPhase.validating ||
      ReceiptSubmissionPhase.submitting ||
      ReceiptSubmissionPhase.success => null,
    };
  }

  /// Why a file or a shop id was refused.
  static String rejectionMessage(ReceiptRejectionReason? reason) {
    return switch (reason) {
      ReceiptRejectionReason.tooLarge =>
        'That image is larger than 10 MB. Take the photo again at a lower '
            'resolution, or choose a smaller file.',
      ReceiptRejectionReason.unsupportedType =>
        'Receipts must be a JPEG, PNG or WebP image. A file can carry the '
            'wrong extension, so this is checked against the image itself.',
      ReceiptRejectionReason.empty =>
        'That file is empty. Choose or take the photo again.',
      ReceiptRejectionReason.missing =>
        'No image was attached. Choose or take a photo of the receipt.',
      ReceiptRejectionReason.invalidName =>
        'That file name cannot be used. Rename the file and try again.',
      ReceiptRejectionReason.tooManyFiles =>
        'Only one image can be submitted at a time.',
      ReceiptRejectionReason.invalidShop =>
        'Choose one of your assigned shops before submitting.',
      ReceiptRejectionReason.malformedBody ||
      ReceiptRejectionReason.rejected ||
      ReceiptRejectionReason.unknown ||
      null => 'The receipt was not accepted. Choose or take the photo again.',
    };
  }

  /// The one-line description under the page title.
  static const String submitPageDescription =
      'Photograph a receipt, choose the shop it belongs to, and send it in.';

  /// The reference-section caption. It states plainly that nothing here is
  /// attached to the submission, so the section cannot be mistaken for a
  /// selection the backend receives.
  static const String productsReferenceDescription =
      'The products your Retailer currently stocks, for reference while you '
      'check a receipt. Products are not attached to a submission.';
}
