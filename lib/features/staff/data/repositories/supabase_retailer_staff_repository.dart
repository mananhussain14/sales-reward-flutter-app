import '../../../../core/errors/retailer_read_problem.dart';
import '../../../../core/parsing/rpc_row.dart';
import '../../domain/repositories/retailer_staff_repository.dart';
import '../datasources/retailer_staff_rpc_data_source.dart';
import '../models/retailer_staff_parsers.dart';

/// The real [RetailerStaffRepository].
///
/// Two independent reads, each doing exactly three things: call the RPC, parse
/// the body, classify the answer.
///
/// ## The two reads are never combined
///
/// [members] and [invitations] are separate methods returning separate result
/// types, and neither awaits the other. They sit on **different permissions**
/// (`RETAILER_STAFF_READ` and `RETAILER_STAFF_MANAGE`), so one succeeding while
/// the other fails is a normal outcome rather than an inconsistency — and a
/// combined method would have to invent a policy for that case, which is
/// precisely the decision the cubit should be making with the screen in view.
///
/// ## It reproduces no backend authorization logic
///
/// There is no Retailer organization id here, no membership lookup, no role
/// check and no permission check. In particular this class does **not**
/// re-implement the roster's `and (v_can_manage or m.status = 'ACTIVE')`
/// predicate: which membership statuses a caller sees is decided in SQL from
/// that caller's own permissions, and restating it here would create a second
/// definition free to drift from the enforced one.
final class SupabaseRetailerStaffRepository implements RetailerStaffRepository {
  const SupabaseRetailerStaffRepository({
    required RetailerStaffRpcDataSource rpc,
    Duration timeout = retailerReadTimeout,
  }) : _rpc = rpc,
       _timeout = timeout;

  final RetailerStaffRpcDataSource _rpc;
  final Duration _timeout;

  @override
  Future<RetailerStaffResult> members() async {
    final Object? raw;
    try {
      raw = await _rpc.fetchMembers().timeout(_timeout);
    } on Object catch (error) {
      // `42501` becomes `denied`, so a refusal can never be presented as an
      // empty roster — "you may not see this" and "nobody works here" are
      // opposite claims.
      return RetailerStaffFailed(classifyRetailerReadError(error));
    }

    try {
      return RetailerStaffLoaded(RetailerStaffMemberParser.parse(raw));
    } on RpcFormatException {
      // The exception's own `reason` is developer-facing and stays here. Only
      // the discriminant travels onward.
      return const RetailerStaffFailed(RetailerReadProblem.malformed);
    }
  }

  @override
  Future<RetailerInvitationsResult> invitations() async {
    final Object? raw;
    try {
      raw = await _rpc.fetchInvitations().timeout(_timeout);
    } on Object catch (error) {
      return RetailerInvitationsFailed(classifyRetailerReadError(error));
    }

    try {
      return RetailerInvitationsLoaded(
        RetailerStaffInvitationParser.parse(raw),
      );
    } on RpcFormatException {
      return const RetailerInvitationsFailed(RetailerReadProblem.malformed);
    }
  }
}
