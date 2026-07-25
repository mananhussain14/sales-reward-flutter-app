import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/shells/vendor/vendor_navigation.dart';
import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/vendor_product_assigned_retailer.dart';
import '../../../domain/entities/vendor_product_detail.dart';
import '../cubit/vendor_product_detail_cubit.dart';
import '../widgets/vendor_product_assignment_tile.dart';
import '../widgets/vendor_product_badges.dart';
import '../widgets/vendor_product_copy.dart';
import '../widgets/vendor_product_formatting.dart';

/// One product, addressed by `product_id` from the route.
///
/// ## Two calls, in one order, once each
///
/// [VendorProductDetailCubit] issues `get_vendor_product_detail` first and
/// `list_vendor_product_assigned_retailers` only after one valid row comes back.
/// This widget's only job in that sequence is to start it exactly once — from
/// [State.initState], which runs once per mounted route, and through an
/// idempotent `open` that ignores a repeat of the id it is already showing. A
/// rebuild, a router refresh or a theme change therefore issues nothing.
///
/// ## The route parameter is an address, not a permission
///
/// Typing an unknown id — or another Vendor's id, or `not-a-uuid` — into the URL
/// bar reaches this screen and produces [VendorProductDetailPhase.notFound], the
/// same state for all of them, because SQL returns zero rows for the first two
/// and the repository answers a malformed one locally without a request. The
/// screen never says whether the product exists and never says it belongs to
/// somebody else.
///
/// ## Two assignment numbers, stated as two different things
///
/// `assignment_count` includes withdrawn rows, so it is never worded as
/// "Retailers currently assigned". The screen says "3 Retailer assignments · 2
/// currently active", and both figures come from the detail row rather than from
/// counting the loaded list — the counts are the backend's, and the list is one
/// rendering of them.
class VendorProductDetailPage extends StatefulWidget {
  const VendorProductDetailPage({super.key, required this.productId});

  /// The `:productId` segment, verbatim. Not validated here: the repository
  /// refuses a malformed id and answers exactly as the backend answers for an id
  /// that names no product, so a mistyped URL, an unknown id and another
  /// Vendor's id are one case.
  final String productId;

  @override
  State<VendorProductDetailPage> createState() =>
      _VendorProductDetailPageState();
}

class _VendorProductDetailPageState extends State<VendorProductDetailPage> {
  @override
  void initState() {
    super.initState();
    context.read<VendorProductDetailCubit>().open(widget.productId);
  }

  @override
  void didUpdateWidget(VendorProductDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Navigating from one product straight to another reuses this element with
    // a new parameter. `open` is idempotent for the same id, so this is a no-op
    // unless the id genuinely changed.
    if (oldWidget.productId != widget.productId) {
      context.read<VendorProductDetailCubit>().open(widget.productId);
    }
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    // Reached by a deep link or a hard browser reload, where there is no list
    // page beneath this one to pop back to.
    context.go(VendorNavigation.products);
  }

  /// Opens the shipped Vendor Retailer detail screen.
  ///
  /// Addressed by `relationship_id` — the same `vendor_retailers.id` that
  /// `list_vendor_retailers()` and `get_vendor_retailer_detail()` already use,
  /// which is exactly why the assignment contract returns it. The Retailer
  /// organization id is never used here: it names a tenant other Vendors may
  /// also manage, and the Retailer route does not accept it.
  void _openRetailer(String relationshipId) =>
      context.go(VendorNavigation.retailerDetailPath(relationshipId));

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<VendorProductDetailCubit, VendorProductDetailState>(
      // The shell's session isolation empties this cubit when the signed-in
      // person changes. Returning to `initial` is that event: the previous
      // Vendor's product is gone, and the same route is re-read under the new
      // caller's own identity — which either loads their product or, far more
      // likely, answers the non-leaking "not available".
      listenWhen:
          (
            VendorProductDetailState previous,
            VendorProductDetailState current,
          ) => current.phase == VendorProductDetailPhase.initial,
      listener: (BuildContext context, VendorProductDetailState state) =>
          context.read<VendorProductDetailCubit>().open(widget.productId),
      builder: (BuildContext context, VendorProductDetailState state) {
        final VendorProductDetailCubit cubit = context
            .read<VendorProductDetailCubit>();

        if (state.phase == VendorProductDetailPhase.initial ||
            state.phase == VendorProductDetailPhase.loading) {
          return const SrLoadingView(label: VendorProductCopy.loadingDetail);
        }

        return SrPageBody(
          children: <Widget>[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Semantics(
                button: true,
                label: VendorProductCopy.backToList,
                child: SrButton(
                  label: VendorProductCopy.backToList,
                  variant: SrButtonVariant.ghost,
                  size: SrButtonSize.sm,
                  icon: Icons.arrow_back_rounded,
                  onPressed: _back,
                ),
              ),
            ),
            const SizedBox(height: SrSpacing.lg),
            ..._content(state, cubit),
          ],
        );
      },
    );
  }

  List<Widget> _content(
    VendorProductDetailState state,
    VendorProductDetailCubit cubit,
  ) {
    switch (state.phase) {
      case VendorProductDetailPhase.initial:
      case VendorProductDetailPhase.loading:
        // Handled above; the loading view replaces the whole page.
        return const <Widget>[];

      case VendorProductDetailPhase.notFound:
        return <Widget>[
          SrEmptyState(
            icon: Icons.search_off_rounded,
            title: VendorProductCopy.detailNotFoundTitle,
            description: VendorProductCopy.detailNotFoundBody,
            // No retry: the backend answered, and it will answer the same way.
            action: SrButton(
              label: VendorProductCopy.backToList,
              variant: SrButtonVariant.outline,
              icon: Icons.arrow_back_rounded,
              onPressed: _back,
            ),
          ),
        ];

      case VendorProductDetailPhase.failed:
        return <Widget>[
          SrFailureView(failure: state.failure!, onRetry: cubit.retryDetail),
        ];

      case VendorProductDetailPhase.ready:
        final VendorProductDetail detail = state.detail!;
        return <Widget>[
          SrPageHeader(
            eyebrow: VendorProductCopy.detailEyebrow,
            title: detail.productName,
          ),
          const SizedBox(height: SrSpacing.lg),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: VendorProductStatusBadge(status: detail.status),
          ),
          const SizedBox(height: SrSpacing.xxl),
          _Overview(detail: detail),
          const SizedBox(height: SrSpacing.xxl),
          _AssignmentsSection(
            state: state,
            cubit: cubit,
            onOpenRetailer: _openRetailer,
          ),
        ];
    }
  }
}

/// The product's own facts, as a labelled list.
///
/// Every value came from `get_vendor_product_detail`. There is no
/// `vendor_organization_id`, no creator, no audit metadata, no category, no
/// price, no reward, no incentive, no inventory, no shop assignment and **no
/// image** — the deployed read returns none of them, and most do not exist as
/// columns anywhere in the schema. The product id is not displayed either: it is
/// an internal address, useful in a URL and noise on a screen, and the product
/// code is the identifier a person actually uses.
///
/// Nullable fields are stated as absent rather than omitted here. On a card,
/// omitting them saves a row; on the detail screen, "Barcode — Not recorded" is
/// the answer to a question the reader came to ask.
class _Overview extends StatelessWidget {
  const _Overview({required this.detail});

  final VendorProductDetail detail;

  @override
  Widget build(BuildContext context) {
    return SrSectionCard(
      title: VendorProductCopy.overviewTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Fact(label: VendorProductCopy.codeLabel, value: detail.productCode),
          _Fact(
            label: VendorProductCopy.barcodeLabel,
            value: formatOptional(detail.barcode),
            muted: detail.barcode == null,
          ),
          _Fact(
            label: VendorProductCopy.brandLabel,
            value: formatOptional(detail.brand),
            muted: detail.brand == null,
          ),
          _Fact(
            label: VendorProductCopy.descriptionLabel,
            value: formatOptional(detail.description),
            muted: detail.description == null,
          ),
          // Repeated as a labelled fact as well as a pill, so the status is
          // legible to a reader scanning the fields rather than the chrome.
          _Fact(
            label: VendorProductCopy.statusLabel,
            value: VendorProductStatusBadge.labelFor(detail.status),
          ),
          // Both figures in one sentence, so neither is ever met alone.
          _Fact(
            label: VendorProductCopy.assignmentsLabel,
            value: formatAssignmentSummary(
              detail.assignmentCount,
              detail.activeAssignmentCount,
            ),
          ),
          _Fact(
            label: VendorProductCopy.createdLabel,
            value: formatProductDate(detail.createdAt),
          ),
          _Fact(
            label: VendorProductCopy.updatedLabel,
            value: formatProductDate(detail.updatedAt),
          ),
        ],
      ),
    );
  }
}

/// The Retailers this product has been assigned to.
///
/// Its own section, loaded by its own call, and degrading on its own: a product
/// whose assignments could not be read still has a name, a code, a status and
/// two counts that came from a call which succeeded, and the retry here re-reads
/// **only** the companion.
///
/// An empty list here is trustworthy precisely because the detail read came back
/// first — zero rows from the assignment read alone would be ambiguous between
/// "never assigned" and "not addressable by you".
///
/// ## An inactive product changes nothing here
///
/// `set_vendor_product_status` does not cascade, so an `INACTIVE` product keeps
/// every assignment row and both counts. This section therefore renders
/// identically whatever the product's status, and nothing implies assignments
/// are disabled — the backend does not say so, and inferring it would be this
/// client deciding a rule it cannot see.
///
/// There is no assign, withdraw or edit action, and no disabled one either.
class _AssignmentsSection extends StatelessWidget {
  const _AssignmentsSection({
    required this.state,
    required this.cubit,
    required this.onOpenRetailer,
  });

  final VendorProductDetailState state;
  final VendorProductDetailCubit cubit;
  final ValueChanged<String> onOpenRetailer;

  @override
  Widget build(BuildContext context) {
    final VendorProductDetail detail = state.detail!;

    return SrSectionCard(
      title: VendorProductCopy.assignmentsTitle,
      description: VendorProductCopy.assignmentsDescription,
      child: switch (state.assignmentsPhase) {
        VendorProductAssignmentsPhase.initial ||
        VendorProductAssignmentsPhase.loading => const SrSkeletonScreen(
          label: VendorProductCopy.loadingAssignments,
          child: SrSkeletonList(rows: 3),
        ),

        VendorProductAssignmentsPhase.failed => SrEmptyState(
          icon: Icons.cloud_off_rounded,
          title: VendorProductCopy.assignmentsUnavailableTitle,
          description: VendorProductCopy.assignmentsUnavailableBody,
          action: SrButton(
            label: VendorProductCopy.retryAssignments,
            variant: SrButtonVariant.outline,
            icon: Icons.refresh_rounded,
            onPressed: cubit.retryAssignments,
          ),
        ),

        // A real, successful "this product has never been assigned to anybody" —
        // distinguishable from "this is not your product" only because the
        // detail read came back first.
        VendorProductAssignmentsPhase.ready when state.assignments.isEmpty =>
          const SrEmptyState(
            icon: Icons.storefront_outlined,
            tone: SrTone.slate,
            title: VendorProductCopy.assignmentsEmptyTitle,
            description: VendorProductCopy.assignmentsEmptyBody,
          ),

        VendorProductAssignmentsPhase.ready => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Every returned row is still rendered and both counts are still the
            // backend's; the note only says the two reads disagreed.
            if (state.assignmentCountDisagrees) ...<Widget>[
              const SrAlert(
                tone: SrAlertTone.warning,
                title: VendorProductCopy.countMismatchTitle,
                message: VendorProductCopy.countMismatchBody,
              ),
              const SizedBox(height: SrSpacing.lg),
            ],
            // Explained once, above the rows it explains, rather than repeated
            // on each row that has lost its relationship.
            if (state.hasUnlinkedAssignments) ...<Widget>[
              const SrAlert(
                message: VendorProductCopy.relationshipUnavailableNote,
              ),
              const SizedBox(height: SrSpacing.lg),
            ],
            // The order the backend sent, preserved: `retailer_name` then
            // `retailer_organization_id`. Nothing is grouped, sorted or filtered
            // — an inactive row keeps its place in the sequence, and the number
            // of rows here is `assignment_count` by construction.
            //
            // Keyed by the Retailer organization id, which is the only value
            // guaranteed present and unique per row: there is at most one
            // assignment per (product, Retailer), and `relationship_id` is
            // nullable.
            for (final VendorProductAssignedRetailer assignment
                in state.assignments)
              VendorProductAssignmentTile(
                key: ValueKey<String>(assignment.retailerOrganizationId),
                assignment: assignment,
                onOpenRetailer: onOpenRetailer,
              ),
            Text(
              formatAssignmentSummary(
                detail.assignmentCount,
                detail.activeAssignmentCount,
              ),
              style: SrTypography.caption.copyWith(color: context.sr.textMuted),
            ),
          ],
        ),
      },
    );
  }
}

/// One label/value pair.
///
/// Stacks on a narrow phone and sits side by side once there is room, so a long
/// value never has to be truncated to fit beside its label. The pair is spoken
/// as one node so a screen reader reads "Barcode: Not recorded" rather than two
/// disconnected fragments.
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.muted = false});

  final String label;
  final String value;

  /// Renders the value in the muted, italic treatment reserved for "there is no
  /// value here" phrases.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    final Widget labelText = Text(
      label,
      style: SrTypography.caption.copyWith(color: sr.textMuted),
    );
    final Widget valueText = Text(
      value,
      style: SrTypography.body.copyWith(
        color: muted ? sr.textMuted : sr.foreground,
        fontStyle: muted ? FontStyle.italic : FontStyle.normal,
      ),
    );

    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Padding(
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
                SizedBox(width: 200, child: labelText),
                const SizedBox(width: SrSpacing.md),
                Expanded(child: valueText),
              ],
            );
          },
        ),
      ),
    );
  }
}
