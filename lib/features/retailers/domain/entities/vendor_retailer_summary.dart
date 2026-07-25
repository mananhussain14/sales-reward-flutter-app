import 'package:equatable/equatable.dart';

import 'retailer_owner_state.dart';
import 'vendor_retailer_status.dart';

/// One row of `public.list_vendor_retailers()`.
///
/// Every field is a column the deployed function actually returns, and there is
/// no field it does not return. In particular there is **no** owner name, email
/// or timestamp, no invitation id, token, hash or failure code, no shop rows, no
/// membership, role or permission internals, and no `vendor_organization_id` —
/// the caller already knows which Vendor they are, and an id in a payload is one
/// a form could echo back.
///
/// ## `retailerOrganizationId` is an output, never an input
///
/// It is carried so a future screen can cross-link to the product-assignment
/// API, which addresses the same tenant that way. It is never sent to any of the
/// three reads: [relationshipId] is the narrower selector, naming *this Vendor's
/// view of one Retailer*, so a foreign value matches nothing rather than
/// selecting a Retailer some other Vendor manages.
final class VendorRetailerSummary extends Equatable {
  const VendorRetailerSummary({
    required this.relationshipId,
    required this.retailerOrganizationId,
    required this.retailerName,
    required this.retailerStatus,
    required this.relationshipStatus,
    required this.relationshipCreatedAt,
    required this.shopCount,
    required this.activeShopCount,
    required this.ownerState,
  });

  /// `vendor_retailers.id` — the selector the detail and shop reads take, and
  /// the segment the detail route carries.
  final String relationshipId;

  /// `organizations.id` of the Retailer. Display and cross-linking only.
  final String retailerOrganizationId;

  final String retailerName;

  /// The Retailer company's own lifecycle state.
  final VendorRetailerStatus retailerStatus;

  /// This Vendor's relationship state — a **separate fact** from
  /// [retailerStatus], rendered as its own badge.
  final VendorRetailerStatus relationshipStatus;

  /// When this Vendor onboarded this Retailer. UTC.
  final DateTime relationshipCreatedAt;

  /// **Every** shop, whatever its status — the same number the web directory
  /// shows, so the two clients cannot disagree.
  final int shopCount;

  /// The `ACTIVE` subset of [shopCount].
  final int activeShopCount;

  final RetailerOwnerState ownerState;

  /// Shops that are counted but not active. Never negative: the parser refuses
  /// a response whose active count exceeds its total.
  int get inactiveShopCount => shopCount - activeShopCount;

  @override
  List<Object?> get props => <Object?>[
    relationshipId,
    retailerOrganizationId,
    retailerName,
    retailerStatus,
    relationshipStatus,
    relationshipCreatedAt,
    shopCount,
    activeShopCount,
    ownerState,
  ];
}
