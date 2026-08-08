import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../cubit/receipt_review_cubit.dart';
import 'receipt_review_copy.dart';

/// The attempt: where it has reached, what it cost, and what may be done next.
///
/// ## Counters are facts; availability is one boolean
///
/// `attempts_used` and `attempts_remaining` describe persisted rows and nothing
/// else. The retry control is bound to `retry_allowed` alone — an app that
/// offered a retry because `attemptsRemaining > 0` would offer it while the
/// provider was switched off, and every tap would fail.
class ReceiptReviewStatusPanel extends StatelessWidget {
  const ReceiptReviewStatusPanel({
    super.key,
    required this.state,
    required this.onRetry,
    required this.onCheckAgain,
  });

  final ReceiptReviewState state;
  final VoidCallback onRetry;
  final VoidCallback onCheckAgain;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final String? description = ReceiptReviewCopy.statusDescription(state);
    final bool working =
        state.phase == ReceiptReviewPhase.requesting ||
        state.isAwaitingExtraction;

    return SrCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  'Reading status',
                  style: SrTypography.cardTitle.copyWith(color: sr.foreground),
                ),
              ),
              const SizedBox(width: SrSpacing.sm),
              SrBadge(
                label: ReceiptReviewCopy.statusLabel(state.phase),
                tone: ReceiptReviewCopy.statusTone(state.phase),
              ),
            ],
          ),
          if (description != null) ...<Widget>[
            const SizedBox(height: SrSpacing.sm),
            Text(
              description,
              style: SrTypography.body.copyWith(color: sr.textSecondary),
            ),
          ],
          if (working) ...<Widget>[
            const SizedBox(height: SrSpacing.lg),
            LinearProgressIndicator(
              minHeight: 4,
              backgroundColor: sr.surfaceMuted,
              color: sr.brand,
            ),
          ],
          const SizedBox(height: SrSpacing.lg),
          _Attempts(state: state),
          if (state.canRetry || state.pollBudgetSpent) ...<Widget>[
            const SizedBox(height: SrSpacing.lg),
            Wrap(
              spacing: SrSpacing.sm,
              runSpacing: SrSpacing.sm,
              children: <Widget>[
                // Shown only when the backend said another attempt is possible.
                if (state.canRetry)
                  Semantics(
                    button: true,
                    label: 'Try reading this invoice / receipt again',
                    child: SrButton(
                      label: 'Try reading again',
                      icon: Icons.restart_alt_rounded,
                      variant: SrButtonVariant.outline,
                      loading: state.phase == ReceiptReviewPhase.requesting,
                      loadingLabel: 'Asking…',
                      onPressed: state.isBusy ? null : onRetry,
                    ),
                  ),
                // A read, so offering it as a retry is safe. It never consumes
                // an attempt.
                if (state.pollBudgetSpent)
                  Semantics(
                    button: true,
                    label: 'Check the reading status again',
                    child: SrButton(
                      label: 'Check again',
                      icon: Icons.refresh_rounded,
                      variant: SrButtonVariant.ghost,
                      onPressed: state.isBusy ? null : onCheckAgain,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Attempts extends StatelessWidget {
  const _Attempts({required this.state});

  final ReceiptReviewState state;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Semantics(
      label:
          'Reading attempts used ${state.attemptsUsed}, '
          '${state.attemptsRemaining} remaining',
      child: ExcludeSemantics(
        child: Row(
          children: <Widget>[
            Icon(Icons.repeat_rounded, size: 16, color: sr.textMuted),
            const SizedBox(width: SrSpacing.xs),
            Text(
              'Attempt ${state.attemptsUsed} of '
              '${state.attemptsUsed + state.attemptsRemaining}',
              style: SrTypography.caption.copyWith(color: sr.textSecondary),
            ),
            const SizedBox(width: SrSpacing.md),
            Text(
              state.attemptsRemaining == 0
                  ? 'none left'
                  : '${state.attemptsRemaining} left',
              style: SrTypography.caption.copyWith(color: sr.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
