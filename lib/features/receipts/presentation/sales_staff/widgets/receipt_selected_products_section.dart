import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/selected_receipt_product.dart';
import '../cubit/receipt_product_selection_cubit.dart';

/// The products chosen for this receipt, in the order they were chosen.
///
/// ## Order is the proposal
///
/// The database derives `line_number` from array position, so the order shown
/// here is the order that will be stored. Changing a quantity replaces a line in
/// place and removing one closes the gap — nothing in this widget or the state
/// beneath it sorts, and a search in the catalogue above cannot disturb it.
///
/// ## Quantities are whole numbers, bounded at both ends
///
/// 1–100, matching `check (quantity >= 1 and quantity <= 100)`. There is no text
/// field: a stepper cannot express `2.5`, `-1`, `250` or an empty committed
/// value, so the four inputs the database refuses are unreachable rather than
/// merely validated. Decrementing at 1 is disabled — removing a line is a
/// separate, explicit act, so a stepper can never silently delete a selection.
class ReceiptSelectedProductsSection extends StatelessWidget {
  const ReceiptSelectedProductsSection({
    super.key,
    required this.products,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
    this.notice,
    this.noticeProductId,
    this.isReadOnly = false,
  });

  final List<SelectedReceiptProduct> products;
  final ValueChanged<String> onIncrement;
  final ValueChanged<String> onDecrement;
  final ValueChanged<String> onRemove;

  /// A refusal the state layer wants said out loud.
  final ReceiptProductSelectionNotice? notice;
  final String? noticeProductId;

  /// True once the proposal may no longer change: every mutation control
  /// disappears rather than merely greying out, so a settled proposal offers no
  /// affordance that could imply it is still editable.
  final bool isReadOnly;

  int get _totalQuantity => products.fold<int>(
    0,
    (int sum, SelectedReceiptProduct p) => sum + p.quantity,
  );

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return SrSectionCard(
      title: 'Products on this receipt',
      description: products.isEmpty
          ? null
          : '${products.length} of $maxReceiptProductLines lines · '
                '$_totalQuantity item${_totalQuantity == 1 ? '' : 's'} in total',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (notice != null) ...<Widget>[
            SrAlert(
              tone: SrAlertTone.warning,
              title: _noticeTitle,
              message: _noticeMessage,
            ),
            const SizedBox(height: SrSpacing.md),
          ],
          if (products.isEmpty)
            SrEmptyState(
              icon: Icons.shopping_bag_outlined,
              title: 'No products chosen yet',
              description:
                  'Add at least one product from the list above. A receipt '
                  'cannot be submitted without its products.',
            )
          else
            for (int i = 0; i < products.length; i++)
              _SelectedLine(
                line: i + 1,
                product: products[i],
                highlighted: products[i].productId == noticeProductId,
                isReadOnly: isReadOnly,
                onIncrement: () => onIncrement(products[i].productId),
                onDecrement: () => onDecrement(products[i].productId),
                onRemove: () => onRemove(products[i].productId),
                sr: sr,
              ),
        ],
      ),
    );
  }

  String get _noticeTitle => switch (notice) {
    ReceiptProductSelectionNotice.alreadySelected => 'Already on this receipt',
    ReceiptProductSelectionNotice.limitReached => 'Line limit reached',
    null => '',
  };

  String get _noticeMessage => switch (notice) {
    // Says where to look, and says plainly that nothing was changed — a person
    // who tapped twice needs to know their first choice is intact.
    ReceiptProductSelectionNotice.alreadySelected =>
      'That product is already listed below. Its quantity was not changed — '
          'use the + control on its line to add more.',
    ReceiptProductSelectionNotice.limitReached =>
      'A receipt can carry at most $maxReceiptProductLines products. Remove one '
          'before adding another. Nothing was removed for you.',
    null => '',
  };
}

class _SelectedLine extends StatelessWidget {
  const _SelectedLine({
    required this.line,
    required this.product,
    required this.highlighted,
    required this.isReadOnly,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
    required this.sr,
  });

  final int line;
  final SelectedReceiptProduct product;
  final bool highlighted;
  final bool isReadOnly;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;
  final SrColorScheme sr;

  @override
  Widget build(BuildContext context) {
    final bool atMin = product.quantity <= minReceiptProductQuantity;
    final bool atMax = product.quantity >= maxReceiptProductQuantity;
    final String subtitle = <String?>[
      product.productCode,
      product.brand,
      product.barcode,
    ].whereType<String>().join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: SrSpacing.sm),
      padding: const EdgeInsets.all(SrSpacing.sm),
      decoration: BoxDecoration(
        color: highlighted ? sr.surfaceMuted : null,
        border: Border.all(color: highlighted ? sr.borderStrong : sr.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '$line.',
                style: SrTypography.label.copyWith(color: sr.textSecondary),
              ),
              const SizedBox(width: SrSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      product.productName,
                      style: SrTypography.label.copyWith(color: sr.textBody),
                      softWrap: true,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: SrTypography.caption.copyWith(
                        color: sr.textSecondary,
                      ),
                      softWrap: true,
                    ),
                  ],
                ),
              ),
              if (!isReadOnly)
                Semantics(
                  button: true,
                  label: 'Remove ${product.productName} from this receipt',
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    // 48dp minimum, so the control is reachable on a phone.
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    tooltip: 'Remove ${product.productName}',
                    onPressed: onRemove,
                  ),
                ),
            ],
          ),
          const SizedBox(height: SrSpacing.xs),
          Row(
            children: <Widget>[
              Text(
                'Quantity',
                style: SrTypography.caption.copyWith(color: sr.textSecondary),
              ),
              const Spacer(),
              if (isReadOnly)
                Text(
                  '${product.quantity}',
                  style: SrTypography.label.copyWith(color: sr.textBody),
                )
              else ...<Widget>[
                Semantics(
                  button: true,
                  enabled: !atMin,
                  label: atMin
                      ? 'Cannot reduce ${product.productName} below '
                            '$minReceiptProductQuantity'
                      : 'Reduce quantity of ${product.productName}',
                  child: IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    tooltip: 'Reduce ${product.productName}',
                    onPressed: atMin ? null : onDecrement,
                  ),
                ),
                // The number itself is announced with its product, so a screen
                // reader never reads a bare digit with no subject.
                Semantics(
                  label: '${product.productName} quantity ${product.quantity}',
                  excludeSemantics: true,
                  child: SizedBox(
                    width: 40,
                    child: Text(
                      '${product.quantity}',
                      textAlign: TextAlign.center,
                      style: SrTypography.label.copyWith(color: sr.textBody),
                    ),
                  ),
                ),
                Semantics(
                  button: true,
                  enabled: !atMax,
                  label: atMax
                      ? 'Cannot increase ${product.productName} above '
                            '$maxReceiptProductQuantity'
                      : 'Increase quantity of ${product.productName}',
                  child: IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    tooltip: 'Increase ${product.productName}',
                    onPressed: atMax ? null : onIncrement,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
