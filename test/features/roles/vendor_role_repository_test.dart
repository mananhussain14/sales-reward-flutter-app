import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/core/result/read_result.dart';
import 'package:sale_reward/features/roles/data/datasources/vendor_role_rpc_data_source.dart';
import 'package:sale_reward/features/roles/data/repositories/supabase_vendor_role_repository.dart';
import 'package:sale_reward/features/roles/domain/entities/vendor_role_detail.dart';
import 'package:sale_reward/features/roles/domain/entities/vendor_role_permission.dart';
import 'package:sale_reward/features/roles/domain/entities/vendor_role_status.dart';
import 'package:sale_reward/features/roles/domain/entities/vendor_role_summary.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/vendor_role_fakes.dart';

/// The data layer's contract with the backend.
///
/// Four properties are asserted over and over, because each is a security
/// boundary rather than a convenience:
///
/// 1. **`list_vendor_roles()` is called with no arguments at all**, so nothing
///    in the client can nominate what comes back or whose counts ride on it.
/// 2. **The two companions send one role id and nothing beside it** — no auth
///    user id, no profile id, no organization or tenant, no role code, no
///    permission code, no status, no page cursor.
/// 3. **A thrown call is classified by SQLSTATE, and an unreadable body is an
///    outage** — never a denial, and never a fabricated empty catalogue.
/// 4. **A malformed selector never reaches PostgREST**, because a `uuid`
///    parameter would answer `22P02` and a cast error wearing outage clothes
///    would offer a retry that can never succeed.
void main() {
  late int roleCalls;
  late List<List<Object?>> roleCallArguments;
  late List<Map<String, Object?>> detailParams;
  late List<Map<String, Object?>> permissionParams;

  Object? roleBody = roleRows();
  Object? detailBody = <Map<String, Object?>>[roleRow()];
  Object? permissionBody = <Map<String, Object?>>[permissionRow()];
  Object? thrown;

  setUp(() {
    roleCalls = 0;
    roleCallArguments = <List<Object?>>[];
    detailParams = <Map<String, Object?>>[];
    permissionParams = <Map<String, Object?>>[];
    roleBody = roleRows();
    detailBody = <Map<String, Object?>>[roleRow()];
    permissionBody = <Map<String, Object?>>[permissionRow()];
    thrown = null;
  });

  SupabaseVendorRoleRepository buildRepository() {
    return SupabaseVendorRoleRepository(
      rpc: VendorRoleRpcDataSource(
        roles: () async {
          roleCalls++;
          // The invoker takes no parameters, so there is literally nothing to
          // record beyond the fact that it was called with none.
          roleCallArguments.add(const <Object?>[]);
          if (thrown != null) throw thrown!;
          return roleBody;
        },
        detail: (String roleId) async {
          detailParams.add(<String, Object?>{roleIdParameter: roleId});
          if (thrown != null) throw thrown!;
          return detailBody;
        },
        permissions: (String roleId) async {
          permissionParams.add(<String, Object?>{roleIdParameter: roleId});
          if (thrown != null) throw thrown!;
          return permissionBody;
        },
      ),
    );
  }

  PostgrestException postgrest(String code) => PostgrestException(
    message: 'backend detail that must not escape',
    code: code,
  );

  group('the RPC contract', () {
    test('list_vendor_roles is invoked with zero arguments', () async {
      await buildRepository().roles();

      expect(roleCalls, 1);
      expect(roleCallArguments.single, isEmpty);
    });

    test('get_vendor_role_detail sends only p_role_id', () async {
      await buildRepository().roleDetail(superAdminRoleUuid);

      expect(detailParams, hasLength(1));
      expect(detailParams.single, <String, Object?>{
        'p_role_id': superAdminRoleUuid,
      });
      expect(detailParams.single.keys, hasLength(1));
    });

    test('list_vendor_role_permissions sends only p_role_id', () async {
      await buildRepository().rolePermissions(superAdminRoleUuid);

      expect(permissionParams, hasLength(1));
      expect(permissionParams.single, <String, Object?>{
        'p_role_id': superAdminRoleUuid,
      });
      expect(permissionParams.single.keys, hasLength(1));
    });

    test('the two companions address the same id space', () async {
      // One selector for both, so the operations cannot drift into two address
      // spaces — and so the detail read is genuinely authoritative about the id
      // the companion was asked for.
      final SupabaseVendorRoleRepository repository = buildRepository();
      await repository.roleDetail(legacyRoleUuid);
      await repository.rolePermissions(legacyRoleUuid);

      expect(
        detailParams.single[roleIdParameter],
        permissionParams.single[roleIdParameter],
      );
    });

    test(
      'no identity, tenant, role-code or permission-code argument',
      () async {
        final SupabaseVendorRoleRepository repository = buildRepository();
        await repository.roles();
        await repository.roleDetail(superAdminRoleUuid);
        await repository.rolePermissions(superAdminRoleUuid);

        final Set<String> sent = <String>{
          ...detailParams.expand((Map<String, Object?> p) => p.keys),
          ...permissionParams.expand((Map<String, Object?> p) => p.keys),
        };

        expect(sent, <String>{'p_role_id'});
        for (final String forbidden in <String>[
          'p_user_id',
          'p_profile_id',
          'p_membership_id',
          'p_organization_id',
          'p_vendor_id',
          'p_tenant_id',
          'p_role_code',
          'p_permission_code',
          'p_permission_id',
          'p_status',
          'p_search',
          'p_limit',
          'p_offset',
        ]) {
          expect(sent.contains(forbidden), isFalse);
        }
      },
    );

    test('the parameter name is the deployed one, exactly', () {
      expect(roleIdParameter, 'p_role_id');
    });

    test('only the three deployed functions are named', () {
      expect(listVendorRolesRpc, 'list_vendor_roles');
      expect(getVendorRoleDetailRpc, 'get_vendor_role_detail');
      expect(listVendorRolePermissionsRpc, 'list_vendor_role_permissions');
    });

    test('no write RPC is reachable from the repository interface', () {
      // The interface has three methods and all three are reads. This asserts
      // the *source* has no write name in it, which is what a future edit would
      // have to add.
      final String source = File(
        'lib/features/roles/data/datasources/vendor_role_rpc_data_source.dart',
      ).readAsStringSync();

      for (final String forbidden in <String>[
        'create_role',
        'update_role',
        'delete_role',
        'activate_role',
        'deactivate_role',
        'assign_role',
        'remove_role',
        'grant_permission',
        'revoke_permission',
      ]) {
        expect(source.contains(forbidden), isFalse);
      }
    });
  });

  group('the catalogue read', () {
    test('a successful body becomes parsed rows, in backend order', () async {
      final ReadResult<List<VendorRoleSummary>> result = await buildRepository()
          .roles();

      expect(result, isA<ReadSuccess<List<VendorRoleSummary>>>());
      final List<VendorRoleSummary> rows =
          (result as ReadSuccess<List<VendorRoleSummary>>).value;
      expect(rows, hasLength(2));
      expect(rows.first.roleName, 'Claim Reviewer');
      expect(rows.last.roleName, 'Vendor Super Admin');
    });

    test('an empty catalogue is a success carrying an empty list', () async {
      roleBody = const <Object?>[];

      final ReadResult<List<VendorRoleSummary>> result = await buildRepository()
          .roles();

      expect((result as ReadSuccess<List<VendorRoleSummary>>).value, isEmpty);
    });

    test('42501 becomes a denial', () async {
      thrown = postgrest('42501');

      final ReadResult<List<VendorRoleSummary>> result = await buildRepository()
          .roles();

      expect(
        (result as ReadFailure<List<VendorRoleSummary>>).failure,
        isA<DeniedFailure>(),
      );
    });

    test('a transport failure is an outage, never a denial', () async {
      thrown = const SocketException('no route to host');

      final ReadResult<List<VendorRoleSummary>> result = await buildRepository()
          .roles();

      final Failure failure =
          (result as ReadFailure<List<VendorRoleSummary>>).failure;
      expect(failure, isA<UnavailableFailure>());
      expect(failure, isNot(isA<DeniedFailure>()));
    });

    test('an unreadable body is an outage, never an empty catalogue', () async {
      // Fabricating an empty list would tell a Vendor Super Admin the platform
      // has no role definitions — which cannot be true of a caller authorized by
      // holding one of them.
      roleBody = <Map<String, Object?>>[roleRow(roleName: null)];

      final ReadResult<List<VendorRoleSummary>> result = await buildRepository()
          .roles();

      expect(result, isA<ReadFailure<List<VendorRoleSummary>>>());
      expect(
        (result as ReadFailure<List<VendorRoleSummary>>).failure,
        isA<UnavailableFailure>(),
      );
    });

    test('the backend message never escapes into the failure', () async {
      thrown = postgrest('42501');

      final ReadResult<List<VendorRoleSummary>> result = await buildRepository()
          .roles();

      expect(
        (result as ReadFailure<List<VendorRoleSummary>>).failure.props,
        isEmpty,
      );
    });
  });

  group('the detail read', () {
    test('one row becomes a detail', () async {
      final ReadResult<VendorRoleDetail?> result = await buildRepository()
          .roleDetail(superAdminRoleUuid);

      final VendorRoleDetail? detail =
          (result as ReadSuccess<VendorRoleDetail?>).value;
      expect(detail!.roleName, 'Vendor Super Admin');
      expect(detail.status, VendorRoleStatus.active);
    });

    test('zero rows is a success carrying null', () async {
      detailBody = const <Object?>[];

      final ReadResult<VendorRoleDetail?> result = await buildRepository()
          .roleDetail(unknownRoleUuid);

      expect(result, isA<ReadSuccess<VendorRoleDetail?>>());
      expect((result as ReadSuccess<VendorRoleDetail?>).value, isNull);
    });

    test('a malformed id answers null without calling the RPC', () async {
      final ReadResult<VendorRoleDetail?> result = await buildRepository()
          .roleDetail('not-a-uuid');

      expect(detailParams, isEmpty);
      expect((result as ReadSuccess<VendorRoleDetail?>).value, isNull);
    });

    test('an empty id answers null without calling the RPC', () async {
      // What a route with a missing segment produces.
      final ReadResult<VendorRoleDetail?> result = await buildRepository()
          .roleDetail('');

      expect(detailParams, isEmpty);
      expect((result as ReadSuccess<VendorRoleDetail?>).value, isNull);
    });

    test('a well-formed unknown id DOES reach the RPC', () async {
      // A valid uuid is a legitimate question, so it is asked; its zero-row
      // answer maps to the same null.
      detailBody = const <Object?>[];

      await buildRepository().roleDetail(unknownRoleUuid);

      expect(detailParams, hasLength(1));
    });

    test('42501 becomes a denial rather than a null', () async {
      thrown = postgrest('42501');

      final ReadResult<VendorRoleDetail?> result = await buildRepository()
          .roleDetail(superAdminRoleUuid);

      expect(
        (result as ReadFailure<VendorRoleDetail?>).failure,
        isA<DeniedFailure>(),
      );
    });

    test('an unreadable body is an outage, never a null', () async {
      // Null means "no such role"; unreadable is a different event, and
      // conflating them would show the wrong screen and withhold the retry.
      detailBody = <Map<String, Object?>>[roleRow(permissionCount: -3)];

      final ReadResult<VendorRoleDetail?> result = await buildRepository()
          .roleDetail(superAdminRoleUuid);

      expect(
        (result as ReadFailure<VendorRoleDetail?>).failure,
        isA<UnavailableFailure>(),
      );
    });
  });

  group('the permission companion', () {
    test('a successful body becomes parsed permissions', () async {
      final ReadResult<List<VendorRolePermission>> result =
          await buildRepository().rolePermissions(superAdminRoleUuid);

      final List<VendorRolePermission> rows =
          (result as ReadSuccess<List<VendorRolePermission>>).value;
      expect(rows.single.name, 'Read roles');
    });

    test('an empty list is a success, not a failure', () async {
      permissionBody = const <Object?>[];

      final ReadResult<List<VendorRolePermission>> result =
          await buildRepository().rolePermissions(claimReviewerRoleUuid);

      expect(
        (result as ReadSuccess<List<VendorRolePermission>>).value,
        isEmpty,
      );
    });

    test('a malformed id never reaches the RPC', () async {
      // Defence in depth: the cubit never calls this for an id the detail read
      // could not resolve, but the rule holds at the boundary regardless.
      final ReadResult<List<VendorRolePermission>> result =
          await buildRepository().rolePermissions('not-a-uuid');

      expect(permissionParams, isEmpty);
      expect(
        (result as ReadSuccess<List<VendorRolePermission>>).value,
        isEmpty,
      );
    });

    test('42501 becomes a denial', () async {
      thrown = postgrest('42501');

      final ReadResult<List<VendorRolePermission>> result =
          await buildRepository().rolePermissions(superAdminRoleUuid);

      expect(
        (result as ReadFailure<List<VendorRolePermission>>).failure,
        isA<DeniedFailure>(),
      );
    });

    test('a transport failure is retryable, not a denial', () async {
      thrown = const SocketException('reset by peer');

      final ReadResult<List<VendorRolePermission>> result =
          await buildRepository().rolePermissions(superAdminRoleUuid);

      expect(
        (result as ReadFailure<List<VendorRolePermission>>).failure,
        isA<UnavailableFailure>(),
      );
    });

    test(
      'an unreadable body is an outage, never an empty mapping list',
      () async {
        // An empty list here means "this role grants nothing" — a claim that must
        // never be manufactured from a body that could not be read.
        permissionBody = <Map<String, Object?>>[permissionRow(name: null)];

        final ReadResult<List<VendorRolePermission>> result =
            await buildRepository().rolePermissions(superAdminRoleUuid);

        expect(result, isA<ReadFailure<List<VendorRolePermission>>>());
        expect(
          (result as ReadFailure<List<VendorRolePermission>>).failure,
          isA<UnavailableFailure>(),
        );
      },
    );
  });

  group('no table is ever read', () {
    test('the repository reaches only the three RPC invokers', () async {
      // The web assembles this screen from three whole-table reads and a
      // TypeScript join. Reimplementing that join here would be a second
      // definition of "which permissions does this role grant".
      final SupabaseVendorRoleRepository repository = buildRepository();
      await repository.roles();
      await repository.roleDetail(superAdminRoleUuid);
      await repository.rolePermissions(superAdminRoleUuid);

      expect(roleCalls, 1);
      expect(detailParams, hasLength(1));
      expect(permissionParams, hasLength(1));
    });

    test('counts are never assembled by a second read', () async {
      // Both counts arrive on the row. A per-role member or permission query
      // would be N+1 over work the backend already did — and a second place for
      // the tenant scoping to be got wrong.
      final ReadResult<List<VendorRoleSummary>> result = await buildRepository()
          .roles();
      final List<VendorRoleSummary> rows =
          (result as ReadSuccess<List<VendorRoleSummary>>).value;

      expect(rows.last.permissionCount, 3);
      expect(rows.last.assignedMemberCount, 2);
      // One call for the whole catalogue, counts included.
      expect(roleCalls, 1);
      expect(detailParams, isEmpty);
      expect(permissionParams, isEmpty);
    });
  });
}
