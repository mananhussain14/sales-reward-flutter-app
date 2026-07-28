import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../../core/errors/retailer_read_problem.dart';
import '../../../../core/parsing/rpc_row.dart';
import '../../domain/entities/retailer_staff_invitation_outcome.dart';
import '../../domain/entities/retailer_staff_invitation_request.dart';
import '../../domain/repositories/retailer_staff_invitation_repository.dart';
import '../datasources/retailer_staff_invitation_rpc_data_source.dart';
import '../models/retailer_assignable_shop_parser.dart';
import '../models/retailer_staff_invitation_request_body.dart';
import '../models/retailer_staff_invitation_response_parser.dart';

/// How long one invitation send may take before it is abandoned.
///
/// Longer than a portal read, because the function does real work in sequence —
/// reserve, prepare, hand the message to Resend, record — and an email provider
/// is the slow step. Short enough that a person is not left watching a spinner
/// with no result.
///
/// A timeout here is **not** a failure and never reported as one: the function
/// may have completed after this client stopped waiting, so the honest answer is
/// that the outcome is unknown and the invitation history is the authority.
const Duration retailerStaffInvitationSendTimeout = Duration(seconds: 45);

/// The real [RetailerStaffInvitationRepository].
///
/// Each method does exactly three things: perform the call, map the answer,
/// classify the fault.
///
/// ## It reproduces no backend authorization logic
///
/// There is no Retailer organization id here, no membership lookup, no role
/// check and no permission check. The Retailer is derived from `auth.uid()`
/// inside both contracts; whether the caller may list assignable shops and
/// whether they may invite are decided in SQL, twice, on every call.
///
/// ## Nothing retries
///
/// [send] performs exactly one request and returns whatever came of it. A repeat
/// would re-reserve the invitation, mint a new token and rotate the hash —
/// killing a link that may already be in the recipient's inbox and sending a
/// second email — so a retry is a deliberate human decision made on a screen,
/// never something this layer does on anyone's behalf. That holds most strongly
/// for the 202 partial success, whose *whole purpose* is to be a status no
/// client resubmits.
final class SupabaseRetailerStaffInvitationRepository
    implements RetailerStaffInvitationRepository {
  const SupabaseRetailerStaffInvitationRepository({
    required RetailerStaffInvitationRpcDataSource rpc,
    Duration readTimeout = retailerReadTimeout,
    Duration sendTimeout = retailerStaffInvitationSendTimeout,
  }) : _rpc = rpc,
       _readTimeout = readTimeout,
       _sendTimeout = sendTimeout;

  final RetailerStaffInvitationRpcDataSource _rpc;
  final Duration _readTimeout;
  final Duration _sendTimeout;

  @override
  Future<RetailerAssignableShopsResult> assignableShops() async {
    final Object? raw;
    try {
      raw = await _rpc.fetchAssignableShops().timeout(_readTimeout);
    } on Object catch (error) {
      // `42501` becomes `denied`, so a refusal can never be presented as an
      // empty picker — "you may not see this" and "your Retailer has no active
      // shops" are opposite claims, and the migration raises rather than
      // returning nothing precisely so the two stay distinguishable.
      return RetailerAssignableShopsFailed(classifyRetailerReadError(error));
    }

    try {
      return RetailerAssignableShopsLoaded(
        RetailerAssignableShopParser.parse(raw),
      );
    } on RpcFormatException {
      // The exception's own `reason` is developer-facing and stays here. Only
      // the discriminant travels onward.
      return const RetailerAssignableShopsFailed(RetailerReadProblem.malformed);
    }
  }

  @override
  Future<RetailerStaffInvitationSendResult> send(
    RetailerStaffInvitationRequest request,
  ) async {
    final RetailerStaffInvitationReply reply;
    try {
      reply = await _rpc
          .sendInvitation(encodeRetailerStaffInvitationRequest(request))
          .timeout(_sendTimeout);
    } on TimeoutException {
      // The request WAS sent. The function may have reserved, prepared and
      // delivered while this client stopped waiting, so this is the absence of
      // an answer rather than a failure — and re-sending could rotate a token
      // whose link is already in somebody's inbox.
      return const RetailerStaffInvitationUnanswered(
        RetailerStaffInvitationTransportProblem.timeout,
      );
    } on http.ClientException {
      // `package:http` wraps socket-level faults as ClientException on every
      // platform, and a browser's CORS or fetch refusal arrives the same way.
      // The request did not reach the backend.
      return const RetailerStaffInvitationUnanswered(
        RetailerStaffInvitationTransportProblem.network,
      );
    } on sb.AuthException {
      // No usable session. Deliberately not bound to a message: auth exceptions
      // can carry token material.
      return const RetailerStaffInvitationUnanswered(
        RetailerStaffInvitationTransportProblem.signedOut,
      );
    } on Object {
      // Fails closed, and never borrows the connection copy: an unexpected SDK
      // state or a programming error is not a statement about the user's
      // network. It is also not a claim that nothing was sent — the notice for
      // this case points at the invitation history rather than inviting a
      // retry.
      return const RetailerStaffInvitationUnanswered(
        RetailerStaffInvitationTransportProblem.unexpected,
      );
    }

    return mapRetailerStaffInvitationReply(
      status: reply.status,
      body: reply.body,
    );
  }
}
