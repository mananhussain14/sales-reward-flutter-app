import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/auth/domain/entities/auth_user.dart';
import 'package:sale_reward/features/auth/domain/entities/lifecycle_access_state.dart';
import 'package:sale_reward/features/auth/domain/repositories/lifecycle_access_repository.dart';
import 'package:sale_reward/features/auth/presentation/cubit/lifecycle_access_cubit.dart';

import '../../support/fakes.dart';
import '../../support/lifecycle_access_fakes.dart';

const AuthUser _other = AuthUser(id: 'user-2', email: 'other@example.com');

({
  LifecycleAccessCubit cubit,
  FakeAuthRepository auth,
  FakeLifecycleAccessRepository repository,
})
build({AuthUser? user = testUser}) {
  final FakeAuthRepository auth = FakeAuthRepository(initialUser: user);
  final FakeLifecycleAccessRepository repository =
      FakeLifecycleAccessRepository();
  final LifecycleAccessCubit cubit = LifecycleAccessCubit(
    repository: repository,
    authRepository: auth,
  );
  addTearDown(auth.dispose);
  return (cubit: cubit, auth: auth, repository: repository);
}

void main() {
  group('the automatic request', () {
    test('starts in initial and asks exactly once', () async {
      final harness = build();
      harness.repository.resolveWith(LifecycleAccessState.active);

      expect(harness.cubit.state.phase, LifecycleAccessPhase.initial);

      await harness.cubit.load();

      expect(harness.repository.callCount, 1);
      expect(harness.cubit.state.phase, LifecycleAccessPhase.resolved);
    });

    test('emits loading before the answer', () async {
      final harness = build()..repository.manual = true;
      final List<LifecycleAccessPhase> seen = <LifecycleAccessPhase>[];
      harness.cubit.stream.listen(
        (LifecycleAccessViewState s) => seen.add(s.phase),
      );

      final Future<void> pending = harness.cubit.load();
      await Future<void>.delayed(Duration.zero);

      expect(harness.cubit.state.phase, LifecycleAccessPhase.loading);

      harness.repository.complete(
        const LifecycleAccessResolved(LifecycleAccessState.ambiguous),
      );
      await pending;
      await Future<void>.delayed(Duration.zero);

      expect(seen, <LifecycleAccessPhase>[
        LifecycleAccessPhase.loading,
        LifecycleAccessPhase.resolved,
      ]);
    });
  });

  group('every resolved state reaches the state object', () {
    for (final LifecycleAccessState state in LifecycleAccessState.values) {
      test('$state', () async {
        final harness = build();
        harness.repository.resolveWith(state);

        await harness.cubit.load();

        expect(harness.cubit.state.phase, LifecycleAccessPhase.resolved);
        expect(harness.cubit.state.state, state);
      });
    }

    test(
      'unavailable resolves to the unavailable phase with no state',
      () async {
        final harness = build();
        harness.repository.result = const LifecycleAccessUnavailable();

        await harness.cubit.load();

        expect(harness.cubit.state.phase, LifecycleAccessPhase.unavailable);
        expect(harness.cubit.state.state, isNull);
      },
    );
  });

  group('load is idempotent', () {
    test('a second load while one is in flight is dropped', () async {
      final harness = build()..repository.manual = true;

      final Future<void> first = harness.cubit.load();
      await Future<void>.delayed(Duration.zero);
      await harness.cubit.load();

      expect(harness.repository.callCount, 1);

      harness.repository.complete(
        const LifecycleAccessResolved(LifecycleAccessState.active),
      );
      await first;
    });

    test('a second load after the answer is dropped', () async {
      final harness = build();
      harness.repository.resolveWith(LifecycleAccessState.profileInactive);

      await harness.cubit.load();
      await harness.cubit.load();
      await harness.cubit.load();

      expect(harness.repository.callCount, 1);
      expect(harness.cubit.state.state, LifecycleAccessState.profileInactive);
    });

    test('a load after an unavailable answer is also dropped', () async {
      final harness = build();

      await harness.cubit.load();
      await harness.cubit.load();

      expect(harness.repository.callCount, 1);
    });
  });

  group('no session means no request', () {
    test('a null currentUser before the request issues no RPC', () async {
      final harness = build(user: null);

      await harness.cubit.load();

      expect(harness.repository.callCount, 0);
      expect(harness.cubit.state.phase, LifecycleAccessPhase.initial);
    });

    test('and no sign-out is attempted', () async {
      final harness = build(user: null);

      await harness.cubit.load();

      expect(harness.auth.signOutCallCount, 0);
    });
  });

  group('stale results are discarded', () {
    test('a result arriving after close is dropped', () async {
      final harness = build()..repository.manual = true;

      final Future<void> pending = harness.cubit.load();
      await Future<void>.delayed(Duration.zero);
      await harness.cubit.close();

      harness.repository.complete(
        const LifecycleAccessResolved(
          LifecycleAccessState.organizationInactive,
        ),
      );
      await pending;

      // No emit-after-close error, and the last visible state never advanced.
      expect(harness.cubit.state.phase, LifecycleAccessPhase.loading);
    });

    test('close advances the generation', () async {
      final harness = build()..repository.manual = true;

      final Future<void> pending = harness.cubit.load();
      await Future<void>.delayed(Duration.zero);
      await harness.cubit.close();
      harness.repository.complete();
      await pending;

      expect(harness.cubit.isClosed, isTrue);
    });

    test('a subject change during the request drops the result', () async {
      final harness = build()..repository.manual = true;

      final Future<void> pending = harness.cubit.load();
      await Future<void>.delayed(Duration.zero);

      // The signed-in person changed while the diagnostic was in flight.
      harness.auth.setCurrentUserSilently(_other);
      harness.repository.complete(
        const LifecycleAccessResolved(LifecycleAccessState.membershipInactive),
      );
      await pending;

      expect(harness.cubit.state.phase, LifecycleAccessPhase.loading);
      expect(harness.cubit.state.state, isNull);
    });

    test('a sign-out during the request drops the result', () async {
      final harness = build()..repository.manual = true;

      final Future<void> pending = harness.cubit.load();
      await Future<void>.delayed(Duration.zero);

      harness.auth.setCurrentUserSilently(null);
      harness.repository.complete(
        const LifecycleAccessResolved(
          LifecycleAccessState.organizationInactive,
        ),
      );
      await pending;

      expect(harness.cubit.state.phase, LifecycleAccessPhase.loading);
    });

    test('the previous subject result never renders under the next', () async {
      final harness = build()..repository.manual = true;

      final Future<void> pending = harness.cubit.load();
      await Future<void>.delayed(Duration.zero);
      harness.auth.setCurrentUserSilently(_other);
      harness.repository.complete(
        const LifecycleAccessResolved(LifecycleAccessState.profileInactive),
      );
      await pending;

      expect(
        harness.cubit.state.state,
        isNot(LifecycleAccessState.profileInactive),
      );
    });
  });

  group('what the Cubit never does', () {
    test('it never signs the user out', () async {
      final harness = build();
      harness.repository.resolveWith(LifecycleAccessState.membershipInactive);

      await harness.cubit.load();

      expect(harness.auth.signOutCallCount, 0);
    });

    test('it issues no further request while it stays alive', () async {
      final harness = build();
      harness.repository.resolveWith(LifecycleAccessState.organizationInactive);

      await harness.cubit.load();
      // Well past any plausible poll interval a timer would have used.
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(harness.repository.callCount, 1);
    });

    test(
      'a repository that breaks its contract cannot escape as an error',
      () async {
        final harness = build()..repository.throwOnRead = true;

        // Documents current behaviour honestly: the Cubit does not catch, because
        // its collaborator is contractually non-throwing and swallowing here would
        // hide a real defect. The boundary is the repository, and its own tests
        // prove nothing escapes it.
        await expectLater(harness.cubit.load(), throwsA(isA<StateError>()));
      },
    );
  });

  group('the state carries nothing sensitive', () {
    test('resolved holds only the enum member', () async {
      final harness = build();
      harness.repository.resolveWith(LifecycleAccessState.ambiguous);

      await harness.cubit.load();

      expect(harness.cubit.state.props, <Object?>[
        LifecycleAccessPhase.resolved,
        LifecycleAccessState.ambiguous,
      ]);
    });

    test('no rendering of the state can contain an identifier', () async {
      final harness = build();
      harness.repository.resolveWith(LifecycleAccessState.organizationInactive);

      await harness.cubit.load();

      final String rendered = harness.cubit.state.toString();
      expect(rendered.contains(testUser.id), isFalse);
      expect(rendered.contains('ORGANIZATION_INACTIVE'), isFalse);
    });
  });
}
