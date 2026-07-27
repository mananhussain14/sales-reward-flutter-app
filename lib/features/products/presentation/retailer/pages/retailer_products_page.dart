import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../../auth/domain/entities/portal_kind.dart';
import '../../../domain/entities/retailer_assigned_product.dart';
import '../cubit/retailer_products_cubit.dart';
import '../widgets/retailer_product_card.dart';
import '../widgets/retailer_products_copy.dart';

/// The products currently assigned to the Retailer, for both Retailer roles.
///
/// Backed by `list_retailer_assigned_products()` — **one call, zero arguments**.
/// The Owner and the Manager see the identical screen because the contract is
/// identical for them: the same member resolver, the same
/// `RETAILER_PRODUCTS_READ` permission, the same rows. [role] is used only for
/// the eyebrow.
///
/// ## Read-only, and it does not pretend otherwise
///
/// There is no assign, withdraw, edit, create or delete control here, and no
/// disabled one. A Retailer genuinely cannot change an assignment — that is a
/// Vendor capability on a different permission — so an affordance would be a
/// promise nothing could keep.
///
/// ## No history, and the copy says so
///
/// The contract returns only rows where both the assignment and the product are
/// `ACTIVE`. A withdrawn assignment is simply absent, and **no RPC exists** that
/// would return one to a Retailer. So there is no "show inactive" toggle, no
/// status filter and no archive tab: each would imply data the backend cannot
/// produce. The note under the header states the scope once, in words.
class RetailerProductsPage extends StatefulWidget {
  const RetailerProductsPage({super.key, required this.role});

  /// Which shell this page is rendered in. Presentation only.
  final PortalKind role;

  @override
  State<RetailerProductsPage> createState() => _RetailerProductsPageState();
}

/// Stateful only to own the first read.
///
/// The shell creates the cubit but deliberately does not load it, so the tab
/// that a user actually opens is the one that issues an RPC. `loadOnce` is a
/// no-op once the phase has left `initial`, which is what makes returning to an
/// already-loaded tab read nothing.
class _RetailerProductsPageState extends State<RetailerProductsPage> {
  @override
  void initState() {
    super.initState();
    // Deferred to after the first frame so the read cannot emit into a widget
    // tree that is still building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<RetailerProductsCubit>().loadOnce();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RetailerProductsCubit, RetailerProductsState>(
      builder: (BuildContext context, RetailerProductsState state) {
        final RetailerProductsCubit cubit = context
            .read<RetailerProductsCubit>();

        if (state.isInitialLoading) {
          return const SrLoadingView(label: RetailerProductsCopy.loading);
        }

        return RefreshIndicator(
          onRefresh: cubit.refresh,
          child: SrPageBody(
            physics: const AlwaysScrollableScrollPhysics(),
            children: <Widget>[
              SrPageHeader(
                eyebrow: widget.role.displayName,
                title: RetailerProductsCopy.title,
                description: RetailerProductsCopy.description,
                actions: <Widget>[
                  Semantics(
                    button: true,
                    label: RetailerProductsCopy.refresh,
                    child: SrButton(
                      label: RetailerProductsCopy.refresh,
                      variant: SrButtonVariant.outline,
                      icon: Icons.refresh_rounded,
                      loading: state.isRefreshing,
                      loadingLabel: RetailerProductsCopy.refreshing,
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

class _Body extends StatelessWidget {
  const _Body({required this.state, required this.cubit});

  final RetailerProductsState state;
  final RetailerProductsCubit cubit;

  @override
  Widget build(BuildContext context) {
    // A failure with nothing loaded is the whole screen. No card renders: an
    // unreadable answer must never be shown as an empty catalogue, and a denial
    // must never be shown as "no Vendor assigns you anything".
    if (state.hasFailedOutright) {
      return SrRetailerProblemView(
        problem: state.problem!,
        onRetry: cubit.load,
      );
    }

    final List<RetailerAssignedProduct> visible = state.visibleProducts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (state.isStale) ...<Widget>[
          const SrAlert(
            tone: SrAlertTone.warning,
            title: RetailerProductsCopy.staleTitle,
            message: RetailerProductsCopy.staleBody,
          ),
          const SizedBox(height: SrSpacing.xxl),
        ],

        const _Note(text: RetailerProductsCopy.readOnlyNote),
        const SizedBox(height: SrSpacing.xl),

        if (!state.isEmpty) ...<Widget>[
          SrSearchField(
            label: RetailerProductsCopy.searchLabel,
            hint: RetailerProductsCopy.searchHint,
            placeholder: RetailerProductsCopy.searchPlaceholder,
            term: state.searchTerm,
            onChanged: cubit.searchChanged,
          ),
          const SizedBox(height: SrSpacing.lg),
          Text(
            RetailerProductsCopy.showing(
              visible.length,
              state.products?.length ?? 0,
            ),
            style: SrTypography.caption.copyWith(color: context.sr.textMuted),
          ),
          const SizedBox(height: SrSpacing.lg),
        ],

        if (state.isEmpty)
          const SrEmptyState(
            icon: Icons.inventory_2_outlined,
            tone: SrTone.slate,
            title: RetailerProductsCopy.emptyTitle,
            description: RetailerProductsCopy.emptyBody,
          )
        else if (state.isSearchEmpty)
          SrEmptyState(
            icon: Icons.search_off_rounded,
            tone: SrTone.slate,
            title: RetailerProductsCopy.searchEmptyTitle,
            description: RetailerProductsCopy.searchEmptyBody,
            action: SrButton(
              label: 'Clear search',
              variant: SrButtonVariant.outline,
              icon: Icons.close_rounded,
              onPressed: () => cubit.searchChanged(''),
            ),
          )
        else
          SrResponsiveGrid(
            // A product card can carry a three-line description, so it needs
            // more room before pairing than a shop card does.
            twoUpThreshold: 760,
            threeUpThreshold: 1240,
            children: <Widget>[
              for (final RetailerAssignedProduct product in visible)
                RetailerProductCard(product: product),
            ],
          ),
      ],
    );
  }
}

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
