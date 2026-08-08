@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-safety assertions for the receipt-submission boundary.
///
/// The companion to `no_secrets_test.dart`, narrowed to the one feature that
/// uploads bytes to a privileged endpoint. These read the source rather than
/// exercise it, which makes them the cheapest guard against the boundary
/// eroding under deadline pressure — the kind of regression a behavioural test
/// cannot see, because the code that erodes it usually still works.
void main() {
  late List<File> sources;
  late List<File> receiptSources;
  late String functionClient;
  late String rpcDataSource;

  String read(String suffix) => sources
      .firstWhere((File f) => f.path.endsWith(suffix))
      .readAsStringSync();

  /// The file's executable lines only.
  ///
  /// Every check below is about what the code *does*. The doc comments in this
  /// feature deliberately discuss the things the code must not do — "no
  /// service-role key", "never `storage.from`", "`package:http` exposes no
  /// upload progress" — and a scan that could not tell the two apart would
  /// either fail on its own documentation or force the documentation to stop
  /// naming what it is protecting against.
  String code(File file) => file
      .readAsLinesSync()
      .where((String line) {
        final String trimmed = line.trimLeft();
        return !trimmed.startsWith('//') && !trimmed.startsWith('*');
      })
      .join('\n');

  setUpAll(() {
    sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .toList();
    receiptSources = sources
        .where((File f) => f.path.contains('/features/receipts/'))
        .toList();
    functionClient = read('submit_receipt_function_client.dart');
    rpcDataSource = read('receipt_rpc_data_source.dart');
  });

  test('the receipt feature is non-empty (the scan would pass vacuously)', () {
    expect(receiptSources, isNotEmpty);
    expect(receiptSources.length, greaterThan(10));
  });

  group('no privileged key reaches the device', () {
    test('no receipt source names a service-role or secret key', () {
      // The Edge Function holds that key in its own environment. An APK is
      // trivially unpacked, so it may never appear in a mobile binary, in a
      // --dart-define, or in CI variables.
      _expectAbsent(receiptSources, <String>[
        'SUPABASE_SERVICE_ROLE_KEY',
        'service_role',
        'serviceRoleKey',
        'sb_secret_',
        'SERVICE_KEY',
      ]);
    });

    test('the function client reads no environment value of its own', () {
      // Configuration is supplied by the injector from AppConfig, which is the
      // single place a dart-define is read.
      expect(functionClient.contains('String.fromEnvironment'), isFalse);
      expect(functionClient.contains('Platform.environment'), isFalse);
    });

    test('no receipt source hardcodes a credential', () {
      _expectAbsent(receiptSources, <String>[
        'Bearer sb_',
        'Bearer ey',
        "password: '",
        'apikey: "',
      ]);
    });
  });

  group('no direct Storage access', () {
    test('no receipt source touches a Storage bucket', () {
      // `storage.objects` carries RLS with zero policies, so a client-side write
      // cannot work — and an attempt to add one is the signal that a privileged
      // key is about to follow it.
      _expectAbsent(receiptSources, <String>[
        'storage.from(',
        '.upload(',
        'uploadBinary(',
        'createSignedUrl',
        'getPublicUrl',
        'StorageFileApi',
      ]);
    });

    test('no receipt source names the bucket or builds an object path', () {
      _expectAbsent(receiptSources, <String>[
        "'receipts'",
        '"receipts"',
        'storage_bucket',
        'storage_object_path',
        'objectPath',
      ], allowInComments: true);
    });
  });

  group('the client chooses nothing the backend derives', () {
    test('the multipart request declares exactly two field names', () {
      // Grep the literals rather than trusting the comment above them.
      final RegExp fieldConstants = RegExp(
        r"const String submitReceipt\w+Field = '([^']+)'",
      );
      final List<String> fields = fieldConstants
          .allMatches(functionClient)
          .map((RegExpMatch m) => m.group(1)!)
          .toList();

      expect(fields, <String>['shop_id', 'file']);
    });

    test('the request is built from those two constants and nothing else', () {
      // Assert the construction itself rather than the absence of words: every
      // `fields[...] =` and every `files.add(...)` must name one of the two
      // declared constants, so a new field cannot be introduced without this
      // test seeing it.
      final List<String> fieldKeys = RegExp(r'\.\.fields\[([^\]]+)\]')
          .allMatches(functionClient)
          .map((RegExpMatch m) => m.group(1)!.trim())
          .toList();
      final List<String> filePartNames = RegExp(
        r'http\.MultipartFile\.fromBytes\(\s*([A-Za-z]+)',
      ).allMatches(functionClient).map((RegExpMatch m) => m.group(1)!).toList();

      expect(fieldKeys, <String>['submitReceiptShopIdField']);
      expect(filePartNames, <String>['submitReceiptFileField']);
      // Exactly one file part is ever added.
      expect(
        RegExp(r'\.\.files\.add\(').allMatches(functionClient),
        hasLength(1),
      );
    });

    test('only two headers are set, and neither is privileged', () {
      final List<String> headerKeys = RegExp(
        r"\.\.headers\['([^']+)'\]",
      ).allMatches(functionClient).map((RegExpMatch m) => m.group(1)!).toList();

      expect(headerKeys, <String>['Authorization', 'apikey']);
    });

    test('no receipt source computes a hash', () {
      // The SHA-256 is computed by the server over the bytes it actually
      // receives. A client-side hash would be either redundant or, worse, a
      // second definition of "the same receipt".
      _expectAbsent(receiptSources, <String>[
        'sha256',
        'Sha256',
        'crypto.',
        'package:crypto',
        'md5',
      ], allowInComments: true);
    });

    test('the app declares no hashing or persistence dependency', () {
      final String pubspec = File('pubspec.yaml').readAsStringSync();
      for (final String forbidden in <String>[
        'crypto:',
        'path_provider:',
        'shared_preferences:',
        'hive:',
        'sqflite:',
      ]) {
        expect(
          pubspec.contains(forbidden),
          isFalse,
          reason: 'pubspec.yaml declares $forbidden',
        );
      }
    });

    test('no receipt source carries a shop id of its own', () {
      // The submission cubit now selects a shop for the caller when they have
      // exactly one. That convenience must never become a *source* of shop ids:
      // the only id this client may hold is one `list_my_assigned_receipt_shops`
      // just returned, and a literal UUID anywhere in the feature would mean
      // somebody had introduced a second one.
      final RegExp uuid = RegExp(
        r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
        r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
      );
      for (final File file in receiptSources) {
        expect(
          uuid.hasMatch(code(file)),
          isFalse,
          reason: '${file.path} hardcodes an id',
        );
      }
    });

    test('the automatic selection reads the id off the loaded list', () {
      final String cubit = code(
        sources.firstWhere(
          (File f) => f.path.endsWith('receipt_submission_cubit.dart'),
        ),
      );

      // The auto-selection takes the id from the single element of the RPC's
      // own result, so there is no path by which a shop the backend did not
      // return could be selected — and `reserve_receipt_submission` re-proves
      // the assignment under the caller's token regardless.
      expect(cubit.contains('value.single.shopId'), isTrue);
    });

    test('no receipt source assigns a submission status', () {
      // The three status tokens may be *recognised* — that is what the parser
      // does — but never assembled into a value the client sends.
      final String outcome = read('receipt_submission_outcome.dart');
      expect(outcome.contains('SUBMITTED'), isFalse);
      expect(functionClient.contains('SUBMITTED'), isFalse);
      expect(functionClient.contains('RESERVED'), isFalse);
    });
  });

  group('the RPC contract', () {
    test('only p_submission_id is ever passed to an RPC', () {
      final RegExp params = RegExp(r"'(p_[a-z_]+)'");
      final Set<String> named = params
          .allMatches(rpcDataSource)
          .map((RegExpMatch m) => m.group(1)!)
          .toSet();

      expect(named, <String>{'p_submission_id'});
    });

    test('no forbidden argument name appears near the call sites', () {
      final String rpcCode = code(
        sources.firstWhere(
          (File f) => f.path.endsWith('receipt_rpc_data_source.dart'),
        ),
      );
      for (final String forbidden in <String>[
        'user_id',
        'p_user',
        'profile_id',
        'organization_id',
        'p_organization',
        'retailer_id',
        'membership_id',
        'role_code',
        'permission_code',
        "'email'",
        'access_token',
        'tenant',
      ]) {
        expect(
          rpcCode.contains(forbidden),
          isFalse,
          reason: 'the receipt RPCs must pass no $forbidden argument',
        );
      }
    });
  });

  group('no role or permission is decided on the client', () {
    test('no receipt source names a permission code', () {
      // Which permission gates which operation is a decision that lives in seed
      // data. A client-side comparison would be a second, drifting definition.
      _expectAbsent(receiptSources, <String>[
        'RECEIPT_SUBMIT',
        'RECEIPT_PRODUCTS_READ',
        'RETAILER_PRODUCTS_READ',
      ], allowInComments: true);
    });

    test('no receipt source infers a role from an email or metadata', () {
      for (final File file in receiptSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'userMetadata',
          'appMetadata',
          'user_metadata',
          'app_metadata',
          'SharedPreferences',
          '.decodeJwt',
          'jwtDecode',
          'endsWith(\'@',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} infers authority from $forbidden',
          );
        }
      }
    });

    test('the capability hint is not used to gate the submission', () {
      // `submit_receipts` may hide a navigation destination. It must never be
      // consulted to decide whether a write is permitted — the database and the
      // Edge Function decide that, again, on every call.
      for (final File file in receiptSources) {
        expect(
          code(file).contains('submitReceipts'),
          isFalse,
          reason: '${file.path} reads a capability hint',
        );
      }
    });
  });

  group('layering', () {
    test('presentation never touches Supabase directly', () {
      final Iterable<File> presentation = receiptSources.where(
        (File f) => f.path.contains('/presentation/'),
      );
      expect(presentation, isNotEmpty);

      for (final File file in presentation) {
        final String src = code(file);
        expect(
          src.contains('Supabase.instance'),
          isFalse,
          reason: '${file.path} reaches Supabase directly',
        );
        expect(
          src.contains('package:supabase_flutter'),
          isFalse,
          reason: '${file.path} imports the Supabase SDK',
        );
        expect(
          src.contains('package:http'),
          isFalse,
          reason: '${file.path} performs its own HTTP',
        );
      }
    });

    test('the domain layer depends on no SDK, transport or picker package', () {
      final Iterable<File> domain = receiptSources.where(
        (File f) => f.path.contains('/domain/'),
      );
      expect(domain, isNotEmpty);

      for (final File file in domain) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'package:supabase_flutter',
          'package:http',
          'package:image_picker',
          'package:flutter/',
          'dart:io',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} imports $forbidden',
          );
        }
      }
    });

    test('no BLoC state holds a raw backend map', () {
      final Iterable<File> cubits = receiptSources.where(
        (File f) => f.path.contains('/cubit/'),
      );
      expect(cubits, isNotEmpty);

      for (final File file in cubits) {
        final String src = code(file);
        expect(
          src.contains('Map<String, dynamic>'),
          isFalse,
          reason: '${file.path} holds a raw SDK map',
        );
        expect(
          RegExp(r'\bdynamic\b').hasMatch(src),
          isFalse,
          reason: '${file.path} holds an untyped value',
        );
      }
    });
  });

  group('nothing is persisted', () {
    test('no receipt source writes a file or opens local storage', () {
      // A receipt is the business's record, not the device's. A private image
      // left behind on a shared shop-floor phone is a leak with no upside.
      _expectAbsent(receiptSources, <String>[
        'writeAsBytes',
        'writeAsString',
        'getTemporaryDirectory',
        'getApplicationDocumentsDirectory',
        'path_provider',
        'dart:io',
        'Hive',
        'sqflite',
      ], allowInComments: true);
    });

    test('no receipt image is tracked in the repository', () {
      final ProcessResult result = Process.runSync('git', <String>['ls-files']);
      final List<String> tracked = (result.stdout as String).split('\n');

      const List<String> imageExtensions = <String>[
        '.jpg',
        '.jpeg',
        '.png',
        '.webp',
        '.heic',
      ];
      // The platform launcher icons and the web favicon are generated by
      // `flutter create` and are the only images this repository legitimately
      // tracks. Anything else — above all under lib/, test/ or assets/ — would
      // be a captured receipt.
      const List<String> generatedIcons = <String>[
        'android/app/src/',
        'ios/Runner/Assets.xcassets/',
        'web/icons/',
        'web/favicon.png',
      ];
      final Iterable<String> images = tracked.where((String path) {
        final bool isImage = imageExtensions.any(
          (String ext) => path.toLowerCase().endsWith(ext),
        );
        return isImage &&
            !generatedIcons.any((String prefix) => path.startsWith(prefix));
      });

      expect(
        images,
        isEmpty,
        reason:
            'a receipt image must never be committed:\n${images.join('\n')}',
      );
    });

    test('no image data or privileged key is embedded in configuration', () {
      // A base64 blob or a data URI in a config file is how a "temporary" test
      // fixture becomes a committed receipt.
      final RegExp base64Blob = RegExp('[A-Za-z0-9+/]{200,}={0,2}');

      for (final String path in <String>[
        'pubspec.yaml',
        'dart_defines.example.json',
        'analysis_options.yaml',
      ]) {
        final File file = File(path);
        if (!file.existsSync()) continue;
        final String src = file.readAsStringSync();

        expect(
          base64Blob.hasMatch(src),
          isFalse,
          reason: '$path embeds encoded binary data',
        );
        expect(
          src.contains('data:image/'),
          isFalse,
          reason: '$path embeds an image',
        );
        expect(
          src.contains('service_role') || src.contains('sb_secret_'),
          isFalse,
          reason: '$path names a privileged key',
        );
      }
    });
  });
}

/// Fails if any [needle] appears in executable source.
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
          (trimmed.startsWith('//') ||
              trimmed.startsWith('*') ||
              trimmed.startsWith('///'))) {
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
