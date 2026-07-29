import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../../core/errors/sql_state.dart';
import '../../domain/entities/retailer_staff_lifecycle_status.dart';
import '../../domain/repositories/retailer_staff_lifecycle_repository.dart';
import '../datasources/retailer_staff_lifecycle_rpc_data_source.dart';
import '../models/retailer_staff_lifecycle_parser.dart';

/// How long one lifecycle change may take before it is abandoned.
///
/// The same 30 seconds the shop-assignment write uses, for the same reason: the
/// function does real work — resolve, authorize, lock the Retailer, lock the
/// membership, read the complete role set, update and audit, in one transaction —
/// and 30s is short enough that a person is not left watching a spinner with no
/// result.
///
/// A timeout is **not** reported as a definite failure. The statement may have
/// committed after this client stopped waiting, so the honest answer is that the
/// outcome is unknown and the roster is the authority on it.
const Duration retailerStaffLifecycleTimeout = Duration(seconds: 30);

/// The real [RetailerStaffLifecycleRepository].
///
/// Three things, and nothing else: perform the call, parse the answer, classify
/// the fault.
///
/// ## Discrimination is by type and machine code only
///
/// Nothing here reads `error.message`, for display or for branching. PostgreSQL
/// messages name tables, columns, functions and policies; GoTrue messages are
/// prose that changes between releases and can carry account detail. The backend
/// contract is explicit that message text is not an API, so neither is read and
/// neither travels onward — only a [RetailerStaffLifecycleProblem] does, and that
/// type has no field a message could occupy.
///
/// Note in particular that the function raises `42501` with **one byte-identical
/// message** for eleven distinct causes, including "the target is a Retailer
/// Owner", "the target is you", "the target holds several roles" and "that
/// membership belongs to another Retailer". All of them arrive here as
/// [RetailerStaffLifecycleProblem.denied], and nothing downstream can tell them
/// apart — which is the whole point.
///
/// ## It reproduces no backend authorization logic
///
/// There is no join over `organization_members`, `member_roles` or `roles` here,
/// no Retailer organization id, no role comparison and no permission evaluation.
/// Whether this caller may change a membership's status is decided in SQL, on
/// every call, under row locks this client cannot take.
final class SupabaseRetailerStaffLifecycleRepository
    implements RetailerStaffLifecycleRepository {
  const SupabaseRetailerStaffLifecycleRepository({
    required RetailerStaffLifecycleRpcDataSource rpc,
  }) : _rpc = rpc;

  final RetailerStaffLifecycleRpcDataSource _rpc;

  @override
  Future<RetailerStaffLifecycleResult> setMembershipStatus({
    required String membershipId,
    required RetailerStaffLifecycleStatus status,
  }) async {
    final Object? raw;
    try {
      // Exactly one call. There is no retry here and no loop around it: an
      // automatic second attempt after a committed write is indistinguishable,
      // from this side, from one after a failed write — and a repeat would write
      // a second audit row for a decision nobody made twice.
      raw = await _rpc
          .setMembershipStatus(membershipId: membershipId, status: status.code)
          .timeout(retailerStaffLifecycleTimeout);
    } on Object catch (error) {
      return RetailerStaffLifecycleRefused(_classify(error));
    }

    // Nothing was thrown, so the transaction committed. From here on the only
    // question is whether this build can describe what it did.
    final RetailerStaffLifecycleRow? row = parseRetailerStaffLifecycleRow(
      raw,
      membershipId,
    );

    if (row == null) {
      // Committed, undescribable. Never a refusal, never "unchanged", and never
      // retried. The caller re-reads the canonical roster instead.
      return const RetailerStaffLifecycleUnconfirmed();
    }

    return RetailerStaffLifecycleApplied(
      // The database's answer, not the request.
      confirmedStatus: row.confirmedStatus,
      statusChanged: row.statusChanged,
    );
  }

  /// Classifies a thrown lifecycle write.
  ///
  /// Fails closed: an unrecognized throw is
  /// [RetailerStaffLifecycleProblem.unexpected] rather than anything that reads
  /// as a success, and never a statement about the user's network.
  ///
  /// `22P02` is mapped **here** rather than through the shared `mapSupabaseError`
  /// for the same reason the Vendor Retailer lifecycle repository maps it
  /// locally: that shared mapper folds `22P02` into an operational failure for
  /// every Vendor read and the Product writes, none of which was written or
  /// tested against this case, and changing it centrally would alter copy and
  /// retry affordances on screens far outside this milestone. This feature's own
  /// problem enum has a member for it, so the local mapping costs one line.
  static RetailerStaffLifecycleProblem _classify(Object error) {
    if (error is TimeoutException) {
      return RetailerStaffLifecycleProblem.timeout;
    }

    // Checked before PostgrestException: the transport exception is what the SDK
    // propagates when the request never arrived, and it carries no SQLSTATE to
    // classify. `package:http` wraps a VM `SocketException` in a subclass of
    // `ClientException`, so matching the base type covers a refused socket, an
    // unresolved host and a browser fetch refusal alike — without importing
    // `dart:io`, which does not exist on Flutter web.
    if (error is http.ClientException) {
      return RetailerStaffLifecycleProblem.network;
    }

    if (error is sb.PostgrestException) {
      return switch (error.code) {
        SqlState.insufficientPrivilege => RetailerStaffLifecycleProblem.denied,
        SqlState.checkViolation => RetailerStaffLifecycleProblem.invalidStatus,
        SqlState.objectNotInPrerequisiteState =>
          RetailerStaffLifecycleProblem.retailerUnavailable,
        SqlState.invalidTextRepresentation =>
          RetailerStaffLifecycleProblem.malformedRequest,
        // A recognized SQLSTATE this function has no business raising, or none
        // at all. `23505` cannot arise — the write touches no unique index.
        _ => RetailerStaffLifecycleProblem.unexpected,
      };
    }

    if (error is sb.AuthException) {
      // The session is absent, expired or rejected. Deliberately not bound to a
      // message: auth exceptions can carry token material.
      return RetailerStaffLifecycleProblem.signedOut;
    }

    return RetailerStaffLifecycleProblem.unexpected;
  }
}
