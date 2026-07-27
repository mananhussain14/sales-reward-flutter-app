import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sale_reward/features/auth/data/repositories/supabase_auth_repository.dart';
import 'package:sale_reward/features/auth/domain/repositories/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

class _MockGoTrueClient extends Mock implements sb.GoTrueClient {}

/// How a sign-in failure is classified.
///
/// The defect this suite pins down: every non-4xx outcome used to become one
/// `UnavailableFailure`, which the login screen rendered as "Check your
/// connection and try again." A release APK that could not open a socket at all
/// and a Supabase project answering 500 and a bug in this app all produced the
/// same sentence, and that sentence sent people to inspect a Wi-Fi connection
/// that was working.
///
/// Discrimination is by machine code and HTTP status only — never by message
/// text, which GoTrue is free to reword and which can name an account.
void main() {
  late _MockGoTrueClient auth;
  late SupabaseAuthRepository repository;

  setUp(() {
    auth = _MockGoTrueClient();
    repository = SupabaseAuthRepository(
      auth,
      timeout: const Duration(milliseconds: 50),
    );
  });

  Future<SignInResult> signIn() => repository.signInWithPassword(
    email: 'sam@example.com',
    password: 'secret',
  );

  void answerWith(Object error) {
    when(
      () => auth.signInWithPassword(
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    ).thenThrow(error);
  }

  group('success', () {
    test('a response carrying a session is a sign-in', () {
      when(
        () => auth.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => sb.AuthResponse(session: _session()));

      expect(signIn(), completion(isA<SignInSucceeded>()));
    });

    test('a 200 carrying no session is not a sign-in', () async {
      when(
        () => auth.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => sb.AuthResponse());

      // Fails closed, and as a *bug* rather than as a connectivity problem —
      // there is nothing wrong with the network in this case.
      expect(
        await signIn(),
        isA<SignInFailed>().having(
          (SignInFailed f) => f.reason,
          'reason',
          SignInFailureReason.unexpected,
        ),
      );
    });
  });

  group('the credentials were evaluated and refused', () {
    test('the invalid_credentials code is a rejection', () async {
      answerWith(
        sb.AuthApiException(
          'Invalid login credentials',
          statusCode: '400',
          code: 'invalid_credentials',
        ),
      );
      expect(await signIn(), isA<SignInRejected>());
    });

    test('the user_not_found code is the same generic rejection', () async {
      // Identical to a wrong password on purpose. Splitting them would turn the
      // login screen into an account-enumeration oracle.
      answerWith(
        sb.AuthApiException(
          'User not found',
          statusCode: '400',
          code: 'user_not_found',
        ),
      );
      expect(await signIn(), isA<SignInRejected>());
    });

    test('a 400 with no code is still a rejection', () async {
      answerWith(sb.AuthApiException('Bad request', statusCode: '400'));
      expect(await signIn(), isA<SignInRejected>());
    });

    test('an unconfirmed address is distinct from a wrong password', () async {
      answerWith(
        sb.AuthApiException(
          'Email not confirmed',
          statusCode: '400',
          code: 'email_not_confirmed',
        ),
      );
      expect(await signIn(), isA<SignInUnconfirmed>());
    });
  });

  group('the credentials were never evaluated', () {
    test('the rate-limit code is throttling, not a rejection', () async {
      answerWith(
        sb.AuthApiException(
          'Too many requests',
          statusCode: '429',
          code: 'over_request_rate_limit',
        ),
      );
      expect(await signIn(), isA<SignInThrottled>());
    });

    test('a 429 with no code is throttling', () async {
      answerWith(sb.AuthApiException('Too many requests', statusCode: '429'));
      expect(await signIn(), isA<SignInThrottled>());
    });

    // The shape of an absent, malformed or revoked publishable key, or a URL
    // addressing a different project: the API gateway refuses the request before
    // GoTrue reads an account. Reporting it as a wrong password would send a
    // user to reset a password that was never looked at.
    for (final String status in <String>['401', '403']) {
      test(
        'a $status with no credential code is a configuration fault',
        () async {
          answerWith(
            sb.AuthApiException('Invalid API key', statusCode: status),
          );
          expect(
            await signIn(),
            isA<SignInFailed>().having(
              (SignInFailed f) => f.reason,
              'reason',
              SignInFailureReason.configuration,
            ),
          );
        },
      );
    }

    test(
      'a 401 that does carry a credential code is still a rejection',
      () async {
        // Guards the ordering: the code is consulted before the status, so a
        // GoTrue release that answered 401 for a wrong password could not be
        // misreported as a broken build.
        answerWith(
          sb.AuthApiException(
            'Invalid login credentials',
            statusCode: '401',
            code: 'invalid_credentials',
          ),
        );
        expect(await signIn(), isA<SignInRejected>());
      },
    );
  });

  group('the service answered badly', () {
    test('a 500 is a service failure, not a rejection', () async {
      answerWith(sb.AuthApiException('Internal error', statusCode: '500'));
      expect(
        await signIn(),
        isA<SignInFailed>().having(
          (SignInFailed f) => f.reason,
          'reason',
          SignInFailureReason.serviceUnavailable,
        ),
      );
    });

    test(
      'a retryable fetch error carrying a 5xx is a service failure',
      () async {
        // GoTrue reuses AuthRetryableFetchException for a genuine 5xx, and the
        // status is the only thing separating it from "we never arrived".
        answerWith(
          sb.AuthRetryableFetchException(
            message: 'Bad gateway',
            statusCode: '503',
          ),
        );
        expect(
          await signIn(),
          isA<SignInFailed>().having(
            (SignInFailed f) => f.reason,
            'reason',
            SignInFailureReason.serviceUnavailable,
          ),
        );
      },
    );
  });

  group('the request never arrived', () {
    // Every transport failure reaches this one type with a null status: no
    // route, an unanswered DNS lookup, a refused TLS handshake, a browser CORS
    // refusal — and the socket an Android release build could not open at all
    // because its manifest declared no INTERNET permission. That last one is the
    // failure this milestone was opened for.
    test(
      'a retryable fetch error with no status is a network failure',
      () async {
        answerWith(
          sb.AuthRetryableFetchException(
            message: 'SocketException: Failed host lookup',
          ),
        );
        expect(
          await signIn(),
          isA<SignInFailed>().having(
            (SignInFailed f) => f.reason,
            'reason',
            SignInFailureReason.network,
          ),
        );
      },
    );

    test(
      'a sign-in that never answers times out rather than hanging',
      () async {
        when(
          () => auth.signInWithPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenAnswer((_) => Completer<sb.AuthResponse>().future);

        expect(
          await signIn(),
          isA<SignInFailed>().having(
            (SignInFailed f) => f.reason,
            'reason',
            SignInFailureReason.timeout,
          ),
        );
      },
    );
  });

  group('anything else is a bug, not a network problem', () {
    test('another GoTrue exception is unexpected', () async {
      answerWith(sb.AuthSessionMissingException());
      expect(
        await signIn(),
        isA<SignInFailed>().having(
          (SignInFailed f) => f.reason,
          'reason',
          SignInFailureReason.unexpected,
        ),
      );
    });

    test('a malformed response is unexpected', () async {
      answerWith(const FormatException('not json'));
      expect(
        await signIn(),
        isA<SignInFailed>().having(
          (SignInFailed f) => f.reason,
          'reason',
          SignInFailureReason.unexpected,
        ),
      );
    });

    test('a programming error is unexpected', () async {
      answerWith(StateError('a bug in this app'));
      expect(
        await signIn(),
        isA<SignInFailed>().having(
          (SignInFailed f) => f.reason,
          'reason',
          SignInFailureReason.unexpected,
        ),
      );
    });

    test('an unexpected throw is never reported as a rejection', () async {
      answerWith(StateError('a bug in this app'));
      expect(await signIn(), isNot(isA<SignInRejected>()));
    });
  });

  group('no backend text escapes the repository', () {
    test('the result carries no message from the exception', () async {
      const String secretish =
          'user sam@example.com in tenant 42 failed policy vendor_read';
      answerWith(
        sb.AuthApiException(
          secretish,
          statusCode: '400',
          code: 'invalid_credentials',
        ),
      );

      final SignInResult result = await signIn();

      // The union has no field able to carry prose at all, which is the point:
      // there is no channel through which a GoTrue message could reach the UI.
      expect(result, isA<SignInRejected>());
      expect(result.toString(), isNot(contains('sam@example.com')));
      expect(result.toString(), isNot(contains('vendor_read')));
    });
  });
}

sb.Session _session() => sb.Session(
  accessToken: 'test-access-token',
  tokenType: 'bearer',
  user: _user(),
);

sb.User _user() => sb.User(
  id: 'user-1',
  appMetadata: const <String, dynamic>{},
  userMetadata: const <String, dynamic>{},
  aud: 'authenticated',
  createdAt: DateTime.utc(2026).toIso8601String(),
  email: 'sam@example.com',
);
