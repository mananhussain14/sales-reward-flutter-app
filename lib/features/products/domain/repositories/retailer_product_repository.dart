import '../../../../core/errors/retailer_read_problem.dart';
import '../entities/retailer_assigned_product.dart';

/// The outcome of the one Retailer product read.
sealed class RetailerProductsResult {
  const RetailerProductsResult();
}

/// The rows, already parsed. Possibly empty, which is a real answer meaning "no
/// Vendor currently assigns you anything".
final class RetailerProductsLoaded extends RetailerProductsResult {
  const RetailerProductsLoaded(this.products);

  final List<RetailerAssignedProduct> products;
}

/// The read did not produce an answer.
final class RetailerProductsFailed extends RetailerProductsResult {
  const RetailerProductsFailed(this.problem);

  final RetailerReadProblem problem;
}

/// The one Retailer assigned-product read, and nothing else.
///
/// ## The signature is the security property
///
/// [products] takes **no arguments at all**. There is no Retailer organization
/// id, product id, vendor id, assignment id, auth user id, profile id,
/// membership id, tenant id, role code, permission code, status filter or search
/// term anywhere on this interface.
///
/// `public.list_retailer_assigned_products()` is declared with an empty
/// parameter list and scopes itself with `where a.retailer_organization_id =
/// resolve_retailer_member_organization('RETAILER_PRODUCTS_READ')`, deriving the
/// caller from `auth.uid()`. There is nothing for a client to supply and
/// therefore nothing for a client to forge — in particular, no Vendor can be
/// named, so this read cannot be pointed at another Vendor's catalogue.
///
/// ## This is a read, and the Retailer could not write here even if it tried
///
/// There is no assign, unassign, edit, create, delete or reorder method, and no
/// place to add one without changing this file. That is not merely this
/// milestone's scope: assignment writes are gated on `PRODUCT_RETAILER_ASSIGN`,
/// which is a **Vendor** capability. `assign_vendor_product_to_retailer` and
/// `unassign_vendor_product_from_retailer` are not named anywhere in the
/// Retailer portal, and product create/edit/status are Vendor RPCs on a
/// different surface entirely.
///
/// ## Both Retailer roles may call this
///
/// Unlike Shops (Owner-only) and Invitations (manage-only), this read resolves
/// through the *member* resolver on `RETAILER_PRODUCTS_READ`, which both the
/// Retailer Owner and the Retailer Manager hold. Sales Staff do not and are
/// refused with `42501`.
abstract interface class RetailerProductRepository {
  /// `public.list_retailer_assigned_products()` — every currently assigned
  /// product, in one round trip.
  ///
  /// ## Only currently-active assignments exist in the answer
  ///
  /// The contract filters on `a.status = 'ACTIVE' and vp.status = 'ACTIVE'`, so
  /// a withdrawn assignment and a discontinued product are both simply absent.
  /// There is **no history** available: no RPC returns inactive assignments to a
  /// Retailer, so the client must not offer a toggle, a filter or a tab that
  /// implies one exists.
  ///
  /// An empty list therefore means "nothing is assigned to you right now" — a
  /// real, successful answer — and never "you are not allowed". A refusal is
  /// `42501` and arrives as [RetailerReadProblem.denied].
  Future<RetailerProductsResult> products();
}
