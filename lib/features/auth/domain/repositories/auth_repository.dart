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

/// The credentials were correct, but the address has not been confirmed.
///
/// Distinct from [SignInRejected] because the two need different actions from
/// the user: one is "check what you typed", the other is "check your inbox".
/// This is not the account-enumeration oracle [SignInRejected] guards against —
/// reaching this outcome already requires knowing the correct password.
final class SignInUnconfirmed extends SignInResult {
  const SignInUnconfirmed();
}

/// Too many attempts in too short a window. Not a rejection: the credentials
/// were never evaluated.
final class SignInThrottled extends SignInResult {
  const SignInThrottled();
}

/// Sign-in could not be attempted or completed. **Not** a credential rejection,
/// and never presented as one.
final class SignInFailed extends SignInResult {
  const SignInFailed(this.reason);

  final SignInFailureReason reason;
}

/// Why a sign-in could not be completed.
///
/// The point of the distinction is that "we could not reach the service" and
/// "the service refused this build" and "something in our own code broke" are
/// three different problems with three different remedies, and telling a user
/// to check their connection when the connection is fine sends them to fix
/// something that was never broken.
enum SignInFailureReason {
  /// The request never reached the auth service: no route, no DNS answer, a
  /// refused TLS handshake, a blocked socket, a browser CORS refusal.
  network,

  /// The request was sent but nothing came back in time.
  timeout,

  /// The auth service answered, and the answer was its own failure (5xx).
  serviceUnavailable,

  /// The request was refused before any account was consulted — the shape of an
  /// absent, malformed or revoked publishable key, or a URL addressing a
  /// different project. A packaging fault, never the user's.
  configuration,

  /// Anything else: a malformed response, an unexpected SDK state, a
  /// programming error.
  unexpected,
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
