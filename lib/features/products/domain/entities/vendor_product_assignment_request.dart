import 'package:equatable/equatable.dart';

/// The whole payload of an assignment write: two addresses, and nothing else.
///
/// ## The field list is the security property
///
/// Both deployed functions take exactly two `uuid` parameters —
/// `p_product_id` and `p_retailer_organization_id` — and this type has exactly
/// two fields with the same meanings. There is no auth user id, profile id,
/// membership id, Vendor organization id, tenant id, relationship id, role code,
/// permission code, actor, audit metadata, assignment id, assignment status,
/// note, price, quantity or effective date here, and there is nowhere to put
/// one: a request object with no such field cannot send it, whatever a caller
/// intends.
///
/// The Vendor is derived server-side from `auth.uid()` through
/// `get_vendor_super_admin_context()`, and both ids are then matched against
/// **that** derived Vendor. So neither id is an authorization — holding one
/// grants nothing, and another Vendor's Product id or Retailer organization id
/// matches zero rows and is refused byte-identically to an id that names
/// nothing.
///
/// ## Why the Retailer is addressed by its organization id
///
/// Because the stored column is `retailer_organization_id`:
/// `vendor_product_retailer_assignments` has **no relationship_id column at
/// all**. And because `relationship_id` is *nullable* in the assignment read —
/// the relationship join is a `LEFT JOIN`, so an assignment whose
/// `vendor_retailers` row ever ceased to exist still appears — which would make
/// a relationship-addressed write un-callable for exactly the historical rows
/// that most need withdrawing.
///
/// Ownership is still proven: the write reaches the Retailer only through the
/// derived Vendor's own `vendor_retailers` row, so the same Retailer
/// organization legitimately managed by two Vendors yields each of them their
/// own assignment row and neither can touch the other's.
///
/// **`relationship_id` is never sent.** It is the address the *Retailer detail
/// screen* accepts, and it is used for navigation and for nothing else.
///
/// ## Shape is checked here, existence is not
///
/// [isAddressable] answers whether both values are shaped like a uuid. That is
/// deliberately a *shape* test and never an existence or permission test: a
/// malformed id put into a `uuid` parameter comes back as a PostgREST cast error
/// raised **before** the function body runs and therefore before any
/// authorization check, which is neither an authorization answer nor an outage.
/// Deciding it locally keeps the write error model to the outcomes the contract
/// actually defines, and says nothing about whether any Product or Retailer
/// exists.
final class VendorProductAssignmentRequest extends Equatable {
  const VendorProductAssignmentRequest({
    required this.productId,
    required this.retailerOrganizationId,
  });

  /// `vendor_products.id` — the same selector the detail read takes.
  ///
  /// One id for the read and the write on purpose: two operations addressed by
  /// one value cannot drift into two address spaces.
  final String productId;

  /// `organizations.id` of the Retailer.
  ///
  /// The value the assignment read and the Retailer directory both **return**,
  /// carried straight back without translation. It is never derived from a
  /// display name, never typed by a person, and never read from a route.
  final String retailerOrganizationId;

  /// Whether both values are shaped like a uuid.
  ///
  /// Both, not either: a well-formed Product id beside a malformed Retailer id
  /// is still a request that cannot reach the function body.
  bool get isAddressable =>
      _isUuidShaped(productId) && _isUuidShaped(retailerOrganizationId);

  @override
  List<Object?> get props => <Object?>[productId, retailerOrganizationId];
}

/// The 8-4-4-4-12 hexadecimal shape PostgreSQL's `uuid` type accepts.
///
/// Case-insensitive, because PostgREST accepts either and the backend stores
/// one canonical form; anchored at both ends, so a uuid embedded in a longer
/// string is not mistaken for one.
final RegExp _uuidShape = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

bool _isUuidShaped(String value) => _uuidShape.hasMatch(value);
