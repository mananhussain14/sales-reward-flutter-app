import 'package:equatable/equatable.dart';

import 'receipt_product.dart';

/// The lowest and highest quantity `receipt_confirmation_products` accepts.
///
/// `check (quantity >= 1 and quantity <= 100)`. Mirrored here so a staff member
/// is stopped at the stepper rather than by a refused immutable write, and
/// enforced again in SQL because this client is not the authority.
const int minReceiptProductQuantity = 1;
const int maxReceiptProductQuantity = 100;

/// The most product lines one receipt may carry.
///
/// `check (line_number >= 1 and line_number <= 50)`, and the RPC refuses an
/// array longer than 50 before it writes anything.
const int maxReceiptProductLines = 50;

/// One product a Sales Staff member has chosen, with how many of it.
///
/// ## The catalogue fields here never reach the database
///
/// [productCode], [productName], [barcode] and [brand] exist so the selection
/// list can be read by a person. They are **display copies of what the
/// catalogue already said**, and they are deliberately not part of the write:
/// the serializer emits `product_id` and `quantity` only, and the database
/// copies every snapshot out of `vendor_products` itself.
///
/// That is not a convention that could drift. The RPC has no parameter for a
/// name, code, barcode or brand, and the table's insert assertion re-reads the
/// catalogue and refuses a row whose snapshot does not match it.
final class SelectedReceiptProduct extends Equatable {
  const SelectedReceiptProduct({
    required this.productId,
    required this.productCode,
    required this.productName,
    required this.quantity,
    this.barcode,
    this.brand,
  });

  /// Builds a selection from a catalogue row, at the default quantity.
  ///
  /// The only supported way to select: there is no constructor path from a
  /// typed-in name or a pasted UUID, so a product this Retailer is not entitled
  /// to cannot enter the list.
  ///
  /// Named `fromCatalogue` rather than `from` on purpose. `.from(` is how
  /// Supabase spells direct table access, and the receipt security boundary
  /// forbids that spelling anywhere under `features/receipts/` — a rule worth
  /// more than a shorter factory name.
  factory SelectedReceiptProduct.fromCatalogue(
    ReceiptProduct product, {
    int quantity = minReceiptProductQuantity,
  }) {
    return SelectedReceiptProduct(
      productId: product.productId,
      productCode: product.productCode,
      productName: product.productName,
      barcode: product.barcode,
      brand: product.brand,
      quantity: quantity,
    );
  }

  /// `product_id` — one of the two values that actually travels.
  final String productId;

  /// `quantity` — the other. A whole number, never a `double`: these are
  /// discrete barcoded units, and an integer removes every rounding argument
  /// from the campaign arithmetic that will read them later.
  final int quantity;

  /// Display only. Not sent.
  final String productCode;

  /// Display only. Not sent.
  final String productName;

  /// Display only. Not sent. Null when the catalogue has none.
  final String? barcode;

  /// Display only. Not sent. Null when the catalogue has none.
  final String? brand;

  /// Whether [quantity] is inside the range the database will accept.
  bool get hasValidQuantity =>
      quantity >= minReceiptProductQuantity &&
      quantity <= maxReceiptProductQuantity;

  /// The same product, one more — capped, never wrapped.
  SelectedReceiptProduct increment() => quantity >= maxReceiptProductQuantity
      ? this
      : copyWith(quantity: quantity + 1);

  /// The same product, one fewer — floored at 1. Removing a line is a separate,
  /// explicit act, so a stepper can never silently delete a selection.
  SelectedReceiptProduct decrement() => quantity <= minReceiptProductQuantity
      ? this
      : copyWith(quantity: quantity - 1);

  SelectedReceiptProduct copyWith({int? quantity}) {
    return SelectedReceiptProduct(
      productId: productId,
      productCode: productCode,
      productName: productName,
      barcode: barcode,
      brand: brand,
      quantity: quantity ?? this.quantity,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    productId,
    productCode,
    productName,
    barcode,
    brand,
    quantity,
  ];
}
