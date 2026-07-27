import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/retailer_assigned_product.dart';
import 'retailer_products_copy.dart';

/// One assigned product.
///
/// ## Deliberately not tappable, and carrying no controls
///
/// No `onTap`, no chevron, no edit, no assignment toggle, no "remove" — not
/// disabled ones, none at all. A Retailer cannot modify an assignment: that is a
/// Vendor capability on `PRODUCT_RETAILER_ASSIGN`, and neither write RPC is
/// named anywhere in the Retailer portal. There is no product detail screen
/// either, and this client deliberately does not carry `product_id`, so there
/// would be nothing to address.
///
/// ## No status badge
///
/// `assignment_status` is `'ACTIVE'` for every row the contract can return, so a
/// badge would say the same word on every card — decoration that looks like
/// information, and worse, one that implies an inactive variant exists to be
/// found. The section note states the scope once instead.
///
/// ## Absent fields are omitted, never faked
///
/// `barcode`, `brand` and `description` are all nullable. A null one is left out
/// entirely rather than rendered as a dash: an absent barcode is a fact about
/// the product, and a placeholder would make every incompletely-recorded product
/// look identical.
class RetailerProductCard extends StatelessWidget {
  const RetailerProductCard({super.key, required this.product});

  final RetailerAssignedProduct product;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    final List<({String label, String value})> details =
        <({String label, String value})>[
          (label: RetailerProductsCopy.codeLabel, value: product.productCode),
          if (product.brand != null)
            (label: RetailerProductsCopy.brandLabel, value: product.brand!),
          if (product.barcode != null)
            (label: RetailerProductsCopy.barcodeLabel, value: product.barcode!),
        ];

    return Semantics(
      label: _semanticLabel(details),
      excludeSemantics: true,
      child: SrCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: SrSpacing.xxs),
                  child: Icon(
                    Icons.inventory_2_rounded,
                    size: 18,
                    color: sr.textMuted,
                  ),
                ),
                const SizedBox(width: SrSpacing.md),
                Expanded(
                  child: Text(
                    product.productName,
                    style: SrTypography.sectionTitle.copyWith(
                      color: sr.foreground,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: SrSpacing.lg),
            Wrap(
              spacing: SrSpacing.xl,
              runSpacing: SrSpacing.sm,
              children: <Widget>[
                for (final ({String label, String value}) detail in details)
                  _Detail(label: detail.label, value: detail.value),
              ],
            ),

            if (product.description != null) ...<Widget>[
              const SizedBox(height: SrSpacing.lg),
              Text(
                product.description!,
                style: SrTypography.body.copyWith(color: sr.textSecondary),
                // Bounded so one verbose description cannot make a card
                // dominate the grid. Nothing is hidden that a person needs: the
                // identifying fields are all above it.
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _semanticLabel(List<({String label, String value})> details) {
    final StringBuffer buffer = StringBuffer('${product.productName}.');
    for (final ({String label, String value}) detail in details) {
      buffer.write(' ${detail.label}: ${detail.value}.');
    }
    if (product.description != null) {
      buffer.write(' ${product.description}');
    }
    return buffer.toString();
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: SrTypography.caption.copyWith(color: sr.textMuted)),
        const SizedBox(height: SrSpacing.xxs),
        Text(value, style: SrTypography.body.copyWith(color: sr.foreground)),
      ],
    );
  }
}
