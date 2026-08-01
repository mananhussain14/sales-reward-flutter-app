@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-safety assertions for the receipt extraction and confirmation
/// boundary.
///
/// The companion to `receipt_boundary_test.dart`, narrowed to the operations
/// that read a stored receipt image and write an immutable confirmation. These
/// read the source rather than exercise it, which makes them the cheapest guard
/// against the boundary eroding under deadline pressure — the kind of regression
/// a behavioural test cannot see, because the code that erodes it usually still
/// works.
void main() {
  late List<File> sources;
  late List<File> extractionSources;
  late String functionClient;
  late String rpcDataSource;

  String read(String suffix) => sources
      .firstWhere((File f) => f.path.endsWith(suffix))
      .readAsStringSync();

  /// The file's executable lines only.
  ///
  /// Every check below is about what the code *does*. The doc comments in this
  /// feature deliberately discuss what the code must not do — "no worker RPC",
  /// "no bucket name", "never persist the URL" — and a scan that could not tell
  /// the two apart would either fail on its own documentation or force the
  /// documentation to stop naming what it is protecting against.
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
    extractionSources = sources
        .where(
          (File f) =>
              f.path.contains('/features/receipts/') &&
              (f.path.contains('extraction') ||
                  f.path.contains('confirmation')),
        )
        .toList();
    functionClient = read('receipt_extraction_function_client.dart');
    rpcDataSource = read('receipt_extraction_rpc_data_source.dart');
  });

  test(
    'the extraction feature is non-empty (the scan would pass vacuously)',
    () {
      expect(extractionSources, isNotEmpty);
      expect(extractionSources.length, greaterThan(10));
    },
  );

  group('no privileged key reaches the device', () {
    test('no extraction source names a privileged or secret key', () {
      // The Edge Functions hold that key in their own environment. An APK is
      // trivially unpacked, so it may never appear in a mobile binary, in a
      // --dart-define, or in CI variables.
      _expectAbsent(extractionSources, <String>[
        'SUPABASE_SERVICE_ROLE_KEY',
        'service_role',
        'serviceRoleKey',
        'sb_secret_',
        'SERVICE_KEY',
      ]);
    });

    test('no extraction source reads an environment value of its own', () {
      for (final File file in extractionSources) {
        final String src = code(file);
        expect(
          src.contains('String.fromEnvironment'),
          isFalse,
          reason: file.path,
        );
        expect(
          src.contains('Platform.environment'),
          isFalse,
          reason: file.path,
        );
      }
    });

    test('neither runtime gate is expressed on the client', () {
      // Both gates live server-side, and no client input participates in
      // either decision. A constant here would be the beginning of a third,
      // client-side gate that could disagree with both.
      _expectAbsent(extractionSources, <String>[
        'RECEIPT_EXTRACTION_MODE',
        'RECEIPT_EXTRACTION_FIXTURE',
        'RECEIPT_EXTRACTION_FAKE_PENDING_MS',
        'receipt_extraction_runtime',
        "'FAKE'",
        "'DISABLED'",
      ], allowInComments: true);
    });
  });

  group('no direct extraction-table access', () {
    test('no extraction source builds a PostgREST table query', () {
      // All five tables carry RLS with zero policies and every privilege
      // revoked from the browser roles, so a direct read would return nothing
      // and the attempt to make it work is the first step toward putting a
      // privileged key on a device.
      _expectAbsent(extractionSources, <String>[
        '.from(',
        '.select(',
        '.insert(',
        '.update(',
        '.upsert(',
        '.delete(',
      ]);
    });

    test('no extraction source names one of the five tables in code', () {
      _expectAbsent(extractionSources, <String>[
        "'receipt_extractions'",
        '"receipt_extractions"',
        "'receipt_confirmations'",
        '"receipt_confirmations"',
        "'receipt_extraction_line_items'",
        "'receipt_extraction_runtime'",
        "'iso_currency_codes'",
        "'receipt_submissions'",
      ], allowInComments: true);
    });
  });

  group('the currency width comes from the backend and nowhere else', () {
    late List<File> currencySources;

    setUp(() {
      // The lookup lives in files whose paths do not all carry the word
      // `extraction`, so this group widens the scan to the whole receipts
      // feature rather than relying on the path filter above.
      currencySources = sources
          .where((File f) => f.path.contains('/features/receipts/'))
          .toList();
      expect(currencySources, isNotEmpty);
    });

    test('no receipt source names the seeded currency table', () {
      // It carries RLS with zero policies and no grant to the browser roles.
      // The lookup function reads it as its DEFINER and returns two values,
      // which is not the same thing as letting a device read the table.
      _expectAbsent(currencySources, <String>[
        "'iso_currency_codes'",
        '"iso_currency_codes"',
        '.from(',
      ], allowInComments: true);
    });

    test('no receipt source carries an ISO minor-unit map', () {
      // A second definition of every currency's width, free to drift from the
      // one the backend actually checks against — and the drift would be
      // silent, immutable and unrecoverable. The lookup exists so that this
      // cannot be tempting.
      for (final File file in currencySources) {
        final String src = code(file);
        for (final String pattern in <String>[
          "'JPY':",
          '"JPY":',
          "'KWD':",
          "'CLF':",
          "'EUR':",
          "'USD':",
        ]) {
          expect(
            src.contains(pattern),
            isFalse,
            reason: '${file.path} maps a currency code to a value',
          );
        }
      }
    });

    test('no receipt source keeps a two-decimal fallback', () {
      // The blocking defect. `defaultMinorDigits` was the name it went by, and
      // `minorDigitsFor` was the function that returned it for any currency the
      // backend had not spoken about.
      _expectAbsent(currencySources, <String>[
        'defaultMinorDigits',
        'minorDigitsFor',
      ], allowInComments: true);
    });

    test('the lookup names one RPC and one parameter', () {
      final String source = read('receipt_extraction_rpc_data_source.dart');

      expect(source.contains("'get_receipt_currency_minor_unit'"), isTrue);
      expect(source.contains("'p_currency_code'"), isTrue);
      // One code in, at most one row out. There is deliberately no list form.
      expect(source.contains('list_currencies'), isFalse);
      expect(source.contains('get_currencies'), isFalse);
    });
  });

  group('no worker capability exists on the client', () {
    test('no extraction source names a worker RPC', () {
      // All seven are granted to the privileged database role alone: a
      // browser-reachable claim would let anyone who learned an extraction id
      // take a job and write a result.
      _expectAbsent(extractionSources, <String>[
        'claim_receipt_extraction_job',
        'record_receipt_extraction_operation',
        'record_receipt_extraction_success',
        'record_receipt_extraction_failure',
        'expire_stale_receipt_extraction_claims',
        'get_receipt_object_reference',
        'get_receipt_extraction_worker_state',
      ], allowInComments: true);
    });

    test('no extraction source names a worker-only concept', () {
      _expectAbsent(extractionSources, <String>[
        'worker_claim_token',
        'claimToken',
        'provider_operation_id',
        'providerOperationId',
        'provider_model',
      ], allowInComments: true);
    });

    test('no stored failure code is representable', () {
      // Ten are stored; a client is shown three. Naming a stored code here
      // would be the availability oracle the mapping exists to remove.
      _expectAbsent(extractionSources, <String>[
        'PROVIDER_UNAVAILABLE',
        'PROVIDER_QUOTA_EXCEEDED',
        'PROVIDER_TIMEOUT',
        'PROVIDER_REJECTED_DOCUMENT',
        'OBJECT_UNREADABLE',
        'UNSUPPORTED_IMAGE',
        'NORMALIZATION_FAILED',
        'WORKER_ABANDONED',
        'NEVER_CLAIMED',
      ], allowInComments: true);
    });
  });

  group('no storage access, and nothing is persisted', () {
    test('no extraction source touches Storage', () {
      _expectAbsent(extractionSources, <String>[
        'storage.from(',
        '.storage',
        'uploadBinary(',
        'getPublicUrl',
        'StorageFileApi',
        'storage_bucket',
        'storage_object_path',
      ]);
    });

    test(
      'the preview URL is never written anywhere that outlives the screen',
      () {
        // The URL is a fetch credential with a 120-second life. Persisting it —
        // to disk, to a log, or to an image-cache key — extends the credential
        // past the only thing that bounds it.
        _expectAbsent(extractionSources, <String>[
          'writeAsBytes',
          'writeAsString',
          'getTemporaryDirectory',
          'getApplicationDocumentsDirectory',
          'SharedPreferences',
          'cacheKey',
          'debugPrint',
          'print(',
          'log(',
        ], allowInComments: true);
      },
    );

    test(
      'the preview value object keeps its URL out of equality and toString',
      () {
        final String preview = read('receipt_image_preview.dart');

        // `props` must not list the url, and toString must not interpolate it.
        expect(
          RegExp(
            r'props => <Object\?>\[\s*expiresInSeconds,?\s*\]',
          ).hasMatch(preview),
          isTrue,
          reason: 'the preview URL must not participate in equality',
        );
        expect(preview.contains(r'$url'), isFalse);
      },
    );
  });

  group('the Edge Function contract', () {
    test('exactly three function names are declared, and they are the deployed '
        'ones', () {
      final List<String> names = RegExp(
        r"^const String \w+Function = '([^']+)'",
        multiLine: true,
      ).allMatches(functionClient).map((RegExpMatch m) => m.group(1)!).toList();

      expect(names, <String>[
        'request-receipt-extraction',
        'get-receipt-extraction',
        'receipt-image-preview',
      ]);
    });

    test(
      'the request body is built from one declared field and nothing else',
      () {
        // Assert the construction itself rather than the absence of words: the
        // body map must name the one allowlisted constant, so a second key
        // cannot be introduced without this test seeing it.
        final List<String> fields =
            RegExp(
                  r"^const String extraction\w+Field = '([^']+)'",
                  multiLine: true,
                )
                .allMatches(functionClient)
                .map((RegExpMatch m) => m.group(1)!)
                .toList();

        expect(fields, <String>['submission_id']);
        expect(
          RegExp(
            r'<String, Object\?>\{extractionSubmissionIdField: submissionId\}',
          ).hasMatch(functionClient),
          isTrue,
        );
      },
    );

    test('no forbidden value can travel in the body', () {
      final String src = code(
        sources.firstWhere(
          (File f) =>
              f.path.endsWith('receipt_extraction_function_client.dart'),
        ),
      );

      for (final String forbidden in <String>[
        'user_id',
        'p_user',
        'profile_id',
        'organization_id',
        'retailer_id',
        'membership_id',
        'role_code',
        'permission_code',
        'shop_id',
        'extraction_id',
        'entry_mode',
        'changed_fields',
        'file_sha256',
        "'email'",
        'access_token',
        'tenant',
      ]) {
        expect(
          src.contains(forbidden),
          isFalse,
          reason: 'the extraction endpoints must carry no $forbidden',
        );
      }
    });
  });

  group('the RPC contract', () {
    test('exactly four RPCs are named, and they are authenticated ones', () {
      final List<String> names =
          RegExp(r"^const String \w+Rpc =\s*'([^']+)'", multiLine: true)
              .allMatches(rpcDataSource.replaceAll('\n    ', ' '))
              .map((RegExpMatch m) => m.group(1)!)
              .toList();

      expect(names, <String>[
        'list_my_receipt_extraction_line_items',
        'confirm_receipt_extraction',
        'get_my_receipt_confirmation',
        'get_receipt_currency_minor_unit',
      ]);
    });

    test(
      'the RPC data source passes only p_submission_id and p_currency_code',
      () {
        final RegExp params = RegExp(r"'(p_[a-z_]+)'");
        final Set<String> named = params
            .allMatches(rpcDataSource)
            .map((RegExpMatch m) => m.group(1)!)
            .toSet();

        // The confirmation's ten parameters are named in the request-body module
        // and asserted there; this boundary passes an already-encoded map. The
        // currency lookup takes one code and no identity beside it.
        expect(named, <String>{'p_submission_id', 'p_currency_code'});
      },
    );

    test('the confirmation body declares exactly the ten RPC parameters', () {
      final List<String> declared =
          RegExp(
                r"^const String confirmation\w+Parameter =\s*'([^']+)'",
                multiLine: true,
              )
              .allMatches(
                read(
                  'receipt_confirmation_request_body.dart',
                ).replaceAll('\n    ', ' '),
              )
              .map((RegExpMatch m) => m.group(1)!)
              .toList();

      expect(declared, <String>[
        'p_submission_id',
        'p_transaction_date',
        'p_currency_code',
        'p_currency_minor_unit',
        'p_total_minor',
        'p_merchant_name',
        'p_document_number',
        'p_transaction_time',
        'p_subtotal_minor',
        'p_tax_total_minor',
      ]);
    });

    test('no forbidden argument name appears near the call sites', () {
      for (final String forbidden in <String>[
        'user_id',
        'p_user',
        'p_profile',
        'p_organization',
        'p_retailer',
        'p_shop',
        'p_extraction_id',
        'p_entry_mode',
        'p_changed_fields',
        'p_mode',
        'p_provider',
        'p_claim_token',
        'role_code',
        'permission_code',
        'access_token',
      ]) {
        expect(
          code(
            sources.firstWhere(
              (File f) =>
                  f.path.endsWith('receipt_extraction_rpc_data_source.dart'),
            ),
          ).contains(forbidden),
          isFalse,
          reason: 'the extraction RPCs must pass no $forbidden argument',
        );
      }
    });
  });

  group('no role, permission or provider is decided on the client', () {
    test('no extraction source names a permission or role code', () {
      _expectAbsent(extractionSources, <String>[
        'RECEIPT_EXTRACTION_REVIEW',
        'RECEIPT_SUBMIT',
        'SALES_STAFF',
        'RETAILER_OWNER',
        'VENDOR_SUPER_ADMIN',
        'resolve_retailer_member_organization',
        'assert_my_receipt_extraction_access',
      ], allowInComments: true);
    });

    test('no extraction source names a document service', () {
      // There is no real provider in this milestone, and no provider endpoint,
      // credential, SDK, region or service name belongs in a mobile binary in
      // any milestone.
      _expectAbsent(extractionSources, <String>[
        'Azure',
        'azure',
        'cognitiveservices',
        'formrecognizer',
        'documentintelligence',
        'openai',
        'textract',
      ], allowInComments: true);
    });

    test('no extraction source computes a reward, claim or incentive', () {
      _expectAbsent(extractionSources, <String>[
        'reward',
        'Reward',
        'incentive',
        'Incentive',
        'campaign',
        'Campaign',
        'coin',
        'Coin',
        'payout',
      ], allowInComments: true);
    });
  });

  group('layering', () {
    test('the domain layer depends on no SDK or transport package', () {
      final Iterable<File> domain = extractionSources.where(
        (File f) => f.path.contains('/domain/'),
      );
      expect(domain, isNotEmpty);

      for (final File file in domain) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'package:supabase_flutter',
          'package:http',
          'package:flutter/',
          'dart:io',
          'dart:convert',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} imports $forbidden',
          );
        }
      }
    });

    test('the Supabase SDK appears only in the data layer', () {
      for (final File file in extractionSources) {
        if (file.path.contains('/data/')) continue;
        expect(
          code(file).contains('package:supabase_flutter'),
          isFalse,
          reason: '${file.path} imports the Supabase SDK',
        );
      }
    });

    test('no extraction source carries a raw untyped map past the parser', () {
      final Iterable<File> beyondTheBoundary = extractionSources.where(
        (File f) =>
            f.path.contains('/domain/') || f.path.contains('/presentation/'),
      );
      expect(beyondTheBoundary, isNotEmpty);

      for (final File file in beyondTheBoundary) {
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
