import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/core/result/read_result.dart';
import 'package:sale_reward/features/dashboard/domain/entities/vendor_dashboard_summary.dart';
import 'package:sale_reward/features/dashboard/presentation/vendor/cubit/vendor_dashboard_cubit.dart';

import '../../support/vendor_dashboard_fakes.dart';

/// The cubit's job is to hold **one snapshot** and to be honest about how old it
/// is.
///
/// Three rules it must never break, each tested from several directions:
///
/// 1. **The four counts are replaced together or not at all.** They come from one
///    statement and describe one instant.
/// 2. **A failure never becomes a figure.** Not zeros, not a partial summary, not
///    a carried-over field.
/// 3. **An answer for a previous identity never lands.** The request token drops a
///    stale first read and a stale refresh alike.
void main() {
  late FakeVendorDashboardRepository repository;

  setUp(() => repository = FakeVendorDashboardRepository());

  VendorDashboardCubit buildCubit() => VendorDashboardCubit(repository);

  group('the first read', () {
    test('starts in initial with nothing loaded', () {
      final VendorDashboardCubit cubit = buildCubit();

      expect(cubit.state.phase, VendorDashboardPhase.initial);
      expect(cubit.state.summary, isNull);
      expect(cubit.state.failure, isNull);
      expect(cubit.state.isRefreshing, isFalse);
      expect(cubit.state.isFirstLoad, isTrue);
      addTearDown(cubit.close);
    });

    test('shows the loading phase while the read is in flight', () async {
      repository.manual = true;
      final VendorDashboardCubit cubit = buildCubit();
      addTearDown(cubit.close);

      unawaited(cubit.load());
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.phase, VendorDashboardPhase.loading);
      expect(cubit.state.isRefreshing, isTrue);
      expect(cubit.state.isFirstLoad, isTrue);
      // Nothing is shown, and nothing is invented, while the answer is unknown.
      expect(cubit.state.summary, isNull);

      repository.complete();
      await Future<void>.delayed(Duration.zero);
    });

    test('a successful read holds the whole snapshot', () async {
      final VendorDashboardCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.phase, VendorDashboardPhase.ready);
      expect(cubit.state.summary, exampleDashboardSummary);
      expect(cubit.state.isRefreshing, isFalse);
      expect(cubit.state.failure, isNull);
      expect(cubit.state.isFirstLoad, isFalse);
    });

    test(
      'an all-zero tenant summary is a real answer, not an empty one',
      () async {
        repository.nextSummary = emptyTenantDashboardSummary;
        final VendorDashboardCubit cubit = buildCubit();
        addTearDown(cubit.close);

        await cubit.load();

        expect(cubit.state.phase, VendorDashboardPhase.ready);
        expect(cubit.state.summary!.activeMemberCount, 0);
        expect(cubit.state.summary!.auditEventCount, 0);
        // The global catalogue counts stay non-zero, which is exactly what makes
        // "four zeros" the wrong way to render a denial.
        expect(cubit.state.summary!.catalogActiveRoleCount, 6);
        expect(cubit.state.hasFailedFirstRead, isFalse);
      },
    );

    test(
      'a failed first read keeps the failure and shows no figures',
      () async {
        repository.result = unavailableDashboardRead<VendorDashboardSummary>();
        final VendorDashboardCubit cubit = buildCubit();
        addTearDown(cubit.close);

        await cubit.load();

        expect(cubit.state.phase, VendorDashboardPhase.failed);
        expect(cubit.state.failure, isA<UnavailableFailure>());
        expect(cubit.state.summary, isNull);
        expect(cubit.state.hasFailedFirstRead, isTrue);
        expect(cubit.state.isStale, isFalse);
      },
    );

    test('a denial is a failure, never a summary of zeros', () async {
      repository.result = deniedDashboardRead<VendorDashboardSummary>();
      final VendorDashboardCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.failure, isA<DeniedFailure>());
      expect(cubit.state.summary, isNull);
    });

    test('a retry after a failure can succeed', () async {
      repository.result = unavailableDashboardRead<VendorDashboardSummary>();
      final VendorDashboardCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.load();
      expect(cubit.state.hasFailedFirstRead, isTrue);

      repository.result = null;
      await cubit.load();

      expect(cubit.state.phase, VendorDashboardPhase.ready);
      expect(cubit.state.summary, exampleDashboardSummary);
      expect(cubit.state.failure, isNull);
      expect(repository.callCount, 2);
    });
  });

  group('refresh', () {
    test('replaces the whole summary atomically', () async {
      final VendorDashboardCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.load();
      expect(cubit.state.summary, exampleDashboardSummary);

      // Every one of the four counts moves. None may be carried over.
      const VendorDashboardSummary next = VendorDashboardSummary(
        activeMemberCount: 9,
        catalogActiveRoleCount: 7,
        catalogPermissionCount: 19,
        auditEventCount: 1300,
      );
      repository.nextSummary = next;
      await cubit.refresh();

      expect(cubit.state.summary, next);
      expect(cubit.state.summary!.activeMemberCount, 9);
      expect(cubit.state.summary!.catalogActiveRoleCount, 7);
      expect(cubit.state.summary!.catalogPermissionCount, 19);
      expect(cubit.state.summary!.auditEventCount, 1300);
    });

    test(
      'a count that falls is replaced, not kept at its higher value',
      () async {
        final VendorDashboardCubit cubit = buildCubit();
        addTearDown(cubit.close);

        await cubit.load();
        repository.nextSummary = const VendorDashboardSummary(
          activeMemberCount: 1,
          catalogActiveRoleCount: 6,
          catalogPermissionCount: 18,
          auditEventCount: 1204,
        );
        await cubit.refresh();

        expect(cubit.state.summary!.activeMemberCount, 1);
      },
    );

    test('keeps the figures on screen while it runs', () async {
      final VendorDashboardCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.load();

      repository.manual = true;
      unawaited(cubit.refresh());
      await Future<void>.delayed(Duration.zero);

      // Visibly refreshing, but the previous snapshot is still on screen — a
      // refresh updates figures, it does not blank them.
      expect(cubit.state.isRefreshing, isTrue);
      expect(cubit.state.phase, VendorDashboardPhase.ready);
      expect(cubit.state.summary, exampleDashboardSummary);
      expect(cubit.state.isFirstLoad, isFalse);

      repository.complete();
      await Future<void>.delayed(Duration.zero);
    });

    test('a failed refresh preserves the stale summary', () async {
      final VendorDashboardCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.load();
      repository.result = unavailableDashboardRead<VendorDashboardSummary>();
      await cubit.refresh();

      expect(cubit.state.phase, VendorDashboardPhase.failed);
      expect(cubit.state.failure, isA<UnavailableFailure>());
      // The figures stay. They are still the last thing the backend said.
      expect(cubit.state.summary, exampleDashboardSummary);
      expect(cubit.state.isStale, isTrue);
      expect(cubit.state.hasFailedFirstRead, isFalse);
    });

    test('a denied refresh preserves the stale summary too', () async {
      final VendorDashboardCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.load();
      repository.result = deniedDashboardRead<VendorDashboardSummary>();
      await cubit.refresh();

      expect(cubit.state.failure, isA<DeniedFailure>());
      expect(cubit.state.summary, exampleDashboardSummary);
      expect(cubit.state.isStale, isTrue);
    });

    test('a failed refresh never zeroes a count', () async {
      final VendorDashboardCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.load();
      repository.result = unavailableDashboardRead<VendorDashboardSummary>();
      await cubit.refresh();

      expect(cubit.state.summary!.activeMemberCount, 7);
      expect(cubit.state.summary!.auditEventCount, 1204);
    });

    test('a retry after a failed refresh clears the notice', () async {
      final VendorDashboardCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.load();
      repository.result = unavailableDashboardRead<VendorDashboardSummary>();
      await cubit.refresh();
      expect(cubit.state.isStale, isTrue);

      repository.result = null;
      await cubit.refresh();

      expect(cubit.state.phase, VendorDashboardPhase.ready);
      expect(cubit.state.failure, isNull);
      expect(cubit.state.isStale, isFalse);
    });

    test('a second refresh while one is in flight is a no-op', () async {
      repository.manual = true;
      final VendorDashboardCubit cubit = buildCubit();
      addTearDown(cubit.close);

      unawaited(cubit.load());
      await Future<void>.delayed(Duration.zero);
      expect(repository.callCount, 1);

      unawaited(cubit.refresh());
      unawaited(cubit.refresh());
      await Future<void>.delayed(Duration.zero);

      // Still one. Two answers to the same question could arrive out of order
      // and leave the older one on screen.
      expect(repository.callCount, 1);
      expect(repository.pendingCount, 1);

      repository.complete();
      await Future<void>.delayed(Duration.zero);
    });

    test(
      'a refresh after the in-flight one settles does issue a call',
      () async {
        final VendorDashboardCubit cubit = buildCubit();
        addTearDown(cubit.close);

        await cubit.load();
        await cubit.refresh();

        expect(repository.callCount, 2);
      },
    );

    test('a refresh with nothing loaded shows the loading state', () async {
      // A pull-to-refresh on a screen whose first read failed: there is nothing
      // on screen to preserve, so it behaves like a first read.
      repository.result = unavailableDashboardRead<VendorDashboardSummary>();
      final VendorDashboardCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.load();
      repository.result = null;
      repository.manual = true;
      unawaited(cubit.refresh());
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.phase, VendorDashboardPhase.loading);
      expect(cubit.state.isFirstLoad, isTrue);

      repository.complete();
      await Future<void>.delayed(Duration.zero);
    });
  });

  group('stale answers', () {
    test('a first read landing after a clear is ignored', () async {
      repository.manual = true;
      final VendorDashboardCubit cubit = buildCubit();
      addTearDown(cubit.close);

      unawaited(cubit.load());
      await Future<void>.delayed(Duration.zero);

      cubit.clear();
      repository.complete();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.summary, isNull);
      expect(cubit.state.phase, VendorDashboardPhase.initial);
    });

    test('a refresh landing after a clear is ignored', () async {
      final VendorDashboardCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.load();
      repository.manual = true;
      unawaited(cubit.refresh());
      await Future<void>.delayed(Duration.zero);

      cubit.clear();
      repository.complete();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.summary, isNull);
      expect(cubit.state.phase, VendorDashboardPhase.initial);
    });

    test('a failed read landing after a clear cannot set a failure', () async {
      repository.manual = true;
      final VendorDashboardCubit cubit = buildCubit();
      addTearDown(cubit.close);

      unawaited(cubit.load());
      await Future<void>.delayed(Duration.zero);

      cubit.clear();
      repository.complete(unavailableDashboardRead<VendorDashboardSummary>());
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.failure, isNull);
      expect(cubit.state.phase, VendorDashboardPhase.initial);
    });

    test('an older answer cannot overwrite a newer one', () async {
      repository.manual = true;
      final VendorDashboardCubit cubit = buildCubit();
      addTearDown(cubit.close);

      unawaited(cubit.load());
      await Future<void>.delayed(Duration.zero);

      // A session change between the two: the token advances, and the second
      // read belongs to the new identity.
      cubit.clear();
      unawaited(cubit.load());
      await Future<void>.delayed(Duration.zero);
      expect(repository.pendingCount, 2);

      // The newer answer settles first.
      repository.completeAt(
        1,
        const ReadSuccess<VendorDashboardSummary>(otherVendorDashboardSummary),
      );
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.summary, otherVendorDashboardSummary);

      // The older one lands late and must be discarded.
      repository.completeAt(
        0,
        const ReadSuccess<VendorDashboardSummary>(exampleDashboardSummary),
      );
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.summary, otherVendorDashboardSummary);
    });
  });

  group('clearing', () {
    test('drops the summary, the failure and both flags', () async {
      final VendorDashboardCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.load();
      repository.result = unavailableDashboardRead<VendorDashboardSummary>();
      await cubit.refresh();
      expect(cubit.state.isStale, isTrue);

      cubit.clear();

      expect(cubit.state, const VendorDashboardState());
      expect(cubit.state.summary, isNull);
      expect(cubit.state.failure, isNull);
      expect(cubit.state.isRefreshing, isFalse);
      expect(cubit.state.phase, VendorDashboardPhase.initial);
    });

    test('the whole snapshot goes, not just the tenant half', () async {
      // A summary carrying only its two global counts is a shape no backend
      // answer ever produces, so there is no half-cleared state to fall into.
      final VendorDashboardCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.load();
      cubit.clear();

      expect(cubit.state.summary, isNull);
    });

    test('a load after a clear reads again', () async {
      final VendorDashboardCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.load();
      cubit.clear();
      await cubit.load();

      expect(repository.callCount, 2);
      expect(cubit.state.summary, exampleDashboardSummary);
    });
  });

  group('the state exposes no per-count setter', () {
    test('copyWith replaces the snapshot whole', () async {
      const VendorDashboardState state = VendorDashboardState(
        phase: VendorDashboardPhase.ready,
        summary: exampleDashboardSummary,
      );

      final VendorDashboardState next = state.copyWith(
        summary: otherVendorDashboardSummary,
      );

      expect(next.summary, otherVendorDashboardSummary);
      // Not merged: every field came from the new snapshot.
      expect(next.summary!.activeMemberCount, 2);
      expect(next.summary!.auditEventCount, 5);
    });

    test('equality is by phase, summary, failure and the refresh flag', () {
      const VendorDashboardState a = VendorDashboardState(
        phase: VendorDashboardPhase.ready,
        summary: exampleDashboardSummary,
      );
      const VendorDashboardState b = VendorDashboardState(
        phase: VendorDashboardPhase.ready,
        summary: exampleDashboardSummary,
      );

      expect(a, b);
      expect(a, isNot(b.copyWith(summary: otherVendorDashboardSummary)));
      expect(a, isNot(b.copyWith(isRefreshing: true)));
    });
  });
}
