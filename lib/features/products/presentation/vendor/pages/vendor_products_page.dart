import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/shells/vendor/vendor_navigation.dart';
import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../../auth/domain/entities/portal_kind.dart';
import '../../../domain/entities/vendor_product_summary.dart';
import '../cubit/vendor_product_list_cubit.dart';
import '../widgets/vendor_product_add_button.dart';
import '../widgets/vendor_product_card.dart';
import '../widgets/vendor_product_copy.dart';
import '../widgets/vendor_product_filter_bar.dart';

/// The Vendor's product catalogue.
///
/// Backed by **one** call to `public.list_vendor_products()` — zero arguments,
/// the Vendor derived from `auth.uid()` in SQL, the active assignment count
/// computed as a correlated aggregate in the same statement. The cubit is
/// created and loaded once by the Vendor shell, so entering this route a second
/// time renders the rows already held rather than issuing a second read, and
/// coming back from a product's detail screen does not reload the catalogue.
///
/// ## One write affordance, and only one
///
/// **Add product**, which opens the create form. There is no edit, activate or
/// deactivate action *here* — those belong to one product and live on its own
/// screen, where the product they act on is visible. There is no delete action
/// anywhere, because no delete control, RPC or `DELETE` statement exists in this
/// product. There is no assign, withdraw or bulk-assignment action, because
/// assignment writes are a separate milestone on a separate permission. And there is
/// no import, upload, price, stock or reward affordance, because none of those exists
/// either. No disabled affordance is offered for any of them: a control that cannot
/// act is a promise about a feature that has not been built.
///
/// **Add product is a presentation guard and nothing more.** Whether this caller may
/// create one is decided in SQL, on the call, by a permission this client never names
/// — so the button's presence is a statement about the route, not about authority.
///
/// ## Refreshing
///
/// Two affordances for one action: pull-to-refresh, which is what a phone user
/// reaches for, and a header button, which is what a browser user reaches for
/// and what a keyboard or screen-reader user can actually operate. Both call the
/// same method, and that method ignores a second call while one read is in
/// flight — so a repeated tap cannot produce simultaneous requests.
class VendorProductsPage extends StatelessWidget {
  const VendorProductsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<VendorProductListCubit, VendorProductListState>(
      builder: (BuildContext context, VendorProductListState state) {
        final VendorProductListCubit cubit = context
            .read<VendorProductListCubit>();

        // The skeleton stands in only for the *first* read. A refresh over rows
        // already on screen keeps them, because they are still the last thing
        // the backend actually said.
        if (state.phase == VendorProductListPhase.initial ||
            (state.phase == VendorProductListPhase.loading &&
                state.products.isEmpty)) {
          return const SrLoadingView(label: VendorProductCopy.loadingList);
        }

        return RefreshIndicator(
          onRefresh: cubit.refresh,
          child: SrPageBody(
            physics: const AlwaysScrollableScrollPhysics(),
            children: <Widget>[
              SrPageHeader(
                eyebrow: PortalKind.vendorSuperAdmin.displayName,
                title: VendorProductCopy.listTitle,
                description: VendorProductCopy.listDescription,
                actions: <Widget>[
                  Semantics(
                    button: true,
                    label: VendorProductCopy.refresh,
                    child: SrButton(
                      label: VendorProductCopy.refresh,
                      variant: SrButtonVariant.outline,
                      icon: Icons.refresh_rounded,
                      loading: state.isRefreshing,
                      loadingLabel: VendorProductCopy.refreshing,
                      onPressed: state.isRefreshing ? null : cubit.refresh,
                    ),
                  ),
                  // The header lays its actions out in a `Wrap`, so they space and
                  // reflow themselves — a phone stacks them, a tablet keeps them on
                  // one row, and neither overflows.
                  const VendorProductAddButton(),
                ],
              ),
              const SizedBox(height: SrSpacing.xxl),
              _Summary(state: state),
              if (state.products.isNotEmpty) ...<Widget>[
                const SizedBox(height: SrSpacing.xxl),
                VendorProductFilterBar(
                  searchTerm: state.searchTerm,
                  statusFilter: state.statusFilter,
                  availableStatuses: state.presentStatuses,
                  onSearchChanged: cubit.search,
                  onStatusChanged: cubit.filterByStatus,
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

/// The figures the catalogue legitimately reports about itself.
///
/// Every one is counted from a value the backend returned. An unrecognised
/// status falls into **neither** the active nor the inactive bucket rather than
/// being folded into one, so the total is always the honest number and the
/// breakdown never claims to be exhaustive.
///
/// The inactive card and the assignment card appear only when they have
/// something to report, so a catalogue with no withdrawn products is not shown a
/// zero to puzzle over.
///
/// **There is no total-assignment figure here.** The list read does not return
/// `assignment_count` for any row, so summing one would be inventing it — the
/// number shown is strictly the active total, and it is labelled as such.
class _Summary extends StatelessWidget {
  const _Summary({required this.state});

  final VendorProductListState state;

  @override
  Widget build(BuildContext context) {
    if (state.products.isEmpty) {
      return const SizedBox.shrink();
    }

    return SrCardGrid(
      children: <Widget>[
        SrStatCard(
          label: VendorProductCopy.totalLabel,
          value: state.totalCount,
          hint: VendorProductCopy.totalHint,
          icon: Icons.inventory_2_rounded,
        ),
        SrStatCard(
          label: VendorProductCopy.activeLabel,
          value: state.activeCount,
          hint: VendorProductCopy.activeHint,
          icon: Icons.check_circle_outline_rounded,
          tone: SrTone.emerald,
        ),
        if (state.inactiveCount > 0)
          SrStatCard(
            label: VendorProductCopy.inactiveLabel,
            value: state.inactiveCount,
            hint: VendorProductCopy.inactiveHint,
            icon: Icons.block_rounded,
            tone: SrTone.slate,
          ),
        if (state.totalActiveAssignments > 0)
          SrStatCard(
            label: VendorProductCopy.activeAssignmentsLabel,
            value: state.totalActiveAssignments,
            hint: VendorProductCopy.activeAssignmentsHint,
            icon: Icons.storefront_rounded,
            tone: SrTone.indigo,
          ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state, required this.cubit});

  final VendorProductListState state;
  final VendorProductListCubit cubit;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    // A failure with nothing loaded is the whole screen. `SrFailureView` decides
    // the wording and whether a retry is offered, per discriminant — a denial
    // never offers one, an outage always does, and neither ever names a
    // permission code or a backend object.
    if (state.phase == VendorProductListPhase.failed &&
        state.products.isEmpty) {
      return SrFailureView(failure: state.failure!, onRetry: cubit.load);
    }

    // A Vendor with no products. A real, reachable state — and now the one place
    // where the invitation to add one is a fact rather than a promise, because this
    // screen can.
    if (state.isEmpty) {
      return const SrEmptyState(
        icon: Icons.inventory_2_outlined,
        tone: SrTone.slate,
        title: VendorProductCopy.emptyTitle,
        description: VendorProductCopy.emptyBody,
        action: VendorProductAddButton(),
      );
    }

    if (state.hasNoMatches) {
      return SrEmptyState(
        icon: Icons.search_off_rounded,
        title: VendorProductCopy.noMatchesTitle,
        description: VendorProductCopy.noMatchesBody,
        action: SrButton(
          label: VendorProductCopy.clearFilters,
          variant: SrButtonVariant.outline,
          icon: Icons.filter_alt_off_outlined,
          onPressed: cubit.clearFilters,
        ),
      );
    }

    final List<VendorProductSummary> visible = state.visibleProducts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // A refresh that failed over rows already on screen says so without
        // throwing the rows away.
        if (state.phase == VendorProductListPhase.failed) ...<Widget>[
          const SrAlert(
            tone: SrAlertTone.warning,
            title: VendorProductCopy.staleListTitle,
            message: VendorProductCopy.staleListBody,
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
        VendorProductGrid(
          children: <Widget>[
            for (final VendorProductSummary product in visible)
              VendorProductCard(
                key: ValueKey<String>(product.productId),
                product: product,
                onOpen: () => context.go(
                  VendorNavigation.productDetailPath(product.productId),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
