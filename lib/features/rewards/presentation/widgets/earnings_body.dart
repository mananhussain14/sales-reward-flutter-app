import 'package:flutter/material.dart';

import '../../../../core/design/design.dart';
import '../../../../core/errors/retailer_read_problem.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/campaign_reward_record.dart';
import '../bloc/campaign_earnings_cubit.dart';
import 'campaign_reward_card.dart';
import 'earnings_copy.dart';
import 'earnings_summary_view.dart';

/// The earnings screen's content: the totals, then the history.
///
/// ## Four independent regions, and none can blank another
///
/// The summary, the history, the pagination attempt and the end-of-list note are
/// driven by four separate fields on [SalesStaffEarningsState]. A failed summary
/// leaves every reward on screen; a failed page leaves the totals *and* the
/// rewards exactly where they were; and an authorization refusal on the summary
/// does not claim the history is empty.
///
/// ## No database detail ever reaches this widget
///
/// Every failure arrives as a [RetailerReadProblem] — a discriminant, never a
/// message. `SrRetailerProblemView` turns it into the application's own copy, so
/// a `PostgrestException` message, a SQLSTATE, an RPC name, a table name, a
/// stack trace and an internal id are all structurally unable to be rendered.
class EarningsBody extends StatelessWidget {
  const EarningsBody({
    super.key,
    required this.state,
    required this.onRetry,
    required this.onLoadOlder,
  });

  final SalesStaffEarningsState state;

  /// Re-issues both reads.
  final VoidCallback onRetry;

  /// Fetches the page before the oldest reward on screen.
  final VoidCallback onLoadOlder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SummaryRegion(state: state, onRetry: onRetry),
        const SizedBox(height: SrSpacing.xxl),
        SrSectionHeader(title: EarningsCopy.historySectionTitle),
        const SizedBox(height: SrSpacing.lg),
        _HistoryRegion(
          state: state,
          onRetry: onRetry,
          onLoadOlder: onLoadOlder,
        ),
      ],
    );
  }
}

/// The totals, or the reason they are not there.
class _SummaryRegion extends StatelessWidget {
  const _SummaryRegion({required this.state, required this.onRetry});

  final SalesStaffEarningsState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    // Zero rows from the contract: the caller is not an authorized earnings
    // reader. Rendered as the shared refusal rather than as a summary of zeros,
    // which would tell somebody they had earned nothing when the truth is that
    // this surface is not theirs.
    if (state.summaryUnavailable) {
      return const SrRetailerProblemView(problem: RetailerReadProblem.denied);
    }

    final RetailerReadProblem? problem = state.summaryProblem;
    if (problem != null && state.summary == null) {
      // The totals failed. Said as a banner rather than as the whole screen, so
      // the reward history below — which may have loaded perfectly — is not
      // thrown away with them.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SrAlert(
            tone: SrAlertTone.warning,
            title: EarningsCopy.summaryFailedTitle,
            message: EarningsCopy.summaryFailedBody,
          ),
          const SizedBox(height: SrSpacing.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: SrButton(
              label: EarningsCopy.refresh,
              variant: SrButtonVariant.outline,
              icon: Icons.refresh_rounded,
              onPressed: onRetry,
            ),
          ),
        ],
      );
    }

    final summary = state.summary;
    if (summary == null) {
      return const SizedBox.shrink();
    }
    return EarningsSummaryView(summary: summary);
  }
}

/// The reward history, its empty state, and the pagination control.
class _HistoryRegion extends StatelessWidget {
  const _HistoryRegion({
    required this.state,
    required this.onRetry,
    required this.onLoadOlder,
  });

  final SalesStaffEarningsState state;
  final VoidCallback onRetry;
  final VoidCallback onLoadOlder;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    // Nothing loaded and the read failed. An unreadable answer must never be
    // shown as "you have not earned any rewards": they are opposite claims.
    if (state.historyFailedOutright) {
      return SrRetailerProblemView(
        problem: state.rewardsProblem!,
        onRetry: onRetry,
      );
    }

    final List<CampaignRewardRecord>? rewards = state.rewards;
    if (rewards == null) {
      return const SizedBox.shrink();
    }

    if (rewards.isEmpty) {
      return const SrEmptyState(
        icon: Icons.emoji_events_outlined,
        tone: SrTone.slate,
        title: EarningsCopy.historyEmptyTitle,
        description: EarningsCopy.historyEmptyBody,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < rewards.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: SrSpacing.lg),
          CampaignRewardCard(reward: rewards[i]),
        ],

        // -- The pagination attempt's own failure --------------------------
        //
        // Below the rewards, because everything above it is still valid. The
        // button stays available: the page that failed can be retried.
        if (state.olderProblem != null) ...<Widget>[
          const SizedBox(height: SrSpacing.lg),
          const SrAlert(
            tone: SrAlertTone.warning,
            title: EarningsCopy.olderFailedTitle,
            message: EarningsCopy.olderFailedBody,
          ),
        ],

        // -- Keyset pagination, on an explicit press ------------------------
        //
        // Never on scroll. The button is disabled while a page is in flight,
        // and the cubit refuses a second request regardless — a guard that
        // depends on a widget being rebuilt is not a guard.
        if (state.canLoadOlder) ...<Widget>[
          const SizedBox(height: SrSpacing.xl),
          Semantics(
            button: true,
            label: EarningsCopy.loadOlder,
            child: SrButton(
              label: EarningsCopy.loadOlder,
              variant: SrButtonVariant.outline,
              icon: Icons.history_rounded,
              loading: state.isLoadingOlder,
              loadingLabel: EarningsCopy.loadingOlder,
              onPressed: state.isLoadingOlder ? null : onLoadOlder,
            ),
          ),
        ] else if (state.reachedEndOfHistory) ...<Widget>[
          // The last page came back short. The control is GONE rather than
          // disabled: there is nothing behind it to press for.
          const SizedBox(height: SrSpacing.xl),
          Text(
            EarningsCopy.historyEnd,
            style: SrTypography.caption.copyWith(color: sr.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
