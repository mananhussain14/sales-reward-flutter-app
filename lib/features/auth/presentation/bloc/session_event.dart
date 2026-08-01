part of 'session_bloc.dart';

/// Events accepted by [SessionBloc].
sealed class SessionEvent extends Equatable {
  const SessionEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

/// Begin coordinating: subscribe to authentication changes and evaluate any
/// restored session. Dispatched once, by the application root.
final class SessionStarted extends SessionEvent {
  const SessionStarted();
}

/// Ask the backend for the portal context again.
///
/// The retry action on the unavailable screen. It re-checks for a session
/// first — a retry is not a reason to call an authenticated RPC without one.
final class SessionContextRequested extends SessionEvent {
  const SessionContextRequested();
}

/// Silently re-check the current portal context.
///
/// Used when the application returns to the foreground. An already active shell
/// remains mounted while the backend is checked, so an unchanged result does
/// not discard page state, scroll position, or loaded feature data.
final class SessionContextRevalidationRequested extends SessionEvent {
  const SessionContextRevalidationRequested();
}

/// Authentication changed underneath us.
///
/// Dispatched by [SessionBloc]'s own subscription rather than by a widget, so
/// the stream and the state machine cannot get out of step.
final class SessionAuthChanged extends SessionEvent {
  const SessionAuthChanged(this.change);

  final AuthChange change;

  @override
  List<Object?> get props => <Object?>[change];
}

/// An in-flight resolution has finished — internal only.
///
/// Feeding the RPC result back as an event, rather than committing it from
/// inside the handler that awaited it, is what lets the commit be validated
/// against the *current* generation and user. It carries the [generation] and
/// [userId] captured when the resolution started; [SessionBloc] commits the
/// [result] only if both are still current. It is never added by anything
/// outside the bloc.
final class _SessionResolutionSettled extends SessionEvent {
  const _SessionResolutionSettled({
    required this.generation,
    required this.userId,
    required this.result,
  });

  final int generation;
  final String userId;
  final PortalContextResult result;

  @override
  List<Object?> get props => <Object?>[generation, userId, result];
}
