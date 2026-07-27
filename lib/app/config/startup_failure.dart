/// Why the application could not finish starting.
///
/// A closed set, because the startup screen has to say something honest and
/// safe about each case without ever naming Supabase, a URL, a key, an HTTP
/// body or a stack trace. The value is the *only* thing that crosses from
/// bootstrap into the UI; the underlying exception never does.
enum StartupFailure {
  /// A build-time value the app cannot run without is absent.
  ///
  /// Not recoverable at runtime: `--dart-define` values are compiled in, so a
  /// retry would read the same empty string. The screen offers no retry.
  missingConfiguration,

  /// A build-time value is present but unusable — not an HTTPS URL, or carrying
  /// whitespace or quote characters that a shell or an editor left behind.
  ///
  /// Also not recoverable at runtime, for the same reason.
  invalidConfiguration,

  /// Initialization did not finish inside the startup budget.
  ///
  /// Recoverable: a retry is offered, because the usual cause is a network that
  /// was not ready yet.
  timedOut,

  /// Initialization threw.
  ///
  /// Recoverable, and deliberately undifferentiated: the reason lives in the
  /// exception, and the exception is not something a user screen may repeat.
  initializationFailed;

  /// Whether offering a retry is honest.
  ///
  /// False for the two configuration cases: the values are compiled into the
  /// binary, so pressing retry could only ever fail the same way, and a control
  /// that cannot work is worse than none.
  bool get isRetryable =>
      this == StartupFailure.timedOut ||
      this == StartupFailure.initializationFailed;
}
