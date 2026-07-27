import 'package:flutter/material.dart';

import '../core/design/design.dart';
import '../core/widgets/widgets.dart';
import 'config/startup_failure.dart';
import 'theme/app_theme.dart';

/// The screen shown when the application could not finish starting.
///
/// It exists so that a startup failure produces a **frame**. Android keeps the
/// activity's window background on screen until Flutter renders its first one;
/// if `runApp` is never reached, that background is all the user ever sees, and
/// the real reason is visible only in `logcat`. Rendering this instead turns a
/// silent hang into something a user can read and an installer can act on.
///
/// The copy is deliberately incurious about the cause. It never names Supabase,
/// a host, a key, an HTTP status, or an exception — those go to the debug
/// console and no further.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key, required this.failure, this.onRetry});

  final StartupFailure failure;

  /// Re-runs initialization. Null when retrying could not help — see
  /// [StartupFailure.isRetryable].
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SalesReward',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: _StartupFailureView(failure: failure, onRetry: onRetry),
    );
  }
}

class _StartupFailureView extends StatefulWidget {
  const _StartupFailureView({required this.failure, this.onRetry});

  final StartupFailure failure;
  final Future<void> Function()? onRetry;

  @override
  State<_StartupFailureView> createState() => _StartupFailureViewState();
}

class _StartupFailureViewState extends State<_StartupFailureView> {
  bool _retrying = false;

  Future<void> _retry() async {
    final Future<void> Function()? onRetry = widget.onRetry;
    if (onRetry == null || _retrying) {
      return;
    }

    setState(() => _retrying = true);
    try {
      await onRetry();
    } finally {
      // A successful retry replaces this whole tree, so this only runs when the
      // retry failed and this screen is still mounted.
      if (mounted) {
        setState(() => _retrying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final bool canRetry = widget.onRetry != null && widget.failure.isRetryable;

    return Scaffold(
      backgroundColor: sr.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(SrSpacing.xxl),
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
                  SrCard(
                    padding: const EdgeInsets.all(SrSpacing.xxl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(
                          _title(widget.failure),
                          style: SrTypography.pageTitle.copyWith(
                            color: sr.foreground,
                          ),
                        ),
                        const SizedBox(height: SrSpacing.sm),
                        Text(
                          _body(widget.failure),
                          style: SrTypography.body.copyWith(
                            color: sr.textSecondary,
                          ),
                        ),
                        if (canRetry) ...<Widget>[
                          const SizedBox(height: SrSpacing.xxl),
                          SrButton(
                            label: 'Try again',
                            loadingLabel: 'Starting…',
                            size: SrButtonSize.lg,
                            fullWidth: true,
                            loading: _retrying,
                            onPressed: _retrying ? null : _retry,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Copy that is honest about what the user can do, and silent about
  /// everything else.
  static String _title(StartupFailure failure) => switch (failure) {
    StartupFailure.missingConfiguration ||
    StartupFailure.invalidConfiguration => 'SalesReward is not set up',
    StartupFailure.timedOut ||
    StartupFailure.initializationFailed => 'SalesReward could not start',
  };

  static String _body(StartupFailure failure) => switch (failure) {
    // The two configuration cases are a packaging fault, not a user fault, and
    // no amount of retrying or reconnecting will change them. Say so, and point
    // at the only person who can fix it.
    StartupFailure.missingConfiguration ||
    StartupFailure.invalidConfiguration =>
      'This copy of the app is missing the settings it needs to run. '
          'Reinstall it from your usual source, or contact your administrator.',
    StartupFailure.timedOut =>
      'Starting up took too long. Check your connection and try again.',
    StartupFailure.initializationFailed =>
      'Something went wrong while starting up. Check your connection and try '
          'again.',
  };
}
