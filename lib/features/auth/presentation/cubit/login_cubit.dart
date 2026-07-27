import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/repositories/auth_repository.dart';

part 'login_state.dart';

/// Owns the login form.
///
/// A Cubit rather than a Bloc: the form has three transitions — a field
/// changed, visibility toggled, submit pressed — and none of them benefits from
/// being modelled as an event object.
///
/// It deliberately does **not** route on success. Signing in emits an auth
/// change, [SessionBloc] hears it and resolves the portal context, and the
/// router follows the resulting state. Routing from here would mean the
/// application had two opinions about where a signed-in user belongs, and the
/// one that did not consult the backend would sometimes win.
class LoginCubit extends Cubit<LoginState> {
  LoginCubit({required AuthRepository authRepository})
    : _auth = authRepository,
      super(const LoginState());

  final AuthRepository _auth;

  void emailChanged(String value) {
    emit(state.copyWith(email: value, clearErrors: true));
  }

  void passwordChanged(String value) {
    emit(state.copyWith(password: value, clearErrors: true));
  }

  void togglePasswordVisibility() {
    emit(state.copyWith(obscurePassword: !state.obscurePassword));
  }

  /// Validates, then attempts a sign-in.
  ///
  /// Re-entrant calls are dropped while a submission is in flight, so a
  /// double-tap cannot produce two authentication requests.
  Future<void> submit() async {
    if (state.isSubmitting) {
      return;
    }

    final String email = state.email.trim();
    final String? emailError = _validateEmail(email);
    final String? passwordError = _validatePassword(state.password);

    if (emailError != null || passwordError != null) {
      emit(
        state.copyWith(emailError: emailError, passwordError: passwordError),
      );
      return;
    }

    emit(state.copyWith(isSubmitting: true, clearErrors: true));

    final SignInResult result = await _auth.signInWithPassword(
      email: email,
      password: state.password,
    );
    if (isClosed) {
      return;
    }

    emit(switch (result) {
      // Stay submitting: the screen is about to be replaced by the router once
      // the context resolves, and re-enabling the button first would let a
      // second submission start during the handover.
      SignInSucceeded() => state.copyWith(isSubmitting: true),
      SignInRejected() => state.copyWith(
        isSubmitting: false,
        formError: LoginFormError.invalidCredentials,
      ),
      SignInUnconfirmed() => state.copyWith(
        isSubmitting: false,
        formError: LoginFormError.emailNotConfirmed,
      ),
      SignInThrottled() => state.copyWith(
        isSubmitting: false,
        formError: LoginFormError.tooManyAttempts,
      ),
      SignInFailed(:final SignInFailureReason reason) => state.copyWith(
        isSubmitting: false,
        formError: _errorFor(reason),
      ),
    });
  }

  /// Carries the repository's classification through unchanged.
  ///
  /// A straight one-to-one map, so that widening the domain later cannot
  /// quietly collapse a new reason into an existing message.
  static LoginFormError _errorFor(SignInFailureReason reason) =>
      switch (reason) {
        SignInFailureReason.network => LoginFormError.network,
        SignInFailureReason.timeout => LoginFormError.timeout,
        SignInFailureReason.serviceUnavailable =>
          LoginFormError.serviceUnavailable,
        SignInFailureReason.configuration => LoginFormError.configuration,
        SignInFailureReason.unexpected => LoginFormError.unexpected,
      };

  /// Shape only. Whether the address exists is the backend's business, and it
  /// deliberately never tells us.
  static String? _validateEmail(String value) {
    if (value.isEmpty) {
      return 'Enter your email address.';
    }
    final bool looksLikeEmail = RegExp(
      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
    ).hasMatch(value);
    return looksLikeEmail ? null : 'Enter a valid email address.';
  }

  /// Presence only. The password policy is enforced by Supabase Auth, which is
  /// the real authority; duplicating a length or complexity rule here would
  /// create a second definition that could disagree with it.
  static String? _validatePassword(String value) {
    return value.isEmpty ? 'Enter your password.' : null;
  }
}
