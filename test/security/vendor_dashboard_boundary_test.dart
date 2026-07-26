@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-safety assertions for the Vendor Dashboard summary boundary.
///
/// The companion to `no_secrets_test.dart`, `receipt_boundary_test.dart` and the
/// five Vendor read boundaries that precede it. These read the source rather than
/// exercise it, which makes them the cheapest guard against the boundary eroding
/// under deadline pressure — the kind of regression a behavioural test cannot
/// see, because the code that erodes it usually still works.
///
/// This surface has a failure mode the others do not. Four numbers with no
/// context are four claims, and **two of them are claims about the deployment
/// rather than about the organization whose name sits at the top of the page**.
/// So alongside the usual boundary properties, this file defends the *wording*.
///
/// Eight properties are defended, stated once each:
///
/// * **The client sends nothing at all.** The read takes zero arguments — no
///   identity, tenant, role, permission, status or period.
/// * **The client never reads a protected table.** Not `organization_members`,
///   `roles`, `permissions`, `audit_logs`, `organizations`, `profiles` or
///   `auth.users` — and issues no `count` head request either.
/// * **The client re-derives no metric.** No sum, filter, join or arithmetic
///   anywhere; the four figures arrive already computed.
/// * **The organization name comes from the trusted session context**, and from
///   exactly one place.
/// * **No global figure is labelled as the Vendor's**, and the all-time audit
///   total is never labelled as a window.
/// * **No metric is invented.** No Retailer, Product, shop, assignment or
///   invitation count; no chart, trend, percentage, revenue or sales figure.
/// * **The client never writes**, and offers no affordance that could.
/// * **A denial is never rendered as zeros**, and no zero is ever fabricated.
void main() {
  late List<File> sources;
  late List<File> dashboardSources;
  late String rpcDataSource;
  late String copy;

  /// The file's executable lines only.
  ///
  /// Every check below is about what the code *does*. The doc comments in this
  /// feature deliberately discuss the things the code must not do — "do not label
  /// it your roles", "no organization id is sent" — and a scan that could not tell
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
    // The Vendor slice only. `features/dashboard/` also holds the Retailer Owner
    // overview page, which belongs to a different role and a different contract;
    // scanning it here would make this file assert things about code this
    // milestone did not write.
    dashboardSources = sources
        .where(
          (File f) =>
              f.path.contains('/features/dashboard/') &&
              !f.path.contains('/retailer_owner/'),
        )
        .toList();
    rpcDataSource = code(
      sources.firstWhere(
        (File f) => f.path.endsWith('vendor_dashboard_rpc_data_source.dart'),
      ),
    );
    copy = code(
      sources.firstWhere(
        (File f) => f.path.endsWith('vendor_dashboard_copy.dart'),
      ),
    );
  });

  test('the feature is non-empty (the scan would pass vacuously)', () {
    expect(dashboardSources, isNotEmpty);
    expect(dashboardSources.length, greaterThan(8));
  });

  group('no privileged key reaches the device', () {
    test('no source names a service-role or secret key', () {
      _expectAbsent(dashboardSources, <String>[
        'SUPABASE_SERVICE_ROLE_KEY',
        'service_role',
        'serviceRoleKey',
        'sb_secret_',
        'SERVICE_KEY',
      ]);
    });

    test('no source reads an environment value of its own', () {
      for (final File file in dashboardSources) {
        final String src = code(file);
        expect(src.contains('String.fromEnvironment'), isFalse);
        expect(src.contains('Platform.environment'), isFalse);
      }
    });

    test('no source hardcodes a credential', () {
      _expectAbsent(dashboardSources, <String>[
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

      expect(names, <String>['get_vendor_admin_dashboard_summary']);
    });

    test('no parameter name of any kind exists in the feature', () {
      // The function is declared with an empty parameter list. There is nothing
      // to send, so no `p_` key may appear anywhere in this slice.
      final RegExp params = RegExp(r"'(p_[a-z_]+)'");
      for (final File file in dashboardSources) {
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
          'client.rpc<Object?>(vendorDashboardSummaryRpc)',
        ),
        isTrue,
      );
    });

    test(
      'no identity, tenant, role, permission, status or period argument',
      () {
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
          'tenant',
          'p_role',
          'role_code',
          'permission_code',
          'p_permission',
          'p_status',
          'p_from',
          'p_to',
          'p_since',
          'p_period',
          'p_days',
          'p_limit',
          'p_offset',
          "'email'",
          'access_token',
        ]) {
          expect(
            rpcDataSource.contains(forbidden),
            isFalse,
            reason: 'the dashboard RPC must pass no $forbidden argument',
          );
        }
      },
    );

    test('the invoker type carries no parameter', () {
      expect(
        rpcDataSource.contains(
          'typedef VendorDashboardSummaryInvoker = Future<Object?> Function();',
        ),
        isTrue,
        reason: 'the zero-argument shape must be enforced by the type',
      );
    });
  });

  group('no table is read directly', () {
    test('no source queries the four counted tables, or organizations', () {
      // The web assembles this page from four direct `head: true, count: exact`
      // reads. Reproducing that here would move the metric definitions — including
      // which two are not tenant-scoped — into a second client free to drift.
      _expectAbsent(dashboardSources, <String>[
        '.from(',
        "'organization_members'",
        "'roles'",
        "'permissions'",
        "'audit_logs'",
        "'organizations'",
        "'profiles'",
        "'member_roles'",
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
        'CountOption',
      ], allowInComments: true);
    });

    test('nothing anywhere touches auth.users', () {
      _expectAbsent(dashboardSources, <String>[
        'auth.users',
        'auth_users',
        'authUsers',
        '.admin.',
        'getUserById',
        'listUsers',
      ], allowInComments: true);
    });

    test('the Vendor resolution is not reimplemented', () {
      for (final File file in dashboardSources) {
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

  group('no metric is derived on the client', () {
    test('no source sums, folds or averages anything itself', () {
      for (final File file in dashboardSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          '.fold(',
          '.reduce(',
          'totalOf',
          'sumOf',
          'percentage',
          'percent',
          'delta',
          'trend',
          'average',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} derives a figure the backend did not send',
          );
        }
      }
    });

    test('the only length read anywhere is the summary row-count guard', () {
      // `.length` is how "exactly one row" is checked, and that is the single
      // legitimate use of it in this slice — a count read off a collection
      // instead of off the backend would be a figure this client invented.
      for (final File file in dashboardSources) {
        final String src = code(file);
        final Iterable<String> uses = RegExp(
          r'[\w.\]\)]+\.length',
        ).allMatches(src).map((RegExpMatch m) => m.group(0)!);

        for (final String use in uses) {
          expect(
            use,
            'raw.length',
            reason:
                '${file.path} reads a length that is not the row-count '
                'guard',
          );
        }
      }
    });

    test('no count is passed through floating point', () {
      // A `bigint` normalised through a double has already been rounded, and the
      // conversion would launder a wrong number into a confident one.
      for (final File file in dashboardSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'roundToDouble',
          'toDouble',
          'double.parse',
          'num.parse',
          '.ceil(',
          '.floor(',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} converts a count through floating point',
          );
        }
      }
    });

    test('a zero is never substituted for a value that could not be read', () {
      for (final File file in dashboardSources) {
        final String src = code(file);
        for (final RegExp pattern in <RegExp>[
          RegExp(r'\?\?\s*0\b'),
          RegExp(r'Count\s*[:=]\s*0\b'),
          RegExp(r'\bclamp\('),
        ]) {
          expect(
            pattern.hasMatch(src),
            isFalse,
            reason: '${file.path} fabricates a zero count',
          );
        }
      }
    });
  });

  group('no authorization is decided on the client', () {
    test('no source names a permission or role code', () {
      // The backend requires Vendor Super Admin authority AND all three read
      // permissions, and refuses the whole summary generically when any is
      // missing. This client knows none of them.
      _expectAbsent(dashboardSources, <String>[
        'ORGANIZATION_MEMBERS_READ',
        'RBAC_READ',
        'AUDIT_LOGS_READ',
        "'VENDOR_SUPER_ADMIN'",
        "'RETAILER_OWNER'",
        "'RETAILER_MANAGER'",
        "'SALES_STAFF'",
      ], allowInComments: true);
    });

    test('no source names a backend function, policy or SQLSTATE', () {
      _expectAbsent(dashboardSources, <String>[
        'has_organization_permission',
        'get_vendor_super_admin_context',
        'get_my_portal_context',
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

      for (final File file in dashboardSources) {
        expect(
          uuidLiteral.hasMatch(code(file)),
          isFalse,
          reason: '${file.path} hardcodes an identifier',
        );
      }
    });

    test('no source infers authority from a token, claim or preference', () {
      for (final File file in dashboardSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'userMetadata',
          'appMetadata',
          'SharedPreferences',
          '.decodeJwt',
          'jwtDecode',
          "endsWith('@",
          'currentSession',
          'currentUser',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} infers authority from $forbidden',
          );
        }
      }
    });

    test('no route or affordance is gated on a count', () {
      // A figure is display data. Nothing may branch a route or an authorization
      // decision on one — "this Vendor has members, so show the Users link" would
      // be a client deciding access from data.
      for (final File file in dashboardSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'canView',
          'canOpen',
          'isAuthorized',
          'hasAccess',
          'allowIf',
          'Count > 0',
          'Count == 0',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} computes access from a count',
          );
        }
      }
    });
  });

  group('the organization name has exactly one source', () {
    test('it is read from the session context and nowhere else', () {
      final String page = code(
        sources.firstWhere(
          (File f) => f.path.endsWith('vendor_dashboard_page.dart'),
        ),
      );

      expect(
        page.contains('portalContext.vendor?.organizationName'),
        isTrue,
        reason: 'the name must come from the trusted session context',
      );
    });

    test('no other file in the feature holds an organization name', () {
      for (final File file in dashboardSources) {
        if (file.path.endsWith('vendor_dashboard_page.dart')) continue;
        expect(
          code(file).contains('organizationName'),
          isFalse,
          reason: '${file.path} is a second source for the organization name',
        );
      }
    });

    test('the entity and parser carry no name or id field', () {
      // The summary RPC returns counts only, and this build has nowhere to put a
      // name even if a future response carried one.
      for (final File file in dashboardSources.where(
        (File f) => f.path.contains('/domain/') || f.path.contains('/data/'),
      )) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'organizationName',
          'organizationId',
          'organization_name',
          'organization_id',
          'vendorId',
          'tenantId',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} models an organization identity',
          );
        }
      }
    });

    test('no source adds a second auth or session listener', () {
      for (final File file in dashboardSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'onAuthStateChange',
          'authStateChanges',
          'auth.onAuth',
          'StreamSubscription',
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

  group('the wording is honest about scope', () {
    test('no global figure is labelled as the Vendor\'s', () {
      for (final String forbidden in <String>[
        'Your roles',
        'Your active roles',
        'Vendor roles',
        'Roles assigned in this organization',
        'Your permissions',
        'Vendor permissions',
        'Assigned permissions',
        'Active permissions',
      ]) {
        expect(
          copy.contains(forbidden),
          isFalse,
          reason: 'the copy labels a catalogue figure as this Vendor\'s',
        );
      }
    });

    test('the catalogue labels say what they actually count', () {
      expect(copy.contains("'Active role definitions'"), isTrue);
      expect(copy.contains("'Permission definitions'"), isTrue);
      expect(
        copy.contains("'Available across the shared role catalogue'"),
        isTrue,
      );
      expect(
        copy.contains("'Available across the shared permission catalogue'"),
        isTrue,
      );
    });

    test('the audit total is never labelled as a window', () {
      for (final String forbidden in <String>[
        'Recent events',
        'Events today',
        'This week',
        'Last 30 days',
        'Last 7 days',
        'Today',
      ]) {
        expect(
          copy.contains(forbidden),
          isFalse,
          reason: 'the copy implies a window the product does not define',
        );
      }
      expect(copy.contains("'Audit events'"), isTrue);
      expect(copy.contains("'All recorded Vendor events'"), isTrue);
    });

    test('the member label is memberships, not profiles or all users', () {
      for (final String forbidden in <String>[
        'Active profiles',
        'Active users with roles',
        'Invited users',
        'All users',
      ]) {
        expect(copy.contains(forbidden), isFalse);
      }
      expect(copy.contains("'Active members'"), isTrue);
      expect(
        copy.contains("'Active memberships in this Vendor organization'"),
        isTrue,
      );
    });

    test('the scope distinction is carried by text, not only by colour', () {
      final String card = code(
        sources.firstWhere(
          (File f) => f.path.endsWith('vendor_dashboard_metric_card.dart'),
        ),
      );

      // A chip label and a chip glyph, both keyed off the scope enum, plus the
      // scope in the spoken sentence. Colour is the fourth channel, never the
      // only one.
      expect(card.contains('chipLabel'), isTrue);
      expect(card.contains('chipIcon'), isTrue);
      expect(card.contains('scope: scope.chipLabel'), isTrue);
    });
  });

  group('nothing fake is rendered', () {
    test('no metric outside the four is named', () {
      for (final File file in dashboardSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'retailerCount',
          'productCount',
          'shopCount',
          'assignmentCount',
          'invitationCount',
          'receiptCount',
          'claimCount',
          'coinCount',
          'payoutCount',
          'campaignCount',
          'revenue',
          'salesTotal',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} names a metric the contract does not return',
          );
        }
      }
    });

    test('no chart, trend or time-series widget exists', () {
      _expectAbsent(dashboardSources, <String>[
        'Chart',
        'chart',
        'Sparkline',
        'sparkline',
        'LineSeries',
        'BarSeries',
        'PieChart',
        'timeSeries',
        'CustomPaint',
      ], allowInComments: true);
    });

    test('no source invents a figure or a sample', () {
      for (final File file in dashboardSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'Example count',
          'Sample count',
          'Lorem',
          'mockSummary',
          'sampleSummary',
          'fakeSummary',
          'Coming soon',
          'placeholderCount',
          'demoValue',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} contains fabricated data',
          );
        }
      }
    });

    test('the metric card cannot render an unavailable figure', () {
      final String card = code(
        sources.firstWhere(
          (File f) => f.path.endsWith('vendor_dashboard_metric_card.dart'),
        ),
      );

      // The count is non-nullable, so there is no null branch that a later edit
      // could turn into a zero.
      expect(card.contains('final int value;'), isTrue);
      expect(card.contains('int? value'), isFalse);
      expect(card.contains('Unavailable'), isFalse);
    });

    test('the router no longer renders a placeholder for this route', () {
      final String router = code(
        sources.firstWhere((File f) => f.path.endsWith('app_router.dart')),
      );

      expect(router.contains('VendorDashboardPage'), isTrue);
      expect(
        RegExp(
          r'_placeholder\([^)]*VendorNavigation\.dashboard',
          dotAll: true,
        ).hasMatch(router),
        isFalse,
        reason: 'the Dashboard route must not be a placeholder',
      );
    });
  });

  group('quick links point only at built routes', () {
    test('the six unbuilt modules are not linked', () {
      final String links = code(
        sources.firstWhere(
          (File f) => f.path.endsWith('vendor_dashboard_quick_links.dart'),
        ),
      );

      for (final String unbuilt in <String>[
        'campaigns',
        'Campaigns',
        'claims',
        'Claims',
        'coins',
        'Coins',
        'payouts',
        'Payouts',
        'reports',
        'Reports',
        'settings',
        'Settings',
      ]) {
        expect(
          links.contains(unbuilt),
          isFalse,
          reason: '$unbuilt has no route, so no shortcut may point at it',
        );
      }
    });

    test('every link path is a VendorNavigation constant', () {
      final String links = code(
        sources.firstWhere(
          (File f) => f.path.endsWith('vendor_dashboard_quick_links.dart'),
        ),
      );

      final RegExp paths = RegExp(r'path:\s*([^,]+),');
      final List<String> found = paths
          .allMatches(links)
          .map((RegExpMatch m) => m.group(1)!.trim())
          .toList();

      expect(found, <String>[
        'VendorNavigation.retailers',
        'VendorNavigation.users',
        'VendorNavigation.roles',
        'VendorNavigation.products',
        'VendorNavigation.auditLogs',
      ]);
      // No hand-written path literal that could drift from the router.
      expect(RegExp(r"path:\s*'").hasMatch(links), isFalse);
    });
  });

  group('this milestone writes nothing', () {
    test('no source performs any mutation', () {
      _expectAbsent(dashboardSources, <String>[
        '.insert(',
        '.update(',
        '.upsert(',
        '.delete(',
        'record_audit',
        'set_dashboard',
        'save_dashboard',
        'update_vendor',
        'edit_profile',
      ], allowInComments: true);
    });

    test('the repository interface exposes one read and nothing else', () {
      final File repository = dashboardSources.firstWhere(
        (File f) => f.path.endsWith(
          'domain/repositories/vendor_dashboard_repository.dart',
        ),
      );
      final String src = code(repository);

      final RegExp methods = RegExp(r'Future<ReadResult<[^>]+>+>\s+(\w+)\(');
      final Set<String> names = methods
          .allMatches(src)
          .map((RegExpMatch m) => m.group(1)!)
          .toSet();

      expect(names, <String>{'summary'});
    });

    test('no customisation, export or profile-edit affordance exists', () {
      _expectAbsent(dashboardSources, <String>[
        'customi',
        'reorder',
        'dragAndDrop',
        'export',
        'Export',
        'downloadCsv',
        'toCsv',
        'CSV',
        'Pdf',
        'PDF',
        'Share.share',
        'editProfile',
        'SrTextField',
      ], allowInComments: true);
    });
  });

  group('layering', () {
    test('presentation never touches Supabase or HTTP directly', () {
      final Iterable<File> presentation = dashboardSources.where(
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
      final Iterable<File> domain = dashboardSources.where(
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
      final Iterable<File> cubits = dashboardSources.where(
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
      final Iterable<File> widgets = dashboardSources.where(
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
      final Iterable<File> offenders = dashboardSources.where((File f) {
        if (f.path.contains('/data/')) return false;
        return code(f).contains('get_vendor_admin_dashboard_summary');
      });

      expect(
        offenders.map((File f) => f.path),
        isEmpty,
        reason: 'the RPC name belongs in the data layer alone',
      );
    });

    test('a portal kind is read for its label and for nothing else', () {
      final RegExp anyUse = RegExp(r'PortalKind\.\w+(\.\w+)?');

      for (final File file in dashboardSources) {
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
