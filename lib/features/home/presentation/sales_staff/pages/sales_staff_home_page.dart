import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/shells/sales_staff/sales_staff_navigation.dart';
import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../../auth/presentation/bloc/session_bloc.dart';
import '../../../../campaigns/presentation/shared/campaign_card.dart';
import '../../../../campaigns/presentation/shared/campaign_list_cubit.dart';
import '../../../../campaigns/presentation/shared/campaign_presentation.dart';
import '../../../../receipts/domain/entities/receipt_submission.dart';
import '../../../../receipts/presentation/sales_staff/cubit/receipt_history_cubit.dart';
import '../../../../receipts/presentation/sales_staff/widgets/receipt_submission_tile.dart';
import '../../../../rewards/domain/entities/campaign_target_progress.dart';
import '../../../../rewards/presentation/bloc/campaign_earnings_cubit.dart';
import '../../../../rewards/presentation/bloc/campaign_target_progress_cubit.dart';
import '../../../../rewards/presentation/widgets/campaign_target_progress_view.dart';
import '../widgets/sales_staff_add_receipt_cta.dart';
import '../widgets/sales_staff_coins_panel.dart';
import '../widgets/sales_staff_home_copy.dart';
import '../widgets/sales_staff_welcome_header.dart';

/// The Sales Staff landing screen.
///
/// ## It composes reads; it does not make one
///
/// Every figure here comes from a contract that already had a screen —
/// `get_my_campaign_earnings_summary()`, `list_my_staff_campaigns()`,
/// `get_my_campaign_target_progress()` and `list_my_receipt_submissions()` —
/// through the cubits the shell already provides. There is no home RPC, no
/// dashboard aggregate and no client-side roll-up: nothing on this screen is
/// summed, ranked, averaged, projected or compared against a previous period,
/// because no contract returns the inputs for any of that.
///
/// ## The first read belongs to this screen, and now the shell lands on it
///
/// The campaign, progress and earnings cubits are created by the shell and
/// deliberately not loaded there. This screen calls `loadOnce` on all three
/// from `initState`, which is what makes entering the shell issue exactly one
/// read of each — and, because this is the landing route, why those reads now
/// happen on arrival rather than when a tab is opened. Opening the Campaigns or
/// Earnings tab afterwards reads nothing: `loadOnce` is a no-op once the phase
/// has left `initial`.
///
/// ## Four independent regions, and none can blank another
///
/// The coins panel, the campaign section and the recent receipts are driven by
/// three separate cubits over three separate contracts on two separate
/// permissions. A failed earnings read leaves the campaigns on screen; a failed
/// campaign read leaves the coins; and neither is ever rendered as an empty
/// state, because "could not read" and "you have none" are opposite claims.
///
/// ## No action other than navigation
///
/// The only interactive elements are the call to action, three links and the
/// campaign cards. There is no claim, redeem, withdraw, payout or dispute
/// control, and none disabled: no such contract exists in the deployed schema.
class SalesStaffHomePage extends StatefulWidget {
  const SalesStaffHomePage({super.key});

  @override
  State<SalesStaffHomePage> createState() => _SalesStaffHomePageState();
}

class _SalesStaffHomePageState extends State<SalesStaffHomePage> {
  /// How many campaigns the home shows before deferring to the full list.
  ///
  /// Three, and the count is stated on screen when it truncates. A landing
  /// screen that silently showed the first three of twenty would read as the
  /// whole list.
  static const int _maxCampaigns = 3;

  @override
  void initState() {
    super.initState();
    // Deferred to after the first frame so the reads cannot emit into a widget
    // tree that is still building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.read<SalesStaffCampaignListCubit>().loadOnce();
      context.read<SalesStaffCampaignProgressCubit>().loadOnce();
      context.read<SalesStaffEarningsCubit>().loadOnce();
    });
  }

  /// Re-issues every read behind the screen.
  ///
  /// Awaited together rather than in sequence: they are independent contracts
  /// and one round trip of latency is enough for a screen that shows all of
  /// them. Neither can fail the other — each cubit holds its own problem — so
  /// there is no error handling here to write.
  Future<void> _refresh() async {
    await Future.wait<void>(<Future<void>>[
      context.read<SalesStaffCampaignListCubit>().refresh(),
      context.read<SalesStaffCampaignProgressCubit>().refresh(),
      context.read<SalesStaffEarningsCubit>().refresh(),
      context.read<ReceiptHistoryCubit>().refresh(),
    ]);
  }

  void _openSubmit() => context.go(SalesStaffNavigation.submit);

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    // At and above this width the shell has already promoted its bottom bar to
    // a navigation rail, so there is no bottom chrome for a pinned bar to sit
    // above and the action belongs in the header.
    final bool wide = width >= SrSpacing.breakpointSm;

    final String? organizationName = switch (context
        .watch<SessionBloc>()
        .state) {
      SessionActive(:final portalContext) => portalContext.organizationName,
      _ => null,
    };

    return BlocBuilder<SalesStaffCampaignListCubit, CampaignListState>(
      builder: (BuildContext context, CampaignListState campaigns) {
        return BlocBuilder<
          SalesStaffCampaignProgressCubit,
          CampaignTargetProgressState
        >(
          builder: (BuildContext context, CampaignTargetProgressState progress) {
            return BlocBuilder<
              SalesStaffEarningsCubit,
              SalesStaffEarningsState
            >(
              builder: (BuildContext context, SalesStaffEarningsState earnings) {
                final List<CampaignPresentation> highlighted = _highlight(
                  campaigns,
                );

                return Stack(
                  children: <Widget>[
                    RefreshIndicator(
                      onRefresh: _refresh,
                      child: SrPageBody(
                        // Always scrollable, so pull-to-refresh works on a
                        // short screen rather than only when it overflows.
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: <Widget>[
                          SrEnter(
                            child: SalesStaffWelcomeHeader(
                              organizationName: organizationName,
                              hasCampaigns: highlighted.isNotEmpty,
                              action: wide
                                  ? SalesStaffAddReceiptButton(
                                      onPressed: _openSubmit,
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(height: SrSpacing.xxl),

                          SrEnter(
                            index: 1,
                            child: SalesStaffCoinsPanel(
                              summary: earnings.summary,
                              unavailable:
                                  earnings.summaryUnavailable ||
                                  earnings.summaryProblem != null,
                              onViewEarnings: () =>
                                  context.go(SalesStaffNavigation.earnings),
                            ),
                          ),
                          const SizedBox(height: SrSpacing.xxl),

                          SrEnter(
                            index: 2,
                            child: _Opportunities(
                              state: campaigns,
                              highlighted: highlighted,
                              progressFor: progress.forCampaign,
                              maxCampaigns: _maxCampaigns,
                            ),
                          ),
                          const SizedBox(height: SrSpacing.xxl),

                          const SrEnter(index: 3, child: _RecentReceipts()),

                          // Room for the pinned bar, so the last card is never
                          // trapped behind it.
                          if (!wide)
                            const SizedBox(
                              height: SalesStaffAddReceiptBar.reservedHeight,
                            ),
                        ],
                      ),
                    ),
                    if (!wide)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: SalesStaffAddReceiptBar(onPressed: _openSubmit),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  /// The campaigns worth putting on a landing screen, in the backend's order.
  ///
  /// **Running now first, and only if there are none, starting soon.** No
  /// scoring, no recommendation and no re-sorting: `list_my_staff_campaigns()`
  /// returns soonest-first and that order is preserved exactly, because a
  /// "recommended for you" ranking would be a claim this application has no
  /// contract to support.
  List<CampaignPresentation> _highlight(CampaignListState state) {
    final List<CampaignSection> sections = state.sections;
    for (final CampaignSectionKind kind in <CampaignSectionKind>[
      CampaignSectionKind.runningNow,
      CampaignSectionKind.startingSoon,
    ]) {
      for (final CampaignSection section in sections) {
        if (section.kind == kind && section.campaigns.isNotEmpty) {
          return section.campaigns;
        }
      }
    }
    return const <CampaignPresentation>[];
  }
}

/// The campaign section: what is running, how far along it is, and a way to the
/// rest.
class _Opportunities extends StatelessWidget {
  const _Opportunities({
    required this.state,
    required this.highlighted,
    required this.progressFor,
    required this.maxCampaigns,
  });

  final CampaignListState state;
  final List<CampaignPresentation> highlighted;

  /// One campaign's target progress, or null when it has none.
  ///
  /// The lookup is a **function of the campaign id**, never of the name: two
  /// campaigns may share a name, and only the id is the key both contracts
  /// return.
  final CampaignTargetProgress? Function(String campaignId) progressFor;

  final int maxCampaigns;

  bool get _isRunning =>
      highlighted.isNotEmpty &&
      highlighted.first.offer.lifecycleState.isRunning;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    if (state.isInitialLoading) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SrSectionHeader(title: SalesStaffHomeCopy.opportunitiesTitle),
          SizedBox(height: SrSpacing.lg),
          SrSkeletonCard(),
          SizedBox(height: SrSpacing.lg),
          SrSkeletonCard(),
        ],
      );
    }

    // An unreadable answer is never shown as "no campaigns": they are opposite
    // claims, and one of them would tell a seller their Retailer has nothing
    // running when the truth is that nobody could tell.
    if (state.hasFailedOutright) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SrSectionHeader(title: SalesStaffHomeCopy.opportunitiesTitle),
          SizedBox(height: SrSpacing.lg),
          SrAlert(
            tone: SrAlertTone.warning,
            title: SalesStaffHomeCopy.campaignsUnavailableTitle,
            message: SalesStaffHomeCopy.campaignsUnavailableBody,
          ),
        ],
      );
    }

    if (highlighted.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SrSectionHeader(title: SalesStaffHomeCopy.opportunitiesTitle),
          const SizedBox(height: SrSpacing.lg),
          SrEmptyState(
            icon: Icons.campaign_outlined,
            tone: SrTone.slate,
            title: SalesStaffHomeCopy.campaignsEmptyTitle,
            description: SalesStaffHomeCopy.campaignsEmptyBody,
            action: SrButton(
              label: SalesStaffHomeCopy.viewAllCampaigns,
              variant: SrButtonVariant.outline,
              icon: Icons.campaign_outlined,
              onPressed: () => context.go(SalesStaffNavigation.campaigns),
            ),
          ),
        ],
      );
    }

    final List<CampaignPresentation> shown = highlighted.length > maxCampaigns
        ? highlighted.sublist(0, maxCampaigns)
        : highlighted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SrSectionHeader(
          title: _isRunning
              ? SalesStaffHomeCopy.opportunitiesTitle
              : SalesStaffHomeCopy.upcomingTitle,
          description: _isRunning
              ? SalesStaffHomeCopy.opportunitiesDescription
              : SalesStaffHomeCopy.upcomingDescription,
        ),
        const SizedBox(height: SrSpacing.lg),

        for (int i = 0; i < shown.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: SrSpacing.lg),
          _HomeCampaign(
            campaign: shown[i],
            progress: progressFor(shown[i].offer.campaignId),
            index: i,
          ),
        ],

        // The cap is stated rather than left to look like the whole list.
        if (highlighted.length > shown.length) ...<Widget>[
          const SizedBox(height: SrSpacing.md),
          Text(
            SalesStaffHomeCopy.showingSome(shown.length, highlighted.length),
            style: SrTypography.caption.copyWith(color: sr.textMuted),
          ),
        ],

        const SizedBox(height: SrSpacing.lg),
        Align(
          alignment: Alignment.centerLeft,
          child: SrButton(
            label: SalesStaffHomeCopy.viewAllCampaigns,
            variant: SrButtonVariant.outline,
            icon: Icons.arrow_forward_rounded,
            onPressed: () => context.go(SalesStaffNavigation.campaigns),
          ),
        ),
      ],
    );
  }
}

/// One campaign on the home screen, and its target progress when there is any.
///
/// The progress sits **beside** the card rather than inside it, for the reason
/// the campaign list records: `CampaignCard` declares itself a single semantics
/// node with `excludeSemantics: true`, so an indicator nested within it would
/// be silent to a screen reader. As a sibling it keeps its own announcement —
/// the label, the current value, the target, the percentage and the state.
class _HomeCampaign extends StatelessWidget {
  const _HomeCampaign({
    required this.campaign,
    required this.progress,
    required this.index,
  });

  final CampaignPresentation campaign;

  /// Null for a `PER_UNIT_COINS` campaign, which has no threshold to progress
  /// towards — drawing one a ring would invent a goal the Vendor never set.
  final CampaignTargetProgress? progress;

  final int index;

  @override
  Widget build(BuildContext context) {
    final CampaignTargetProgress? row = progress;

    return SrEnter(
      index: index,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          CampaignCard(
            campaign: campaign,
            onTap: () => context.go(
              SalesStaffNavigation.campaignDetail(campaign.offer.campaignId),
            ),
          ),
          if (row != null) ...<Widget>[
            const SizedBox(height: SrSpacing.sm),
            CampaignTargetProgressView(
              progress: row,
              density: CampaignProgressDensity.compact,
            ),
          ],
        ],
      ),
    );
  }
}

/// The two most recent submissions, and a way to the rest.
///
/// Present on the landing screen because it answers "did that actually go
/// through?" — the question a person asks straight after submitting, and the
/// one the history is the only authority on.
class _RecentReceipts extends StatelessWidget {
  const _RecentReceipts();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReceiptHistoryCubit, ReceiptHistoryState>(
      builder: (BuildContext context, ReceiptHistoryState state) {
        return SrSectionCard(
          title: SalesStaffHomeCopy.recentTitle,
          description: SalesStaffHomeCopy.recentDescription,
          action: SrButton(
            label: SalesStaffHomeCopy.recentAction,
            variant: SrButtonVariant.ghost,
            size: SrButtonSize.sm,
            icon: Icons.chevron_right_rounded,
            onPressed: () => context.go(SalesStaffNavigation.history),
          ),
          child: _body(context, state),
        );
      },
    );
  }

  Widget _body(BuildContext context, ReceiptHistoryState state) {
    if (state.phase == ReceiptHistoryPhase.initial ||
        state.phase == ReceiptHistoryPhase.loading) {
      return const SrLoadingView(
        showHeader: false,
        rows: 2,
        label: 'Loading your submissions',
      );
    }

    // A failed refresh over rows already on screen keeps the rows: they are
    // still the last thing the backend actually said.
    if (state.phase == ReceiptHistoryPhase.failed &&
        state.submissions.isEmpty) {
      return SrFailureView(
        failure: state.failure!,
        onRetry: context.read<ReceiptHistoryCubit>().load,
      );
    }

    final List<ReceiptSubmission> recent = state.take(2);
    if (recent.isEmpty) {
      return const SrEmptyState(
        icon: Icons.inbox_outlined,
        title: SalesStaffHomeCopy.recentEmptyTitle,
        description: SalesStaffHomeCopy.recentEmptyBody,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < recent.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: SrSpacing.md),
          ReceiptSubmissionTile(submission: recent[i]),
        ],
      ],
    );
  }
}
