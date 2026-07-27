import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../../auth/domain/entities/portal_kind.dart';
import '../../../../auth/domain/entities/retailer_capabilities.dart';
import '../../../../auth/presentation/bloc/session_bloc.dart';
import '../../../domain/entities/retailer_owner_overview.dart';
import '../../../domain/repositories/retailer_owner_overview_repository.dart';
import '../cubit/retailer_owner_overview_cubit.dart';
import '../widgets/retailer_owner_detail_grid.dart';
import '../widgets/retailer_owner_overview_copy.dart';
import '../widgets/retailer_shop_count_card.dart';

/// The Retailer Owner landing screen.
///
/// Backed by `public.get_retailer_owner_portal_context()` — **one call, zero
/// arguments**. The cubit is created and loaded once by the Retailer Owner
/// shell, so entering this route a second time renders the values already held
/// rather than re-reading them.
///
/// ## Two sources, and neither is asked for the other's fact
///
/// * The **overview row** comes from the RPC and from nowhere else.
/// * The **organization name in the shell chrome** comes from the trusted
///   `PortalContext` the application already holds, resolved by
///   `get_my_portal_context()`.
///
/// Nothing is sent from the second to the first — the function takes no
/// arguments, so it could not accept an organization id even if one were offered
/// — and the name is never queried from `organizations` directly. Both contracts
/// resolve their Retailer from `auth.uid()`, so the name in the app bar and the
/// row on this page describe the same organization by construction rather than
/// by coincidence.
///
/// The page still renders `retailer_name` from the **row**, because that is the
/// canonical value this contract exists to return; the session name captions the
/// shell. They agree by construction, and neither is derived from the other.
///
/// ## Read-only, and it does not pretend otherwise
///
/// There is no chart, trend, comparison, revenue, receipt, claim, coin or payout
/// figure here, and no disabled one either. There is no shop list, staff roster,
/// product list, invitation control, organization editor or write action of any
/// kind: the backend function is `STABLE` and this screen has nothing to call
/// that is not. The upcoming destinations are named as text, and nothing is
/// fetched to populate them.
///
/// ## Refreshing
///
/// Two affordances for one action: pull-to-refresh, which is what a phone user
/// reaches for, and a header button, which is what a browser user reaches for and
/// what a keyboard or screen-reader user can actually operate. Both call the same
/// method, and that method ignores a second call while a read is in flight — so a
/// repeated tap cannot produce simultaneous requests.
///
/// A refresh **replaces the whole row atomically** and never merges a field: the
/// seven values come from one statement and describe one instant. A refresh that
/// fails keeps the values and says so above them, because they are still the last
/// thing the backend actually said.
class RetailerOwnerOverviewPage extends StatelessWidget {
  const RetailerOwnerOverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RetailerOwnerOverviewCubit, RetailerOwnerOverviewState>(
      builder: (BuildContext context, RetailerOwnerOverviewState state) {
        final RetailerOwnerOverviewCubit cubit = context
            .read<RetailerOwnerOverviewCubit>();

        // The skeleton stands in only for the *first* read. A refresh over
        // values already on screen keeps them.
        if (state.isInitialLoading) {
          return const SrLoadingView(label: RetailerOwnerOverviewCopy.loading);
        }

        return RefreshIndicator(
          onRefresh: cubit.refresh,
          child: SrPageBody(
            physics: const AlwaysScrollableScrollPhysics(),
            children: <Widget>[
              SrPageHeader(
                eyebrow: PortalKind.retailerOwner.displayName,
                title: RetailerOwnerOverviewCopy.title,
                description: RetailerOwnerOverviewCopy.description,
                actions: <Widget>[
                  Semantics(
                    button: true,
                    label: RetailerOwnerOverviewCopy.refresh,
                    child: SrButton(
                      label: RetailerOwnerOverviewCopy.refresh,
                      variant: SrButtonVariant.outline,
                      icon: Icons.refresh_rounded,
                      loading: state.isRefreshing,
                      loadingLabel: RetailerOwnerOverviewCopy.refreshing,
                      // Disabled while a read is in flight, so a repeated press
                      // cannot issue two requests for the same overview.
                      onPressed: state.isRefreshing ? null : cubit.refresh,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SrSpacing.xxl),
              _Body(state: state, cubit: cubit),
            ],
          ),
        );
      },
    );
  }
}

/// The overview, or the reason there is none.
class _Body extends StatelessWidget {
  const _Body({required this.state, required this.cubit});

  final RetailerOwnerOverviewState state;
  final RetailerOwnerOverviewCubit cubit;

  @override
  Widget build(BuildContext context) {
    // Zero rows. A successful answer meaning "there is no Owner overview for
    // you", so it is not a failure and offers no retry — a second identical call
    // returns the same nothing. Critically, no card renders: an ineligible
    // caller must never be shown an organization, and least of all the previous
    // caller's.
    if (state.phase == RetailerOverviewPhase.ineligible) {
      return const SrEmptyState(
        icon: Icons.person_off_outlined,
        tone: SrTone.slate,
        title: RetailerOwnerOverviewCopy.ineligibleTitle,
        description: RetailerOwnerOverviewCopy.ineligibleBody,
      );
    }

    // A failure with nothing loaded is the whole screen. The copy is chosen per
    // discriminant and carries no backend text; a retry appears only where a
    // second call could genuinely produce a different answer.
    if (state.hasFailedOutright) {
      final RetailerOverviewProblemCopy copy =
          RetailerOwnerOverviewCopy.problemCopy(state.problem!);
      return SrEmptyState(
        icon: _problemIcon(state.problem!),
        tone: _problemTone(state.problem!),
        title: copy.title,
        description: copy.body,
        action: copy.retryable
            ? SrButton(
                label: 'Try again',
                variant: SrButtonVariant.outline,
                icon: Icons.refresh_rounded,
                onPressed: cubit.load,
              )
            : null,
      );
    }

    final RetailerOwnerOverview? overview = state.overview;
    if (overview == null) {
      // Unreachable: `isInitialLoading` covers "nothing read yet",
      // `ineligible` covers zero rows and `hasFailedOutright` covers a failed
      // first read. Kept as a shrink rather than an assertion so an unforeseen
      // ordering renders nothing at all — never a zero-filled grid.
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // The organization or this membership is not active. Shown above the
        // values rather than instead of them: the row is real and the user is
        // entitled to see it, but presenting a suspended organization as a
        // healthy one would be the more misleading of the two options.
        if (state.hasInactiveStatus) ...<Widget>[
          const SrAlert(
            tone: SrAlertTone.warning,
            title: RetailerOwnerOverviewCopy.inactiveTitle,
            message: RetailerOwnerOverviewCopy.inactiveBody,
          ),
          const SizedBox(height: SrSpacing.xxl),
        ],

        // A refresh that failed over values already on screen says so without
        // throwing them away. Non-blocking: the cards below stay exactly as they
        // were, and the Refresh button remains the retry.
        if (state.isStale) ...<Widget>[
          const SrAlert(
            tone: SrAlertTone.warning,
            title: RetailerOwnerOverviewCopy.staleTitle,
            message: RetailerOwnerOverviewCopy.staleBody,
          ),
          const SizedBox(height: SrSpacing.xxl),
        ],

        // -- the organization ------------------------------------------------
        const SrSectionHeader(
          title: RetailerOwnerOverviewCopy.organizationSectionTitle,
          description: RetailerOwnerOverviewCopy.organizationSectionDescription,
        ),
        const SizedBox(height: SrSpacing.lg),
        RetailerOverviewDetailGrid(facts: _factsFor(overview)),

        const SizedBox(height: SrSpacing.xxxl),

        // -- the two shop counts ----------------------------------------------
        const SrSectionHeader(
          title: RetailerOwnerOverviewCopy.shopsSectionTitle,
          description: RetailerOwnerOverviewCopy.shopsSectionDescription,
        ),
        const SizedBox(height: SrSpacing.lg),
        SrCardGrid(
          children: <Widget>[
            RetailerShopCountCard(
              label: RetailerOwnerOverviewCopy.totalShopsLabel,
              value: overview.totalShopCount,
              hint: RetailerOwnerOverviewCopy.totalShopsHint,
              icon: Icons.storefront_rounded,
            ),
            RetailerShopCountCard(
              label: RetailerOwnerOverviewCopy.activeShopsLabel,
              value: overview.activeShopCount,
              hint: RetailerOwnerOverviewCopy.activeShopsHint,
              icon: Icons.check_circle_outline_rounded,
              tone: SrTone.emerald,
            ),
          ],
        ),
        const SizedBox(height: SrSpacing.lg),
        _Note(text: RetailerOwnerOverviewCopy.shopsNote),

        const SizedBox(height: SrSpacing.xxxl),

        // -- what is not here yet ---------------------------------------------
        const _UpcomingSection(),
      ],
    );
  }

  /// The five canonical facts, in the contract's own order.
  ///
  /// Each value is a display string. The two statuses render their [label], not
  /// their backend token, so an unrecognised token from a newer backend shows as
  /// "Unknown" rather than reaching the screen verbatim.
  static List<RetailerOverviewFact> _factsFor(RetailerOwnerOverview overview) {
    return <RetailerOverviewFact>[
      RetailerOverviewFact(
        label: RetailerOwnerOverviewCopy.retailerNameLabel,
        value: overview.retailerName,
        icon: Icons.apartment_rounded,
      ),
      RetailerOverviewFact(
        label: RetailerOwnerOverviewCopy.retailerStatusLabel,
        value: overview.retailerStatus.label,
        icon: Icons.verified_outlined,
        tone: _lifecycleTone(overview.retailerStatus),
      ),
      RetailerOverviewFact(
        label: RetailerOwnerOverviewCopy.membershipStatusLabel,
        value: overview.membershipStatus.label,
        icon: Icons.badge_outlined,
        tone: _membershipTone(overview.membershipStatus),
      ),
      RetailerOverviewFact(
        label: RetailerOwnerOverviewCopy.countryLabel,
        // Null is a real answer — the column is nullable — so it is said rather
        // than guessed at.
        value: overview.countryCode ?? RetailerOwnerOverviewCopy.notRecorded,
        icon: Icons.public_rounded,
        isMuted: overview.countryCode == null,
      ),
      RetailerOverviewFact(
        label: RetailerOwnerOverviewCopy.currencyLabel,
        value:
            overview.defaultCurrency ?? RetailerOwnerOverviewCopy.notRecorded,
        icon: Icons.payments_outlined,
        isMuted: overview.defaultCurrency == null,
      ),
    ];
  }

  static SrTone _lifecycleTone(RetailerLifecycleStatus status) =>
      switch (status) {
        RetailerLifecycleStatus.active => SrTone.emerald,
        RetailerLifecycleStatus.suspended => SrTone.amber,
        RetailerLifecycleStatus.deactivated => SrTone.red,
        RetailerLifecycleStatus.unknown => SrTone.slate,
      };

  static SrTone _membershipTone(RetailerMembershipStatus status) =>
      switch (status) {
        RetailerMembershipStatus.active => SrTone.emerald,
        RetailerMembershipStatus.invited => SrTone.blue,
        RetailerMembershipStatus.suspended => SrTone.amber,
        RetailerMembershipStatus.deactivated => SrTone.red,
        RetailerMembershipStatus.unknown => SrTone.slate,
      };

  static IconData _problemIcon(RetailerOverviewProblem problem) =>
      switch (problem) {
        RetailerOverviewProblem.denied => Icons.shield_outlined,
        RetailerOverviewProblem.signedOut => Icons.lock_outline_rounded,
        RetailerOverviewProblem.malformed => Icons.report_gmailerrorred_rounded,
        RetailerOverviewProblem.network => Icons.cloud_off_rounded,
        RetailerOverviewProblem.timeout => Icons.hourglass_empty_rounded,
        RetailerOverviewProblem.unexpected => Icons.error_outline_rounded,
      };

  static SrTone _problemTone(RetailerOverviewProblem problem) =>
      switch (problem) {
        RetailerOverviewProblem.denied => SrTone.amber,
        RetailerOverviewProblem.signedOut => SrTone.slate,
        RetailerOverviewProblem.malformed => SrTone.amber,
        RetailerOverviewProblem.network => SrTone.slate,
        RetailerOverviewProblem.timeout => SrTone.slate,
        RetailerOverviewProblem.unexpected => SrTone.amber,
      };
}

/// The destinations that exist on the web portal but not yet in the app.
///
/// ## Why these are named as text and not as cards
///
/// A tappable card would be a promise. These are read-only statements about what
/// the app does not do yet, and nothing here calls a backend to populate them —
/// `list_retailer_owner_portal_shops()`, `list_retailer_staff_members()` and
/// `list_retailer_assigned_products()` are all deployed and all deliberately
/// unused by this milestone.
///
/// ## Why the wording is "not in the app yet"
///
/// Every one of these already works on the SalesReward web portal. Labelling
/// them "coming soon" or "unavailable" would tell a Retailer Owner that a
/// feature they use today does not exist, which is both false and alarming. The
/// limitation is this client's, and the copy says so.
///
/// ## Capability hints filter this list
///
/// Presentation only. A destination whose backend capability hint is false is
/// not advertised, because advertising a dead end is worse than omitting it —
/// and a hint can only ever *hide* an entry here, never grant one. Whether any
/// of these operations is permitted is decided again in SQL when the screen that
/// performs it is eventually built.
class _UpcomingSection extends StatelessWidget {
  const _UpcomingSection();

  @override
  Widget build(BuildContext context) {
    final SessionState session = context.watch<SessionBloc>().state;
    final RetailerCapabilities capabilities = session is SessionActive
        ? session.portalContext.capabilities
        : RetailerCapabilities.none;

    final List<({String label, RetailerCapability capability})> entries =
        <({String label, RetailerCapability capability})>[
          (
            label: RetailerOwnerOverviewCopy.upcomingShops,
            capability: RetailerCapability.viewShops,
          ),
          (
            label: RetailerOwnerOverviewCopy.upcomingStaff,
            capability: RetailerCapability.viewStaff,
          ),
          (
            label: RetailerOwnerOverviewCopy.upcomingProducts,
            capability: RetailerCapability.viewAssignedProducts,
          ),
        ];

    final List<String> visible = entries
        .where(
          (({String label, RetailerCapability capability}) entry) =>
              capabilities.allows(entry.capability),
        )
        .map((({String label, RetailerCapability capability}) e) => e.label)
        .toList();

    if (visible.isEmpty) {
      // Nothing to advertise. The section disappears entirely rather than
      // rendering an empty heading.
      return const SizedBox.shrink();
    }

    return SrSectionCard(
      title: RetailerOwnerOverviewCopy.upcomingTitle,
      description: RetailerOwnerOverviewCopy.upcomingDescription,
      child: Wrap(
        spacing: SrSpacing.sm,
        runSpacing: SrSpacing.sm,
        children: <Widget>[
          for (final String label in visible)
            SrBadge(
              label: label,
              tone: SrTone.slate,
              icon: Icons.schedule_rounded,
            ),
        ],
      ),
    );
  }
}

/// A one-line qualifier beneath the shop counts.
class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: SrSpacing.xxs),
          child: Icon(
            Icons.info_outline_rounded,
            size: 15,
            color: sr.textMuted,
          ),
        ),
        const SizedBox(width: SrSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: SrTypography.caption.copyWith(color: sr.textMuted),
          ),
        ),
      ],
    );
  }
}
