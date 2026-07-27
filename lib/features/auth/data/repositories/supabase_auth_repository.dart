import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../../core/errors/failure_mapper.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/repositories/auth_repository.dart';

/// How long a sign-in may take before it is abandoned.
///
/// Without this a request against a host that accepts a connection and then
/// says nothing leaves the button spinning with no end and no message. Thirty
/// seconds is well past a slow mobile round trip and well short of a user
/// deciding the app is broken.
const Duration signInTimeout = Duration(seconds: 30);

/// The Supabase-backed [AuthRepository].
///
/// The only file above the SDK that knows GoTrue exists. It translates GoTrue's
/// event vocabulary into the three domain changes the rest of the app reasons
/// about, and nothing else leaks upward — no `Session`, no `User`, no
/// `AuthChangeEvent`, no access token.
final class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._auth, {Duration timeout = signInTimeout})
    : _timeout = timeout;

  final sb.GoTrueClient _auth;

  /// Injectable so a test can prove the timeout branch without waiting for it.
  final Duration _timeout;

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
      final sb.AuthResponse response = await _auth
          .signInWithPassword(email: email, password: password)
          .timeout(_timeout);
      // Defence in depth: a 200 with no session is not a sign-in.
      return response.session == null
          ? const SignInFailed(SignInFailureReason.unexpected)
          : const SignInSucceeded();
    } on TimeoutException {
      return const SignInFailed(SignInFailureReason.timeout);
    } on sb.AuthApiException catch (error) {
      return _classify(error);
    } on sb.AuthRetryableFetchException catch (error) {
      // GoTrue funnels *every* transport failure into this one type with a null
      // status code — no route to the host, an unanswered DNS lookup, a
      // rejected TLS handshake, a browser CORS refusal, and an Android socket
      // the OS refuses because the app holds no INTERNET permission. It reuses
      // the same type for a genuine 5xx, which does carry a status; that is the
      // only thing separating "we never arrived" from "it answered badly".
      final int? status = int.tryParse(error.statusCode ?? '');
      return SignInFailed(
        status != null && status >= 500
            ? SignInFailureReason.serviceUnavailable
            : SignInFailureReason.network,
      );
    } on sb.AuthException {
      // Some other GoTrue-level condition: a missing session, an unusable JWT,
      // a PKCE exchange that failed. Real, but neither a transport problem nor
      // a rejection, and mapping it to either would be a lie.
      return const SignInFailed(SignInFailureReason.unexpected);
    } on Object {
      // Nothing here reads the error. An unrecognized throw is a bug in this
      // app or in the SDK, not a statement about the user's network.
      return const SignInFailed(SignInFailureReason.unexpected);
    }
  }

  /// Classifies a GoTrue API error.
  ///
  /// Discrimination is by machine code and HTTP status **only**. GoTrue's
  /// `message` is prose that changes between releases and can carry account
  /// detail, so it is neither read nor shown — the same rule the failure mapper
  /// applies to Postgres messages.
  static SignInResult _classify(sb.AuthApiException error) {
    switch (error.code) {
      case 'invalid_credentials':
      case 'user_not_found':
        return const SignInRejected();
      case 'email_not_confirmed':
        return const SignInUnconfirmed();
      case 'over_request_rate_limit':
        return const SignInThrottled();
    }

    final int? status = int.tryParse(error.statusCode ?? '');

    if (status == null) {
      return const SignInFailed(SignInFailureReason.unexpected);
    }
    if (status >= 500) {
      return const SignInFailed(SignInFailureReason.serviceUnavailable);
    }
    if (status == 429) {
      return const SignInThrottled();
    }
    // A 401 or 403 carrying no credential code is the API gateway refusing the
    // *request*, not the account: an absent, malformed or revoked publishable
    // key, or a URL pointing at another project. GoTrue answers a wrong password
    // with 400 and a code, so this branch cannot swallow one — and presenting it
    // as "wrong password" would send a user to reset a password that was never
    // read, while the real fault sits in the build.
    if (status == 401 || status == 403) {
      return const SignInFailed(SignInFailureReason.configuration);
    }
    if (status >= 400) {
      // Any other 4xx: GoTrue looked at the credentials and refused them.
      return const SignInRejected();
    }
    return const SignInFailed(SignInFailureReason.unexpected);
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
