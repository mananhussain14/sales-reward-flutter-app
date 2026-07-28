import '../../../../core/errors/retailer_read_problem.dart';
import '../entities/retailer_assignable_shop.dart';

/// The outcome of the assignable-shops read.
sealed class RetailerAssignableShopsResult {
  const RetailerAssignableShopsResult();
}

/// The rows, already parsed.
///
/// An **empty** list is a real answer and is never confused with a refusal: the
/// function raises `insufficient_privilege` for an unresolved caller precisely
/// so that "you may not see this" cannot be mistaken for "this Retailer has no
/// shops" — a distinction both callers depend on to avoid telling an Owner their
/// Retailer is empty when they were in fact refused.
final class RetailerAssignableShopsLoaded
    extends RetailerAssignableShopsResult {
  const RetailerAssignableShopsLoaded(this.shops);

  final List<RetailerAssignableShop> shops;
}

/// The read did not produce an answer. [RetailerReadProblem.denied] is `42501`.
final class RetailerAssignableShopsFailed
    extends RetailerAssignableShopsResult {
  const RetailerAssignableShopsFailed(this.problem);

  final RetailerReadProblem problem;
}

/// `public.list_retailer_staff_assignable_shops()` — the ACTIVE shops this
/// caller's Retailer may attach to a Sales Staff member, with their ids.
///
/// ## Why this is its own interface
///
/// Two features need the same read for the same reason. Invite Staff populates
/// the picker attached to a **new** invitation; Manage Shops populates the
/// picker that replaces an **existing** member's assignments. It is one deployed
/// contract, so it gets one Dart contract — a second method on a second
/// interface would be a second definition of "which shops may be assigned", free
/// to drift from the first and free to acquire a parameter the deployed function
/// does not have.
///
/// `RetailerStaffInvitationRepository` implements this, which is what lets the
/// shop-assignment editor consume the read without depending on the invitation
/// vocabulary and without a second registration in the injector.
///
/// ## Zero arguments, and that is the whole contract
///
/// The deployed function is declared with an empty parameter list. There is no
/// Retailer id, organization id, relationship id, membership id, shop id, role
/// code, permission code, status filter, search term, sort or page selector to
/// pass, so no URL segment, form field, header or cookie can nominate whose
/// shops come back. The Retailer is derived inside the function from
/// `auth.uid()` through the established resolver, which fails closed when the
/// caller resolves to zero or to more than one qualifying Retailer.
///
/// **In particular there is no membership parameter.** The list is the
/// Retailer's assignable estate, not "the shops available to this person": the
/// function has no idea which member the caller has open, and asking it to would
/// mean sending the target's id on a read that does not need it.
///
/// ## Only ACTIVE shops exist here
///
/// The function filters `status = 'ACTIVE'` itself, matching what the write will
/// accept. No client applies a status filter of its own and none could — there
/// is no status column on this contract to filter on. A suspended or deactivated
/// shop is not "shown as unavailable"; it is absent.
abstract interface class RetailerAssignableShopsReader {
  /// The assignable shops, in one round trip. Takes nothing.
  Future<RetailerAssignableShopsResult> assignableShops();
}
