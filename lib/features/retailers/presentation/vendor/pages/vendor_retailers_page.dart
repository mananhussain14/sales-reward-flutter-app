import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/shells/vendor/vendor_navigation.dart';
import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../../auth/domain/entities/portal_kind.dart';
import '../../../domain/entities/vendor_retailer_summary.dart';
import '../cubit/vendor_retailer_list_cubit.dart';
import '../widgets/vendor_retailer_card.dart';
import '../widgets/vendor_retailer_copy.dart';
import '../widgets/vendor_retailer_filter_bar.dart';
import '../widgets/vendor_retailer_grid.dart';

/// The Vendor's Retailer directory.
///
/// Backed by **one** call to `public.list_vendor_retailers()` — zero arguments,
/// the Vendor derived from `auth.uid()` in SQL. The cubit is created and loaded
/// once by the Vendor shell, so entering this route a second time renders the
/// rows already held rather than issuing a second read, and coming back from a
/// Retailer's detail screen does not reload the directory.
///
/// ## Refreshing
///
/// Two affordances for one action: pull-to-refresh, which is what a phone user
/// reaches for, and a header button, which is what a browser user reaches for
/// and what a keyboard or screen-reader user can actually operate. Both call the
/// same method, and that method ignores a second call while one read is in
/// flight — so a repeated tap cannot produce simultaneous requests.
class VendorRetailersPage extends StatelessWidget {
  const VendorRetailersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<VendorRetailerListCubit, VendorRetailerListState>(
      builder: (BuildContext context, VendorRetailerListState state) {
        final VendorRetailerListCubit cubit = context
            .read<VendorRetailerListCubit>();

        // The skeleton stands in only for the *first* read. A refresh over rows
        // already on screen keeps them, because they are still the last thing
        // the backend actually said.
        if (state.phase == VendorRetailerListPhase.initial ||
            (state.phase == VendorRetailerListPhase.loading &&
                state.retailers.isEmpty)) {
          return const SrLoadingView(label: VendorRetailerCopy.loadingList);
        }

        return RefreshIndicator(
          onRefresh: cubit.refresh,
          child: SrPageBody(
            physics: const AlwaysScrollableScrollPhysics(),
            children: <Widget>[
              SrPageHeader(
                eyebrow: PortalKind.vendorSuperAdmin.displayName,
                title: VendorRetailerCopy.listTitle,
                description: VendorRetailerCopy.listDescription,
                actions: <Widget>[
                  SrButton(
                    label: VendorRetailerCopy.refresh,
                    variant: SrButtonVariant.outline,
                    icon: Icons.refresh_rounded,
                    loading: state.isRefreshing,
                    loadingLabel: VendorRetailerCopy.refreshing,
                    onPressed: state.isRefreshing ? null : cubit.refresh,
                  ),
                ],
              ),
              const SizedBox(height: SrSpacing.xxl),
              _Summary(state: state),
              if (state.retailers.isNotEmpty) ...<Widget>[
                const SizedBox(height: SrSpacing.xxl),
                VendorRetailerFilterBar(
                  searchTerm: state.searchTerm,
                  statusFilter: state.statusFilter,
                  availableStatuses: state.presentRelationshipStatuses,
                  onSearchChanged: cubit.search,
                  onStatusChanged: cubit.filterByRelationshipStatus,
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

/// The two figures a directory legitimately reports about itself.
///
/// Both are sums of counts the backend computed. Nothing here re-counts anything
/// from a list the client would have had to fetch, and neither figure is shown
/// while the read has failed with nothing loaded — a fabricated `0` would be a
/// claim the backend never made.
class _Summary extends StatelessWidget {
  const _Summary({required this.state});

  final VendorRetailerListState state;

  @override
  Widget build(BuildContext context) {
    if (state.retailers.isEmpty) {
      return const SizedBox.shrink();
    }

    return SrCardGrid(
      children: <Widget>[
        SrStatCard(
          label: 'Connected Retailers',
          value: state.totalCount,
          hint: 'Every Retailer your organization manages',
          icon: Icons.storefront_rounded,
        ),
        SrStatCard(
          label: 'Shops across Retailers',
          value: state.totalShopCount,
          hint: '${state.totalActiveShopCount} active',
          icon: Icons.store_mall_directory_rounded,
          tone: SrTone.emerald,
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state, required this.cubit});

  final VendorRetailerListState state;
  final VendorRetailerListCubit cubit;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    // A failure with nothing loaded is the whole screen. `SrFailureView` decides
    // the wording and whether a retry is offered, per discriminant — a denial
    // never offers one, an outage always does.
    if (state.phase == VendorRetailerListPhase.failed &&
        state.retailers.isEmpty) {
      return SrFailureView(failure: state.failure!, onRetry: cubit.load);
    }

    if (state.isEmpty) {
      return const SrEmptyState(
        icon: Icons.storefront_outlined,
        tone: SrTone.indigo,
        title: VendorRetailerCopy.emptyTitle,
        description: VendorRetailerCopy.emptyBody,
      );
    }

    if (state.hasNoMatches) {
      return SrEmptyState(
        icon: Icons.search_off_rounded,
        title: VendorRetailerCopy.noMatchesTitle,
        description: VendorRetailerCopy.noMatchesBody,
        action: SrButton(
          label: VendorRetailerCopy.clearFilters,
          variant: SrButtonVariant.outline,
          icon: Icons.filter_alt_off_outlined,
          onPressed: cubit.clearFilters,
        ),
      );
    }

    final List<VendorRetailerSummary> visible = state.visibleRetailers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // A refresh that failed over rows already on screen says so without
        // throwing the rows away.
        if (state.phase == VendorRetailerListPhase.failed) ...<Widget>[
          const SrAlert(
            tone: SrAlertTone.warning,
            title: VendorRetailerCopy.staleListTitle,
            message: VendorRetailerCopy.staleListBody,
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
        VendorRetailerGrid(
          children: <Widget>[
            for (final VendorRetailerSummary retailer in visible)
              VendorRetailerCard(
                key: ValueKey<String>(retailer.relationshipId),
                retailer: retailer,
                onOpen: () => context.go(
                  VendorNavigation.retailerDetailPath(retailer.relationshipId),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
