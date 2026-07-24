import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../../core/errors/failure.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/repositories/auth_repository.dart';

/// The Supabase-backed [AuthRepository].
///
/// The only file above the SDK that knows GoTrue exists. It translates GoTrue's
/// event vocabulary into the three domain changes the rest of the app reasons
/// about, and nothing else leaks upward — no `Session`, no `User`, no
/// `AuthChangeEvent`, no access token.
final class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._auth);

  final sb.GoTrueClient _auth;

  @override
  AuthUser? get currentUser => _toUser(_auth.currentUser);

  @override
  Stream<AuthChange> get changes => _auth.onAuthStateChange
      .map(_toChange)
      .where((AuthChange? change) => change != null)
      .cast<AuthChange>();

  /// Maps a GoTrue event to a domain change, or null for events this app has no
  /// opinion about.
  ///
  /// The mapping is where the "a token refresh must not log the user out" rule
  /// is actually enforced. `tokenRefreshed` becomes [AuthTokenRefreshed] — a
  /// distinct case the coordinator ignores — rather than being folded into
  /// "signed in" (which would re-resolve the context on every refresh) or
  /// falling through to a default (which would look like a sign-out).
  static AuthChange? _toChange(sb.AuthState state) {
    final AuthUser? user = _toUser(state.session?.user);

    return switch (state.event) {
      sb.AuthChangeEvent.initialSession =>
        user == null ? const AuthSignedOut() : AuthSignedIn(user),
      sb.AuthChangeEvent.signedIn =>
        user == null ? const AuthSignedOut() : AuthSignedIn(user),
      sb.AuthChangeEvent.signedOut => const AuthSignedOut(),
      sb.AuthChangeEvent.tokenRefreshed =>
        user == null ? const AuthSignedOut() : AuthTokenRefreshed(user),
      // A profile attribute changed. The identity is the same, so the resolved
      // context is still valid — re-resolving would be a wasted round trip.
      sb.AuthChangeEvent.userUpdated =>
        user == null ? const AuthSignedOut() : AuthTokenRefreshed(user),
      // Password-recovery and MFA flows are not part of this milestone. Having
      // no opinion is safer than inventing one.
      _ => null,
    };
  }

  static AuthUser? _toUser(sb.User? user) {
    if (user == null) {
      return null;
    }
    return AuthUser(id: user.id, email: user.email);
  }

  @override
  Future<SignInResult> signInWithPassword({
    required String email,
    required String password,
  }) async {
    try {
      final sb.AuthResponse response = await _auth.signInWithPassword(
        email: email,
        password: password,
      );
      // Defence in depth: a 200 with no session is not a sign-in.
      return response.session == null
          ? const SignInFailed(UnavailableFailure())
          : const SignInSucceeded();
    } on sb.AuthApiException catch (error) {
      // A credential rejection is a 400/401 from GoTrue. Anything else — a 500,
      // a gateway error — is operational and must not be shown as "wrong
      // password".
      final int? status = int.tryParse(error.statusCode ?? '');
      final bool rejected = status != null && status >= 400 && status < 500;
      return rejected
          ? const SignInRejected()
          : const SignInFailed(UnavailableFailure());
    } on Object catch (error) {
      return SignInFailed(mapSupabaseError(error));
    }
  }

  @override
  Future<SignOutResult> signOut() async {
    try {
      // `local` scope, matching the web: signing out on this device must not
      // end the same person's sessions elsewhere.
      await _auth.signOut(scope: sb.SignOutScope.local);
      return const SignOutSucceeded();
    } on Object catch (error) {
      return SignOutFailed(mapSupabaseError(error));
    }
  }
}
