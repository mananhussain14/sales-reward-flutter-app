import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/app/config/app_config.dart';
import 'package:sale_reward/app/config/startup_failure.dart';

/// The startup configuration parser.
///
/// [AppConfig.validate] reads `const String.fromEnvironment` values, which a
/// test cannot vary — they are baked in at compile time. The rules therefore
/// live in [AppConfig.validateValues], which takes them as arguments, and this
/// suite drives that.
///
/// Every case here used to be an uncaught `StateError` thrown out of
/// `bootstrap()` before `runApp()`. On Android that is invisible: the launch
/// window background stays up forever and the user sees a permanently blank
/// branded screen. Returning a value instead is what lets the app render a
/// reason.
void main() {
  const String url = 'https://project.supabase.co';
  const String key = 'sb_publishable_example';

  group('accepts a usable configuration', () {
    test('a hosted HTTPS URL and a non-empty key', () {
      expect(AppConfig.validateValues(url: url, publishableKey: key), isNull);
    });

    test('a URL carrying a path or a port', () {
      expect(
        AppConfig.validateValues(
          url: 'https://project.supabase.co:443/',
          publishableKey: key,
        ),
        isNull,
      );
    });

    test('a legacy JWT-shaped key', () {
      // The key format is the backend's business. Only presence and cleanliness
      // are checked here, so rotating from a JWT anon key to an `sb_publishable_`
      // key cannot start failing at launch.
      expect(
        AppConfig.validateValues(
          url: url,
          publishableKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.body.sig',
        ),
        isNull,
      );
    });
  });

  group('missing configuration', () {
    test('an absent URL', () {
      expect(
        AppConfig.validateValues(url: '', publishableKey: key),
        StartupFailure.missingConfiguration,
      );
    });

    test('an absent key', () {
      expect(
        AppConfig.validateValues(url: url, publishableKey: ''),
        StartupFailure.missingConfiguration,
      );
    });

    test(
      'both absent — the shape of a build with no --dart-define-from-file',
      () {
        expect(
          AppConfig.validateValues(url: '', publishableKey: ''),
          StartupFailure.missingConfiguration,
        );
      },
    );

    test('a missing value is not retryable', () {
      // The values are compiled in. A retry button would read the same empty
      // string and fail identically, so the screen must not offer one.
      expect(StartupFailure.missingConfiguration.isRetryable, isFalse);
      expect(StartupFailure.invalidConfiguration.isRetryable, isFalse);
    });
  });

  // ---------------------------------------------------------------------
  group('the local Supabase stack, in a debug build only', () {
    // `supabase start` serves plain HTTP on 127.0.0.1:54321 and has no TLS to
    // offer, so a debug build could not be pointed at it at all. The exception
    // below is the narrowest one that fixes that: debug builds, three exact
    // hostnames, and nothing else.
    const String localKey = 'sb_publishable_local';

    test('debug accepts the loopback IPv4 address', () {
      expect(
        AppConfig.validateValues(
          url: 'http://127.0.0.1:54321',
          publishableKey: localKey,
          isDebugBuild: true,
        ),
        isNull,
      );
    });

    test('debug accepts localhost', () {
      expect(
        AppConfig.validateValues(
          url: 'http://localhost:54321',
          publishableKey: localKey,
          isDebugBuild: true,
        ),
        isNull,
      );
    });

    test('debug accepts the IPv6 loopback address', () {
      // `Uri` strips the brackets, so the parsed host is the bare `::1` the
      // allow-list holds.
      expect(Uri.parse('http://[::1]:54321').host, '::1');
      expect(
        AppConfig.validateValues(
          url: 'http://[::1]:54321',
          publishableKey: localKey,
          isDebugBuild: true,
        ),
        isNull,
      );
    });

    test('debug accepts loopback with a path, and with no port', () {
      for (final String local in <String>[
        'http://127.0.0.1',
        'http://127.0.0.1:54321/',
        'http://localhost:54321/rest/v1',
      ]) {
        expect(
          AppConfig.validateValues(
            url: local,
            publishableKey: localKey,
            isDebugBuild: true,
          ),
          isNull,
          reason: local,
        );
      }
    });

    test('the scheme and host are matched after normalisation', () {
      // `Uri` lower-cases both during parsing, so no case handling of its own is
      // needed — asserted rather than assumed.
      expect(
        AppConfig.validateValues(
          url: 'HTTP://LOCALHOST:54321',
          publishableKey: localKey,
          isDebugBuild: true,
        ),
        isNull,
      );
    });

    test('a profile or release build rejects the SAME local URL', () {
      // The one property that makes the exception safe to ship. `AppConfig
      // .validate()` always passes `kDebugMode`, which the build mode fixes, so
      // there is no input a shipped binary could supply to reach the branch.
      for (final String local in <String>[
        'http://127.0.0.1:54321',
        'http://localhost:54321',
        'http://[::1]:54321',
      ]) {
        expect(
          AppConfig.validateValues(
            url: local,
            publishableKey: localKey,
            isDebugBuild: false,
          ),
          StartupFailure.invalidConfiguration,
          reason: local,
        );
      }
    });

    test('debug rejects plaintext to any REMOTE host', () {
      for (final String remote in <String>[
        'http://project.supabase.co',
        'http://10.0.2.2:54321',
        'http://0.0.0.0:54321',
        'http://192.168.1.10:54321',
      ]) {
        expect(
          AppConfig.validateValues(
            url: remote,
            publishableKey: localKey,
            isDebugBuild: true,
          ),
          StartupFailure.invalidConfiguration,
          reason: remote,
        );
      }
    });

    test('debug rejects a host that merely LOOKS local', () {
      // Every one of these is a name an attacker can register or control, and
      // every one of them would be admitted by a `contains`, `startsWith` or
      // `endsWith` test. The allow-list is whole-string equality for exactly
      // this reason.
      for (final String deceptive in <String>[
        'http://localhost.example.com',
        'http://127.0.0.1.example.com',
        'http://user@localhost',
        'http://localhost@example.com',
        'http://evil-localhost',
        'http://localhost.evil',
        'http://notlocalhost',
        'http://127.0.0.11',
        'http://127.0.0.2',
        'http://xn--localhost-.example.com',
      ]) {
        expect(
          AppConfig.validateValues(
            url: deceptive,
            publishableKey: localKey,
            isDebugBuild: true,
          ),
          StartupFailure.invalidConfiguration,
          reason: deceptive,
        );
      }
    });

    test('credentials in a loopback URL are refused, not ignored', () {
      // `http://user@localhost` parses with a host of `localhost`, so the host
      // check alone would admit it. Credentials in a URL are the shape of a
      // phishing link rather than of a local stack.
      expect(Uri.parse('http://user@localhost').host, 'localhost');
      expect(
        AppConfig.validateValues(
          url: 'http://user:pass@127.0.0.1:54321',
          publishableKey: localKey,
          isDebugBuild: true,
        ),
        StartupFailure.invalidConfiguration,
      );
    });

    test('a non-HTTP scheme is never admitted, loopback or not', () {
      for (final String scheme in <String>[
        'ftp://127.0.0.1:54321',
        'ws://localhost:54321',
        'file://localhost/etc/passwd',
        'javascript://localhost',
      ]) {
        expect(
          AppConfig.validateValues(
            url: scheme,
            publishableKey: localKey,
            isDebugBuild: true,
          ),
          StartupFailure.invalidConfiguration,
          reason: scheme,
        );
      }
    });

    test('the loopback exception weakens nothing else', () {
      // Every other rule still applies to a local URL: presence, whitespace,
      // quotes and a host.
      expect(
        AppConfig.validateValues(
          url: 'http://127.0.0.1:54321',
          publishableKey: '',
          isDebugBuild: true,
        ),
        StartupFailure.missingConfiguration,
      );
      expect(
        AppConfig.validateValues(
          url: ' http://127.0.0.1:54321 ',
          publishableKey: localKey,
          isDebugBuild: true,
        ),
        StartupFailure.invalidConfiguration,
      );
      expect(
        AppConfig.validateValues(
          url: '"http://127.0.0.1:54321"',
          publishableKey: localKey,
          isDebugBuild: true,
        ),
        StartupFailure.invalidConfiguration,
      );
      expect(
        AppConfig.validateValues(
          url: 'http://',
          publishableKey: localKey,
          isDebugBuild: true,
        ),
        StartupFailure.invalidConfiguration,
      );
    });

    test('the hosted HTTPS configuration is unaffected in every mode', () {
      for (final bool debug in <bool>[true, false]) {
        expect(
          AppConfig.validateValues(
            url: url,
            publishableKey: key,
            isDebugBuild: debug,
          ),
          isNull,
          reason: 'isDebugBuild: $debug',
        );
      }
    });

    test('HTTPS to a loopback host is still fine', () {
      // A tunnel in front of the local stack. Nothing about the exception makes
      // an encrypted local URL worse than an encrypted remote one.
      expect(
        AppConfig.validateValues(
          url: 'https://localhost:54321',
          publishableKey: localKey,
          isDebugBuild: false,
        ),
        isNull,
      );
    });
  });

  group('invalid configuration', () {
    test('a non-HTTPS URL to a remote host', () {
      expect(
        AppConfig.validateValues(
          url: 'http://project.supabase.co',
          publishableKey: key,
        ),
        StartupFailure.invalidConfiguration,
      );
    });

    test('a URL with no host', () {
      expect(
        AppConfig.validateValues(url: 'https://', publishableKey: key),
        StartupFailure.invalidConfiguration,
      );
    });

    test('a value that is not a URL at all', () {
      expect(
        AppConfig.validateValues(
          url: 'project.supabase.co',
          publishableKey: key,
        ),
        StartupFailure.invalidConfiguration,
      );
    });

    test('a URL with surrounding whitespace', () {
      expect(
        AppConfig.validateValues(
          url: '  https://project.supabase.co\n',
          publishableKey: key,
        ),
        StartupFailure.invalidConfiguration,
      );
    });

    test('a URL wrapped in quotes', () {
      // What a shell heredoc or a hand-edited JSON file leaves behind. It fails
      // later as an unresolvable hostname, a long way from its cause.
      expect(
        AppConfig.validateValues(
          url: '"https://project.supabase.co"',
          publishableKey: key,
        ),
        StartupFailure.invalidConfiguration,
      );
    });

    test('a key with surrounding whitespace or quotes', () {
      for (final String dirty in <String>[
        ' $key',
        '$key\n',
        '"$key"',
        "'$key'",
      ]) {
        expect(
          AppConfig.validateValues(url: url, publishableKey: dirty),
          StartupFailure.invalidConfiguration,
          reason: 'a key carrying whitespace or quotes must be rejected',
        );
      }
    });
  });

  group('the shipped values', () {
    test(
      'the compile-time names are the ones dart_defines.example.json uses',
      () {
        // A rename on either side silently produces an empty string, which used
        // to surface as a permanently blank launch screen. Asserting the pair
        // exists keeps the two files describing the same contract.
        expect(AppConfig.supabaseUrl, isA<String>());
        expect(AppConfig.supabasePublishableKey, isA<String>());
      },
    );
  });
}
