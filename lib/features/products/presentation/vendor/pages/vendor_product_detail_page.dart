import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/shells/vendor/vendor_navigation.dart';
import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/vendor_product_assigned_retailer.dart';
import '../../../domain/entities/vendor_product_detail.dart';
import '../../../domain/entities/vendor_product_status.dart';
import '../cubit/vendor_product_assignment_cubit.dart';
import '../cubit/vendor_product_detail_cubit.dart';
import '../cubit/vendor_product_write_notice.dart';
import '../widgets/vendor_product_assign_retailer_dialog.dart';
import '../widgets/vendor_product_assignment_action.dart';
import '../widgets/vendor_product_assignment_tile.dart';
import '../widgets/vendor_product_badges.dart';
import '../widgets/vendor_product_copy.dart';
import '../widgets/vendor_product_formatting.dart';
import '../widgets/vendor_product_status_action.dart';
import '../widgets/vendor_product_write_notices.dart';

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
///
/// ## Two write affordances, kept apart on purpose
///
/// **Edit** opens a form for the four mutable display fields.
/// **Activate / Deactivate** is a separate section with its own confirmation,
/// because `update_vendor_product` never writes `status` and
/// `set_vendor_product_status` never writes the display fields — two operations, two
/// RPCs, and a screen that merged them would suggest they are one decision.
///
/// **Assign / Reactivate / Withdraw** is a third group, in the assigned-Retailer
/// section, on a **different permission** (`PRODUCT_RETAILER_ASSIGN`, not
/// `PRODUCTS_MANAGE`). It is kept there rather than promoted to the header because
/// every one of its actions is about one Retailer, and because nothing on this screen
/// may infer "may edit this product, therefore may assign it" — the backend proved
/// those two entitlements are independent in both directions.
///
/// There is **no Delete**: no delete control, action, RPC or `DELETE` statement
/// exists anywhere in this product, and a disabled one would advertise a capability
/// that will never arrive. There is **no bulk assignment** either — no multi-select,
/// no assign-all — because no bulk function exists and N calls would not be one.
///
/// Every affordance here is a presentation guard. Whether this caller may write is
/// decided in SQL on every call, by permissions this client never names, and a
/// refusal arrives as one generic wording covering an unauthorized caller, an unknown
/// product and another Vendor's product alike.
///
/// ## After a write, the values come from the backend
///
/// The three write RPCs return `uuid`, `void` and `void` — never a product row. So an
/// acknowledged write is always accompanied by a fresh `get_vendor_product_detail`,
/// and the fields, the status pill and both counts on this screen are that read's
/// answer. Nothing here echoes what was submitted, flips a status ahead of the
/// backend, or recomputes a count.
///
/// If that follow-up read fails, the write still stands: the product already on
/// screen is kept, the screen says it may be out of date, and it offers a Reload. It
/// never says the save failed, because it did not.
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
        final VendorProductWriteNotice? notice = state.currentNotice;

        return <Widget>[
          SrPageHeader(
            eyebrow: VendorProductCopy.detailEyebrow,
            title: detail.productName,
            actions: <Widget>[
              Semantics(
                button: true,
                label: VendorProductCopy.editSemantics,
                child: SrButton(
                  label: VendorProductCopy.edit,
                  variant: SrButtonVariant.outline,
                  icon: Icons.edit_outlined,
                  onPressed: () => context.go(
                    VendorNavigation.productEditPath(detail.productId),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: SrSpacing.lg),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: VendorProductStatusBadge(status: detail.status),
          ),
          // The acknowledgement for a write that landed, above the values it was
          // read back with. Rendered only while it names the product on screen, so
          // it can never start describing whatever the reader opened next.
          if (notice != null) ...<Widget>[
            const SizedBox(height: SrSpacing.xl),
            VendorProductWriteNoticeAlert(notice: notice),
          ],
          // A write that landed whose follow-up read did not. The product below is
          // the last thing the backend actually said; the change is saved either way.
          // The wording names which read went stale, because after an assignment
          // it is the list and the counts rather than the product's own fields.
          if (state.refreshFailure != null) ...<Widget>[
            const SizedBox(height: SrSpacing.xl),
            SrAlert(
              tone: SrAlertTone.warning,
              title: state.refreshIncludesAssignments
                  ? VendorProductCopy.staleAfterAssignmentTitle
                  : VendorProductCopy.staleAfterWriteTitle,
              message: state.refreshIncludesAssignments
                  ? VendorProductCopy.staleAfterAssignmentBody
                  : VendorProductCopy.staleAfterWriteBody,
            ),
            const SizedBox(height: SrSpacing.md),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Semantics(
                button: true,
                label: VendorProductCopy.reloadSemantics,
                child: SrButton(
                  label: VendorProductCopy.reload,
                  loadingLabel: VendorProductCopy.reloading,
                  variant: SrButtonVariant.outline,
                  size: SrButtonSize.sm,
                  icon: Icons.refresh_rounded,
                  loading: state.isRefreshing,
                  // Null while a reload is running: the cubit refuses a second one
                  // regardless, and a re-read is not a re-write, so repeating it
                  // could not double anything — it would only waste a call. It
                  // repeats the scope that failed rather than always re-reading
                  // everything.
                  onPressed: state.isRefreshing
                      ? null
                      : () => cubit.reloadCanonical(),
                ),
              ),
            ),
          ]
          // Progress for a re-read that has not failed. Beside the product rather
          // than in place of it: every field stays legible, because a saved change
          // must not look like a page reset.
          else if (state.isRefreshing) ...<Widget>[
            const SizedBox(height: SrSpacing.xl),
            SrAlert(
              message: state.refreshIncludesAssignments
                  ? VendorProductCopy.refreshingAssignments
                  : VendorProductCopy.refreshingProduct,
            ),
          ],
          const SizedBox(height: SrSpacing.xxl),
          _Overview(detail: detail),
          const SizedBox(height: SrSpacing.xxl),
          VendorProductStatusAction(detail: detail),
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
/// ## An inactive product keeps every assignment, and can still end one
///
/// `set_vendor_product_status` does not cascade, so an `INACTIVE` product keeps
/// every assignment row and both counts, and every row is still rendered. What
/// an inactive product *cannot* do is receive a new assignment or have a
/// withdrawn one reactivated — the deployed function refuses both with `55000` —
/// so the Assign control is replaced by a sentence saying so, once, above the
/// list rather than on every row it affects. **Withdrawal stays available**,
/// because the withdrawal function deliberately requires no status to be active.
///
/// Nothing here is an authorization. The controls are gated on
/// `PRODUCT_RETAILER_ASSIGN` in SQL, on every call, by a permission this client
/// never names — and it is a *different* permission from the one governing the
/// Edit and Activate controls above, so nothing on this screen infers one from
/// the other.
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _AssignmentWriteBanner(productId: detail.productId),
          _AssignAction(detail: detail, assignments: state.assignments),
          const SizedBox(height: SrSpacing.lg),
          _AssignmentList(
            state: state,
            cubit: cubit,
            onOpenRetailer: onOpenRetailer,
          ),
        ],
      ),
    );
  }
}

/// The **refusal** for the assignment write this screen just attempted.
///
/// Only the refusal. A successful transition is acknowledged once, at the top of
/// the product, beside the canonical values it was read back with — the same
/// place an edit and a status change are acknowledged, and the only place that
/// can honestly claim what the product now looks like. Rendering it here as well
/// would say the same sentence twice.
///
/// A refusal belongs here instead, next to the assignments it did **not**
/// change, which are still correct exactly as they are.
///
/// Bound to the product on screen, so a refusal that landed for another product
/// can never appear under this one.
class _AssignmentWriteBanner extends StatelessWidget {
  const _AssignmentWriteBanner({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<
      VendorProductAssignmentCubit,
      VendorProductAssignmentState
    >(
      builder: (BuildContext context, VendorProductAssignmentState state) {
        if (!state.hasFailureFor(productId)) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SrAlert(
              tone: SrAlertTone.error,
              title: VendorProductCopy.assignmentFailedTitle,
              message: VendorProductCopy.assignmentFailedBody,
            ),
            const SizedBox(height: SrSpacing.md),
            // The reason beneath the headline, so a reader learns both the
            // effect and the cause without either being guessed at.
            VendorProductAssignmentWriteAlert(failure: state.failure!),
            const SizedBox(height: SrSpacing.lg),
          ],
        );
      },
    );
  }
}

/// The control that opens the Retailer picker — or the sentence that replaces
/// it.
///
/// A presentation mirror of the deployed gate, and knowingly only that: the
/// database refuses the call regardless, so a client that ignored the rule would
/// get `55000` rather than an unauthorized write.
class _AssignAction extends StatelessWidget {
  const _AssignAction({required this.detail, required this.assignments});

  final VendorProductDetail detail;
  final List<VendorProductAssignedRetailer> assignments;

  @override
  Widget build(BuildContext context) {
    if (!detail.status.isActive) {
      return SrAlert(
        message: detail.status == VendorProductStatus.inactive
            ? VendorProductCopy.assignUnavailableInactive
            // A status token this build does not recognise. No control, because
            // the rule for an unfamiliar status is not knowable.
            : VendorProductCopy.assignUnavailableUnknownStatus,
      );
    }

    return BlocBuilder<
      VendorProductAssignmentCubit,
      VendorProductAssignmentState
    >(
      builder: (BuildContext context, VendorProductAssignmentState state) {
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: Semantics(
            button: true,
            label: VendorProductCopy.assignRetailerSemantics,
            child: SrButton(
              label: VendorProductCopy.assignRetailer,
              variant: SrButtonVariant.outline,
              icon: Icons.add_link_rounded,
              // Disabled while a write is settling: opening a picker composed
              // from a history that is about to be re-read would offer a verdict
              // already out of date.
              onPressed: state.isBusy
                  ? null
                  : () => showVendorProductAssignRetailerDialog(
                      context,
                      productId: detail.productId,
                      assignments: assignments,
                    ),
            ),
          ),
        );
      },
    );
  }
}

/// The assignment history itself.
class _AssignmentList extends StatelessWidget {
  const _AssignmentList({
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

    return switch (state.assignmentsPhase) {
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
              // Withdraw, Reactivate, a neutral explanation, or nothing —
              // decided from this row and the product's own status, and never
              // from a permission this client cannot see.
              action: VendorProductAssignmentRowAction(
                productId: detail.productId,
                productStatus: detail.status,
                assignment: assignment,
              ),
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
    };
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
