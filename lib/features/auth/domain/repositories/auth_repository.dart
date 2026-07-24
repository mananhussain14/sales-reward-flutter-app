import '../../../../core/errors/failure.dart';
import '../entities/auth_user.dart';

/// The outcome of a sign-in attempt.
sealed class SignInResult {
  const SignInResult();
}

/// A session now exists. The session coordinator will hear about it on the auth
/// stream and resolve the portal context; the caller does not route itself.
final class SignInSucceeded extends SignInResult {
  const SignInSucceeded();
}

/// The credentials were rejected.
///
/// Deliberately carries **no detail**. The backend must never reveal whether an
/// address exists, so the message shown for this case is fixed, generic, and
/// identical for a wrong password and an unknown account.
final class SignInRejected extends SignInResult {
  const SignInRejected();
}

/// Sign-in could not be attempted or completed — offline, timeout, the auth
/// service is unreachable. **Not** a credential rejection, and never presented
/// as one.
final class SignInFailed extends SignInResult {
  const SignInFailed(this.failure);

  final Failure failure;
}

/// The outcome of a sign-out attempt.
sealed class SignOutResult {
  const SignOutResult();
}

final class SignOutSucceeded extends SignOutResult {
  const SignOutSucceeded();
}

/// Sign-out did not complete. The caller must surface this rather than
/// pretending the user is signed out — leaving a stale shell on screen after a
/// failed sign-out is worse than saying it failed.
final class SignOutFailed extends SignOutResult {
  const SignOutFailed(this.failure);

  final Failure failure;
}

/// Authentication, expressed without a single Supabase type.
///
/// Everything above the data layer talks to this. The presentation layer never
/// touches `Supabase.instance.client`, which is what keeps "how we authenticate"
/// a swappable detail and makes the whole flow testable with a plain fake.
abstract interface class AuthRepository {
  /// The signed-in user, or null. Read once at startup to decide between the
  /// login screen and resolving a portal context.
  AuthUser? get currentUser;

  /// Authentication changes, in domain terms.
  ///
  /// Emits the restored session at startup if one exists, so a subscriber does
  /// not have to poll [currentUser] and race with restoration.
  Stream<AuthChange> get changes;

  Future<SignInResult> signInWithPassword({
    required String email,
    required String password,
  });

  /// Signs out **locally**, matching the web's `scope: 'local'`, so other
  /// sessions belonging to the same person survive.
  Future<SignOutResult> signOut();
}
