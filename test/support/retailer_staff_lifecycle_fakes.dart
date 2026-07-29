import 'dart:async';

import 'package:sale_reward/features/staff/domain/entities/retailer_staff_lifecycle_status.dart';
import 'package:sale_reward/features/staff/domain/repositories/retailer_staff_lifecycle_repository.dart';

/// A hand-written [RetailerStaffLifecycleRepository] fake.
///
/// Hand-written rather than mocked because these tests care about *what was
/// sent* as much as what came back: [writes] records every membership id and
/// requested status that left the client, which is how a test proves that one
/// membership id — and nothing beside it — ever travels, and that exactly one
/// call is made per confirmed decision.
class FakeRetailerStaffLifecycleRepository
    implements RetailerStaffLifecycleRepository {
  /// Every lifecycle write, in order.
  final List<({String membershipId, RetailerStaffLifecycleStatus status})>
  writes = <({String membershipId, RetailerStaffLifecycleStatus status})>[];

  int get callCount => writes.length;

  /// The answer every write produces. Defaults to a committed deactivation.
  RetailerStaffLifecycleResult result = const RetailerStaffLifecycleApplied(
    confirmedStatus: RetailerStaffLifecycleStatus.deactivated,
    statusChanged: true,
  );

  /// When true, every write stays pending until [complete] or [completeAt] is
  /// called — so "a second confirmation while one is in flight", "row B is not
  /// busy while row A is" and out-of-order completion are all deterministic
  /// rather than a sleep-and-hope.
  bool manual = false;
  final List<Completer<RetailerStaffLifecycleResult>> _pending =
      <Completer<RetailerStaffLifecycleResult>>[];

  int get pendingCount => _pending.length;

  /// Completes the oldest pending write.
  void complete([RetailerStaffLifecycleResult? override]) =>
      completeAt(0, override);

  /// Completes the pending write at [index], oldest first.
  ///
  /// Exists so a test can answer the SECOND request before the first and prove
  /// that each answer lands on the membership that asked for it — the
  /// out-of-order case a single-slot fake cannot express.
  void completeAt(int index, [RetailerStaffLifecycleResult? override]) {
    _pending.removeAt(index).complete(override ?? result);
  }

  @override
  Future<RetailerStaffLifecycleResult> setMembershipStatus({
    required String membershipId,
    required RetailerStaffLifecycleStatus status,
  }) {
    writes.add((membershipId: membershipId, status: status));
    if (manual) {
      final Completer<RetailerStaffLifecycleResult> completer =
          Completer<RetailerStaffLifecycleResult>();
      _pending.add(completer);
      return completer.future;
    }
    return Future<RetailerStaffLifecycleResult>.value(result);
  }
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// A `set_retailer_staff_membership_status` body, as PostgREST returns a
/// `returns table (...)` function: a list of one row object.
List<Map<String, Object?>> staffLifecycleRows({
  Object? membershipId,
  Object? membershipStatus = 'DEACTIVATED',
  Object? roleCode = 'SALES_STAFF',
  Object? statusChanged = true,
}) => <Map<String, Object?>>[
  staffLifecycleRow(
    membershipId: membershipId,
    membershipStatus: membershipStatus,
    roleCode: roleCode,
    statusChanged: statusChanged,
  ),
];

Map<String, Object?> staffLifecycleRow({
  Object? membershipId,
  Object? membershipStatus = 'DEACTIVATED',
  Object? roleCode = 'SALES_STAFF',
  Object? statusChanged = true,
}) => <String, Object?>{
  'membership_id': membershipId,
  'membership_status': membershipStatus,
  // Present in the deployed contract and deliberately never read by the parser.
  'role_code': roleCode,
  'status_changed': statusChanged,
};

/// A write the backend refused with [problem].
RetailerStaffLifecycleResult refusedStaffLifecycle(
  RetailerStaffLifecycleProblem problem,
) => RetailerStaffLifecycleRefused(problem);
