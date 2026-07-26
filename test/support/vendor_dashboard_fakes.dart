import 'dart:async';

import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/core/result/read_result.dart';
import 'package:sale_reward/features/dashboard/domain/entities/vendor_dashboard_summary.dart';
import 'package:sale_reward/features/dashboard/domain/repositories/vendor_dashboard_repository.dart';

/// A hand-written [VendorDashboardRepository] fake.
///
/// Hand-written rather than mocked because these tests care about *how many times*
/// the summary was asked for as much as what came back: [callCount] is how a test
/// proves that a duplicate refresh is suppressed, that a session change reloads
/// exactly once, and that an identical re-emitted session reloads not at all.
///
/// There is nothing to record about *what was sent*, because nothing is ever
/// sent — the contract takes zero arguments, which is why this fake has no
/// captured-parameter list at all. That absence is itself the shape of the
/// contract.
class FakeVendorDashboardRepository implements VendorDashboardRepository {
  /// When set, every call answers this — how a test scripts a failure.
  ReadResult<VendorDashboardSummary>? result;

  /// The summary returned when [result] is unset.
  VendorDashboardSummary nextSummary = exampleDashboardSummary;

  int callCount = 0;

  /// When true, every call stays pending until it is completed by hand — so "a
  /// second refresh while one is in flight" and "a stale answer arriving after a
  /// session change" are deterministic rather than a sleep-and-hope.
  bool manual = false;
  final List<Completer<ReadResult<VendorDashboardSummary>>> _pending =
      <Completer<ReadResult<VendorDashboardSummary>>>[];

  int get pendingCount => _pending.length;

  /// Completes the oldest pending call.
  void complete([ReadResult<VendorDashboardSummary>? override]) =>
      completeAt(0, override);

  /// Completes a pending call **out of order**, so a test can make an older
  /// request answer after a newer one — the stale-response race the request token
  /// exists to close. [index] is into the pending queue, oldest first.
  void completeAt(int index, [ReadResult<VendorDashboardSummary>? override]) {
    _pending
        .removeAt(index)
        .complete(
          override ??
              result ??
              ReadSuccess<VendorDashboardSummary>(nextSummary),
        );
  }

  @override
  Future<ReadResult<VendorDashboardSummary>> summary() {
    callCount++;
    if (manual) {
      final Completer<ReadResult<VendorDashboardSummary>> completer =
          Completer<ReadResult<VendorDashboardSummary>>();
      _pending.add(completer);
      return completer.future;
    }
    return Future<ReadResult<VendorDashboardSummary>>.value(
      result ?? ReadSuccess<VendorDashboardSummary>(nextSummary),
    );
  }
}

// ---------------------------------------------------------------------------
// Fixtures
//
// Invented figures. Nothing here is a real count from any environment. The four
// values are deliberately distinct so a test asserting "the Audit events card
// shows 1,204" cannot pass by accidentally reading a different card.
// ---------------------------------------------------------------------------

/// An ordinary answer for an established Vendor.
const VendorDashboardSummary exampleDashboardSummary = VendorDashboardSummary(
  activeMemberCount: 7,
  catalogActiveRoleCount: 6,
  catalogPermissionCount: 18,
  auditEventCount: 1204,
);

/// A second Vendor's answer, for session-isolation tests.
///
/// The two **tenant** counts differ from [exampleDashboardSummary] and the two
/// **catalogue** counts are identical — which is exactly what the backend
/// produces for two Vendors, and what makes "A's numbers are gone" assertable on
/// the tenant figures alone.
const VendorDashboardSummary otherVendorDashboardSummary =
    VendorDashboardSummary(
      activeMemberCount: 2,
      catalogActiveRoleCount: 6,
      catalogPermissionCount: 18,
      auditEventCount: 5,
    );

/// An authorized Vendor with no tenant-scoped data yet.
///
/// The two Vendor counts are `0` and the two catalogue counts are not — the
/// legitimate shape for a brand-new organization, and the one a client must never
/// confuse with a denial.
const VendorDashboardSummary emptyTenantDashboardSummary =
    VendorDashboardSummary(
      activeMemberCount: 0,
      catalogActiveRoleCount: 6,
      catalogPermissionCount: 18,
      auditEventCount: 0,
    );

/// Every count at zero, including the catalogue ones — reachable only in a
/// database whose catalogue was never seeded, and still a valid answer.
const VendorDashboardSummary allZeroDashboardSummary = VendorDashboardSummary(
  activeMemberCount: 0,
  catalogActiveRoleCount: 0,
  catalogPermissionCount: 0,
  auditEventCount: 0,
);

/// One `get_vendor_admin_dashboard_summary()` row, as PostgREST returns it.
///
/// Four keys, in the contract's own order, and **no** `organization_id`,
/// organization name, status, timestamp or permission key — the function returns
/// none of them.
Map<String, Object?> dashboardSummaryRow({
  Object? activeMemberCount = 7,
  Object? catalogActiveRoleCount = 6,
  Object? catalogPermissionCount = 18,
  Object? auditEventCount = 1204,
}) => <String, Object?>{
  'active_member_count': activeMemberCount,
  'catalog_active_role_count': catalogActiveRoleCount,
  'catalog_permission_count': catalogPermissionCount,
  'audit_event_count': auditEventCount,
};

/// A well-formed body: a list of exactly one row.
List<Map<String, Object?>> dashboardSummaryBody([Map<String, Object?>? row]) =>
    <Map<String, Object?>>[row ?? dashboardSummaryRow()];

/// A read that failed the way an unreadable body does.
ReadResult<T> unavailableDashboardRead<T>() =>
    ReadFailure<T>(const UnavailableFailure());

/// A read the backend refused with `42501` — which covers a caller who is not
/// signed in, is not a Vendor Super Admin, whose profile or membership is
/// suspended, or whose role no longer holds any one of the three read permissions
/// the summary requires. All of them are the same answer here, exactly as they
/// are in SQL.
ReadResult<T> deniedDashboardRead<T>() => ReadFailure<T>(const DeniedFailure());
