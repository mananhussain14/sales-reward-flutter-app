import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/design/design.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/repositories/auth_repository.dart';
import '../cubit/login_cubit.dart';

/// The sign-in screen.
///
/// Translated from § 5.1 of `docs/mobile-ui-design-handoff.md`. The web is a
/// two-column split whose gradient marketing panel is **already hidden below
/// `lg`**, so this builds the mobile column the web itself falls back to: the
/// brand lockup, a 32px gap, then a card carrying "Welcome back", the two
/// fields, and a full-width `lg` primary submit.
///
/// ## Invariants carried over from the web
///
/// * **The page is role-neutral.** Nothing names a role, because the page
///   genuinely cannot know who is signing in. Where the user lands is resolved
///   afterwards, by the backend.
/// * **Error copy stays generic.** A wrong password and an unknown address
///   produce the identical message; the backend never reveals which, and
///   neither does this screen.
/// * **No sign-up, no forgot-password, no social login, no demo credentials.**
///   None exists in the product, and the handoff records their absence as
///   deliberate. An affordance that cannot work is worse than none.
class LoginPage extends StatelessWidget {
  const LoginPage({super.key, this.authRepository});

  /// Overrides the injected repository. For tests only.
  final AuthRepository? authRepository;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<LoginCubit>(
      create: (BuildContext context) => LoginCubit(
        authRepository: authRepository ?? context.read<AuthRepository>(),
      ),
      child: const _LoginView(),
    );
  }
}

class _LoginView extends StatefulWidget {
  const _LoginView();

  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _submit() => context.read<LoginCubit>().submit();

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Scaffold(
      backgroundColor: sr.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return SingleChildScrollView(
              // Keyboard-safe: the viewInsets padding keeps the focused field
              // above the keyboard, and the scroll view means a short screen
              // never clips the submit button.
              padding: EdgeInsets.only(
                left: SrSpacing.lg,
                right: SrSpacing.lg,
                top: SrSpacing.xxl,
                bottom: SrSpacing.xxl + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: ConstrainedBox(
                // Enough height to centre on a tall screen, never enough to
                // force overflow on a short one.
                constraints: BoxConstraints(
                  minHeight:
                      constraints.maxHeight -
                      (SrSpacing.xxl * 2) -
                      MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: SrSpacing.compactMaxWidth,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const Center(child: SrBrandLockup(size: 40)),
                        const SizedBox(height: SrSpacing.xxxl),
                        _card(sr),
                        const SizedBox(height: SrSpacing.xxxl),
                        Text(
                          'Secure sign-in · SalesReward',
                          textAlign: TextAlign.center,
                          style: SrTypography.caption.copyWith(
                            color: sr.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _card(SrColorScheme sr) {
    return BlocBuilder<LoginCubit, LoginState>(
      builder: (BuildContext context, LoginState state) {
        return SrCard(
          padding: const EdgeInsets.all(SrSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Welcome back',
                style: SrTypography.pageTitle.copyWith(color: sr.foreground),
              ),
              const SizedBox(height: SrSpacing.sm),
              Text(
                'Sign in to your SalesReward account to continue.',
                style: SrTypography.body.copyWith(color: sr.textSecondary),
              ),

              if (state.formError != null) ...<Widget>[
                const SizedBox(height: SrSpacing.xl),
                SrAlert(
                  tone: SrAlertTone.error,
                  // No message here repeats anything the backend said. Each is
                  // fixed copy chosen from a classification, so an HTTP body, a
                  // GoTrue message, a key or a stack trace cannot reach the
                  // screen through this switch.
                  message: switch (state.formError!) {
                    // Deliberately identical for a wrong password and an
                    // unknown address.
                    LoginFormError.invalidCredentials =>
                      'That email address and password do not match an '
                          'account.',
                    LoginFormError.emailNotConfirmed =>
                      'Confirm your email address before signing in. Check '
                          'your inbox for the confirmation link.',
                    LoginFormError.tooManyAttempts =>
                      'Too many sign-in attempts. Wait a minute and try again.',
                    // Only the two genuinely connection-shaped failures mention
                    // the connection. Telling someone to check a connection
                    // that is working sends them to fix the wrong thing.
                    LoginFormError.network =>
                      'Could not reach SalesReward. Check your connection and '
                          'try again.',
                    LoginFormError.timeout =>
                      'Signing in took too long. Check your connection and try '
                          'again.',
                    LoginFormError.serviceUnavailable =>
                      'SalesReward is temporarily unavailable. Try again in a '
                          'few minutes.',
                    LoginFormError.configuration =>
                      'This copy of the app cannot sign in. Reinstall it from '
                          'your usual source, or contact your administrator.',
                    LoginFormError.unexpected =>
                      'Something went wrong while signing in. Try again.',
                  },
                ),
              ],

              const SizedBox(height: SrSpacing.xl),
              SrTextField(
                label: 'Email address',
                controller: _email,
                required: true,
                placeholder: 'you@example.com',
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const <String>[AutofillHints.username],
                enabled: !state.isSubmitting,
                errorText: state.emailError,
                onChanged: context.read<LoginCubit>().emailChanged,
                onSubmitted: (_) => _passwordFocus.requestFocus(),
              ),

              const SizedBox(height: SrSpacing.xl),
              SrTextField(
                label: 'Password',
                controller: _password,
                focusNode: _passwordFocus,
                required: true,
                obscureText: state.obscurePassword,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.done,
                autofillHints: const <String>[AutofillHints.password],
                enabled: !state.isSubmitting,
                errorText: state.passwordError,
                onChanged: context.read<LoginCubit>().passwordChanged,
                onSubmitted: (_) => _submit(),
                suffix: _VisibilityToggle(
                  obscured: state.obscurePassword,
                  enabled: !state.isSubmitting,
                  onPressed: context
                      .read<LoginCubit>()
                      .togglePasswordVisibility,
                ),
              ),

              const SizedBox(height: SrSpacing.xxl),
              SrButton(
                label: 'Sign in',
                loadingLabel: 'Signing in…',
                size: SrButtonSize.lg,
                fullWidth: true,
                loading: state.isSubmitting,
                onPressed: state.canSubmit ? _submit : null,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The show/hide control inside the password field.
///
/// A real button with a state-dependent accessible label, so a screen-reader
/// user is told what pressing it will do — not merely that an eye is present.
class _VisibilityToggle extends StatelessWidget {
  const _VisibilityToggle({
    required this.obscured,
    required this.enabled,
    required this.onPressed,
  });

  final bool obscured;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final String label = obscured ? 'Show password' : 'Hide password';

    return Semantics(
      button: true,
      label: label,
      // An explicit label, so assistive technology announces what pressing the
      // control will do rather than merely that an icon is present.
      child: IconButton(
        icon: Icon(
          obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          size: 20,
          color: context.sr.textSecondary,
        ),
        tooltip: label,
        onPressed: enabled ? onPressed : null,
        splashRadius: 20,
      ),
    );
  }
}
