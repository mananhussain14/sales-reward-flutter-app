import '../entities/vendor_retailer_detail.dart';
import '../entities/vendor_retailer_shop.dart';
import '../entities/vendor_retailer_summary.dart';
import 'vendor_retailer_result.dart';

/// The three Vendor Retailer reads, and nothing else.
///
/// One repository for all three deliberately: they share a Vendor derivation, a
/// selector vocabulary and a failure contract, and splitting them would create
/// three places for those to drift. It is also the whole surface — this
/// milestone is **read-only**, so there is no onboard, invite, suspend, create-
/// shop or edit-shop method here and no place to add one without changing this
/// interface.
///
/// ## What the signatures make impossible
///
/// [retailers] takes **no arguments**. [retailerDetail] and [retailerShops] take
/// exactly one, and it is a relationship id. There is no user id, profile id,
/// Vendor organization id, membership id, role, permission code, tenant id or
/// Retailer organization id parameter anywhere on this interface — not as an
/// optional, not as a named argument with a default. The absence is the point:
/// the Vendor is derived from `auth.uid()` in SQL by
/// `get_vendor_super_admin_context()`, and the relationship is matched on
/// **both** its own id and that derived Vendor.
///
/// ## What "zero rows" means, and why the ordering matters
///
/// [retailerDetail] answers `null` for an unknown id, another Vendor's id and a
/// malformed id **alike** — one indistinguishable result, because a
/// distinguishable refusal would confirm that a relationship the caller may not
/// read nevertheless exists.
///
/// [retailerShops] answers an empty list for a shop-less Retailer of the
/// caller's own *and* for a relationship that is not addressable by them. That
/// ambiguity is why a caller loads the detail **first**: a `null` there is the
/// authoritative "not addressable", and an empty shop list after a successful
/// detail is an honest "this Retailer has no shops".
abstract interface class VendorRetailerRepository {
  /// `public.list_vendor_retailers()` — zero arguments.
  ///
  /// An empty list is a real answer ("this Vendor has not onboarded a Retailer
  /// yet") and is never produced from a failure. A refusal is `42501` and
  /// arrives as a [VendorRetailerReadFailure], because a denial and an empty
  /// directory are opposite claims.
  Future<VendorRetailerResult<List<VendorRetailerSummary>>> retailers();

  /// `public.get_vendor_retailer_detail(p_relationship_id)`.
  ///
  /// Returns `null` inside a success for zero rows. See the class comment.
  Future<VendorRetailerResult<VendorRetailerDetail?>> retailerDetail(
    String relationshipId,
  );

  /// `public.list_vendor_retailer_shops(p_relationship_id)`.
  ///
  /// Call only after [retailerDetail] confirmed the relationship.
  Future<VendorRetailerResult<List<VendorRetailerShop>>> retailerShops(
    String relationshipId,
  );
}
