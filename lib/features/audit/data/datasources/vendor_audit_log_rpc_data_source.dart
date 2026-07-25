import 'package:supabase_flutter/supabase_flutter.dart';

/// The one Vendor Audit Log RPC, named exactly once.
const String listVendorAuditLogsRpc = 'list_vendor_audit_logs';

/// The three — and only three — parameters it accepts.
const String auditLimitParameter = 'p_limit';
const String auditBeforeOccurredAtParameter = 'p_before_occurred_at';
const String auditBeforeAuditLogIdParameter = 'p_before_audit_log_id';

/// The page size this client always asks for.
///
/// Fixed rather than configurable, and fixed at a value the backend accepts.
/// `list_vendor_audit_logs` honours `1 … 100` exactly and raises `22023` for
/// `0`, for every negative value and for everything above 100 — it refuses
/// rather than clamping, because a client that asked for 500 and silently
/// received 100 would draw the natural, wrong inference ("fewer rows than I
/// asked for, so that is the end of the history") and stop paging early.
///
/// Pinning 50 here means this client can never construct such a request, and
/// means the "a short page is the end" rule below is sound: a page shorter than
/// what was asked for can only mean the history is exhausted.
const int vendorAuditLogPageSize = 50;

/// Invokes `list_vendor_audit_logs(integer, timestamptz, uuid)`.
///
/// ## The signature is the security property
///
/// Three arguments: a page size and a two-part cursor. None of them is
/// authorization context and none can widen what comes back. There is no auth
/// user id, profile id, membership id, Vendor organization id, tenant id, role
/// code, permission code, actor selector, entity selector, entity owner, offset
/// or page number to express at this boundary — so there is none to get wrong,
/// and no future edit can quietly add one without changing this type.
///
/// The cursor travels **whole or not at all**: [beforeOccurredAt] and
/// [beforeAuditLogId] are supplied together or both omitted. A half cursor is a
/// client bug the backend refuses with `22023` rather than completing with a
/// default, and the repository above makes one unrepresentable.
typedef VendorAuditLogInvoker =
    Future<Object?> Function({
      required int limit,
      required String? beforeOccurredAt,
      required String? beforeAuditLogId,
    });

/// The production invoker.
///
/// The only place in the application that names the Vendor Audit Log RPC and
/// touches the Supabase client for it. Note the call site: a function name, a
/// fixed page size, and a cursor that came from a row the backend itself
/// returned.
VendorAuditLogInvoker supabaseVendorAuditLogsInvoker(SupabaseClient client) {
  return ({
    required int limit,
    required String? beforeOccurredAt,
    required String? beforeAuditLogId,
  }) => client.rpc<Object?>(
    listVendorAuditLogsRpc,
    params: <String, Object?>{
      auditLimitParameter: limit,
      // Sent explicitly as nulls on the newest page rather than omitted. The
      // function's defaults would produce the same result, but naming both keys
      // every time makes "the cursor is one value in two columns" visible at the
      // call site instead of implied by an absence.
      auditBeforeOccurredAtParameter: beforeOccurredAt,
      auditBeforeAuditLogIdParameter: beforeAuditLogId,
    },
  );
}

/// Reads the Vendor audit history a Vendor Super Admin is entitled to.
///
/// Thin by design: it performs the call and lets exceptions propagate. Turning
/// an exception into a `Failure` is the repository's job and turning a body into
/// domain objects is the parser's, so each of the three has one reason to
/// change.
///
/// **No table is ever read here.** There is no query against `audit_logs`,
/// `profiles`, `organization_members`, `organizations` or `auth.users` under any
/// spelling. `authenticated` genuinely does hold `SELECT` on `audit_logs`, so a
/// direct read would *work* — which is exactly why the rule is stated rather
/// than left to the schema to enforce. A `select *` there would carry
/// `metadata`, `entity_id`, `ip_address`, `user_agent` and `actor_profile_id`
/// (**the auth user id**) to a phone, would make column choice a client
/// responsibility on the most sensitive table in the schema, and would move both
/// the actor join and the keyset tie-break into Dart.
///
/// **No write.** `audit_logs` grants no `INSERT`, `UPDATE` or `DELETE` to any
/// browser role, and none is named here. Reading a history is not an event in
/// it, so this call writes no audit row of its own either.
final class VendorAuditLogRpcDataSource {
  const VendorAuditLogRpcDataSource({required VendorAuditLogInvoker auditLogs})
    : _auditLogs = auditLogs;

  /// Builds the data source against a live client.
  factory VendorAuditLogRpcDataSource.forClient(SupabaseClient client) {
    return VendorAuditLogRpcDataSource(
      auditLogs: supabaseVendorAuditLogsInvoker(client),
    );
  }

  final VendorAuditLogInvoker _auditLogs;

  /// The newest page.
  Future<Object?> fetchNewest() => _auditLogs(
    limit: vendorAuditLogPageSize,
    beforeOccurredAt: null,
    beforeAuditLogId: null,
  );

  /// The page strictly older than the supplied position.
  ///
  /// [beforeOccurredAt] is the ISO-8601 rendering of the final row's
  /// `occurred_at` and [beforeAuditLogId] is that **same row's** id. Neither is
  /// derived, rounded or otherwise adjusted here — an altered cursor would
  /// silently move a page boundary.
  Future<Object?> fetchOlder({
    required String beforeOccurredAt,
    required String beforeAuditLogId,
  }) => _auditLogs(
    limit: vendorAuditLogPageSize,
    beforeOccurredAt: beforeOccurredAt,
    beforeAuditLogId: beforeAuditLogId,
  );
}
