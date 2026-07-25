import '../../../../core/result/read_result.dart';
import '../entities/vendor_user_detail.dart';
import '../entities/vendor_user_summary.dart';

/// The two Vendor User reads, and nothing else.
///
/// One repository for both deliberately: they share a Vendor derivation, a
/// selector vocabulary and a failure contract, and splitting them would create
/// two places for those to drift. It is also the whole surface — this milestone
/// is **read-only**, so there is no invite, edit, activate, deactivate or
/// assign-role method here and no place to add one without changing this
/// interface.
///
/// Inviting in particular has no backend at all, not merely no read contract:
/// nothing in the schema invites a person into a VENDOR organization.
///
/// ## What the signatures make impossible
///
/// [users] takes **no arguments**. [userDetail] takes exactly one, and it is a
/// membership id. There is no auth user id, profile id, Vendor organization id,
/// role, permission code, tenant id, email or status parameter anywhere on this
/// interface — not as an optional, not as a named argument with a default. The
/// absence is the point: the Vendor is derived from `auth.uid()` in SQL by
/// `get_vendor_super_admin_context()`, and the membership is matched on **both**
/// its own id and that derived Vendor.
///
/// ## What "zero rows" means
///
/// [userDetail] answers `null` for an unknown id, another Vendor's id, a
/// **Retailer-owned** membership id, a null id and a malformed id **alike** —
/// one indistinguishable result, because a distinguishable refusal would confirm
/// that a membership the caller may not read nevertheless exists, and by
/// sweeping ids, roughly how many.
///
/// A zero-row answer is a **success carrying null**, never a failure: the
/// backend answered, and reporting it as an outage would offer a retry that
/// cannot change anything.
abstract interface class VendorUserRepository {
  /// `public.list_vendor_users()` — zero arguments.
  ///
  /// An empty list is a legitimate answer and is never produced from a failure.
  /// In practice it is not reachable while the caller is authorized: an
  /// authorized caller is by definition an ACTIVE member of the Vendor they are
  /// listing, so their own row is always present. A Vendor whose only user is
  /// its administrator returns exactly one row — which is the real "no other
  /// users" case, and the one the empty state should be written against.
  ///
  /// A refusal is `42501` and arrives as a [ReadFailure], because a denial and
  /// an empty directory are opposite claims.
  Future<ReadResult<List<VendorUserSummary>>> users();

  /// `public.get_vendor_user_detail(p_membership_id)`.
  ///
  /// Returns `null` inside a success for zero rows. See the class comment.
  Future<ReadResult<VendorUserDetail?>> userDetail(String membershipId);
}
