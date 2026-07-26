import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/vendor_product_assigned_retailer.dart';
import '../../../domain/entities/vendor_product_assignment_action.dart';
import '../../../domain/entities/vendor_product_assignment_candidate.dart';
import '../cubit/vendor_product_assignment_cubit.dart';
import 'vendor_product_assignment_confirmations.dart';
import 'vendor_product_copy.dart';
import 'vendor_product_formatting.dart';

/// Opens the Retailer picker for one Product, and cleans up after it.
///
/// The candidate read starts **before** the dialog is shown, so the list is
/// already in flight while the surface appears rather than after it. Closing the
/// picker drops the candidates: eligibility is exactly the thing that goes
/// stale, and a reopened picker asks again rather than offering a verdict about
/// a relationship that may have been suspended in between.
///
/// [assignments] is the canonical assignment history the Product screen already
/// holds. It is passed in rather than re-read so the picker cannot disagree with
/// the list underneath it about which Retailers already hold this Product.
Future<void> showVendorProductAssignRetailerDialog(
  BuildContext context, {
  required String productId,
  required List<VendorProductAssignedRetailer> assignments,
}) async {
  final VendorProductAssignmentCubit cubit = context
      .read<VendorProductAssignmentCubit>();

  unawaitedLoad(cubit, productId: productId, assignments: assignments);

  await showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) =>
        BlocProvider<VendorProductAssignmentCubit>.value(
          // `showDialog` inserts the route on the **root** navigator, which is above
          // the Vendor shell that owns this cubit — so the value is carried across
          // explicitly rather than looked up from a context that could not see it.
          value: cubit,
          child: _AssignRetailerDialog(productId: productId),
        ),
  );

  cubit.closeCandidates();
}

/// Starts the candidate read without awaiting it.
///
/// Named rather than inlined so the deliberate absence of an `await` reads as a
/// decision: the dialog renders its own loading state from the cubit, and
/// awaiting here would delay the surface until the directory answered.
void unawaitedLoad(
  VendorProductAssignmentCubit cubit, {
  required String productId,
  required List<VendorProductAssignedRetailer> assignments,
}) {
  cubit.loadCandidates(productId: productId, assignments: assignments);
}

/// The picker itself.
///
/// ## What may be selected, and how
///
/// Every Retailer this Vendor manages is listed, plus any historical pairing the
/// directory no longer contains — nothing is hidden. Only the two actionable
/// states carry a control, and each row states what is true of it in a sentence
/// rather than relying on the presence or absence of a button.
///
/// Selection always carries `retailer_organization_id`, taken verbatim from a
/// trusted read. **No Retailer is ever selected by display name**, two Retailers
/// may legitimately share one, and **no uuid is displayed** — it is an address,
/// and an address on screen is noise.
///
/// **No relationship id is carried anywhere on this surface.** The assignment
/// table stores no such column, and the write has no parameter for one.
///
/// ## One at a time
///
/// There is no multi-select, no "assign all" and no checkbox column: the backend
/// offers no bulk function, and N calls would not be one transaction. A
/// confirmation is required per assignment, and while one is being written every
/// control on the list is disabled — so a double tap, or two rows tapped in
/// quick succession, cannot start a second write.
class _AssignRetailerDialog extends StatelessWidget {
  const _AssignRetailerDialog({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final Size screen = MediaQuery.sizeOf(context);

    return Dialog(
      insetPadding: const EdgeInsets.all(SrSpacing.lg),
      child: ConstrainedBox(
        // Bounded in both directions: wide enough to read a Retailer name and a
        // sentence beside a button on a tablet or the web, and never wider than
        // a comfortable measure; tall enough to show several rows and never
        // taller than the viewport, so the list scrolls inside the dialog rather
        // than pushing its own header off screen.
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: screen.height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.all(SrSpacing.xl),
          child:
              BlocBuilder<
                VendorProductAssignmentCubit,
                VendorProductAssignmentState
              >(
                builder: (BuildContext context, VendorProductAssignmentState state) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Semantics(
                        header: true,
                        child: Text(
                          VendorProductCopy.assignSheetTitle,
                          style: SrTypography.sectionTitle.copyWith(
                            color: sr.foreground,
                          ),
                        ),
                      ),
                      const SizedBox(height: SrSpacing.xs),
                      Text(
                        VendorProductCopy.assignSheetDescription,
                        style: SrTypography.caption.copyWith(
                          color: sr.textMuted,
                        ),
                      ),
                      const SizedBox(height: SrSpacing.lg),
                      // Offered only once there is something to narrow. A search box
                      // above an outage or an empty directory is a control that
                      // cannot do anything.
                      if (state.candidatesPhase ==
                              VendorProductAssignmentCandidatesPhase.ready &&
                          state.candidates.isNotEmpty) ...<Widget>[
                        _CandidateSearchField(
                          term: state.searchTerm,
                          onChanged: context
                              .read<VendorProductAssignmentCubit>()
                              .searchCandidates,
                        ),
                        const SizedBox(height: SrSpacing.md),
                      ],
                      Flexible(
                        child: _Body(productId: productId, state: state),
                      ),
                      const SizedBox(height: SrSpacing.lg),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text(VendorProductCopy.close),
                        ),
                      ),
                    ],
                  );
                },
              ),
        ),
      ),
    );
  }
}

/// The list, or whatever stands in for it.
class _Body extends StatelessWidget {
  const _Body({required this.productId, required this.state});

  final String productId;
  final VendorProductAssignmentState state;

  @override
  Widget build(BuildContext context) {
    switch (state.candidatesPhase) {
      case VendorProductAssignmentCandidatesPhase.initial:
      case VendorProductAssignmentCandidatesPhase.loading:
        return const SrSkeletonScreen(
          label: VendorProductCopy.loadingCandidates,
          child: SrSkeletonList(rows: 3),
        );

      case VendorProductAssignmentCandidatesPhase.failed:
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SrEmptyState(
                icon: Icons.cloud_off_rounded,
                title: VendorProductCopy.candidatesUnavailableTitle,
                // Never worded as a denial and never as an empty directory: a
                // read that did not answer is neither.
                description: VendorProductCopy.candidatesUnavailableBody,
                action: SrButton(
                  label: VendorProductCopy.retryCandidates,
                  variant: SrButtonVariant.outline,
                  icon: Icons.refresh_rounded,
                  // The retry is not offered here as a re-read of the whole
                  // picker's inputs: the assignment history it was composed with
                  // is the Product screen's, and reopening the picker is the
                  // path that re-reads both together.
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        );

      case VendorProductAssignmentCandidatesPhase.ready:
        if (state.hasNoCandidates) {
          return const SingleChildScrollView(
            child: SrEmptyState(
              icon: Icons.storefront_outlined,
              tone: SrTone.slate,
              title: VendorProductCopy.candidatesEmptyTitle,
              description: VendorProductCopy.candidatesEmptyBody,
            ),
          );
        }
        if (state.hasNoMatches) {
          return const SingleChildScrollView(
            child: SrEmptyState(
              icon: Icons.search_off_rounded,
              tone: SrTone.slate,
              title: VendorProductCopy.candidatesNoMatchesTitle,
              description: VendorProductCopy.candidatesNoMatchesBody,
            ),
          );
        }

        final List<VendorProductAssignmentCandidate> visible =
            state.visibleCandidates;

        return ListView.builder(
          shrinkWrap: true,
          itemCount: visible.length,
          itemBuilder: (BuildContext context, int index) => _CandidateTile(
            productId: productId,
            candidate: visible[index],
            // Keyed by the Retailer organization id: the one value guaranteed
            // present and unique per row.
            key: ValueKey<String>(visible[index].retailerOrganizationId),
            anyWriteInFlight: state.isBusy,
            isThisPairingBusy: state.isBusyForPairing(
              productId,
              visible[index].retailerOrganizationId,
            ),
          ),
        );
    }
  }
}

/// The picker's local search field.
class _CandidateSearchField extends StatefulWidget {
  const _CandidateSearchField({required this.term, required this.onChanged});

  final String term;
  final ValueChanged<String> onChanged;

  @override
  State<_CandidateSearchField> createState() => _CandidateSearchFieldState();
}

class _CandidateSearchFieldState extends State<_CandidateSearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.term,
  );

  @override
  void didUpdateWidget(_CandidateSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keeps the field in step when the term is cleared from outside — by a
    // session change wiping the cubit, or by the picker being reopened. Guarded
    // on inequality so typing is never fought by a rebuild.
    if (widget.term != _controller.text) {
      _controller.text = widget.term;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SrTextField(
      label: VendorProductCopy.candidateSearchLabel,
      controller: _controller,
      placeholder: VendorProductCopy.candidateSearchPlaceholder,
      hint: VendorProductCopy.candidateSearchHint,
      showOptionalMarker: false,
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.search,
      onChanged: widget.onChanged,
    );
  }
}

/// One Retailer, as a choice.
///
/// Its state is carried by a sentence and by whether a control is present —
/// never by colour alone — and the whole row is spoken as one node followed by
/// its own button, so a listener hears the Retailer, what is true of it, and
/// what may be done, in that order.
class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    super.key,
    required this.productId,
    required this.candidate,
    required this.anyWriteInFlight,
    required this.isThisPairingBusy,
  });

  final String productId;
  final VendorProductAssignmentCandidate candidate;

  /// Whether **any** assignment write is running. Every control on the list is
  /// disabled while one is, so two rows tapped in quick succession cannot start
  /// two writes.
  final bool anyWriteInFlight;

  /// Whether the write in flight is this row's, which is the only row that shows
  /// progress.
  final bool isThisPairingBusy;

  /// The one-line statement of what is true of this Retailer.
  static String stateLabelFor(VendorProductAssignmentCandidate candidate) =>
      switch (candidate.state) {
        VendorProductAssignmentCandidateState.assignable =>
          VendorProductCopy.candidateAssignable,
        VendorProductAssignmentCandidateState.reactivatable =>
          VendorProductCopy.candidateReactivatable,
        VendorProductAssignmentCandidateState.alreadyAssigned =>
          VendorProductCopy.candidateAlreadyAssigned,
        VendorProductAssignmentCandidateState.ineligible =>
          VendorProductCopy.candidateIneligible,
        VendorProductAssignmentCandidateState.relationshipUnavailable =>
          VendorProductCopy.candidateRelationshipUnavailable,
      };

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final bool actionable = candidate.isActionable;
    final VendorProductAssignmentAction action =
        candidate.state == VendorProductAssignmentCandidateState.reactivatable
        ? VendorProductAssignmentAction.reactivate
        : VendorProductAssignmentAction.assign;

    final String stateLabel = stateLabelFor(candidate);
    // The previous activation date, offered as context on a row that can be
    // reactivated. Never on a row with no history, and never spoken as a
    // first-assignment date.
    final String? historyLine =
        candidate.state ==
                VendorProductAssignmentCandidateState.reactivatable &&
            candidate.assignedAt != null
        ? '${VendorProductCopy.assignedOnLabel} '
              '${formatProductDate(candidate.assignedAt!)}'
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: SrSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            label: <String>[
              candidate.retailerName,
              stateLabel,
              ?historyLine,
            ].join('. '),
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  candidate.retailerName,
                  style: SrTypography.body.copyWith(
                    color: actionable ? sr.foreground : sr.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: SrSpacing.xxs),
                Text(
                  stateLabel,
                  style: SrTypography.caption.copyWith(color: sr.textMuted),
                ),
                if (historyLine != null) ...<Widget>[
                  const SizedBox(height: SrSpacing.xxs),
                  Text(
                    historyLine,
                    style: SrTypography.caption.copyWith(color: sr.textMuted),
                  ),
                ],
              ],
            ),
          ),
          if (actionable) ...<Widget>[
            const SizedBox(height: SrSpacing.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Semantics(
                button: true,
                label: switch (action) {
                  VendorProductAssignmentAction.reactivate =>
                    '${VendorProductCopy.reactivateSemantics} '
                        '${candidate.retailerName}.',
                  _ =>
                    '${VendorProductCopy.candidateAssignAction}: '
                        '${candidate.retailerName}. Asks for confirmation '
                        'first.',
                },
                child: SrButton(
                  label: action == VendorProductAssignmentAction.reactivate
                      ? VendorProductCopy.candidateReactivateAction
                      : VendorProductCopy.candidateAssignAction,
                  loadingLabel:
                      action == VendorProductAssignmentAction.reactivate
                      ? VendorProductCopy.reactivating
                      : VendorProductCopy.assigning,
                  variant: SrButtonVariant.outline,
                  size: SrButtonSize.sm,
                  icon: action == VendorProductAssignmentAction.reactivate
                      ? Icons.restart_alt_rounded
                      : Icons.add_link_rounded,
                  loading: isThisPairingBusy,
                  onPressed: anyWriteInFlight
                      ? null
                      : () => _confirmAndApply(context, action),
                ),
              ),
            ),
          ],
          const SizedBox(height: SrSpacing.sm),
          Divider(height: 1, color: sr.border),
        ],
      ),
    );
  }

  Future<void> _confirmAndApply(
    BuildContext context,
    VendorProductAssignmentAction action,
  ) async {
    final VendorProductAssignmentCubit cubit = context
        .read<VendorProductAssignmentCubit>();
    final NavigatorState navigator = Navigator.of(context);

    final bool confirmed = await confirmVendorProductAssignment(
      context,
      action: action,
      retailerName: candidate.retailerName,
    );
    if (!confirmed) {
      // No RPC, no state change, and the picker stays open on the same list.
      return;
    }

    await cubit.apply(
      productId: productId,
      // The organization id from the trusted read, and never the name a person
      // searched by.
      retailerOrganizationId: candidate.retailerOrganizationId,
      action: action,
    );

    // The picker closes whatever the outcome, because the Product screen below
    // is where both are answered: a success is acknowledged beside the re-read
    // history it changed, and a refusal beside the assignments it did not.
    // Leaving the picker open over a list composed *before* the attempt would
    // show a verdict that is no longer current.
    if (navigator.mounted) {
      navigator.pop();
    }
  }
}
