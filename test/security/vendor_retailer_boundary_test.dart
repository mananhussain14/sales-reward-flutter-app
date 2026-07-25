@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-safety assertions for the Vendor Retailer read boundary.
///
/// The companion to `no_secrets_test.dart` and `receipt_boundary_test.dart`,
/// narrowed to the one feature that reads another organization's records. These
/// read the source rather than exercise it, which makes them the cheapest guard
/// against the boundary eroding under deadline pressure — the kind of regression
/// a behavioural test cannot see, because the code that erodes it usually still
/// works.
///
/// The property they defend, stated once: **the client never decides which
/// Vendor it is.** The three deployed functions derive the Vendor from
/// `auth.uid()`; every assertion below is some form of "and nothing here tries
/// to help".
void main() {
  late List<File> sources;
  late List<File> retailerSources;
  late String rpcDataSource;

  /// The file's executable lines only.
  ///
  /// Every check below is about what the code *does*. The doc comments in this
  /// feature deliberately discuss the things the code must not do — "no Vendor
  /// organization id", "never `.from('vendor_retailers')`", "the relationship id
  /// is an address, not authorization" — and a scan that could not tell the two
  /// apart would either fail on its own documentation or force the documentation
  /// to stop naming what it is protecting against.
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
    retailerSources = sources
        .where((File f) => f.path.contains('/features/retailers/'))
        .toList();
    rpcDataSource = code(
      sources.firstWhere(
        (File f) => f.path.endsWith('vendor_retailer_rpc_data_source.dart'),
      ),
    );
  });

  test('the feature is non-empty (the scan would pass vacuously)', () {
    expect(retailerSources, isNotEmpty);
    expect(retailerSources.length, greaterThan(10));
  });

  group('no privileged key reaches the device', () {
    test('no source names a service-role or secret key', () {
      _expectAbsent(retailerSources, <String>[
        'SUPABASE_SERVICE_ROLE_KEY',
        'service_role',
        'serviceRoleKey',
        'sb_secret_',
        'SERVICE_KEY',
      ]);
    });

    test('no source reads an environment value of its own', () {
      // Configuration is supplied by the injector from AppConfig, which is the
      // single place a dart-define is read.
      for (final File file in retailerSources) {
        final String src = code(file);
        expect(src.contains('String.fromEnvironment'), isFalse);
        expect(src.contains('Platform.environment'), isFalse);
      }
    });

    test('no source hardcodes a credential', () {
      _expectAbsent(retailerSources, <String>[
        'Bearer sb_',
        'Bearer ey',
        "password: '",
        'apikey',
      ]);
    });
  });

  group('the RPC contract', () {
    test('p_relationship_id is the only parameter name in the feature', () {
      final RegExp params = RegExp(r"'(p_[a-z_]+)'");
      final Set<String> named = params
          .allMatches(rpcDataSource)
          .map((RegExpMatch m) => m.group(1)!)
          .toSet();

      expect(named, <String>{'p_relationship_id'});
    });

    test('only the three deployed functions are named', () {
      final RegExp rpcNames = RegExp(r"const String \w+Rpc = '([^']+)'");
      final List<String> names = rpcNames
          .allMatches(rpcDataSource)
          .map((RegExpMatch m) => m.group(1)!)
          .toList();

      expect(names, <String>[
        'list_vendor_retailers',
        'get_vendor_retailer_detail',
        'list_vendor_retailer_shops',
      ]);
    });

    test('the internal owner-state derivation is never called', () {
      // `vendor_retailer_owner_state(uuid)` is granted to nobody: it takes a
      // Retailer organization id and performs no authorization of its own, so a
      // client that could reach it would hold an oracle for probing any
      // organization id.
      _expectAbsent(retailerSources, <String>[
        'vendor_retailer_owner_state',
      ], allowInComments: true);
    });

    test('the owner-status RPC is not called either', () {
      // Out of scope for this read-only milestone, and the only source of owner
      // name, email and invitation timestamps. Not calling it is why no owner
      // PII can appear on these screens.
      _expectAbsent(retailerSources, <String>[
        'get_vendor_retailer_owner_status',
      ], allowInComments: true);
    });

    test('no identity, tenant, role or permission argument appears', () {
      for (final String forbidden in <String>[
        'user_id',
        'p_user',
        'profile_id',
        'p_profile',
        'p_vendor',
        'vendor_organization_id',
        'organization_id',
        'p_organization',
        'membership_id',
        'role_code',
        'permission_code',
        "'email'",
        'access_token',
        'tenant',
        'p_limit',
        'p_offset',
      ]) {
        expect(
          rpcDataSource.contains(forbidden),
          isFalse,
          reason: 'the Vendor Retailer RPCs must pass no $forbidden argument',
        );
      }
    });

    test('the list invoker takes no arguments at all', () {
      // The typedef is the security property: with no parameter there is no
      // parameter to get wrong, and a future edit that adds one has to change
      // this line.
      expect(
        rpcDataSource,
        contains(
          'typedef VendorRetailerListInvoker = Future<Object?> Function();',
        ),
      );
    });

    test('retailer_organization_id is received, never sent', () {
      // It is returned so a future screen can cross-link to the product API. It
      // is refused as an input because the relationship id is the narrower
      // selector — a foreign value there matches nothing rather than selecting
      // a Retailer some other Vendor manages.
      expect(
        rpcDataSource.contains('retailer_organization_id'),
        isFalse,
        reason: 'the Retailer organization id must never address a read',
      );
    });
  });

  group('no table is read directly', () {
    test('no source queries a relationship, organization or shop table', () {
      // The web assembles this directory from three table reads and a
      // TypeScript join. Reimplementing that join in a second client is a
      // second place for tenant scoping to be got wrong, which is the whole
      // reason the deployed functions exist.
      //
      // The table names are matched as *quoted literals* rather than as bare
      // words: `list_vendor_retailers` and `list_vendor_retailer_shops` are the
      // RPC names this feature legitimately calls, and they contain the table
      // names as substrings. A quoted literal can only be a table argument.
      _expectAbsent(retailerSources, <String>[
        '.from(',
        "'vendor_retailers'",
        "'retailer_shops'",
        "'organizations'",
        "'organization_members'",
        "'member_roles'",
        "'retailer_invitations'",
        '.select(',
        '.eq(',
        '.in_(',
        '.maybeSingle(',
      ], allowInComments: true);
    });

    test('no source touches Storage', () {
      _expectAbsent(retailerSources, <String>[
        'storage.from(',
        'uploadBinary(',
        'createSignedUrl',
        'getPublicUrl',
      ]);
    });
  });

  group('no authorization is decided on the client', () {
    test('no source names a permission code', () {
      // Which permission gates this read is seed data — RETAILERS_READ, mapped
      // to VENDOR_SUPER_ADMIN and to nothing else. A client-side comparison
      // would be a second, drifting definition.
      _expectAbsent(retailerSources, <String>[
        'RETAILERS_READ',
        'RETAILERS_WRITE',
        'RBAC_READ',
        'has_organization_permission',
        'get_vendor_super_admin_context',
      ], allowInComments: true);
    });

    test('no source hardcodes a Vendor organization', () {
      // A UUID literal in this feature could only be a tenant the client chose.
      final RegExp uuidLiteral = RegExp(
        r"'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
        r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'",
      );

      for (final File file in retailerSources) {
        expect(
          uuidLiteral.hasMatch(code(file)),
          isFalse,
          reason: '${file.path} hardcodes an identifier',
        );
      }
    });

    test('no source infers a role from an email or metadata', () {
      for (final File file in retailerSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'userMetadata',
          'appMetadata',
          'user_metadata',
          'app_metadata',
          'SharedPreferences',
          '.decodeJwt',
          'jwtDecode',
          "endsWith('@",
          'VENDOR_SUPER_ADMIN',
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
      // Navigation visibility is presentation. The role's display name is a
      // legitimate use — it is the page-header eyebrow — but a *comparison*
      // would be the client deciding whether a read is permitted, which the
      // database decides again on every call.
      final RegExp anyUse = RegExp(r'PortalKind\.\w+(\.\w+)?');

      for (final File file in retailerSources) {
        for (final RegExpMatch match in anyUse.allMatches(code(file))) {
          expect(
            match.group(0),
            'PortalKind.vendorSuperAdmin.displayName',
            reason:
                '${file.path} uses a portal kind for something other than '
                'its label',
          );
        }
      }
    });
  });

  group('no owner or invitation data is modelled', () {
    test('no source names an invitation token, hash or failure code', () {
      // `retailer_invitations` is default-deny with zero policies and zero
      // browser privileges, and the deployed reads return none of these. A field
      // for one here would be a field waiting for a leak.
      _expectAbsent(retailerSources, <String>[
        'token_hash',
        'tokenHash',
        'invitation_kind',
        'invitationKind',
        'failure_code',
        'failureCode',
        'invitation_id',
        'invitationId',
        'sent_at',
        'sentAt',
        'accepted_at',
        'acceptedAt',
        'expires_at',
        'expiresAt',
      ], allowInComments: true);
    });

    test('no source models an owner name or email', () {
      _expectAbsent(retailerSources, <String>[
        'ownerEmail',
        'owner_email',
        'ownerName',
        'owner_name',
        'recipientEmail',
        'recipient_email',
      ], allowInComments: true);
    });
  });

  group('this milestone writes nothing', () {
    test('no source names a Vendor Retailer write operation', () {
      // Read-only. Onboarding, inviting, suspending and shop editing all exist
      // in the backend and none of them is reachable from here.
      _expectAbsent(retailerSources, <String>[
        'onboard_vendor_retailer',
        'invite_retailer_owner',
        'update_vendor_retailer',
        'create_retailer_shop',
        'update_retailer_shop',
        'delete',
      ], allowInComments: true);
    });
  });

  group('layering', () {
    test('presentation never touches Supabase or HTTP directly', () {
      final Iterable<File> presentation = retailerSources.where(
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
      final Iterable<File> domain = retailerSources.where(
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
      final Iterable<File> cubits = retailerSources.where(
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

    test('only the data layer names an RPC', () {
      final Iterable<File> offenders = retailerSources.where((File f) {
        if (f.path.contains('/data/')) return false;
        final String src = code(f);
        return src.contains('list_vendor_retailers') ||
            src.contains('get_vendor_retailer_detail') ||
            src.contains('list_vendor_retailer_shops');
      });

      expect(
        offenders.map((File f) => f.path),
        isEmpty,
        reason: 'RPC names belong in the data layer alone',
      );
    });
  });

  group('nothing fake is rendered', () {
    test('no source invents a Retailer, a shop or a count', () {
      // Every figure on screen is a column the backend returned or a sum of
      // them. A literal Retailer name or a placeholder count in the source
      // would be data no database produced.
      for (final File file in retailerSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'Example Retailer',
          'Acme',
          'Lorem',
          'mockRetailer',
          'sampleShop',
          'fakeRetailer',
          'Coming soon',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} contains fabricated data',
          );
        }
      }
    });

    test('a status is never assembled by the client', () {
      // The tokens may be *recognised* — that is what the enums do — but never
      // written into a value the client sends. Nothing in this read-only
      // feature sends anything at all beyond one relationship id.
      final Iterable<File> outsideDomain = retailerSources.where(
        (File f) => !f.path.contains('/domain/entities/'),
      );

      for (final File file in outsideDomain) {
        final String src = code(file);
        for (final String token in <String>[
          "'ACTIVE'",
          "'SUSPENDED'",
          "'DEACTIVATED'",
          "'DELIVERY_FAILED'",
        ]) {
          expect(
            src.contains(token),
            isFalse,
            reason: '${file.path} writes a backend status literal',
          );
        }
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
