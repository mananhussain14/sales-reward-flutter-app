import 'package:equatable/equatable.dart';

import 'vendor_retailer_status.dart';

/// One row of `public.list_vendor_retailer_shops(uuid)`.
///
/// Six columns, addressed by the **relationship id** rather than by a Retailer
/// organization id, so this read and the detail read cannot drift into two
/// address spaces and a foreign id is inert here for the same reason it is inert
/// there.
///
/// ## Three of the six are nullable, and that is the schema, not a shortcut
///
/// `retailer_shops` declares `code`, `city` and `country_code` as `null`-able. A
/// shop without a code is an ordinary shop, so the parser accepts absence — and
/// refuses a present value of the wrong type, which is a different thing.
///
/// ## What is deliberately absent
///
/// `address_line1`, `address_line2`, `region`, `postal_code`, `created_at`,
/// `updated_at` and `retailer_organization_id` — the caller supplied the
/// relationship and the detail read already told them the Retailer. There is no
/// status filter in SQL either: a `SUSPENDED` or `DEACTIVATED` shop stays
/// listed, so this list can never contradict the `shop_count` on the detail.
final class VendorRetailerShop extends Equatable {
  const VendorRetailerShop({
    required this.shopId,
    required this.shopName,
    required this.shopStatus,
    this.shopCode,
    this.city,
    this.countryCode,
  });

  /// `retailer_shops.id`. Returned so a list can key its rows — the web's
  /// index-keyed shop list is exactly what a mobile widget cannot use.
  final String shopId;

  final String shopName;

  /// The shop's lifecycle state. Never inferred: a missing status is a format
  /// error, and an unrecognised one is [VendorRetailerStatus.unknown], which is
  /// not active.
  final VendorRetailerStatus shopStatus;

  final String? shopCode;
  final String? city;
  final String? countryCode;

  @override
  List<Object?> get props => <Object?>[
    shopId,
    shopName,
    shopStatus,
    shopCode,
    city,
    countryCode,
  ];
}
