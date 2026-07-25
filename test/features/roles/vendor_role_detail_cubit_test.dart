import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/core/result/read_result.dart';
import 'package:sale_reward/features/roles/domain/entities/vendor_role_detail.dart';
import 'package:sale_reward/features/roles/domain/entities/vendor_role_permission.dart';
import 'package:sale_reward/features/roles/domain/entities/vendor_role_status.dart';
import 'package:sale_reward/features/roles/presentation/vendor/cubit/vendor_role_detail_cubit.dart';

import '../../support/vendor_role_fakes.dart';

void main() {
  late FakeVendorRoleRepository repository;

  setUp(() => repository = FakeVendorRoleRepository());

  VendorRoleDetailCubit build() => VendorRoleDetailCubit(repository);

  group('the loading sequence', () {
    test('reads the detail first, then the permissions', () async {
      final VendorRoleDetailCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.open(superAdminRoleUuid);

      expect(repository.callLog, <String>['detail', 'permissions']);
      expect(cubit.state.phase, VendorRoleDetailPhase.ready);
      expect(cubit.state.permissionsPhase, VendorRolePermissionsPhase.ready);
    });

    test('issues each read exactly once', () async {
      final VendorRoleDetailCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.open(superAdminRoleUuid);

      expect(repository.detailCallCount, 1);
      expect(repository.permissionsCallCount, 1);
    });

    test('sends the same role id to both reads', () async {
      final VendorRoleDetailCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.open(legacyRoleUuid);

      expect(repository.requestedDetailIds, <String>[legacyRoleUuid]);
      expect(repository.requestedPermissionIds, <String>[legacyRoleUuid]);
    });

    test('loads every field the contract returns', () async {
      final VendorRoleDetailCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.open(superAdminRoleUuid);

      final VendorRoleDetail detail = cubit.state.detail!;
      expect(detail.roleName, 'Vendor Super Admin');
      expect(detail.status, VendorRoleStatus.active);
      expect(detail.permissionCount, 3);
      expect(detail.assignedMemberCount, 2);
      expect(cubit.state.permissions, hasLength(3));
    });

    test('preserves the backend permission order', () async {
      final VendorRoleDetailCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.open(superAdminRoleUuid);

      expect(
        cubit.state.permissions.map((VendorRolePermission p) => p.name),
        <String>['Manage retailers', 'Read organization members', 'Read roles'],
      );
    });

    test(
      'a role with no permissions is a real, distinguishable state',
      () async {
        // Distinguishable only because the detail read came back first.
        final VendorRoleDetailCubit cubit = build();
        addTearDown(cubit.close);

        await cubit.open(claimReviewerRoleUuid);

        expect(cubit.state.phase, VendorRoleDetailPhase.ready);
        expect(cubit.state.hasNoPermissions, isTrue);
        expect(cubit.state.detail!.permissionCount, 0);
        expect(repository.permissionsCallCount, 1);
      },
    );
  });

  group('an id that names no role', () {
    test(
      'zero rows is notFound, and the permission read is never issued',
      () async {
        repository.detailResult = const ReadSuccess<VendorRoleDetail?>(null);
        final VendorRoleDetailCubit cubit = build();
        addTearDown(cubit.close);

        await cubit.open(unknownRoleUuid);

        expect(cubit.state.phase, VendorRoleDetailPhase.notFound);
        expect(repository.detailCallCount, 1);
        // The whole point of the ordering: an empty permission list would look
        // like a role that grants nothing.
        expect(repository.permissionsCallCount, 0);
        expect(repository.callLog, <String>['detail']);
      },
    );

    test('a malformed selector never reaches the permission read', () async {
      // That the *detail* RPC is not issued either is a property of the real
      // repository's id-shape guard, asserted in
      // `vendor_role_repository_test.dart` and end to end in the flow suite.
      // What this cubit owns is the ordering: a selector that resolves to no
      // role must not produce a permission read.
      final VendorRoleDetailCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.open('not-a-uuid');

      expect(cubit.state.phase, VendorRoleDetailPhase.notFound);
      expect(repository.permissionsCallCount, 0);
      expect(repository.callLog, isNot(contains('permissions')));
    });

    test('an empty selector behaves identically', () async {
      final VendorRoleDetailCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.open('');

      expect(cubit.state.phase, VendorRoleDetailPhase.notFound);
      expect(repository.permissionsCallCount, 0);
    });

    test(
      'a well-formed unknown id calls the detail once and permissions zero times',
      () async {
        repository.detailResult = const ReadSuccess<VendorRoleDetail?>(null);
        final VendorRoleDetailCubit cubit = build();
        addTearDown(cubit.close);

        await cubit.open(unknownRoleUuid);

        expect(repository.detailCallCount, 1);
        expect(repository.permissionsCallCount, 0);
      },
    );

    test('notFound is not retryable and retrying re-reads nothing new', () async {
      // retryDetail exists for an operational failure. From notFound the backend
      // already answered, and it will answer the same way — the screen offers no
      // retry, so this only pins that the state is not an outage.
      repository.detailResult = const ReadSuccess<VendorRoleDetail?>(null);
      final VendorRoleDetailCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.open(unknownRoleUuid);

      expect(cubit.state.failure, isNull);
      expect(cubit.state.phase, VendorRoleDetailPhase.notFound);
    });

    test('retryPermissions does nothing when no role is open', () async {
      repository.detailResult = const ReadSuccess<VendorRoleDetail?>(null);
      final VendorRoleDetailCubit cubit = build();
      addTearDown(cubit.close);
      await cubit.open(unknownRoleUuid);

      await cubit.retryPermissions();

      expect(repository.permissionsCallCount, 0);
    });
  });

  group('an inactive role', () {
    test('is loaded, marked, and keeps its permissions and count', () async {
      final VendorRoleDetailCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.open(legacyRoleUuid);

      expect(cubit.state.detail!.status, VendorRoleStatus.inactive);
      // Still listed, still counted — hiding them would make a retired role look
      // permission-less and hide the state the screen exists to explain.
      expect(cubit.state.permissions, hasLength(2));
      expect(cubit.state.detail!.permissionCount, 2);
      expect(cubit.state.hasNoPermissions, isFalse);
    });

    test('reports its mapped permissions as NOT effective', () async {
      final VendorRoleDetailCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.open(legacyRoleUuid);

      expect(cubit.state.permissionsAreEffective, isFalse);
    });

    test('an active role reports them as effective', () async {
      final VendorRoleDetailCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.open(superAdminRoleUuid);

      expect(cubit.state.permissionsAreEffective, isTrue);
    });

    test('an unknown status never reports them as effective', () async {
      repository.detailResult = ReadSuccess<VendorRoleDetail?>(
        VendorRoleDetail(
          roleId: unknownRoleUuid,
          roleName: 'Future Role',
          description: null,
          status: VendorRoleStatus.unknown,
          createdAt: legacyCreatedAt,
          permissionCount: 1,
          assignedMemberCount: 0,
        ),
      );
      final VendorRoleDetailCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.open(unknownRoleUuid);

      expect(cubit.state.permissionsAreEffective, isFalse);
    });

    test('nothing reports effectiveness while nothing is open', () {
      final VendorRoleDetailCubit cubit = build();
      addTearDown(cubit.close);

      expect(cubit.state.permissionsAreEffective, isFalse);
    });

    test('an inactive role still counts members holding it', () async {
      // The backend applies no role-status filter to the count: a retired
      // definition still held by somebody reports that honestly.
      final VendorRoleDetailCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.open(legacyRoleUuid);

      expect(cubit.state.detail!.assignedMemberCount, 1);
    });
  });

  group('failures', () {
    test(
      'a detail outage is retryable and the retry re-runs the sequence',
      () async {
        repository.detailResult = unavailableRoleRead<VendorRoleDetail?>();
        final VendorRoleDetailCubit cubit = build();
        addTearDown(cubit.close);

        await cubit.open(superAdminRoleUuid);
        expect(cubit.state.phase, VendorRoleDetailPhase.failed);
        expect(cubit.state.failure, isA<UnavailableFailure>());
        expect(repository.permissionsCallCount, 0);

        repository.detailResult = null;
        await cubit.retryDetail();

        expect(cubit.state.phase, VendorRoleDetailPhase.ready);
        expect(repository.permissionsCallCount, 1);
      },
    );

    test('a denial on the detail is carried as a denial', () async {
      repository.detailResult = deniedRoleRead<VendorRoleDetail?>();
      final VendorRoleDetailCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.open(superAdminRoleUuid);

      expect(cubit.state.failure, isA<DeniedFailure>());
      expect(cubit.state.phase, VendorRoleDetailPhase.failed);
    });

    test('a permission failure leaves the loaded detail intact', () async {
      repository.permissionsResult =
          unavailableRoleRead<List<VendorRolePermission>>();
      final VendorRoleDetailCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.open(superAdminRoleUuid);

      expect(cubit.state.phase, VendorRoleDetailPhase.ready);
      expect(cubit.state.detail!.roleName, 'Vendor Super Admin');
      expect(cubit.state.permissionsPhase, VendorRolePermissionsPhase.failed);
      expect(cubit.state.permissionsFailure, isA<UnavailableFailure>());
    });

    test(
      'the role status stays visible through a permission failure',
      () async {
        // The one fact that makes a permission list truthful must not be lost
        // because the companion did.
        repository.permissionsResult =
            unavailableRoleRead<List<VendorRolePermission>>();
        final VendorRoleDetailCubit cubit = build();
        addTearDown(cubit.close);

        await cubit.open(legacyRoleUuid);

        expect(cubit.state.detail!.status, VendorRoleStatus.inactive);
        expect(cubit.state.permissionsAreEffective, isFalse);
      },
    );

    test('retrying permissions does not re-read the detail', () async {
      repository.permissionsResult =
          unavailableRoleRead<List<VendorRolePermission>>();
      final VendorRoleDetailCubit cubit = build();
      addTearDown(cubit.close);
      await cubit.open(superAdminRoleUuid);
      expect(repository.detailCallCount, 1);

      repository.permissionsResult = null;
      await cubit.retryPermissions();

      expect(repository.detailCallCount, 1);
      expect(repository.permissionsCallCount, 2);
      expect(cubit.state.permissionsPhase, VendorRolePermissionsPhase.ready);
      expect(cubit.state.permissions, hasLength(3));
    });

    test('a permission failure clears when the retry succeeds', () async {
      repository.permissionsResult =
          unavailableRoleRead<List<VendorRolePermission>>();
      final VendorRoleDetailCubit cubit = build();
      addTearDown(cubit.close);
      await cubit.open(superAdminRoleUuid);

      repository.permissionsResult = null;
      await cubit.retryPermissions();

      expect(cubit.state.permissionsFailure, isNull);
    });
  });

  group('the count invariant', () {
    test('agreement is the normal case and raises nothing', () async {
      final VendorRoleDetailCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.open(superAdminRoleUuid);

      expect(cubit.state.permissionCountDisagrees, isFalse);
    });

    test(
      'a disagreement is surfaced without dropping or fabricating rows',
      () async {
        repository.permissionsResult = ReadSuccess<List<VendorRolePermission>>(
          <VendorRolePermission>[superAdminPermissions.first],
        );
        final VendorRoleDetailCubit cubit = build();
        addTearDown(cubit.close);

        await cubit.open(superAdminRoleUuid);

        expect(cubit.state.permissionCountDisagrees, isTrue);
        // Everything returned is still held, and the count is still the
        // backend's.
        expect(cubit.state.permissions, hasLength(1));
        expect(cubit.state.detail!.permissionCount, 3);
      },
    );

    test('nothing disagrees while the companion is still loading', () async {
      repository.manualPermissions = true;
      final VendorRoleDetailCubit cubit = build();
      addTearDown(cubit.close);
      final Future<void> pending = cubit.open(superAdminRoleUuid);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.permissionCountDisagrees, isFalse);

      repository.completePermissions();
      await pending;
    });
  });

  group('idempotence and races', () {
    test('re-opening the same role issues no second pair of reads', () async {
      final VendorRoleDetailCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.open(superAdminRoleUuid);
      await cubit.open(superAdminRoleUuid);

      expect(repository.detailCallCount, 1);
      expect(repository.permissionsCallCount, 1);
    });

    test('opening a different role starts a fresh load', () async {
      final VendorRoleDetailCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.open(superAdminRoleUuid);
      await cubit.open(legacyRoleUuid);

      expect(repository.detailCallCount, 2);
      expect(cubit.state.detail!.roleName, 'Legacy Auditor');
    });

    test('opening the same role after clear does reload', () async {
      final VendorRoleDetailCubit cubit = build();
      addTearDown(cubit.close);
      await cubit.open(superAdminRoleUuid);

      cubit.clear();
      await cubit.open(superAdminRoleUuid);

      expect(repository.detailCallCount, 2);
    });

    test('an earlier detail answer cannot overwrite a later role', () async {
      repository.manualDetail = true;
      final VendorRoleDetailCubit cubit = build();
      addTearDown(cubit.close);

      final Future<void> first = cubit.open(superAdminRoleUuid);
      final Future<void> second = cubit.open(legacyRoleUuid);
      expect(repository.pendingDetailCount, 2);

      // The *second* request answers first, then the first answers late — the
      // classic stale-response race. The late answer must be discarded.
      repository.completeDetailAt(
        1,
        ReadSuccess<VendorRoleDetail?>(legacySummary),
      );
      repository.completeDetailAt(
        0,
        ReadSuccess<VendorRoleDetail?>(superAdminSummary),
      );
      await Future.wait(<Future<void>>[first, second]);

      expect(cubit.state.roleId, legacyRoleUuid);
      expect(cubit.state.detail!.roleName, 'Legacy Auditor');
    });
  });

  group('session isolation', () {
    test('clear drops the role, its permissions and its counts', () async {
      final VendorRoleDetailCubit cubit = build();
      addTearDown(cubit.close);
      await cubit.open(superAdminRoleUuid);

      cubit.clear();

      expect(cubit.state.detail, isNull);
      expect(cubit.state.roleId, isNull);
      expect(cubit.state.permissions, isEmpty);
      expect(cubit.state.failure, isNull);
      expect(cubit.state.permissionsFailure, isNull);
      expect(cubit.state.phase, VendorRoleDetailPhase.initial);
      expect(cubit.state.permissionsPhase, VendorRolePermissionsPhase.initial);
    });

    test('a detail answer in flight when clear runs is discarded', () async {
      repository.manualDetail = true;
      final VendorRoleDetailCubit cubit = build();
      addTearDown(cubit.close);
      final Future<void> pending = cubit.open(superAdminRoleUuid);

      cubit.clear();
      repository.completeDetail();
      await pending;

      expect(cubit.state.detail, isNull);
      expect(cubit.state.phase, VendorRoleDetailPhase.initial);
      // And the companion was never reached for a role nobody is looking at.
      expect(repository.permissionsCallCount, 0);
    });

    test(
      'a permission answer in flight when clear runs is discarded',
      () async {
        repository.manualPermissions = true;
        final VendorRoleDetailCubit cubit = build();
        addTearDown(cubit.close);
        final Future<void> pending = cubit.open(superAdminRoleUuid);
        await Future<void>.delayed(Duration.zero);
        expect(repository.pendingPermissionCount, 1);

        cubit.clear();
        repository.completePermissions();
        await pending;

        expect(cubit.state.permissions, isEmpty);
        expect(cubit.state.phase, VendorRoleDetailPhase.initial);
      },
    );
  });
}
