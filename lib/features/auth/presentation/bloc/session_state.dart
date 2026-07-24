part of 'session_bloc.dart';

/// States emitted by [SessionBloc].
///
/// Six states, not "context or null". Collapsing "still booting", "nobody is
/// signed in", "asking the backend", "the backend said no" and "the backend
/// could not be reached" into one falsy value is exactly the mistake the web
/// layer avoids: an outage must never render as an access denial, and a denial
/// must never render as an outage.
sealed class SessionState extends Equatable {
  const SessionState();

  /// The resolved context, or null. Only [SessionActive] has one.
  ///
  /// Used by the router to decide which shell to build. It is never used to
  /// decide whether an operation is allowed.
  PortalContext? get context => null;

  /// Whether the answer is still unknown.
  ///
  /// The router sends every role route back to the gate while this is true,
  /// which is what prevents a shell from flashing before resolution finishes.
  bool get isIndeterminate =>
      this is SessionInitial || this is SessionResolving;

  @override
  List<Object?> get props => const <Object?>[];
}

/// Booting, or deliberately cleared because the signed-in person changed.
final class SessionInitial extends SessionState {
  const SessionInitial();
}

/// No session. The login screen is the only reachable destination.
final class SessionUnauthenticated extends SessionState {
  const SessionUnauthenticated();
}

/// A session exists and the portal context is being read.
final class SessionResolving extends SessionState {
  const SessionResolving();
}

/// A context was resolved. [context] carries the routing decision and, where
/// the backend supplied them, the organization blocks and capability hints.
final class SessionActive extends SessionState {
  const SessionActive(this.portalContext);

  final PortalContext portalContext;

  @override
  PortalContext get context => portalContext;

  /// The experience to open.
  PortalKind get portalKind => portalContext.portalKind;

  @override
  List<Object?> get props => <Object?>[portalContext];
}

/// The backend answered `portal_kind: NONE`.
///
/// A **decision**, not a failure. There is nothing to retry: the same call would
/// return the same answer. The destination is the shared access-denied screen,
/// whose only affordance is sign-out.
final class SessionDenied extends SessionState {
  const SessionDenied();
}

/// The context could not be read: transport failure, or a body this build does
/// not understand.
///
/// **Operational, never a denial.** The session is intact and the user is
/// offered a retry. [failure] is a discriminant — it never carries the
/// backend's own message.
final class SessionUnavailable extends SessionState {
  const SessionUnavailable(this.failure);

  final Failure failure;

  @override
  List<Object?> get props => <Object?>[failure];
}
