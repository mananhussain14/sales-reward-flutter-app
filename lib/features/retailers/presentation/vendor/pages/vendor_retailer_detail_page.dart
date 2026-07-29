import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/shells/vendor/vendor_navigation.dart';
import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/vendor_retailer_detail.dart';
import '../../../domain/entities/vendor_retailer_shop.dart';
import '../cubit/vendor_retailer_detail_cubit.dart';
import '../cubit/vendor_retailer_lifecycle_notice.dart';
import '../widgets/vendor_retailer_badges.dart';
import '../widgets/vendor_retailer_copy.dart';
import '../widgets/vendor_retailer_formatting.dart';
import '../widgets/vendor_retailer_lifecycle_action.dart';
import '../widgets/vendor_retailer_lifecycle_notices.dart';
import '../widgets/vendor_retailer_shop_tile.dart';

/// One Retailer, addressed by `relationship_id` from the route.
///
/// ## Two calls, in one order, once each
///
/// [VendorRetailerDetailCubit] issues `get_vendor_retailer_detail` first and
/// `list_vendor_retailer_shops` only after a row comes back. This widget's only
/// job in that sequence is to start it exactly once — from [State.initState],
/// which runs once per mounted route, and through an idempotent `open` that
/// ignores a repeat of the id it is already showing. A rebuild, a router refresh
/// or a theme change therefore issues nothing.
///
/// ## The route parameter is an address, not a permission
///
/// Typing another Vendor's relationship id into the URL bar reaches this screen
/// and produces [VendorRetailerDetailPhase.notFound] — the same state an unknown
/// id and a malformed id produce, because SQL returns zero rows for all three.
/// The screen never says whether the Retailer exists.
class VendorRetailerDetailPage extends StatefulWidget {
  const VendorRetailerDetailPage({super.key, required this.relationshipId});

  /// The `:relationshipId` segment, verbatim. Not validated here: the repository
  /// refuses a malformed id and answers exactly as the backend answers for an id
  /// that names no row, so a mistyped URL and a foreign one are one case.
  final String relationshipId;

  @override
  State<VendorRetailerDetailPage> createState() =>
      _VendorRetailerDetailPageState();
}

class _VendorRetailerDetailPageState extends State<VendorRetailerDetailPage> {
  @override
  void initState() {
    super.initState();
    context.read<VendorRetailerDetailCubit>().open(widget.relationshipId);
  }

  @override
  void didUpdateWidget(VendorRetailerDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Navigating from one Retailer straight to another reuses this element with
    // a new parameter. `open` is idempotent for the same id, so this is a no-op
    // unless the id genuinely changed.
    if (oldWidget.relationshipId != widget.relationshipId) {
      context.read<VendorRetailerDetailCubit>().open(widget.relationshipId);
    }
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    // Reached by a deep link or a hard browser reload, where there is no list
    // page beneath this one to pop back to.
    context.go(VendorNavigation.retailers);
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<VendorRetailerDetailCubit, VendorRetailerDetailState>(
      // The shell's session isolation empties this cubit when the signed-in
      // person changes. Returning to `initial` is that event: the previous
      // Vendor's Retailer is gone, and the same route is re-read under the new
      // caller's own identity — which either loads their Retailer or, far more
      // likely, answers the non-leaking "not available".
      listenWhen:
          (
            VendorRetailerDetailState previous,
            VendorRetailerDetailState current,
          ) => current.phase == VendorRetailerDetailPhase.initial,
      listener: (BuildContext context, VendorRetailerDetailState state) =>
          context.read<VendorRetailerDetailCubit>().open(widget.relationshipId),
      builder: (BuildContext context, VendorRetailerDetailState state) {
        final VendorRetailerDetailCubit cubit = context
            .read<VendorRetailerDetailCubit>();

        if (state.phase == VendorRetailerDetailPhase.initial ||
            state.phase == VendorRetailerDetailPhase.loading) {
          return const SrLoadingView(label: VendorRetailerCopy.loadingDetail);
        }

        return SrPageBody(
          children: <Widget>[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: SrButton(
                label: VendorRetailerCopy.backToList,
                variant: SrButtonVariant.ghost,
                size: SrButtonSize.sm,
                icon: Icons.arrow_back_rounded,
                onPressed: _back,
              ),
            ),
            const SizedBox(height: SrSpacing.lg),
            ..._content(context, state, cubit),
          ],
        );
      },
    );
  }

  List<Widget> _content(
    BuildContext context,
    VendorRetailerDetailState state,
    VendorRetailerDetailCubit cubit,
  ) {
    switch (state.phase) {
      case VendorRetailerDetailPhase.initial:
      case VendorRetailerDetailPhase.loading:
        // Handled above; the loading view replaces the whole page.
        return const <Widget>[];

      case VendorRetailerDetailPhase.notFound:
        return <Widget>[
          SrEmptyState(
            icon: Icons.search_off_rounded,
            title: VendorRetailerCopy.detailNotFoundTitle,
            description: VendorRetailerCopy.detailNotFoundBody,
            // No retry: the backend answered, and it will answer the same way.
            action: SrButton(
              label: VendorRetailerCopy.backToList,
              variant: SrButtonVariant.outline,
              icon: Icons.arrow_back_rounded,
              onPressed: _back,
            ),
          ),
        ];

      case VendorRetailerDetailPhase.failed:
        return <Widget>[
          SrFailureView(failure: state.failure!, onRetry: cubit.retryDetail),
        ];

      case VendorRetailerDetailPhase.ready:
        final VendorRetailerDetail detail = state.detail!;
        final VendorRetailerLifecycleNotice? notice = state.noticeFor(
          detail.relationshipId,
        );
        return <Widget>[
          SrPageHeader(
            eyebrow: VendorRetailerCopy.detailEyebrow,
            title: detail.retailerName,
          ),
          const SizedBox(height: SrSpacing.lg),
          Wrap(
            spacing: SrSpacing.sm,
            runSpacing: SrSpacing.sm,
            children: <Widget>[
              // The badges are the canonical statuses and nothing else. They
              // are never flipped ahead of a re-read, which is why a failed
              // lifecycle write leaves them exactly as they are.
              VendorRetailerStatusBadge(
                status: detail.relationshipStatus,
                prefix: 'Relationship',
              ),
              VendorRetailerStatusBadge(
                status: detail.retailerStatus,
                prefix: 'Retailer',
              ),
              RetailerOwnerStateBadge(ownerState: detail.ownerState),
            ],
          ),
          // The acknowledgement for a committed lifecycle write, shown beside
          // the statuses it was re-read with — and only for this Retailer.
          if (notice != null) ...<Widget>[
            const SizedBox(height: SrSpacing.lg),
            VendorRetailerLifecycleNoticeAlert(notice: notice),
          ],
          // The write committed and the canonical re-read did not. The statuses
          // above may be out of date, and the honest thing is to say so and
          // offer another read — never another write.
          if (state.refreshFailure != null) ...<Widget>[
            const SizedBox(height: SrSpacing.lg),
            SrAlert(
              tone: SrAlertTone.warning,
              title: VendorRetailerCopy.staleDetailTitle,
              message: VendorRetailerCopy.staleDetailBody,
            ),
            const SizedBox(height: SrSpacing.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: SrButton(
                label: VendorRetailerCopy.reloadDetail,
                variant: SrButtonVariant.outline,
                size: SrButtonSize.sm,
                icon: Icons.refresh_rounded,
                loading: state.isRefreshing,
                onPressed: state.isRefreshing ? null : cubit.reloadCanonical,
              ),
            ),
          ],
          const SizedBox(height: SrSpacing.xxl),
          _Overview(detail: detail),
          // The lifecycle control. It renders nothing unless RETAILERS_MANAGE is
          // confirmed and the canonical pair is one this operation owns — and it
          // owns its own leading gap, so a hidden control contributes no height
          // at all rather than leaving a double space above the shops.
          VendorRetailerLifecycleSection(detail: detail),
          const SizedBox(height: SrSpacing.xxl),
          _ShopsSection(state: state, cubit: cubit),
        ];
    }
  }
}

/// The Retailer's facts, as a labelled list.
///
/// Every value here came from `get_vendor_retailer_detail`. There is no owner
/// name, email or timestamp — the deployed read does not return them, and this
/// milestone deliberately does not call the separate owner-status RPC that
/// does. The relationship id is not displayed either: it is an internal address,
/// useful in a URL and noise on a screen.
class _Overview extends StatelessWidget {
  const _Overview({required this.detail});

  final VendorRetailerDetail detail;

  @override
  Widget build(BuildContext context) {
    return SrSectionCard(
      title: VendorRetailerCopy.overviewTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Fact(
            label: VendorRetailerCopy.relationshipStatusLabel,
            value: VendorRetailerStatusBadge.labelFor(
              detail.relationshipStatus,
            ),
          ),
          _Fact(
            label: VendorRetailerCopy.retailerStatusLabel,
            value: VendorRetailerStatusBadge.labelFor(detail.retailerStatus),
          ),
          _Fact(
            label: VendorRetailerCopy.ownerLabel,
            value: RetailerOwnerStateBadge.labelFor(detail.ownerState),
          ),
          // Both nullable in `organizations`. Absence is a Retailer that never
          // recorded one, and it is said out loud rather than left blank.
          _Fact(
            label: VendorRetailerCopy.countryLabel,
            value: detail.countryCode,
          ),
          _Fact(
            label: VendorRetailerCopy.currencyLabel,
            value: detail.defaultCurrency,
          ),
          _Fact(
            label: VendorRetailerCopy.shopsLabel,
            value: formatShopCounts(detail.shopCount, detail.activeShopCount),
          ),
          _Fact(
            label: VendorRetailerCopy.onboardedLabel,
            value: formatOnboardedDate(detail.relationshipCreatedAt),
          ),
        ],
      ),
    );
  }
}

/// One label/value pair.
///
/// Stacks on a narrow phone and sits side by side once there is room, so a long
/// value never has to be truncated to fit beside its label.
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final bool present = value != null;

    final Widget labelText = Text(
      label,
      style: SrTypography.caption.copyWith(color: sr.textMuted),
    );
    final Widget valueText = Text(
      value ?? notRecorded,
      style: SrTypography.body.copyWith(
        color: present ? sr.foreground : sr.textMuted,
        fontStyle: present ? FontStyle.normal : FontStyle.italic,
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: SrSpacing.md),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          if (constraints.maxWidth < 420) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                labelText,
                const SizedBox(height: SrSpacing.xxs),
                valueText,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(width: 180, child: labelText),
              const SizedBox(width: SrSpacing.md),
              Expanded(child: valueText),
            ],
          );
        },
      ),
    );
  }
}

/// The Retailer's shops.
///
/// Degrades on its own: a shop failure leaves the overview above it untouched
/// and offers a retry for the shop read alone, because the Retailer's identity,
/// statuses and counts came from a call that succeeded and are still true.
///
/// An empty list here is trustworthy precisely because the detail read came back
/// first — zero rows from the shop read alone would be ambiguous between "no
/// shops" and "not addressable by you".
class _ShopsSection extends StatelessWidget {
  const _ShopsSection({required this.state, required this.cubit});

  final VendorRetailerDetailState state;
  final VendorRetailerDetailCubit cubit;

  @override
  Widget build(BuildContext context) {
    final VendorRetailerDetail detail = state.detail!;

    return SrSectionCard(
      title: VendorRetailerCopy.shopsSectionTitle,
      description: formatShopCounts(detail.shopCount, detail.activeShopCount),
      child: switch (state.shopsPhase) {
        VendorRetailerShopsPhase.initial ||
        VendorRetailerShopsPhase.loading => const SrSkeletonScreen(
          label: 'Loading shops',
          child: SrSkeletonList(rows: 2),
        ),
        VendorRetailerShopsPhase.failed => SrEmptyState(
          icon: Icons.cloud_off_rounded,
          title: VendorRetailerCopy.shopsUnavailableTitle,
          description: VendorRetailerCopy.shopsUnavailableBody,
          action: SrButton(
            label: VendorRetailerCopy.retryShops,
            variant: SrButtonVariant.outline,
            icon: Icons.refresh_rounded,
            onPressed: cubit.retryShops,
          ),
        ),
        VendorRetailerShopsPhase.ready when state.shops.isEmpty =>
          const SrEmptyState(
            icon: Icons.store_outlined,
            title: VendorRetailerCopy.shopsEmptyTitle,
            description: VendorRetailerCopy.shopsEmptyBody,
          ),
        VendorRetailerShopsPhase.ready => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final VendorRetailerShop shop in state.shops)
              Padding(
                padding: const EdgeInsets.only(bottom: SrSpacing.md),
                child: VendorRetailerShopTile(
                  key: ValueKey<String>(shop.shopId),
                  shop: shop,
                ),
              ),
          ],
        ),
      },
    );
  }
}
