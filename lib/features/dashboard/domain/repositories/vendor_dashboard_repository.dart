import '../../../../core/result/read_result.dart';
import '../entities/vendor_dashboard_summary.dart';

/// The one Vendor Dashboard read, and nothing else.
///
/// ## The signature is the security property
///
/// [summary] takes **no arguments at all**. There is no auth user id, profile
/// id, membership id, Vendor organization id, tenant id, role code, permission
/// code, status, date range, period selector or organization selector anywhere on
/// this interface — not as an optional, not as a named argument with a default.
///
/// The absence is the point, and it mirrors the deployed function exactly:
/// `public.get_vendor_admin_dashboard_summary()` is declared with an empty
/// parameter list and derives the Vendor from `auth.uid()` through
/// `get_vendor_super_admin_context()`. There is nothing for a client to supply
/// and therefore nothing for a client to forge.
///
/// ## This milestone is read-only, and the interface is the proof
///
/// There is no write, edit, refresh-server-side, recompute, export or
/// customisation method here, and no place to add one without changing this
/// file. The backend function is declared `STABLE` and contains no insert, update
/// or delete; reading a count is not an event, so this call writes no audit row
/// of its own either.
///
/// ## What it deliberately does not return
///
/// No organization id and no organization name. The name a Dashboard shows comes
/// from the trusted Session / PortalContext the application already holds —
/// resolved by `get_my_portal_context()` through the **same** Vendor resolver and
/// the same lowest-organization-id tie-break this summary applies, so the two
/// agree by construction. Returning it here would be a second copy of one fact,
/// free to disagree with the first.
///
/// No Retailer, Product, shop, assignment or invitation count either: none of
/// those figures exists on the web dashboard, so there is no shipped definition
/// to share, and one invented here would be a product decision made in a client.
abstract interface class VendorDashboardRepository {
  /// `public.get_vendor_admin_dashboard_summary()` — the whole summary, in one
  /// round trip.
  ///
  /// An authorized caller always receives **exactly one row of four non-null,
  /// non-negative counts**. That is structural rather than a guarantee some guard
  /// could drop: the function body is a single `select` with no from-clause and
  /// four scalar aggregate subqueries, and an aggregate over an empty set is `0`
  /// rather than null or "no row". A brand-new Vendor with no members and no
  /// history therefore receives one row of zeros, not zero rows.
  ///
  /// **A refusal is `42501` and arrives as a [ReadFailure], never as zeros.** The
  /// backend raises one generic denial for every failing case — not signed in,
  /// not a Vendor Super Admin, a suspended profile or membership, and a role that
  /// no longer holds any one of the three read permissions the summary requires.
  /// This client preserves that: one denial, no permission code, no hint at which
  /// gate refused. "You may not read this summary" and "this Vendor has nothing"
  /// are opposite claims, and a dashboard that rendered four zeros for the first
  /// would be actively misleading.
  ///
  /// An **unreadable body** is an operational failure for the same reason: a
  /// response this build cannot understand is not a Vendor with no data.
  Future<ReadResult<VendorDashboardSummary>> summary();
}
