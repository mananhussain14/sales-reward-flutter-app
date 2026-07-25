import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/core/result/read_result.dart';
import 'package:sale_reward/features/roles/domain/entities/vendor_role_status.dart';
import 'package:sale_reward/features/roles/domain/entities/vendor_role_summary.dart';
import 'package:sale_reward/features/roles/presentation/vendor/cubit/vendor_role_list_cubit.dart';

import '../../support/vendor_role_fakes.dart';

void main() {
  late FakeVendorRoleRepository repository;

  setUp(() => repository = FakeVendorRoleRepository());

  VendorRoleListCubit build() => VendorRoleListCubit(repository);

  group('loading', () {
    test('starts idle and reads nothing until asked', () {
      final VendorRoleListCubit cubit = build();

      expect(cubit.state.phase, VendorRoleListPhase.initial);
      expect(repository.rolesCallCount, 0);
      addTearDown(cubit.close);
    });

    test('a successful load holds the backend order untouched', () async {
      final VendorRoleListCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.phase, VendorRoleListPhase.ready);
      expect(
        cubit.state.roles.map((VendorRoleSummary r) => r.roleName),
        <String>[
          'Claim Reviewer',
          'Legacy Auditor',
          'Retailer Owner',
          'Vendor Super Admin',
        ],
      );
      expect(repository.rolesCallCount, 1);
    });

    test('the catalogue is read exactly once per load', () async {
      final VendorRoleListCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.load();

      expect(repository.rolesCallCount, 1);
      // No per-role detail or permission read is issued for a list.
      expect(repository.detailCallCount, 0);
      expect(repository.permissionsCallCount, 0);
    });

    test(
      'an empty response is a ready-and-empty state, not a failure',
      () async {
        repository.rolesResult = const ReadSuccess<List<VendorRoleSummary>>(
          <VendorRoleSummary>[],
        );
        final VendorRoleListCubit cubit = build();
        addTearDown(cubit.close);

        await cubit.load();

        expect(cubit.state.phase, VendorRoleListPhase.ready);
        expect(cubit.state.isEmpty, isTrue);
        expect(cubit.state.failure, isNull);
      },
    );

    test('a failure is retryable and the retry works', () async {
      repository.rolesResult = unavailableRoleRead<List<VendorRoleSummary>>();
      final VendorRoleListCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.load();
      expect(cubit.state.phase, VendorRoleListPhase.failed);
      expect(cubit.state.failure, isA<UnavailableFailure>());

      repository.rolesResult = ReadSuccess<List<VendorRoleSummary>>(
        catalogueSummaries,
      );
      await cubit.load();

      expect(cubit.state.phase, VendorRoleListPhase.ready);
      expect(cubit.state.roles, hasLength(4));
      expect(cubit.state.failure, isNull);
    });

    test(
      'a denial is carried as a denial, never as an empty catalogue',
      () async {
        repository.rolesResult = deniedRoleRead<List<VendorRoleSummary>>();
        final VendorRoleListCubit cubit = build();
        addTearDown(cubit.close);

        await cubit.load();

        expect(cubit.state.failure, isA<DeniedFailure>());
        expect(cubit.state.isEmpty, isFalse);
      },
    );
  });

  group('refreshing', () {
    test('keeps the loaded rows on screen while re-reading', () async {
      final VendorRoleListCubit cubit = build();
      addTearDown(cubit.close);
      await cubit.load();

      repository.manualRoles = true;
      final Future<void> pending = cubit.refresh();

      expect(cubit.state.isRefreshing, isTrue);
      expect(cubit.state.roles, hasLength(4));
      expect(cubit.state.phase, VendorRoleListPhase.ready);

      repository.completeRoles();
      await pending;
      expect(cubit.state.isRefreshing, isFalse);
    });

    test('a failed refresh keeps the rows and reports the failure', () async {
      // The rows already held are still the last thing the backend said.
      final VendorRoleListCubit cubit = build();
      addTearDown(cubit.close);
      await cubit.load();

      repository.rolesResult = unavailableRoleRead<List<VendorRoleSummary>>();
      await cubit.refresh();

      expect(cubit.state.phase, VendorRoleListPhase.failed);
      expect(cubit.state.roles, hasLength(4));
      expect(cubit.state.failure, isA<UnavailableFailure>());
    });

    test('a second refresh while one is in flight is a no-op', () async {
      final VendorRoleListCubit cubit = build();
      addTearDown(cubit.close);
      await cubit.load();

      repository.manualRoles = true;
      final Future<void> first = cubit.refresh();
      await cubit.refresh();

      expect(repository.pendingRoleCount, 1);
      expect(repository.rolesCallCount, 2);

      repository.completeRoles();
      await first;
    });

    test(
      'a refresh over an empty list shows the loading state again',
      () async {
        repository.rolesResult = const ReadSuccess<List<VendorRoleSummary>>(
          <VendorRoleSummary>[],
        );
        final VendorRoleListCubit cubit = build();
        addTearDown(cubit.close);
        await cubit.load();

        repository.manualRoles = true;
        final Future<void> pending = cubit.refresh();

        expect(cubit.state.phase, VendorRoleListPhase.loading);

        repository.completeRoles();
        await pending;
      },
    );
  });

  group('search', () {
    test('narrows by role name without re-reading anything', () async {
      final VendorRoleListCubit cubit = build();
      addTearDown(cubit.close);
      await cubit.load();

      cubit.search('legacy');

      expect(
        cubit.state.visibleRoles.map((VendorRoleSummary r) => r.roleName),
        <String>['Legacy Auditor'],
      );
      expect(repository.rolesCallCount, 1);
    });

    test('is case-insensitive and matches a substring', () async {
      final VendorRoleListCubit cubit = build();
      addTearDown(cubit.close);
      await cubit.load();

      cubit.search('RETAILER');

      expect(cubit.state.visibleRoles.single.roleName, 'Retailer Owner');
    });

    test(
      'a term matching nothing is a no-matches state, not an empty one',
      () async {
        final VendorRoleListCubit cubit = build();
        addTearDown(cubit.close);
        await cubit.load();

        cubit.search('zzzz');

        expect(cubit.state.hasNoMatches, isTrue);
        expect(cubit.state.isEmpty, isFalse);
        expect(cubit.state.totalCount, 4);
      },
    );

    test('a whitespace-only term narrows nothing', () async {
      final VendorRoleListCubit cubit = build();
      addTearDown(cubit.close);
      await cubit.load();

      cubit.search('   ');

      expect(cubit.state.hasFilters, isFalse);
      expect(cubit.state.visibleRoles, hasLength(4));
    });
  });

  group('status filtering', () {
    test('offers only the statuses actually present', () async {
      final VendorRoleListCubit cubit = build();
      addTearDown(cubit.close);
      await cubit.load();

      expect(cubit.state.presentStatuses, <VendorRoleStatus>[
        VendorRoleStatus.active,
        VendorRoleStatus.inactive,
      ]);
    });

    test(
      'a single-status catalogue offers one chip, so the row is hidden',
      () async {
        repository.rolesResult = ReadSuccess<List<VendorRoleSummary>>(
          <VendorRoleSummary>[superAdminSummary],
        );
        final VendorRoleListCubit cubit = build();
        addTearDown(cubit.close);
        await cubit.load();

        expect(cubit.state.presentStatuses, <VendorRoleStatus>[
          VendorRoleStatus.active,
        ]);
      },
    );

    test('an unknown status is offered rather than made unreachable', () async {
      repository.rolesResult =
          ReadSuccess<List<VendorRoleSummary>>(<VendorRoleSummary>[
            superAdminSummary,
            VendorRoleSummary(
              roleId: unknownRoleUuid,
              roleName: 'Future Role',
              description: null,
              status: VendorRoleStatus.unknown,
              createdAt: superAdminCreatedAt,
              permissionCount: 1,
              assignedMemberCount: 0,
            ),
          ]);
      final VendorRoleListCubit cubit = build();
      addTearDown(cubit.close);
      await cubit.load();

      expect(cubit.state.presentStatuses, contains(VendorRoleStatus.unknown));
    });

    test('filtering to inactive keeps only the retired definition', () async {
      final VendorRoleListCubit cubit = build();
      addTearDown(cubit.close);
      await cubit.load();

      cubit.filterByStatus(VendorRoleStatus.inactive);

      expect(cubit.state.visibleRoles.single.roleName, 'Legacy Auditor');
    });

    test('clearing the filter restores the original backend order', () async {
      final VendorRoleListCubit cubit = build();
      addTearDown(cubit.close);
      await cubit.load();

      cubit.filterByStatus(VendorRoleStatus.active);
      cubit.filterByStatus(null);

      expect(cubit.state.statusFilter, isNull);
      expect(cubit.state.visibleRoles, cubit.state.roles);
      expect(
        cubit.state.visibleRoles.map((VendorRoleSummary r) => r.roleName),
        <String>[
          'Claim Reviewer',
          'Legacy Auditor',
          'Retailer Owner',
          'Vendor Super Admin',
        ],
      );
    });

    test('search and status filter combine', () async {
      final VendorRoleListCubit cubit = build();
      addTearDown(cubit.close);
      await cubit.load();

      cubit.search('e');
      cubit.filterByStatus(VendorRoleStatus.inactive);

      expect(cubit.state.visibleRoles.single.roleName, 'Legacy Auditor');
    });

    test('clearFilters drops both and restores every row', () async {
      final VendorRoleListCubit cubit = build();
      addTearDown(cubit.close);
      await cubit.load();

      cubit.search('legacy');
      cubit.filterByStatus(VendorRoleStatus.inactive);
      cubit.clearFilters();

      expect(cubit.state.searchTerm, isEmpty);
      expect(cubit.state.statusFilter, isNull);
      expect(cubit.state.hasFilters, isFalse);
      expect(cubit.state.visibleRoles, hasLength(4));
    });

    test('narrowing is a subsequence, never a re-ranking', () async {
      final VendorRoleListCubit cubit = build();
      addTearDown(cubit.close);
      await cubit.load();

      cubit.filterByStatus(VendorRoleStatus.active);

      expect(
        cubit.state.visibleRoles.map((VendorRoleSummary r) => r.roleName),
        <String>['Claim Reviewer', 'Retailer Owner', 'Vendor Super Admin'],
      );
    });
  });

  group('the figures the screen reports', () {
    test(
      'total, active and inactive are counted from returned statuses',
      () async {
        final VendorRoleListCubit cubit = build();
        addTearDown(cubit.close);
        await cubit.load();

        expect(cubit.state.totalCount, 4);
        expect(cubit.state.activeCount, 3);
        expect(cubit.state.inactiveCount, 1);
      },
    );

    test(
      'an unknown status is counted as neither active nor inactive',
      () async {
        repository.rolesResult =
            ReadSuccess<List<VendorRoleSummary>>(<VendorRoleSummary>[
              VendorRoleSummary(
                roleId: unknownRoleUuid,
                roleName: 'Future Role',
                description: null,
                status: VendorRoleStatus.unknown,
                createdAt: superAdminCreatedAt,
                permissionCount: 0,
                assignedMemberCount: 0,
              ),
            ]);
        final VendorRoleListCubit cubit = build();
        addTearDown(cubit.close);
        await cubit.load();

        expect(cubit.state.totalCount, 1);
        expect(cubit.state.activeCount, 0);
        expect(cubit.state.inactiveCount, 0);
      },
    );

    test('the mapping total sums every role\'s permission count', () async {
      final VendorRoleListCubit cubit = build();
      addTearDown(cubit.close);
      await cubit.load();

      // 0 + 2 + 2 + 3 — mappings, not distinct permissions.
      expect(cubit.state.totalPermissionMappings, 7);
    });

    test('the Vendor-scoped assignment total sums the member counts', () async {
      final VendorRoleListCubit cubit = build();
      addTearDown(cubit.close);
      await cubit.load();

      // 0 + 1 + 0 + 2 — the caller's own Vendor alone.
      expect(cubit.state.totalAssignments, 3);
    });

    test('a Retailer role is kept, with a zero count for this Vendor', () async {
      // The true answer, not a hidden row: the catalogue is global and the count
      // is tenant-scoped.
      final VendorRoleListCubit cubit = build();
      addTearDown(cubit.close);
      await cubit.load();

      final VendorRoleSummary retailerRole = cubit.state.roles.firstWhere(
        (VendorRoleSummary r) => r.roleName == 'Retailer Owner',
      );
      expect(retailerRole.assignedMemberCount, 0);
      expect(cubit.state.roles, contains(retailerRole));
    });
  });

  group('session isolation', () {
    test('clear drops the rows, the counts, the term and the filter', () async {
      final VendorRoleListCubit cubit = build();
      addTearDown(cubit.close);
      await cubit.load();
      cubit.search('legacy');
      cubit.filterByStatus(VendorRoleStatus.inactive);

      cubit.clear();

      expect(cubit.state.roles, isEmpty);
      expect(cubit.state.totalAssignments, 0);
      expect(cubit.state.searchTerm, isEmpty);
      expect(cubit.state.statusFilter, isNull);
      expect(cubit.state.failure, isNull);
      expect(cubit.state.phase, VendorRoleListPhase.initial);
    });

    test('a response in flight when clear runs is discarded', () async {
      // The stale-response race: A's answer must not refill a list emptied for
      // B, because it carries A's assigned member counts.
      repository.manualRoles = true;
      final VendorRoleListCubit cubit = build();
      addTearDown(cubit.close);
      final Future<void> pending = cubit.load();

      cubit.clear();
      repository.completeRoles();
      await pending;

      expect(cubit.state.roles, isEmpty);
      expect(cubit.state.phase, VendorRoleListPhase.initial);
    });

    test('a load after clear works normally', () async {
      final VendorRoleListCubit cubit = build();
      addTearDown(cubit.close);
      await cubit.load();
      cubit.clear();

      await cubit.load();

      expect(cubit.state.roles, hasLength(4));
      expect(repository.rolesCallCount, 2);
    });
  });
}
