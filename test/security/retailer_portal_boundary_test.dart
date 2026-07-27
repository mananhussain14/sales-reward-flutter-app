@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static assertions about the Retailer portal's security boundary.
///
/// These read the source rather than exercising it, which makes them the
/// cheapest possible guard against the boundary eroding under deadline
/// pressure — the kind of regression a behavioural test cannot see. They are the
/// Retailer counterpart of `no_secrets_test.dart`, and they exist because every
/// property below is one an ordinary-looking edit could quietly reverse.
///
/// The single claim they defend: **the client nominates nothing.** Not an
/// organization, not a role, not a permission, not a person. The backend derives
/// all of it from `auth.uid()`, and there is no parameter through which a client
/// could offer an alternative.
void main() {
  late List<File> lib;
  late List<File> retailerSources;

  /// The one file whose *basename* is [name].
  ///
  /// Matched on the separator deliberately: a bare `endsWith` would let
  /// `supabase_retailer_owner_overview_repository.dart` satisfy a lookup for
  /// `retailer_owner_overview_repository.dart`, so an assertion about the domain
  /// interface would silently run against the data implementation instead.
  File named(String name) {
    final Iterable<File> matches = lib.where(
      (File f) => f.path.endsWith(Platform.pathSeparator + name),
    );
    expect(matches, hasLength(1), reason: 'expected exactly one $name');
    return matches.single;
  }

  /// [file]'s executable source, with comments removed.
  ///
  /// Every scan below is for a token that must not appear in *code*. The same
  /// tokens are legitimately discussed in the documentation comments that
  /// explain why the client does not send, compare or display them — which is
  /// the whole point of those comments, and not something to punish.
  String codeOf(File file) {
    return file
        .readAsLinesSync()
        .map((String line) => line.trimLeft())
        .where(
          (String line) =>
              !line.startsWith('//') &&
              !line.startsWith('*') &&
              !line.startsWith('/*'),
        )
        .join('\n');
  }

  setUpAll(() {
    lib = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .toList();

    // Everything this milestone added or touched on the Retailer side.
    retailerSources = lib
        .where(
          (File f) =>
              f.path.contains('retailer_owner') ||
              f.path.contains('retailer_manager'),
        )
        .toList();
  });

  test('the scan is non-vacuous', () {
    expect(lib, isNotEmpty);
    expect(retailerSources, isNotEmpty);
  });

  // -------------------------------------------------------------------------
  group('the RPCs are called with zero arguments', () {
    test('the Overview data source names one RPC and passes nothing', () {
      final String src = codeOf(
        named('retailer_owner_overview_rpc_data_source.dart'),
      );

      // The function name appears exactly once, as a named constant.
      expect(
        "'get_retailer_owner_portal_context'".allMatches(src).length,
        1,
        reason: 'the RPC name must be written in exactly one place',
      );

      // No params map at all — not even an empty one, which would be the
      // obvious place for someone to later add "just one" selector.
      expect(src.contains('params:'), isFalse);
      expect(src.contains('{}'), isFalse);
    });

    test('neither RPC call site carries an identity argument', () {
      for (final String file in <String>[
        'retailer_owner_overview_rpc_data_source.dart',
        'portal_context_data_source.dart',
      ]) {
        final String src = codeOf(named(file));

        for (final String forbidden in <String>[
          'organization_id',
          'p_organization',
          'retailer_id',
          'p_retailer',
          'user_id',
          'p_user',
          'auth_user_id',
          'profile_id',
          'membership_id',
          'p_membership',
          'vendor_id',
          'tenant',
          'role_code',
          'p_role',
          'permission_code',
          'p_permission',
          'access_token',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '$file must pass no $forbidden argument',
          );
        }
      }
    });

    test('the invoker typedefs take no parameters', () {
      // The security property is enforced by the type system: a nullary
      // function cannot be handed an organization id. This asserts the shape
      // stays nullary, so widening it becomes a deliberate, visible edit.
      final String src = codeOf(
        named('retailer_owner_overview_rpc_data_source.dart'),
      );

      expect(
        src.contains(
          'typedef RetailerOwnerOverviewInvoker = '
          'Future<Object?> Function();',
        ),
        isTrue,
        reason: 'the invoker must take no arguments',
      );
    });

    test('the repository interface exposes no parameter either', () {
      final String src = codeOf(
        named('retailer_owner_overview_repository.dart'),
      );

      expect(
        src.contains('Future<RetailerOverviewResult> overview();'),
        isTrue,
        reason: 'the one read must take no arguments',
      );
    });
  });

  // -------------------------------------------------------------------------
  group('no direct table access', () {
    test('no Retailer source reads or writes a table', () {
      // `retailer_shops` carries exactly one vendor-scoped SELECT policy, which
      // returns zero rows to a Retailer Owner — so a direct count would render
      // `0` for every Owner and look entirely plausible. The counts come from
      // SQL for that reason, and this asserts nobody reintroduces the read.
      for (final File file in retailerSources) {
        final String src = codeOf(file);
        for (final String forbidden in <String>[
          '.from(',
          '.select(',
          '.insert(',
          '.update(',
          '.upsert(',
          '.delete(',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} performs direct table access ($forbidden)',
          );
        }
      }
    });

    test('no Retailer source names a Retailer table', () {
      for (final File file in retailerSources) {
        final List<String> lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final String trimmed = lines[i].trimLeft();
          // Table names are legitimately *discussed* in the comments that
          // explain why the client does not read them.
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;

          for (final String table in <String>[
            "'retailer_shops'",
            "'organizations'",
            "'organization_members'",
            "'member_roles'",
            "'role_permissions'",
            "'profiles'",
          ]) {
            expect(
              lines[i].contains(table),
              isFalse,
              reason: '${file.path}:${i + 1} names $table',
            );
          }
        }
      }
    });

    test('the Overview repository performs no write of any kind', () {
      final String src = codeOf(
        named('supabase_retailer_owner_overview_repository.dart'),
      );

      for (final String forbidden in <String>[
        '.insert(',
        '.update(',
        '.delete(',
        '.upsert(',
        'rpc(\'set_',
        'rpc(\'create_',
        'rpc(\'update_',
        'rpc(\'delete_',
      ]) {
        expect(src.contains(forbidden), isFalse, reason: 'found $forbidden');
      }
    });
  });

  // -------------------------------------------------------------------------
  group('no authorization is decided in Dart', () {
    test('no Retailer source compares a permission code', () {
      // Permission codes may be *named* in documentation that explains what the
      // backend gates on. A comparison would be the client deciding
      // authorization, which SQL owns.
      for (final File file in retailerSources) {
        final List<String> lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final String trimmed = lines[i].trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;

          for (final String code in <String>[
            'RETAILER_PORTAL_READ',
            'RETAILER_SHOPS_READ',
            'RETAILER_STAFF_READ',
            'RETAILER_STAFF_MANAGE',
            'RETAILER_PRODUCTS_READ',
            'RECEIPT_SUBMIT',
          ]) {
            expect(
              lines[i].contains(code),
              isFalse,
              reason: '${file.path}:${i + 1} names permission $code in code',
            );
          }
        }
      }
    });

    test('the capability type can only hide a destination', () {
      // Its whole surface is a boolean lookup. A method that returned a Failure,
      // threw, or gated a call would make a presentation hint into a gate.
      final String src = codeOf(named('retailer_capabilities.dart'));

      expect(src.contains('throw'), isFalse);
      expect(src.contains('Failure'), isFalse);
      expect(src.contains('assert'), isFalse);
    });

    test(
      'the Overview screen does not consult a capability to decide its read',
      () {
        // The page may read capabilities to decide what to *advertise*. It must
        // not wrap the load in one — the RPC is the authority, and a hint that
        // suppressed the call would turn a false hint into a denial the backend
        // never issued.
        final String src = codeOf(named('retailer_owner_overview_page.dart'));

        expect(
          RegExp(r'if\s*\(.*viewRetailerOverview.*\)').hasMatch(src),
          isFalse,
          reason: 'the overview read must not be gated on a capability hint',
        );
        expect(
          src.contains('cubit.load()'),
          isFalse,
          reason: 'the shell owns the initial load; the page only retries',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  group('nothing privileged or identifying reaches the client', () {
    test('the Overview entity holds no identifier', () {
      final String src = codeOf(named('retailer_owner_overview.dart'));

      for (final String forbidden in <String>[
        'organizationId',
        'membershipId',
        'profileId',
        'userId',
        'authUserId',
        'shopId',
        'relationshipId',
        'roleId',
        'permissionId',
      ]) {
        expect(
          src.contains(forbidden),
          isFalse,
          reason: 'the overview must carry no $forbidden',
        );
      }
    });

    test('no Retailer source names a service-role key', () {
      for (final File file in retailerSources) {
        final String src = codeOf(file);
        for (final String forbidden in <String>[
          'SUPABASE_SERVICE_ROLE_KEY',
          'service_role',
          'serviceRoleKey',
        ]) {
          expect(src.contains(forbidden), isFalse, reason: file.path);
        }
      }
    });

    test('user-facing copy contains no backend identifier or code', () {
      final String src = codeOf(named('retailer_owner_overview_copy.dart'));

      for (final String forbidden in <String>[
        '42501',
        'SQLSTATE',
        'PostgrestException',
        'public.',
        'auth.uid',
        'get_retailer_owner_portal_context',
        'retailer_shops',
        'RETAILER_PORTAL_READ',
      ]) {
        expect(
          src.contains(forbidden),
          isFalse,
          reason: 'user-facing copy must not mention $forbidden',
        );
      }
    });

    test('no Retailer presentation source touches Supabase', () {
      final Iterable<File> presentation = retailerSources.where(
        (File f) =>
            f.path.contains('/presentation/') || f.path.contains('/shells/'),
      );
      expect(presentation, isNotEmpty);

      for (final File file in presentation) {
        final String src = codeOf(file);
        expect(
          src.contains('Supabase.instance'),
          isFalse,
          reason: '${file.path} reaches Supabase directly',
        );
        expect(
          src.contains('package:supabase_flutter'),
          isFalse,
          reason: '${file.path} imports the SDK outside the data layer',
        );
      }
    });

    test('no cubit state holds an unparsed map', () {
      final String src = codeOf(named('retailer_owner_overview_state.dart'));

      for (final String forbidden in <String>[
        'Map<String, dynamic>',
        'Map<String, Object?>',
        'dynamic ',
      ]) {
        expect(
          src.contains(forbidden),
          isFalse,
          reason: 'state must hold parsed domain types only',
        );
      }
    });
  });

  // -------------------------------------------------------------------------
  group('Vendor and Retailer stay isolated', () {
    test('the Retailer Owner shell provides no Vendor cubit', () {
      // Two shells that share no cubit cannot leak a selection or a notice into
      // each other.
      final String src = codeOf(named('retailer_owner_shell.dart'));

      expect(
        RegExp(r'BlocProvider<Vendor\w+>').hasMatch(src),
        isFalse,
        reason: 'no Vendor cubit may be provided inside the Retailer shell',
      );
      expect(src.contains('VendorNavigation'), isFalse);
    });

    test('the Vendor shell provides no Retailer Owner cubit', () {
      final String src = codeOf(named('vendor_shell.dart'));

      expect(src.contains('RetailerOwnerOverviewCubit'), isFalse);
      expect(src.contains('RetailerOwnerNavigation'), isFalse);
    });

    test('each role navigation owns a disjoint route prefix', () {
      final String owner = codeOf(named('retailer_owner_navigation.dart'));
      final String manager = codeOf(named('retailer_manager_navigation.dart'));

      expect(owner.contains("prefix = '/retailer-owner'"), isTrue);
      expect(manager.contains("prefix = '/retailer-manager'"), isTrue);
      // The Manager has no route into the Owner's tree.
      expect(manager.contains('/retailer-owner'), isFalse);
    });

    test('the Retailer Manager has no Overview destination', () {
      // The Owner Overview RPC hard-filters RETAILER_OWNER, so a Manager
      // destination pointing at it would be an advertised refusal.
      final String src = codeOf(named('retailer_manager_navigation.dart'));

      expect(src.contains('viewRetailerOverview'), isFalse);
      expect(src.contains("label: 'Overview'"), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  test('dart_defines.json is still untracked', () {
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
