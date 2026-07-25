@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-safety assertions for the Vendor Role read boundary.
///
/// The companion to `no_secrets_test.dart`, `receipt_boundary_test.dart`,
/// `vendor_retailer_boundary_test.dart` and `vendor_user_boundary_test.dart`,
/// narrowed to the one feature that reads **authorization configuration**.
/// These read the source rather than exercise it, which makes them the cheapest
/// guard against the boundary eroding under deadline pressure — the kind of
/// regression a behavioural test cannot see, because the code that erodes it
/// usually still works.
///
/// Four properties are defended, stated once each:
///
/// * **The client never decides which Vendor it is.** All three deployed reads
///   derive the Vendor from `auth.uid()`.
/// * **The client never learns authorization vocabulary.** No role code, no
///   permission code, no module — those are the literals the RLS policies match
///   on, and a client that held them would be invited to reason about them.
/// * **The client never computes access.** A permission list is configuration
///   information; nothing branches on one.
/// * **The client never invents a taxonomy.** There is no role scope, kind,
///   system or custom column, so a Vendor/Retailer or built-in/custom label
///   could only have been derived from a role name.
void main() {
  late List<File> sources;
  late List<File> roleSources;
  late String rpcDataSource;

  /// The file's executable lines only.
  ///
  /// Every check below is about what the code *does*. The doc comments in this
  /// feature deliberately discuss the things the code must not do — "no
  /// permission code", "there is no role kind column", "never
  /// `.from('roles')`" — and a scan that could not tell the two apart would
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
    roleSources = sources
        .where((File f) => f.path.contains('/features/roles/'))
        .toList();
    rpcDataSource = code(
      sources.firstWhere(
        (File f) => f.path.endsWith('vendor_role_rpc_data_source.dart'),
      ),
    );
  });

  test('the feature is non-empty (the scan would pass vacuously)', () {
    expect(roleSources, isNotEmpty);
    expect(roleSources.length, greaterThan(10));
  });

  group('no privileged key reaches the device', () {
    test('no source names a service-role or secret key', () {
      _expectAbsent(roleSources, <String>[
        'SUPABASE_SERVICE_ROLE_KEY',
        'service_role',
        'serviceRoleKey',
        'sb_secret_',
        'SERVICE_KEY',
      ]);
    });

    test('no source reads an environment value of its own', () {
      for (final File file in roleSources) {
        final String src = code(file);
        expect(src.contains('String.fromEnvironment'), isFalse);
        expect(src.contains('Platform.environment'), isFalse);
      }
    });

    test('no source hardcodes a credential', () {
      _expectAbsent(roleSources, <String>[
        'Bearer sb_',
        'Bearer ey',
        "password: '",
        'apikey',
      ]);
    });

    test('dart_defines.json is ignored and not tracked by git', () {
      // The publishable key is supplied at build time and the file stays local.
      // A committed defines file is how a private value starts travelling with
      // the repository. It may exist on a developer's machine; it may not be in
      // the index.
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
    test('p_role_id is the only parameter name in the feature', () {
      final RegExp params = RegExp(r"'(p_[a-z_]+)'");
      final Set<String> named = params
          .allMatches(rpcDataSource)
          .map((RegExpMatch m) => m.group(1)!)
          .toSet();

      expect(named, <String>{'p_role_id'});
    });

    test('only the three deployed functions are named', () {
      final RegExp rpcNames = RegExp(r"const String \w+Rpc = '([^']+)'");
      final List<String> names = rpcNames
          .allMatches(rpcDataSource)
          .map((RegExpMatch m) => m.group(1)!)
          .toList();

      expect(names, <String>[
        'list_vendor_roles',
        'get_vendor_role_detail',
        'list_vendor_role_permissions',
      ]);
    });

    test('the catalogue invoker takes no arguments at all', () {
      // The typedef is the security property: with no parameter there is no
      // parameter to get wrong, and a future edit that adds one has to change
      // this line.
      expect(
        rpcDataSource,
        contains('typedef VendorRoleListInvoker = Future<Object?> Function();'),
      );
    });

    test('no identity, tenant, role-code or permission-code argument', () {
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
        'role_code',
        'permission_code',
        'permission_id',
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
          reason: 'the Vendor Role RPCs must pass no $forbidden argument',
        );
      }
    });

    test('the selector is the role id, never the role code or name', () {
      // roles.code is UNIQUE and would address a role just as precisely, which
      // is exactly why the backend refuses it: the codes are the literals the
      // RLS policies and the authorization helpers match on.
      expect(rpcDataSource.contains('roleId'), isTrue);
      for (final File file in roleSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'roleCode',
          'role_code',
          'byRoleName',
          'roleIndex',
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
    test('no source queries an RBAC or membership table', () {
      // The web assembles this screen from three whole-table reads and a
      // TypeScript join. Reimplementing that join in a second client would be a
      // second definition of "which permissions does this role grant".
      //
      // Table names are matched as *quoted literals*: the RPC names this feature
      // legitimately calls contain "role" as a substring.
      _expectAbsent(roleSources, <String>[
        '.from(',
        "'roles'",
        "'permissions'",
        "'role_permissions'",
        "'member_roles'",
        "'organization_members'",
        "'organizations'",
        "'profiles'",
        '.select(',
        '.eq(',
        '.in_(',
        '.maybeSingle(',
      ], allowInComments: true);
    });

    test('nothing anywhere touches auth.users', () {
      _expectAbsent(roleSources, <String>[
        'auth.users',
        'auth_users',
        'authUsers',
        '.admin.',
        'getUserById',
        'listUsers',
      ], allowInComments: true);
    });

    test('no source touches Storage', () {
      _expectAbsent(roleSources, <String>[
        'storage.from(',
        'uploadBinary(',
        'createSignedUrl',
      ]);
    });
  });

  group('no authorization vocabulary reaches the client', () {
    test('no source names a permission code', () {
      // These are the literals `has_organization_permission()` matches on. The
      // backend never returns one, and this client never writes one.
      _expectAbsent(roleSources, <String>[
        'RBAC_READ',
        'ORGANIZATION_MEMBERS_READ',
        'RETAILERS_READ',
        'PRODUCTS_READ',
        'AUDIT_LOGS_READ',
        'RETAILER_OWNERS_INVITE',
      ], allowInComments: true);
    });

    test('no source names a role code', () {
      _expectAbsent(roleSources, <String>[
        'VENDOR_SUPER_ADMIN',
        'CLAIM_REVIEWER',
        'FINANCE_ADMIN',
        'RETAILER_OWNER',
        'RETAILER_MANAGER',
        'SALES_STAFF',
      ], allowInComments: true);
    });

    test('no source models a permission code, id or module', () {
      _expectAbsent(roleSources, <String>[
        'permissionCode',
        'permission_code',
        'permissionId',
        'permission_id',
        'permissionModule',
        'permission_module',
        "'module'",
        'moduleName',
      ], allowInComments: true);
    });

    test('no source names a backend function, policy or SQLSTATE', () {
      _expectAbsent(roleSources, <String>[
        'has_organization_permission',
        'get_vendor_super_admin_context',
        'roles_select_rbac_authorized',
        'SQLSTATE',
        '42501',
        '22P02',
      ], allowInComments: true);
    });

    test('no source models a permission status', () {
      // Neither `permissions` nor `role_permissions` has a status column, so an
      // inactive assigned permission is unrepresentable. A field for one would
      // be a promise about a column that does not exist.
      _expectAbsent(roleSources, <String>[
        'permissionStatus',
        'permission_status',
        'VendorPermissionStatus',
        'activePermissionCount',
        'active_permission_count',
      ], allowInComments: true);
    });
  });

  group('no taxonomy is invented', () {
    test('no source models a role scope, kind, or system/custom flag', () {
      // There is no such column anywhere. It could only be derived from the role
      // name or code, which would disagree with the web the moment either
      // changed.
      _expectAbsent(roleSources, <String>[
        'roleScope',
        'role_scope',
        'roleKind',
        'role_kind',
        'isSystem',
        'is_system',
        'isCustom',
        'is_custom',
        'isEditable',
        'is_editable',
        'builtIn',
        'RoleScope',
        'RoleKind',
      ], allowInComments: true);
    });

    test('nothing branches on a role name', () {
      // Role names are display data the backend sent for rendering. A name that
      // decided an affordance, a label or a filter would be the client
      // re-deriving a taxonomy from a string.
      for (final File file in roleSources) {
        final String src = code(file);
        expect(
          RegExp(r"roleName[^\n]*==\s*'").hasMatch(src),
          isFalse,
          reason: '${file.path} compares a role name to a literal',
        );
        expect(
          RegExp(r'roleName\.(startsWith|endsWith|contains)\(\s*.').hasMatch(
            src.replaceAll('roleName.toLowerCase().contains(needle)', ''),
          ),
          isFalse,
          reason: '${file.path} matches a role name against a literal',
        );
      }
    });

    test('nothing filters the catalogue by role identity', () {
      // The catalogue is global and every definition is shown. A local filter
      // that removed Retailer roles would be a silent product change and would
      // immediately disagree with the web.
      for (final File file in roleSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'hideRetailer',
          'vendorOnly',
          'isVendorRole',
          'isRetailerRole',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} narrows the global catalogue',
          );
        }
      }
    });
  });

  group('no authorization is decided on the client', () {
    test('nothing computes access from a permission list', () {
      // The permission list is configuration information, not a capability
      // check. The backend evaluates the real question again on every call.
      for (final File file in roleSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'permissions.contains(',
          'hasPermission',
          'canPerform',
          'isAllowed',
          'checkPermission',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} computes authorization from a list',
          );
        }
      }
    });

    test('no source hardcodes an organization or a role identifier', () {
      final RegExp uuidLiteral = RegExp(
        r"'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
        r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'",
      );

      for (final File file in roleSources) {
        expect(
          uuidLiteral.hasMatch(code(file)),
          isFalse,
          reason: '${file.path} hardcodes an identifier',
        );
      }
    });

    test('no source infers authority from an email, token or metadata', () {
      for (final File file in roleSources) {
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

      for (final File file in roleSources) {
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

    test('the Vendor authorization resolver is not duplicated', () {
      // Whether this caller is a Vendor Super Admin is resolved once, in SQL.
      // A second resolver here would be a second definition free to drift.
      for (final File file in roleSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'resolveVendor',
          'vendorContext',
          'organizationId',
          'isVendorSuperAdmin',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} reimplements Vendor resolution',
          );
        }
      }
    });
  });

  group('this milestone writes nothing', () {
    test('no source names a role or permission write operation', () {
      _expectAbsent(roleSources, <String>[
        'create_role',
        'update_role',
        'delete_role',
        'activate_role',
        'deactivate_role',
        'duplicate_role',
        'assign_role',
        'remove_role',
        'assign_permission',
        'remove_permission',
        'grant_permission',
        'revoke_permission',
        'add_member_role',
      ], allowInComments: true);
    });

    test('no source performs any mutation on the client', () {
      _expectAbsent(roleSources, <String>[
        '.insert(',
        '.update(',
        '.upsert(',
        '.delete(',
      ], allowInComments: true);
    });
  });

  group('layering', () {
    test('presentation never touches Supabase or HTTP directly', () {
      final Iterable<File> presentation = roleSources.where(
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
      final Iterable<File> domain = roleSources.where(
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
      final Iterable<File> cubits = roleSources.where(
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
      final Iterable<File> offenders = roleSources.where((File f) {
        if (f.path.contains('/data/')) return false;
        final String src = code(f);
        return src.contains('list_vendor_roles') ||
            src.contains('get_vendor_role_detail') ||
            src.contains('list_vendor_role_permissions');
      });

      expect(
        offenders.map((File f) => f.path),
        isEmpty,
        reason: 'RPC names belong in the data layer alone',
      );
    });
  });

  group('nothing fake is rendered', () {
    test('no source invents a role, a permission or a count', () {
      for (final File file in roleSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'Example Role',
          'Sample Role',
          'Lorem',
          'mockRole',
          'sampleRole',
          'fakeRole',
          'Coming soon',
          'placeholderPermission',
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
      final Iterable<File> outsideDomain = roleSources.where(
        (File f) => !f.path.contains('/domain/entities/'),
      );

      for (final File file in outsideDomain) {
        final String src = code(file);
        for (final String token in <String>["'ACTIVE'", "'INACTIVE'"]) {
          expect(
            src.contains(token),
            isFalse,
            reason: '${file.path} writes a backend status literal',
          );
        }
      }
    });

    test('a nullable description is never given a fabricated fallback', () {
      // A description invented from the role name would be a sentence the
      // backend never sent, presented as though it had.
      for (final File file in roleSources) {
        final String src = code(file);
        expect(
          RegExp(r'description\s*\?\?\s*roleName').hasMatch(src),
          isFalse,
          reason: '${file.path} fabricates a description',
        );
        expect(
          RegExp(r'description\s*\?\?\s*permission\.name').hasMatch(src),
          isFalse,
          reason: '${file.path} fabricates a permission description',
        );
      }
    });

    test('an unknown status is never mapped to active', () {
      final File statusFile = roleSources.firstWhere(
        (File f) => f.path.endsWith('vendor_role_status.dart'),
      );
      final String src = code(statusFile);

      // Effectiveness is a positive test against `active`, so no future token
      // can reach it by failing to match something else.
      expect(src.contains('grantsMappedPermissions => this == active'), isTrue);
      expect(src.contains('isActive => this == active'), isTrue);
      expect(src.contains('!= inactive'), isFalse);
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
