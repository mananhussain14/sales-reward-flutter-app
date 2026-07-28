import '../../../../core/errors/retailer_read_problem.dart';
import '../entities/retailer_assignable_shop.dart';
import '../entities/retailer_staff_invitation_outcome.dart';
import '../entities/retailer_staff_invitation_request.dart';

/// The outcome of the assignable-shops read.
sealed class RetailerAssignableShopsResult {
  const RetailerAssignableShopsResult();
}

/// The rows, already parsed.
///
/// An **empty** list is a real answer and is never confused with a refusal: the
/// function raises `insufficient_privilege` for an unresolved caller precisely
/// so that "you may not see this" cannot be mistaken for "this Retailer has no
/// shops" — a distinction the invite form depends on to avoid telling an Owner
/// their Retailer is empty when they were in fact refused.
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

/// The outcome of one invitation send.
///
/// Two cases, and the split is the point: either the function answered in its
/// own vocabulary, or it did not answer in a way this build can use. Every
/// decision about retrying, clearing the form and re-reading the history is made
/// from one of the two, and never from an HTTP status this type does not carry.
sealed class RetailerStaffInvitationSendResult {
  const RetailerStaffInvitationSendResult();
}

/// The function answered with a valid, version-1 contract response.
///
/// [outcome] is read first and decides whether an email may have gone out;
/// [code] only refines the reason and may be
/// [RetailerStaffInvitationCode.unrecognized] for a token this build does not
/// know.
///
/// **This is not a synonym for success.** A [RetailerStaffInvitationOutcome.deliveryFailed]
/// and every `NOT_SENT` reason arrive here too — they are answers, and a refusal
/// the backend stated clearly is worth more than a transport guess.
final class RetailerStaffInvitationAnswered
    extends RetailerStaffInvitationSendResult {
  const RetailerStaffInvitationAnswered({
    required this.outcome,
    required this.code,
  });

  final RetailerStaffInvitationOutcome outcome;
  final RetailerStaffInvitationCode code;
}

/// No usable answer: a transport fault, a timeout, no session, or a body this
/// build could not read.
///
/// Never carries an HTTP body, a PostgREST message, a SQLSTATE, provider text, a
/// stack trace, an invitation token or a token hash — the type has no field any
/// of those could occupy.
final class RetailerStaffInvitationUnanswered
    extends RetailerStaffInvitationSendResult {
  const RetailerStaffInvitationUnanswered(this.problem);

  final RetailerStaffInvitationTransportProblem problem;
}

/// The Retailer staff **invitation** contracts: one read and one write.
///
/// ## Why this is separate from `RetailerStaffRepository`
///
/// That interface is the read portal's, its own documentation guarantees it
/// holds no write, and both of its methods are nullary reads of `STABLE`
/// functions. Bolting a send onto it would falsify that guarantee for the roster
/// and the invitation history as well. These two operations sit on a third
/// permission (`assignable shops`) and on the shared Edge Function, so they get
/// their own interface in the same feature — extending it rather than
/// duplicating it.
///
/// ## What a caller may nominate, exhaustively
///
/// Nothing at all for [assignableShops]; the five contract fields for [send].
/// There is no Retailer organization id, actor / user / profile id, membership
/// id, invitation id, token, token hash, audit field, invitation state,
/// normalized email, expiry, permission code, service-role credential or Resend
/// setting anywhere on this interface, and no place to add one without changing
/// this file.
///
/// ## What is deliberately absent
///
/// No accept, no revoke, no resend, no role change, no activation or
/// deactivation, no post-acceptance shop reassignment, and no shop write. Every
/// one of those is either a different backend operation this milestone does not
/// implement or, in the case of acceptance, a flow that lives entirely in the
/// web portal.
abstract interface class RetailerStaffInvitationRepository {
  /// `public.list_retailer_staff_assignable_shops()` — the ACTIVE shops that may
  /// be attached to a Sales Staff invitation, with their ids.
  ///
  /// ## Zero arguments, and that is the whole contract
  ///
  /// The deployed function is declared with an empty parameter list. There is no
  /// Retailer id, organization id, relationship id or membership id to pass, so
  /// no URL segment, form field, header or cookie can nominate whose shops come
  /// back. The Retailer is derived inside the function from `auth.uid()` through
  /// the established resolver, which fails closed when the caller resolves to
  /// zero or to more than one qualifying Retailer.
  ///
  /// ## A refusal is an exception, never an empty list
  ///
  /// An unresolved caller raises the same generic `42501` every other staff
  /// operation raises, which arrives as [RetailerReadProblem.denied]. That is
  /// what lets the form say "you were refused" rather than "your Retailer has no
  /// shops".
  ///
  /// ## Only assignable shops exist on this contract
  ///
  /// The function filters `status = 'ACTIVE'` itself, matching what the
  /// reservation will accept. This client applies no status filter of its own —
  /// there is no status column to filter on.
  Future<RetailerAssignableShopsResult> assignableShops();

  /// `send-retailer-staff-invitation` — the shared delivery Edge Function.
  ///
  /// ## One implementation of "send a staff invitation", for both clients
  ///
  /// The web portal posts to the same function. The reserve → prepare → send →
  /// record sequence, the token construction, the email content and this
  /// response vocabulary therefore exist in exactly one place, and the two
  /// clients cannot hold different opinions about what a valid request or a
  /// stable outcome is.
  ///
  /// Three of the four RPCs behind it are granted to the privileged database
  /// role alone, and the function also holds the delivery-provider credential.
  /// **Neither key exists
  /// anywhere in this application**, which is precisely why the operation is an
  /// Edge Function call and not an RPC.
  ///
  /// ## It never retries, and neither may any caller
  ///
  /// One request, one answer. A repeated write re-reserves, mints a new token
  /// and rotates the hash — killing a link that may already be in someone's
  /// inbox and sending a second email — so a retry is a deliberate human
  /// decision and never an automatic one, least of all after a 2xx.
  Future<RetailerStaffInvitationSendResult> send(
    RetailerStaffInvitationRequest request,
  );
}
