import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../cubit/receipt_review_cubit.dart';
import 'receipt_review_copy.dart';

/// The last thing on the review screen: what is about to be written, and the
/// one control that writes it.
///
/// ## One confirmation action, and never two
///
/// The transaction header and the product proposal are a single immutable
/// assertion written by a single RPC, so there is exactly one control on this
/// screen that sends anything — this one. The transaction form above it has no
/// submit button of its own: two buttons would imply two writes, and a header
/// written on its own can never acquire products afterwards.
///
/// Once a write has started, the control is **gone** rather than greyed: every
/// state a started write can reach is terminal for this screen, so an affordance
/// that merely looked unavailable would be promising something that can never
/// happen. The only control offered afterwards is the status *read*.
///
/// ## Disabled is structural, not visual
///
/// Nothing here is dimmed and left tappable. A control that may not fire is
/// either absent or has a null callback, and its `Semantics` says `enabled:
/// false` — so a screen reader and a hardware keyboard reach the same answer
/// the eye does.
///
/// ## Nothing backend-shaped is rendered
///
/// Every sentence comes from [ReceiptReviewCopy] and is chosen by a
/// discriminant. No SQLSTATE, no Postgres message, no hint, no detail, no
/// function name, no confirmation id and no actor identity appears here —
/// including on the conflict branch, where the RPC deliberately returns no id
/// at all.
class ReceiptFinalConfirmationSection extends StatelessWidget {
  const ReceiptFinalConfirmationSection({
    super.key,
    required this.state,
    required this.lineCount,
    required this.totalQuantity,
    required this.onConfirm,
    required this.onCheckStatus,
  });

  final ReceiptReviewState state;

  /// How many product lines are about to be written. The order they are in is
  /// the order they will be numbered.
  final int lineCount;

  /// The sum of every quantity, for the final read-through.
  final int totalQuantity;

  final VoidCallback onConfirm;
  final VoidCallback onCheckStatus;

  ReceiptProductSubmission get _submission => state.productSubmission;

  @override
  Widget build(BuildContext context) {
    final ReceiptReviewNotice? notice =
        ReceiptReviewCopy.productSubmissionNotice(_submission);

    return SrSectionCard(
      title: 'Confirm this receipt',
      description:
          'The receipt details and the products are recorded together, in one '
          'step. Once recorded, neither can be changed.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Summary(
            lineCount: lineCount,
            totalQuantity: totalQuantity,
            settled: _submission.isSettled,
          ),
          if (notice != null) ...<Widget>[
            const SizedBox(height: SrSpacing.md),
            // A live region, so the pending, slow and outcome states are spoken
            // as they arrive rather than only found by somebody who goes
            // looking for them.
            Semantics(
              liveRegion: true,
              container: true,
              child: SrAlert(
                tone: notice.tone,
                title: notice.title,
                message: notice.message,
              ),
            ),
          ],
          const SizedBox(height: SrSpacing.lg),
          ..._actions(context),
        ],
      ),
    );
  }

  List<Widget> _actions(BuildContext context) {
    if (_submission.isSettled) {
      // Terminal. No second confirmation control of any kind: the proposal is
      // immutable and a button that could only ever answer `ALREADY_CONFIRMED`
      // is an invitation to press it and find out.
      return <Widget>[
        Text(
          'Nothing further is needed for this receipt.',
          textAlign: TextAlign.center,
          style: SrTypography.caption.copyWith(color: context.sr.textSecondary),
        ),
      ];
    }

    if (_submission.needsStatusCheck) {
      // A READ, and the only affordance offered here. There is no resend, no
      // "try again" and no automatic anything: the write may have committed,
      // and the one safe next step is to look.
      return <Widget>[
        Semantics(
          button: true,
          enabled: _submission.canCheckStatus,
          label: 'Check what is stored for this receipt',
          child: SrButton(
            label: ReceiptReviewCopy.statusCheckAction,
            icon: Icons.search_rounded,
            variant: SrButtonVariant.outline,
            size: SrButtonSize.lg,
            fullWidth: true,
            loading: _submission.isCheckingStatus,
            loadingLabel: 'Checking…',
            // Null while a check is already reading — the visible half of a
            // guard the cubit enforces regardless, and one that is deliberately
            // separate from the write's.
            onPressed: _submission.canCheckStatus ? onCheckStatus : null,
          ),
        ),
        const SizedBox(height: SrSpacing.sm),
        Text(
          'This only looks at what is stored. It does not send anything again.',
          textAlign: TextAlign.center,
          style: SrTypography.caption.copyWith(color: context.sr.textSecondary),
        ),
      ];
    }

    final bool enabled = state.canSubmitProposal && lineCount > 0;

    return <Widget>[
      Semantics(
        button: true,
        enabled: enabled,
        label: 'Confirm this receipt',
        child: SrButton(
          label: ReceiptReviewCopy.confirmAction,
          icon: Icons.check_rounded,
          size: SrButtonSize.lg,
          fullWidth: true,
          loading: _submission.isPending,
          loadingLabel: ReceiptReviewCopy.confirmPending,
          onPressed: enabled ? onConfirm : null,
        ),
      ),
      const SizedBox(height: SrSpacing.sm),
      Text(
        lineCount == 0
            ? 'Choose at least one product to confirm this receipt.'
            : 'Once confirmed, these details and these products cannot be '
                  'changed.',
        textAlign: TextAlign.center,
        style: SrTypography.caption.copyWith(color: context.sr.textSecondary),
      ),
    ];
  }
}

/// The last read-through: how many lines, and how many items in total.
class _Summary extends StatelessWidget {
  const _Summary({
    required this.lineCount,
    required this.totalQuantity,
    required this.settled,
  });

  final int lineCount;
  final int totalQuantity;
  final bool settled;

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
      // One label for the pair, so a screen reader says a sentence rather than
      // two orphaned numbers.
      child: Semantics(
        label: settled
            ? 'Recorded: $lines, $items in total'
            : 'About to confirm: $lines, $items in total',
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
