import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_lifecycle_action.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_lifecycle_status.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_member.dart';
import 'package:sale_reward/features/staff/domain/repositories/retailer_staff_lifecycle_repository.dart';
import 'package:sale_reward/features/staff/presentation/retailer/cubit/retailer_staff_lifecycle_cubit.dart';

import '../../support/retailer_staff_lifecycle_fakes.dart';

/// The lifecycle cubit, driven directly.
///
/// The concurrency rules are the point of this file. Requests for different
/// memberships are **independent** — the deployed function serializes on the
/// target row, so two colleagues never contend — and the only thing refused is a
/// duplicate for the *same* membership, which is also the only row whose control
/// is disabled. That pairing is what makes "an enabled control is never silently
/// ignored" true rather than merely intended.
void main() {
  const String memberA = '11111111-1111-4111-8111-111111111111';
  const String memberB = '22222222-2222-4222-8222-222222222222';

  RetailerStaffLifecycleAction actionFor(String status) {
    final RetailerStaffMember m = RetailerStaffMember(
      membershipId: memberA,
      firstName: 'Sam',
      lastName: 'Taylor',
      roleCode: 'SALES_STAFF',
      roleName: 'Sales Staff',
      status: RetailerMemberStatus.fromCode(status),
      shopIds: const <String>[],
      shopNames: const <String>[],
      joinedAt: DateTime.utc(2026, 3, 1),
      createdAt: DateTime.utc(2026, 2, 1),
    );
    return RetailerStaffLifecycleAction.forStatus(m.status)!;
  }

  late RetailerStaffLifecycleAction deactivate;
  late RetailerStaffLifecycleAction reactivate;
  late FakeRetailerStaffLifecycleRepository repository;
  late int rereadCount;

  setUp(() {
    deactivate = actionFor('ACTIVE');
    reactivate = actionFor('DEACTIVATED');
    repository = FakeRetailerStaffLifecycleRepository();
    rereadCount = 0;
  });

  RetailerStaffLifecycleCubit buildCubit() => RetailerStaffLifecycleCubit(
    repository,
    rereadRoster: () async => rereadCount++,
  );

  /// A result naming which membership it belongs to, so an out-of-order test can
  /// prove each answer landed on the right row.
  RetailerStaffLifecycleResult appliedActive() =>
      const RetailerStaffLifecycleApplied(
        confirmedStatus: RetailerStaffLifecycleStatus.active,
        statusChanged: true,
      );

  RetailerStaffLifecycleResult appliedDeactivated() =>
      const RetailerStaffLifecycleApplied(
        confirmedStatus: RetailerStaffLifecycleStatus.deactivated,
        statusChanged: true,
      );

  group('the write', () {
    test('calls the repository once, with the derived action', () async {
      final RetailerStaffLifecycleCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.apply(memberA, deactivate);

      expect(repository.callCount, 1);
      expect(repository.writes.single.membershipId, memberA);
      expect(
        repository.writes.single.status,
        RetailerStaffLifecycleStatus.deactivated,
      );
    });

    test('a reactivation sends ACTIVE', () async {
      final RetailerStaffLifecycleCubit cubit = buildCubit();
      addTearDown(cubit.close);
      repository.result = appliedActive();

      await cubit.apply(memberA, reactivate);

      expect(
        repository.writes.single.status,
        RetailerStaffLifecycleStatus.active,
      );
    });
  });

  group('duplicate submission, scoped to one membership', () {
    test('pressing A twice results in ONE A request', () async {
      final RetailerStaffLifecycleCubit cubit = buildCubit();
      addTearDown(cubit.close);
      repository.manual = true;

      final Future<void> first = cubit.apply(memberA, deactivate);
      await cubit.apply(memberA, deactivate);
      await cubit.apply(memberA, deactivate);

      expect(repository.callCount, 1);

      repository.complete();
      await first;

      expect(repository.callCount, 1);
    });

    test(
      'A is busy and therefore disabled while its request is in flight',
      () async {
        final RetailerStaffLifecycleCubit cubit = buildCubit();
        addTearDown(cubit.close);
        repository.manual = true;

        final Future<void> pending = cubit.apply(memberA, deactivate);

        // The row the cubit would refuse is exactly the row the card disables.
        expect(cubit.state.isBusyFor(memberA), isTrue);

        repository.complete();
        await pending;

        expect(cubit.state.isBusyFor(memberA), isFalse);
      },
    );
  });

  group('independent requests for different memberships', () {
    test('B proceeds while A is pending — one RPC each', () async {
      final RetailerStaffLifecycleCubit cubit = buildCubit();
      addTearDown(cubit.close);
      repository.manual = true;

      final Future<void> a = cubit.apply(memberA, deactivate);
      final Future<void> b = cubit.apply(memberB, deactivate);

      // The defect this replaces: B used to be visibly enabled and silently
      // refused. It is now genuinely accepted.
      expect(repository.callCount, 2);
      expect(
        repository.writes.map(
          (({String membershipId, RetailerStaffLifecycleStatus status}) w) =>
              w.membershipId,
        ),
        <String>[memberA, memberB],
      );
      expect(cubit.state.isBusyFor(memberA), isTrue);
      expect(cubit.state.isBusyFor(memberB), isTrue);

      repository.complete();
      repository.complete();
      await a;
      await b;
    });

    test('busy for A does not mark B busy', () async {
      final RetailerStaffLifecycleCubit cubit = buildCubit();
      addTearDown(cubit.close);
      repository.manual = true;

      final Future<void> pending = cubit.apply(memberA, deactivate);

      expect(cubit.state.isBusyFor(memberA), isTrue);
      expect(cubit.state.isBusyFor(memberB), isFalse);

      repository.complete();
      await pending;
    });

    test('each membership receives only its own result', () async {
      final RetailerStaffLifecycleCubit cubit = buildCubit();
      addTearDown(cubit.close);
      repository.manual = true;

      final Future<void> a = cubit.apply(memberA, deactivate);
      final Future<void> b = cubit.apply(memberB, reactivate);

      // A deactivates; B reactivates.
      repository.complete(appliedDeactivated());
      repository.complete(appliedActive());
      await a;
      await b;

      expect(
        cubit.state.noticeFor(memberA),
        RetailerStaffLifecycleNotice.deactivated,
      );
      expect(
        cubit.state.noticeFor(memberB),
        RetailerStaffLifecycleNotice.reactivated,
      );
    });

    test('completion order A then B is handled correctly', () async {
      final RetailerStaffLifecycleCubit cubit = buildCubit();
      addTearDown(cubit.close);
      repository.manual = true;

      final Future<void> a = cubit.apply(memberA, deactivate);
      final Future<void> b = cubit.apply(memberB, reactivate);

      repository.completeAt(0, appliedDeactivated());
      await a;
      expect(cubit.state.isBusyFor(memberA), isFalse);
      expect(cubit.state.isBusyFor(memberB), isTrue);

      repository.completeAt(0, appliedActive());
      await b;

      expect(
        cubit.state.noticeFor(memberA),
        RetailerStaffLifecycleNotice.deactivated,
      );
      expect(
        cubit.state.noticeFor(memberB),
        RetailerStaffLifecycleNotice.reactivated,
      );
      expect(cubit.state.hasAnyInFlight, isFalse);
    });

    test('completion order B then A is handled correctly', () async {
      final RetailerStaffLifecycleCubit cubit = buildCubit();
      addTearDown(cubit.close);
      repository.manual = true;

      final Future<void> a = cubit.apply(memberA, deactivate);
      final Future<void> b = cubit.apply(memberB, reactivate);

      // B's future is second in the queue; completing it first is the
      // out-of-order case.
      repository.completeAt(1, appliedActive());
      await b;
      expect(cubit.state.isBusyFor(memberB), isFalse);
      expect(cubit.state.isBusyFor(memberA), isTrue);
      expect(cubit.state.noticeFor(memberA), isNull);

      repository.completeAt(0, appliedDeactivated());
      await a;

      expect(
        cubit.state.noticeFor(memberA),
        RetailerStaffLifecycleNotice.deactivated,
      );
      expect(
        cubit.state.noticeFor(memberB),
        RetailerStaffLifecycleNotice.reactivated,
      );
    });

    test('a refusal for A does not appear for B', () async {
      final RetailerStaffLifecycleCubit cubit = buildCubit();
      addTearDown(cubit.close);
      repository.result = refusedStaffLifecycle(
        RetailerStaffLifecycleProblem.denied,
      );

      await cubit.apply(memberA, deactivate);

      expect(
        cubit.state.problemFor(memberA),
        RetailerStaffLifecycleProblem.denied,
      );
      expect(cubit.state.problemFor(memberB), isNull);
      expect(cubit.state.noticeFor(memberA), isNull);
    });

    test('a notice for A does not appear for B', () async {
      final RetailerStaffLifecycleCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.apply(memberA, deactivate);

      expect(
        cubit.state.noticeFor(memberA),
        RetailerStaffLifecycleNotice.deactivated,
      );
      expect(cubit.state.noticeFor(memberB), isNull);
    });

    test(
      'starting a new request clears only that row\'s previous result',
      () async {
        final RetailerStaffLifecycleCubit cubit = buildCubit();
        addTearDown(cubit.close);
        repository.result = refusedStaffLifecycle(
          RetailerStaffLifecycleProblem.denied,
        );
        await cubit.apply(memberA, deactivate);
        await cubit.apply(memberB, deactivate);
        expect(cubit.state.problems.keys.toSet(), <String>{memberA, memberB});

        repository.manual = true;
        final Future<void> retryA = cubit.apply(memberA, deactivate);

        expect(cubit.state.problemFor(memberA), isNull);
        expect(
          cubit.state.problemFor(memberB),
          RetailerStaffLifecycleProblem.denied,
        );

        repository.complete();
        await retryA;
      },
    );
  });

  group('outcomes', () {
    test('a described change notices and rereads', () async {
      final RetailerStaffLifecycleCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.apply(memberA, deactivate);

      expect(
        cubit.state.noticeFor(memberA),
        RetailerStaffLifecycleNotice.deactivated,
      );
      expect(rereadCount, 1);
    });

    test(
      'the notice comes from the confirmed status, not the request',
      () async {
        final RetailerStaffLifecycleCubit cubit = buildCubit();
        addTearDown(cubit.close);
        repository.result = appliedActive();

        await cubit.apply(memberA, deactivate);

        expect(
          cubit.state.noticeFor(memberA),
          RetailerStaffLifecycleNotice.reactivated,
        );
      },
    );

    test('a no-op says so, and still rereads', () async {
      final RetailerStaffLifecycleCubit cubit = buildCubit();
      addTearDown(cubit.close);
      repository.result = const RetailerStaffLifecycleApplied(
        confirmedStatus: RetailerStaffLifecycleStatus.deactivated,
        statusChanged: false,
      );

      await cubit.apply(memberA, deactivate);

      expect(
        cubit.state.noticeFor(memberA),
        RetailerStaffLifecycleNotice.alreadyInactive,
      );
      expect(rereadCount, 1);
    });

    test(
      'an unconfirmed write notices and rereads, and never retries',
      () async {
        final RetailerStaffLifecycleCubit cubit = buildCubit();
        addTearDown(cubit.close);
        repository.result = const RetailerStaffLifecycleUnconfirmed();

        await cubit.apply(memberA, deactivate);

        expect(
          cubit.state.noticeFor(memberA),
          RetailerStaffLifecycleNotice.unconfirmed,
        );
        expect(cubit.state.problemFor(memberA), isNull);
        expect(rereadCount, 1);
        expect(repository.callCount, 1);
      },
    );

    test('a refusal does not reread and does not patch staff state', () async {
      final RetailerStaffLifecycleCubit cubit = buildCubit();
      addTearDown(cubit.close);
      repository.result = refusedStaffLifecycle(
        RetailerStaffLifecycleProblem.denied,
      );

      await cubit.apply(memberA, deactivate);

      expect(rereadCount, 0);
      expect(cubit.state.noticeFor(memberA), isNull);
    });

    test('no problem is ever retried automatically', () async {
      final RetailerStaffLifecycleCubit cubit = buildCubit();
      addTearDown(cubit.close);

      for (final RetailerStaffLifecycleProblem problem
          in RetailerStaffLifecycleProblem.values) {
        repository.writes.clear();
        repository.result = refusedStaffLifecycle(problem);
        cubit.dismiss(memberA);
        await cubit.apply(memberA, deactivate);
        expect(
          repository.callCount,
          1,
          reason: '$problem must produce exactly one call',
        );
      }
    });
  });

  group('clear() invalidates every request', () {
    test('a stale result is dropped, with no reread', () async {
      final RetailerStaffLifecycleCubit cubit = buildCubit();
      addTearDown(cubit.close);
      repository.manual = true;

      final Future<void> pending = cubit.apply(memberA, deactivate);
      cubit.clear();

      repository.complete();
      await pending;

      expect(cubit.state, const RetailerStaffLifecycleState());
      expect(rereadCount, 0);
    });

    test('clear invalidates BOTH of two in-flight requests', () async {
      final RetailerStaffLifecycleCubit cubit = buildCubit();
      addTearDown(cubit.close);
      repository.manual = true;

      final Future<void> a = cubit.apply(memberA, deactivate);
      final Future<void> b = cubit.apply(memberB, deactivate);

      cubit.clear();

      repository.complete();
      repository.complete();
      await a;
      await b;

      expect(cubit.state.isIdle, isTrue);
      expect(cubit.state.noticeFor(memberA), isNull);
      expect(cubit.state.noticeFor(memberB), isNull);
      expect(rereadCount, 0);
    });

    test('clear empties every collection and advances the epoch', () async {
      final RetailerStaffLifecycleCubit cubit = buildCubit();
      addTearDown(cubit.close);
      repository.result = refusedStaffLifecycle(
        RetailerStaffLifecycleProblem.denied,
      );
      await cubit.apply(memberA, deactivate);
      final int before = cubit.epoch;

      cubit.clear();

      expect(cubit.state.busyMembershipIds, isEmpty);
      expect(cubit.state.problems, isEmpty);
      expect(cubit.state.notices, isEmpty);
      expect(cubit.epoch, greaterThan(before));
    });
  });

  group('rosterChanged invalidates a departed membership', () {
    test(
      'a request in flight for a departed membership is suppressed entirely',
      () async {
        final RetailerStaffLifecycleCubit cubit = buildCubit();
        addTearDown(cubit.close);
        repository.manual = true;

        // 1. Start a request for A.
        final Future<void> pending = cubit.apply(memberA, deactivate);
        expect(cubit.state.isBusyFor(memberA), isTrue);

        // 2. Before it completes, the roster no longer lists A.
        cubit.rosterChanged(<String>[memberB]);
        expect(cubit.state.isBusyFor(memberA), isFalse);

        // 3. The repository answers successfully.
        repository.complete();
        await pending;

        // 4. Nothing for A survives, and the roster is NOT re-read: the roster
        //    was just re-read — that is how A departed — so a second call would
        //    learn nothing.
        expect(cubit.state.noticeFor(memberA), isNull);
        expect(cubit.state.problemFor(memberA), isNull);
        expect(cubit.state.isBusyFor(memberA), isFalse);
        expect(cubit.state.isIdle, isTrue);
        expect(rereadCount, 0);
      },
    );

    test('A is suppressed while B, still present, keeps its result', () async {
      final RetailerStaffLifecycleCubit cubit = buildCubit();
      addTearDown(cubit.close);
      repository.manual = true;

      // 1. Requests for A and B.
      final Future<void> a = cubit.apply(memberA, deactivate);
      final Future<void> b = cubit.apply(memberB, deactivate);

      // 2. A leaves the roster; B stays.
      cubit.rosterChanged(<String>[memberB]);
      expect(cubit.state.isBusyFor(memberA), isFalse);
      expect(cubit.state.isBusyFor(memberB), isTrue);

      // 3. Both complete successfully.
      repository.completeAt(1, appliedDeactivated());
      await b;
      repository.completeAt(0, appliedDeactivated());
      await a;

      // 4. B's result stands; A's is suppressed.
      expect(
        cubit.state.noticeFor(memberB),
        RetailerStaffLifecycleNotice.deactivated,
      );
      expect(cubit.state.noticeFor(memberA), isNull);
      // Exactly one canonical reread — B's.
      expect(rereadCount, 1);
    });

    test('a settled outcome for a departed membership is dropped', () async {
      final RetailerStaffLifecycleCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.apply(memberA, deactivate);
      expect(cubit.state.noticeFor(memberA), isNotNull);

      cubit.rosterChanged(<String>[memberB]);

      expect(cubit.state.noticeFor(memberA), isNull);
      expect(cubit.state.isIdle, isTrue);
    });

    test(
      'rosterChanged keeps everything whose membership is present',
      () async {
        final RetailerStaffLifecycleCubit cubit = buildCubit();
        addTearDown(cubit.close);
        await cubit.apply(memberA, deactivate);

        cubit.rosterChanged(<String>[memberA, memberB]);

        expect(
          cubit.state.noticeFor(memberA),
          RetailerStaffLifecycleNotice.deactivated,
        );
      },
    );

    test(
      'a suppressed membership may be acted on again if it returns',
      () async {
        final RetailerStaffLifecycleCubit cubit = buildCubit();
        addTearDown(cubit.close);
        repository.manual = true;

        final Future<void> first = cubit.apply(memberA, deactivate);
        cubit.rosterChanged(<String>[memberB]);
        repository.complete();
        await first;

        // A is back in the roster and is pressable again — the generation bump
        // invalidated the answer, not the membership.
        expect(cubit.state.isBusyFor(memberA), isFalse);
        repository.manual = false;
        await cubit.apply(memberA, deactivate);

        expect(repository.callCount, 2);
        expect(
          cubit.state.noticeFor(memberA),
          RetailerStaffLifecycleNotice.deactivated,
        );
      },
    );
  });

  group('dismiss is scoped to one membership', () {
    test('dismissing A leaves B untouched', () async {
      final RetailerStaffLifecycleCubit cubit = buildCubit();
      addTearDown(cubit.close);
      await cubit.apply(memberA, deactivate);
      await cubit.apply(memberB, deactivate);

      cubit.dismiss(memberA);

      expect(cubit.state.noticeFor(memberA), isNull);
      expect(
        cubit.state.noticeFor(memberB),
        RetailerStaffLifecycleNotice.deactivated,
      );
    });

    test('dismiss re-issues nothing', () async {
      final RetailerStaffLifecycleCubit cubit = buildCubit();
      addTearDown(cubit.close);
      await cubit.apply(memberA, deactivate);

      cubit.dismiss(memberA);

      expect(repository.callCount, 1);
    });

    test('dismiss is a no-op while that row is in flight', () async {
      final RetailerStaffLifecycleCubit cubit = buildCubit();
      addTearDown(cubit.close);
      repository.manual = true;

      final Future<void> pending = cubit.apply(memberA, deactivate);
      cubit.dismiss(memberA);

      expect(cubit.state.isBusyFor(memberA), isTrue);

      repository.complete();
      await pending;
    });
  });
}
