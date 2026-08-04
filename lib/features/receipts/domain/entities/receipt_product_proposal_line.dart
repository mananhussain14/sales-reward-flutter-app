import 'package:equatable/equatable.dart';

/// One line of the immutable Sales Staff product proposal, as the database
/// stored it.
///
/// Every text field here is a **snapshot frozen at proposal time**, copied out
/// of `vendor_products` by the database. A later rename, rebrand, barcode
/// reassignment or deactivation does not change it, which is the whole point:
/// this is what was proposed, not what the catalogue says today.
///
/// Returned by `get_my_receipt_product_proposal(uuid)`, whose seven columns are
/// the entire output. There is no proposal-line id, confirmation id, product id,
/// Vendor id or Retailer id to receive — the function does not return them, and
/// this type could not carry one if it wanted to.
final class ReceiptProductProposalLine extends Equatable {
  const ReceiptProductProposalLine({
    required this.lineNumber,
    required this.quantity,
    required this.productCode,
    required this.productName,
    required this.productStatus,
    this.barcode,
    this.brand,
  });

  /// `line_number` — 1-based, and the order the staff member submitted.
  final int lineNumber;

  /// `quantity` — a whole number, 1–100.
  final int quantity;

  /// `product_code_at_proposal`.
  final String productCode;

  /// `product_name_at_proposal`.
  final String productName;

  /// `barcode_at_proposal` — null when the catalogue had none.
  final String? barcode;

  /// `brand_at_proposal` — null when the catalogue had none.
  final String? brand;

  /// `product_status_at_proposal` — ACTIVE or INACTIVE **as of that moment**.
  ///
  /// Kept as a plain string rather than an enum: it is a historical fact copied
  /// from the catalogue, and a value this build does not recognise must still
  /// render rather than crash a submitted receipt.
  final String productStatus;

  @override
  List<Object?> get props => <Object?>[
    lineNumber,
    quantity,
    productCode,
    productName,
    barcode,
    brand,
    productStatus,
  ];
}
