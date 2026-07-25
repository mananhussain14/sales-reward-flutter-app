import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/shells/vendor/vendor_navigation.dart';
import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../../auth/domain/entities/portal_kind.dart';
import '../../../domain/entities/vendor_user_summary.dart';
import '../cubit/vendor_user_list_cubit.dart';
import '../widgets/vendor_user_card.dart';
import '../widgets/vendor_user_copy.dart';
import '../widgets/vendor_user_filter_bar.dart';

/// The Vendor's user directory.
///
/// Backed by **one** call to `public.list_vendor_users()` — zero arguments, the
/// Vendor derived from `auth.uid()` in SQL, roles aggregated into the same row.
/// The cubit is created and loaded once by the Vendor shell, so entering this
/// route a second time renders the rows already held rather than issuing a
/// second read, and coming back from a user's detail screen does not reload the
/// directory.
///
/// ## Refreshing
///
/// Two affordances for one action: pull-to-refresh, which is what a phone user
/// reaches for, and a header button, which is what a browser user reaches for
/// and what a keyboard or screen-reader user can actually operate. Both call the
/// same method, and that method ignores a second call while one read is in
/// flight — so a repeated tap cannot produce simultaneous requests.
class VendorUsersPage extends StatelessWidget {
  const VendorUsersPage({super.key});

  /// Two columns later than the Retailer directory: a user card carries two
  /// prefixed status pills *and* a wrapping row of role chips, so it needs more
  /// width before a second column stops crowding it.
  static const double twoUpThreshold = 820;
  static const double threeUpThreshold = 1180;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<VendorUserListCubit, VendorUserListState>(
      builder: (BuildContext context, VendorUserListState state) {
        final VendorUserListCubit cubit = context.read<VendorUserListCubit>();

        // The skeleton stands in only for the *first* read. A refresh over rows
        // already on screen keeps them, because they are still the last thing
        // the backend actually said.
        if (state.phase == VendorUserListPhase.initial ||
            (state.phase == VendorUserListPhase.loading &&
                state.users.isEmpty)) {
          return const SrLoadingView(label: VendorUserCopy.loadingList);
        }

        return RefreshIndicator(
          onRefresh: cubit.refresh,
          child: SrPageBody(
            physics: const AlwaysScrollableScrollPhysics(),
            children: <Widget>[
              SrPageHeader(
                eyebrow: PortalKind.vendorSuperAdmin.displayName,
                title: VendorUserCopy.listTitle,
                description: VendorUserCopy.listDescription,
                actions: <Widget>[
                  Semantics(
                    button: true,
                    label: VendorUserCopy.refresh,
                    child: SrButton(
                      label: VendorUserCopy.refresh,
                      variant: SrButtonVariant.outline,
                      icon: Icons.refresh_rounded,
                      loading: state.isRefreshing,
                      loadingLabel: VendorUserCopy.refreshing,
                      onPressed: state.isRefreshing ? null : cubit.refresh,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SrSpacing.xxl),
              _Summary(state: state),
              if (state.users.isNotEmpty) ...<Widget>[
                const SizedBox(height: SrSpacing.xxl),
                VendorUserFilterBar(
                  searchTerm: state.searchTerm,
                  profileFilter: state.profileFilter,
                  membershipFilter: state.membershipFilter,
                  availableProfileStatuses: state.presentProfileStatuses,
                  availableMembershipStatuses: state.presentMembershipStatuses,
                  onSearchChanged: cubit.search,
                  onProfileStatusChanged: cubit.filterByProfileStatus,
                  onMembershipStatusChanged: cubit.filterByMembershipStatus,
                  onClear: cubit.clearFilters,
                ),
              ],
              const SizedBox(height: SrSpacing.xxl),
              _Body(state: state, cubit: cubit),
            ],
          ),
        );
      },
    );
  }
}

/// The figures a directory legitimately reports about itself.
///
/// Every one is counted from a `membership_status` the backend returned. Nothing
/// here is re-counted from a list the client would have had to fetch, and an
/// unknown status falls into **none** of the three buckets rather than being
/// folded into one — the total is always the honest number, and the breakdown
/// never claims to be exhaustive.
///
/// The two lifecycle cards appear only when they have something to report, so a
/// healthy Vendor is not shown two zeroes.
class _Summary extends StatelessWidget {
  const _Summary({required this.state});

  final VendorUserListState state;

  @override
  Widget build(BuildContext context) {
    if (state.users.isEmpty) {
      return const SizedBox.shrink();
    }

    return SrCardGrid(
      children: <Widget>[
        SrStatCard(
          label: VendorUserCopy.totalLabel,
          value: state.totalCount,
          hint: VendorUserCopy.totalHint,
          icon: Icons.group_rounded,
        ),
        SrStatCard(
          label: VendorUserCopy.activeLabel,
          value: state.activeCount,
          hint: 'Membership status: Active',
          icon: Icons.verified_user_outlined,
          tone: SrTone.emerald,
        ),
        if (state.invitedCount > 0)
          SrStatCard(
            label: VendorUserCopy.invitedLabel,
            value: state.invitedCount,
            hint: 'Recorded, not yet joined',
            icon: Icons.schedule_rounded,
            tone: SrTone.amber,
          ),
        if (state.inactiveCount > 0)
          SrStatCard(
            label: VendorUserCopy.inactiveLabel,
            value: state.inactiveCount,
            hint: 'Membership no longer active',
            icon: Icons.pause_circle_outline_rounded,
            tone: SrTone.slate,
          ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state, required this.cubit});

  final VendorUserListState state;
  final VendorUserListCubit cubit;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    // A failure with nothing loaded is the whole screen. `SrFailureView` decides
    // the wording and whether a retry is offered, per discriminant — a denial
    // never offers one, an outage always does.
    if (state.phase == VendorUserListPhase.failed && state.users.isEmpty) {
      return SrFailureView(failure: state.failure!, onRetry: cubit.load);
    }

    // Written against one row rather than zero: an authorized caller is by
    // definition a member of the Vendor they are listing, so their own row is
    // always present and "it is just me" is the real no-colleagues case.
    if (state.isEmpty) {
      return const SrEmptyState(
        icon: Icons.group_outlined,
        tone: SrTone.slate,
        title: VendorUserCopy.emptyTitle,
        description: VendorUserCopy.emptyBody,
      );
    }

    if (state.hasNoMatches) {
      return SrEmptyState(
        icon: Icons.search_off_rounded,
        title: VendorUserCopy.noMatchesTitle,
        description: VendorUserCopy.noMatchesBody,
        action: SrButton(
          label: VendorUserCopy.clearFilters,
          variant: SrButtonVariant.outline,
          icon: Icons.filter_alt_off_outlined,
          onPressed: cubit.clearFilters,
        ),
      );
    }

    final List<VendorUserSummary> visible = state.visibleUsers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // A refresh that failed over rows already on screen says so without
        // throwing the rows away.
        if (state.phase == VendorUserListPhase.failed) ...<Widget>[
          const SrAlert(
            tone: SrAlertTone.warning,
            title: VendorUserCopy.staleListTitle,
            message: VendorUserCopy.staleListBody,
          ),
          const SizedBox(height: SrSpacing.lg),
        ],
        if (state.hasFilters) ...<Widget>[
          Text(
            'Showing ${visible.length} of ${state.totalCount}',
            style: SrTypography.caption.copyWith(color: sr.textSecondary),
          ),
          const SizedBox(height: SrSpacing.md),
        ],
        SrResponsiveGrid(
          twoUpThreshold: VendorUsersPage.twoUpThreshold,
          threeUpThreshold: VendorUsersPage.threeUpThreshold,
          children: <Widget>[
            for (final VendorUserSummary user in visible)
              VendorUserCard(
                key: ValueKey<String>(user.membershipId),
                user: user,
                onOpen: () => context.go(
                  VendorNavigation.userDetailPath(user.membershipId),
                ),
              ),
          ],
        ),
        if (state.isOnlyMe) ...<Widget>[
          const SizedBox(height: SrSpacing.lg),
          const SrAlert(
            title: VendorUserCopy.onlyMeTitle,
            message: VendorUserCopy.onlyMeBody,
          ),
        ],
      ],
    );
  }
}
