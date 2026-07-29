import '../entities/vendor_retailer_lifecycle_status.dart';
import '../entities/vendor_retailer_manage_capability.dart';
import 'vendor_retailer_write_result.dart';

/// The Vendor Retailer **lifecycle** surface: one write, and one probe.
///
/// ## Why this is a separate interface from `VendorRetailerRepository`
///
/// That interface's contract says, in its own words, that the Retailer milestone
/// is read-only and that *"there is no onboard, invite, suspend, create-shop or
/// edit-shop method here and no place to add one without changing this
/// interface"*. That guarantee is worth keeping rather than quietly rewriting:
/// its three reads are `STABLE`, take at most a relationship id, and are covered
/// by a boundary test that asserts exactly that.
///
/// So the write lives here, beside its own capability probe, on the same split
/// `RetailerStaffInvitationRepository` and `RetailerStaffShopAssignmentRepository`
/// already use for the Retailer side — one repository per contract, so each
/// one's boundary test can assert its payload vocabulary exactly.
///
/// ## What the signatures make impossible
///
/// [setRetailerStatus] takes a `vendor_retailers.id` and a two-member enum. It
/// takes no Vendor organization id, Retailer organization id, actor id, profile
/// id, membership id, role code, permission code, current status, audit action
/// or timestamp — the RPC accepts none of those, and none is expressible here.
///
/// The Retailer **organization** id is deliberately not accepted either. The
/// schema permits several Vendors to manage one Retailer, so an organization id
/// does not identify whose relationship is meant; the relationship id names
/// exactly one Retailer as seen by exactly one Vendor, which is what makes the
/// RPC's single tenant predicate a complete cross-tenant boundary.
///
/// [manageCapability] takes the Vendor organization id, and that is the one
/// argument on this interface that names a tenant. It must come from the
/// authenticated session's server-resolved portal context and from nowhere else
/// — never a route parameter, a form field, local storage or a Retailer record.
/// Even so, `has_organization_permission` is `SECURITY DEFINER` and hard-filtered
/// to `auth.uid()`: it requires an ACTIVE profile, an ACTIVE membership **of the
/// organization asked about**, an ACTIVE organization and an ACTIVE role carrying
/// the permission, so a substituted id could only ever answer `false`.
abstract interface class VendorRetailerLifecycleRepository {
  /// `public.set_vendor_retailer_status(p_relationship_id, p_status)`.
  ///
  /// Issues **exactly one** RPC call and never retries. A failure of any kind is
  /// returned for the caller to decide about: an automatic retry after a
  /// committed write is indistinguishable, from here, from a retry after a
  /// failed one.
  ///
  /// A successful response whose body cannot be trusted returns
  /// [VendorRetailerWriteUnconfirmed] — never a failure, and never a fabricated
  /// success.
  Future<VendorRetailerWriteResult> setRetailerStatus({
    required String relationshipId,
    required VendorRetailerLifecycleStatus status,
  });

  /// `public.has_organization_permission(organization, 'RETAILERS_MANAGE')`.
  ///
  /// Presentation only. Never cached, never persisted, and never treated as
  /// permission to write — see [VendorRetailerManageCapability].
  ///
  /// Returns [VendorRetailerManageCapability.unavailable] for every failure and
  /// for any response that is not a genuine boolean. A non-boolean is **not**
  /// coerced: treating a null or a string as `false` would assert a definite
  /// denial this client has no grounds for.
  Future<VendorRetailerManageCapability> manageCapability(
    String vendorOrganizationId,
  );
}
