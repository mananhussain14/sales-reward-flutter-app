import 'package:equatable/equatable.dart';

/// One row of `public.list_retailer_assigned_products()`.
///
/// ## Every row is doubly ACTIVE, which is why there is no status to model
///
/// The contract's `where` clause is `a.status = 'ACTIVE' and vp.status =
/// 'ACTIVE'`, so a row exists only when **both** the assignment and the product
/// are active. `assignment_status` is therefore returned but constant: it is
/// `'ACTIVE'` for every row that can ever appear.
///
/// It is carried anyway, as [assignmentStatus], and validated — because a value
/// that is constant by construction is exactly the kind of assumption that
/// silently stops being true when a contract widens. What is **not** done is
/// building a status filter, a badge palette or an "inactive" tab around a
/// column that has one value: that would advertise a distinction the data cannot
/// express.
///
/// The consequence for the screen is stated plainly in its copy: this is the
/// list of products **currently** assigned. It is not a history, and the backend
/// offers no way to see withdrawn assignments.
///
/// ## `productId` is not carried
///
/// The contract returns `product_id`. Nothing here holds it. This milestone is
/// read-only: there is no product detail screen, no assignment write, no
/// reorder, no receipt link — nothing that could address a product. Carrying a
/// UUID for no purpose puts an identifier on a phone and invites the first write
/// feature to trust one from a stale list.
///
/// The Retailer cannot modify assignments at all. That is a Vendor capability on
/// a different surface, gated by `PRODUCT_RETAILER_ASSIGN`, and no RPC that
/// performs it is named anywhere in the Retailer portal.
final class RetailerAssignedProduct extends Equatable {
  const RetailerAssignedProduct({
    required this.productCode,
    required this.productName,
    required this.barcode,
    required this.brand,
    required this.description,
    required this.assignmentStatus,
  });

  /// `vendor_products.product_code`. `NOT NULL`, stored normalized (upper-cased,
  /// trimmed, internal whitespace collapsed).
  final String productCode;

  /// `vendor_products.product_name`. `NOT NULL`.
  final String productName;

  /// `vendor_products.barcode` — nullable. A GTIN-family barcode when present.
  final String? barcode;

  /// `vendor_products.brand` — nullable.
  final String? brand;

  /// `vendor_products.description` — nullable.
  final String? description;

  /// `vendor_product_retailer_assignments.status`.
  ///
  /// Always `'ACTIVE'` on this contract — see the class doc. Kept as the raw
  /// token rather than an enum precisely because there is no second value to
  /// discriminate: an enum with one member would imply a choice that does not
  /// exist. It is validated by the parser and is **not rendered**; the screen
  /// says "currently assigned" in fixed copy instead.
  final String assignmentStatus;

  /// Whether the assignment is the active one the contract guarantees.
  ///
  /// Structurally always true for a row that parsed. Exposed so a test can pin
  /// the guarantee rather than assume it.
  bool get isActiveAssignment => assignmentStatus == 'ACTIVE';

  @override
  List<Object?> get props => <Object?>[
    productCode,
    productName,
    barcode,
    brand,
    description,
    assignmentStatus,
  ];
}
