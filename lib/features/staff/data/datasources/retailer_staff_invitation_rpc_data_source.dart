import 'package:supabase_flutter/supabase_flutter.dart';

/// The assignable-shops RPC, named exactly once in the application.
const String retailerStaffAssignableShopsRpc =
    'list_retailer_staff_assignable_shops';

/// The shared delivery Edge Function, named exactly once in the application.
///
/// The web portal posts to this same function, so "send a staff invitation"
/// exists once for both clients. The three service-role RPCs behind it, the
/// token construction and the Resend credential all live inside it and appear
/// nowhere in this binary.
const String sendRetailerStaffInvitationFunction =
    'send-retailer-staff-invitation';

/// Invokes `list_retailer_staff_assignable_shops()`.
///
/// ## Zero arguments, and that is the whole contract
///
/// The typedef takes nothing, because the deployed function takes nothing. There
/// is no Retailer organization id, shop id, auth user id, profile id, membership
/// id, tenant id, role code, permission code, status filter, search term, sort
/// or page selector to express at this boundary — so there is none to get wrong,
/// and no future edit can quietly add one without changing this type and the
/// boundary test that asserts its shape.
///
/// Ordering is the backend's: `order by s.name, s.code nulls last, s.id`. It is
/// not requested here and not re-sorted here, so the picker's option order is
/// stable across renders.
typedef RetailerAssignableShopsInvoker = Future<Object?> Function();

/// Everything one Edge Function reply carries, before anything has been made of
/// it.
///
/// A data-layer type. It exists so the transport can hand the repository the two
/// facts it needs — what status came back and what body came with it — without
/// the repository ever touching an SDK exception, and so that the whole response
/// mapping is testable with no socket.
///
/// [body] is deliberately `Object?` rather than a map: a body that is not a JSON
/// object is a real possibility (a gateway error page, an empty reply) and must
/// be refused by the parser rather than crash the transport. It never leaves the
/// data layer, and no part of it is ever rendered.
final class RetailerStaffInvitationReply {
  const RetailerStaffInvitationReply({
    required this.status,
    required this.body,
  });

  /// The HTTP status. Recorded because a bare gateway `401` carries no contract
  /// body to read, and for nothing else — the outcome, not the status, decides
  /// what happened to the email.
  final int status;

  /// The decoded body, whatever shape it arrived in.
  final Object? body;
}

/// Posts one invitation request and returns the reply.
///
/// Takes the already-encoded five-field body rather than a domain request, so
/// this boundary has one job and the encoding is pinned by its own test.
typedef RetailerStaffInvitationSender =
    Future<RetailerStaffInvitationReply> Function(Map<String, Object?> body);

/// The production assignable-shops invoker.
///
/// The only place in the application that names this RPC and touches the
/// Supabase client for it. Note the call site: a function name, and nothing else
/// at all.
///
/// **No `params` map is passed, not even an empty one.** An empty map would be
/// harmless today and would be the obvious place for someone to later add "just
/// one" filter; omitting it makes the zero-argument shape visible at the call
/// site rather than implied by an absence of keys.
RetailerAssignableShopsInvoker supabaseRetailerAssignableShopsInvoker(
  SupabaseClient client,
) {
  return () => client.rpc<Object?>(retailerStaffAssignableShopsRpc);
}

/// The production invitation sender.
///
/// ## Why `functions.invoke` rather than a hand-built request
///
/// Because the one thing this call must get right is *whose* session it runs
/// under. The SDK's functions client carries the publishable key and keeps its
/// `Authorization` header in step with the signed-in user's access token, so the
/// request arrives as the caller — which is what makes `auth.uid()` mean
/// something inside `reserve_retailer_staff_invitation()`, resolves the Retailer
/// in PostgreSQL, and validates every submitted shop against that Retailer.
/// (The receipt upload builds its own request only because it needs multipart,
/// which this client cannot express; a JSON body needs no such workaround.)
///
/// **No key of any other kind is attached.** No service-role credential and no
/// Resend setting exists anywhere in this application; both live only in the
/// function's own environment.
///
/// ## Every reply becomes a value, including the refusals
///
/// `invoke` throws `FunctionException` for any non-2xx — and four of this
/// contract's codes are non-2xx by design (`409` for a conflict, `502` for a
/// delivery failure, and so on). Those are *answers*, not faults, so the
/// exception is unwrapped back into a [RetailerStaffInvitationReply] and the
/// contract body it carries is parsed exactly like a 200's. Only a fault that
/// produced no reply at all is allowed to propagate, which is what the
/// repository classifies as transport.
///
/// Nothing here is logged. A request body carries a colleague's name and
/// address, and a reply or an exception can quote either.
RetailerStaffInvitationSender supabaseRetailerStaffInvitationSender(
  SupabaseClient client,
) {
  return (Map<String, Object?> body) async {
    try {
      final FunctionResponse response = await client.functions.invoke(
        sendRetailerStaffInvitationFunction,
        body: body,
      );
      return RetailerStaffInvitationReply(
        status: response.status,
        body: response.data,
      );
    } on FunctionException catch (error) {
      // A refusal the contract defines, or a gateway status with no contract
      // body. Both are replies; the parser decides which.
      return RetailerStaffInvitationReply(
        status: error.status,
        body: error.details,
      );
    }
  };
}

/// The Retailer staff **invitation** boundary: one read and one write.
///
/// Thin by design: it performs the calls and lets genuine faults propagate.
/// Turning an exception into a problem is the repository's job and turning a
/// body into domain values is the parser's.
///
/// **No table is ever read or written here.** There is no query against
/// `retailer_staff_invitations`, `retailer_invitation_shop_assignments`,
/// `retailer_shop_members`, the shop table, `organization_members`, `profiles`
/// or any other relation under any spelling — no insert, update, upsert or
/// delete of any kind. Reserving the invitation, minting and hashing the token,
/// preparing the row, sending the email and recording the result all happen
/// inside the Edge Function, three of them under a service-role key this
/// application does not have.
///
/// **No invitation acceptance, no revoke, no resend control, no role change, no
/// membership status change and no post-acceptance shop reassignment.** None of
/// those is named here, and none has a method on this class.
final class RetailerStaffInvitationRpcDataSource {
  const RetailerStaffInvitationRpcDataSource({
    required RetailerAssignableShopsInvoker assignableShops,
    required RetailerStaffInvitationSender send,
  }) : _assignableShops = assignableShops,
       _send = send;

  /// Builds the data source against a live client.
  factory RetailerStaffInvitationRpcDataSource.forClient(
    SupabaseClient client,
  ) {
    return RetailerStaffInvitationRpcDataSource(
      assignableShops: supabaseRetailerAssignableShopsInvoker(client),
      send: supabaseRetailerStaffInvitationSender(client),
    );
  }

  final RetailerAssignableShopsInvoker _assignableShops;
  final RetailerStaffInvitationSender _send;

  /// The assignable shops, in one round trip.
  Future<Object?> fetchAssignableShops() => _assignableShops();

  /// One invitation, in one round trip. Never called twice for one submission.
  Future<RetailerStaffInvitationReply> sendInvitation(
    Map<String, Object?> body,
  ) => _send(body);
}
