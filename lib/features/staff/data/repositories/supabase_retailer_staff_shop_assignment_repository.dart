import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../../core/errors/sql_state.dart';
import '../../../../core/parsing/rpc_row.dart';
import '../../domain/entities/retailer_staff_shop_assignment.dart';
import '../../domain/repositories/retailer_staff_shop_assignment_repository.dart';
import '../datasources/retailer_staff_shop_assignment_rpc_data_source.dart';
import '../models/retailer_staff_shop_assignment_parser.dart';

/// How long one shop-assignment replacement may take before it is abandoned.
///
/// Longer than a portal read, because the function does real work — resolve,
/// authorize, validate every submitted shop, retire, insert and audit, in one
/// transaction — and short enough that a person is not left watching a spinner
/// with no result.
///
/// A timeout is **not** reported as a failure. The statement may have committed
/// after this client stopped waiting, so the honest answer is that the outcome
/// is unknown and the roster is the authority on it.
const Duration retailerStaffShopAssignmentTimeout = Duration(seconds: 30);

/// The real [RetailerStaffShopAssignmentRepository].
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
/// neither travels onward — only a [RetailerStaffShopAssignmentProblem] does,
/// and that type has no field a message could occupy.
///
/// Note in particular that the function raises `42501` with the same message for
/// "you may not do this", "that membership does not exist" and "that membership
/// is another Retailer's", deliberately, so the operation is not an existence
/// oracle. All three arrive here as
/// [RetailerStaffShopAssignmentProblem.denied], and nothing downstream can tell
/// them apart because nothing downstream is given anything to tell them apart
/// with.
///
/// ## It reproduces no backend authorization logic
///
/// There is no Retailer organization id here, no membership lookup, no role
/// check and no permission check. Whether the caller may assign shops, whether
/// the target is theirs, whether it is an active Sales Staff member and whether
/// each shop is that Retailer's ACTIVE shop are all decided in SQL, on every
/// call.
///
/// ## Nothing retries
///
/// [setShopAssignments] performs exactly one call and returns whatever came of
/// it. A silent second call after an unknown outcome would write a second audit
/// row for a change nobody asked for twice, and could overwrite an edit somebody
/// else made in between — so a retry is always a person pressing the button
/// again.
final class SupabaseRetailerStaffShopAssignmentRepository
    implements RetailerStaffShopAssignmentRepository {
  const SupabaseRetailerStaffShopAssignmentRepository({
    required RetailerStaffShopAssignmentRpcDataSource rpc,
    Duration timeout = retailerStaffShopAssignmentTimeout,
  }) : _rpc = rpc,
       _timeout = timeout;

  final RetailerStaffShopAssignmentRpcDataSource _rpc;
  final Duration _timeout;

  @override
  Future<RetailerStaffShopAssignmentResult> setShopAssignments(
    RetailerStaffShopAssignmentRequest request,
  ) async {
    final Object? raw;
    try {
      raw = await _rpc
          .setShopAssignments(
            // The two canonical values the request already validated, and
            // nothing beside them. There is no third argument to add here
            // without changing the data source's typedef.
            membershipId: request.membershipId,
            shopIds: request.shopIds,
          )
          .timeout(_timeout);
    } on Object catch (error) {
      return RetailerStaffShopAssignmentRefused(_classify(error));
    }

    try {
      return RetailerStaffShopAssignmentApplied(
        RetailerStaffShopAssignmentParser.parse(raw),
      );
    } on RpcFormatException {
      // The exception's own `reason` is developer-facing and stays here. Only
      // the discriminant travels onward — and it says "unreadable answer", never
      // "the write failed", because the statement may well have committed.
      return const RetailerStaffShopAssignmentRefused(
        RetailerStaffShopAssignmentProblem.malformedResponse,
      );
    }
  }

  /// Classifies a thrown replacement.
  ///
  /// Fails closed: no branch returns a success-shaped value, and an unrecognised
  /// throw is [RetailerStaffShopAssignmentProblem.unexpected] rather than
  /// borrowing the connection copy. Reporting a programming error as a network
  /// problem sends a person to fix a connection that is working.
  static RetailerStaffShopAssignmentProblem _classify(Object error) {
    if (error is TimeoutException) {
      // The request WAS sent. The transaction may have committed while this
      // client stopped waiting, so this is the absence of an answer rather than
      // a failure.
      return RetailerStaffShopAssignmentProblem.timeout;
    }

    // Checked before PostgrestException: the transport exception is what the SDK
    // propagates when the request never arrived, and it carries no SQLSTATE to
    // classify. `package:http` wraps a VM `SocketException` in a subclass of
    // `ClientException`, and a browser's CORS or fetch refusal arrives the same
    // way — so matching the base type covers both platforms without importing
    // `dart:io`, which does not exist on Flutter web.
    if (error is http.ClientException) {
      return RetailerStaffShopAssignmentProblem.network;
    }

    if (error is sb.PostgrestException) {
      return switch (error.code) {
        SqlState.insufficientPrivilege =>
          RetailerStaffShopAssignmentProblem.denied,
        SqlState.checkViolation =>
          RetailerStaffShopAssignmentProblem.invalidSelection,
        SqlState.objectNotInPrerequisiteState =>
          RetailerStaffShopAssignmentProblem.retailerUnavailable,
        // Raised by the type system before the function body runs, when a value
        // could not be cast to `uuid` or `uuid[]`. A defect in the request.
        SqlState.invalidTextRepresentation =>
          RetailerStaffShopAssignmentProblem.malformedRequest,
        // A recognised SQLSTATE this function has no business raising, or none
        // at all. Not folded into any of the above: guessing which rule was
        // broken would put a wrong instruction on screen.
        _ => RetailerStaffShopAssignmentProblem.unexpected,
      };
    }

    if (error is sb.AuthException) {
      // The session is absent, expired or rejected. Deliberately not bound to a
      // message: auth exceptions can carry token material.
      return RetailerStaffShopAssignmentProblem.signedOut;
    }

    return RetailerStaffShopAssignmentProblem.unexpected;
  }
}
