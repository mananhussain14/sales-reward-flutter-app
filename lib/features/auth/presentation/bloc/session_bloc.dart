import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/failure.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/entities/portal_context.dart';
import '../../domain/entities/portal_kind.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/portal_context_repository.dart';

part 'session_event.dart';
part 'session_state.dart';

/// The session coordinator: the single owner of "is anyone signed in, and which
/// experience are they in?".
///
/// It is the only place that joins authentication to portal resolution, which is
/// what lets the four rules below be stated once and tested once instead of
/// being scattered across the router, the login screen and four shells.
///
/// ## The four rules
///
/// 1. **Never resolve without a session.** `get_my_portal_context()` is granted
///    to `authenticated` and revoked from `anon`, so calling it signed-out
///    yields a transport refusal that would be misreported as "unavailable".
///    The coordinator checks for a session first, every time, including on retry.
///
/// 2. **A token refresh changes nothing.** GoTrue emits `tokenRefreshed`
///    roughly hourly. It is neither a sign-in nor a sign-out, so it is ignored
///    outright — no re-resolution, no state change, and above all no bounce to
///    the login screen.
///
/// 3. **A different user discards the previous context first.** When the
///    signed-in id changes, the old context is cleared *before* the new one is
///    requested, so there is no window in which one person's shell is rendered
///    against another person's session.
///
/// 4. **One resolution at a time.** Duplicate auth events and repeated retry
///    taps are collapsed, so router rebuilds and impatient users cannot produce
///    two concurrent RPC calls.
///
/// ## What it is not
///
/// It is not an authorization service. It produces a hint about which shell to
/// build. Supabase remains the only authority on what the caller may do, and
/// re-decides on every call regardless of what this BLoC last emitted.
class SessionBloc extends Bloc<SessionEvent, SessionState> {
  SessionBloc({
    required AuthRepository authRepository,
    required PortalContextRepository portalContextRepository,
  }) : _auth = authRepository,
       _portalContext = portalContextRepository,
       super(const SessionInitial()) {
    on<SessionStarted>(_onStarted);
    on<SessionContextRequested>(_onContextRequested);
    on<SessionAuthChanged>(_onAuthChanged);
  }

  final AuthRepository _auth;
  final PortalContextRepository _portalContext;

  StreamSubscription<AuthChange>? _authSubscription;

  /// The user the current state belongs to, so a change of person can be
  /// distinguished from a change of token.
  String? _userId;

  /// Rule 4. Set for the whole duration of a resolution, including its await.
  bool _resolving = false;

  Future<void> _onStarted(
    SessionStarted event,
    Emitter<SessionState> emit,
  ) async {
    _authSubscription ??= _auth.changes.listen(
      (AuthChange change) => add(SessionAuthChanged(change)),
    );

    // Evaluate the restored session directly rather than waiting for the
    // stream. `onAuthStateChange` replays `initialSession` to its first
    // listener, but relying on that alone would leave startup racing against
    // restoration — and a missed event would strand the app on a blank gate.
    // The dedupe in _onAuthChanged makes the two paths idempotent.
    final AuthUser? user = _auth.currentUser;
    if (user == null) {
      _userId = null;
      emit(const SessionUnauthenticated());
      return;
    }

    _userId = user.id;
    await _resolve(emit);
  }

  Future<void> _onContextRequested(
    SessionContextRequested event,
    Emitter<SessionState> emit,
  ) async {
    // Retry step 1: a session must still exist. A user whose token expired
    // while the failure screen was on display belongs on the login screen, not
    // in another doomed RPC call.
    final AuthUser? user = _auth.currentUser;
    if (user == null) {
      _userId = null;
      emit(const SessionUnauthenticated());
      return;
    }

    _userId = user.id;
    await _resolve(emit);
  }

  Future<void> _onAuthChanged(
    SessionAuthChanged event,
    Emitter<SessionState> emit,
  ) async {
    switch (event.change) {
      case AuthSignedOut():
        _userId = null;
        // Rule 3, sign-out edition: the context goes before the screen does.
        emit(const SessionUnauthenticated());

      case AuthSignedIn(:final AuthUser user):
        final String? previousUserId = _userId;
        final bool sameUser = user.id == previousUserId;
        if (sameUser && !_isIndeterminate) {
          // A duplicate event for the person already resolved. Ignoring it is
          // what stops a router rebuild from triggering a second RPC.
          return;
        }
        if (previousUserId != null && previousUserId != user.id) {
          // Rule 3: a genuine switch of person. Discard the previous context
          // before asking for the new one, so nothing downstream can read a
          // stale pairing. (There is nothing to clear when arriving from a
          // signed-out state, so no spurious clear is emitted then.)
          emit(const SessionInitial());
        }
        _userId = user.id;
        await _resolve(emit);

      case AuthTokenRefreshed(:final AuthUser user):
        // Rule 2. The same person with a fresh token needs nothing at all.
        if (user.id == _userId) {
          return;
        }
        // A refresh that names a different person is not something GoTrue
        // should produce; treat it as a user change rather than trusting it.
        _userId = user.id;
        emit(const SessionInitial());
        await _resolve(emit);
    }
  }

  /// True while the session has no settled answer, so a repeat sign-in event
  /// for the same user is worth acting on rather than ignoring.
  bool get _isIndeterminate =>
      state is SessionInitial || state is SessionUnauthenticated;

  Future<void> _resolve(Emitter<SessionState> emit) async {
    if (_resolving) {
      return;
    }
    _resolving = true;
    try {
      emit(const SessionResolving());

      final PortalContextResult result = await _portalContext.resolve();
      if (emit.isDone) {
        return;
      }

      emit(switch (result) {
        PortalContextResolved(:final PortalContext context) => SessionActive(
          context,
        ),
        PortalContextDenied() => const SessionDenied(),
        PortalContextFailed(:final Failure failure) => SessionUnavailable(
          failure,
        ),
      });
    } finally {
      _resolving = false;
    }
  }

  @override
  Future<void> close() {
    _authSubscription?.cancel();
    return super.close();
  }
}
