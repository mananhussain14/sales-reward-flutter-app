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

  group('invalid configuration', () {
    test('a non-HTTPS URL', () {
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
