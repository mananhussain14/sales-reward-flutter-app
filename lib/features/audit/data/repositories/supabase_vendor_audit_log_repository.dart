import '../../../../core/errors/failure.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../../../core/result/read_result.dart';
import '../../domain/entities/vendor_audit_log_entry.dart';
import '../../domain/repositories/vendor_audit_log_repository.dart';
import '../datasources/vendor_audit_log_rpc_data_source.dart';
import '../models/vendor_audit_log_parsers.dart';

/// The real [VendorAuditLogRepository].
///
/// The read does exactly three things, in order: call the RPC, parse the body,
/// classify the answer. Each of the three is somebody else's code — the data
/// source, the parser, and `mapSupabaseError` — so this class contains no
/// branching of its own beyond "did it throw?".
///
/// ## It reproduces no backend authorization logic
///
/// There is no Vendor organization id here, no membership lookup, no join to
/// `profiles`, no metadata extraction and no tenant predicate. Whether this
/// caller may read the history is decided in SQL by
/// `get_vendor_super_admin_context()` **and** `has_organization_permission` on
/// every call — a pair of gates deliberately narrower than the table's own RLS
/// policy, which is an `OR`. Restating any of it here would create a second
/// definition free to drift, and only one of the two could be right.
///
/// Nor is anything inferred from the data. An action code, an entity type and an
/// actor type are all *display* data; none of them decides whether anything may
/// be read, and none of them may gate a route or an affordance.
final class SupabaseVendorAuditLogRepository
    implements VendorAuditLogRepository {
  const SupabaseVendorAuditLogRepository({
    required VendorAuditLogRpcDataSource rpc,
  }) : _rpc = rpc;

  final VendorAuditLogRpcDataSource _rpc;

  @override
  Future<ReadResult<List<VendorAuditLogEntry>>> auditLogs({
    VendorAuditLogCursor? before,
  }) {
    if (before == null) {
      return _read(_rpc.fetchNewest);
    }

    return _read(
      () => _rpc.fetchOlder(
        // Rendered from the exact [DateTime] the parser produced, which is the
        // exact instant the backend sent. `toIso8601String` on a UTC value emits
        // the `Z` suffix, so the zone travels with the value and the position is
        // unambiguous whatever the device's own zone is.
        //
        // Nothing is rounded, truncated or re-derived: an altered cursor would
        // move a page boundary silently, which under a strict `<` comparison
        // means either re-emitting rows or skipping them.
        beforeOccurredAt: before.occurredAt.toUtc().toIso8601String(),
        beforeAuditLogId: before.auditLogId,
      ),
    );
  }

  /// Call → parse → classify, with the two failure modes kept apart.
  ///
  /// * A **thrown** call is classified by SQLSTATE. `42501` becomes
  ///   [DeniedFailure] and everything unrecognized becomes [UnavailableFailure],
  ///   so a transport fault can never be presented as an authorization denial —
  ///   nor the reverse. The backend raises the same generic `42501` for "not
  ///   signed in", "not a Vendor Super Admin", "this role no longer holds the
  ///   audit read permission" and "your membership is suspended" alike, and this
  ///   client preserves that: one denial, no permission code, no hint at which
  ///   of the four it was.
  /// * `22023` — the backend's answer to an out-of-range page size or a half
  ///   cursor — is neither of those. It is unreachable from this client by
  ///   construction (the page size is a fixed 50 and the cursor type cannot hold
  ///   half a value), and if it ever arrived it would mean this build and the
  ///   deployed function disagree about the contract. It falls to
  ///   [UnavailableFailure] through the default branch of `mapSupabaseError`,
  ///   which is the correct reading: an operational problem the user can retry
  ///   past, never a statement about their access and never an empty history.
  /// * An **unparseable body** is [UnavailableFailure]. Unreadable is not
  ///   refused, and it is certainly not an empty history: fabricating one would
  ///   tell a Vendor that nothing has ever happened in their organization when
  ///   the response simply could not be understood.
  Future<ReadResult<List<VendorAuditLogEntry>>> _read(
    Future<Object?> Function() call,
  ) async {
    final Object? raw;
    try {
      raw = await call();
    } on Object catch (error) {
      // mapSupabaseError discriminates on SQLSTATE and returns a discriminant;
      // the backend's own message never travels past this line, so no table,
      // column, function or policy name can reach a screen.
      return ReadFailure<List<VendorAuditLogEntry>>(mapSupabaseError(error));
    }

    try {
      return ReadSuccess<List<VendorAuditLogEntry>>(
        VendorAuditLogEntryParser.parseList(raw),
      );
    } on VendorAuditLogFormatException {
      return const ReadFailure<List<VendorAuditLogEntry>>(UnavailableFailure());
    }
  }
}
