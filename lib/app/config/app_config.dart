import 'startup_failure.dart';

/// The build-time connection settings.
///
/// Both values arrive through `--dart-define-from-file=dart_defines.json` and
/// are compiled into the binary. Both are public by definition — the web bundle
/// embeds the same two — and nothing privileged is ever read here. The
/// service-role key has no representation in this class because it has no
/// representation in this application.
abstract final class AppConfig {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  /// Validates the values this binary was built with.
  ///
  /// Returns null when they are usable, or the [StartupFailure] to show
  /// otherwise. It **returns** rather than throws so the caller can render a
  /// screen instead of dying before the first frame — an uncaught throw here is
  /// what leaves an Android launch stuck on the system's window background with
  /// nothing on screen to explain it.
  static StartupFailure? validate() =>
      validateValues(url: supabaseUrl, publishableKey: supabasePublishableKey);

  /// The rules, over explicit inputs.
  ///
  /// Split from [validate] because [supabaseUrl] and [supabasePublishableKey]
  /// are `const String.fromEnvironment` — compile-time constants that a test
  /// cannot vary. A test drives this function directly.
  static StartupFailure? validateValues({
    required String url,
    required String publishableKey,
  }) {
    if (url.isEmpty || publishableKey.isEmpty) {
      return StartupFailure.missingConfiguration;
    }

    // A shell heredoc, a copy-paste, or a JSON editor can leave a stray space,
    // newline or quote around either value. None of it is legal in a URL and
    // none of it belongs in a header, and the resulting failure — a DNS lookup
    // for a host with a quote in it — surfaces far from its cause. Reject it
    // here, where the message can be about configuration.
    if (_isDirty(url) || _isDirty(publishableKey)) {
      return StartupFailure.invalidConfiguration;
    }

    final Uri? uri = Uri.tryParse(url);

    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return StartupFailure.invalidConfiguration;
    }

    return null;
  }

  /// Whether [value] carries whitespace or quote characters.
  static bool _isDirty(String value) =>
      value.trim() != value ||
      value.contains(RegExp(r'\s')) ||
      value.contains('"') ||
      value.contains("'");
}
