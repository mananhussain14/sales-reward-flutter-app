import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_status.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_summary.dart';
import 'package:sale_reward/features/retailers/domain/repositories/vendor_retailer_result.dart';
import 'package:sale_reward/features/retailers/presentation/vendor/cubit/vendor_retailer_list_cubit.dart';

import '../../support/vendor_retailer_fakes.dart';

void main() {
  late FakeVendorRetailerRepository repository;
  late VendorRetailerListCubit cubit;

  setUp(() {
    repository = FakeVendorRetailerRepository();
    cubit = VendorRetailerListCubit(repository);
  });

  tearDown(() => cubit.close());

  group('the first read', () {
    test('starts empty and initial', () {
      expect(cubit.state.phase, VendorRetailerListPhase.initial);
      expect(cubit.state.retailers, isEmpty);
      expect(cubit.state.isRefreshing, isFalse);
      expect(cubit.state.failure, isNull);
    });

    test('shows loading, then the directory', () async {
      final List<VendorRetailerListPhase> phases = <VendorRetailerListPhase>[];
      cubit.stream.listen((VendorRetailerListState s) => phases.add(s.phase));

      await cubit.load();
      // The stream is asynchronous; let the last emit reach the listener.
      await Future<void>.delayed(Duration.zero);

      expect(phases, <VendorRetailerListPhase>[
        VendorRetailerListPhase.loading,
        VendorRetailerListPhase.ready,
      ]);
      expect(cubit.state.retailers, hasLength(2));
      expect(cubit.state.isRefreshing, isFalse);
      expect(repository.retailersCallCount, 1);
    });

    test('issues exactly one RPC and reads no shops', () async {
      await cubit.load();

      expect(repository.retailersCallCount, 1);
      expect(repository.shopsCallCount, 0);
      expect(repository.detailCallCount, 0);
    });

    test('an empty directory is ready-and-empty, not a failure', () async {
      repository.retailersResult =
          const VendorRetailerReadSuccess<List<VendorRetailerSummary>>(
            <VendorRetailerSummary>[],
          );

      await cubit.load();

      expect(cubit.state.phase, VendorRetailerListPhase.ready);
      expect(cubit.state.isEmpty, isTrue);
      expect(cubit.state.failure, isNull);
    });

    test('a denial is a failure and keeps the list empty', () async {
      repository.retailersResult =
          deniedRetailerRead<List<VendorRetailerSummary>>();

      await cubit.load();

      expect(cubit.state.phase, VendorRetailerListPhase.failed);
      expect(cubit.state.failure, isA<DeniedFailure>());
      expect(cubit.state.retailers, isEmpty);
      // A denial is not "you manage no Retailers".
      expect(cubit.state.isEmpty, isFalse);
    });

    test('an outage is a failure that a retry can clear', () async {
      repository.retailersResult =
          unavailableRetailerRead<List<VendorRetailerSummary>>();
      await cubit.load();
      expect(cubit.state.phase, VendorRetailerListPhase.failed);

      repository.retailersResult =
          VendorRetailerReadSuccess<List<VendorRetailerSummary>>(
            <VendorRetailerSummary>[northwindSummary],
          );
      await cubit.load();

      expect(cubit.state.phase, VendorRetailerListPhase.ready);
      expect(cubit.state.failure, isNull);
      expect(cubit.state.retailers, hasLength(1));
      expect(repository.retailersCallCount, 2);
    });
  });

  group('refresh', () {
    test('keeps the loaded rows on screen while it runs', () async {
      await cubit.load();

      final Future<void> refreshing = cubit.refresh();
      expect(cubit.state.phase, VendorRetailerListPhase.ready);
      expect(cubit.state.isRefreshing, isTrue);
      expect(cubit.state.retailers, hasLength(2));

      await refreshing;
      expect(cubit.state.isRefreshing, isFalse);
    });

    test('a failed refresh keeps the previous rows', () async {
      await cubit.load();
      repository.retailersResult =
          unavailableRetailerRead<List<VendorRetailerSummary>>();

      await cubit.refresh();

      expect(cubit.state.phase, VendorRetailerListPhase.failed);
      expect(cubit.state.failure, isA<UnavailableFailure>());
      // Still the last thing the backend actually said.
      expect(cubit.state.retailers, hasLength(2));
    });

    test('a refresh over an empty list shows loading again', () async {
      repository.retailersResult =
          const VendorRetailerReadSuccess<List<VendorRetailerSummary>>(
            <VendorRetailerSummary>[],
          );
      await cubit.load();

      final List<VendorRetailerListPhase> phases = <VendorRetailerListPhase>[];
      cubit.stream.listen((VendorRetailerListState s) => phases.add(s.phase));
      await cubit.refresh();
      await Future<void>.delayed(Duration.zero);

      expect(phases.first, VendorRetailerListPhase.loading);
    });

    test('a second refresh while one is in flight is dropped', () async {
      await cubit.load();
      repository.manualRetailers = true;

      final Future<void> first = cubit.refresh();
      final Future<void> second = cubit.refresh();
      final Future<void> third = cubit.refresh();

      // One in-flight request, not three.
      expect(repository.pendingRetailerCount, 1);
      expect(repository.retailersCallCount, 2); // the load, plus one refresh

      repository.completeRetailers();
      await Future.wait(<Future<void>>[first, second, third]);

      expect(cubit.state.isRefreshing, isFalse);
      expect(repository.retailersCallCount, 2);
    });

    test('load is also blocked while a refresh is in flight', () async {
      await cubit.load();
      repository.manualRetailers = true;

      final Future<void> refreshing = cubit.refresh();
      await cubit.load();

      expect(repository.retailersCallCount, 2);

      repository.completeRetailers();
      await refreshing;
    });
  });

  group('local search', () {
    setUp(() async {
      await cubit.load();
    });

    test('matches a Retailer name case-insensitively', () {
      cubit.search('north');

      expect(
        cubit.state.visibleRetailers.map(
          (VendorRetailerSummary r) => r.retailerName,
        ),
        <String>['Northwind Retail'],
      );
      expect(cubit.state.totalCount, 2);
    });

    test('matches a fragment anywhere in the name', () {
      cubit.search('SO STO');
      expect(
        cubit.state.visibleRetailers.single.retailerName,
        'Contoso Stores',
      );
    });

    test('a term matching nothing is "no matches", not "no Retailers"', () {
      cubit.search('zzz');

      expect(cubit.state.visibleRetailers, isEmpty);
      expect(cubit.state.hasNoMatches, isTrue);
      expect(cubit.state.isEmpty, isFalse);
    });

    test('whitespace alone does not narrow anything', () {
      cubit.search('   ');

      expect(cubit.state.hasFilters, isFalse);
      expect(cubit.state.visibleRetailers, hasLength(2));
    });

    test('an unnarrowed list is the backend list, in order', () {
      expect(cubit.state.visibleRetailers, same(cubit.state.retailers));
      expect(
        cubit.state.visibleRetailers.map(
          (VendorRetailerSummary r) => r.retailerName,
        ),
        <String>['Northwind Retail', 'Contoso Stores'],
      );
    });

    test('narrowing preserves the backend order', () {
      cubit.search('r');
      expect(
        cubit.state.visibleRetailers.map(
          (VendorRetailerSummary r) => r.retailerName,
        ),
        <String>['Northwind Retail', 'Contoso Stores'],
      );
    });

    test('the search is never sent to the backend', () async {
      final int before = repository.retailersCallCount;
      cubit.search('north');
      expect(repository.retailersCallCount, before);
    });
  });

  group('local status filtering', () {
    setUp(() async {
      await cubit.load();
    });

    test('offers only the statuses actually present in the data', () {
      expect(cubit.state.presentRelationshipStatuses, <VendorRetailerStatus>[
        VendorRetailerStatus.active,
        VendorRetailerStatus.suspended,
      ]);
    });

    test('filters on relationship status', () {
      cubit.filterByRelationshipStatus(VendorRetailerStatus.suspended);

      expect(
        cubit.state.visibleRetailers.single.retailerName,
        'Contoso Stores',
      );
    });

    test('null clears the filter', () {
      cubit.filterByRelationshipStatus(VendorRetailerStatus.suspended);
      cubit.filterByRelationshipStatus(null);

      expect(cubit.state.statusFilter, isNull);
      expect(cubit.state.visibleRetailers, hasLength(2));
    });

    test('search and status compose', () {
      cubit.search('o');
      cubit.filterByRelationshipStatus(VendorRetailerStatus.suspended);

      expect(
        cubit.state.visibleRetailers.single.retailerName,
        'Contoso Stores',
      );
    });

    test('clearFilters drops both', () {
      cubit.search('north');
      cubit.filterByRelationshipStatus(VendorRetailerStatus.active);

      cubit.clearFilters();

      expect(cubit.state.searchTerm, isEmpty);
      expect(cubit.state.statusFilter, isNull);
      expect(cubit.state.hasFilters, isFalse);
      expect(cubit.state.visibleRetailers, hasLength(2));
    });

    test(
      'an unknown status is still offered when one actually arrived',
      () async {
        // Hiding the rows behind no chip at all would make them unreachable.
        repository.retailersResult =
            VendorRetailerReadSuccess<List<VendorRetailerSummary>>(
              <VendorRetailerSummary>[
                VendorRetailerSummary(
                  relationshipId: foreignRelationshipUuid,
                  retailerOrganizationId: contosoOrganizationUuid,
                  retailerName: 'Future Retail',
                  retailerStatus: VendorRetailerStatus.active,
                  relationshipStatus: VendorRetailerStatus.unknown,
                  relationshipCreatedAt: contosoOnboardedAt,
                  shopCount: 0,
                  activeShopCount: 0,
                  ownerState: northwindSummary.ownerState,
                ),
              ],
            );
        await cubit.load();

        expect(cubit.state.presentRelationshipStatuses, <VendorRetailerStatus>[
          VendorRetailerStatus.unknown,
        ]);
      },
    );
  });

  group('the summary figures', () {
    test('sum the trusted per-row counts', () async {
      await cubit.load();

      expect(cubit.state.totalCount, 2);
      expect(cubit.state.totalShopCount, 4);
      expect(cubit.state.totalActiveShopCount, 3);
    });
  });

  group('private data is cleared on a session change', () {
    test('clear drops rows, search and filter together', () async {
      await cubit.load();
      cubit.search('north');
      cubit.filterByRelationshipStatus(VendorRetailerStatus.active);

      cubit.clear();

      expect(cubit.state.retailers, isEmpty);
      // A search term is a fragment of a Retailer name — private too.
      expect(cubit.state.searchTerm, isEmpty);
      expect(cubit.state.statusFilter, isNull);
      expect(cubit.state.phase, VendorRetailerListPhase.initial);
      expect(cubit.state.failure, isNull);
      expect(cubit.state.isRefreshing, isFalse);
    });

    test('a read that lands after close is dropped', () async {
      repository.manualRetailers = true;
      final Future<void> pending = cubit.load();

      await cubit.close();
      repository.completeRetailers();
      await pending;

      // No emit after close; the test passing without a StateError is the
      // assertion.
      expect(repository.retailersCallCount, 1);
    });
  });
}
