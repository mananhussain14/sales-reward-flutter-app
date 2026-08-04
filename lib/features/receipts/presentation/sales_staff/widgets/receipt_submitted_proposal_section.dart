import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/receipt_product_proposal_line.dart';
import '../cubit/receipt_review_cubit.dart';
import 'receipt_review_copy.dart';

/// The product proposal exactly as the database holds it. Read-only, forever.
///
/// ## Every value here is a frozen snapshot
///
/// The name, code, barcode, brand and status are `*_at_proposal` columns the
/// database copied out of `vendor_products` at the moment the proposal was
/// written. Nothing on this screen looks the current catalogue up, and there is
/// no code path here that could: the widget receives
/// [ReceiptProductProposalLine] values and has no repository, no cubit and no
/// product list. A rename, a rebrand, a new barcode or a deactivation after the
/// fact changes none of it — which is the point, because this is the assertion
/// a Claim Reviewer will judge, not a description of today's catalogue.
///
/// ## There is nothing to press
///
/// No edit, remove, increment, decrement, search, add, resubmit, correct,
/// replace or reopen control exists in this file. That is not enforced by a
/// disabled flag somebody could flip — the widgets simply are not here, so
/// there is nothing for a stray callback or a stale frame to reach. A
/// corrected proposal does not exist in Phase 1D-B, and an affordance offering
/// one could only ever fail.
///
/// ## The status is a word
///
/// "Submitted" is written out, with an icon beside it. Colour reinforces it and
/// never carries it alone.
class ReceiptSubmittedProposalSection extends StatelessWidget {
  const ReceiptSubmittedProposalSection({
    super.key,
    required this.proposal,
    required this.onReload,
  });

  /// The stored proposal, and where its read has reached.
  final ReceiptStoredProposal proposal;

  /// Re-reads the stored lines after an explicit tap. A **read**: there is no
  /// write anywhere behind this callback.
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    return SrSectionCard(
      title: ReceiptReviewCopy.submittedTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[_body(context)],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (proposal.isLoading) {
      // Bounded, and announced. The confirmed transaction details above stay on
      // screen throughout: a person must not watch their receipt disappear
      // while a read is in flight.
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: SrSpacing.lg),
        child: SrLoadingView(label: ReceiptReviewCopy.submittedLoading),
      );
    }

    if (proposal.isUnreadable) {
      // NOT "there is no proposal". The confirmation is authoritative and stays
      // so; only the lines are missing from this screen, and the one thing
      // offered is another read.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            liveRegion: true,
            container: true,
            child: const SrAlert(
              tone: SrAlertTone.warning,
              title: 'Submitted, but we could not load the lines',
              message: ReceiptReviewCopy.submittedUnreadable,
            ),
          ),
          const SizedBox(height: SrSpacing.lg),
          Semantics(
            button: true,
            label: 'Check what is stored for this receipt',
            child: SrButton(
              label: ReceiptReviewCopy.statusCheckAction,
              icon: Icons.search_rounded,
              variant: SrButtonVariant.outline,
              size: SrButtonSize.lg,
              fullWidth: true,
              onPressed: onReload,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _SubmittedHeader(),
        const SizedBox(height: SrSpacing.md),
        _Summary(
          lineCount: proposal.lineCount,
          totalQuantity: proposal.totalQuantity,
        ),
        const SizedBox(height: SrSpacing.md),
        // The database's own `line_number` order. Nothing here sorts, filters
        // or renumbers: the order IS the proposal.
        for (final ReceiptProductProposalLine line in proposal.lines)
          _ProposalLine(line: line),
        const SizedBox(height: SrSpacing.md),
        const _Explanations(),
      ],
    );
  }
}

/// "Submitted", as a word and an icon.
class _SubmittedHeader extends StatelessWidget {
  const _SubmittedHeader();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      liveRegion: true,
      label:
          '${ReceiptReviewCopy.submittedStatusBadge}. '
          '${ReceiptReviewCopy.submittedFinality}',
      child: Align(
        alignment: Alignment.centerLeft,
        child: SrBadge(
          label: ReceiptReviewCopy.submittedStatusBadge,
          tone: SrTone.emerald,
          icon: Icons.lock_outline_rounded,
        ),
      ),
    );
  }
}

/// How many lines, and how many items. Counted from the stored rows.
class _Summary extends StatelessWidget {
  const _Summary({required this.lineCount, required this.totalQuantity});

  final int lineCount;
  final int totalQuantity;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final String lines = '$lineCount product line${lineCount == 1 ? '' : 's'}';
    final String items = '$totalQuantity item${totalQuantity == 1 ? '' : 's'}';

    return Container(
      padding: const EdgeInsets.all(SrSpacing.md),
      decoration: BoxDecoration(
        color: sr.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Semantics(
        label: 'Submitted: $lines, $items in total',
        excludeSemantics: true,
        // Wraps rather than overflows: on a narrow phone the two facts stack.
        child: Wrap(
          spacing: SrSpacing.md,
          runSpacing: SrSpacing.xs,
          children: <Widget>[
            Text(
              lines,
              style: SrTypography.label.copyWith(color: sr.textBody),
              softWrap: true,
            ),
            Text(
              '$items in total',
              style: SrTypography.label.copyWith(color: sr.textSecondary),
              softWrap: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// One stored line, entirely from frozen proposal-time values.
class _ProposalLine extends StatelessWidget {
  const _ProposalLine({required this.line});

  final ReceiptProductProposalLine line;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    // Only what the RPC actually returned. There is no current-catalogue value
    // available here to fall back to, and none is wanted.
    final String details = <String?>[
      line.productCode,
      line.brand,
      line.barcode,
    ].whereType<String>().join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: SrSpacing.sm),
      padding: const EdgeInsets.all(SrSpacing.sm),
      decoration: BoxDecoration(
        border: Border.all(color: sr.border),
        borderRadius: BorderRadius.circular(12),
      ),
      // One label for the whole line, so a screen reader says a sentence rather
      // than reading a bare number with no subject.
      child: Semantics(
        label:
            'Line ${line.lineNumber}. ${line.productName}. '
            'Quantity ${line.quantity}.',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${line.lineNumber}.',
                  style: SrTypography.label.copyWith(color: sr.textSecondary),
                ),
                const SizedBox(width: SrSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        line.productName,
                        style: SrTypography.label.copyWith(color: sr.textBody),
                        softWrap: true,
                      ),
                      if (details.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          details,
                          style: SrTypography.caption.copyWith(
                            color: sr.textSecondary,
                          ),
                          softWrap: true,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: SrSpacing.sm),
                // The quantity, as a plain frozen number. No stepper, because
                // there is nothing to step.
                Text(
                  '× ${line.quantity}',
                  style: SrTypography.label.copyWith(color: sr.textBody),
                ),
              ],
            ),
            const SizedBox(height: SrSpacing.xs),
            // The status the product had AT PROPOSAL TIME, labelled as such.
            // The RPC returns no current status and this screen asks for none:
            // showing today's would rewrite what was proposed.
            Text(
              'Status when submitted: ${line.productStatus}',
              style: SrTypography.caption.copyWith(color: sr.textMuted),
              softWrap: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// The four facts a staff member must leave this screen with.
class _Explanations extends StatelessWidget {
  const _Explanations();

  @override
  Widget build(BuildContext context) {
    return const SrAlert(
      tone: SrAlertTone.info,
      title: 'What happens next',
      message:
          '${ReceiptReviewCopy.submittedFinality}\n\n'
          '${ReceiptReviewCopy.submittedWholeListReview}\n\n'
          '${ReceiptReviewCopy.submittedReceiptSeparate}\n\n'
          '${ReceiptReviewCopy.submittedNoRewards}',
    );
  }
}
