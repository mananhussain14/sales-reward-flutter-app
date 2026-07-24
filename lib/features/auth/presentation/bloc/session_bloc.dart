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
/// ## Why a request-generation state machine, not a boolean
///
/// Portal resolution is asynchronous, and authentication can change *while a
/// resolution is in flight*. A shared `_resolving` flag cannot make that safe:
/// it both drops a legitimately new resolution (a user switch mid-flight) and
/// fails to stop a stale one from committing (an older RPC completing after a
/// newer sign-out already emitted). The commit point is where correctness lives,
/// so that is where it is enforced.
///
/// Every resolution carries two facts captured at the moment it starts: a
/// monotonic [_generation] and the [_currentUserId] that owns it. Any newer
/// intent — a sign-out, a user switch, a fresh retry — bumps [_generation] and
/// updates [_currentUserId]. When a resolution finally settles it arrives back
/// as an internal [_SessionResolutionSettled] event, and its result is committed
/// **only if it is still the current generation and still belongs to the
/// currently authenticated user**. Anything else is silently dropped. The RPC
/// cannot be un-called, but its result can be — and is — discarded.
///
/// ## Why the handlers are synchronous
///
/// No handler `await`s the RPC. Each handler mutates state and, where a
/// resolution is needed, kicks off `resolve()` as a fire-and-forget future that
/// re-enters the bloc as [_SessionResolutionSettled]. Because the handlers never
/// suspend, two events can never interleave their state transitions — which is
/// the interleaving the reviewer found. The generation check is the safety net;
/// the synchronous handlers are the mechanism that makes ordering deterministic.
///
/// ## The invariants, all enforced here
///
/// 1. A result commits only for the user that initiated it (generation + owner).
/// 2. Sign-out during a resolution ends in [SessionUnauthenticated]; the old
///    result never reactivates a shell.
/// 3. A→B switch mid-flight discards A immediately, never emits A's result,
///    resolves B once, and finishes with B.
/// 4. A retry superseded by sign-out does not emit its result.
/// 5. A retry superseded by a different user does not emit the old result.
/// 6. Duplicate events for the same user are deduplicated.
/// 7. A token refresh for the same user changes nothing.
/// 8. No authenticated shell flashes after logout or during a user change.
///
/// ## What it is not
///
/// It is not an authorization service. It produces a hint about which shell to
/// build. Supabase remains the only authority on what the caller may do.
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
    on<_SessionResolutionSettled>(_onResolutionSettled);
  }

  final AuthRepository _auth;
  final PortalContextRepository _portalContext;

  StreamSubscription<AuthChange>? _authSubscription;

  /// Bumped on every new intent. A resolution may only commit at the generation
  /// that started it, so any newer intent invalidates an in-flight resolution.
  int _generation = 0;

  /// The user the current state and any in-flight resolution belong to. Null
  /// when signed out.
  String? _currentUserId;

  /// The generation of the resolution currently in flight, or null when none is
  /// pending. Used only to deduplicate redundant same-user requests; it is
  /// never the thing that authorizes a commit.
  int? _inFlightGeneration;

  void _onStarted(SessionStarted event, Emitter<SessionState> emit) {
    _authSubscription ??= _auth.changes.listen(
      (AuthChange change) => add(SessionAuthChanged(change)),
    );

    // Evaluate the restored session directly rather than waiting for the
    // stream's replayed `initialSession`, which would race startup. The dedupe
    // below makes the two paths idempotent.
    final AuthUser? user = _auth.currentUser;
    if (user == null) {
      _goUnauthenticated(emit);
      return;
    }
    _beginResolution(user.id, emit);
  }

  void _onContextRequested(
    SessionContextRequested event,
    Emitter<SessionState> emit,
  ) {
    // Retry step 1: a session must still exist. A user whose token expired
    // while the failure screen was up belongs on the login screen, not in
    // another doomed RPC call.
    final AuthUser? user = _auth.currentUser;
    if (user == null) {
      _goUnauthenticated(emit);
      return;
    }
    _beginResolution(user.id, emit);
  }

  void _onAuthChanged(SessionAuthChanged event, Emitter<SessionState> emit) {
    switch (event.change) {
      case AuthSignedOut():
        _goUnauthenticated(emit);

      case AuthSignedIn(:final AuthUser user):
        final bool sameUser = user.id == _currentUserId;
        if (sameUser && !state.isIndeterminate) {
          // Rule 6: a duplicate event for the person already settled. Ignoring
          // it stops a router rebuild or a replayed session from re-resolving.
          return;
        }
        _beginResolution(user.id, emit);

      case AuthTokenRefreshed(:final AuthUser user):
        // Rule 7: the same person with a fresh token needs nothing at all.
        if (user.id == _currentUserId) {
          return;
        }
        // A refresh naming a different person is not something GoTrue should
        // produce; treat it as a user change rather than trusting it.
        _beginResolution(user.id, emit);
    }
  }

  /// Commits a settled resolution, but only if it is still current.
  void _onResolutionSettled(
    _SessionResolutionSettled event,
    Emitter<SessionState> emit,
  ) {
    // The three-part ownership check that is the whole point of this rewrite.
    final bool superseded = event.generation != _generation;
    final bool wrongOwner = event.userId != _currentUserId;
    final bool userChangedUnderneath = _auth.currentUser?.id != event.userId;
    if (superseded || wrongOwner || userChangedUnderneath) {
      return;
    }

    _inFlightGeneration = null;
    emit(switch (event.result) {
      PortalContextResolved(:final PortalContext context) => SessionActive(
        context,
      ),
      PortalContextDenied() => const SessionDenied(),
      PortalContextFailed(:final Failure failure) => SessionUnavailable(
        failure,
      ),
    });
  }

  /// Moves to the signed-out state, invalidating any in-flight resolution.
  void _goUnauthenticated(Emitter<SessionState> emit) {
    _generation++;
    _inFlightGeneration = null;
    _currentUserId = null;
    emit(const SessionUnauthenticated());
  }

  /// Starts (or declines to restart) a resolution for [userId].
  ///
  /// Synchronous: it sets up the new generation, emits the interim state, and
  /// fires the RPC without awaiting it. The result returns as
  /// [_SessionResolutionSettled].
  void _beginResolution(String userId, Emitter<SessionState> emit) {
    final bool isUserChange =
        _currentUserId != null && userId != _currentUserId;

    // Rule 6 (in-flight edition): a redundant request for the SAME user while
    // one is already pending is dropped, so repeated retries and replayed
    // sign-ins produce at most one applicable request. A user *change* is never
    // dropped — it must supersede.
    if (!isUserChange &&
        _inFlightGeneration != null &&
        userId == _currentUserId) {
      return;
    }

    if (isUserChange) {
      // Rules 3 & 8: discard the previous user's visible context immediately,
      // before the new resolution even begins.
      emit(const SessionInitial());
    }

    final int generation = ++_generation;
    _currentUserId = userId;
    _inFlightGeneration = generation;

    emit(const SessionResolving());

    // Fire and forget. The generation and owner are captured here and validated
    // at the commit point; the future is never awaited inside a handler.
    _portalContext
        .resolve()
        .then((PortalContextResult result) {
          if (isClosed) {
            return;
          }
          add(
            _SessionResolutionSettled(
              generation: generation,
              userId: userId,
              result: result,
            ),
          );
        })
        .catchError((Object _) {
          // The repository is contractually non-throwing, so this is pure
          // defence: a thrown resolve() becomes an operational failure, never a
          // role and never a swallowed error.
          if (isClosed) {
            return;
          }
          add(
            _SessionResolutionSettled(
              generation: generation,
              userId: userId,
              result: const PortalContextFailed(UnavailableFailure()),
            ),
          );
        });
  }

  @override
  Future<void> close() {
    _authSubscription?.cancel();
    return super.close();
  }
}
