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

  test('no source hardcodes a login credential', () {
    // No demo email/password, no seeded token. A credential in the binary is a
    // credential in every user's hands.
    _expectAbsent(
      sources,
      <String>['sb_secret_', 'password:'],
      allowInComments: true,
      allowNamedParams: true,
    );
  });

  test('the portal-context RPC is called with no identity arguments', () {
    // The RPC derives identity from auth.uid(). The data source models it as a
    // nullary invoker, so an argument cannot be expressed — but assert directly
    // that no forbidden parameter name appears near the call site.
    final File dataSource = sources.firstWhere(
      (File f) => f.path.endsWith('portal_context_data_source.dart'),
    );
    final String src = dataSource.readAsStringSync();
    for (final String forbidden in <String>[
      'user_id',
      'p_user',
      'organization_id',
      'p_organization',
      'retailer_id',
      'membership_id',
      'role_code',
      "'email'",
      'access_token',
      'tenant',
    ]) {
      expect(
        src.contains(forbidden),
        isFalse,
        reason: 'the RPC call must pass no $forbidden argument',
      );
    }
  });

  test('the presentation layer never touches Supabase.instance directly', () {
    // Data access is confined to the data layer. A widget or bloc reaching for
    // the client would route around the repository boundary.
    final Iterable<File> presentation = sources.where(
      (File f) =>
          f.path.contains('/presentation/') || f.path.contains('/shells/'),
    );
    for (final File file in presentation) {
      expect(
        file.readAsStringSync().contains('Supabase.instance'),
        isFalse,
        reason: '${file.path} reaches Supabase directly',
      );
    }
  });

  test('no source outside the data layer imports the Supabase SDK', () {
    final Iterable<File> offenders = sources.where((File f) {
      if (f.path.contains('/data/') || f.path.endsWith('bootstrap.dart')) {
        return false; // the data layer and the one init call may.
      }
      // The DI injector wires the client into the data layer; allow it.
      if (f.path.endsWith('injector.dart')) return false;
      // The failure mapper is the one seam that classifies SDK exception types
      // into the shared Failure union — a data-adjacent boundary by design.
      if (f.path.endsWith('failure_mapper.dart')) return false;
      // The Retailer read classifier is the same kind of seam, for the same
      // reason: it turns SDK exception *types* and SQLSTATEs into a
      // discriminant, reads no message, and lets no Supabase type travel
      // onward. It lives in core rather than in one feature's data layer
      // because Shops, Staff and Products all share it — the alternative was
      // three copies of the same classification, which is worse.
      if (f.path.endsWith('retailer_read_problem.dart')) return false;
      return f.readAsStringSync().contains("package:supabase_flutter");
    });
    expect(
      offenders.map((File f) => f.path),
      isEmpty,
      reason: 'Supabase types must stay in the data layer',
    );
  });

  test('no source disables TLS validation', () {
    // The debugging reflex when a mobile HTTPS call fails is to trust every
    // certificate and move on. It would have "fixed" nothing here — the release
    // build could not open a socket at all — and it would have shipped a client
    // that accepts any interceptor's certificate.
    _expectAbsent(sources, <String>[
      'badCertificateCallback',
      'allowBadCertificates',
      'HttpOverrides',
      'onBadCertificate',
    ], allowInComments: true);
  });

  test('no source forces cleartext HTTP', () {
    _expectAbsent(sources, <String>[
      'usesCleartextTraffic',
      "http://'",
      'http://10.0.2.2',
      'http://localhost',
      'http://127.0.0.1',
    ], allowInComments: true);
  });

  test('the configured Supabase URL is not a local endpoint', () {
    // A local Supabase reaches nothing from a physical device, and 10.0.2.2 is
    // an emulator-only alias. Neither belongs in a build that gets installed.
    const String url = String.fromEnvironment('SUPABASE_URL');
    if (url.isEmpty) {
      // `flutter test` runs without --dart-define-from-file, which is fine.
      return;
    }
    for (final String local in <String>[
      'localhost',
      '127.0.0.1',
      '10.0.2.2',
      '0.0.0.0',
    ]) {
      expect(
        url.contains(local),
        isFalse,
        reason: 'SUPABASE_URL must address the hosted project',
      );
    }
    expect(url.startsWith('https://'), isTrue);
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
  bool allowNamedParams = false,
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
        if (!line.contains(needle)) continue;
        // `password:` is a legitimate Dart named parameter (signInWithPassword,
        // AuthUser fields). Only a string LITERAL assigned to it would be a
        // hardcoded credential, and there is none.
        if (allowNamedParams &&
            needle == 'password:' &&
            !RegExp("password:\\s*'").hasMatch(line)) {
          continue;
        }
        hits.add('${file.path}:${i + 1} → $needle');
      }
    }
  }

  expect(hits, isEmpty, reason: 'forbidden reference(s):\n${hits.join('\n')}');
}
