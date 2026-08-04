import 'package:equatable/equatable.dart';

import 'receipt_product.dart';
import 'selected_receipt_product.dart';

/// Why a selection cannot be submitted yet.
///
/// Client-side pre-checks only. Every one of them is enforced again in SQL, and
/// the database's answer is the one that counts — most importantly for product
/// eligibility, where the real rule is "ACTIVE and actively assigned to this
/// Retailer at proposal time" and this client carries no assignment table.
enum ReceiptProductSelectionProblem {
  /// `A receipt product proposal must contain at least one product`.
  noProductsSelected,

  /// More than 50 lines. The RPC refuses the array before writing anything.
  tooManyProducts,

  /// A quantity outside 1–100 reached the list somehow.
  invalidQuantity,

  /// The same `product_id` appears on two lines.
  ///
  /// [add] cannot produce this and neither can any other operation here, so
  /// reaching it means a selection was assembled some other way. It is checked
  /// anyway, and refused rather than de-duplicated: `unique
  /// (receipt_confirmation_id, vendor_product_id)` would roll the whole write
  /// back, and quietly merging two lines into one would submit a proposal
  /// nobody built.
  duplicateProduct,

  /// A selected product is not in the catalogue this screen loaded.
  ///
  /// Raised by [ReceiptProductProposalSnapshot], which is the only place that
  /// knows what the catalogue held; a selection on its own cannot answer it.
  notInCatalogue,
}

/// The Sales Staff product proposal, before it is submitted.
///
/// An immutable value: every mutation returns a new selection, so a widget can
/// never hold a half-edited list and a Cubit can compare states by equality.
///
/// ## Order is the proposal
///
/// `line_number` is not sent — the database derives it from array position — so
/// the order of [products] IS the line numbering. Every operation here preserves
/// it: adding appends, changing a quantity replaces in place, and removing
/// closes the gap. Nothing sorts.
///
/// ## Duplicates are refused, never merged
///
/// `unique (receipt_confirmation_id, vendor_product_id)`. Selecting a product
/// that is already in the list does **not** add a second line and does **not**
/// silently add to the first one's quantity: quietly changing a number a person
/// did not type is how a proposal stops matching what they meant. The caller is
/// told which line already holds it so the UI can point at it instead.
final class ReceiptProductSelection extends Equatable {
  const ReceiptProductSelection({
    this.products = const <SelectedReceiptProduct>[],
  });

  /// The chosen products, in the order they will be numbered.
  final List<SelectedReceiptProduct> products;

  bool get isEmpty => products.isEmpty;

  bool get isNotEmpty => products.isNotEmpty;

  int get lineCount => products.length;

  /// The sum of every quantity. Display and Audit-metadata parity only.
  int get totalQuantity => products.fold<int>(
    0,
    (int sum, SelectedReceiptProduct p) => sum + p.quantity,
  );

  bool get isFull => products.length >= maxReceiptProductLines;

  bool contains(String productId) =>
      products.any((SelectedReceiptProduct p) => p.productId == productId);

  /// The 1-based line a product already occupies, or null when it is unselected.
  ///
  /// Lets the UI scroll to and highlight the existing line rather than pretend
  /// a second tap did nothing.
  int? lineNumberOf(String productId) {
    for (int i = 0; i < products.length; i++) {
      if (products[i].productId == productId) {
        return i + 1;
      }
    }
    return null;
  }

  /// Adds a catalogue product at quantity 1.
  ///
  /// Returns the selection **unchanged** when the product is already selected or
  /// the list is full. Both are states the caller must surface; neither is a
  /// silent success.
  ReceiptProductSelection add(ReceiptProduct product) {
    if (contains(product.productId) || isFull) {
      return this;
    }
    return ReceiptProductSelection(
      products: <SelectedReceiptProduct>[
        ...products,
        SelectedReceiptProduct.fromCatalogue(product),
      ],
    );
  }

  ReceiptProductSelection remove(String productId) {
    if (!contains(productId)) {
      return this;
    }
    return ReceiptProductSelection(
      products: products
          .where((SelectedReceiptProduct p) => p.productId != productId)
          .toList(growable: false),
    );
  }

  /// Replaces one line's quantity, in place, keeping its position.
  ReceiptProductSelection setQuantity(String productId, int quantity) {
    if (quantity < minReceiptProductQuantity ||
        quantity > maxReceiptProductQuantity) {
      return this;
    }
    return _mapLine(
      productId,
      (SelectedReceiptProduct p) => p.copyWith(quantity: quantity),
    );
  }

  ReceiptProductSelection increment(String productId) =>
      _mapLine(productId, (SelectedReceiptProduct p) => p.increment());

  ReceiptProductSelection decrement(String productId) =>
      _mapLine(productId, (SelectedReceiptProduct p) => p.decrement());

  ReceiptProductSelection _mapLine(
    String productId,
    SelectedReceiptProduct Function(SelectedReceiptProduct) change,
  ) {
    if (!contains(productId)) {
      return this;
    }
    return ReceiptProductSelection(
      products: products
          .map(
            (SelectedReceiptProduct p) =>
                p.productId == productId ? change(p) : p,
          )
          .toList(growable: false),
    );
  }

  /// The first rule this selection breaks, or null when it breaks none.
  ReceiptProductSelectionProblem? validate() {
    if (products.isEmpty) {
      return ReceiptProductSelectionProblem.noProductsSelected;
    }
    if (products.length > maxReceiptProductLines) {
      return ReceiptProductSelectionProblem.tooManyProducts;
    }
    final Set<String> seen = <String>{};
    for (final SelectedReceiptProduct p in products) {
      if (!p.hasValidQuantity) {
        return ReceiptProductSelectionProblem.invalidQuantity;
      }
      if (!seen.add(p.productId)) {
        return ReceiptProductSelectionProblem.duplicateProduct;
      }
    }
    return null;
  }

  bool get isSubmittable => validate() == null;

  @override
  List<Object?> get props => <Object?>[products];
}
