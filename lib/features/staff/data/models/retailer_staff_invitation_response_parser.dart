import '../../domain/entities/retailer_staff_invitation_outcome.dart';
import '../../domain/repositories/retailer_staff_invitation_repository.dart';

/// Maps one Edge Function reply to a send result.
///
/// Separated from the transport so the whole mapping table is testable without a
/// socket, and so that adding a code is a change to one pure function.
///
/// ## `outcome` is read before `code`, always
///
/// The contract calls `outcome` the safety-critical field: it alone answers
/// *might an email have been delivered?*, which is what decides whether
/// repeating the write could invalidate a link already in someone's inbox. So an
/// unreadable or unrecognised `outcome` fails the whole response, while an
/// unrecognised `code` degrades to [RetailerStaffInvitationCode.unrecognized]
/// and the screen falls back to the outcome's generic copy.
///
/// A response whose `code` belongs to a **different** outcome is treated the
/// same way as an unknown code. The two disagreeing is evidence of drift, and
/// preferring the code would mean preferring the field the contract says is not
/// the authority.
///
/// ## `version` must be exactly 1
///
/// The version is bumped only for a breaking change — a removed field, a changed
/// field meaning, or a repurposed outcome. Reading a version this build has never
/// seen would mean guessing at the one question that must not be guessed at, so
/// it is refused. A numeric `1` is accepted in either JSON representation; a
/// string `"1"`, a boolean, or anything else is not a version.
///
/// ## Nothing from the reply is retained
///
/// No field of the body, no HTTP status, no reason phrase and no provider text
/// travels past this function. The result types have nowhere to put any of them,
/// so no backend message, SQLSTATE, invitation id, raw token, token hash or email
/// link can reach a screen through this path.
///
/// ## The one place the status is consulted
///
/// A bare `401` with no contract body is the API gateway refusing the request
/// before the function ran — the shape an expired or absent session takes. That
/// is reported as [RetailerStaffInvitationTransportProblem.signedOut] rather than
/// as an unreadable answer, because "sign in again" is actionable and "the
/// service said something odd" is not. Every other non-contract reply is
/// [RetailerStaffInvitationTransportProblem.malformed], which is deliberately
/// treated as *unresolved* rather than as a failure: nothing in it says whether
/// an email went out.
RetailerStaffInvitationSendResult mapRetailerStaffInvitationReply({
  required int status,
  required Object? body,
}) {
  if (body is! Map) {
    return _unreadable(status);
  }

  final Map<String, Object?> reply = body.map<String, Object?>(
    (Object? key, Object? value) => MapEntry<String, Object?>('$key', value),
  );

  final Object? version = reply['version'];
  if (version is! num || version != retailerStaffInvitationContractVersion) {
    return _unreadable(status);
  }

  final Object? rawOutcome = reply['outcome'];
  if (rawOutcome is! String) {
    return _unreadable(status);
  }

  final RetailerStaffInvitationOutcome? outcome =
      RetailerStaffInvitationOutcome.fromToken(rawOutcome);
  if (outcome == null) {
    return _unreadable(status);
  }

  // Everything from here is additive-safe: a missing, non-string, unknown or
  // contradictory code still leaves a fully usable answer, because the outcome
  // has already settled what happened to the email.
  final Object? rawCode = reply['code'];
  final RetailerStaffInvitationCode? declared = rawCode is String
      ? RetailerStaffInvitationCode.fromToken(rawCode)
      : null;

  final RetailerStaffInvitationCode code =
      (declared != null && declared.outcome == outcome)
      ? declared
      : RetailerStaffInvitationCode.unrecognized;

  // Any additional top-level field is ignored. The contract is closed today, but
  // a client that failed on an unfamiliar key would break on the first purely
  // additive deployment.
  return RetailerStaffInvitationAnswered(outcome: outcome, code: code);
}

/// The reply is not a version-1 contract response.
RetailerStaffInvitationSendResult _unreadable(int status) {
  // 401 alone: the gateway refuses before the function runs and answers in its
  // own vocabulary, not this one.
  if (status == 401) {
    return const RetailerStaffInvitationUnanswered(
      RetailerStaffInvitationTransportProblem.signedOut,
    );
  }
  return const RetailerStaffInvitationUnanswered(
    RetailerStaffInvitationTransportProblem.malformed,
  );
}
