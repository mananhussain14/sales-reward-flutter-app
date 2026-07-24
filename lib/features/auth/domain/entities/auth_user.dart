import 'package:equatable/equatable.dart';

/// The authenticated caller, as far as the application is allowed to know.
///
/// Deliberately minimal. It carries an id — used **only** to notice that the
/// signed-in person changed, so the previous person's portal context can be
/// discarded — and an email, used only to caption the account sheet.
///
/// It carries **no role, no organization, no permission and no token**. None of
/// those may be read from a session: the backend derives them from `auth.uid()`
/// and returns them through one authenticated call.
final class AuthUser extends Equatable {
  const AuthUser({required this.id, this.email});

  final String id;
  final String? email;

  @override
  List<Object?> get props => <Object?>[id, email];
}

/// A change in authentication state, expressed in domain terms.
///
/// The data layer translates GoTrue's events into these so nothing above it
/// imports a Supabase type or has to know which of GoTrue's dozen event names
/// mean "the user changed" versus "the same user got a fresh token".
sealed class AuthChange extends Equatable {
  const AuthChange();

  @override
  List<Object?> get props => const <Object?>[];
}

/// A session now exists for [user].
///
/// Emitted on sign-in and on restoring a persisted session at startup.
final class AuthSignedIn extends AuthChange {
  const AuthSignedIn(this.user);

  final AuthUser user;

  @override
  List<Object?> get props => <Object?>[user];
}

/// There is no session.
final class AuthSignedOut extends AuthChange {
  const AuthSignedOut();
}

/// The same user's access token was renewed.
///
/// **This is not a sign-in and not a sign-out.** Treating it as either is the
/// classic bug that bounces a working session back to the login screen every
/// hour, so it is a distinct case here and the session coordinator ignores it.
final class AuthTokenRefreshed extends AuthChange {
  const AuthTokenRefreshed(this.user);

  final AuthUser user;

  @override
  List<Object?> get props => <Object?>[user];
}
