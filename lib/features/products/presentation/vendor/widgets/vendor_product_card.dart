import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/vendor_product_summary.dart';
import 'vendor_product_badges.dart';
import 'vendor_product_copy.dart';
import 'vendor_product_formatting.dart';

/// One product in the catalogue.
///
/// ## It has to *look* openable, and it does so three times over
///
/// The placeholder this screen replaces gave no hint that a row led anywhere.
/// This card carries a trailing chevron, an explicit "View details" affordance
/// at its foot, and the interactive card treatment (press state, brand-tinted
/// border) — so the affordance survives whether a reader is scanning shapes,
/// reading words, or feeling for a touch target. The whole card is the target,
/// not the 16px glyph.
///
/// ## There is no image, and no space reserved for one
///
/// No product image exists anywhere in this product — no column, no bucket, no
/// storage call, and no image on either web product page. So this card shows no
/// thumbnail, and deliberately no grey placeholder frame either: a fallback
/// glyph in an image-shaped box would advertise an image system that would then
/// have to be built to explain itself. The leading disc is a product **icon**,
/// fixed for every row, and is not an image slot.
///
/// ## Only fields the list read returns
///
/// Name, code, barcode, brand, status, active assignment count and the two
/// dates. There is no category — no such column exists — no price, no reward, no
/// incentive, no inventory and no shop count, because none of those exists
/// anywhere in the schema.
///
/// **No total assignment count either.** `list_vendor_products()` does not
/// return one, so the card's count line is worded strictly as the *active*
/// figure: "2 Retailers currently hold this", never "2 of 5".
class VendorProductCard extends StatelessWidget {
  const VendorProductCard({
    super.key,
    required this.product,
    required this.onOpen,
  });

  final VendorProductSummary product;
  final VoidCallback onOpen;

  /// The one spoken sentence this card presents.
  ///
  /// Everything visible, in order, so a screen reader user is not made to walk a
  /// pill and four lines to learn the same thing. It names no uuid — the product
  /// code is the identifier a person actually uses, and the id is an address.
  ///
  /// Absent optional fields are spoken as the neutral phrase rather than
  /// skipped, so a listener can tell "this product has no barcode" from "the
  /// barcode was not read out".
  static String semanticsFor(VendorProductSummary product) =>
      '${product.productName}. '
      '${VendorProductStatusBadge.semanticsFor(product.status)}. '
      '${VendorProductCopy.codeLabel}: ${product.productCode}. '
      '${VendorProductCopy.barcodeLabel}: ${formatOptional(product.barcode)}. '
      '${VendorProductCopy.brandLabel}: ${formatOptional(product.brand)}. '
      '${formatActiveAssignmentCount(product.activeAssignmentCount)}.';

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Semantics(
      button: true,
      label: semanticsFor(product),
      hint: VendorProductCopy.openDetails,
      excludeSemantics: true,
      child: SrCard(
        variant: SrCardVariant.interactive,
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SrIconDisc(
                  icon: Icons.inventory_2_rounded,
                  tone: SrTone.indigo,
                  size: 40,
                ),
                const SizedBox(width: SrSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        product.productName,
                        style: SrTypography.cardTitle.copyWith(
                          color: sr.foreground,
                        ),
                        // Two lines then ellipsis: a long name wraps rather than
                        // being cut at the first overflow.
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: SrSpacing.xs),
                      Text(
                        'Updated ${formatProductDate(product.updatedAt)}',
                        style: SrTypography.caption.copyWith(
                          color: sr.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: SrSpacing.sm),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: sr.textMuted,
                ),
              ],
            ),
            const SizedBox(height: SrSpacing.lg),
            // Wrap rather than Row: the pill must run onto its own line on a
            // 360px phone at large text scale instead of overflowing.
            Wrap(
              spacing: SrSpacing.sm,
              runSpacing: SrSpacing.sm,
              children: <Widget>[
                VendorProductStatusBadge(status: product.status),
              ],
            ),
            const SizedBox(height: SrSpacing.md),
            // The code is never absent — it is NOT NULL and normalized — so it
            // is always shown, and it is what a person uses to name a product.
            VendorProductIdentifierLine(
              icon: Icons.qr_code_2_rounded,
              label: VendorProductCopy.codeLabel,
              value: product.productCode,
              monospace: true,
            ),
            // Barcode and brand are nullable and are simply omitted when absent.
            // A "Not recorded" line on a card would spend a row saying nothing;
            // the detail screen states the absence explicitly, and the card's
            // semantics label does too, so the fact is never actually lost.
            if (product.barcode != null) ...<Widget>[
              const SizedBox(height: SrSpacing.xs),
              VendorProductIdentifierLine(
                icon: Icons.qr_code_scanner_rounded,
                label: VendorProductCopy.barcodeLabel,
                value: product.barcode!,
                monospace: true,
              ),
            ],
            if (product.brand != null) ...<Widget>[
              const SizedBox(height: SrSpacing.xs),
              VendorProductIdentifierLine(
                icon: Icons.sell_outlined,
                label: VendorProductCopy.brandLabel,
                value: product.brand!,
              ),
            ],
            const SizedBox(height: SrSpacing.md),
            _AssignmentLine(product: product),
            const SizedBox(height: SrSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                Text(
                  VendorProductCopy.openDetails,
                  style: SrTypography.caption.copyWith(color: sr.brand),
                ),
                Icon(Icons.arrow_forward_rounded, size: 14, color: sr.brand),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The active-assignment sentence.
///
/// Strictly the *active* figure, because that is the only assignment number the
/// list read returns. The zero case is worded as a fact — "No Retailer currently
/// holds this" — rather than as a warning: a product with no active assignment
/// is an ordinary state, not a problem this screen is entitled to diagnose.
class _AssignmentLine extends StatelessWidget {
  const _AssignmentLine({required this.product});

  final VendorProductSummary product;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final Color color = product.hasNoActiveAssignments
        ? sr.textMuted
        : sr.textSecondary;
    final String label = formatActiveAssignmentCount(
      product.activeAssignmentCount,
    );

    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: SrSpacing.xxs),
            child: Icon(Icons.storefront_outlined, size: 14, color: color),
          ),
          const SizedBox(width: SrSpacing.xs),
          Expanded(
            child: Text(
              label,
              style: SrTypography.caption.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// The responsive arrangement for product cards.
///
/// The layout itself lives in [SrResponsiveGrid]; what belongs here is the pair
/// of numbers, which is a property of *this* content. A product card carries up
/// to three identifier lines and a full-sentence count line — "No Retailer
/// currently holds this" is not a short string — so it needs roughly the width a
/// role card does before a second column stops crowding it.
class VendorProductGrid extends StatelessWidget {
  const VendorProductGrid({super.key, required this.children});

  final List<Widget> children;

  /// Below this a second column would squeeze the identifier lines.
  static const double twoUpThreshold = 800;

  /// Above this a third column still leaves each card wider than a phone.
  static const double threeUpThreshold = 1150;

  @override
  Widget build(BuildContext context) {
    return SrResponsiveGrid(
      twoUpThreshold: twoUpThreshold,
      threeUpThreshold: threeUpThreshold,
      children: children,
    );
  }
}
