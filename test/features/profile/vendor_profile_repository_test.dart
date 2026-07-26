import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/core/result/read_result.dart';
import 'package:sale_reward/features/profile/data/datasources/vendor_profile_rpc_data_source.dart';
import 'package:sale_reward/features/profile/data/repositories/supabase_vendor_profile_repository.dart';
import 'package:sale_reward/features/profile/domain/entities/vendor_administrator_profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/vendor_profile_fakes.dart';

/// The data layer's contract with the backend.
///
/// Four properties are asserted over and over, because each is a security
/// boundary rather than a convenience:
///
/// 1. **Nothing at all travels.** The invoker takes no arguments, so there is no
///    auth user id, profile id, membership id, organization or tenant, role,
///    permission, status or date range to send — and no way to add one without
///    changing the type. A profile selector in particular would turn a self-read
///    into a way to read a colleague.
/// 2. **One RPC, and no table read.** Not `organizations`, not `profiles`, not
///    `organization_members`, not `member_roles`, not `roles`, not `auth.users` —
///    and no call to the Vendor user directory to find oneself in it either.
/// 3. **A thrown call is classified by SQLSTATE**, and an unreadable body is an
///    outage — never a denial, and never a blank profile.
/// 4. **A refusal is never an identity.** No failure path anywhere produces a
///    `VendorAdministratorProfile`.
void main() {
  late int callCount;
  Object? body = administratorProfileBody();
  Object? thrown;

  setUp(() {
    callCount = 0;
    body = administratorProfileBody();
    thrown = null;
  });

  SupabaseVendorProfileRepository buildRepository() {
    return SupabaseVendorProfileRepository(
      rpc: VendorProfileRpcDataSource(
        administratorProfile: () async {
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
            'lib/features/profile/data/datasources/'
            'vendor_profile_rpc_data_source.dart',
          )
          .readAsLinesSync()
          .where((String line) {
            final String trimmed = line.trimLeft();
            return !trimmed.startsWith('//') && !trimmed.startsWith('*');
          })
          .join('\n');

  group('the RPC contract', () {
    test('the read issues exactly one call', () async {
      await buildRepository().administratorProfile();

      expect(callCount, 1);
    });

    test('the invoker takes no arguments at all', () {
      // The type is the assertion. A zero-argument function literal satisfies
      // it; anything that needed a value would not compile.
      const VendorAdministratorProfileInvoker invoker = _noArgumentInvoker;

      expect(invoker, isA<Future<Object?> Function()>());
    });

    test('no params map is passed, not even an empty one', () {
      final String source = dataSourceCode();

      // The call site is a function name and nothing else. An empty `params: {}`
      // would be harmless today and would be the obvious place for a future
      // "just one" selector to land — a profile id above all.
      expect(
        source.contains('client.rpc<Object?>(vendorAdministratorProfileRpc)'),
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

      expect(names, <String>['get_my_vendor_profile']);
    });

    test('no identity, tenant, role, permission or status argument', () {
      final String source = dataSourceCode();

      for (final String forbidden in <String>[
        'p_user_id',
        'p_auth_user_id',
        'p_profile_id',
        'p_membership_id',
        'p_member_id',
        'p_organization_id',
        'p_vendor_organization_id',
        'p_vendor_id',
        'p_tenant_id',
        'p_role',
        'p_role_id',
        'p_role_code',
        'p_permission',
        'p_permission_code',
        'p_status',
        'p_from',
        'p_to',
        'p_limit',
        'p_offset',
        'organization_id',
        'user_id',
        'membership_id',
        'access_token',
      ]) {
        expect(
          source.contains(forbidden),
          isFalse,
          reason: 'the profile RPC must pass no $forbidden argument',
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
        "'member_roles'",
        "'roles'",
        "'permissions'",
        "'profiles'",
        'auth.users',
        'service_role',
        'serviceRoleKey',
        'SUPABASE_SERVICE_ROLE_KEY',
      ]) {
        expect(
          source.contains(forbidden),
          isFalse,
          reason: 'the profile data source must not contain $forbidden',
        );
      }
      expect(source.contains('client.rpc<Object?>('), isTrue);
    });

    test('the Vendor user directory is never called to find the caller', () {
      final String source = dataSourceCode();

      for (final String forbidden in <String>[
        'list_vendor_users',
        'get_vendor_user_detail',
        'get_my_portal_context',
        'get_vendor_super_admin_context',
      ]) {
        expect(
          source.contains(forbidden),
          isFalse,
          reason: 'the self-read must not reach for $forbidden',
        );
      }
    });
  });

  group('success', () {
    test('a profile row is parsed into the entity', () async {
      final ReadResult<VendorAdministratorProfile> result =
          await buildRepository().administratorProfile();

      expect(result, isA<ReadSuccess<VendorAdministratorProfile>>());
      expect(
        (result as ReadSuccess<VendorAdministratorProfile>).value,
        aminaAdministratorProfile,
      );
    });

    test('several active roles come back in the backend\'s order', () async {
      body = administratorProfileBody(
        administratorProfileRow(
          roleNames: const <Object?>[
            'Vendor Super Admin',
            'Finance Admin',
            'Catalogue Manager',
          ],
        ),
      );

      final ReadResult<VendorAdministratorProfile> result =
          await buildRepository().administratorProfile();

      expect(
        (result as ReadSuccess<VendorAdministratorProfile>).value.roleNames,
        <String>['Vendor Super Admin', 'Finance Admin', 'Catalogue Manager'],
      );
    });

    test(
      'a defensively empty role array is a success, never a failure',
      () async {
        body = administratorProfileBody(
          administratorProfileRow(roleNames: const <Object?>[]),
        );

        final ReadResult<VendorAdministratorProfile> result =
            await buildRepository().administratorProfile();

        expect(result, isA<ReadSuccess<VendorAdministratorProfile>>());
        expect(
          (result as ReadSuccess<VendorAdministratorProfile>).value,
          noRoleAdministratorProfile,
        );
      },
    );
  });

  group('failure classification', () {
    test('42501 is a denial, and carries no backend text', () async {
      thrown = postgrest('42501');

      final ReadResult<VendorAdministratorProfile> result =
          await buildRepository().administratorProfile();

      expect(result, isA<ReadFailure<VendorAdministratorProfile>>());
      final Failure failure =
          (result as ReadFailure<VendorAdministratorProfile>).failure;
      expect(failure, isA<DeniedFailure>());
      // The discriminant carries no fields at all, so no message, permission
      // code or object name can ride along — and the backend deliberately does
      // not say which of its gates refused.
      expect(failure.props, isEmpty);
    });

    test('a denial never becomes a profile', () async {
      thrown = postgrest('42501');

      final ReadResult<VendorAdministratorProfile> result =
          await buildRepository().administratorProfile();

      expect(result, isNot(isA<ReadSuccess<VendorAdministratorProfile>>()));
    });

    test('a transport failure is an outage, never a denial', () async {
      thrown = const SocketException('no route to host');

      final ReadResult<VendorAdministratorProfile> result =
          await buildRepository().administratorProfile();

      final Failure failure =
          (result as ReadFailure<VendorAdministratorProfile>).failure;
      expect(failure, isA<UnavailableFailure>());
      expect(failure, isNot(isA<DeniedFailure>()));
    });

    test('an expired session is unauthenticated, not denied', () async {
      thrown = const AuthException('jwt expired');

      final ReadResult<VendorAdministratorProfile> result =
          await buildRepository().administratorProfile();

      expect(
        (result as ReadFailure<VendorAdministratorProfile>).failure,
        isA<UnauthenticatedFailure>(),
      );
    });

    test('an unrecognised SQLSTATE is an outage, not a denial', () async {
      thrown = postgrest('08006');

      final ReadResult<VendorAdministratorProfile> result =
          await buildRepository().administratorProfile();

      final Failure failure =
          (result as ReadFailure<VendorAdministratorProfile>).failure;
      expect(failure, isA<UnavailableFailure>());
      expect(failure, isNot(isA<DeniedFailure>()));
    });

    test('a malformed row is an outage, never a blank profile', () async {
      body = administratorProfileBody(administratorProfileRow(displayName: 42));

      final ReadResult<VendorAdministratorProfile> result =
          await buildRepository().administratorProfile();

      expect(result, isA<ReadFailure<VendorAdministratorProfile>>());
      expect(
        (result as ReadFailure<VendorAdministratorProfile>).failure,
        isA<UnavailableFailure>(),
      );
    });

    test('a null role array is an outage, never "no roles"', () async {
      body = administratorProfileBody(administratorProfileRow(roleNames: null));

      final ReadResult<VendorAdministratorProfile> result =
          await buildRepository().administratorProfile();

      expect(
        (result as ReadFailure<VendorAdministratorProfile>).failure,
        isA<UnavailableFailure>(),
      );
    });

    test('a zero-row response is an outage, never an empty profile', () async {
      body = <Object?>[];

      final ReadResult<VendorAdministratorProfile> result =
          await buildRepository().administratorProfile();

      expect(result, isA<ReadFailure<VendorAdministratorProfile>>());
      expect(
        (result as ReadFailure<VendorAdministratorProfile>).failure,
        isA<UnavailableFailure>(),
      );
    });

    test('a multiple-row response is an outage, and no row is taken', () async {
      body = <Object?>[
        administratorProfileRow(),
        administratorProfileRow(displayName: 'Jo Nakamura'),
      ];

      final ReadResult<VendorAdministratorProfile> result =
          await buildRepository().administratorProfile();

      expect(result, isA<ReadFailure<VendorAdministratorProfile>>());
      expect(
        (result as ReadFailure<VendorAdministratorProfile>).failure,
        isA<UnavailableFailure>(),
      );
    });

    test('a body that is not a list is an outage', () async {
      body = administratorProfileRow();

      final ReadResult<VendorAdministratorProfile> result =
          await buildRepository().administratorProfile();

      expect(
        (result as ReadFailure<VendorAdministratorProfile>).failure,
        isA<UnavailableFailure>(),
      );
    });
  });

  group('the repository decides nothing itself', () {
    String repositoryCode() =>
        File(
              'lib/features/profile/data/repositories/'
              'supabase_vendor_profile_repository.dart',
            )
            .readAsLinesSync()
            .where((String line) {
              final String trimmed = line.trimLeft();
              return !trimmed.startsWith('//') && !trimmed.startsWith('*');
            })
            .join('\n');

    test('it reproduces no authorization or tenant logic', () {
      for (final String forbidden in <String>[
        'RBAC_READ',
        'ORGANIZATION_MEMBERS_READ',
        'VENDOR_SUPER_ADMIN',
        'has_organization_permission',
        'get_vendor_super_admin_context',
        'organizationId',
        'organization_id',
        'auth.uid',
        '42501',
        'SQLSTATE',
      ]) {
        expect(
          repositoryCode().contains(forbidden),
          isFalse,
          reason: 'the repository must not restate $forbidden',
        );
      }
    });

    test('it composes no name and re-orders no role list', () {
      for (final String forbidden in <String>[
        'first_name',
        'last_name',
        'firstName',
        'lastName',
        '.sort(',
        '.toSet(',
        '.join(',
        '.split(',
        '.trim(',
        'Member',
      ]) {
        expect(
          repositoryCode().contains(forbidden),
          isFalse,
          reason: 'the repository must not perform $forbidden',
        );
      }
    });
  });
}

/// A zero-argument invoker, proving the typedef accepts one.
Future<Object?> _noArgumentInvoker() async => administratorProfileBody();
