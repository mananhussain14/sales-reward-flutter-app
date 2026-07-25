@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-safety assertions for the Vendor User read boundary.
///
/// The companion to `no_secrets_test.dart`, `receipt_boundary_test.dart` and
/// `vendor_retailer_boundary_test.dart`, narrowed to the one feature that reads
/// records about **people**. These read the source rather than exercise it,
/// which makes them the cheapest guard against the boundary eroding under
/// deadline pressure — the kind of regression a behavioural test cannot see,
/// because the code that erodes it usually still works.
///
/// Two properties are defended, stated once each:
///
/// * **The client never decides which Vendor it is.** The two deployed reads
///   derive the Vendor from `auth.uid()`.
/// * **The client never learns more about a person than the contract returns.**
///   No email, no phone, no auth identity, no permission — and no invitation,
///   because there is no Vendor user invitation table anywhere in the schema.
void main() {
  late List<File> sources;
  late List<File> userSources;
  late String rpcDataSource;

  /// The file's executable lines only.
  ///
  /// Every check below is about what the code *does*. The doc comments in this
  /// feature deliberately discuss the things the code must not do — "no email",
  /// "there are no Vendor user invitations", "never `.from('profiles')`" — and a
  /// scan that could not tell the two apart would either fail on its own
  /// documentation or force the documentation to stop naming what it is
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
    userSources = sources
        .where((File f) => f.path.contains('/features/users/'))
        .toList();
    rpcDataSource = code(
      sources.firstWhere(
        (File f) => f.path.endsWith('vendor_user_rpc_data_source.dart'),
      ),
    );
  });

  test('the feature is non-empty (the scan would pass vacuously)', () {
    expect(userSources, isNotEmpty);
    expect(userSources.length, greaterThan(10));
  });

  group('no privileged key reaches the device', () {
    test('no source names a service-role or secret key', () {
      _expectAbsent(userSources, <String>[
        'SUPABASE_SERVICE_ROLE_KEY',
        'service_role',
        'serviceRoleKey',
        'sb_secret_',
        'SERVICE_KEY',
      ]);
    });

    test('no source reads an environment value of its own', () {
      for (final File file in userSources) {
        final String src = code(file);
        expect(src.contains('String.fromEnvironment'), isFalse);
        expect(src.contains('Platform.environment'), isFalse);
      }
    });

    test('no source hardcodes a credential', () {
      _expectAbsent(userSources, <String>[
        'Bearer sb_',
        'Bearer ey',
        "password: '",
        'apikey',
      ]);
    });
  });

  group('the RPC contract', () {
    test('p_membership_id is the only parameter name in the feature', () {
      final RegExp params = RegExp(r"'(p_[a-z_]+)'");
      final Set<String> named = params
          .allMatches(rpcDataSource)
          .map((RegExpMatch m) => m.group(1)!)
          .toSet();

      expect(named, <String>{'p_membership_id'});
    });

    test('only the two deployed functions are named', () {
      final RegExp rpcNames = RegExp(r"const String \w+Rpc = '([^']+)'");
      final List<String> names = rpcNames
          .allMatches(rpcDataSource)
          .map((RegExpMatch m) => m.group(1)!)
          .toList();

      expect(names, <String>['list_vendor_users', 'get_vendor_user_detail']);
    });

    test('the list invoker takes no arguments at all', () {
      // The typedef is the security property: with no parameter there is no
      // parameter to get wrong, and a future edit that adds one has to change
      // this line.
      expect(
        rpcDataSource,
        contains('typedef VendorUserListInvoker = Future<Object?> Function();'),
      );
    });

    test('no identity, tenant, role or permission argument appears', () {
      for (final String forbidden in <String>[
        'user_id',
        'p_user',
        'auth_user_id',
        'profile_id',
        'p_profile',
        'p_vendor',
        'vendor_organization_id',
        'organization_id',
        'p_organization',
        'role_id',
        'role_code',
        'permission_code',
        'p_role',
        'p_permission',
        'p_status',
        'p_search',
        'p_limit',
        'p_offset',
        "'email'",
        'access_token',
        'tenant',
      ]) {
        expect(
          rpcDataSource.contains(forbidden),
          isFalse,
          reason: 'the Vendor User RPCs must pass no $forbidden argument',
        );
      }
    });

    test('the selector is the membership id, never a profile or auth id', () {
      // A membership row names one person IN ONE ORGANIZATION, so scoping it to
      // the caller's Vendor is a predicate on the same row. A profile id names a
      // person globally; an auth user id is the token subject.
      expect(rpcDataSource.contains('membershipId'), isTrue);
      for (final File file in userSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'profileId',
          'authUserId',
          'userId',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} names $forbidden',
          );
        }
      }
    });
  });

  group('no table is read directly', () {
    test('no source queries a member, profile or role table', () {
      // The web assembles this directory from four table reads and a TypeScript
      // join. Reimplementing that join in a second client is a second place for
      // the tenant scoping and the ACTIVE-role filter to be got wrong, which is
      // the whole reason the deployed functions exist.
      //
      // Table names are matched as *quoted literals*: the RPC names this feature
      // legitimately calls contain "vendor_user" as a substring.
      _expectAbsent(userSources, <String>[
        '.from(',
        "'organization_members'",
        "'profiles'",
        "'member_roles'",
        "'roles'",
        "'permissions'",
        "'role_permissions'",
        "'organizations'",
        '.select(',
        '.eq(',
        '.in_(',
        '.maybeSingle(',
      ], allowInComments: true);
    });

    test('nothing anywhere touches auth.users', () {
      // profiles.id IS the auth.users id. Neither deployed function reads that
      // table, and neither does this client — under any spelling.
      _expectAbsent(userSources, <String>[
        'auth.users',
        'auth_users',
        'authUsers',
        '.admin.',
        'getUserById',
        'listUsers',
      ], allowInComments: true);
    });

    test('no source touches Storage', () {
      _expectAbsent(userSources, <String>[
        'storage.from(',
        'uploadBinary(',
        'createSignedUrl',
      ]);
    });
  });

  group('no personal data beyond the contract', () {
    test('no source models an email or a phone number', () {
      // Email lives in auth.users and the web Vendor Users page neither queries
      // nor displays it. There is nothing to render, and a placeholder row —
      // "Email unavailable" — would still be a claim about the field.
      _expectAbsent(userSources, <String>[
        'email',
        'Email',
        'mobile_number',
        'mobileNumber',
        'phone',
        'Phone',
      ], allowInComments: true);
    });

    test('no source models an invitation of any kind', () {
      // Both invitation tables in the schema are Retailer-scoped; nothing
      // invites a person into a VENDOR organization. An invitation entity here
      // would be a promise about a table that does not exist.
      _expectAbsent(userSources, <String>[
        'invitation',
        'Invitation',
        'token_hash',
        'tokenHash',
        'invitationToken',
        'resend',
        'Resend',
      ], allowInComments: true);
    });

    test('no source models a permission or a role identifier', () {
      // Names are what a screen renders; codes and ids are internal
      // authorization vocabulary, and the backend returns neither.
      _expectAbsent(userSources, <String>[
        'roleId',
        'role_id',
        'roleCode',
        'role_code',
        'permissionCode',
        'permission_code',
        'ORGANIZATION_MEMBERS_READ',
        'RBAC_READ',
        'has_organization_permission',
        'get_vendor_super_admin_context',
      ], allowInComments: true);
    });

    test('no source models login, provider or session metadata', () {
      _expectAbsent(userSources, <String>[
        'lastSignIn',
        'last_sign_in',
        'provider',
        'Provider',
        'passwordHash',
        'encrypted_password',
      ], allowInComments: true);
    });
  });

  group('no authorization is decided on the client', () {
    test('no source hardcodes an organization or a membership', () {
      // A UUID literal in this feature could only be a tenant or a person the
      // client chose.
      final RegExp uuidLiteral = RegExp(
        r"'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
        r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'",
      );

      for (final File file in userSources) {
        expect(
          uuidLiteral.hasMatch(code(file)),
          isFalse,
          reason: '${file.path} hardcodes an identifier',
        );
      }
    });

    test('no source infers a role from an email or metadata', () {
      for (final File file in userSources) {
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

      for (final File file in userSources) {
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

    test('a role name never gates anything', () {
      // Role chips are display. Nothing may branch on one — a role name that
      // decided an affordance would be the client re-deriving authorization from
      // a label the backend sent for rendering.
      for (final File file in userSources) {
        final String src = code(file);
        expect(
          RegExp(r'roleNames\.contains\(').hasMatch(src),
          isFalse,
          reason: '${file.path} branches on a role name',
        );
        expect(
          RegExp(r"roleNames[^\n]*==\s*'").hasMatch(src),
          isFalse,
          reason: '${file.path} compares a role name to a literal',
        );
      }
    });
  });

  group('this milestone writes nothing', () {
    test('no source names a Vendor user write operation', () {
      _expectAbsent(userSources, <String>[
        'invite_vendor_user',
        'create_vendor_user',
        'update_vendor_user',
        'deactivate_vendor_user',
        'assign_member_role',
        'remove_member_role',
        'update_profile',
        'delete',
      ], allowInComments: true);
    });

    test('no source performs any mutation on the client', () {
      _expectAbsent(userSources, <String>[
        '.insert(',
        '.update(',
        '.upsert(',
        '.delete(',
      ], allowInComments: true);
    });
  });

  group('layering', () {
    test('presentation never touches Supabase or HTTP directly', () {
      final Iterable<File> presentation = userSources.where(
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
      final Iterable<File> domain = userSources.where(
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
      final Iterable<File> cubits = userSources.where(
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
      final Iterable<File> offenders = userSources.where((File f) {
        if (f.path.contains('/data/')) return false;
        final String src = code(f);
        return src.contains('list_vendor_users') ||
            src.contains('get_vendor_user_detail');
      });

      expect(
        offenders.map((File f) => f.path),
        isEmpty,
        reason: 'RPC names belong in the data layer alone',
      );
    });
  });

  group('nothing fake is rendered', () {
    test('no source invents a user, a role or a count', () {
      for (final File file in userSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'John Doe',
          'Jane Doe',
          'Example User',
          'Lorem',
          'mockUser',
          'sampleUser',
          'fakeUser',
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

    test('a status literal is never written outside the domain enum', () {
      // The tokens may be *recognised* — that is what the enum does — but never
      // assembled into a value the client sends or displays raw.
      final Iterable<File> outsideDomain = userSources.where(
        (File f) => !f.path.contains('/domain/entities/'),
      );

      for (final File file in outsideDomain) {
        final String src = code(file);
        for (final String token in <String>[
          "'INVITED'",
          "'ACTIVE'",
          "'SUSPENDED'",
          "'DEACTIVATED'",
        ]) {
          expect(
            src.contains(token),
            isFalse,
            reason: '${file.path} writes a backend status literal',
          );
        }
      }
    });

    test('an empty role array is never given a fallback', () {
      // The one place in this feature where a wrong guess would grant something.
      for (final File file in userSources) {
        final String src = code(file);
        expect(
          RegExp(r'roleNames\s*\?\?').hasMatch(src),
          isFalse,
          reason: '${file.path} defaults a missing role array',
        );
        expect(
          RegExp(r"roleNames[^\n]*isEmpty[^\n]*\?[^\n]*'[A-Z]").hasMatch(src),
          isFalse,
          reason: '${file.path} substitutes a role for an empty array',
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
