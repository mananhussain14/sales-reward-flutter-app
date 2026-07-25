@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-safety assertions for the Vendor Audit Log read boundary.
///
/// The companion to `no_secrets_test.dart`, `receipt_boundary_test.dart`,
/// `vendor_retailer_boundary_test.dart`, `vendor_user_boundary_test.dart`,
/// `vendor_role_boundary_test.dart` and `vendor_product_boundary_test.dart`.
/// These read the source rather than exercise it, which makes them the cheapest
/// guard against the boundary eroding under deadline pressure — the kind of
/// regression a behavioural test cannot see, because the code that erodes it
/// usually still works.
///
/// `public.audit_logs` is the most sensitive table in the schema, and unlike the
/// product tables it grants `authenticated` a real `SELECT`. A direct read here
/// would therefore **work**, which is precisely why these assertions exist
/// rather than being left to the database to enforce.
///
/// Seven properties are defended, stated once each:
///
/// * **The client never decides which Vendor it is.** The read derives the
///   Vendor from `auth.uid()` and takes no tenant argument.
/// * **The client never reads a protected table.** Not `audit_logs`, not
///   `profiles`, not `organization_members`, not `organizations`, not
///   `auth.users`.
/// * **The client never touches metadata.** The five whitelisted name snapshots
///   are extracted in SQL; the raw object never leaves the database.
/// * **The client never handles an identifier it was not given.** No
///   `entity_id`, no `actor_profile_id`, no `organization_id`.
/// * **The client never handles personal network data.** No `ip_address`, no
///   `user_agent`, no email, no phone.
/// * **The client never writes, and never offers a detail, export or
///   navigation affordance**, because none of those exists to offer.
/// * **The cursor is ordering data, never authority**, and is never invented.
void main() {
  late List<File> sources;
  late List<File> auditSources;
  late String rpcDataSource;

  /// The file's executable lines only.
  ///
  /// Every check below is about what the code *does*. The doc comments in this
  /// feature deliberately discuss the things the code must not do — "metadata is
  /// never returned", "`entity_id` is deliberately not returned", "never a bare
  /// System" — and a scan that could not tell the two apart would either fail on
  /// its own documentation or force the documentation to stop naming what it is
  /// protecting against.
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
    auditSources = sources
        .where((File f) => f.path.contains('/features/audit/'))
        .toList();
    rpcDataSource = code(
      sources.firstWhere(
        (File f) => f.path.endsWith('vendor_audit_log_rpc_data_source.dart'),
      ),
    );
  });

  test('the feature is non-empty (the scan would pass vacuously)', () {
    expect(auditSources, isNotEmpty);
    expect(auditSources.length, greaterThan(8));
  });

  group('no privileged key reaches the device', () {
    test('no source names a service-role or secret key', () {
      _expectAbsent(auditSources, <String>[
        'SUPABASE_SERVICE_ROLE_KEY',
        'service_role',
        'serviceRoleKey',
        'sb_secret_',
        'SERVICE_KEY',
      ]);
    });

    test('no source reads an environment value of its own', () {
      for (final File file in auditSources) {
        final String src = code(file);
        expect(src.contains('String.fromEnvironment'), isFalse);
        expect(src.contains('Platform.environment'), isFalse);
      }
    });

    test('no source hardcodes a credential', () {
      _expectAbsent(auditSources, <String>[
        'Bearer sb_',
        'Bearer ey',
        "password: '",
        'apikey',
      ]);
    });

    test('dart_defines.json is ignored and not tracked by git', () {
      expect(
        File('.gitignore').readAsStringSync().contains('dart_defines.json'),
        isTrue,
      );

      final ProcessResult tracked = Process.runSync('git', <String>[
        'ls-files',
        'dart_defines.json',
      ]);
      expect((tracked.stdout as String).trim(), isEmpty);
    });
  });

  group('the RPC contract', () {
    test('exactly three parameter names exist in the feature', () {
      final RegExp params = RegExp(r"'(p_[a-z_]+)'");
      final Set<String> named = params
          .allMatches(rpcDataSource)
          .map((RegExpMatch m) => m.group(1)!)
          .toSet();

      expect(named, <String>{
        'p_limit',
        'p_before_occurred_at',
        'p_before_audit_log_id',
      });
    });

    test('only the one deployed function is named', () {
      final RegExp rpcNames = RegExp(r"const String \w+Rpc =\s*'([^']+)'");
      final List<String> names = rpcNames
          .allMatches(rpcDataSource)
          .map((RegExpMatch m) => m.group(1)!)
          .toList();

      expect(names, <String>['list_vendor_audit_logs']);
    });

    test('no identity, tenant, role, permission or filter argument', () {
      for (final String forbidden in <String>[
        'user_id',
        'p_user',
        'auth_user_id',
        'profile_id',
        'p_profile',
        'membership_id',
        'p_membership',
        'p_vendor',
        'vendor_organization_id',
        'organization_id',
        'p_organization',
        'p_tenant',
        'p_role',
        'role_code',
        'permission_code',
        'p_permission',
        'p_actor',
        'p_entity',
        'p_action',
        'p_search',
        'p_from',
        'p_to',
        "'email'",
        'access_token',
        'tenant',
      ]) {
        expect(
          rpcDataSource.contains(forbidden),
          isFalse,
          reason: 'the Vendor Audit Log RPC must pass no $forbidden argument',
        );
      }
    });

    test('no offset or page-number argument anywhere in the feature', () {
      // Keyset only. An offset re-walks N rows per page on an append-only table
      // that grows forever, and one new event between pages shifts every
      // subsequent window.
      _expectAbsent(auditSources, <String>[
        'p_offset',
        'p_page',
        'offset:',
        'pageNumber',
        'pageIndex',
        'currentPage',
        '.skip(',
      ], allowInComments: true);
    });

    test('the page size is a fixed constant inside the backend range', () {
      final File source = auditSources.firstWhere(
        (File f) => f.path.endsWith('vendor_audit_log_rpc_data_source.dart'),
      );

      expect(
        code(source).contains('const int vendorAuditLogPageSize = 50;'),
        isTrue,
      );

      // Assigned exactly once, in that declaration. No screen, cubit or
      // repository may choose a page size of its own, and no literal other than
      // the constant may reach the limit parameter.
      final int assignments = auditSources
          .map(code)
          .expand(
            (String src) =>
                RegExp(r'vendorAuditLogPageSize\s*=(?!=)').allMatches(src),
          )
          .length;
      expect(assignments, 1);

      // The only value that reaches the limit parameter is the invoker's own
      // argument, and the only value passed for it is the constant.
      expect(rpcDataSource.contains('auditLimitParameter: limit,'), isTrue);
      expect(
        RegExp(r'limit: vendorAuditLogPageSize,').allMatches(rpcDataSource),
        hasLength(2),
      );
      expect(RegExp(r'limit:\s*\d').hasMatch(rpcDataSource), isFalse);
    });

    test('the cursor type makes a half cursor unrepresentable', () {
      final File entity = auditSources.firstWhere(
        (File f) => f.path.endsWith('vendor_audit_log_entry.dart'),
      );
      final String src = code(entity);

      // Two non-nullable fields, so "a timestamp with no id" cannot be built.
      expect(
        src.contains(
          'typedef VendorAuditLogCursor = ({DateTime occurredAt, '
          'String auditLogId});',
        ),
        isTrue,
      );
      expect(src.contains('DateTime? occurredAt'), isFalse);
      expect(src.contains('String? auditLogId'), isFalse);
    });

    test('the cursor is taken from a row and never synthesised', () {
      for (final File file in auditSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'DateTime.now()',
          'subtract(',
          'add(const Duration',
          'microsecondsSinceEpoch',
          'millisecondsSinceEpoch',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} adjusts or invents a cursor value',
          );
        }
      }
    });
  });

  group('no table is read directly', () {
    test('no source queries audit, profile, membership or org tables', () {
      // `authenticated` DOES hold SELECT on audit_logs, so this would work — and
      // `select *` there would carry metadata, entity_id, ip_address, user_agent
      // and actor_profile_id (THE AUTH USER ID) to a phone, while moving the
      // actor join and the keyset tie-break into Dart.
      _expectAbsent(auditSources, <String>[
        '.from(',
        "'audit_logs'",
        "'profiles'",
        "'organization_members'",
        "'organizations'",
        "'member_roles'",
        '.select(',
        '.eq(',
        '.lt(',
        '.gt(',
        '.order(',
        '.range(',
        '.limit(',
        '.in_(',
        '.maybeSingle(',
      ], allowInComments: true);
    });

    test('nothing anywhere touches auth.users', () {
      _expectAbsent(auditSources, <String>[
        'auth.users',
        'auth_users',
        'authUsers',
        '.admin.',
        'getUserById',
        'listUsers',
      ], allowInComments: true);
    });

    test('the actor join is not reimplemented', () {
      // Resolving a name through a membership of the audit row's own Vendor is a
      // privacy boundary decided in SQL. A second resolver here would be a
      // second definition free to drift, and only one of the two could be right.
      for (final File file in auditSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'resolveActor',
          'lookupActor',
          'actorNameFor',
          'fetchProfile',
          'membershipFor',
          'resolveVendor',
          'isVendorSuperAdmin',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} reimplements the actor or Vendor resolution',
          );
        }
      }
    });
  });

  group('the withheld columns never appear', () {
    test('no source models metadata in any spelling', () {
      _expectAbsent(auditSources, <String>[
        'metadata',
        'rawMetadata',
        'auditMetadata',
        'jsonb',
        'oldValues',
        'newValues',
        'old_values',
        'new_values',
      ], allowInComments: true);
    });

    test('no source models an entity, actor or organization id', () {
      _expectAbsent(auditSources, <String>[
        'entityId',
        'entity_id',
        'actorProfileId',
        'actor_profile_id',
        'organizationId',
        'organization_id',
        'targetId',
        'target_id',
      ], allowInComments: true);
    });

    test('no source models an IP address or a user agent', () {
      // Never selected by the backend, not merely never rendered — and never
      // modelled here either, so a future refactor has nothing to surface.
      _expectAbsent(auditSources, <String>[
        'ipAddress',
        'ip_address',
        'userAgent',
        'user_agent',
        'deviceId',
        'sessionId',
      ], allowInComments: true);
    });

    test('no source models an email or a phone number', () {
      _expectAbsent(auditSources, <String>[
        'email',
        'Email',
        'mobileNumber',
        'mobile_number',
        'phoneNumber',
        'phone_number',
      ], allowInComments: true);
    });

    test('no source invents an outcome, severity or result field', () {
      // `public.audit_logs` has no such column. Outcome is encoded in the action
      // code itself where it is recorded at all.
      _expectAbsent(auditSources, <String>[
        'isSuccess',
        'succeeded',
        'outcome',
        'severity',
        'riskLevel',
        'isFailure',
        'wasDenied',
      ], allowInComments: true);
    });

    test('no source invents a total count', () {
      // Keyset paging returns none, and an exact COUNT over an append-only table
      // that grows forever is a full scan per page that is stale when computed.
      _expectAbsent(auditSources, <String>[
        'totalCount',
        'total_count',
        'totalEvents',
        'rowCount',
        'estimatedTotal',
      ], allowInComments: true);
    });
  });

  group('no authorization is decided on the client', () {
    test('no source names a permission or role code', () {
      // The backend requires BOTH Vendor Super Admin authority and the audit
      // read permission. That pair is enforced in SQL; this client knows
      // neither, and a denial is one generic answer.
      _expectAbsent(auditSources, <String>[
        'AUDIT_LOGS_READ',
        'AUDIT_LOGS',
        'RBAC_READ',
        'PRODUCTS_READ',
        'RETAILERS_READ',
        "'VENDOR_SUPER_ADMIN'",
        "'RETAILER_OWNER'",
        "'RETAILER_MANAGER'",
        "'SALES_STAFF'",
      ], allowInComments: true);
    });

    test('no source names a backend function, policy or SQLSTATE', () {
      _expectAbsent(auditSources, <String>[
        'has_organization_permission',
        'get_vendor_super_admin_context',
        'audit_logs_select_authorized',
        'SQLSTATE',
        '42501',
        '22023',
        '22P02',
      ], allowInComments: true);
    });

    test('no source hardcodes an identifier', () {
      final RegExp uuidLiteral = RegExp(
        r"'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
        r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'",
      );

      for (final File file in auditSources) {
        expect(
          uuidLiteral.hasMatch(code(file)),
          isFalse,
          reason: '${file.path} hardcodes an identifier',
        );
      }
    });

    test('no source infers authority from a token, claim or preference', () {
      for (final File file in auditSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'userMetadata',
          'appMetadata',
          'SharedPreferences',
          '.decodeJwt',
          'jwtDecode',
          "endsWith('@",
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} infers authority from $forbidden',
          );
        }
      }
    });

    test('a portal kind is read for its label and for nothing else', () {
      final RegExp anyUse = RegExp(r'PortalKind\.\w+(\.\w+)?');

      for (final File file in auditSources) {
        for (final RegExpMatch match in anyUse.allMatches(code(file))) {
          expect(
            match.group(0),
            'PortalKind.vendorSuperAdmin.displayName',
            reason:
                '${file.path} uses a portal kind for something other than its '
                'label',
          );
        }
      }
    });

    test('no route or affordance is gated on audit data', () {
      // An action code, an entity type and an actor type are display data.
      // Nothing may branch a route or an authorization decision on any of them.
      for (final File file in auditSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'canView',
          'canOpen',
          'isAuthorized',
          'hasAccess',
          'allowIf',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} computes access from audit data',
          );
        }
      }
    });
  });

  group('the actor wording is honest', () {
    test('SYSTEM is never rendered as a bare System', () {
      final File copy = auditSources.firstWhere(
        (File f) => f.path.endsWith('vendor_audit_log_copy.dart'),
      );
      final String src = code(copy);

      expect(src.contains("'System or unavailable actor'"), isTrue);
      // Each of these is a claim about who acted that the schema cannot support:
      // an event born without an actor and an event whose actor was deleted are
      // byte-identical here.
      for (final String forbidden in <String>[
        "= 'System'",
        'Automated system',
        'System process',
        'Deleted user',
        'Former user',
        'Removed user',
      ]) {
        expect(
          src.contains(forbidden),
          isFalse,
          reason: 'the copy overclaims what SYSTEM means: $forbidden',
        );
      }
    });

    test('an unknown actor type is never folded into a known one', () {
      final File actorType = auditSources.firstWhere(
        (File f) => f.path.endsWith('vendor_audit_actor_type.dart'),
      );
      final String src = code(actorType);

      // A positive test against a single member, so no future token can arrive
      // at "this has a name" by failing to match something else.
      expect(src.contains('carriesName => this == user'), isTrue);
      expect(src.contains('!= system'), isFalse);
      expect(src.contains('return user;'), isFalse);
      expect(src.contains('return unrecognized;'), isTrue);
    });

    test('no source fabricates an actor or entity name', () {
      for (final File file in auditSources) {
        final String src = code(file);
        for (final RegExp pattern in <RegExp>[
          // A fallback that substitutes a literal, or another field of the same
          // row, for a name the backend declined to send. Falling back to the
          // feature's own neutral wording is not on this list: that is what the
          // copy file exists for, and it names nobody.
          RegExp(r'''actorDisplayName\s*\?\?\s*['"]'''),
          RegExp(r'''entityDisplayName\s*\?\?\s*['"]'''),
          RegExp(r'actorDisplayName\s*\?\?\s*(entry|widget)\.'),
          RegExp(r'entityDisplayName\s*\?\?\s*(entry|widget)\.'),
          // A name assigned from a literal rather than read from the row.
          RegExp(r'''actorDisplayName\s*[:=]\s*['"]'''),
          RegExp(r'''entityDisplayName\s*[:=]\s*['"]'''),
        ]) {
          expect(
            pattern.hasMatch(src),
            isFalse,
            reason: '${file.path} fabricates a name',
          );
        }
      }
    });

    test('the caller is never substituted for a missing actor', () {
      for (final File file in auditSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'currentUser',
          'signedInUser',
          'authUserId',
          'currentSession',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} reaches for the caller identity',
          );
        }
      }
    });
  });

  group('this milestone writes nothing and opens nothing', () {
    test('no source performs any mutation', () {
      _expectAbsent(auditSources, <String>[
        '.insert(',
        '.update(',
        '.upsert(',
        '.delete(',
        'record_audit',
        'write_audit',
        'delete_audit',
        'purge_audit',
        'clear_audit',
        'retention',
      ], allowInComments: true);
    });

    test('the repository interface exposes one read and nothing else', () {
      final File repository = auditSources.firstWhere(
        (File f) => f.path.endsWith(
          'domain/repositories/vendor_audit_log_repository.dart',
        ),
      );
      final String src = code(repository);

      final RegExp methods = RegExp(r'Future<ReadResult<[^>]+>+>\s+(\w+)\(');
      final Set<String> names = methods
          .allMatches(src)
          .map((RegExpMatch m) => m.group(1)!)
          .toSet();

      expect(names, <String>{'auditLogs'});
    });

    test('no export, download or share affordance exists', () {
      _expectAbsent(auditSources, <String>[
        'export',
        'Export',
        'downloadCsv',
        'toCsv',
        'CSV',
        'Pdf',
        'PDF',
        'Share.share',
        'shareFiles',
        'Clipboard',
      ], allowInComments: true);
    });

    test('no detail route, modal or drawer is offered', () {
      // No audit detail read exists on the backend, so there is nowhere to go.
      _expectAbsent(auditSources, <String>[
        'auditLogDetailPath',
        'auditDetail',
        'showModalBottomSheet',
        'showDialog',
        'Navigator.push',
        'context.push',
        'context.go',
      ], allowInComments: true);
    });

    test('no entity or actor navigation is offered', () {
      // Neither `entity_id` nor `actor_profile_id` is returned, so no row holds
      // an address for anything.
      _expectAbsent(auditSources, <String>[
        'productDetailPath',
        'retailerDetailPath',
        'userDetailPath',
        'roleDetailPath',
        'onOpen',
        'onTap',
      ], allowInComments: true);
    });

    test('no filter or search affordance exists', () {
      _expectAbsent(auditSources, <String>[
        'searchTerm',
        'SrTextField',
        'filterByAction',
        'filterByActor',
        'filterByEntity',
        'dateRange',
        'DateRangePicker',
      ], allowInComments: true);
    });
  });

  group('layering', () {
    test('presentation never touches Supabase or HTTP directly', () {
      final Iterable<File> presentation = auditSources.where(
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

    test('the domain layer depends on no SDK or transport package', () {
      final Iterable<File> domain = auditSources.where(
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
      final Iterable<File> cubits = auditSources.where(
        (File f) => f.path.contains('/cubit/'),
      );
      expect(cubits, isNotEmpty);

      for (final File file in cubits) {
        final String src = code(file);
        expect(
          src.contains('Map<String, Object?>'),
          isFalse,
          reason: '${file.path} holds a raw SDK map',
        );
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

    test('only the data layer names the RPC', () {
      final Iterable<File> offenders = auditSources.where((File f) {
        if (f.path.contains('/data/')) return false;
        return code(f).contains('list_vendor_audit_logs');
      });

      expect(
        offenders.map((File f) => f.path),
        isEmpty,
        reason: 'the RPC name belongs in the data layer alone',
      );
    });
  });

  group('nothing fake is rendered', () {
    test('no source invents an event, an actor or a timestamp', () {
      for (final File file in auditSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'Example event',
          'Sample event',
          'Lorem',
          'mockEvent',
          'sampleEvent',
          'fakeEvent',
          'Coming soon',
          'placeholderEvent',
          'demoActor',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} contains fabricated data',
          );
        }
      }
    });

    test('the neutral placeholders exist only in presentation', () {
      final Iterable<File> nonPresentation = auditSources.where(
        (File f) => !f.path.contains('/presentation/'),
      );

      for (final File file in nonPresentation) {
        final String src = code(file);
        for (final String phrase in <String>[
          'Unknown actor',
          'System or unavailable actor',
          'Affected item unavailable',
        ]) {
          expect(
            src.contains(phrase),
            isFalse,
            reason: '${file.path} stores a presentation placeholder',
          );
        }
      }
    });

    test('the router no longer renders a placeholder for this route', () {
      final String router = code(
        sources.firstWhere((File f) => f.path.endsWith('app_router.dart')),
      );

      expect(router.contains('VendorAuditLogsPage'), isTrue);
      expect(
        RegExp(
          r'_placeholder\([^)]*VendorNavigation\.auditLogs',
          dotAll: true,
        ).hasMatch(router),
        isFalse,
        reason: 'the Audit Logs route must not be a placeholder',
      );
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
