part of 'login_cubit.dart';

/// A form-level failure.
///
/// One value per *message the user should read*. Everything below the rejection
/// cases is an operational failure — none of them is a rejection, and none is
/// ever shown as one.
enum LoginFormError {
  /// The credentials were rejected.
  ///
  /// One value for every rejection. The backend must never reveal whether an
  /// address exists, so a wrong password and an unknown account are
  /// indistinguishable here by design — splitting them would turn the login
  /// screen into an account-enumeration oracle.
  invalidCredentials,

  /// The credentials were correct but the address is unconfirmed.
  emailNotConfirmed,

  /// Too many attempts. The credentials were never evaluated.
  tooManyAttempts,

  /// The auth service could not be reached.
  network,

  /// The request was sent and nothing came back in time.
  timeout,

  /// The auth service answered with its own failure.
  serviceUnavailable,

  /// This build cannot authenticate — a packaging fault, not a user fault, and
  /// not something a user can fix by retrying or reconnecting.
  configuration,

  /// Something unforeseen went wrong.
  unexpected,
}

/// The login form's state.
final class LoginState extends Equatable {
  const LoginState({
    this.email = '',
    this.password = '',
    this.obscurePassword = true,
    this.isSubmitting = false,
    this.emailError,
    this.passwordError,
    this.formError,
  });

  final String email;
  final String password;
  final bool obscurePassword;
  final bool isSubmitting;

  final String? emailError;
  final String? passwordError;
  final LoginFormError? formError;

  /// Whether the submit control accepts a press.
  ///
  /// False while submitting, which is what makes a duplicate submission
  /// impossible from the control itself rather than only from the Cubit guard.
  bool get canSubmit => !isSubmitting;

  LoginState copyWith({
    String? email,
    String? password,
    bool? obscurePassword,
    bool? isSubmitting,
    String? emailError,
    String? passwordError,
    LoginFormError? formError,
    bool clearErrors = false,
  }) {
    return LoginState(
      email: email ?? this.email,
      password: password ?? this.password,
      obscurePassword: obscurePassword ?? this.obscurePassword,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      emailError: clearErrors ? null : (emailError ?? this.emailError),
      passwordError: clearErrors ? null : (passwordError ?? this.passwordError),
      formError: clearErrors ? null : (formError ?? this.formError),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    email,
    password,
    obscurePassword,
    isSubmitting,
    emailError,
    passwordError,
    formError,
  ];
}
