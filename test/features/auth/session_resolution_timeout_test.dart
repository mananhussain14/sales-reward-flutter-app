import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/auth/data/datasources/portal_context_data_source.dart';
import 'package:sale_reward/features/auth/data/repositories/supabase_portal_context_repository.dart';
import 'package:sale_reward/features/auth/domain/entities/auth_user.dart';
import 'package:sale_reward/features/auth/domain/repositories/portal_context_repository.dart';
import 'package:sale_reward/features/auth/presentation/bloc/session_bloc.dart';

import '../../support/fakes.dart';

/// Startup must not be able to wait forever.
///
/// `SessionBloc` emits [SessionResolving] and then hands off to
/// `PortalContextRepository.resolve()`, and the router holds the splash for as
/// long as the session is indeterminate. The RPC behind that call had no
/// timeout, so a request that connected and then went quiet — a stalled mobile
/// handover, a proxy that swallows a connection — produced a splash screen with
/// no error, no retry and no end. Indistinguishable, to a user, from a crash.
///
/// This suite pins both halves: the repository gives up, and the bloc leaves the
/// indeterminate state when it does.
void main() {
  group('the portal-context RPC gives up', () {
    test('a call that never answers becomes an operational failure', () async {
      final SupabasePortalContextRepository repository =
          SupabasePortalContextRepository(
            // Never completes: the exact shape of a socket that connected and
            // then went silent.
            PortalContextDataSource(() => Completer<Object?>().future),
            timeout: const Duration(milliseconds: 50),
          );

      final PortalContextResult result = await repository.resolve();

      // Operational, so the user keeps their session and is offered a retry.
      // Emphatically not a denial — a stalled network is not an authorization
      // answer, and must never send anyone to access-denied.
      expect(result, isA<PortalContextFailed>());
      expect(result, isNot(isA<PortalContextDenied>()));
    });

    test('a timeout does not outlive its budget', () async {
      final Stopwatch clock = Stopwatch()..start();

      await SupabasePortalContextRepository(
        PortalContextDataSource(() => Completer<Object?>().future),
        timeout: const Duration(milliseconds: 50),
      ).resolve();

      clock.stop();
      expect(clock.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('the shipped budget is finite', () {
      expect(portalContextTimeout, lessThan(const Duration(minutes: 1)));
      expect(portalContextTimeout, greaterThan(Duration.zero));
    });
  });

  group('the session never stays unresolved', () {
    late FakeAuthRepository auth;

    setUp(
      () => auth = FakeAuthRepository(
        initialUser: const AuthUser(id: 'user-1', email: 'a@b.com'),
      ),
    );
    tearDown(() => auth.dispose());

    blocTest<SessionBloc, SessionState>(
      'a signed-in start whose resolution fails settles out of the splash',
      build: () => SessionBloc(
        authRepository: auth,
        portalContextRepository: _TimingOutPortalContextRepository(),
      ),
      act: (SessionBloc bloc) => bloc.add(const SessionStarted()),
      wait: const Duration(milliseconds: 200),
      verify: (SessionBloc bloc) {
        // The one assertion that matters: whatever it settled on, it is no
        // longer indeterminate, so the router can leave the splash.
        expect(
          bloc.state.isIndeterminate,
          isFalse,
          reason:
              'a resolution that never answers must still end the splash, or '
              'startup hangs with nothing on screen to explain it',
        );
        expect(bloc.state, isA<SessionUnavailable>());
      },
    );

    blocTest<SessionBloc, SessionState>(
      'the interim resolving state is still emitted on the way through',
      build: () => SessionBloc(
        authRepository: auth,
        portalContextRepository: _TimingOutPortalContextRepository(),
      ),
      act: (SessionBloc bloc) => bloc.add(const SessionStarted()),
      wait: const Duration(milliseconds: 200),
      expect: () => <Matcher>[
        isA<SessionResolving>(),
        isA<SessionUnavailable>(),
      ],
    );
  });
}

/// A repository whose real RPC would hang, standing in for the timed-out call.
final class _TimingOutPortalContextRepository
    implements PortalContextRepository {
  @override
  Future<PortalContextResult> resolve() => SupabasePortalContextRepository(
    PortalContextDataSource(() => Completer<Object?>().future),
    timeout: const Duration(milliseconds: 20),
  ).resolve();
}
