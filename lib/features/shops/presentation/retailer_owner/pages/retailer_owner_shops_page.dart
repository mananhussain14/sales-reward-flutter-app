import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../../auth/domain/entities/portal_kind.dart';
import '../../../domain/entities/retailer_shop.dart';
import '../cubit/retailer_shops_cubit.dart';
import '../widgets/retailer_shop_card.dart';
import '../widgets/retailer_shops_copy.dart';

/// The Retailer Owner's shop estate.
///
/// Backed by `list_retailer_owner_portal_shops()` — **one call, zero
/// arguments**. The cubit is owned by the shell and loads on first entry to this
/// tab, so returning to the tab renders rows already held rather than re-reading
/// them.
///
/// ## Read-only, and it does not pretend otherwise
///
/// There is no add, edit, activate, deactivate or delete control here, and no
/// disabled one — a greyed-out button would imply the feature exists and is
/// merely switched off. There is no row tap, no chevron and no detail route,
/// because the contract returns no `shop_id` and there is therefore nothing to
/// address. The note under the header says so in words.
///
/// ## Nothing is sorted or filtered on the way in
///
/// The order is the backend's (`order by s.name, s.code nulls last, s.id`) and
/// is not re-sorted here. The search box filters rows **already read** and sends
/// nothing.
class RetailerOwnerShopsPage extends StatefulWidget {
  const RetailerOwnerShopsPage({super.key});

  @override
  State<RetailerOwnerShopsPage> createState() => _RetailerOwnerShopsPageState();
}

/// Stateful only to own the first read.
///
/// The shell creates the cubit but deliberately does not load it, so the tab
/// that a user actually opens is the one that issues an RPC. `loadOnce` is a
/// no-op once the phase has left `initial`, which is what makes returning to an
/// already-loaded tab read nothing.
class _RetailerOwnerShopsPageState extends State<RetailerOwnerShopsPage> {
  @override
  void initState() {
    super.initState();
    // Deferred to after the first frame so the read cannot emit into a widget
    // tree that is still building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<RetailerShopsCubit>().loadOnce();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RetailerShopsCubit, RetailerShopsState>(
      builder: (BuildContext context, RetailerShopsState state) {
        final RetailerShopsCubit cubit = context.read<RetailerShopsCubit>();

        if (state.isInitialLoading) {
          return const SrLoadingView(label: RetailerShopsCopy.loading);
        }

        return RefreshIndicator(
          onRefresh: cubit.refresh,
          child: SrPageBody(
            physics: const AlwaysScrollableScrollPhysics(),
            children: <Widget>[
              SrPageHeader(
                eyebrow: PortalKind.retailerOwner.displayName,
                title: RetailerShopsCopy.title,
                description: RetailerShopsCopy.description,
                actions: <Widget>[
                  Semantics(
                    button: true,
                    label: RetailerShopsCopy.refresh,
                    child: SrButton(
                      label: RetailerShopsCopy.refresh,
                      variant: SrButtonVariant.outline,
                      icon: Icons.refresh_rounded,
                      loading: state.isRefreshing,
                      loadingLabel: RetailerShopsCopy.refreshing,
                      // Disabled while a read is in flight, so a repeated press
                      // cannot issue two requests for the same estate.
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

  final RetailerShopsState state;
  final RetailerShopsCubit cubit;

  @override
  Widget build(BuildContext context) {
    // A failure with nothing loaded is the whole screen. Critically, no card
    // renders: an unreadable answer must never be shown as an empty estate.
    if (state.hasFailedOutright) {
      return SrRetailerProblemView(
        problem: state.problem!,
        onRetry: cubit.load,
      );
    }

    final List<RetailerShop> visible = state.visibleShops;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // A refresh that failed over rows already on screen says so without
        // throwing them away.
        if (state.isStale) ...<Widget>[
          const SrAlert(
            tone: SrAlertTone.warning,
            title: RetailerShopsCopy.staleTitle,
            message: RetailerShopsCopy.staleBody,
          ),
          const SizedBox(height: SrSpacing.xxl),
        ],

        const _ReadOnlyNote(),
        const SizedBox(height: SrSpacing.xl),

        // The search box is hidden when the backend returned nothing at all:
        // filtering an empty list is a control that cannot do anything.
        if (!state.isEmpty) ...<Widget>[
          SrSearchField(
            label: RetailerShopsCopy.searchLabel,
            hint: RetailerShopsCopy.searchHint,
            placeholder: RetailerShopsCopy.searchPlaceholder,
            term: state.searchTerm,
            onChanged: cubit.searchChanged,
          ),
          const SizedBox(height: SrSpacing.lg),
          _CountCaption(
            visible: visible.length,
            total: state.shops?.length ?? 0,
          ),
          const SizedBox(height: SrSpacing.lg),
        ],

        if (state.isEmpty)
          const SrEmptyState(
            icon: Icons.storefront_outlined,
            tone: SrTone.slate,
            title: RetailerShopsCopy.emptyTitle,
            description: RetailerShopsCopy.emptyBody,
          )
        else if (state.isSearchEmpty)
          // Distinct from having no shops: the estate is there, this search
          // simply matched none of it, and the way back is to clear the box.
          SrEmptyState(
            icon: Icons.search_off_rounded,
            tone: SrTone.slate,
            title: RetailerShopsCopy.searchEmptyTitle,
            description: RetailerShopsCopy.searchEmptyBody,
            action: SrButton(
              label: 'Clear search',
              variant: SrButtonVariant.outline,
              icon: Icons.close_rounded,
              onPressed: () => cubit.searchChanged(''),
            ),
          )
        else
          SrResponsiveGrid(
            // A shop card carries a name, a status pill and up to three short
            // details, so it pairs comfortably earlier than a card with a long
            // description would.
            twoUpThreshold: 640,
            threeUpThreshold: 1100,
            children: <Widget>[
              for (final RetailerShop shop in visible)
                RetailerShopCard(
                  // The presentation key, which exists purely so a refresh that
                  // reorders rows does not rebuild every card. It is not an id,
                  // is never sent anywhere, and is never shown.
                  key: ValueKey<String>(shop.presentationKey),
                  shop: shop,
                ),
            ],
          ),
      ],
    );
  }
}

class _CountCaption extends StatelessWidget {
  const _CountCaption({required this.visible, required this.total});

  final int visible;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Text(
      RetailerShopsCopy.showing(visible, total),
      style: SrTypography.caption.copyWith(color: context.sr.textMuted),
    );
  }
}

class _ReadOnlyNote extends StatelessWidget {
  const _ReadOnlyNote();

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
            RetailerShopsCopy.readOnlyNote,
            style: SrTypography.caption.copyWith(color: sr.textMuted),
          ),
        ),
      ],
    );
  }
}
