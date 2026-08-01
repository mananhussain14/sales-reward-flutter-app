import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/receipt_file.dart';
import '../../../domain/entities/receipt_submission.dart';
import 'receipt_formatting.dart';
import 'receipt_status_badge.dart';

/// The confirmation shown after `200 submitted`.
///
/// ## The status comes from the database, not from the HTTP code
///
/// A `200` proves the function accepted the receipt. What the row actually
/// *says* comes from `get_my_receipt_submission(<the returned id>)`, and that
/// read is what this card displays. Rendering "Submitted" because a request
/// returned 200 would be the client asserting a state it did not observe.
///
/// When the confirming read did not return the row, [submission] is null: the
/// submission is still a success — the function said so — and the card shows the
/// id and says the details could not be read back. It never downgrades a
/// success to a failure over a follow-up read.
///
/// ## No storage path, bucket, hash or image
///
/// None of those is returned by either RPC, so none of them exists here to
/// render.
///
/// ## Review is offered, never forced
///
/// [onReviewReceipt] opens the review screen for the id the function returned.
/// It is an offer and not a redirect: somebody who has just photographed one
/// receipt is usually about to photograph the next, and navigating them away
/// from the camera would be the wrong default. Submitting another receipt stays
/// the primary action.
class ReceiptSuccessCard extends StatelessWidget {
  const ReceiptSuccessCard({
    super.key,
    required this.submissionId,
    required this.submission,
    required this.onSubmitAnother,
    this.onReviewReceipt,
  });

  final String? submissionId;
  final ReceiptSubmission? submission;
  final VoidCallback onSubmitAnother;

  /// Opens the review screen for [submissionId]. Null when there is no id to
  /// open one with, which is the only case in which the action is absent.
  final VoidCallback? onReviewReceipt;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final ReceiptSubmission? row = submission;

    return SrCard(
      variant: SrCardVariant.highlighted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SrIconDisc(
                icon: Icons.check_circle_outline_rounded,
                tone: SrTone.emerald,
                size: 48,
              ),
              const SizedBox(width: SrSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Receipt submitted',
                      style: SrTypography.sectionTitle.copyWith(
                        color: sr.foreground,
                      ),
                    ),
                    const SizedBox(height: SrSpacing.xxs),
                    Text(
                      row == null
                          ? 'Your receipt was accepted. We could not read the '
                                'details back just now — it is on your '
                                'submissions list.'
                          : 'Your receipt for ${row.shopName} was received.',
                      style: SrTypography.body.copyWith(
                        color: sr.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: SrSpacing.xl),
          if (row != null) ...<Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: ReceiptStatusBadge(status: row.status),
            ),
            const SizedBox(height: SrSpacing.lg),
            _DetailRow(label: 'Shop', value: row.shopName),
            if (row.shopCode != null)
              _DetailRow(label: 'Shop code', value: row.shopCode!),
            _DetailRow(label: 'File', value: row.originalFileName),
            _DetailRow(
              label: 'Size',
              value: formatReceiptFileSize(row.fileSizeBytes),
            ),
            _DetailRow(label: 'Format', value: row.mimeType),
            _DetailRow(
              label: 'Received',
              value: formatReceiptTimestamp(row.displayedAt),
            ),
          ],
          if (submissionId != null)
            _DetailRow(
              label: 'Submission ID',
              value: submissionId!,
              monospaceish: true,
            ),
          const SizedBox(height: SrSpacing.xl),
          if (onReviewReceipt != null) ...<Widget>[
            Semantics(
              button: true,
              label: 'Review this receipt',
              child: SrButton(
                label: 'Review receipt',
                icon: Icons.fact_check_outlined,
                size: SrButtonSize.lg,
                fullWidth: true,
                onPressed: onReviewReceipt,
              ),
            ),
            const SizedBox(height: SrSpacing.md),
          ],
          SrButton(
            label: 'Submit another receipt',
            icon: Icons.add_a_photo_outlined,
            size: SrButtonSize.lg,
            fullWidth: true,
            variant: onReviewReceipt == null
                ? SrButtonVariant.primary
                : SrButtonVariant.outline,
            onPressed: onSubmitAnother,
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.monospaceish = false,
  });

  final String label;
  final String value;
  final bool monospaceish;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Padding(
      padding: const EdgeInsets.only(bottom: SrSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 116,
            child: Text(
              label,
              style: SrTypography.caption.copyWith(color: sr.textSecondary),
            ),
          ),
          const SizedBox(width: SrSpacing.sm),
          Expanded(
            child: Text(
              value,
              style: SrTypography.caption.copyWith(
                color: sr.textBody,
                fontFeatures: monospaceish
                    ? const <FontFeature>[FontFeature.tabularFigures()]
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
