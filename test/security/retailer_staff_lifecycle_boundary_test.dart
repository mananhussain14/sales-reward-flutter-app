@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-safety assertions for the Retailer staff **lifecycle** write.
///
/// The companion to `retailer_manage_staff_shops_boundary_test.dart`, narrowed
/// to the one operation that decides whether a colleague may work at all. These
/// read the source rather than exercise it, which makes them the cheapest guard
/// against the boundary eroding under deadline pressure — the kind of regression
/// a behavioural test cannot see, because the code that erodes it usually still
/// works.
///
/// The property they defend, stated once: **the client never decides who may be
/// deactivated.** The deployed function derives the Retailer from `auth.uid()`,
/// re-reads the target's complete ACTIVE role set under a row lock, and refuses
/// every Owner, multi-role, role-less, invited, suspended, cross-tenant and self
/// target on its own terms. Every assertion below is some form of "and nothing
/// here tries to help".
void main() {
  late List<File> sources;
  late List<File> staffSources;

  /// The **one** file permitted to name the write RPC and its two parameters.
  late File lifecycleDataSourceFile;
  late String lifecycleDataSource;

  /// Every `lib/` source except that one.
  late List<File> nonLifecycleSources;

  /// The file's executable lines only.
  ///
  /// Every check below is about what the code *does*. The doc comments in this
  /// feature deliberately discuss the things the code must not do — "no direct
  /// table write", "no service-role client", "the Owner exclusion" — and a scan
  /// that could not tell the two apart would either fail on its own
  /// documentation or force the documentation to stop naming what it protects
  /// against.
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
    staffSources = sources
        .where((File f) => f.path.contains('/features/staff/'))
        .toList();
    lifecycleDataSourceFile = sources.firstWhere(
      (File f) =>
          f.path.endsWith('retailer_staff_lifecycle_rpc_data_source.dart'),
    );
    lifecycleDataSource = code(lifecycleDataSourceFile);
    nonLifecycleSources = sources
        .where((File f) => f.path != lifecycleDataSourceFile.path)
        .toList();
  });

  test('the scan is non-vacuous', () {
    expect(staffSources.length, greaterThan(10));
    expect(nonLifecycleSources.length, greaterThan(50));
  });

  group('the write RPC is named once, exactly', () {
    test('only the lifecycle data source names it, anywhere in lib/', () {
      // Scanned over the WHOLE of `lib/`, not just the staff feature: a call
      // site added in another feature would escape a feature-scoped guard.
      _expectAbsent(nonLifecycleSources, <String>[
        'set_retailer_staff_membership_status',
      ], allowInComments: true);
    });

    test('the constant is the deployed name', () {
      final RegExp rpcNames = RegExp(r"const String \w+Rpc =\s*'([^']+)'");
      expect(
        rpcNames
            .allMatches(lifecycleDataSource)
            .map((RegExpMatch m) => m.group(1)!)
            .toList(),
        <String>['set_retailer_staff_membership_status'],
      );
    });

    test('the invoker is called through the injected client, once', () {
      expect(
        RegExp(r'client\.rpc<Object\?>').allMatches(lifecycleDataSource).length,
        1,
      );
    });
  });

  group('the request carries exactly two arguments', () {
    test('the parameter set is exactly the contract\'s', () {
      final RegExp params = RegExp(r"'(p_[a-z_]+)'");
      expect(
        params
            .allMatches(lifecycleDataSource)
            .map((RegExpMatch m) => m.group(1)!)
            .toSet(),
        <String>{'p_membership_id', 'p_status'},
      );
    });

    test('no identity, tenant, role or permission argument appears', () {
      for (final String forbidden in <String>[
        'organization_id',
        'retailer_id',
        'user_id',
        'profile_id',
        'p_actor',
        'p_role',
        'role_code',
        'permission_code',
        'target_organization_id',
        'target_permission_code',
        'access_token',
        'tenant',
        'p_shop_ids',
        'p_audit',
      ]) {
        expect(
          lifecycleDataSource.contains(forbidden),
          isFalse,
          reason: 'the lifecycle write must pass no $forbidden argument',
        );
      }
    });

    test('the invoker typedef takes those two and nothing else', () {
      expect(lifecycleDataSource, contains('required String membershipId'));
      expect(lifecycleDataSource, contains('required String status'));
    });
  });

  group('no direct membership write, no privileged client', () {
    test('no staff source writes a table', () {
      // `organization_members` is SELECT-only for the browser with no
      // INSERT/UPDATE/DELETE privilege of any kind, so a direct write would not
      // merely be poor layering — it would not work.
      _expectAbsent(staffSources, <String>[
        '.from(',
        '.insert(',
        '.update(',
        '.upsert(',
        '.delete(',
      ], allowInComments: true);
    });

    test('no staff source names a backend table in code', () {
      _expectAbsent(staffSources, <String>[
        "'organization_members'",
        "'member_roles'",
        "'profiles'",
        "'roles'",
        "'audit_logs'",
      ], allowInComments: true);
    });

    test('no staff source names a privileged key or reads an environment', () {
      _expectAbsent(staffSources, <String>[
        'SUPABASE_SERVICE_ROLE_KEY',
        'service_role',
        'serviceRoleKey',
        'sb_secret_',
        'SERVICE_KEY',
        'String.fromEnvironment',
        'Platform.environment',
        'SharedPreferences',
      ]);
    });

    test('the SDK is imported only in the data layer', () {
      for (final File file in staffSources) {
        if (file.path.contains('/data/')) continue;
        final String src = code(file);
        expect(
          src.contains('package:supabase_flutter'),
          isFalse,
          reason: '${file.path} imports the Supabase SDK outside data/',
        );
      }
    });
  });

  group('nothing retries, and nothing is optimistic', () {
    test('no lifecycle source introduces a retry or a loop over the write', () {
      final Iterable<File> lifecycleSources = sources.where(
        (File f) => f.path.contains('retailer_staff_lifecycle'),
      );
      expect(lifecycleSources, isNotEmpty);

      for (final File file in lifecycleSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'retryWrite',
          'RetryPolicy',
          'exponentialBackoff',
          'Timer.periodic',
          'while (',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} introduces $forbidden on a write path',
          );
        }
      }
    });

    test('the busy guard is membership-scoped, never global', () {
      // The regression this pins: an earlier design guarded `apply` on "any
      // request in flight" while disabling only the asking row, which left every
      // other button visibly enabled and silently inert. The guard must read the
      // membership it was asked about.
      final File cubit = sources.firstWhere(
        (File f) => f.path.endsWith('retailer_staff_lifecycle_cubit.dart'),
      );
      final String src = code(cubit);

      expect(
        src.contains('if (state.isBusyFor(membershipId))'),
        isTrue,
        reason: 'apply must refuse only a duplicate for the SAME membership',
      );
      for (final String globalGuard in <String>[
        'if (state.isBusy)',
        'if (state.hasAnyInFlight)',
      ]) {
        expect(
          src.contains(globalGuard),
          isFalse,
          reason: 'a global busy guard would silently ignore enabled controls',
        );
      }
    });

    test('the card disables exactly what the cubit refuses', () {
      // The two halves of "an enabled control is never silently ignored": the
      // card binds its disabled state to the same per-membership predicate the
      // cubit guards on.
      final File page = sources.firstWhere(
        (File f) => f.path.endsWith('retailer_staff_page.dart'),
      );
      final File card = sources.firstWhere(
        (File f) => f.path.endsWith('retailer_staff_member_card.dart'),
      );

      expect(code(page).contains('state.isBusyFor(id)'), isTrue);
      expect(
        code(card).contains('onPressed: lifecycleBusy ? null : onLifecycle'),
        isTrue,
      );
      // And nothing binds a control to the whole-cubit flag.
      expect(code(page).contains('hasAnyInFlight'), isFalse);
      expect(code(card).contains('hasAnyInFlight'), isFalse);
    });

    test('no cubit writes a membership status onto a roster row', () {
      // The roster is the only authority on what a membership holds. A local
      // patch would be this client inventing a state the backend never
      // reported.
      final File cubit = sources.firstWhere(
        (File f) => f.path.endsWith('retailer_staff_lifecycle_cubit.dart'),
      );
      final String src = code(cubit);
      expect(src.contains('RetailerMemberStatus'), isFalse);
      expect(src.contains('copyWith(status'), isFalse);
    });
  });

  group('the request vocabulary is closed', () {
    test('INACTIVE is never expressible in the staff feature', () {
      // Scoped to `features/staff/`, not the whole of `lib/`. `INACTIVE` is a
      // legitimate **Vendor product** status token — `set_vendor_product_status`
      // accepts it, and the shared badge map keys on it — so a repository-wide
      // ban would fail on unrelated, correct code. What must never happen is a
      // staff *membership* being described or requested with it: the column's
      // vocabulary has no such value, and "Inactive" is only ever the display
      // word for `DEACTIVATED` here.
      for (final File file in staffSources) {
        expect(
          code(file).contains("'INACTIVE'"),
          isFalse,
          reason: '${file.path} could send the display word INACTIVE',
        );
      }

      // And the one file that builds the request payload names neither the
      // display word nor any status this operation may not request.
      for (final String forbidden in <String>[
        "'INACTIVE'",
        "'SUSPENDED'",
        "'INVITED'",
      ]) {
        expect(lifecycleDataSource.contains(forbidden), isFalse);
      }
    });

    test('the stored tokens live in the pure domain model alone', () {
      // `ACTIVE`, `DEACTIVATED`, `SUSPENDED` and `INVITED` may be written in
      // `staff/domain/entities/` — that is where the response enum and the
      // closed request vocabulary are declared — and nowhere else in the staff
      // feature. Everything downstream carries an enum, so no screen, cubit,
      // parser or data source can assemble a status of its own.
      final Iterable<File> outsideDomain = staffSources.where(
        (File f) => !f.path.contains('/domain/entities/'),
      );

      for (final File file in outsideDomain) {
        final String src = code(file);
        for (final String token in <String>[
          "'ACTIVE'",
          "'DEACTIVATED'",
          "'SUSPENDED'",
          "'INVITED'",
        ]) {
          expect(
            src.contains(token),
            isFalse,
            reason: '${file.path} writes a backend status literal',
          );
        }
      }
    });

    test('the eligible role codes are declared once', () {
      final Iterable<File> namingRoles = staffSources.where(
        (File f) =>
            code(f).contains("'RETAILER_MANAGER'") ||
            code(f).contains("'RETAILER_OWNER'"),
      );

      // The lifecycle role set, the invitation role enum and the roster's role
      // label map are the only three places a Retailer role code appears — and
      // none of them compares one to decide authorization.
      for (final File file in namingRoles) {
        expect(
          file.path.contains('/domain/entities/') ||
              file.path.endsWith('retailer_staff_copy.dart'),
          isTrue,
          reason: '${file.path} names a role code outside the approved files',
        );
      }
    });
  });

  group('the control is confined to the Retailer Owner surface', () {
    test('only the Owner shell provides the lifecycle cubit', () {
      final Iterable<File> providers = sources.where(
        (File f) =>
            f.path.contains('/shells/') &&
            code(f).contains('RetailerStaffLifecycleCubit'),
      );

      expect(providers.map((File f) => f.path), <String>[
        'lib/app/shells/retailer_owner/retailer_owner_shell.dart',
      ]);
    });

    test('no Vendor or Sales Staff source names the lifecycle', () {
      final Iterable<File> foreign = sources.where(
        (File f) =>
            f.path.contains('/presentation/vendor/') ||
            f.path.contains('/presentation/sales_staff/') ||
            f.path.contains('/shells/vendor/') ||
            f.path.contains('/shells/sales_staff/') ||
            f.path.contains('/shells/retailer_manager/'),
      );
      expect(foreign, isNotEmpty);

      for (final File file in foreign) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'RetailerStaffLifecycleCubit',
          'RetailerStaffLifecycleAction',
          'confirmRetailerStaffLifecycle',
          'set_retailer_staff_membership_status',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} must carry no staff lifecycle control',
          );
        }
      }
    });

    test('the invitation surface carries no lifecycle action', () {
      final Iterable<File> invitationSurfaces = staffSources.where(
        (File f) =>
            f.path.endsWith('retailer_invitation_card.dart') ||
            f.path.endsWith('retailer_invite_staff_form.dart'),
      );
      expect(invitationSurfaces, isNotEmpty);

      for (final File file in invitationSurfaces) {
        final String src = code(file);
        expect(src.contains('Lifecycle'), isFalse);
        expect(src.contains('Deactivate'), isFalse);
        expect(src.contains('Reactivate'), isFalse);
      }
    });
  });

  group('the lifecycle diagnostic stays outside this feature', () {
    // This group used to assert the diagnostic did not exist anywhere. It now
    // ships, in `features/auth`, so the assertion has been NARROWED rather than
    // dropped: the property still worth defending is that the *staff lifecycle
    // write* feature neither names the diagnostic RPC nor carries its
    // vocabulary or copy. Every write protection in this file is unchanged.
    test('no staff source names the diagnostic RPC or its vocabulary', () {
      // Scanned over the staff feature AND every non-diagnostic source, so a
      // call site added in a shell or another feature is caught too.
      final List<File> outsideDiagnostic = sources
          .where(
            (File f) => !_approvedDiagnosticPaths.any(
              (String approved) => f.path.endsWith(approved),
            ),
          )
          .toList();

      expect(
        outsideDiagnostic.length,
        greaterThan(50),
        reason: 'the scan must not be vacuous',
      );
      // The exclusion list must actually exclude something, or the scan below
      // is asserting a property no file could violate.
      expect(outsideDiagnostic.length, lessThan(sources.length));

      _expectAbsent(outsideDiagnostic, <String>[
        'get_my_lifecycle_access_state',
        'ORGANIZATION_INACTIVE',
        'MEMBERSHIP_INACTIVE',
        'PROFILE_INACTIVE',
        'NO_SUPPORTED_ACCESS',
      ], allowInComments: true);
    });

    test('no staff source carries the approved inactive-access copy', () {
      for (final File file in staffSources) {
        final String src = code(file);
        expect(src.contains('This Retailer is currently inactive'), isFalse);
        expect(
          src.contains('Your access to this Retailer is inactive'),
          isFalse,
        );
      }
    });

    test('the staff lifecycle write does not consult the diagnostic', () {
      // The write must never gate itself on a read: the deployed function
      // re-derives everything it needs from auth.uid() under its own row locks.
      for (final File file in staffSources) {
        final String src = code(file);
        expect(src.contains('LifecycleAccessRepository'), isFalse);
        expect(src.contains('LifecycleAccessCubit'), isFalse);
      }
    });
  });

  group('no backend artefact lives in the Flutter repository', () {
    test('there is no migration, Edge Function or SQL file', () {
      for (final String path in <String>[
        'supabase',
        'migrations',
        'functions',
      ]) {
        expect(
          Directory(path).existsSync(),
          isFalse,
          reason: 'the Flutter repository must contain no backend directory',
        );
      }

      final Iterable<File> sqlFiles = Directory('.')
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (File f) =>
                f.path.endsWith('.sql') &&
                !f.path.contains('/build/') &&
                !f.path.contains('/.dart_tool/'),
          );

      expect(sqlFiles.map((File f) => f.path), isEmpty);
    });
  });
}

/// The only files permitted to name the diagnostic RPC, its wire vocabulary or
/// its approved copy.
///
/// Kept as an explicit allow-list rather than a directory prefix so that adding
/// a file to the diagnostic feature is a visible edit here, reviewed alongside
/// the code it exempts.
const List<String> _approvedDiagnosticPaths = <String>[
  'features/auth/data/models/lifecycle_access_parser.dart',
  'features/auth/data/datasources/lifecycle_access_rpc_data_source.dart',
  'features/auth/presentation/widgets/lifecycle_access_copy.dart',
];

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
