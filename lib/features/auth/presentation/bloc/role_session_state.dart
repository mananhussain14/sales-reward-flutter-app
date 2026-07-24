part of 'role_session_bloc.dart';

/// States emitted by [RoleSessionBloc].
///
/// The union is deliberately six-way rather than "role or null". Collapsing
/// "resolving", "no role", "refused" and "could not reach the backend" into one
/// falsy value is exactly the mistake the web layer avoids: an outage must never
/// render as an access denial, and a denial must never render as an outage.
sealed class RoleSessionState extends Equatable {
  const RoleSessionState();

  /// The role in effect, or null. Only [RoleSessionActive] has one.
  ///
  /// Used by the router to decide which shell to build. It is never used to
  /// decide whether an operation is allowed.
  ResolvedRole? get resolved => null;

  @override
  List<Object?> get props => const <Object?>[];
}

/// Nothing has been asked yet.
final class RoleSessionInitial extends RoleSessionState {
  const RoleSessionInitial();
}

/// A resolution is in flight.
final class RoleSessionResolving extends RoleSessionState {
  const RoleSessionResolving();
}

/// A role is in effect. Check [ResolvedRole.trust] before treating it as having
/// come from the backend.
final class RoleSessionActive extends RoleSessionState {
  const RoleSessionActive(this.role);

  final ResolvedRole role;

  @override
  ResolvedRole get resolved => role;

  @override
  List<Object?> get props => <Object?>[role];
}

/// The caller has a verified identity but qualifies for no supported
/// experience — the backend answered `kind = 'none'`.
///
/// The shell for this state is the shared access-denied screen.
final class RoleSessionNoAccess extends RoleSessionState {
  const RoleSessionNoAccess();
}

/// The resolution failed. [failure] distinguishes an outage from a denial from
/// an unimplemented backend capability; the UI must not flatten them.
final class RoleSessionFailed extends RoleSessionState {
  const RoleSessionFailed(this.failure);

  final Failure failure;

  /// True while the backend capability itself is missing — the state this
  /// milestone actually ships in.
  bool get isUnimplemented => failure is NotImplementedFailure;

  @override
  List<Object?> get props => <Object?>[failure];
}
