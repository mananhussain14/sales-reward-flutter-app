import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/receipt_file.dart';
import '../../../domain/entities/receipt_submission.dart';
import 'receipt_formatting.dart';
import 'receipt_status_badge.dart';

/// One row in the submission history.
///
/// ## Not tappable, on purpose
///
/// There is no detail screen behind it, because there is nothing further to
/// show: the backend exposes **no** receipt-image retrieval path — no signed
/// URL, no download RPC, no storage policy — and every field the two read RPCs
/// return is already on this row. A tappable row that opened a screen repeating
/// itself would promise something the contract cannot deliver.
class ReceiptSubmissionTile extends StatelessWidget {
  const ReceiptSubmissionTile({super.key, required this.submission});

  final ReceiptSubmission submission;

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
              const SrIconDisc(
                icon: Icons.receipt_long_rounded,
                tone: SrTone.indigo,
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
