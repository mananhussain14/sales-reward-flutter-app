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
