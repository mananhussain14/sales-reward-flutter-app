@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static assertions about the Android manifests.
///
/// ## Why this suite exists
///
/// The release APK shipped without `android.permission.INTERNET`. Nothing in
/// the source looked wrong, because the permission *was* present — in
/// `src/debug/AndroidManifest.xml` and `src/profile/AndroidManifest.xml`, which
/// the Flutter template writes for the tool's own hot-reload channel. Gradle
/// merges a source set's manifest only into its own build type, so debug and
/// profile builds had network access and release builds had none.
///
/// Every behavioural test in this repository runs on the Dart VM, where there is
/// no manifest and no Android permission model, so none of them could see it.
/// The failure only appeared on a device, as a login that reported a connection
/// problem on a working connection.
///
/// These tests read the manifests instead of exercising them, which is the only
/// way to catch a defect that lives in the build configuration.
void main() {
  late String main;

  final File mainFile = File('android/app/src/main/AndroidManifest.xml');
  final File debugFile = File('android/app/src/debug/AndroidManifest.xml');
  final File profileFile = File('android/app/src/profile/AndroidManifest.xml');

  setUpAll(() {
    main = mainFile.readAsStringSync();
  });

  test(
    'the main manifest exists (the scan would pass vacuously otherwise)',
    () {
      expect(mainFile.existsSync(), isTrue);
      expect(main, isNotEmpty);
    },
  );

  group('network access', () {
    test('the MAIN manifest declares INTERNET', () {
      // The point of the assertion is *which file* it is in. Only `src/main`
      // merges into every build type; a permission declared anywhere else
      // leaves the release APK unable to open a socket, which is exactly how
      // this shipped.
      expect(
        main.contains('android.permission.INTERNET'),
        isTrue,
        reason:
            'android/app/src/main/AndroidManifest.xml must declare '
            'android.permission.INTERNET, or release builds ship without '
            'network access and Supabase sign-in cannot work',
      );
    });

    test('INTERNET is declared outside <application>', () {
      // A substring check is not enough. `uses-permission` is only a permission
      // declaration as a direct child of <manifest>; nested inside
      // <application> it is a stray element the merger drops, and the release
      // APK ships without network access exactly as before — while a test that
      // only greps for the string keeps passing.
      // Comments are stripped first: the manifest explains this very rule in
      // prose, and prose that names an element must not be mistaken for the
      // element.
      final String markup = main.replaceAll(
        RegExp(r'<!--.*?-->', dotAll: true),
        '',
      );

      final int appStart = markup.indexOf('<application');
      final int appEnd = markup.indexOf('</application>');
      final int permission = markup.indexOf('android.permission.INTERNET');

      expect(appStart, greaterThanOrEqualTo(0));
      expect(appEnd, greaterThan(appStart));
      expect(permission, greaterThanOrEqualTo(0));
      expect(
        permission > appStart && permission < appEnd,
        isFalse,
        reason:
            'uses-permission must be a direct child of <manifest>; nested in '
            '<application> it declares nothing and release builds still have '
            'no network access',
      );
    });

    test('debug and profile do not carry it alone', () {
      // They may keep their own copy — the template puts it there and the
      // merger deduplicates. What must not happen is main lacking it while they
      // have it, because that is the combination that hides the fault behind a
      // working `flutter run`.
      for (final File file in <File>[debugFile, profileFile]) {
        if (!file.existsSync()) continue;
        if (file.readAsStringSync().contains('android.permission.INTERNET')) {
          expect(
            main.contains('android.permission.INTERNET'),
            isTrue,
            reason:
                '${file.path} declares INTERNET but the main manifest does '
                'not — debug would work and release would not',
          );
        }
      }
    });
  });

  group('transport security', () {
    test('cleartext HTTP is not enabled', () {
      // The Supabase project is HTTPS. Turning cleartext on would let a
      // misconfiguration downgrade silently instead of failing loudly.
      expect(
        main.contains('android:usesCleartextTraffic="true"'),
        isFalse,
        reason: 'the backend is HTTPS; cleartext must stay off',
      );
    });

    test('no network-security configuration relaxes trust', () {
      // A custom config is the usual place a debugging session installs a
      // user-CA override or a cleartext exemption and forgets to remove it.
      expect(
        main.contains('android:networkSecurityConfig'),
        isFalse,
        reason:
            'no network-security override is needed for a hosted HTTPS '
            'backend; adding one is how certificate validation gets weakened',
      );

      final Directory res = Directory('android/app/src/main/res');
      if (res.existsSync()) {
        final Iterable<File> configs = res
            .listSync(recursive: true)
            .whereType<File>()
            .where((File f) => f.path.contains('network_security_config'));
        expect(
          configs.map((File f) => f.path),
          isEmpty,
          reason: 'no network-security configuration file should exist',
        );
      }
    });
  });

  group('launch configuration', () {
    test('the launcher activity is exported', () {
      // An unexported launcher activity installs fine and then cannot be
      // started — the app appears to do nothing at all.
      expect(main.contains('android:exported="true"'), isTrue);
      expect(main.contains('android.intent.category.LAUNCHER'), isTrue);
      expect(main.contains('android.intent.action.MAIN'), isTrue);
    });

    test('the application id and namespace agree', () {
      final String gradle = File(
        'android/app/build.gradle.kts',
      ).readAsStringSync();

      final RegExp namespace = RegExp(r'namespace\s*=\s*"([^"]+)"');
      final RegExp applicationId = RegExp(r'applicationId\s*=\s*"([^"]+)"');

      final String? ns = namespace.firstMatch(gradle)?.group(1);
      final String? id = applicationId.firstMatch(gradle)?.group(1);

      expect(ns, isNotNull, reason: 'a namespace must be declared');
      expect(id, isNotNull, reason: 'an applicationId must be declared');
      // The manifest names the activity relatively (`.MainActivity`), which
      // resolves against the namespace. A mismatch produces a launch that
      // cannot find its activity class.
      expect(id, ns);
    });
  });
}
