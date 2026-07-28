import '../entities/retailer_staff_invitation_outcome.dart';
import '../entities/retailer_staff_invitation_request.dart';
import 'retailer_assignable_shops_reader.dart';

// The assignable-shops read and its result types moved to
// `retailer_assignable_shops_reader.dart` when a second feature — the
// post-acceptance shop editor — needed the same deployed contract. They are
// re-exported so this file remains the one import an invitation caller needs,
// and so the move cost no call site anywhere.
export 'retailer_assignable_shops_reader.dart';

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
abstract interface class RetailerStaffInvitationRepository
    implements RetailerAssignableShopsReader {
  /// `public.list_retailer_staff_assignable_shops()` — the ACTIVE shops that may
  /// be attached to a Sales Staff invitation, with their ids.
  ///
  /// Declared on [RetailerAssignableShopsReader], which the shop-assignment
  /// editor also consumes: one deployed contract, one Dart contract. See that
  /// interface for the zero-argument guarantee and for why a refusal arrives as
  /// an exception rather than as an empty list.
  @override
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
