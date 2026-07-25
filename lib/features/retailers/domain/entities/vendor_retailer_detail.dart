import 'package:equatable/equatable.dart';

import 'retailer_owner_state.dart';
import 'vendor_retailer_status.dart';

/// The one row `public.get_vendor_retailer_detail(uuid)` returns.
///
/// ## Why this is a separate type from `VendorRetailerSummary`
///
/// The detail contract is the list contract **plus two columns**
/// ([countryCode], [defaultCurrency]) — the only two Retailer profile fields the
/// web detail page shows and the directory does not. Every shared column is
/// identical in name, type and meaning, and the backend's static contract test
/// pins that relation so a future column has to be added to both or to neither.
///
/// A single entity with two nullable extras would have made "did the list give
/// me a country, or does this Retailer not have one?" unanswerable, and every
/// screen would have had to know which read produced the value it holds. Two
/// types make that question unrepresentable instead.
///
/// ## What is deliberately absent
///
/// No owner name, email or timestamp; no invitation id, token, `token_hash`,
/// `failure_code` or `invitation_kind`; no `vendor_organization_id`; no
/// membership, role or permission internals; no Retailer staff; no receipt; and
/// no `updated_at`. Shops are **not** nested — a Retailer's shop list is
/// unbounded, so it is the companion read `list_vendor_retailer_shops(uuid)`.
final class VendorRetailerDetail extends Equatable {
  const VendorRetailerDetail({
    required this.relationshipId,
    required this.retailerOrganizationId,
    required this.retailerName,
    required this.retailerStatus,
    required this.countryCode,
    required this.defaultCurrency,
    required this.relationshipStatus,
    required this.relationshipCreatedAt,
    required this.shopCount,
    required this.activeShopCount,
    required this.ownerState,
  });

  final String relationshipId;
  final String retailerOrganizationId;
  final String retailerName;
  final VendorRetailerStatus retailerStatus;

  /// `organizations.country_code`. **Nullable in the schema**
  /// (`country_code text null`), so a Retailer that never recorded one is a
  /// legitimate answer and not a malformed response.
  final String? countryCode;

  /// `organizations.default_currency`. Nullable for the same reason.
  final String? defaultCurrency;

  final VendorRetailerStatus relationshipStatus;
  final DateTime relationshipCreatedAt;
  final int shopCount;
  final int activeShopCount;
  final RetailerOwnerState ownerState;

  int get inactiveShopCount => shopCount - activeShopCount;

  @override
  List<Object?> get props => <Object?>[
    relationshipId,
    retailerOrganizationId,
    retailerName,
    retailerStatus,
    countryCode,
    defaultCurrency,
    relationshipStatus,
    relationshipCreatedAt,
    shopCount,
    activeShopCount,
    ownerState,
  ];
}
