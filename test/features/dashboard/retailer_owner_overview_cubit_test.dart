import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/dashboard/domain/repositories/retailer_owner_overview_repository.dart';
import 'package:sale_reward/features/dashboard/presentation/retailer_owner/cubit/retailer_owner_overview_cubit.dart';

import '../../support/retailer_owner_overview_fakes.dart';

/// The Retailer Owner Overview cubit.
///
/// Three properties carry the milestone's weight and each has its own group: a
/// refresh never blanks what is on screen, a stale answer can never repopulate a
/// cleared cubit, and "ineligible" is a settled answer rather than an error.
void main() {
  late FakeRetailerOwnerOverviewRepository repository;

  setUp(() => repository = FakeRetailerOwnerOverviewRepository());

  RetailerOwnerOverviewCubit build() => RetailerOwnerOverviewCubit(repository);

  group('load', () {
    blocTest<RetailerOwnerOverviewCubit, RetailerOwnerOverviewState>(
      'shows the skeleton and then the overview',
      build: build,
      act: (RetailerOwnerOverviewCubit c) => c.load(),
      expect: () => <Matcher>[
        isA<RetailerOwnerOverviewState>()
            .having(
              (RetailerOwnerOverviewState s) => s.phase,
              'phase',
              RetailerOverviewPhase.loading,
            )
            .having(
              (RetailerOwnerOverviewState s) => s.isInitialLoading,
              'isInitialLoading',
              isTrue,
            ),
        isA<RetailerOwnerOverviewState>()
            .having(
              (RetailerOwnerOverviewState s) => s.phase,
              'phase',
              RetailerOverviewPhase.ready,
            )
            .having(
              (RetailerOwnerOverviewState s) => s.overview,
              'overview',
              exampleRetailerOverview,
            )
            .having(
              (RetailerOwnerOverviewState s) => s.isRefreshing,
              'isRefreshing',
              isFalse,
            ),
      ],
    );

    blocTest<RetailerOwnerOverviewCubit, RetailerOwnerOverviewState>(
      'a failed first read is the whole screen and holds no overview',
      build: () {
        repository.result = const RetailerOverviewFailed(
          RetailerOverviewProblem.network,
        );
        return build();
      },
      act: (RetailerOwnerOverviewCubit c) => c.load(),
      verify: (RetailerOwnerOverviewCubit c) {
        expect(c.state.hasFailedOutright, isTrue);
        expect(c.state.overview, isNull);
        expect(c.state.problem, RetailerOverviewProblem.network);
      },
    );

    blocTest<RetailerOwnerOverviewCubit, RetailerOwnerOverviewState>(
      'zero rows settles on ineligible, with no problem and no overview',
      build: () {
        repository.result = const RetailerOverviewIneligible();
        return build();
      },
      act: (RetailerOwnerOverviewCubit c) => c.load(),
      verify: (RetailerOwnerOverviewCubit c) {
        expect(c.state.phase, RetailerOverviewPhase.ineligible);
        expect(c.state.overview, isNull);
        // Not an error: nothing to retry, and nothing to explain away.
        expect(c.state.problem, isNull);
        expect(c.state.hasFailedOutright, isFalse);
        expect(c.state.isRefreshing, isFalse);
      },
    );
  });

  group('refresh', () {
    blocTest<RetailerOwnerOverviewCubit, RetailerOwnerOverviewState>(
      'keeps the figures on screen while re-reading',
      build: build,
      act: (RetailerOwnerOverviewCubit c) async {
        await c.load();
        repository.nextOverview = otherRetailerOverview;
        await c.refresh();
      },
      verify: (RetailerOwnerOverviewCubit c) {
        expect(c.state.overview, otherRetailerOverview);
        expect(repository.callCount, 2);
      },
    );

    test('never blanks the values mid-refresh', () async {
      repository.manual = true;
      final RetailerOwnerOverviewCubit cubit = build();

      unawaitedLoad(cubit);
      repository.complete();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.overview, exampleRetailerOverview);

      final Future<void> refreshing = cubit.refresh();
      await Future<void>.delayed(Duration.zero);

      // The whole point of a refresh over a load: the previous answer is still
      // on screen, and the spinner says a read is happening.
      expect(cubit.state.overview, exampleRetailerOverview);
      expect(cubit.state.isRefreshing, isTrue);
      expect(cubit.state.isInitialLoading, isFalse);

      repository.complete();
      await refreshing;
      await cubit.close();
    });

    blocTest<RetailerOwnerOverviewCubit, RetailerOwnerOverviewState>(
      'a failed refresh keeps the last good overview and marks it stale',
      build: build,
      act: (RetailerOwnerOverviewCubit c) async {
        await c.load();
        repository.result = const RetailerOverviewFailed(
          RetailerOverviewProblem.timeout,
        );
        await c.refresh();
      },
      verify: (RetailerOwnerOverviewCubit c) {
        // Still the last thing the backend actually said. Discarding it would
        // replace real figures with nothing; zeroing it would replace them with
        // a lie.
        expect(c.state.overview, exampleRetailerOverview);
        expect(c.state.isStale, isTrue);
        expect(c.state.hasFailedOutright, isFalse);
        expect(c.state.problem, RetailerOverviewProblem.timeout);
      },
    );

    blocTest<RetailerOwnerOverviewCubit, RetailerOwnerOverviewState>(
      'a successful refresh clears a previous problem',
      build: build,
      act: (RetailerOwnerOverviewCubit c) async {
        await c.load();
        repository.result = const RetailerOverviewFailed(
          RetailerOverviewProblem.network,
        );
        await c.refresh();
        repository.result = null;
        await c.refresh();
      },
      verify: (RetailerOwnerOverviewCubit c) {
        // A stale error notice must not survive above fresh figures.
        expect(c.state.problem, isNull);
        expect(c.state.isStale, isFalse);
      },
    );

    blocTest<RetailerOwnerOverviewCubit, RetailerOwnerOverviewState>(
      'becoming ineligible on refresh drops the previously held overview',
      build: build,
      act: (RetailerOwnerOverviewCubit c) async {
        await c.load();
        repository.result = const RetailerOverviewIneligible();
        await c.refresh();
      },
      verify: (RetailerOwnerOverviewCubit c) {
        // Access was withdrawn between the two reads. Keeping the row would
        // leave an organization on screen the backend has stopped returning.
        expect(c.state.overview, isNull);
        expect(c.state.phase, RetailerOverviewPhase.ineligible);
      },
    );

    test(
      'a second refresh while one is in flight issues no second call',
      () async {
        repository.manual = true;
        final RetailerOwnerOverviewCubit cubit = build();

        unawaitedLoad(cubit);
        await Future<void>.delayed(Duration.zero);
        expect(repository.callCount, 1);

        // Two answers to the same question could arrive out of order and leave
        // the older one on screen.
        unawaitedRefresh(cubit);
        unawaitedRefresh(cubit);
        await Future<void>.delayed(Duration.zero);

        expect(repository.callCount, 1);
        expect(repository.pendingCount, 1);

        repository.complete();
        await Future<void>.delayed(Duration.zero);
        await cubit.close();
      },
    );
  });

  group('session isolation', () {
    blocTest<RetailerOwnerOverviewCubit, RetailerOwnerOverviewState>(
      'clear empties the overview, the problem and the refresh state',
      build: build,
      act: (RetailerOwnerOverviewCubit c) async {
        await c.load();
        c.clear();
      },
      verify: (RetailerOwnerOverviewCubit c) {
        expect(c.state, const RetailerOwnerOverviewState());
        expect(c.state.overview, isNull);
        expect(c.state.problem, isNull);
        expect(c.state.phase, RetailerOverviewPhase.initial);
        expect(c.state.isRefreshing, isFalse);
      },
    );

    test('an answer in flight at clear() cannot refill the cubit', () async {
      // The stale-response race the request token exists to close: Owner A's
      // read lands after A has been replaced by B.
      repository.manual = true;
      final RetailerOwnerOverviewCubit cubit = build();

      unawaitedLoad(cubit);
      await Future<void>.delayed(Duration.zero);
      expect(repository.pendingCount, 1);

      cubit.clear();
      expect(cubit.state.overview, isNull);

      // Owner A's answer arrives now, after the switch.
      repository.complete();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.overview, isNull);
      expect(cubit.state.phase, RetailerOverviewPhase.initial);
      await cubit.close();
    });

    test('a stale ineligible answer cannot overwrite a newer load', () async {
      // The reverse direction, and the one a naive "null means empty" check
      // would get wrong: A's zero-row answer must not report B as ineligible.
      repository.manual = true;
      final RetailerOwnerOverviewCubit cubit = build();

      unawaitedLoad(cubit);
      await Future<void>.delayed(Duration.zero);

      cubit.clear();
      unawaitedLoad(cubit);
      await Future<void>.delayed(Duration.zero);
      expect(repository.pendingCount, 2);

      // Complete the OLD one first, out of order.
      repository.completeAt(0, const RetailerOverviewIneligible());
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.phase, isNot(RetailerOverviewPhase.ineligible));

      // Then the current one.
      repository.completeAt(
        0,
        const RetailerOverviewLoaded(otherRetailerOverview),
      );
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.overview, otherRetailerOverview);
      await cubit.close();
    });

    test('the request token advances on every request and on clear', () {
      final RetailerOwnerOverviewCubit cubit = build();
      final int start = cubit.requestToken;

      cubit.clear();
      expect(cubit.requestToken, greaterThan(start));

      cubit.close();
    });
  });
}

/// Starts a load without awaiting it, so a test can inspect the in-flight state.
void unawaitedLoad(RetailerOwnerOverviewCubit cubit) {
  cubit.load();
}

/// Starts a refresh without awaiting it.
void unawaitedRefresh(RetailerOwnerOverviewCubit cubit) {
  cubit.refresh();
}
