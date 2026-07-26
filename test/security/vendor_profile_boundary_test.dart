@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-safety assertions for the Vendor company/profile boundary.
///
/// The companion to `no_secrets_test.dart`, `receipt_boundary_test.dart` and the
/// six Vendor read boundaries that precede it. These read the source rather than
/// exercise it, which makes them the cheapest guard against the boundary eroding
/// under deadline pressure — the kind of regression a behavioural test cannot
/// see, because the code that erodes it usually still works.
///
/// This surface has two failure modes the others do not.
///
/// **It is a self-read**, so the one argument that must never appear is a
/// *person*: a profile id, a membership id or an auth user id would each turn
/// "my profile" into a way to read a colleague. The deployed function has an
/// empty parameter list precisely so that no such argument can be forged, and
/// this file holds the client to the same shape.
///
/// **It composes two trusted sources on one screen**, so the second thing that
/// must never happen is either one answering for the other: the organization name
/// must come from the session and from nowhere else, and the administrator's name
/// and roles from the RPC and from nowhere else.
///
/// Nine properties are defended, stated once each:
///
/// * **The client sends nothing at all.** Zero arguments — no identity, profile,
///   membership, organization, tenant, role, permission, status or date range.
/// * **The client never reads a protected table.** Not `organizations`, not
///   `profiles`, not `organization_members`, not `member_roles`, not `roles`, not
///   `auth.users` — and never the Vendor user directory to find itself in it.
/// * **The client never writes.** No mutation, and no affordance that could.
/// * **The organization name comes from the trusted session context**, from
///   exactly one place, and is never modelled by this feature.
/// * **The administrator's name and roles come from the RPC**, and are never
///   composed, re-ordered or inferred on this side of the wire.
/// * **No personal detail beyond the two contracted fields is modelled** — no
///   email, mobile number, status, timestamp, id, metadata or image path.
/// * **No company field is fabricated** — none of the eight columns exists, and
///   nothing here names one.
/// * **No authorization is decided or displayed on the client.**
/// * **The layering holds.** Presentation never touches Supabase; the domain
///   depends on no SDK; no BLoC state or widget holds a raw backend map.
void main() {
  late List<File> sources;
  late List<File> profileSources;
  late String rpcDataSource;
  late String copy;
  late String page;

  /// The file's executable lines only.
  ///
  /// Every check below is about what the code *does*. The doc comments in this
  /// feature deliberately discuss the things the code must not do — "no profile
  /// id is sent", "no such column exists" — and a scan that could not tell the
  /// two apart would either fail on its own documentation or force the
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
    profileSources = sources
        .where((File f) => f.path.contains('/features/profile/'))
        .toList();
    rpcDataSource = code(
      sources.firstWhere(
        (File f) => f.path.endsWith('vendor_profile_rpc_data_source.dart'),
      ),
    );
    copy = code(
      sources.firstWhere(
        (File f) => f.path.endsWith('vendor_profile_copy.dart'),
      ),
    );
    page = code(
      sources.firstWhere(
        (File f) => f.path.endsWith('vendor_company_profile_page.dart'),
      ),
    );
  });

  test('the feature is non-empty (the scan would pass vacuously)', () {
    expect(profileSources, isNotEmpty);
    expect(profileSources.length, greaterThan(8));
  });

  group('no privileged key reaches the device', () {
    test('no source names a service-role or secret key', () {
      _expectAbsent(profileSources, <String>[
        'SUPABASE_SERVICE_ROLE_KEY',
        'service_role',
        'serviceRoleKey',
        'sb_secret_',
        'SERVICE_KEY',
      ]);
    });

    test('no source reads an environment value of its own', () {
      for (final File file in profileSources) {
        final String src = code(file);
        expect(src.contains('String.fromEnvironment'), isFalse);
        expect(src.contains('Platform.environment'), isFalse);
      }
    });

    test('no source hardcodes a credential', () {
      _expectAbsent(profileSources, <String>[
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
    test('only the one deployed function is named', () {
      final RegExp rpcNames = RegExp(r"const String \w+Rpc =\s*'([^']+)'");
      final List<String> names = rpcNames
          .allMatches(rpcDataSource)
          .map((RegExpMatch m) => m.group(1)!)
          .toList();

      expect(names, <String>['get_my_vendor_profile']);
    });

    test('no parameter name of any kind exists in the feature', () {
      // The function is declared with an empty parameter list. There is nothing
      // to send, so no `p_` key may appear anywhere in this slice.
      final RegExp params = RegExp(r"'(p_[a-z_]+)'");
      for (final File file in profileSources) {
        expect(
          params.allMatches(code(file)).map((RegExpMatch m) => m.group(1)),
          isEmpty,
          reason: '${file.path} names an RPC parameter, and there are none',
        );
      }
    });

    test('no params map is passed, not even an empty one', () {
      expect(rpcDataSource.contains('params:'), isFalse);
      expect(
        rpcDataSource.contains(
          'client.rpc<Object?>(vendorAdministratorProfileRpc)',
        ),
        isTrue,
      );
    });

    test('no caller identity, organization or selector argument', () {
      // The one that matters most for this contract: a profile, membership or
      // auth user id would turn a self-read into a way to read a colleague.
      for (final String forbidden in <String>[
        'user_id',
        'p_user',
        'auth_user_id',
        'authUserId',
        'profile_id',
        'p_profile',
        'membership_id',
        'p_membership',
        'p_member',
        'p_vendor',
        'vendor_organization_id',
        'organization_id',
        'organizationId',
        'p_organization',
        'p_tenant',
        'tenant',
        'p_role',
        'role_code',
        'permission_code',
        'p_permission',
        'p_status',
        'p_from',
        'p_to',
        'p_limit',
        'p_offset',
        "'email'",
        'access_token',
      ]) {
        expect(
          rpcDataSource.contains(forbidden),
          isFalse,
          reason: 'the profile RPC must pass no $forbidden argument',
        );
      }
    });

    test('the invoker type carries no parameter', () {
      expect(
        rpcDataSource.contains(
          'typedef VendorAdministratorProfileInvoker = '
          'Future<Object?> Function();',
        ),
        isTrue,
        reason: 'the zero-argument shape must be enforced by the type',
      );
    });
  });

  group('no table is read directly', () {
    test('no source queries the identity or RBAC tables', () {
      // `authenticated` genuinely holds SELECT on profiles, organization_members,
      // member_roles and roles, so a direct read would partly *work*. It is not
      // done because it would put a second definition of the composed display
      // name into a client free to drift from the database and from the web.
      _expectAbsent(profileSources, <String>[
        '.from(',
        "'organizations'",
        "'profiles'",
        "'organization_members'",
        "'member_roles'",
        "'roles'",
        "'permissions'",
        "'role_permissions'",
        '.select(',
        '.eq(',
        '.neq(',
        '.in_(',
        '.order(',
        '.range(',
        '.limit(',
        '.count(',
        '.head(',
        '.maybeSingle(',
      ], allowInComments: true);
    });

    test('nothing anywhere touches auth.users', () {
      _expectAbsent(profileSources, <String>[
        'auth.users',
        'auth_users',
        'authUsers',
        '.admin.',
        'getUserById',
        'listUsers',
      ], allowInComments: true);
    });

    test('the Vendor user directory is never used to find the caller', () {
      // The anti-pattern this whole contract exists to remove: downloading every
      // colleague's name, statuses and roles and guessing which row is oneself.
      _expectAbsent(profileSources, <String>[
        'list_vendor_users',
        'get_vendor_user_detail',
        'VendorUserRepository',
        'VendorUserSummary',
        'VendorUserDetail',
        'VendorUserListCubit',
      ], allowInComments: true);
    });

    test('the Vendor resolution is not reimplemented', () {
      for (final File file in profileSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'resolveVendor',
          'isVendorSuperAdmin',
          'currentVendor',
          'membershipFor',
          'fetchProfile',
          'hasPermission',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} reimplements the Vendor resolution',
          );
        }
      }
    });
  });

  group('no identity is composed or inferred on the client', () {
    test('no name part is joined, split or recombined', () {
      // The database composed the display name — byte-identically to
      // list_vendor_users() and to the web header — so no client is the third
      // implementation of "trim the parts, drop the empty ones, join with one
      // space".
      for (final File file in profileSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'first_name',
          'last_name',
          'firstName',
          'lastName',
          'givenName',
          'familyName',
          'fullNameOf',
          'composeName',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} composes a name the backend already composed',
          );
        }
      }
    });

    test('the display name is never trimmed or re-cased before rendering', () {
      // The parser's blank check runs against a trimmed *copy* and hands on the
      // original; nothing in the presentation layer touches it at all.
      final Iterable<File> presentation = profileSources.where(
        (File f) => f.path.contains('/presentation/'),
      );
      expect(presentation, isNotEmpty);

      for (final File file in presentation) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'displayName.trim',
          'displayName.split',
          'displayName.toUpperCase',
          'displayName.toLowerCase',
          'displayName.substring',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} rewrites a name the database composed',
          );
        }
      }
    });

    test('the role array is never sorted, filtered or de-duplicated', () {
      // `order by r.name, r.id` is fixed in SQL. Re-ordering here would apply a
      // collation the database does not use, and the mobile order would drift
      // from the web's.
      for (final File file in profileSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'roleNames.sort',
          'roleNames.toSet',
          'roleNames.where',
          'roleNames.reversed',
          '..sort(',
          'Set<String>.from',
          'LinkedHashSet',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} re-orders or collapses the role list',
          );
        }
      }
    });

    test('no role or permission code is named or derived', () {
      _expectAbsent(profileSources, <String>[
        "'VENDOR_SUPER_ADMIN'",
        "'RETAILER_OWNER'",
        "'RETAILER_MANAGER'",
        "'SALES_STAFF'",
        'RBAC_READ',
        'ORGANIZATION_MEMBERS_READ',
        'AUDIT_LOGS_READ',
        'roleCode',
        'permissionCode',
        'toRoleCode',
      ], allowInComments: true);
    });

    test('the SQL display-name floor is not special-cased', () {
      // 'Member' is the database's unreachable floor. A client that recognised
      // it would be rendering a status the contract does not express — and would
      // refuse a perfectly ordinary single-word name.
      for (final File file in profileSources) {
        expect(
          RegExp(r"==\s*'Member'").hasMatch(code(file)),
          isFalse,
          reason: '${file.path} treats the SQL fallback as a status',
        );
      }
    });
  });

  group('the organization name has exactly one source', () {
    test('it is read from the session context, in the page alone', () {
      expect(
        page.contains('portalContext.vendor?.organizationName'),
        isTrue,
        reason: 'the name must come from the trusted session context',
      );
    });

    test('no other file in the feature reads an organization name', () {
      for (final File file in profileSources) {
        if (file.path.endsWith('vendor_company_profile_page.dart')) continue;
        expect(
          code(file).contains('portalContext'),
          isFalse,
          reason: '${file.path} is a second source for the organization name',
        );
      }
    });

    test('the entity, parser and cubit model no organization identity', () {
      // The profile RPC returns no company field, and this build has nowhere to
      // put one even if a future response carried it.
      for (final File file in profileSources.where(
        (File f) =>
            f.path.contains('/domain/') ||
            f.path.contains('/data/') ||
            f.path.contains('/cubit/'),
      )) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'organizationName',
          'organizationId',
          'organization_name',
          'organization_id',
          'companyName',
          'vendorId',
          'tenantId',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} models a company identity',
          );
        }
      }
    });

    test('no source adds a second auth or session listener', () {
      for (final File file in profileSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'onAuthStateChange',
          'authStateChanges',
          'auth.onAuth',
          'StreamSubscription',
          'BlocListener<SessionBloc',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason:
                '${file.path} opens a second opinion about who is signed in',
          );
        }
      }
    });
  });

  group('no personal detail beyond the two fields is modelled', () {
    test('no source names an email, mobile number or address', () {
      _expectAbsent(profileSources, <String>[
        'email',
        'Email',
        'mobile_number',
        'mobileNumber',
        'phoneNumber',
        'postalAddress',
        'addressLine',
      ], allowInComments: true);
    });

    test('no source models a status or a timestamp', () {
      // An authorized caller is ACTIVE in all three statuses by construction, so
      // the contract returns none of them — a field here could only ever hold one
      // literal, and would invite a badge that can never change.
      for (final File file in profileSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'profileStatus',
          'membershipStatus',
          'organizationStatus',
          'accountStatus',
          "'ACTIVE'",
          "'SUSPENDED'",
          "'INVITED'",
          "'DEACTIVATED'",
          'createdAt',
          'updatedAt',
          'joinedAt',
          'deactivatedAt',
          'DateTime',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} models $forbidden, which is not returned',
          );
        }
      }
    });

    test('no source models an identifier of any kind', () {
      for (final File file in profileSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'membershipId',
          'profileId',
          'authUserId',
          'userId',
          'uuid',
          'Uuid',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} models $forbidden, which is not returned',
          );
        }
      }
    });

    test('no source hardcodes an identifier', () {
      final RegExp uuidLiteral = RegExp(
        r"'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
        r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'",
      );

      for (final File file in profileSources) {
        expect(
          uuidLiteral.hasMatch(code(file)),
          isFalse,
          reason: '${file.path} hardcodes an identifier',
        );
      }
    });

    test('no source names metadata, a token or a session claim', () {
      for (final File file in profileSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'metadata',
          'userMetadata',
          'appMetadata',
          'SharedPreferences',
          '.decodeJwt',
          'jwtDecode',
          'currentSession',
          'currentUser',
          'accessToken',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} reaches for $forbidden',
          );
        }
      }
    });

    test('no image, avatar path or storage reference exists', () {
      // No logo, avatar, image or path column exists anywhere in the schema, and
      // the only bucket in the project is `receipts` — private, zero policies,
      // unrelated to identity. The avatars on this screen are initials computed
      // from a name already on screen.
      for (final File file in profileSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'NetworkImage',
          'Image.network',
          'CircleAvatar',
          'avatarUrl',
          'logoUrl',
          'imagePath',
          'signedUrl',
          'createSignedUrl',
          'getPublicUrl',
          '.storage',
          'bucket',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} reaches for an image that does not exist',
          );
        }
      }
    });
  });

  group('no company field is fabricated', () {
    test('the copy names no column the schema does not have', () {
      for (final String invented in <String>[
        'Legal name',
        'legalName',
        'Trading name',
        'tradingName',
        'Registration',
        'registrationNumber',
        'Tax ID',
        'taxId',
        'VAT',
        'Website',
        'website',
        'Business email',
        'Business phone',
        'Postal address',
        'Country',
        'Currency',
        'Logo',
      ]) {
        expect(
          copy.contains(invented),
          isFalse,
          reason: 'the copy names "$invented", which has no column',
        );
      }
    });

    test('the limitation note reads as product scope, not as a failure', () {
      expect(
        copy.contains(
          "'Additional company details are not configured in SalesReward yet.'",
        ),
        isTrue,
      );
      // Scoped to the note itself. The refresh-failure copy elsewhere in this
      // file legitimately says "could not refresh" — that one *is* a failure.
      // What must never happen is the company's absence borrowing its language.
      final Match? note = RegExp(
        r"companyLimitationNote\s*=\s*'([^']*)'",
      ).firstMatch(copy);
      expect(note, isNotNull);

      for (final String failureWord in <String>[
        'could not',
        'Could not',
        'failed',
        'Failed',
        'unavailable',
        'Unavailable',
        'error',
        'Error',
        'try again',
        'Try again',
      ]) {
        expect(
          note!.group(1)!.contains(failureWord),
          isFalse,
          reason: 'the company note must not read as a failure',
        );
      }
    });

    test('no placeholder value stands in for an absent field', () {
      for (final File file in profileSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          "'—'",
          "'--'",
          "'N/A'",
          "'Not set'",
          "'Not provided'",
          "'Coming soon'",
          "'TBD'",
          'placeholder:',
          'hintText',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} renders a placeholder for absent data',
          );
        }
      }
    });

    test('no source invents a person, a company or a sample', () {
      for (final File file in profileSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'Lorem',
          'mockProfile',
          'sampleProfile',
          'fakeProfile',
          'demoName',
          'Example Vendor',
          'Acme',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} contains fabricated data',
          );
        }
      }
    });
  });

  group('this milestone writes nothing', () {
    test('no source performs any mutation', () {
      _expectAbsent(profileSources, <String>[
        '.insert(',
        '.update(',
        '.upsert(',
        '.delete(',
        '.upload(',
        'record_audit',
        'update_profile',
        'update_vendor',
        'edit_profile',
        'set_profile',
        'change_password',
        'updateUser',
      ], allowInComments: true);
    });

    test('the repository interface exposes one read and nothing else', () {
      final File repository = profileSources.firstWhere(
        (File f) => f.path.endsWith(
          'domain/repositories/vendor_profile_repository.dart',
        ),
      );

      final RegExp methods = RegExp(r'Future<ReadResult<[^>]+>+>\s+(\w+)\(');
      final Set<String> names = methods
          .allMatches(code(repository))
          .map((RegExpMatch m) => m.group(1)!)
          .toSet();

      expect(names, <String>{'administratorProfile'});
    });

    test('no edit, upload or security affordance exists', () {
      _expectAbsent(profileSources, <String>[
        'SrTextField',
        'TextField',
        'TextFormField',
        'onChanged:',
        'onSubmitted:',
        'FilePicker',
        'ImagePicker',
        'image_picker',
        'editProfile',
        'changePassword',
        'switchOrganization',
      ], allowInComments: true);
    });

    test('the cubit exposes only the three read operations', () {
      final File cubit = profileSources.firstWhere(
        (File f) => f.path.endsWith('vendor_profile_cubit.dart'),
      );
      // Public methods only: `_fetch` is the shared private implementation both
      // reads delegate to, and is not part of the surface a widget can call.
      final RegExp publicMethods = RegExp(
        r'^  (?:Future<void>|void) ([a-z]\w*)\(',
      );
      final Set<String> names = code(cubit)
          .split('\n')
          .map((String line) => publicMethods.firstMatch(line)?.group(1))
          .whereType<String>()
          .toSet();

      expect(names, <String>{'load', 'refresh', 'clear'});
    });
  });

  group('layering', () {
    test('presentation never touches Supabase or HTTP directly', () {
      final Iterable<File> presentation = profileSources.where(
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
      final Iterable<File> domain = profileSources.where(
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
      final Iterable<File> cubits = profileSources.where(
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

    test('no widget holds a raw backend map', () {
      final Iterable<File> widgets = profileSources.where(
        (File f) => f.path.contains('/widgets/') || f.path.contains('/pages/'),
      );
      expect(widgets, isNotEmpty);

      for (final File file in widgets) {
        final String src = code(file);
        expect(src.contains('Map<String, Object?>'), isFalse);
        expect(src.contains('Map<String, dynamic>'), isFalse);
      }
    });

    test('only the data layer names the RPC', () {
      final Iterable<File> offenders = profileSources.where((File f) {
        if (f.path.contains('/data/')) return false;
        return code(f).contains('get_my_vendor_profile');
      });

      expect(
        offenders.map((File f) => f.path),
        isEmpty,
        reason: 'the RPC name belongs in the data layer alone',
      );
    });

    test('no source names a backend function, policy or SQLSTATE', () {
      _expectAbsent(profileSources, <String>[
        'has_organization_permission',
        'get_vendor_super_admin_context',
        'get_my_portal_context',
        'SQLSTATE',
        '42501',
        '22023',
        '22P02',
        'insufficient_privilege',
      ], allowInComments: true);
    });

    test('a portal kind is read for its label and for nothing else', () {
      final RegExp anyUse = RegExp(r'PortalKind\.\w+(\.\w+)?');

      for (final File file in profileSources) {
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
  });

  group('the route and navigation entry', () {
    test('the Settings destination is routable, and only for the Vendor', () {
      final String navigation = code(
        sources.firstWhere(
          (File f) => f.path.endsWith('vendor_navigation.dart'),
        ),
      );

      expect(navigation.contains("static const String settings ="), isTrue);
      expect(navigation.contains("'\$prefix/settings'"), isTrue);
      // No longer a placeholder.
      expect(
        RegExp(
          r"RoleDestination\.soon\(\s*label: 'Settings'",
        ).hasMatch(navigation),
        isFalse,
        reason: 'Settings must no longer be a "Soon" placeholder',
      );

      // And no other role gained one.
      for (final String other in <String>[
        'retailer_owner_navigation.dart',
        'retailer_manager_navigation.dart',
        'sales_staff_navigation.dart',
      ]) {
        final String src = code(
          sources.firstWhere((File f) => f.path.endsWith(other)),
        );
        expect(
          src.contains('Settings'),
          isFalse,
          reason: '$other must not gain a Settings destination',
        );
        expect(src.contains('settings'), isFalse);
      }
    });

    test('the router renders the real page for the route', () {
      final String router = code(
        sources.firstWhere((File f) => f.path.endsWith('app_router.dart')),
      );

      expect(router.contains('VendorCompanyProfilePage'), isTrue);
      expect(
        RegExp(
          r'_placeholder\([^)]*VendorNavigation\.settings',
          dotAll: true,
        ).hasMatch(router),
        isFalse,
        reason: 'the Settings route must not be a placeholder',
      );
    });

    test('no company or profile shortcut was added to another screen', () {
      // The Dashboard's quick links reach only the five built modules they
      // already reached; a shortcut this product never had is not invented here.
      final String links = code(
        sources.firstWhere(
          (File f) => f.path.endsWith('vendor_dashboard_quick_links.dart'),
        ),
      );

      for (final String forbidden in <String>[
        'Settings',
        'settings',
        'Company',
        'Profile',
        'Account',
      ]) {
        expect(
          links.contains(forbidden),
          isFalse,
          reason: 'no quick link may point at the company/profile screen',
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
