import 'dart:async';

import 'package:sale_reward/features/staff/domain/entities/retailer_staff_shop_assignment.dart';
import 'package:sale_reward/features/staff/domain/repositories/retailer_staff_shop_assignment_repository.dart';

/// Completion plumbing, matching the other Retailer fakes.
///
/// [manual] makes a call stay pending until completed by hand, so "a second
/// press while a save is in flight" and "an answer arriving after a session
/// change" are deterministic rather than a sleep-and-hope. [completeAt] can
/// complete out of order, which is the stale-response race the request tokens
/// exist to close.
class _Pending<T> {
  final List<Completer<T>> _queue = <Completer<T>>[];

  int get length => _queue.length;

  Future<T> add() {
    final Completer<T> completer = Completer<T>();
    _queue.add(completer);
    return completer.future;
  }

  void completeAt(int index, T value) => _queue.removeAt(index).complete(value);
}

/// A hand-written [RetailerStaffShopAssignmentRepository] fake.
///
/// [sentRequests] records the **domain** request rather than an encoded payload,
/// because that is what the interface takes; the two parameter names and their
/// values are pinned separately by the repository and boundary tests.
///
/// Recording what was sent is the point: it is how a test proves a double tap
/// produced one write and not two, that the id sent was the roster's canonical
/// membership id and not a name or an index, and that a selection was
/// intersected with the options before it left.
class FakeRetailerStaffShopAssignmentRepository
    implements RetailerStaffShopAssignmentRepository {
  RetailerStaffShopAssignmentResult? result;

  int callCount = 0;
  bool manual = false;

  /// Every request handed to [setShopAssignments], in order.
  final List<RetailerStaffShopAssignmentRequest> sentRequests =
      <RetailerStaffShopAssignmentRequest>[];

  final _Pending<RetailerStaffShopAssignmentResult> _pending =
      _Pending<RetailerStaffShopAssignmentResult>();

  int get pendingCount => _pending.length;

  void complete([RetailerStaffShopAssignmentResult? override]) =>
      completeAt(0, override);

  void completeAt(int index, [RetailerStaffShopAssignmentResult? override]) {
    _pending.completeAt(index, override ?? result ?? appliedOneForOne);
  }

  @override
  Future<RetailerStaffShopAssignmentResult> setShopAssignments(
    RetailerStaffShopAssignmentRequest request,
  ) {
    callCount++;
    sentRequests.add(request);
    if (manual) {
      return _pending.add();
    }
    return Future<RetailerStaffShopAssignmentResult>.value(
      result ?? appliedOneForOne,
    );
  }
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// The ordinary success: one shop added, one retired, one left alone.
const RetailerStaffShopAssignmentResult appliedOneForOne =
    RetailerStaffShopAssignmentApplied(
      RetailerStaffShopAssignmentChange(
        shopsAdded: 1,
        shopsRemoved: 1,
        shopsUnchanged: 1,
      ),
    );

/// A committed no-op: the submitted set was already the assigned set.
///
/// A real, reachable answer — and the one that must never be reported as a
/// failure.
const RetailerStaffShopAssignmentResult appliedNoChange =
    RetailerStaffShopAssignmentApplied(
      RetailerStaffShopAssignmentChange(
        shopsAdded: 0,
        shopsRemoved: 0,
        shopsUnchanged: 2,
      ),
    );

/// A refusal with an arbitrary stable problem.
RetailerStaffShopAssignmentResult refused(
  RetailerStaffShopAssignmentProblem problem,
) => RetailerStaffShopAssignmentRefused(problem);
