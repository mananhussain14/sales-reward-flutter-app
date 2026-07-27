import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config/app_config.dart';
import 'config/startup_failure.dart';
import 'di/injector.dart';
import 'startup_failure_app.dart';

/// How long initialization may take before the user gets a screen instead.
///
/// Not a network timeout for the app's own requests — those are the
/// repositories' business. This is the budget for *reaching the first frame*,
/// and it exists because there is no upper bound on how long a hung
/// initialization would otherwise hold the launch screen. Twenty seconds is
/// long enough that a slow-but-working cold start on mobile data still wins,
/// and short enough that a stuck one does not look like a crash.
const Duration startupTimeout = Duration(seconds: 20);

/// Starts the application.
///
/// Supabase is initialized with the URL and the **publishable** key only — the
/// same two values the web bundle embeds, and the only two that may ever appear
/// in a mobile binary. Anything in the binary is public; an APK is trivially
/// unpacked. The service-role key, the Resend key and any future OCR credential
/// stay server-side, exactly as they do in the web repository.
///
/// ## Why this always reaches `runApp`
///
/// Android shows the activity's window background (`LaunchTheme`) from process
/// start until Flutter rasterizes its first frame. Nothing else ends it — there
/// is no native splash plugin here, and no call to remove one. So a `bootstrap`
/// that throws, or that awaits something which never settles, does not produce
/// an error: it produces an app that sits on a blank branded background
/// forever, with the cause visible only to whoever thinks to run `logcat`.
///
/// Every path below therefore ends in a `runApp`, either with the real
/// application or with [StartupFailureApp]. Failures are classified into
/// [StartupFailure] — a closed set with no exception text in it — so the screen
/// can be specific without repeating anything a user should not see.
Future<void> bootstrap() => _start();

Future<void> _start() async {
  WidgetsFlutterBinding.ensureInitialized();

  final StartupFailure? failure = await initializeApp();

  runApp(
    failure == null
        ? const SaleRewardApp()
        // `_start` is passed as the retry: it re-runs the whole sequence and
        // replaces this tree with the real app if the second attempt works.
        : StartupFailureApp(failure: failure, onRetry: _start),
  );
}

/// Validates configuration, initializes Supabase, and registers the graph.
///
/// Returns null on success, or the reason to show. It never throws and never
/// hangs: [timeout] bounds the one call that talks to the outside world.
///
/// Idempotent enough to be a retry target — `Supabase.initialize` tolerates
/// being called again after a failure, and [configureDependencies] returns
/// early once the graph is registered.
@visibleForTesting
Future<StartupFailure?> initializeApp({
  Duration timeout = startupTimeout,
}) async {
  final StartupFailure? invalid = AppConfig.validate();
  if (invalid != null) {
    _report(invalid);
    return invalid;
  }

  try {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabasePublishableKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    ).timeout(timeout);

    await configureDependencies();
  } on TimeoutException {
    _report(StartupFailure.timedOut);
    return StartupFailure.timedOut;
  } on Object catch (error) {
    _report(StartupFailure.initializationFailed, error);
    return StartupFailure.initializationFailed;
  }

  if (kDebugMode) {
    debugPrint('Supabase client initialized successfully.');
  }

  return null;
}

/// Reports a startup failure to the debug console.
///
/// Debug builds only, and it prints the classification plus the exception's
/// *type* — never its message. A thrown Supabase error can carry a request
/// body, and a released build must not write either to the device log.
void _report(StartupFailure failure, [Object? error]) {
  if (!kDebugMode) {
    return;
  }
  final String detail = error == null ? '' : ' (${error.runtimeType})';
  debugPrint('Startup failed: ${failure.name}$detail');
}
