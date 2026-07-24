import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/auth/domain/entities/auth_user.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/auth/domain/repositories/portal_context_repository.dart';
import 'package:sale_reward/features/auth/presentation/bloc/session_bloc.dart';

import '../../support/fakes.dart';

/// Drains microtasks and timers so the fire-and-forget resolution future and its
/// internal settle event are fully processed — deterministically, without
/// timing-based sleeps.
Future<void> _settle() => pumpEventQueue();

const AuthUser userA = AuthUser(id: 'user-A', email: 'a@example.com');
const AuthUser userB = AuthUser(id: 'user-B', email: 'b@example.com');

void main() {
  // ==========================================================================
  // Behavioural sequences (kept from the original suite).
  // ==========================================================================
  group('behaviour', () {
    late FakeAuthRepository auth;
    late FakePortalContextRepository portal;

    tearDown(() => auth.dispose());

    SessionBloc build({AuthUser? user, required PortalContextResult result}) {
      auth = FakeAuthRepository(initialUser: user);
      portal = FakePortalContextRepository(result);
      return SessionBloc(authRepository: auth, portalContextRepository: portal);
    }

    blocTest<SessionBloc, SessionState>(
      'no session → unauthenticated, without calling the RPC',
      build: () => build(result: deniedResult),
      act: (SessionBloc b) => b.add(const SessionStarted()),
      expect: () => <Matcher>[isA<SessionUnauthenticated>()],
      verify: (_) => expect(portal.resolveCallCount, 0),
    );

    blocTest<SessionBloc, SessionState>(
      'restored session resolves the context',
      build: () =>
          build(user: userA, result: resolvedResult(PortalKind.retailerOwner)),
      act: (SessionBloc b) => b.add(const SessionStarted()),
      expect: () => <Matcher>[
        isA<SessionResolving>(),
        isA<SessionActive>().having(
          (SessionActive s) => s.portalKind,
          'portalKind',
          PortalKind.retailerOwner,
        ),
      ],
    );

    blocTest<SessionBloc, SessionState>(
      'NONE → denied, not a failure',
      build: () => build(user: userA, result: deniedResult),
      act: (SessionBloc b) => b.add(const SessionStarted()),
      skip: 1,
      expect: () => <Matcher>[isA<SessionDenied>()],
    );

    blocTest<SessionBloc, SessionState>(
      'a resolve failure → unavailable, not denied',
      build: () => build(user: userA, result: unavailableResult),
      act: (SessionBloc b) => b.add(const SessionStarted()),
      skip: 1,
      expect: () => <Matcher>[isA<SessionUnavailable>()],
    );

    blocTest<SessionBloc, SessionState>(
      'sign-out clears the context and goes unauthenticated',
      build: () => build(
        user: userA,
        result: resolvedResult(PortalKind.vendorSuperAdmin),
      ),
      act: (SessionBloc b) async {
        b.add(const SessionStarted());
        await _settle();
        auth.emitSignedOut();
      },
      expect: () => <Matcher>[
        isA<SessionResolving>(),
        isA<SessionActive>(),
        isA<SessionUnauthenticated>(),
      ],
    );

    blocTest<SessionBloc, SessionState>(
      'token refresh for the same user changes nothing and does not re-resolve',
      build: () => build(
        user: userA,
        result: resolvedResult(PortalKind.retailerManager),
      ),
      act: (SessionBloc b) async {
        b.add(const SessionStarted());
        await _settle();
        auth.emitTokenRefreshed(userA);
        await _settle();
      },
      expect: () => <Matcher>[isA<SessionResolving>(), isA<SessionActive>()],
      verify: (_) => expect(portal.resolveCallCount, 1),
    );

    blocTest<SessionBloc, SessionState>(
      'a duplicate sign-in for the same settled user is ignored',
      build: () =>
          build(user: userA, result: resolvedResult(PortalKind.salesStaff)),
      act: (SessionBloc b) async {
        b.add(const SessionStarted());
        await _settle();
        auth.emitSignedIn(userA);
        await _settle();
      },
      expect: () => <Matcher>[isA<SessionResolving>(), isA<SessionActive>()],
      verify: (_) => expect(portal.resolveCallCount, 1),
    );

    blocTest<SessionBloc, SessionState>(
      'a user switch (settled A → B) clears A before resolving B',
      build: () =>
          build(user: userA, result: resolvedResult(PortalKind.retailerOwner)),
      act: (SessionBloc b) async {
        b.add(const SessionStarted());
        await _settle();
        auth.emitSignedIn(userB);
        await _settle();
      },
      expect: () => <Matcher>[
        isA<SessionResolving>(),
        isA<SessionActive>(),
        isA<SessionInitial>(),
        isA<SessionResolving>(),
        isA<SessionActive>(),
      ],
    );
  });

  // ==========================================================================
  // Race regressions — deterministic, driven by a controllable Completer.
  //
  // Each proves BOTH the emitted states and RPC ownership/counts.
  // ==========================================================================
  group('race regressions', () {
    late FakeAuthRepository auth;
    late FakePortalContextRepository portal;
    late SessionBloc bloc;
    late List<SessionState> states;

    void start(AuthUser? user, {PortalContextResult result = deniedResult}) {
      auth = FakeAuthRepository(initialUser: user);
      portal = FakePortalContextRepository(result)..manualCompletion = true;
      bloc = SessionBloc(authRepository: auth, portalContextRepository: portal);
      states = <SessionState>[];
      bloc.stream.listen(states.add);
    }

    tearDown(() async {
      await bloc.close();
      await auth.dispose();
    });

    bool sawActive() => states.whereType<SessionActive>().isNotEmpty;

    test(
      'sign-out while startup resolution is pending ends unauthenticated',
      () async {
        start(userA, result: resolvedResult(PortalKind.vendorSuperAdmin));

        bloc.add(const SessionStarted());
        await _settle();
        expect(bloc.state, isA<SessionResolving>());
        expect(portal.pendingCount, 1, reason: 'A resolution is in flight');

        auth.emitSignedOut();
        await _settle();
        expect(bloc.state, isA<SessionUnauthenticated>());

        // The stale resolution now completes — it must NOT reactivate a shell.
        portal.completeNext();
        await _settle();

        expect(bloc.state, isA<SessionUnauthenticated>());
        expect(
          sawActive(),
          isFalse,
          reason: 'the stale result reactivated a shell',
        );
      },
    );

    test('A→B switch while A is pending: A dropped, B resolved once', () async {
      start(userA, result: resolvedResult(PortalKind.vendorSuperAdmin));

      bloc.add(const SessionStarted());
      await _settle();
      expect(portal.pendingCount, 1);

      auth.emitSignedIn(userB);
      await _settle();
      // A's visible context is discarded immediately; we are resolving B.
      expect(bloc.state, isA<SessionResolving>());
      expect(portal.pendingCount, 2, reason: 'A still pending; B has started');

      // A's (now stale) resolution completes first — must be dropped.
      portal.completeNext(resolvedResult(PortalKind.vendorSuperAdmin));
      await _settle();
      expect(sawActive(), isFalse, reason: "A's result must never activate");
      expect(bloc.state, isA<SessionResolving>());

      // B's resolution completes — the one that wins.
      portal.completeNext(resolvedResult(PortalKind.salesStaff));
      await _settle();

      expect(bloc.state, isA<SessionActive>());
      expect((bloc.state as SessionActive).portalKind, PortalKind.salesStaff);
      expect(
        portal.resolveCallCount,
        2,
        reason: 'A called once, B once — B resolved exactly once',
      );
    });

    test('a stale A result completing after B is active is dropped', () async {
      start(userA, result: resolvedResult(PortalKind.retailerOwner));

      bloc.add(const SessionStarted()); // A pending (gen 1)
      await _settle();
      auth.emitSignedIn(userB); // B pending (gen 2)
      await _settle();

      // Complete B first (the second pending), then A (the stale first).
      portal
        ..completeNext(resolvedResult(PortalKind.retailerOwner)) // A (stale)
        ..completeNext(resolvedResult(PortalKind.salesStaff)); // B (current)
      await _settle();

      // Only B may be active; A's kind must never have appeared.
      expect((bloc.state as SessionActive).portalKind, PortalKind.salesStaff);
      expect(
        states.whereType<SessionActive>().map(
          (SessionActive s) => s.portalKind,
        ),
        isNot(contains(PortalKind.retailerOwner)),
      );
    });

    test('sign-out while a retry is pending does not emit the retry', () async {
      start(userA, result: unavailableResult);

      bloc.add(const SessionStarted());
      await _settle();
      portal.completeNext(unavailableResult);
      await _settle();
      expect(bloc.state, isA<SessionUnavailable>());

      portal.result = resolvedResult(PortalKind.vendorSuperAdmin);
      bloc.add(const SessionContextRequested());
      await _settle();
      expect(bloc.state, isA<SessionResolving>());
      expect(portal.pendingCount, 1);

      auth.emitSignedOut();
      await _settle();
      expect(bloc.state, isA<SessionUnauthenticated>());

      portal.completeNext(); // stale retry completes
      await _settle();

      expect(bloc.state, isA<SessionUnauthenticated>());
      expect(sawActive(), isFalse);
    });

    test(
      'a user switch while a retry is pending drops the old result',
      () async {
        start(userA, result: unavailableResult);

        bloc.add(const SessionStarted());
        await _settle();
        portal.completeNext(unavailableResult);
        await _settle();
        expect(bloc.state, isA<SessionUnavailable>());

        bloc.add(const SessionContextRequested());
        await _settle();
        expect(portal.pendingCount, 1);

        auth.emitSignedIn(userB);
        await _settle();

        portal.completeNext(
          resolvedResult(PortalKind.vendorSuperAdmin),
        ); // stale A
        await _settle();
        expect(sawActive(), isFalse);

        portal.completeNext(resolvedResult(PortalKind.retailerOwner)); // B
        await _settle();
        expect(
          (bloc.state as SessionActive).portalKind,
          PortalKind.retailerOwner,
        );
      },
    );

    test('repeated retry taps create at most one applicable request', () async {
      start(userA, result: unavailableResult);

      bloc.add(const SessionStarted());
      await _settle();
      portal.completeNext(unavailableResult);
      await _settle();
      expect(bloc.state, isA<SessionUnavailable>());
      final int before = portal.resolveCallCount;

      bloc
        ..add(const SessionContextRequested())
        ..add(const SessionContextRequested())
        ..add(const SessionContextRequested());
      await _settle();

      expect(
        portal.resolveCallCount - before,
        1,
        reason: 'one RPC call despite three taps',
      );
      expect(portal.pendingCount, 1);

      portal.completeNext(resolvedResult(PortalKind.salesStaff));
      await _settle();
      expect(bloc.state, isA<SessionActive>());
    });

    test(
      'token refresh during resolution creates no stale or duplicate state',
      () async {
        start(userA, result: resolvedResult(PortalKind.retailerManager));

        bloc.add(const SessionStarted());
        await _settle();
        expect(portal.pendingCount, 1);

        auth.emitTokenRefreshed(userA); // same user, mid-flight
        await _settle();
        expect(portal.pendingCount, 1, reason: 'no second resolution started');
        expect(portal.resolveCallCount, 1);

        portal.completeNext();
        await _settle();

        expect(bloc.state, isA<SessionActive>());
        expect(states.whereType<SessionResolving>().length, 1);
        expect(states.whereType<SessionActive>().length, 1);
      },
    );
  });
}
