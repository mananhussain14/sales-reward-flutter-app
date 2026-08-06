import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/shells/sales_staff/sales_staff_navigation.dart';
import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../../auth/domain/entities/portal_kind.dart';
import '../../../domain/entities/receipt_submission.dart';
import '../cubit/receipt_history_cubit.dart';
import '../cubit/receipt_submission_cubit.dart';
import '../widgets/receipt_copy.dart';
import '../widgets/receipt_file_field.dart';
import '../widgets/receipt_products_section.dart';
import '../widgets/receipt_progress_panel.dart';
import '../widgets/receipt_shop_selector.dart';
import '../widgets/receipt_steps_strip.dart';
import '../widgets/receipt_submission_tile.dart';
import '../widgets/receipt_success_card.dart';

/// The Sales Staff landing screen: submit one receipt for one assigned shop.
///
/// ## The whole flow, in the order it appears
///
/// 1. **Shop** — from `list_my_assigned_receipt_shops()`. Always visible, so a
///    person can see which shop a receipt is about to be filed against.
/// 2. **Receipt image** — camera or gallery, previewed, replaceable, removable.
/// 3. **Submit** — one `POST` to the `submit-receipt` Edge Function carrying
///    `shop_id` and the file, and nothing else.
/// 4. **Progress** — four true stages, and no invented percentage.
/// 5. **Result** — the status the *database* returned for the created row, read
///    back with `get_my_receipt_submission(uuid)`.
///
/// Below the form sit two context sections that never gate a submission: the
/// eligible-product reference list, and the caller's most recent submissions.
///
/// ## What is deliberately absent
///
/// No OCR, no product attachment, no reward or coin figure, no review or
/// approval state, and no way to open a submitted image — the backend exposes no
/// retrieval path for one, so an affordance would promise something the contract
/// cannot deliver. No storage bucket, object path, file hash, profile,
/// membership or organization id appears anywhere on this screen, because none
/// of them reaches this layer to be rendered.
class SalesStaffSubmitPage extends StatelessWidget {
  const SalesStaffSubmitPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReceiptSubmissionCubit, ReceiptSubmissionState>(
      builder: (BuildContext context, ReceiptSubmissionState state) {
        final ReceiptSubmissionCubit cubit = context
            .read<ReceiptSubmissionCubit>();

        if (state.phase == ReceiptSubmissionPhase.initialLoading) {
          return const SrLoadingView(label: 'Loading your shops');
        }

        return SrPageBody(
          maxWidth: SrSpacing.formMaxWidth,
          children: <Widget>[
            SrEnter(
              child: SrPageHeader(
                eyebrow: PortalKind.salesStaff.displayName,
                title: 'Submit a receipt',
                description: ReceiptCopy.submitPageDescription,
              ),
            ),
            const SizedBox(height: SrSpacing.xl),

            if (state.phase != ReceiptSubmissionPhase.loadFailed) ...<Widget>[
              SrEnter(
                index: 1,
                child: ReceiptStepsStrip(current: _stepFor(state)),
              ),
              const SizedBox(height: SrSpacing.xl),
            ],

            if (state.phase == ReceiptSubmissionPhase.loadFailed)
              SrFailureView(failure: state.loadFailure!, onRetry: cubit.load)
            else ...<Widget>[
              if (state.phase == ReceiptSubmissionPhase.success)
                ReceiptSuccessCard(
                  submissionId: state.submissionId,
                  submission: state.submission,
                  onSubmitAnother: cubit.startAnother,
                  // Offered only when the function actually returned an id.
                  // Without one there is nothing to review, and a control that
                  // navigated nowhere would be worse than no control.
                  onReviewReceipt: state.submissionId == null
                      ? null
                      : () => context.go(
                          SalesStaffNavigation.review(state.submissionId!),
                        ),
                )
              else
                SrEnter(
                  index: 2,
                  child: _SubmitForm(state: state, cubit: cubit),
                ),

              const SizedBox(height: SrSpacing.xxl),
              SrEnter(
                index: 3,
                child: ReceiptProductsSection(
                  products: state.products,
                  failure: state.productsFailure,
                  onRetry: cubit.load,
                ),
              ),
              const SizedBox(height: SrSpacing.xxl),
              const SrEnter(index: 4, child: _RecentSubmissions()),
            ],
          ],
        );
      },
    );
  }

  /// Which of the four steps the current phase is at.
  ///
  /// Derived, never stored. The submission cubit holds one phase and this
  /// reads it — a second counter kept alongside would be one more thing that
  /// could disagree with the state that actually performs the write.
  ///
  /// A settled failure — rejected, retryable, unconfirmed, duplicate, denied —
  /// leaves the strip wherever the person actually is: they still have a file
  /// chosen, so they are on "Review image", which is exactly the step the
  /// notice above the form is asking them to act on.
  ReceiptStep _stepFor(ReceiptSubmissionState state) {
    if (state.phase == ReceiptSubmissionPhase.success) {
      return ReceiptStep.reviewDetails;
    }
    if (state.phase == ReceiptSubmissionPhase.submitting ||
        state.phase == ReceiptSubmissionPhase.validating) {
      return ReceiptStep.submitSecurely;
    }
    return state.file == null
        ? ReceiptStep.chooseReceipt
        : ReceiptStep.reviewImage;
  }
}

/// The form itself: shop, image, feedback, progress, submit.
class _SubmitForm extends StatelessWidget {
  const _SubmitForm({required this.state, required this.cubit});

  final ReceiptSubmissionState state;
  final ReceiptSubmissionCubit cubit;

  @override
  Widget build(BuildContext context) {
    final ReceiptNotice? notice = ReceiptCopy.noticeFor(state);
    final bool hasShops = state.shops.isNotEmpty;

    return SrSectionCard(
      title: 'Receipt details',
      description: 'A receipt is always submitted against one assigned shop.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (notice != null) ...<Widget>[
            SrAlert(
              tone: notice.tone,
              title: notice.title,
              message: notice.message,
            ),
            const SizedBox(height: SrSpacing.xl),
          ],

          if (!hasShops)
            const SrEmptyState(
              icon: Icons.storefront_outlined,
              title: 'No shops assigned yet',
              description:
                  'You need to be assigned to at least one shop before you can '
                  'submit a receipt. Ask your manager to assign you.',
            )
          else ...<Widget>[
            ReceiptShopSelector(
              shops: state.shops,
              selected: state.selectedShop,
              enabled: !state.isBusy,
              onChanged: cubit.selectShop,
            ),
            const SizedBox(height: SrSpacing.xl),

            ReceiptFileField(
              file: state.file,
              enabled: state.canChooseFile,
              supportsCamera: cubit.supportsCamera,
              onChoose: cubit.chooseImage,
              onRemove: cubit.removeFile,
            ),

            if (state.isBusy && state.stage != null) ...<Widget>[
              const SizedBox(height: SrSpacing.xl),
              ReceiptProgressPanel(stage: state.stage!),
            ],

            const SizedBox(height: SrSpacing.xl),
            SrButton(
              label: 'Submit receipt',
              icon: Icons.cloud_upload_outlined,
              size: SrButtonSize.lg,
              fullWidth: true,
              loading: state.phase == ReceiptSubmissionPhase.submitting,
              loadingLabel: 'Submitting…',
              // Null while a submission is in flight — the visible half of the
              // duplicate-tap guard. The cubit refuses a second call regardless,
              // so a stale frame cannot get past it either.
              onPressed: state.canSubmit ? cubit.submit : null,
            ),
          ],
        ],
      ),
    );
  }
}

/// The three most recent submissions, and a way to see the rest.
///
/// Present on this screen because it answers "did that actually go through?" —
/// most of all after an unconfirmed result, where the history is the only
/// authority on what exists.
class _RecentSubmissions extends StatelessWidget {
  const _RecentSubmissions();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReceiptHistoryCubit, ReceiptHistoryState>(
      builder: (BuildContext context, ReceiptHistoryState state) {
        return SrSectionCard(
          title: 'Recent submissions',
          description: 'Your most recent receipts.',
          action: SrButton(
            label: 'View all',
            variant: SrButtonVariant.ghost,
            size: SrButtonSize.sm,
            icon: Icons.chevron_right_rounded,
            onPressed: () => context.go(SalesStaffNavigation.history),
          ),
          child: _body(context, state),
        );
      },
    );
  }

  Widget _body(BuildContext context, ReceiptHistoryState state) {
    final ReceiptHistoryCubit cubit = context.read<ReceiptHistoryCubit>();

    if (state.phase == ReceiptHistoryPhase.initial ||
        state.phase == ReceiptHistoryPhase.loading) {
      return const SrLoadingView(
        showHeader: false,
        rows: 2,
        label: 'Loading your submissions',
      );
    }

    // A failed refresh over rows already on screen keeps the rows: they are
    // still the last thing the backend actually said.
    if (state.phase == ReceiptHistoryPhase.failed &&
        state.submissions.isEmpty) {
      return SrFailureView(failure: state.failure!, onRetry: cubit.load);
    }

    final List<ReceiptSubmission> recent = state.take(3);

    if (recent.isEmpty) {
      return const SrEmptyState(
        icon: Icons.inbox_outlined,
        title: 'No receipts yet',
        description: 'Receipts you submit will appear here straight away.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final ReceiptSubmission submission in recent)
          Padding(
            padding: const EdgeInsets.only(bottom: SrSpacing.md),
            child: ReceiptSubmissionTile(submission: submission),
          ),
      ],
    );
  }
}
