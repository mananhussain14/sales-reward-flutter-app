import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/receipt_confirmation.dart';
import '../../../domain/entities/receipt_confirmation_field.dart';
import '../cubit/receipt_review_cubit.dart';
import 'receipt_formatting.dart';
import 'receipt_minor_units.dart';
import 'receipt_review_copy.dart';

/// The settled confirmation.
///
/// ## Everything on this card is the backend's answer, not this client's
///
/// The entry mode and the list of corrected fields are **outcomes** of a
/// confirmation, not inputs to one. `confirm_receipt_extraction` has no
/// parameter for either, so this client could not state them even if it wanted
/// to: the comparison that produces them lives in SQL, is deliberately forgiving
/// about casing and punctuation, and a second definition in Dart would be free
/// to drift from the stored answer. This card renders what came back and
/// computes nothing.
///
/// ## There is no way back from here
///
/// A confirmation is immutable: no update, no delete, no revision exists
/// anywhere in the contract. The card therefore offers no edit control — an
/// affordance that could only ever fail.
class ReceiptReviewConfirmedCard extends StatelessWidget {
  const ReceiptReviewConfirmedCard({
    super.key,
    required this.state,
    required this.onBackToHistory,
    this.showBackAction = true,
  });

  final ReceiptReviewState state;
  final VoidCallback onBackToHistory;

  /// Whether this card carries the way off the screen.
  ///
  /// False when a submitted-proposal or legacy section follows it: the two
  /// belong to one finished receipt, and a back button wedged between them
  /// would read as the end of the page when it is not. The section below
  /// carries the navigation instead.
  final bool showBackAction;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final ReceiptConfirmation? row = state.confirmation;
    final List<ReceiptConfirmationField> changed =
        row?.changedFields ??
        state.confirmationResult?.changedFields ??
        const <ReceiptConfirmationField>[];

    return SrCard(
      variant: SrCardVariant.highlighted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SrIconDisc(
                icon: Icons.task_alt_rounded,
                tone: SrTone.emerald,
                size: 48,
              ),
              const SizedBox(width: SrSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Receipt confirmed',
                      style: SrTypography.sectionTitle.copyWith(
                        color: sr.foreground,
                      ),
                    ),
                    const SizedBox(height: SrSpacing.xxs),
                    Text(
                      'These details are recorded and cannot be changed.',
                      style: SrTypography.body.copyWith(
                        color: sr.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: SrSpacing.xl),
          Align(
            alignment: Alignment.centerLeft,
            child: SrBadge(
              label: ReceiptReviewCopy.entryModeLabel(
                row?.entryMode ?? state.confirmationResult?.entryMode,
              ),
              tone: SrTone.indigo,
            ),
          ),
          if (row != null) ...<Widget>[
            const SizedBox(height: SrSpacing.lg),
            _Row(label: 'Date', value: row.transactionDate.iso),
            if (row.transactionTime != null)
              _Row(label: 'Time', value: row.transactionTime!.iso),
            _Row(
              label: 'Total',
              value: formatMinorAmount(
                row.totalMinor,
                row.currencyCode,
                row.currencyMinorUnit,
              ),
            ),
            if (row.subtotalMinor != null)
              _Row(
                label: 'Subtotal',
                value: formatMinorAmount(
                  row.subtotalMinor!,
                  row.currencyCode,
                  row.currencyMinorUnit,
                ),
              ),
            if (row.taxTotalMinor != null)
              _Row(
                label: 'Tax',
                value: formatMinorAmount(
                  row.taxTotalMinor!,
                  row.currencyCode,
                  row.currencyMinorUnit,
                ),
              ),
            if (row.merchantName != null)
              _Row(label: 'Shop name', value: row.merchantName!),
            if (row.documentNumber != null)
              _Row(label: 'Receipt number', value: row.documentNumber!),
            _Row(
              label: 'Confirmed',
              value: formatReceiptTimestamp(row.confirmedAt),
            ),
          ],
          if (changed.isNotEmpty) ...<Widget>[
            const SizedBox(height: SrSpacing.md),
            Text(
              'You corrected: '
              '${changed.map(ReceiptReviewCopy.changedFieldLabel).join(', ')}',
              style: SrTypography.caption.copyWith(color: sr.textSecondary),
            ),
          ],
          if (showBackAction) ...<Widget>[
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
                onPressed: onBackToHistory,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Padding(
      padding: const EdgeInsets.only(bottom: SrSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 116,
            child: Text(
              label,
              style: SrTypography.caption.copyWith(color: sr.textSecondary),
            ),
          ),
          const SizedBox(width: SrSpacing.sm),
          Expanded(
            child: Text(
              value,
              style: SrTypography.caption.copyWith(color: sr.textBody),
            ),
          ),
        ],
      ),
    );
  }
}
