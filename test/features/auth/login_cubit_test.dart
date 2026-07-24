import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/features/auth/domain/repositories/auth_repository.dart';
import 'package:sale_reward/features/auth/presentation/cubit/login_cubit.dart';

import '../../support/fakes.dart';

void main() {
  late FakeAuthRepository auth;

  setUp(() => auth = FakeAuthRepository());
  tearDown(() => auth.dispose());

  LoginCubit build() => LoginCubit(authRepository: auth);

  group('validation', () {
    blocTest<LoginCubit, LoginState>(
      'rejects an empty email and password without calling the backend',
      build: build,
      act: (LoginCubit c) => c.submit(),
      verify: (LoginCubit c) {
        expect(c.state.emailError, isNotNull);
        expect(c.state.passwordError, isNotNull);
        expect(auth.signInCallCount, 0);
      },
    );

    blocTest<LoginCubit, LoginState>(
      'rejects a malformed email',
      build: build,
      act: (LoginCubit c) => c
        ..emailChanged('not-an-email')
        ..passwordChanged('secret')
        ..submit(),
      verify: (LoginCubit c) {
        expect(c.state.emailError, isNotNull);
        expect(auth.signInCallCount, 0);
      },
    );
  });

  group('submission', () {
    blocTest<LoginCubit, LoginState>(
      'a valid submission calls sign-in with the entered credentials',
      build: build,
      act: (LoginCubit c) => c
        ..emailChanged('  sam@example.com ')
        ..passwordChanged('secret')
        ..submit(),
      verify: (LoginCubit c) {
        expect(auth.signInCallCount, 1);
        // The email is trimmed before it reaches the backend.
        expect(auth.lastSignIn?.email, 'sam@example.com');
        expect(auth.lastSignIn?.password, 'secret');
      },
    );

    blocTest<LoginCubit, LoginState>(
      'invalid credentials keep the form with a generic error',
      build: () {
        auth.nextSignInResult = const SignInRejected();
        return build();
      },
      act: (LoginCubit c) => c
        ..emailChanged('sam@example.com')
        ..passwordChanged('wrong')
        ..submit(),
      verify: (LoginCubit c) {
        expect(c.state.formError, LoginFormError.invalidCredentials);
        expect(c.state.isSubmitting, isFalse);
      },
    );

    blocTest<LoginCubit, LoginState>(
      'an operational failure is distinct from a credential rejection',
      build: () {
        auth.nextSignInResult = const SignInFailed(UnavailableFailure());
        return build();
      },
      act: (LoginCubit c) => c
        ..emailChanged('sam@example.com')
        ..passwordChanged('secret')
        ..submit(),
      verify: (LoginCubit c) {
        expect(c.state.formError, LoginFormError.unavailable);
        expect(c.state.formError, isNot(LoginFormError.invalidCredentials));
      },
    );

    blocTest<LoginCubit, LoginState>(
      'a duplicate submit while in flight does not call sign-in twice',
      build: () {
        auth.nextSignInResult = const SignInSucceeded();
        return build();
      },
      act: (LoginCubit c) async {
        c
          ..emailChanged('sam@example.com')
          ..passwordChanged('secret');
        // Two submits back to back; the second is dropped by the in-flight
        // guard.
        await Future.wait<void>(<Future<void>>[c.submit(), c.submit()]);
      },
      verify: (LoginCubit c) => expect(auth.signInCallCount, 1),
    );
  });

  group('form controls', () {
    blocTest<LoginCubit, LoginState>(
      'toggles password visibility',
      build: build,
      act: (LoginCubit c) => c.togglePasswordVisibility(),
      verify: (LoginCubit c) => expect(c.state.obscurePassword, isFalse),
    );

    blocTest<LoginCubit, LoginState>(
      'editing a field clears a previous error',
      build: () {
        auth.nextSignInResult = const SignInRejected();
        return build();
      },
      act: (LoginCubit c) async {
        c
          ..emailChanged('sam@example.com')
          ..passwordChanged('wrong');
        await c.submit();
        c.passwordChanged('secret2');
      },
      verify: (LoginCubit c) => expect(c.state.formError, isNull),
    );
  });
}
