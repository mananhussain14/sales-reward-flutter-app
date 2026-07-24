import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/auth/domain/entities/auth_user.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/auth/domain/repositories/portal_context_repository.dart';
import 'package:sale_reward/features/auth/presentation/bloc/session_bloc.dart';

import '../../support/fakes.dart';

void main() {
  late FakeAuthRepository auth;
  late FakePortalContextRepository portal;

  tearDown(() => auth.dispose());

  SessionBloc build({
    AuthUser? user,
    required PortalContextResult portalResult,
  }) {
    auth = FakeAuthRepository(initialUser: user);
    portal = FakePortalContextRepository(portalResult);
    return SessionBloc(authRepository: auth, portalContextRepository: portal);
  }

  group('startup', () {
    blocTest<SessionBloc, SessionState>(
      'with no session goes unauthenticated, without calling the RPC',
      build: () => build(portalResult: deniedResult),
      act: (SessionBloc bloc) => bloc.add(const SessionStarted()),
      expect: () => <Matcher>[isA<SessionUnauthenticated>()],
      verify: (_) => expect(
        portal.resolveCallCount,
        0,
        reason: 'no session means no authenticated RPC call',
      ),
    );

    blocTest<SessionBloc, SessionState>(
      'with a restored session resolves the context',
      build: () => build(
        user: testUser,
        portalResult: resolvedResult(PortalKind.retailerOwner),
      ),
      act: (SessionBloc bloc) => bloc.add(const SessionStarted()),
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
      'a NONE answer becomes denied, not a failure',
      build: () => build(user: testUser, portalResult: deniedResult),
      act: (SessionBloc bloc) => bloc.add(const SessionStarted()),
      skip: 1,
      expect: () => <Matcher>[isA<SessionDenied>()],
    );

    blocTest<SessionBloc, SessionState>(
      'a resolve failure becomes unavailable, not denied',
      build: () => build(user: testUser, portalResult: unavailableResult),
      act: (SessionBloc bloc) => bloc.add(const SessionStarted()),
      skip: 1,
      expect: () => <Matcher>[isA<SessionUnavailable>()],
    );
  });

  group('sign-in', () {
    blocTest<SessionBloc, SessionState>(
      'resolves the context when a sign-in arrives on the stream',
      build: () => build(portalResult: resolvedResult(PortalKind.salesStaff)),
      act: (SessionBloc bloc) async {
        bloc.add(const SessionStarted());
        await Future<void>.delayed(Duration.zero);
        auth.emitSignedIn(testUser);
      },
      expect: () => <Matcher>[
        isA<SessionUnauthenticated>(),
        isA<SessionResolving>(),
        isA<SessionActive>().having(
          (SessionActive s) => s.portalKind,
          'portalKind',
          PortalKind.salesStaff,
        ),
      ],
    );
  });

  group('sign-out', () {
    blocTest<SessionBloc, SessionState>(
      'clears the context and goes unauthenticated',
      build: () => build(
        user: testUser,
        portalResult: resolvedResult(PortalKind.vendorSuperAdmin),
      ),
      act: (SessionBloc bloc) async {
        bloc.add(const SessionStarted());
        await Future<void>.delayed(Duration.zero);
        auth.emitSignedOut();
      },
      expect: () => <Matcher>[
        isA<SessionResolving>(),
        isA<SessionActive>(),
        isA<SessionUnauthenticated>(),
      ],
    );
  });

  group('token refresh', () {
    blocTest<SessionBloc, SessionState>(
      'for the same user changes nothing — no re-resolve, no logout',
      build: () => build(
        user: testUser,
        portalResult: resolvedResult(PortalKind.retailerManager),
      ),
      act: (SessionBloc bloc) async {
        bloc.add(const SessionStarted());
        await Future<void>.delayed(Duration.zero);
        auth.emitTokenRefreshed(testUser);
        await Future<void>.delayed(Duration.zero);
      },
      expect: () => <Matcher>[isA<SessionResolving>(), isA<SessionActive>()],
      verify: (_) => expect(
        portal.resolveCallCount,
        1,
        reason: 'a refresh must not trigger a second resolution',
      ),
    );
  });

  group('user change', () {
    blocTest<SessionBloc, SessionState>(
      'discards the previous context before resolving the new user',
      build: () => build(
        user: testUser,
        portalResult: resolvedResult(PortalKind.retailerOwner),
      ),
      act: (SessionBloc bloc) async {
        bloc.add(const SessionStarted());
        await Future<void>.delayed(Duration.zero);
        auth.emitSignedIn(const AuthUser(id: 'user-2', email: 'b@example.com'));
        await Future<void>.delayed(Duration.zero);
      },
      expect: () => <Matcher>[
        isA<SessionResolving>(),
        isA<SessionActive>(),
        // The clear happens before the new resolve begins.
        isA<SessionInitial>(),
        isA<SessionResolving>(),
        isA<SessionActive>(),
      ],
    );

    blocTest<SessionBloc, SessionState>(
      'a duplicate sign-in for the same resolved user is ignored',
      build: () => build(
        user: testUser,
        portalResult: resolvedResult(PortalKind.salesStaff),
      ),
      act: (SessionBloc bloc) async {
        bloc.add(const SessionStarted());
        await Future<void>.delayed(Duration.zero);
        auth.emitSignedIn(testUser);
        await Future<void>.delayed(Duration.zero);
      },
      // Only the startup resolve; the duplicate produces no further states.
      expect: () => <Matcher>[isA<SessionResolving>(), isA<SessionActive>()],
    );
  });

  group('retry', () {
    blocTest<SessionBloc, SessionState>(
      're-resolves after a failure and can then succeed',
      build: () => build(user: testUser, portalResult: unavailableResult),
      act: (SessionBloc bloc) async {
        bloc.add(const SessionStarted());
        await Future<void>.delayed(Duration.zero);
        // The failure screen's retry, now with a good answer scripted.
        portal.result = resolvedResult(PortalKind.retailerOwner);
        bloc.add(const SessionContextRequested());
        await Future<void>.delayed(Duration.zero);
      },
      expect: () => <Matcher>[
        isA<SessionResolving>(),
        isA<SessionUnavailable>(),
        isA<SessionResolving>(),
        isA<SessionActive>(),
      ],
    );

    blocTest<SessionBloc, SessionState>(
      'a retry after the session expired goes to login, not another RPC call',
      build: () => build(user: testUser, portalResult: unavailableResult),
      act: (SessionBloc bloc) async {
        bloc.add(const SessionStarted());
        await Future<void>.delayed(Duration.zero);
        // The token lapsed while the failure screen was up.
        auth.emitSignedOut();
        await Future<void>.delayed(Duration.zero);
        bloc.add(const SessionContextRequested());
        await Future<void>.delayed(Duration.zero);
      },
      expect: () => <Matcher>[
        isA<SessionResolving>(),
        isA<SessionUnavailable>(),
        isA<SessionUnauthenticated>(),
      ],
      verify: (_) => expect(
        portal.resolveCallCount,
        1,
        reason: 'retry without a session must not call the RPC',
      ),
    );
  });
}
