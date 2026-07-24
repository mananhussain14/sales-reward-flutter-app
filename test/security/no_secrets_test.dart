@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-safety assertions.
///
/// The Dart counterpart of the web repository's `*-source-safety.test.ts` suite,
/// recommended as "Tier 4" in § 9.2 of `mobile-architecture-recommendation.md`.
/// These tests read the source rather than exercising it, which makes them the
/// cheapest possible guard against the security boundary eroding under deadline
/// pressure — the kind of regression a behavioural test cannot see.
void main() {
  late List<File> sources;

  setUpAll(() {
    sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .toList();
  });

  test(
    'the lib tree is non-empty (the scan would pass vacuously otherwise)',
    () {
      expect(sources, isNotEmpty);
    },
  );

  test('no source names a service-role key', () {
    // The service key is equivalent to full database access. An APK is
    // trivially unpacked, so it may never appear in a mobile binary, in a
    // --dart-define, or in CI variables.
    _expectAbsent(sources, <String>[
      'SUPABASE_SERVICE_ROLE_KEY',
      'service_role',
      'serviceRoleKey',
    ]);
  });

  test('no source names a third-party delivery secret', () {
    _expectAbsent(sources, <String>['RESEND_API_KEY', 'RESEND_FROM']);
  });

  test('no source writes to Storage directly', () {
    // `storage.objects` and `storage.buckets` have RLS with zero policies, so
    // only the service key can write. A client-side upload cannot work, and an
    // attempt to add one is a signal that the secret is about to follow.
    _expectAbsent(sources, <String>[
      '.storage.from(',
      'storage.from(',
      'uploadBinary(',
    ]);
  });

  test('no source hardcodes a role as proof of permission', () {
    // Role *codes* may appear for display. A hardcoded permission name being
    // compared to decide a write would be the client deciding authorization,
    // which SQL is supposed to own.
    _expectAbsent(sources, <String>[
      'RECEIPT_SUBMIT',
      'RETAILER_STAFF_READ',
      'RETAILER_PORTAL_READ',
      'RETAILER_PRODUCTS_READ',
      'RBAC_READ',
    ], allowInComments: true);
  });

  test('only the config layer reads a dart-define', () {
    final Iterable<File> offenders = sources.where(
      (File f) =>
          f.readAsStringSync().contains('String.fromEnvironment') &&
          !f.path.endsWith('app_config.dart'),
    );

    expect(
      offenders.map((File f) => f.path),
      isEmpty,
      reason: 'environment reads belong in AppConfig alone',
    );
  });

  test('dart_defines.json is not tracked by git', () {
    final ProcessResult result = Process.runSync('git', <String>[
      'ls-files',
      'dart_defines.json',
    ]);

    expect(
      (result.stdout as String).trim(),
      isEmpty,
      reason: 'dart_defines.json holds environment values and must stay local',
    );
  });
}

/// Fails if any [needle] appears in executable source.
///
/// When [allowInComments] is true, a match inside a `//` or `///` line is
/// ignored — the permission names above are legitimately *discussed* in the
/// documentation comments that explain why the client does not check them.
void _expectAbsent(
  List<File> sources,
  List<String> needles, {
  bool allowInComments = false,
}) {
  final List<String> hits = <String>[];

  for (final File file in sources) {
    final List<String> lines = file.readAsLinesSync();

    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i];
      final String trimmed = line.trimLeft();

      if (allowInComments &&
          (trimmed.startsWith('//') || trimmed.startsWith('*'))) {
        continue;
      }

      for (final String needle in needles) {
        if (line.contains(needle)) {
          hits.add('${file.path}:${i + 1} → $needle');
        }
      }
    }
  }

  expect(hits, isEmpty, reason: 'forbidden reference(s):\n${hits.join('\n')}');
}
