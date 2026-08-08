import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/receipt_file.dart';
import '../../../domain/entities/receipt_submission.dart';
import 'receipt_formatting.dart';
import 'receipt_status_badge.dart';

/// One row in the submission history.
///
/// ## Review is offered only for a receipt that can actually be reviewed
///
/// [onOpenReview] is supplied only for a `SUBMITTED` row. A `RESERVED` or
/// `UPLOAD_FAILED` receipt has no stored object behind it, so every one of the
/// review screen's calls would refuse — and the refusal is deliberately
/// indistinguishable from "that is not yours", which would be an alarming thing
/// to show somebody about their own receipt. Not offering the action is the
/// honest answer.
///
/// The row itself is still not tappable: the affordance is an explicit control
/// with its own label, so a person scrolling a long list cannot open a screen by
/// brushing it.
class ReceiptSubmissionTile extends StatelessWidget {
  const ReceiptSubmissionTile({
    super.key,
    required this.submission,
    this.onOpenReview,
  });

  final ReceiptSubmission submission;

  /// Opens the review screen for this receipt, when it has one.
  final VoidCallback? onOpenReview;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return SrCard(
      padding: const EdgeInsets.all(SrSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Tinted by the row's own status, from the badge's single
              // definition — so the left and the right of the row always agree
              // about what state this receipt is in.
              SrIconDisc(
                icon: Icons.receipt_long_rounded,
                tone: ReceiptStatusBadge.toneFor(submission.status),
                size: 40,
              ),
              const SizedBox(width: SrSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      submission.shopName,
                      style: SrTypography.label.copyWith(color: sr.foreground),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: SrSpacing.xxs),
                    Text(
                      formatReceiptMoment(submission),
                      style: SrTypography.caption.copyWith(
                        color: sr.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: SrSpacing.sm),
              ReceiptStatusBadge(status: submission.status),
            ],
          ),
          const SizedBox(height: SrSpacing.md),
          Wrap(
            spacing: SrSpacing.md,
            runSpacing: SrSpacing.xs,
            children: <Widget>[
              _Fact(
                icon: Icons.description_outlined,
                label: submission.originalFileName,
              ),
              _Fact(
                icon: Icons.data_usage_rounded,
                label: formatReceiptFileSize(submission.fileSizeBytes),
              ),
              if (submission.shopCode != null)
                _Fact(
                  icon: Icons.storefront_outlined,
                  label: submission.shopCode!,
                ),
            ],
          ),
          if (onOpenReview != null) ...<Widget>[
            const SizedBox(height: SrSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                button: true,
                label:
                    'Review the invoice / receipt from ${submission.shopName}',
                child: SrButton(
                  label: 'Review invoice / receipt',
                  variant: SrButtonVariant.outline,
                  size: SrButtonSize.sm,
                  icon: Icons.fact_check_outlined,
                  onPressed: onOpenReview,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return ConstrainedBox(
      // Bounded so a long filename wraps into the Wrap rather than overflowing
      // a narrow phone.
      constraints: const BoxConstraints(maxWidth: 260),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: sr.textMuted),
          const SizedBox(width: SrSpacing.xs),
          Flexible(
            child: Text(
              label,
              style: SrTypography.caption.copyWith(color: sr.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
