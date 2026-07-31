import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/shells/sales_staff/sales_staff_navigation.dart';
import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../../auth/domain/entities/portal_kind.dart';
import '../../../domain/entities/receipt_extraction.dart';
import '../../../domain/entities/receipt_extraction_problem.dart';
import '../cubit/receipt_review_cubit.dart';
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
/// 2. **Your receipt** — the private image, through a capability that lives for
///    about two minutes and is never written down.
/// 3. **Things to check** — the reading's own warnings, as sentences.
/// 4. **Receipt details** — the eight values a confirmation carries, editable.
/// 5. **Line items** — informational, collapsed, and gating nothing.
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

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReceiptReviewCubit, ReceiptReviewState>(
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

    if (state.phase == ReceiptReviewPhase.confirmed) {
      return <Widget>[
        ReceiptReviewConfirmedCard(
          state: state,
          onBackToHistory: _backToHistory,
        ),
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
          onConfirm: cubit.confirm,
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

      if (state.lineItems.isNotEmpty) ...<Widget>[
        const SizedBox(height: SrSpacing.xl),
        // THE EXTRACTION'S OWN currency and width, and deliberately not the
        // form's. These integers were written by the provider under the currency
        // the provider read; the two fields above are a proposal about what the
        // receipt should be *confirmed* as, and are not a description of
        // anything already stored. Passing `draft.currencyCode` or
        // `resolvedMinorUnit` here would relabel AED 12.50 as JPY 1250 the
        // moment somebody typed JPY — rewriting what the reviewer is checking
        // against, on the strength of an edit not yet confirmed.
        ReceiptReviewLineItems(
          items: state.lineItems,
          currencyCode: state.extractionCurrencyCode,
          minorDigits: state.extractionMinorUnit,
        ),
      ],
    ];
  }
}
