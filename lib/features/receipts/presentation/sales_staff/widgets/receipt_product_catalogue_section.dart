import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/errors/errors.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/receipt_product.dart';

/// The searchable catalogue a Sales Staff member picks products from.
///
/// ## The catalogue is the only door
///
/// Every row here came from `list_my_receipt_products()`, which returns only
/// products ACTIVE and actively assigned to the caller's Retailer. There is no
/// free-text field, no "add a product" affordance and no product-id input
/// anywhere in this widget — a product that is not in the list cannot be
/// expressed, and the database would refuse it even if it could.
///
/// ## It knows nothing about Supabase
///
/// It receives a typed list and callbacks. No client, no RPC name and no table
/// access appears in this file, which is also what the receipt security
/// boundary asserts about every source under `features/receipts/`.
///
/// ## Selected state is a word, not a colour
///
/// A selected row carries the word "Selected" and a check icon, and its button
/// changes label. Colour reinforces it and never carries it alone.
class ReceiptProductCatalogueSection extends StatelessWidget {
  const ReceiptProductCatalogueSection({
    super.key,
    required this.products,
    required this.query,
    required this.onQueryChanged,
    required this.onSelect,
    required this.isSelected,
    required this.lineNumberOf,
    this.isLoading = false,
    this.failure,
    this.onRetry,
    this.isReadOnly = false,
    this.isFull = false,
  });

  /// The catalogue already narrowed by [query] — the state layer owns the
  /// matcher, so this widget cannot drift into a second definition of "matches".
  final List<ReceiptProduct> products;

  final String query;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<ReceiptProduct> onSelect;

  /// Whether a product is already on the proposal.
  final bool Function(String productId) isSelected;

  /// Which line it occupies, so an already-selected row can say where to look
  /// rather than appear to do nothing when tapped again.
  final int? Function(String productId) lineNumberOf;

  final bool isLoading;

  /// Set when the catalogue read failed. Products are a prerequisite for a
  /// proposal, but a failure degrades this section alone — a selection already
  /// built stays intact.
  final Failure? failure;

  final VoidCallback? onRetry;

  /// True once the proposal may no longer change.
  final bool isReadOnly;

  /// True at 50 selected products. The 51st is refused; nothing is evicted.
  final bool isFull;

  @override
  Widget build(BuildContext context) {
    return SrSectionCard(
      title: 'Choose products',
      description:
          'Pick every product on this invoice / receipt, then set how many of '
          'each. '
          'Only products your Retailer is assigned appear here.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (!isReadOnly) ...<Widget>[
            SrSearchField(
              label: 'Search products',
              hint: 'Search by product name, code or barcode',
              term: query,
              onChanged: onQueryChanged,
            ),
            const SizedBox(height: SrSpacing.md),
          ],
          _body(context),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: SrSpacing.lg),
        child: SrLoadingView(label: 'Loading your product list'),
      );
    }

    if (failure != null) {
      // The shared failure view renders a discriminant, never a backend
      // message, and offers the repository's established single retry.
      return SrFailureView(failure: failure!, onRetry: onRetry);
    }

    if (products.isEmpty) {
      return SrEmptyState(
        icon: Icons.inventory_2_outlined,
        title: query.trim().isEmpty
            ? 'No products are assigned to your Retailer'
            : 'No products match “${query.trim()}”',
        description: query.trim().isEmpty
            ? 'Ask your manager to assign products before submitting an '
                  'invoice / receipt.'
            : 'Try part of the product name, its code, or the barcode.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final ReceiptProduct product in products)
          _CatalogueRow(
            product: product,
            selected: isSelected(product.productId),
            lineNumber: lineNumberOf(product.productId),
            enabled: !isReadOnly,
            isFull: isFull,
            onSelect: () => onSelect(product),
          ),
      ],
    );
  }
}

class _CatalogueRow extends StatelessWidget {
  const _CatalogueRow({
    required this.product,
    required this.selected,
    required this.lineNumber,
    required this.enabled,
    required this.isFull,
    required this.onSelect,
  });

  final ReceiptProduct product;
  final bool selected;
  final int? lineNumber;
  final bool enabled;
  final bool isFull;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final String subtitle = <String?>[
      product.productCode,
      product.brand,
      product.barcode,
    ].whereType<String>().join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SrSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
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
                  style: SrTypography.caption.copyWith(color: sr.textSecondary),
                  softWrap: true,
                ),
                if (selected) ...<Widget>[
                  const SizedBox(height: SrSpacing.xs),
                  // A word, plus an icon. Never colour alone.
                  SrBadge(
                    label: lineNumber == null
                        ? 'Selected'
                        : 'Selected · line $lineNumber',
                    tone: SrTone.emerald,
                    icon: Icons.check_circle_outline,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: SrSpacing.sm),
          Semantics(
            button: true,
            enabled: enabled && !selected && !isFull,
            label: selected
                ? '${product.productName} is already selected'
                : 'Add ${product.productName} to this invoice / receipt',
            child: SrButton(
              label: selected ? 'Selected' : 'Add',
              variant: selected
                  ? SrButtonVariant.ghost
                  : SrButtonVariant.secondary,
              size: SrButtonSize.sm,
              icon: selected ? Icons.check : Icons.add,
              // Still tappable when already selected: the state layer answers
              // with a notice pointing at the existing line, which is more
              // useful than a control that appears broken.
              onPressed: enabled ? onSelect : null,
            ),
          ),
        ],
      ),
    );
  }
}
