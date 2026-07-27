import '../../../../core/errors/retailer_read_problem.dart';
import '../entities/retailer_shop.dart';

/// The outcome of the one Retailer shop read.
sealed class RetailerShopsResult {
  const RetailerShopsResult();
}

/// The rows, already parsed. Possibly empty — see
/// [RetailerShopRepository.shops] for why an empty list is genuinely ambiguous
/// on this contract.
final class RetailerShopsLoaded extends RetailerShopsResult {
  const RetailerShopsLoaded(this.shops);

  final List<RetailerShop> shops;
}

/// The read did not produce an answer.
final class RetailerShopsFailed extends RetailerShopsResult {
  const RetailerShopsFailed(this.problem);

  final RetailerReadProblem problem;
}

/// The one Retailer shop read, and nothing else.
///
/// ## The signature is the security property
///
/// [shops] takes **no arguments at all**. There is no Retailer organization id,
/// shop id, auth user id, profile id, membership id, tenant id, role code,
/// permission code, status filter or search term anywhere on this interface —
/// not as an optional, not as a named argument with a default.
///
/// `public.list_retailer_owner_portal_shops()` is declared with an empty
/// parameter list and scopes itself with
/// `where s.retailer_organization_id =
/// resolve_retailer_owner_organization('RETAILER_SHOPS_READ')`, which derives
/// the caller from `auth.uid()`. There is nothing for a client to supply and
/// therefore nothing for a client to forge.
///
/// Search is a **presentation** concern applied to rows already read (see the
/// cubit). It is not expressible here, because sending a filter would be sending
/// a parameter.
///
/// ## Read-only, and the interface is the proof
///
/// There is no create, edit, activate, deactivate or delete method here, and no
/// place to add one without changing this file. The backend function is declared
/// `STABLE` and contains no insert, update or delete.
///
/// ## There is no detail read, because there is no id to read by
///
/// The contract returns no `shop_id`. No detail RPC exists on the backend, no
/// route addresses a shop, and this interface offers no `shopById`. Adding one
/// would require an identifier that does not exist.
abstract interface class RetailerShopRepository {
  /// `public.list_retailer_owner_portal_shops()` — every shop, in one round
  /// trip.
  ///
  /// ## An empty list is ambiguous on this contract, deliberately
  ///
  /// The function does **not** raise on refusal. Its `where` clause compares
  /// against a resolver that returns NULL for an unauthorized or ambiguous
  /// caller, and `= NULL` matches no row — so a Retailer Manager, a Sales Staff
  /// member and a Retailer Owner whose organization genuinely has no shops all
  /// receive **exactly the same empty result**.
  ///
  /// The migration is explicit that this is the intent: an unauthorized caller
  /// "gets an empty list rather than another retailer's estate".
  ///
  /// This client preserves that ambiguity rather than resolving it. It does not
  /// probe the caller's role to decide which empty state to show, and it does
  /// not claim "you have no shops" is a permission outcome or the reverse. The
  /// screen shows one honest empty state, and the Manager never reaches it
  /// because the Manager's navigation carries no Shops destination at all.
  ///
  /// A [RetailerShopsFailed] therefore means a genuine fault — transport,
  /// timeout, an unreadable body — and never "you are not allowed", because this
  /// function has no way to say that.
  Future<RetailerShopsResult> shops();
}
