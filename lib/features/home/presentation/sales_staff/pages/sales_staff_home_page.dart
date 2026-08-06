import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/shells/sales_staff/sales_staff_navigation.dart';
import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../../auth/presentation/bloc/session_bloc.dart';
import '../../../../campaigns/presentation/shared/campaign_list_cubit.dart';
import '../../../../campaigns/presentation/shared/campaign_presentation.dart';
import '../../../../receipts/domain/entities/receipt_submission.dart';
import '../../../../receipts/presentation/sales_staff/cubit/receipt_history_cubit.dart';
import '../../../../receipts/presentation/sales_staff/widgets/receipt_submission_tile.dart';
import '../../../../rewards/presentation/bloc/campaign_earnings_cubit.dart';
import '../../../../rewards/presentation/bloc/campaign_target_progress_cubit.dart';
import '../widgets/sales_staff_add_receipt_cta.dart';
import '../widgets/sales_staff_coins_panel.dart';
import '../widgets/sales_staff_home_copy.dart';
import '../widgets/sales_staff_next_reward_hero.dart';
import '../widgets/sales_staff_opportunity.dart';
import '../widgets/sales_staff_opportunity_card.dart';
import '../widgets/sales_staff_welcome_header.dart';

/// The Sales Staff landing screen.
///
/// ## Mobile first, and it shows
///
/// The order on a phone is the order the questions are asked: a one-line
/// greeting, then the **hero** — which campaign, how close, what it pays, and
/// the way into it — then the coins already earned, then the rest of the
/// campaigns as a horizontal carousel, then the latest receipt. The primary
/// action floats above the bottom bar the whole time.
///
/// The tablet and desktop layouts are adaptations of that, not the other way
/// round: the same widgets, a constrained content column, and the action moved
/// into the header where the shell has a rail instead of a bottom bar.
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
/// The hero is chosen by [selectHeroOpportunity], a deterministic rule over the
/// order the backend returned. It is not a recommendation.
///
/// ## The first read belongs to this screen
///
/// The campaign, progress and earnings cubits are created by the shell and
/// deliberately not loaded there. This screen calls `loadOnce` on all three
/// from `initState`, which is what makes entering the shell issue exactly one
/// read of each. Opening the Campaigns or Earnings tab afterwards reads
/// nothing: `loadOnce` is a no-op once the phase has left `initial`.
///
/// ## Four independent regions, and none can blank another
///
/// The hero, the coins strip, the carousel and the recent receipt are driven by
/// three separate cubits over four separate contracts on two separate
/// permissions. A failed earnings read leaves the campaigns on screen; a failed
/// campaign read leaves the coins; and neither is ever rendered as an empty
/// state, because "could not read" and "you have none" are opposite claims.
///
/// ## No action other than navigation
///
/// The only interactive elements are the call to action, the cards and three
/// links. There is no claim, redeem, withdraw, payout or dispute control, and
/// none disabled: no such contract exists in the deployed schema.
class SalesStaffHomePage extends StatefulWidget {
  const SalesStaffHomePage({super.key});

  @override
  State<SalesStaffHomePage> createState() => _SalesStaffHomePageState();
}

class _SalesStaffHomePageState extends State<SalesStaffHomePage> {
  /// How many campaigns the carousel carries before deferring to the full
  /// list. The cap is stated on screen when it truncates.
  static const int _maxCarousel = 6;

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

  void _openCampaign(String campaignId) =>
      context.go(SalesStaffNavigation.campaignDetail(campaignId));

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    // At and above this width the shell has already promoted its bottom bar to
    // a navigation rail, so there is no bottom chrome for a floating pill to
    // sit above and the action belongs in the header.
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
                final List<SalesStaffOpportunity> all = buildOpportunities(
                  campaigns.campaigns ?? const <CampaignPresentation>[],
                  progress.forCampaign,
                );
                final SalesStaffOpportunity? hero = selectHeroOpportunity(all);
                final List<SalesStaffOpportunity> rest = remainingOpportunities(
                  all,
                  hero,
                );

                return SrSoftBackdrop(
                  child: Stack(
                    children: <Widget>[
                      RefreshIndicator(
                        onRefresh: _refresh,
                        child: SrPageBody(
                          // Always scrollable, so pull-to-refresh works on a
                          // short screen rather than only when it overflows.
                          physics: const AlwaysScrollableScrollPhysics(),
                          // A reading measure rather than the full 1152: a
                          // dashboard whose every card spans a 1440px browser
                          // is a phone layout that has been stretched.
                          maxWidth: 900,
                          children: <Widget>[
                            SrEnter(
                              child: SalesStaffWelcomeHeader(
                                organizationName: organizationName,
                                action: wide
                                    ? SalesStaffAddReceiptButton(
                                        onPressed: _openSubmit,
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(height: SrSpacing.xl),

                            SrEnter(
                              index: 1,
                              child: _HeroRegion(
                                state: campaigns,
                                hero: hero,
                                onView: _openCampaign,
                              ),
                            ),
                            const SizedBox(height: SrSpacing.xl),

                            SrEnter(
                              index: 2,
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

                            _Carousel(
                              opportunities: rest,
                              maxCards: _maxCarousel,
                              onOpen: _openCampaign,
                            ),
                            const SizedBox(height: SrSpacing.xxl),

                            const SrEnter(index: 4, child: _LatestReceipt()),

                            // Room for the floating pill, so the last card is
                            // never trapped behind it.
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
                          child: SalesStaffAddReceiptBar(
                            onPressed: _openSubmit,
                          ),
                        ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

/// The hero, or the honest reason there is not one.
class _HeroRegion extends StatelessWidget {
  const _HeroRegion({
    required this.state,
    required this.hero,
    required this.onView,
  });

  final CampaignListState state;
  final SalesStaffOpportunity? hero;
  final void Function(String campaignId) onView;

  @override
  Widget build(BuildContext context) {
    if (state.isInitialLoading) {
      return const SrSkeletonCard();
    }

    // An unreadable answer is never shown as "no campaigns": they are opposite
    // claims, and one of them would tell a seller their Retailer has nothing
    // running when the truth is that nobody could tell.
    if (state.hasFailedOutright) {
      return const SrAlert(
        tone: SrAlertTone.warning,
        title: SalesStaffHomeCopy.campaignsUnavailableTitle,
        message: SalesStaffHomeCopy.campaignsUnavailableBody,
      );
    }

    final SalesStaffOpportunity? opportunity = hero;
    if (opportunity == null) {
      return SrFeatureCard(
        tone: SrTone.slate,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SrIconDisc(
              icon: Icons.campaign_outlined,
              tone: SrTone.slate,
              size: 48,
            ),
            const SizedBox(height: SrSpacing.lg),
            Text(
              SalesStaffHomeCopy.heroEmptyTitle,
              style: SrTypography.sectionTitle.copyWith(
                color: context.sr.foreground,
              ),
            ),
            const SizedBox(height: SrSpacing.xs),
            Text(
              SalesStaffHomeCopy.heroEmptyBody,
              style: SrTypography.body.copyWith(color: context.sr.textBody),
            ),
          ],
        ),
      );
    }

    return SalesStaffNextRewardHero(
      opportunity: opportunity,
      onView: () => onView(opportunity.campaign.offer.campaignId),
    );
  }
}

/// The horizontally scrolling campaign strip.
///
/// A carousel rather than a stack, because the home screen is not the campaign
/// list: it is a place to notice an opportunity and open it. The full list is
/// one tap away and is the screen that owns the sections, the counts and the
/// grid.
class _Carousel extends StatelessWidget {
  const _Carousel({
    required this.opportunities,
    required this.maxCards,
    required this.onOpen,
  });

  final List<SalesStaffOpportunity> opportunities;
  final int maxCards;
  final void Function(String campaignId) onOpen;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    if (opportunities.isEmpty) {
      return const SizedBox.shrink();
    }

    final List<SalesStaffOpportunity> shown = opportunities.length > maxCards
        ? opportunities.sublist(0, maxCards)
        : opportunities;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SrEnter(
          index: 3,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      SalesStaffHomeCopy.carouselTitle,
                      style: SrTypography.sectionTitle.copyWith(
                        color: sr.foreground,
                      ),
                    ),
                    Text(
                      opportunities.length > shown.length
                          ? SalesStaffHomeCopy.showingSome(
                              shown.length,
                              opportunities.length,
                            )
                          : SalesStaffHomeCopy.carouselHint,
                      style: SrTypography.caption.copyWith(color: sr.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: SrSpacing.md),
              SrButton(
                label: SalesStaffHomeCopy.viewAllCampaigns,
                variant: SrButtonVariant.ghost,
                size: SrButtonSize.sm,
                icon: Icons.chevron_right_rounded,
                onPressed: () => context.go(SalesStaffNavigation.campaigns),
              ),
            ],
          ),
        ),
        const SizedBox(height: SrSpacing.md),
        // The strip is allowed to paint outside the page gutter so a card is
        // visibly cut off at the edge — which is what tells a reader it
        // scrolls.
        SizedBox(
          // Scaled with the reader's text size rather than fixed: a horizontal
          // ListView has to be given a height, and a height that ignored text
          // scaling would clip the very content the scaling exists to enlarge.
          height:
              268 *
              (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 2.2),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: EdgeInsets.zero,
            itemCount: shown.length,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(width: SrSpacing.md),
            itemBuilder: (BuildContext context, int index) => SrEnter(
              index: index,
              child: SalesStaffOpportunityCard(
                opportunity: shown[index],
                onOpen: () => onOpen(shown[index].campaign.offer.campaignId),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The most recent submission, and a way to the rest.
///
/// One row rather than a list: it answers "did that actually go through?" — the
/// question a person asks straight after submitting — and the history screen
/// owns everything beyond it.
class _LatestReceipt extends StatelessWidget {
  const _LatestReceipt();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReceiptHistoryCubit, ReceiptHistoryState>(
      builder: (BuildContext context, ReceiptHistoryState state) {
        return SrSectionCard(
          title: SalesStaffHomeCopy.latestReceiptTitle,
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
        rows: 1,
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

    final List<ReceiptSubmission> recent = state.take(1);
    if (recent.isEmpty) {
      return const SrEmptyState(
        icon: Icons.inbox_outlined,
        title: SalesStaffHomeCopy.recentEmptyTitle,
        description: SalesStaffHomeCopy.recentEmptyBody,
      );
    }

    return ReceiptSubmissionTile(submission: recent.first);
  }
}
