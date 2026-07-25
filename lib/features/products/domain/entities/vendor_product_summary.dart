import 'package:equatable/equatable.dart';

import 'vendor_product_status.dart';

/// One row of `public.list_vendor_products()`.
///
/// Ten fields, which are exactly the ten columns the deployed function returns —
/// and there is no field it does not return. In particular there is **no**
/// `vendor_organization_id`, no `created_by_profile_id`, no audit metadata, no
/// category, and **no image of any kind**.
///
/// ## There is no product image, anywhere
///
/// Not "not returned yet" — it does not exist. The backend audit searched the
/// whole repository and recorded the finding as § 9:
///
/// > *`public.vendor_products` has **no** image, photo, media, asset, thumbnail
/// > or storage column. **No storage bucket holds product media.** Neither web
/// > product page renders an image, and `lib/products/*` contains **zero**
/// > storage calls.*
///
/// So there is no `imageUrl` here, no placeholder for one, and no widget in this
/// feature that reserves space for one. A thumbnail frame with a fallback glyph
/// would advertise an image system that would then have to be built to explain
/// itself.
///
/// ## There is no category either
///
/// No category column exists. A label derived from the brand, the code prefix or
/// the name would be a taxonomy this client invented, and it would immediately
/// disagree with the web catalogue showing the same rows.
///
/// ## Why this is not the same class as `VendorProductDetail`
///
/// The list genuinely does not return `assignment_count` — only the detail read
/// does, and the list was deliberately left unchanged. A single entity would
/// therefore need a **nullable** count, and a nullable count is ambiguous: null
/// would mean both "this product has zero assignments" *(impossible — the detail
/// returns `0`, never null)* and "this row came from the list, where the total
/// was never computed". Collapsing a real value with an absent one is exactly
/// what every other field in this contract refuses to do.
///
/// The two classes share ten field names and no inheritance. A `VendorProductDetail
/// extends VendorProductSummary` would let the detail silently widen the list's
/// contract, and a future column added to only one read would have somewhere to
/// hide. What *is* shared is the parsing of the ten common columns, in
/// `vendor_product_parsers.dart` — safe precisely because the backend pins the
/// shared columns byte-identical in name, type and meaning, and asserts that
/// relationship structurally.
final class VendorProductSummary extends Equatable {
  const VendorProductSummary({
    required this.productId,
    required this.productCode,
    required this.barcode,
    required this.productName,
    required this.brand,
    required this.description,
    required this.status,
    required this.activeAssignmentCount,
    required this.createdAt,
    required this.updatedAt,
  });

  /// `vendor_products.id` — the selector both companion reads take, and the
  /// segment the detail route carries.
  ///
  /// It is the right selector because it **is** the tenant boundary:
  /// `vendor_organization_id` is `NOT NULL` and immutable by trigger, so a
  /// product belongs to exactly one Vendor for its whole life and an id from
  /// another Vendor's catalogue matches nothing. Holding one therefore grants
  /// nothing.
  final String productId;

  /// The canonical internal code — normalized upper-case by the database. Never
  /// null and never blank.
  ///
  /// Unique **per Vendor**, not globally
  /// (`vendor_products_code_unique_idx (vendor_organization_id, product_code)`),
  /// so two Vendors may each own `A-100`. Nothing here treats it as a global
  /// identifier.
  final String productCode;

  /// The GTIN-family barcode, or **null** when the product has none.
  ///
  /// The single barcode field: there is no separate SKU, GTIN, EAN or UPC
  /// column, so none is modelled. Null is a real answer and is never replaced by
  /// the product code, by a generated value, or by an empty string dressed as
  /// data.
  final String? barcode;

  /// The display name. Never null, never blank.
  ///
  /// **Not unique**, even within one Vendor — only the code and the barcode are
  /// — so nothing may key, address or de-duplicate a product by its name.
  final String productName;

  /// The stored brand, or **null** when the product has none. Never fabricated.
  final String? brand;

  /// The stored description, or **null**. Never fabricated, and never composed
  /// from the name or the brand.
  final String? description;

  /// The product's own place in the catalogue.
  ///
  /// Returned unfiltered by the backend and rendered unfiltered here: a
  /// catalogue that hid `INACTIVE` products would misrepresent what is stored.
  final VendorProductStatus status;

  /// How many Retailers hold an **`ACTIVE`** assignment of this product.
  ///
  /// Never null; `0` is a real answer. Computed in SQL as a correlated
  /// `count(*)` filtered to `status = 'ACTIVE'`, so it arrives with the row and
  /// is never assembled by a second read.
  ///
  /// It counts **only** assignment status. It does *not* consult the product's
  /// own status, the Vendor–Retailer relationship status, or the Retailer
  /// organization's status — an active assignment to a suspended Retailer still
  /// counts. That is the shipped meaning of the number the web catalogue prints
  /// today, and narrowing it here would silently disagree with it.
  ///
  /// The **total** assignment count is deliberately absent: the list does not
  /// return one. See [VendorProductDetail.assignmentCount].
  final int activeAssignmentCount;

  /// When the product was created. UTC. The backend's primary sort key
  /// (`created_at desc, id desc`).
  final DateTime createdAt;

  /// When the product row last changed. UTC.
  final DateTime updatedAt;

  /// Whether no Retailer currently holds this product.
  ///
  /// Says nothing about whether one ever did — that question needs
  /// `assignment_count`, which this row does not carry.
  bool get hasNoActiveAssignments => activeAssignmentCount == 0;

  /// The lower-cased haystack the local search matches against.
  ///
  /// Name, code, barcode and brand — the four fields a reader can actually see
  /// on a card. The description is deliberately excluded: matching a paragraph
  /// would surface rows whose reason for matching is invisible in the result.
  ///
  /// Absent values contribute nothing rather than an empty string, so a search
  /// for `''` is never "matched" by a product that has no barcode.
  String get searchHaystack => <String>[
    productName,
    productCode,
    ?barcode,
    ?brand,
  ].join(' ').toLowerCase();

  @override
  List<Object?> get props => <Object?>[
    productId,
    productCode,
    barcode,
    productName,
    brand,
    description,
    status,
    activeAssignmentCount,
    createdAt,
    updatedAt,
  ];
}
