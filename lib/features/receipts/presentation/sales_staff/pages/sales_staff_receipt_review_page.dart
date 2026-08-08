import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/shells/sales_staff/sales_staff_navigation.dart';
import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../../auth/domain/entities/portal_kind.dart';
import '../../../domain/entities/receipt_extraction.dart';
import '../../../domain/entities/receipt_extraction_problem.dart';
import '../cubit/receipt_product_selection_cubit.dart';
import '../cubit/receipt_review_cubit.dart';
import '../widgets/receipt_final_confirmation_section.dart';
import '../widgets/receipt_legacy_confirmation_section.dart';
import '../widgets/receipt_submitted_proposal_section.dart';
import '../widgets/receipt_product_catalogue_section.dart';
import '../widgets/receipt_selected_products_section.dart';
import '../widgets/receipt_review_confirmed_card.dart';
import '../widgets/receipt_review_copy.dart';
import '../widgets/receipt_review_form.dart';
import '../widgets/receipt_review_line_items.dart';
import '../widgets/receipt_review_preview.dart';
import '../widgets/receipt_review_status_panel.dart';
import '../widgets/receipt_review_warnings.dart';

/// Review one submitted receipt, correct what was read, and confirm it.
///
/// ## The whole flow, in the order it appears
///
/// 1. **Status** — what the attempt is doing, what it has cost, and whether
///    another may be asked for.
/// 2. **Extracted items** — every line the provider read, expanded, and gating
///    nothing. First among the content sections on purpose: it is what the
///    person came to see, and what step 5 will ask them to confirm. Asking for
///    a confirmation above the figures being confirmed had it backwards.
/// 3. **Your receipt** — the private image, through a capability that lives for
///    about two minutes and is never written down.
/// 4. **Things to check** — the reading's own warnings, as sentences.
/// 5. **Receipt details** — the eight values a confirmation carries, editable.
///
/// ## Why this screen is stateful
///
/// Three reasons, and each is a rule rather than a convenience:
///
/// * **One request per screen.** `start()` is called from `initState` behind its
///   own guard, so a rebuild cannot ask for a second extraction attempt.
/// * **Polling stops when the app does.** The observer pauses the loop when the
///   application leaves the foreground and resumes it on return, so a phone in
///   somebody's pocket is not asking every three seconds.
/// * **The capability is dropped on the way out.** `dispose` forgets the preview
///   URL before the provider closes the cubit, so it does not sit in a state
///   object waiting to be collected.
///
/// ## What is deliberately absent
///
/// No product, reward or claim of any kind. No storage path, bucket, file hash,
/// provider name, operation id, claim token, SQLSTATE or internal failure code —
/// none of them reaches this layer to be rendered. No edit control after a
/// confirmation, because a confirmation is immutable and the affordance could
/// only ever fail.
class SalesStaffReceiptReviewPage extends StatefulWidget {
  const SalesStaffReceiptReviewPage({super.key, required this.submissionId});

  final String submissionId;

  @override
  State<SalesStaffReceiptReviewPage> createState() =>
      _SalesStaffReceiptReviewPageState();
}

class _SalesStaffReceiptReviewPageState
    extends State<SalesStaffReceiptReviewPage>
    with WidgetsBindingObserver {
  late final ReceiptReviewCubit _cubit;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cubit = context.read<ReceiptReviewCubit>();
    // Guarded inside the cubit, so a rebuilt element cannot consume a second
    // attempt.
    _cubit.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _cubit.setAppActive(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Runs before the route's provider closes the cubit: the credential leaves
    // memory as the screen does, not whenever the object is collected.
    _cubit.forgetPreview();
    super.dispose();
  }

  void _backToHistory() => context.go(SalesStaffNavigation.history);

  /// Takes ONE frozen reading of the proposal and hands it to the cubit that
  /// owns the write.
  ///
  /// This is the whole of the coordination between the two cubits, and it runs
  /// in one direction only: the page reads the selection, the review cubit
  /// receives a value. Neither cubit holds the other, so there is no path by
  /// which the write could re-read the list halfway through, and no second door
  /// to the RPC.
  void _confirmWithProducts() {
    _cubit.confirmWithProducts(
      context.read<ReceiptProductSelectionCubit>().state.snapshot,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ReceiptReviewCubit, ReceiptReviewState>(
      // The one capability the submission owns and the selection obeys. It is
      // pushed rather than pulled so the selection cubit stays ignorant of the
      // write: it knows only whether it may currently be edited.
      //
      // `isEditable` is false for pending, settled, conflict and uncertain
      // alike, and true again only after a status check has authoritatively
      // proved that nothing is stored — at which point the list, which was
      // never cleared, becomes editable exactly as it was left.
      listenWhen: (ReceiptReviewState previous, ReceiptReviewState current) =>
          previous.productSubmission.isEditable !=
          current.productSubmission.isEditable,
      listener: (BuildContext context, ReceiptReviewState state) {
        context.read<ReceiptProductSelectionCubit>().setReadOnly(
          readOnly: !state.productSubmission.isEditable,
        );
      },
      builder: (BuildContext context, ReceiptReviewState state) {
        final ReceiptReviewCubit cubit = context.read<ReceiptReviewCubit>();

        return SrPageBody(
          maxWidth: SrSpacing.formMaxWidth,
          children: <Widget>[
            SrPageHeader(
              eyebrow: PortalKind.salesStaff.displayName,
              title: 'Review your receipt',
              description: ReceiptReviewCopy.pageDescription,
              actions: <Widget>[
                Semantics(
                  button: true,
                  label: 'Back to my submitted receipts',
                  child: SrButton(
                    label: 'Back',
                    variant: SrButtonVariant.ghost,
                    icon: Icons.arrow_back_rounded,
                    onPressed: _backToHistory,
                  ),
                ),
              ],
            ),
            const SizedBox(height: SrSpacing.xxl),
            ..._body(state, cubit),
          ],
        );
      },
    );
  }

  List<Widget> _body(ReceiptReviewState state, ReceiptReviewCubit cubit) {
    // A refusal that retrying cannot fix. The receipt image is not shown and
    // no form is offered: there is nothing here this person may act on.
    if (state.phase == ReceiptReviewPhase.blocked) {
      final ReceiptReviewNotice notice = ReceiptReviewCopy.problemNotice(
        state.problem ?? const ExtractionNotFoundProblem(),
      );
      return <Widget>[
        SrEmptyState(
          icon: Icons.lock_outline_rounded,
          tone: SrTone.amber,
          title: notice.title,
          description: notice.message,
          action: SrButton(
            label: 'Back to my submissions',
            icon: Icons.arrow_back_rounded,
            onPressed: _backToHistory,
          ),
        ),
      ];
    }

    // A finished receipt, opened as one: the confirmation is stored and the
    // only thing left is to show what it says. The stored proposal decides
    // which finished receipt this is — one with products, or the header-only
    // shape that predates Phase 1D-B.
    if (state.phase == ReceiptReviewPhase.confirmed) {
      return <Widget>[
        ReceiptReviewConfirmedCard(
          state: state,
          onBackToHistory: _backToHistory,
          // The section below carries the way off the screen instead.
          showBackAction: false,
        ),
        const SizedBox(height: SrSpacing.xl),
        ..._finishedProposal(state, cubit),
      ];
    }

    final ReceiptReviewNotice? notice = ReceiptReviewCopy.noticeFor(state);
    final ReceiptExtraction? extraction = state.extraction;
    final bool showFailure =
        state.phase == ReceiptReviewPhase.failed ||
        state.phase == ReceiptReviewPhase.exhausted;

    return <Widget>[
      ReceiptReviewStatusPanel(
        state: state,
        onRetry: cubit.retryExtraction,
        onCheckAgain: cubit.checkAgain,
      ),
      const SizedBox(height: SrSpacing.xl),

      if (notice != null) ...<Widget>[
        SrAlert(
          tone: notice.tone,
          title: notice.title,
          message: notice.message,
        ),
        const SizedBox(height: SrSpacing.xl),
      ],

      if (showFailure) ...<Widget>[
        Builder(
          builder: (BuildContext context) {
            final ReceiptReviewNotice failure = ReceiptReviewCopy.failureNotice(
              extraction?.failureCode,
            );
            return SrAlert(
              tone: failure.tone,
              title: failure.title,
              message: failure.message,
            );
          },
        ),
        const SizedBox(height: SrSpacing.xl),
      ],

      // What the provider actually read, ABOVE the image and above every
      // control. It is the thing a person opened this screen for, and the thing
      // the form below asks them to confirm — so it is shown before they are
      // asked to confirm anything, and without a tap to reveal it.
      //
      // THE EXTRACTION'S OWN currency and width, and deliberately not the
      // form's. These integers were written by the provider under the currency
      // the provider read; the two fields in the form are a proposal about what
      // the receipt should be *confirmed* as, and are not a description of
      // anything already stored. Passing `draft.currencyCode` or
      // `resolvedMinorUnit` here would relabel AED 12.50 as JPY 1250 the moment
      // somebody typed JPY — rewriting what the reviewer is checking against, on
      // the strength of an edit not yet confirmed.
      if (state.lineItems.isNotEmpty) ...<Widget>[
        ReceiptReviewLineItems(
          items: state.lineItems,
          currencyCode: state.extractionCurrencyCode,
          minorDigits: state.extractionMinorUnit,
        ),
        const SizedBox(height: SrSpacing.xl),
      ],

      ReceiptReviewPreview(state: state, onRefresh: cubit.loadPreview),
      const SizedBox(height: SrSpacing.xl),

      if (extraction != null && extraction.warningCodes.isNotEmpty) ...<Widget>[
        ReceiptReviewWarnings(codes: extraction.warningCodes),
        const SizedBox(height: SrSpacing.xl),
      ],

      // The form appears only when the backend says manual confirmation is
      // open. That boolean is blocked by exactly two things — an existing
      // confirmation and an attempt in flight — and never by a mode gate.
      if (state.canEdit)
        ReceiptReviewForm(
          state: state,
          // Null until the backend has said how wide this currency is. Nothing
          // downstream substitutes a width for it.
          minorDigits: state.resolvedMinorUnit,
          cubit: cubit,
        )
      else
        SrEmptyState(
          icon: Icons.hourglass_empty_rounded,
          title: 'Not ready to confirm yet',
          description: state.isAwaitingExtraction
              ? 'We are still reading this receipt. The form opens as soon as '
                    'the reading finishes.'
              : 'This receipt cannot be confirmed from here just now.',
        ),

      // Phase 1D-B. The product proposal, built AFTER the transaction details
      // it will be submitted with — the order the final review reads in, and
      // the order the atomic confirmation sends. Rendered only while the form
      // is open, for the same reason the form is: a receipt that cannot be
      // confirmed cannot receive products either.
      //
      // The final confirmation control lives at the foot of these sections,
      // because it sends the header and the products in one call.
      // Editable only while the receipt is genuinely unfinished. The moment a
      // confirmation exists — written just now, or discovered by a status
      // check — the catalogue and the selected-products editor are REMOVED
      // rather than disabled, and the immutable record takes their place.
      if (state.canEdit && !state.isReceiptFinished) ...<Widget>[
        const SizedBox(height: SrSpacing.xl),
        _ProductProposalSections(
          review: state,
          onConfirm: _confirmWithProducts,
          onCheckStatus: cubit.checkReceiptStatus,
        ),
      ],

      if (state.isReceiptFinished) ...<Widget>[
        const SizedBox(height: SrSpacing.xl),
        ..._finishedProposal(state, cubit),
      ],
    ];
  }

  /// What a finished receipt shows in place of the editable proposal.
  ///
  /// Three outcomes and no fourth: the stored lines, the explicit header-only
  /// state, or an honest "we could not load them" that offers another read.
  /// None of the three carries a control that could write anything — the
  /// catalogue, the selected-products editor and the confirm button are not
  /// disabled here, they are absent.
  List<Widget> _finishedProposal(
    ReceiptReviewState state,
    ReceiptReviewCubit cubit,
  ) {
    // What THIS session's write did, when it was this session that wrote. It
    // carries the one distinction the stored lines cannot: whether the record
    // was created just now or already existed. Absent on an initial load, and
    // suppressed for the legacy state, which says it better in its own words.
    final ReceiptReviewNotice? outcome = state.storedProposal.isLegacyHeaderOnly
        ? null
        : ReceiptReviewCopy.productSubmissionNotice(state.productSubmission);

    return <Widget>[
      if (outcome != null) ...<Widget>[
        Semantics(
          liveRegion: true,
          container: true,
          child: SrAlert(
            tone: outcome.tone,
            title: outcome.title,
            message: outcome.message,
          ),
        ),
        const SizedBox(height: SrSpacing.xl),
      ],

      if (state.storedProposal.isLegacyHeaderOnly)
        const ReceiptLegacyConfirmationSection()
      else
        ReceiptSubmittedProposalSection(
          proposal: state.storedProposal,
          onReload: cubit.reloadStoredProposal,
        ),
      const SizedBox(height: SrSpacing.xl),
      Semantics(
        button: true,
        label: 'Back to my submitted receipts',
        child: SrButton(
          label: 'Back to my submissions',
          icon: Icons.arrow_back_rounded,
          variant: SrButtonVariant.outline,
          size: SrButtonSize.lg,
          fullWidth: true,
          onPressed: _backToHistory,
        ),
      ),
    ];
  }
}

/// The product sections and the one final confirmation control.
///
/// Split into its own widget so only these cards rebuild when a quantity
/// changes — the review page above them, which owns the image preview and the
/// transaction form, is untouched by a stepper tap.
///
/// The confirmation control is here, at the foot, rather than under the
/// transaction form: it sends the header and the products in one immutable
/// call, so it belongs after everything it will send.
class _ProductProposalSections extends StatefulWidget {
  const _ProductProposalSections({
    required this.review,
    required this.onConfirm,
    required this.onCheckStatus,
  });

  /// The review state, for the capabilities the submission owns — whether the
  /// control may fire, and whether the list may still change.
  final ReceiptReviewState review;
  final VoidCallback onConfirm;
  final VoidCallback onCheckStatus;

  @override
  State<_ProductProposalSections> createState() =>
      _ProductProposalSectionsState();
}

class _ProductProposalSectionsState extends State<_ProductProposalSections> {
  @override
  void initState() {
    super.initState();
    // One catalogue read for the life of this route. Guarded inside the cubit,
    // so a rebuilt element cannot issue a second one.
    context.read<ReceiptProductSelectionCubit>().loadCatalogue();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<
      ReceiptProductSelectionCubit,
      ReceiptProductSelectionState
    >(
      builder: (BuildContext context, ReceiptProductSelectionState state) {
        final ReceiptProductSelectionCubit cubit = context
            .read<ReceiptProductSelectionCubit>();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ReceiptProductCatalogueSection(
              products: state.visibleCatalogue,
              query: state.query,
              onQueryChanged: cubit.search,
              onSelect: cubit.select,
              isSelected: state.isSelected,
              lineNumberOf: state.lineNumberOf,
              isLoading: state.isLoading,
              failure: state.failure,
              onRetry: cubit.retryCatalogue,
              isReadOnly: state.isReadOnly,
              isFull: state.isFull,
            ),
            const SizedBox(height: SrSpacing.xl),
            ReceiptSelectedProductsSection(
              products: state.selectedProducts,
              onIncrement: cubit.increment,
              onDecrement: cubit.decrement,
              onRemove: cubit.remove,
              notice: state.notice,
              noticeProductId: state.noticeProductId,
              isReadOnly: state.isReadOnly,
            ),
            const SizedBox(height: SrSpacing.xl),
            ReceiptFinalConfirmationSection(
              state: widget.review,
              // Read from the selection state so the summary and the request
              // describe the same list — the snapshot the tap takes is built
              // from this very state object.
              lineCount: state.selectedCount,
              totalQuantity: state.totalQuantity,
              onConfirm: widget.onConfirm,
              onCheckStatus: widget.onCheckStatus,
            ),
          ],
        );
      },
    );
  }
}
