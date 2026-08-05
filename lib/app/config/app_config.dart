import 'package:flutter/foundation.dart';

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

  /// The only hosts an `http` URL may name, and only in a debug build.
  ///
  /// **Exact strings, matched whole.** Not a prefix, not a suffix, not a
  /// pattern: `localhost.example.com`, `127.0.0.1.example.com` and
  /// `evil-localhost` are all attacker-controlled names that a `contains`,
  /// `startsWith` or `endsWith` test would admit, and every one of them resolves
  /// to somebody else's server.
  ///
  /// `127.0.0.0/8` is loopback in its entirety and `0:0:0:0:0:0:0:1` is the same
  /// address as `::1`, but neither is admitted here. `supabase status` prints
  /// `127.0.0.1`, so the wider forms buy nothing and every one of them is
  /// another string to get wrong. They fail closed.
  static const Set<String> _loopbackHosts = <String>{
    'localhost',
    '127.0.0.1',
    '::1',
  };

  /// The rules, over explicit inputs.
  ///
  /// Split from [validate] because [supabaseUrl] and [supabasePublishableKey]
  /// are `const String.fromEnvironment` — compile-time constants that a test
  /// cannot vary. A test drives this function directly.
  ///
  /// [isDebugBuild] defaults to [kDebugMode], and [validate] — the only caller
  /// in the application — always takes that default. So in a profile or release
  /// build the loopback branch below is **unreachable**: there is no argument a
  /// shipped binary could pass to enter it, and no `--dart-define` that changes
  /// it, because `kDebugMode` is fixed by the build mode itself.
  ///
  /// It is a parameter only so a test can drive both build modes; `flutter test`
  /// always runs in debug, so a release build's behaviour would otherwise be
  /// unassertable.
  static StartupFailure? validateValues({
    required String url,
    required String publishableKey,
    bool isDebugBuild = kDebugMode,
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

    if (uri == null || uri.host.isEmpty) {
      return StartupFailure.invalidConfiguration;
    }

    // HTTPS remains the rule. Nothing below relaxes it for any host that is not
    // this machine, and nothing below applies outside a debug build.
    if (uri.scheme == 'https') {
      return null;
    }

    if (uri.scheme == 'http' && _isDebugLoopback(uri, isDebugBuild)) {
      return null;
    }

    return StartupFailure.invalidConfiguration;
  }

  /// Whether [uri] is the local Supabase stack, in a build allowed to reach it.
  ///
  /// ## Why this exception exists at all
  ///
  /// `supabase start` serves plain HTTP on `127.0.0.1:54321` and has no TLS to
  /// offer. Without this, manually testing a build against the local stack meant
  /// either standing a tunnel in front of it or editing this file — and an
  /// engineer who edits a validator to test something is one distracted commit
  /// away from shipping the edit.
  ///
  /// ## Why it cannot widen anything
  ///
  /// Three independent conditions, all required:
  ///
  /// 1. **The build is debug.** [kDebugMode] is fixed by the build mode, and
  ///    [validate] passes it, so a profile or release binary cannot reach this
  ///    branch by any input.
  /// 2. **The host is exactly one of [_loopbackHosts].** Whole-string equality
  ///    against a fixed set, on the host `Uri` parsed — not on the raw text — so
  ///    a name that merely *looks* local cannot pass.
  /// 3. **There is no user info.** `http://user@localhost` parses with a host of
  ///    `localhost`, and credentials in a URL are the shape of a phishing link
  ///    rather than of a local stack. Refused outright rather than ignored.
  ///
  /// `Uri` lower-cases the scheme and the host during parsing, so `HTTP://` and
  /// `LOCALHOST` are already normalised by the time they reach here and need no
  /// case handling of their own.
  static bool _isDebugLoopback(Uri uri, bool isDebugBuild) =>
      isDebugBuild && uri.userInfo.isEmpty && _loopbackHosts.contains(uri.host);

  /// Whether [value] carries whitespace or quote characters.
  static bool _isDirty(String value) =>
      value.trim() != value ||
      value.contains(RegExp(r'\s')) ||
      value.contains('"') ||
      value.contains("'");
}
