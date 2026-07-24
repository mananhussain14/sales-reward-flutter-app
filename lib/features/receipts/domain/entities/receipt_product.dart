import 'package:equatable/equatable.dart';

/// One product a Vendor has actively assigned to the caller's own Retailer.
///
/// Produced by `public.list_my_receipt_products()`, which takes **zero
/// arguments**.
///
/// ## This is reference data, and only reference data
///
/// The deployed submission endpoint accepts **one shop id and one file**. It has
/// no parameter for a product, a quantity or a line item, and
/// `public.receipt_submissions` stores none — the migration says so directly:
///
/// > *"No product is attached to a submission here, because receipts and
/// > products are related only in the future OCR/matching step."*
///
/// So a [ReceiptProduct] is shown to help a submitter recognise what the
/// catalogue contains. Selecting one grants nothing, changes nothing about the
/// request, and is deliberately not modelled.
final class ReceiptProduct extends Equatable {
  const ReceiptProduct({
    required this.productId,
    required this.productCode,
    required this.productName,
    this.barcode,
    this.brand,
  });

  /// `product_id` — a UUID, validated on parse.
  final String productId;

  /// `product_code` — NOT NULL, stored upper-cased and normalized.
  final String productCode;

  /// `product_name` — NOT NULL.
  final String productName;

  /// `barcode` — nullable; 8–14 digits when present.
  final String? barcode;

  /// `brand` — nullable.
  final String? brand;

  /// Whether this product matches a free-text filter, matched over every field
  /// the backend actually returns.
  bool matches(String query) {
    final String needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return true;
    }
    return productName.toLowerCase().contains(needle) ||
        productCode.toLowerCase().contains(needle) ||
        (brand?.toLowerCase().contains(needle) ?? false) ||
        (barcode?.contains(needle) ?? false);
  }

  @override
  List<Object?> get props => <Object?>[
    productId,
    productCode,
    productName,
    barcode,
    brand,
  ];
}
