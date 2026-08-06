import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/shells/sales_staff/sales_staff_navigation.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../../auth/domain/entities/portal_kind.dart';
import '../../../domain/entities/receipt_submission.dart';
import '../cubit/receipt_history_cubit.dart';
import '../widgets/receipt_submission_tile.dart';

/// Every receipt this person has submitted.
///
/// Backed by one call to `public.list_my_receipt_submissions()` — **zero
/// arguments**, filtered in SQL on both `submitted_by_profile_id = auth.uid()`
/// and the resolved Retailer. There is no page, filter or id parameter, so
/// nothing on this screen can widen what comes back, and no other person's
/// receipt can appear on it.
///
/// ## A stored receipt opens its review, and only a stored one
///
/// A `SUBMITTED` row has an object behind it and can be read, corrected and
/// confirmed. A `RESERVED` or `UPLOAD_FAILED` row has nothing behind it, so it
/// is offered no review control: every call the review screen makes would
/// refuse, and that refusal is deliberately indistinguishable from "that is not
/// yours" — an alarming thing to show somebody about their own receipt.
class SalesStaffHistoryPage extends StatelessWidget {
  const SalesStaffHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReceiptHistoryCubit, ReceiptHistoryState>(
      builder: (BuildContext context, ReceiptHistoryState state) {
        final ReceiptHistoryCubit cubit = context.read<ReceiptHistoryCubit>();

        if (state.phase == ReceiptHistoryPhase.initial ||
            (state.phase == ReceiptHistoryPhase.loading &&
                state.submissions.isEmpty)) {
          return const SrLoadingView(label: 'Loading your receipts');
        }

        return SrPageBody(
          maxWidth: SrSpacing.formMaxWidth,
          children: <Widget>[
            SrEnter(
              child: SrPageHeader(
                eyebrow: PortalKind.salesStaff.displayName,
                title: 'My receipts',
                description:
                    'Every receipt you have submitted, newest first. Only your '
                    'own submissions appear here.',
                actions: <Widget>[
                  SrButton(
                    label: 'Refresh',
                    variant: SrButtonVariant.outline,
                    icon: Icons.refresh_rounded,
                    loading: state.isRefreshing,
                    loadingLabel: 'Refreshing…',
                    onPressed: state.isRefreshing ? null : cubit.refresh,
                  ),
                ],
              ),
            ),
            const SizedBox(height: SrSpacing.xxl),
            _body(context, state, cubit),
          ],
        );
      },
    );
  }

  Widget _body(
    BuildContext context,
    ReceiptHistoryState state,
    ReceiptHistoryCubit cubit,
  ) {
    if (state.phase == ReceiptHistoryPhase.failed &&
        state.submissions.isEmpty) {
      return SrFailureView(failure: state.failure!, onRetry: cubit.load);
    }

    if (state.submissions.isEmpty) {
      return SrEmptyState(
        icon: Icons.inbox_outlined,
        tone: SrTone.indigo,
        title: 'No receipts yet',
        description:
            'Once you submit a receipt it will appear here, newest first.',
        // The one thing a person with no receipts can do, opening the flow
        // that already performs the write.
        action: SrButton(
          label: 'Add receipt',
          icon: Icons.add_a_photo_rounded,
          size: SrButtonSize.lg,
          onPressed: () => context.go(SalesStaffNavigation.submit),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // A refresh that failed over rows already on screen says so without
        // throwing the rows away — they are still the last thing the backend
        // actually returned.
        if (state.phase == ReceiptHistoryPhase.failed) ...<Widget>[
          const SrAlert(
            tone: SrAlertTone.warning,
            title: 'This list may be out of date',
            message: 'We could not refresh your receipts just now.',
          ),
          const SizedBox(height: SrSpacing.lg),
        ],
        for (int i = 0; i < state.submissions.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: SrSpacing.md),
            child: SrEnter(
              index: i,
              child: Builder(
                builder: (BuildContext context) {
                  final ReceiptSubmission submission = state.submissions[i];
                  return ReceiptSubmissionTile(
                    submission: submission,
                    onOpenReview: submission.status.isSubmitted
                        ? () => context.go(
                            SalesStaffNavigation.review(
                              submission.submissionId,
                            ),
                          )
                        : null,
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
