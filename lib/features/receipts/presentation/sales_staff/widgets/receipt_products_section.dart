import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/errors/errors.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/receipt_product.dart';
import 'receipt_copy.dart';

/// The eligible-products reference section.
///
/// ## Reference, and nothing more
///
/// `list_my_receipt_products()` tells a submitter what their Retailer stocks.
/// The deployed submission endpoint accepts a shop id and a file — there is no
/// product parameter, `receipt_submissions` stores no product, and receipts and
/// products are related only in a future OCR/matching step that does not exist.
///
/// So this section is **read-only by construction**: no row is selectable, no
/// row carries a checkbox or a quantity, and nothing in it can reach the
/// request. Rendering a picker here would create an authority the backend does
/// not have — and would quietly promise that the chosen product was attached to
/// the receipt, which would be false.
///
/// Collapsed by default so it never competes with the submit button, and
/// searchable because a real catalogue is longer than a phone screen.
class ReceiptProductsSection extends StatefulWidget {
  const ReceiptProductsSection({
    super.key,
    required this.products,
    this.failure,
    this.onRetry,
  });

  final List<ReceiptProduct> products;

  /// Set when the product read failed. Products are context rather than a
  /// prerequisite, so a failure degrades this section alone and never blocks a
  /// submission.
  final Failure? failure;

  final VoidCallback? onRetry;

  @override
  State<ReceiptProductsSection> createState() => _ReceiptProductsSectionState();
}

class _ReceiptProductsSectionState extends State<ReceiptProductsSection> {
  final TextEditingController _search = TextEditingController();
  bool _expanded = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<ReceiptProduct> get _visible {
    final String query = _search.text;
    if (query.trim().isEmpty) {
      return widget.products;
    }
    return widget.products
        .where((ReceiptProduct product) => product.matches(query))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return SrSectionCard(
      title: 'Eligible products',
      description: ReceiptCopy.productsReferenceDescription,
      action: widget.failure != null || widget.products.isEmpty
          ? null
          : SrButton(
              label: _expanded ? 'Hide' : 'Show',
              variant: SrButtonVariant.ghost,
              size: SrButtonSize.sm,
              icon: _expanded
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
              onPressed: () => setState(() => _expanded = !_expanded),
            ),
      child: _body(sr),
    );
  }

  Widget _body(SrColorScheme sr) {
    if (widget.failure != null) {
      return SrFailureView(failure: widget.failure!, onRetry: widget.onRetry);
    }

    if (widget.products.isEmpty) {
      return const SrEmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'No products listed yet',
        description:
            'Your Retailer has no products assigned right now. You can still '
            'submit a receipt.',
      );
    }

    if (!_expanded) {
      return Align(
        alignment: Alignment.centerLeft,
        child: SrBadge(
          label: widget.products.length == 1
              ? '1 product'
              : '${widget.products.length} products',
          tone: SrTone.slate,
          icon: Icons.inventory_2_outlined,
        ),
      );
    }

    final List<ReceiptProduct> visible = _visible;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SrTextField(
          label: 'Search products',
          controller: _search,
          placeholder: 'Name, code, brand or barcode',
          onChanged: (String _) => setState(() {}),
        ),
        const SizedBox(height: SrSpacing.lg),
        if (visible.isEmpty)
          Text(
            'No product matches that search.',
            style: SrTypography.body.copyWith(color: sr.textSecondary),
          )
        else
          ConstrainedBox(
            // Bounded and independently scrollable, so a long catalogue cannot
            // push the submit button off the page.
            constraints: const BoxConstraints(maxHeight: 320),
            child: Scrollbar(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: visible.length,
                separatorBuilder: (BuildContext context, int index) =>
                    Divider(color: sr.border, height: SrSpacing.xl),
                itemBuilder: (BuildContext context, int index) =>
                    _ProductRow(product: visible[index]),
              ),
            ),
          ),
      ],
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product});

  final ReceiptProduct product;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Semantics(
      // Read-only: announced as plain content, never as a control.
      container: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  product.productName,
                  style: SrTypography.label.copyWith(color: sr.foreground),
                ),
                const SizedBox(height: SrSpacing.xxs),
                Text(
                  <String?>[
                    product.brand,
                    product.productCode,
                    product.barcode,
                  ].whereType<String>().join(' · '),
                  style: SrTypography.caption.copyWith(color: sr.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
