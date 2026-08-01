import 'package:equatable/equatable.dart';

/// One product a campaign counts, **for the reading Retailer**.
///
/// A row of `list_my_retailer_campaign_products(uuid)` or
/// `list_my_staff_campaign_products(uuid)`. Both return the same five columns
/// and resolve them the same way.
///
/// ## Where the list comes from depends on the campaign, and that is the
/// backend's decision
///
/// * `SELECTED_PRODUCTS` reads the frozen snapshot — *"the list is exactly what
///   was resolved at publication and a later assignment change cannot alter
///   it."*
/// * `ALL_ELIGIBLE_PRODUCTS` reads the assignment **timeline** at
///   `least(now(), coalesce(ends_at, 'infinity'))`.
///
/// **Neither rule is implemented here.** No temporal resolution, no assignment
/// filtering, no date arithmetic: this client renders the rows the contract
/// returned, in the order it returned them. Reimplementing the resolution would
/// put a second definition of eligibility on a phone, and a phone's clock is not
/// the one the backend used.
///
/// ## `product_id` is returned and is not carried
///
/// Same reasoning as `RetailerAssignedProduct`: this milestone is read-only,
/// there is no product detail screen, and nothing here could address a product.
/// Carrying a UUID for no purpose puts an identifier on a device and invites the
/// first write feature to trust one from a stale list.
///
/// Duplicates are kept. The backend orders by `product_name, product_code, id`,
/// which can legitimately place two distinct catalogue rows adjacent, and
/// without `product_id` there is no key on which a genuine duplicate could be
/// told from two similar products.
final class CampaignProduct extends Equatable {
  const CampaignProduct({
    required this.productCode,
    required this.productName,
    required this.barcode,
    required this.brand,
  });

  /// `vendor_products.product_code`. `NOT NULL`, stored normalised.
  final String productCode;

  /// `vendor_products.product_name`. `NOT NULL`.
  final String productName;

  /// `vendor_products.barcode` — nullable.
  ///
  /// Refused by the parser if it arrives as a number rather than a string: a
  /// numeric barcode has already lost its leading zeros by the time a JSON
  /// parser is done with it, and a GTIN with a leading zero is a different
  /// barcode.
  final String? barcode;

  /// `vendor_products.brand` — nullable.
  final String? brand;

  @override
  List<Object?> get props => <Object?>[
    productCode,
    productName,
    barcode,
    brand,
  ];
}
