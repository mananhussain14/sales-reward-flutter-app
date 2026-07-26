import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/core/result/read_result.dart';
import 'package:sale_reward/features/dashboard/data/datasources/vendor_dashboard_rpc_data_source.dart';
import 'package:sale_reward/features/dashboard/data/repositories/supabase_vendor_dashboard_repository.dart';
import 'package:sale_reward/features/dashboard/domain/entities/vendor_dashboard_summary.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/vendor_dashboard_fakes.dart';

/// The data layer's contract with the backend.
///
/// Four properties are asserted over and over, because each is a security
/// boundary rather than a convenience:
///
/// 1. **Nothing at all travels.** The invoker takes no arguments, so there is no
///    auth user id, profile id, membership id, organization or tenant, role,
///    permission, status, date range or period to send — and no way to add one
///    without changing the type.
/// 2. **One RPC, and no table read.** Not `organization_members`, not `roles`,
///    not `permissions`, not `audit_logs`, not `organizations`, not `profiles`.
/// 3. **A thrown call is classified by SQLSTATE**, and an unreadable body is an
///    outage — never a denial, and never a summary of zeros.
/// 4. **A refusal is never a figure.** No failure path anywhere produces a
///    `VendorDashboardSummary`.
void main() {
  late int callCount;
  Object? body = dashboardSummaryBody();
  Object? thrown;

  setUp(() {
    callCount = 0;
    body = dashboardSummaryBody();
    thrown = null;
  });

  SupabaseVendorDashboardRepository buildRepository() {
    return SupabaseVendorDashboardRepository(
      rpc: VendorDashboardRpcDataSource(
        summary: () async {
          callCount++;
          if (thrown != null) throw thrown!;
          return body;
        },
      ),
    );
  }

  PostgrestException postgrest(String code) => PostgrestException(
    message: 'backend detail that must not escape',
    code: code,
  );

  /// The data source's executable lines only. The doc comments deliberately
  /// discuss the arguments the contract does *not* accept, so a scan that could
  /// not tell prose from code would fail on its own documentation.
  String dataSourceCode() =>
      File(
            'lib/features/dashboard/data/datasources/'
            'vendor_dashboard_rpc_data_source.dart',
          )
          .readAsLinesSync()
          .where((String line) {
            final String trimmed = line.trimLeft();
            return !trimmed.startsWith('//') && !trimmed.startsWith('*');
          })
          .join('\n');

  group('the RPC contract', () {
    test('the read issues exactly one call', () async {
      await buildRepository().summary();

      expect(callCount, 1);
    });

    test('the invoker takes no arguments at all', () {
      // The type is the assertion. A zero-argument function literal satisfies
      // it; anything that needed a value would not compile.
      const VendorDashboardSummaryInvoker invoker = _noArgumentInvoker;

      expect(invoker, isA<Future<Object?> Function()>());
    });

    test('no params map is passed, not even an empty one', () {
      final String source = dataSourceCode();

      // The call site is a function name and nothing else. An empty `params: {}`
      // would be harmless today and would be the obvious place for a future
      // "just one" selector to land.
      expect(
        source.contains("client.rpc<Object?>(vendorDashboardSummaryRpc)"),
        isTrue,
      );
      expect(source.contains('params:'), isFalse);
    });

    test('only the one deployed function is named', () {
      final RegExp rpcNames = RegExp(r"const String \w+Rpc =\s*'([^']+)'");
      final List<String> names = rpcNames
          .allMatches(dataSourceCode())
          .map((RegExpMatch m) => m.group(1)!)
          .toList();

      expect(names, <String>['get_vendor_admin_dashboard_summary']);
    });

    test('no identity, tenant, role, permission or period argument', () {
      final String source = dataSourceCode();

      for (final String forbidden in <String>[
        'p_user_id',
        'p_auth_user_id',
        'p_profile_id',
        'p_membership_id',
        'p_organization_id',
        'p_vendor_organization_id',
        'p_tenant_id',
        'p_role_code',
        'p_permission_code',
        'p_status',
        'p_from',
        'p_to',
        'p_since',
        'p_period',
        'p_days',
        'p_limit',
        'p_offset',
        'organization_id',
        'user_id',
        'access_token',
      ]) {
        expect(
          source.contains(forbidden),
          isFalse,
          reason: 'the dashboard RPC must pass no $forbidden argument',
        );
      }
    });

    test('the data source performs no query and holds no key', () {
      final String source = dataSourceCode();

      for (final String forbidden in <String>[
        '.from(',
        '.select(',
        '.eq(',
        '.count(',
        '.head(',
        '.insert(',
        '.update(',
        '.upsert(',
        '.delete(',
        "'organizations'",
        "'organization_members'",
        "'roles'",
        "'permissions'",
        "'audit_logs'",
        "'profiles'",
        'auth.users',
        'service_role',
        'serviceRoleKey',
        'SUPABASE_SERVICE_ROLE_KEY',
      ]) {
        expect(
          source.contains(forbidden),
          isFalse,
          reason: 'the dashboard data source must not contain $forbidden',
        );
      }
      expect(source.contains('client.rpc<Object?>('), isTrue);
    });
  });

  group('success', () {
    test('a summary row is parsed into the entity', () async {
      final ReadResult<VendorDashboardSummary> result = await buildRepository()
          .summary();

      expect(result, isA<ReadSuccess<VendorDashboardSummary>>());
      expect(
        (result as ReadSuccess<VendorDashboardSummary>).value,
        exampleDashboardSummary,
      );
    });

    test('an all-zero tenant summary is a success, never a failure', () async {
      // A brand-new Vendor: no members counted beyond the caller, nothing
      // recorded. The backend answered perfectly, and the catalogue counts are
      // still non-zero.
      body = dashboardSummaryBody(
        dashboardSummaryRow(activeMemberCount: 0, auditEventCount: 0),
      );

      final ReadResult<VendorDashboardSummary> result = await buildRepository()
          .summary();

      expect(result, isA<ReadSuccess<VendorDashboardSummary>>());
      expect(
        (result as ReadSuccess<VendorDashboardSummary>).value,
        emptyTenantDashboardSummary,
      );
    });

    test('a fully zero summary is still a success', () async {
      body = dashboardSummaryBody(
        dashboardSummaryRow(
          activeMemberCount: 0,
          catalogActiveRoleCount: 0,
          catalogPermissionCount: 0,
          auditEventCount: 0,
        ),
      );

      final ReadResult<VendorDashboardSummary> result = await buildRepository()
          .summary();

      expect(
        (result as ReadSuccess<VendorDashboardSummary>).value,
        allZeroDashboardSummary,
      );
    });
  });

  group('failure classification', () {
    test('42501 is a denial, and carries no backend text', () async {
      thrown = postgrest('42501');

      final ReadResult<VendorDashboardSummary> result = await buildRepository()
          .summary();

      expect(result, isA<ReadFailure<VendorDashboardSummary>>());
      final Failure failure =
          (result as ReadFailure<VendorDashboardSummary>).failure;
      expect(failure, isA<DeniedFailure>());
      // The discriminant carries no fields at all, so no message, permission
      // code or object name can ride along — and the backend deliberately does
      // not say which of its four gates refused.
      expect(failure.props, isEmpty);
    });

    test('a denial never becomes a summary of zeros', () async {
      thrown = postgrest('42501');

      final ReadResult<VendorDashboardSummary> result = await buildRepository()
          .summary();

      expect(result, isNot(isA<ReadSuccess<VendorDashboardSummary>>()));
    });

    test('a transport failure is an outage, never a denial', () async {
      thrown = const SocketException('no route to host');

      final ReadResult<VendorDashboardSummary> result = await buildRepository()
          .summary();

      final Failure failure =
          (result as ReadFailure<VendorDashboardSummary>).failure;
      expect(failure, isA<UnavailableFailure>());
      expect(failure, isNot(isA<DeniedFailure>()));
    });

    test('an expired session is unauthenticated, not denied', () async {
      thrown = const AuthException('jwt expired');

      final ReadResult<VendorDashboardSummary> result = await buildRepository()
          .summary();

      expect(
        (result as ReadFailure<VendorDashboardSummary>).failure,
        isA<UnauthenticatedFailure>(),
      );
    });

    test('an unrecognised SQLSTATE is an outage, not a denial', () async {
      thrown = postgrest('08006');

      final ReadResult<VendorDashboardSummary> result = await buildRepository()
          .summary();

      final Failure failure =
          (result as ReadFailure<VendorDashboardSummary>).failure;
      expect(failure, isA<UnavailableFailure>());
      expect(failure, isNot(isA<DeniedFailure>()));
    });

    test('a malformed row is an outage, never zeros', () async {
      body = dashboardSummaryBody(
        dashboardSummaryRow(activeMemberCount: 'seven'),
      );

      final ReadResult<VendorDashboardSummary> result = await buildRepository()
          .summary();

      expect(result, isA<ReadFailure<VendorDashboardSummary>>());
      expect(
        (result as ReadFailure<VendorDashboardSummary>).failure,
        isA<UnavailableFailure>(),
      );
    });

    test('a zero-row response is an outage, never an empty summary', () async {
      body = <Object?>[];

      final ReadResult<VendorDashboardSummary> result = await buildRepository()
          .summary();

      expect(result, isA<ReadFailure<VendorDashboardSummary>>());
      expect(
        (result as ReadFailure<VendorDashboardSummary>).failure,
        isA<UnavailableFailure>(),
      );
    });

    test('a multiple-row response is an outage, and no row is taken', () async {
      body = <Object?>[
        dashboardSummaryRow(),
        dashboardSummaryRow(activeMemberCount: 99),
      ];

      final ReadResult<VendorDashboardSummary> result = await buildRepository()
          .summary();

      expect(result, isA<ReadFailure<VendorDashboardSummary>>());
      expect(
        (result as ReadFailure<VendorDashboardSummary>).failure,
        isA<UnavailableFailure>(),
      );
    });

    test('a body that is not a list is an outage', () async {
      body = <String, Object?>{'active_member_count': 7};

      final ReadResult<VendorDashboardSummary> result = await buildRepository()
          .summary();

      expect(
        (result as ReadFailure<VendorDashboardSummary>).failure,
        isA<UnavailableFailure>(),
      );
    });

    test('a negative count is an outage, never clamped to zero', () async {
      body = dashboardSummaryBody(dashboardSummaryRow(auditEventCount: -1));

      final ReadResult<VendorDashboardSummary> result = await buildRepository()
          .summary();

      expect(
        (result as ReadFailure<VendorDashboardSummary>).failure,
        isA<UnavailableFailure>(),
      );
    });
  });

  group('the repository decides nothing itself', () {
    test('it reproduces no authorization or tenant logic', () {
      final String source =
          File(
                'lib/features/dashboard/data/repositories/'
                'supabase_vendor_dashboard_repository.dart',
              )
              .readAsLinesSync()
              .where((String line) {
                final String trimmed = line.trimLeft();
                return !trimmed.startsWith('//') && !trimmed.startsWith('*');
              })
              .join('\n');

      for (final String forbidden in <String>[
        'ORGANIZATION_MEMBERS_READ',
        'RBAC_READ',
        'AUDIT_LOGS_READ',
        'VENDOR_SUPER_ADMIN',
        'has_organization_permission',
        'get_vendor_super_admin_context',
        'organizationId',
        'organization_id',
        '42501',
        'SQLSTATE',
      ]) {
        expect(
          source.contains(forbidden),
          isFalse,
          reason: 'the repository must not restate $forbidden',
        );
      }
    });

    test('it derives, sums or filters no count', () {
      final String source = File(
        'lib/features/dashboard/data/repositories/'
        'supabase_vendor_dashboard_repository.dart',
      ).readAsStringSync();

      for (final String forbidden in <String>[
        '.fold(',
        '.reduce(',
        '.where(',
        '.length',
        'total',
        '+ 1',
      ]) {
        expect(
          source.contains(forbidden),
          isFalse,
          reason: 'the repository must not compute $forbidden',
        );
      }
    });
  });
}

/// A zero-argument invoker, proving the typedef accepts one.
Future<Object?> _noArgumentInvoker() async => dashboardSummaryBody();
