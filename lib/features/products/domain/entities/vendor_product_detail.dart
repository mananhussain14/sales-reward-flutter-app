import 'package:equatable/equatable.dart';

import 'vendor_product_status.dart';

/// The one row `public.get_vendor_product_detail(uuid)` returns.
///
/// Eleven fields: the ten `list_vendor_products()` returns, plus
/// [assignmentCount]. That is the whole difference, and the backend pins it —
/// every shared column is byte-identical in name, type and meaning, including
/// `active_assignment_count`, which is `bigint` on both sides.
///
/// ## Why this is its own class and not a subtype of `VendorProductSummary`
///
/// Two entities over one shared set of common fields is the shape the backend
/// audit recommends (§ 5.1), and the reason is [assignmentCount]:
///
/// > *a **nullable count is ambiguous**: `null` would mean both "this product
/// > has zero assignments" (impossible here — the detail returns `0`, never
/// > `null`) and "this row came from the list, where the total was never
/// > computed".*
///
/// Inheritance would be the same mistake wearing a type. If this widened
/// `VendorProductSummary`, a summary variable could hold a detail and a caller
/// could not tell whether the total was available; and a future column added to
/// only one of the two reads would have a place to hide. So the classes are
/// siblings, sharing only the parsing of the ten common columns — which is safe
/// exactly because the backend asserts those ten stay identical.
///
/// > Contrast `VendorRoleDetail`, which **is** a typedef of its summary: the
/// > role detail contract is the role list contract exactly, so a second class
/// > there would be a second place to add a future column and only one of the
/// > two could be right. The distinction is whether the shapes genuinely differ.
/// > Here they do.
final class VendorProductDetail extends Equatable {
  const VendorProductDetail({
    required this.productId,
    required this.productCode,
    required this.barcode,
    required this.productName,
    required this.brand,
    required this.description,
    required this.status,
    required this.assignmentCount,
    required this.activeAssignmentCount,
    required this.createdAt,
    required this.updatedAt,
  });

  /// `vendor_products.id`. The address this screen was opened by, and the
  /// selector the assignment companion takes.
  final String productId;

  /// The canonical internal code. Never null, never blank. Unique per Vendor.
  final String productCode;

  /// The GTIN-family barcode, or **null**. Never fabricated.
  final String? barcode;

  /// The display name. Never null, never blank, and not unique.
  final String productName;

  /// The stored brand, or **null**. Never fabricated.
  final String? brand;

  /// The stored description, or **null**. Never fabricated.
  final String? description;

  /// The product's own place in the catalogue.
  ///
  /// An `INACTIVE` product is fully readable and **keeps its assignment rows and
  /// both counts** — `set_vendor_product_status` deliberately does not cascade.
  /// So nothing on a detail screen may zero a count, hide an assignment or imply
  /// assignments are disabled on the strength of this value.
  final VendorProductStatus status;

  /// **Every** assignment row for this product, `ACTIVE` and `INACTIVE` alike.
  ///
  /// Never null; `count(*)` over an empty set is `0`. This is the one column the
  /// list has no counterpart for, and it exists so a detail screen can say "3
  /// Retailer assignments, 2 currently active" without downloading the
  /// assignment list to find out.
  ///
  /// It is **exactly** the number of rows
  /// `list_vendor_product_assigned_retailers()` returns for the same product —
  /// both are the same set over the same table with the same predicate, and the
  /// backend's pgTAP suite asserts the invariant. This client therefore reports
  /// this number rather than the length of the list it loaded: the count is the
  /// authority, the list is one rendering of it. When the two disagree, the
  /// screen says so and changes neither.
  ///
  /// An assignment is a **row**, and there is at most one row per
  /// (product, Retailer) for all time, so a Retailer assigned, withdrawn and
  /// re-assigned contributes one. History cannot inflate it.
  ///
  /// It consults neither the product's status, nor the relationship status, nor
  /// the Retailer organization's status.
  final int assignmentCount;

  /// The `ACTIVE` subset of [assignmentCount].
  ///
  /// Reproduces `list_vendor_products()`' number predicate-for-predicate, so the
  /// list and the detail of the same product can never disagree. Never null, and
  /// never greater than [assignmentCount] — the parser refuses a response where
  /// it is.
  final int activeAssignmentCount;

  /// When the product was created. UTC.
  final DateTime createdAt;

  /// When the product row last changed. UTC.
  ///
  /// The **product** row, not an assignment row: an assignment carries its own
  /// `assignment_updated_at`, and the two are unrelated.
  final DateTime updatedAt;

  /// Assignment rows that exist but are not currently in force.
  ///
  /// Never negative: the parser refuses a response whose active count exceeds
  /// its total.
  int get inactiveAssignmentCount => assignmentCount - activeAssignmentCount;

  /// Whether this product has never been assigned to any Retailer.
  ///
  /// A different question from "no Retailer holds it now", which is
  /// `activeAssignmentCount == 0` — a product withdrawn from every Retailer has
  /// a zero active count and a non-zero total.
  bool get hasNoAssignments => assignmentCount == 0;

  @override
  List<Object?> get props => <Object?>[
    productId,
    productCode,
    barcode,
    productName,
    brand,
    description,
    status,
    assignmentCount,
    activeAssignmentCount,
    createdAt,
    updatedAt,
  ];
}
