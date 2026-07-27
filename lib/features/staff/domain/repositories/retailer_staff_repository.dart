import '../../../../core/errors/retailer_read_problem.dart';
import '../entities/retailer_staff_invitation.dart';
import '../entities/retailer_staff_member.dart';

/// The outcome of the staff roster read.
sealed class RetailerStaffResult {
  const RetailerStaffResult();
}

/// The roster rows, already parsed. Possibly empty, which is a real answer.
final class RetailerStaffLoaded extends RetailerStaffResult {
  const RetailerStaffLoaded(this.members);

  final List<RetailerStaffMember> members;
}

/// The roster read did not produce an answer.
final class RetailerStaffFailed extends RetailerStaffResult {
  const RetailerStaffFailed(this.problem);

  final RetailerReadProblem problem;
}

/// The outcome of the invitation-history read.
sealed class RetailerInvitationsResult {
  const RetailerInvitationsResult();
}

/// The invitation rows, already parsed. Possibly empty.
final class RetailerInvitationsLoaded extends RetailerInvitationsResult {
  const RetailerInvitationsLoaded(this.invitations);

  final List<RetailerStaffInvitation> invitations;
}

/// The invitation read did not produce an answer.
///
/// [RetailerReadProblem.denied] is the **expected** outcome for a Retailer
/// Manager, whose resolver call for `RETAILER_STAFF_MANAGE` returns NULL and
/// causes the function to raise. That is why the Manager screen does not call
/// this read at all — see [RetailerStaffRepository.invitations].
final class RetailerInvitationsFailed extends RetailerInvitationsResult {
  const RetailerInvitationsFailed(this.problem);

  final RetailerReadProblem problem;
}

/// The two Retailer staff reads, and nothing else.
///
/// ## Both signatures are the security property
///
/// Neither method takes **any argument at all**. There is no Retailer
/// organization id, membership id, invitation id, shop id, profile id, auth user
/// id, tenant id, role code, permission code, status filter or search term
/// anywhere on this interface.
///
/// Both deployed functions are declared with empty parameter lists and resolve
/// their tenant through `resolve_retailer_member_organization(<permission>)`,
/// which derives the caller from `auth.uid()`. There is nothing for a client to
/// supply and therefore nothing for a client to forge.
///
/// ## This milestone is read-only, and the interface is the proof
///
/// There is no invite, resend, revoke, role change, activate, deactivate or shop
/// assignment method here, and no place to add one without changing this file.
/// Both backend functions are `STABLE`. Sending an invitation additionally
/// requires the `send-staff-invitation` Edge Function, which holds the delivery
/// credential and is not called anywhere in this application.
///
/// ## The two reads are companions, not a transaction
///
/// They are separate RPCs on **different permissions** — `RETAILER_STAFF_READ`
/// and `RETAILER_STAFF_MANAGE` — so one can succeed while the other fails, and
/// that is a normal state rather than an error. The cubit models them
/// independently for exactly that reason: a roster that loaded must not be
/// erased because the invitation history did not, and the screen must not claim
/// both failed when only one did.
abstract interface class RetailerStaffRepository {
  /// `public.list_retailer_staff_members()` — the roster, in one round trip.
  ///
  /// ## The caller's role decides which rows come back, in SQL
  ///
  /// The function's final predicate is `and (v_can_manage or m.status =
  /// 'ACTIVE')`. A Retailer Owner holds `RETAILER_STAFF_MANAGE` and receives
  /// every membership status; a Retailer Manager does not and receives only
  /// `ACTIVE` members. Both receive the same shape.
  ///
  /// **This client applies no equivalent filter.** It renders what it was given.
  /// A Manager seeing fewer people is the database answering a narrower
  /// question, not the app hiding rows — and re-implementing the rule here would
  /// create a second definition free to drift from the one that is enforced.
  ///
  /// A refusal is `42501` and arrives as [RetailerReadProblem.denied], never as
  /// an empty roster. Sales Staff are refused outright: their role holds no
  /// `RETAILER_STAFF_READ`, the resolver returns NULL, and the function raises.
  Future<RetailerStaffResult> members();

  /// `public.list_retailer_staff_invitations()` — the invitation history.
  ///
  /// ## Owner-only, and the caller is expected to know that
  ///
  /// This function resolves through `RETAILER_STAFF_MANAGE` and **raises
  /// `42501`** when that returns NULL. A Retailer Manager therefore always fails
  /// this call.
  ///
  /// The Manager screen does not call it — not because the client is enforcing
  /// the permission, but because issuing a request whose only possible outcome
  /// is a refusal is pointless work that would put a denial notice on a screen
  /// where nothing is wrong. The authorization decision remains entirely the
  /// backend's: if a Manager's role were granted the permission tomorrow, this
  /// method would start succeeding with no change here.
  ///
  /// `derived_state` may be **null** for an unmatched `PENDING` combination —
  /// the backend's `CASE` has no `ELSE`. That is a real value on this contract
  /// and is surfaced as [RetailerInvitationState.indeterminate] rather than
  /// treated as malformed.
  Future<RetailerInvitationsResult> invitations();
}
