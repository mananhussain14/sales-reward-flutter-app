import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/core/result/read_result.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_status.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_summary.dart';
import 'package:sale_reward/features/products/presentation/vendor/cubit/vendor_product_list_cubit.dart';

import '../../support/vendor_product_fakes.dart';

/// The catalogue cubit.
///
/// What it must get right, and why each matters:
///
/// * **One read for the whole screen.** The counts arrive on the rows, so
///   nothing here issues a per-product query.
/// * **A refresh never blanks the list**, and a *failed* refresh never discards
///   it — the rows on screen are still the last thing the backend actually said.
/// * **Search and filtering are local and lossless.** They narrow a complete
///   trusted answer, preserve the backend's order, and restore it exactly when
///   cleared.
/// * **A session change empties everything, and a late answer for the previous
///   person cannot refill it.**
void main() {
  late FakeVendorProductRepository repository;

  setUp(() => repository = FakeVendorProductRepository());

  VendorProductListCubit build() => VendorProductListCubit(repository);

  group('loading', () {
    test('starts in initial with nothing loaded', () {
      final VendorProductListCubit cubit = build();

      expect(cubit.state.phase, VendorProductListPhase.initial);
      expect(cubit.state.products, isEmpty);
      expect(cubit.state.isRefreshing, isFalse);
      expect(repository.productsCallCount, 0);
    });

    test('a successful load renders the catalogue in backend order', () async {
      final VendorProductListCubit cubit = build();

      await cubit.load();

      expect(cubit.state.phase, VendorProductListPhase.ready);
      expect(cubit.state.products, productCatalogueSummaries);
      expect(
        cubit.state.products.map((VendorProductSummary p) => p.productCode),
        <String>['ESP-1000', 'DEC-2000', 'NEW-4000', 'RET-3000'],
      );
      expect(cubit.state.isRefreshing, isFalse);
      expect(cubit.state.failure, isNull);
      expect(repository.productsCallCount, 1);
    });

    test('the loading phase is visible while the read is in flight', () async {
      repository.manualProducts = true;
      final VendorProductListCubit cubit = build();

      final Future<void> pending = cubit.load();
      expect(cubit.state.phase, VendorProductListPhase.loading);
      expect(cubit.state.isRefreshing, isTrue);

      repository.completeProducts();
      await pending;

      expect(cubit.state.phase, VendorProductListPhase.ready);
    });

    test('an empty catalogue is a success, not a failure', () async {
      repository.productsResult = const ReadSuccess<List<VendorProductSummary>>(
        <VendorProductSummary>[],
      );
      final VendorProductListCubit cubit = build();

      await cubit.load();

      expect(cubit.state.phase, VendorProductListPhase.ready);
      expect(cubit.state.isEmpty, isTrue);
      expect(cubit.state.failure, isNull);
    });

    test('a failed first load carries the discriminant', () async {
      repository.productsResult =
          unavailableProductRead<List<VendorProductSummary>>();
      final VendorProductListCubit cubit = build();

      await cubit.load();

      expect(cubit.state.phase, VendorProductListPhase.failed);
      expect(cubit.state.failure, isA<UnavailableFailure>());
      expect(cubit.state.products, isEmpty);
    });

    test('a denial is a denial, never an empty catalogue', () async {
      repository.productsResult =
          deniedProductRead<List<VendorProductSummary>>();
      final VendorProductListCubit cubit = build();

      await cubit.load();

      expect(cubit.state.phase, VendorProductListPhase.failed);
      expect(cubit.state.failure, isA<DeniedFailure>());
      expect(cubit.state.isEmpty, isFalse);
    });

    test('a retry after a failure succeeds', () async {
      repository.productsResult =
          unavailableProductRead<List<VendorProductSummary>>();
      final VendorProductListCubit cubit = build();
      await cubit.load();

      repository.productsResult = ReadSuccess<List<VendorProductSummary>>(
        productCatalogueSummaries,
      );
      await cubit.load();

      expect(cubit.state.phase, VendorProductListPhase.ready);
      expect(cubit.state.products, hasLength(4));
      expect(repository.productsCallCount, 2);
    });
  });

  group('refreshing', () {
    test('re-reads without blanking the rows', () async {
      final VendorProductListCubit cubit = build();
      await cubit.load();

      repository.manualProducts = true;
      final Future<void> pending = cubit.refresh();

      // The rows stay on screen while the read is in flight; the refresh is
      // visible through the flag rather than through an empty list.
      expect(cubit.state.products, hasLength(4));
      expect(cubit.state.phase, VendorProductListPhase.ready);
      expect(cubit.state.isRefreshing, isTrue);

      repository.completeProducts();
      await pending;

      expect(cubit.state.isRefreshing, isFalse);
      expect(repository.productsCallCount, 2);
    });

    test(
      'a failed refresh keeps the stale rows and records the failure',
      () async {
        final VendorProductListCubit cubit = build();
        await cubit.load();

        repository.productsResult =
            unavailableProductRead<List<VendorProductSummary>>();
        await cubit.refresh();

        // Discarding a real catalogue because a refresh failed would replace it
        // with a false one.
        expect(cubit.state.products, hasLength(4));
        expect(cubit.state.phase, VendorProductListPhase.failed);
        expect(cubit.state.failure, isA<UnavailableFailure>());
      },
    );

    test('a duplicate refresh while one is in flight is suppressed', () async {
      final VendorProductListCubit cubit = build();
      await cubit.load();

      repository.manualProducts = true;
      final Future<void> first = cubit.refresh();
      // A second tap must be a no-op, not a queued duplicate.
      await cubit.refresh();

      expect(repository.pendingProductCount, 1);
      expect(repository.productsCallCount, 2);

      repository.completeProducts();
      await first;
    });

    test('a refresh over an empty list shows the loading phase', () async {
      repository.productsResult = const ReadSuccess<List<VendorProductSummary>>(
        <VendorProductSummary>[],
      );
      final VendorProductListCubit cubit = build();
      await cubit.load();

      repository.manualProducts = true;
      final Future<void> pending = cubit.refresh();

      expect(cubit.state.phase, VendorProductListPhase.loading);

      repository.completeProducts();
      await pending;
    });

    test('a successful refresh clears a previous failure', () async {
      repository.productsResult =
          unavailableProductRead<List<VendorProductSummary>>();
      final VendorProductListCubit cubit = build();
      await cubit.load();
      expect(cubit.state.failure, isNotNull);

      repository.productsResult = ReadSuccess<List<VendorProductSummary>>(
        productCatalogueSummaries,
      );
      await cubit.refresh();

      expect(cubit.state.failure, isNull);
      expect(cubit.state.phase, VendorProductListPhase.ready);
    });
  });

  group('search', () {
    Future<VendorProductListCubit> loaded() async {
      final VendorProductListCubit cubit = build();
      await cubit.load();
      return cubit;
    }

    test('matches the product name', () async {
      final VendorProductListCubit cubit = await loaded();

      cubit.search('espresso');

      expect(cubit.state.visibleProducts, <VendorProductSummary>[
        espressoSummary,
      ]);
      // Nothing was sent anywhere.
      expect(repository.productsCallCount, 1);
    });

    test('matches the product code', () async {
      final VendorProductListCubit cubit = await loaded();

      cubit.search('RET-3000');

      expect(cubit.state.visibleProducts, <VendorProductSummary>[
        retiredSummary,
      ]);
    });

    test('matches the barcode', () async {
      final VendorProductListCubit cubit = await loaded();

      cubit.search('5012345678900');

      expect(cubit.state.visibleProducts, <VendorProductSummary>[
        espressoSummary,
      ]);
    });

    test('matches the brand', () async {
      final VendorProductListCubit cubit = await loaded();

      cubit.search('Harvest');

      // Three of the four carry the brand; the decaf row has none.
      expect(cubit.state.visibleProducts, hasLength(3));
      expect(cubit.state.visibleProducts.contains(decafSummary), isFalse);
    });

    test('is case-insensitive in both directions', () async {
      final VendorProductListCubit cubit = await loaded();

      cubit.search('ESPRESSO');
      expect(cubit.state.visibleProducts, hasLength(1));

      cubit.search('esp-1000');
      expect(cubit.state.visibleProducts, <VendorProductSummary>[
        espressoSummary,
      ]);
    });

    test(
      'a product with no barcode or brand is not matched by an empty one',
      () async {
        // Absent values contribute nothing to the haystack rather than an empty
        // string, so they cannot be "matched" by a stray separator.
        final VendorProductListCubit cubit = await loaded();

        cubit.search('null');

        expect(cubit.state.visibleProducts, isEmpty);
      },
    );

    test('the description is deliberately not searched', () async {
      // Matching a paragraph would surface rows whose reason for matching is
      // invisible in the result.
      final VendorProductListCubit cubit = await loaded();

      cubit.search('dark roast blend');

      expect(cubit.state.visibleProducts, isEmpty);
    });

    test('surrounding whitespace is trimmed', () async {
      final VendorProductListCubit cubit = await loaded();

      cubit.search('  decaf  ');

      expect(cubit.state.visibleProducts, <VendorProductSummary>[decafSummary]);
    });

    test('a whitespace-only term narrows nothing', () async {
      final VendorProductListCubit cubit = await loaded();

      cubit.search('   ');

      expect(cubit.state.hasFilters, isFalse);
      expect(cubit.state.visibleProducts, productCatalogueSummaries);
    });

    test('a term matching nothing is hasNoMatches, not isEmpty', () async {
      final VendorProductListCubit cubit = await loaded();

      cubit.search('zzzz');

      expect(cubit.state.hasNoMatches, isTrue);
      expect(cubit.state.isEmpty, isFalse);
      expect(cubit.state.visibleProducts, isEmpty);
    });

    test('narrowing preserves the backend order', () async {
      final VendorProductListCubit cubit = await loaded();

      cubit.search('Harvest');

      // A subsequence of the original, never a re-ranking.
      expect(
        cubit.state.visibleProducts.map(
          (VendorProductSummary p) => p.productCode,
        ),
        <String>['ESP-1000', 'NEW-4000', 'RET-3000'],
      );
    });
  });

  group('status filtering', () {
    Future<VendorProductListCubit> loaded() async {
      final VendorProductListCubit cubit = build();
      await cubit.load();
      return cubit;
    }

    test('filters to active products', () async {
      final VendorProductListCubit cubit = await loaded();

      cubit.filterByStatus(VendorProductStatus.active);

      expect(cubit.state.visibleProducts, hasLength(3));
      expect(cubit.state.visibleProducts.contains(retiredSummary), isFalse);
    });

    test('filters to inactive products', () async {
      final VendorProductListCubit cubit = await loaded();

      cubit.filterByStatus(VendorProductStatus.inactive);

      expect(cubit.state.visibleProducts, <VendorProductSummary>[
        retiredSummary,
      ]);
    });

    test('null clears the filter', () async {
      final VendorProductListCubit cubit = await loaded();
      cubit.filterByStatus(VendorProductStatus.inactive);

      cubit.filterByStatus(null);

      expect(cubit.state.statusFilter, isNull);
      expect(cubit.state.visibleProducts, productCatalogueSummaries);
    });

    test(
      'the offered statuses come from the loaded rows, not the enum',
      () async {
        // A chip that could only ever produce an empty list would imply the
        // backend uses a status it has not sent.
        final VendorProductListCubit cubit = await loaded();

        expect(cubit.state.presentStatuses, <VendorProductStatus>[
          VendorProductStatus.active,
          VendorProductStatus.inactive,
        ]);
        expect(
          cubit.state.presentStatuses.contains(VendorProductStatus.unknown),
          isFalse,
        );
      },
    );

    test('an unknown status IS offered when one actually arrived', () async {
      // Hiding those rows behind no chip at all would make them unreachable.
      repository.productsResult =
          ReadSuccess<List<VendorProductSummary>>(<VendorProductSummary>[
            espressoSummary,
            VendorProductSummary(
              productId: unknownProductUuid,
              productCode: 'FUT-9000',
              barcode: null,
              productName: 'Future Product',
              brand: null,
              description: null,
              status: VendorProductStatus.unknown,
              activeAssignmentCount: 0,
              createdAt: espressoCreatedAt,
              updatedAt: espressoUpdatedAt,
            ),
          ]);
      final VendorProductListCubit cubit = await loaded();

      expect(
        cubit.state.presentStatuses.contains(VendorProductStatus.unknown),
        isTrue,
      );
      // And it is counted as neither active nor inactive.
      expect(cubit.state.activeCount, 1);
      expect(cubit.state.inactiveCount, 0);
      expect(cubit.state.totalCount, 2);
    });

    test('search and filter combine', () async {
      final VendorProductListCubit cubit = await loaded();

      cubit.search('Harvest');
      cubit.filterByStatus(VendorProductStatus.inactive);

      expect(cubit.state.visibleProducts, <VendorProductSummary>[
        retiredSummary,
      ]);
    });

    test('clearFilters restores the backend order exactly', () async {
      final VendorProductListCubit cubit = await loaded();
      cubit.search('espresso');
      cubit.filterByStatus(VendorProductStatus.active);

      cubit.clearFilters();

      expect(cubit.state.searchTerm, isEmpty);
      expect(cubit.state.statusFilter, isNull);
      expect(cubit.state.hasFilters, isFalse);
      expect(cubit.state.visibleProducts, productCatalogueSummaries);
      // Clearing does not re-read.
      expect(repository.productsCallCount, 1);
    });
  });

  group('summary figures', () {
    test('are counted from the returned rows', () async {
      final VendorProductListCubit cubit = build();
      await cubit.load();

      expect(cubit.state.totalCount, 4);
      expect(cubit.state.activeCount, 3);
      expect(cubit.state.inactiveCount, 1);
      // 2 + 0 + 0 + 1 — a sum of the ACTIVE assignment counts alone.
      expect(cubit.state.totalActiveAssignments, 3);
    });

    test('an empty catalogue reports zeroes rather than throwing', () async {
      repository.productsResult = const ReadSuccess<List<VendorProductSummary>>(
        <VendorProductSummary>[],
      );
      final VendorProductListCubit cubit = build();
      await cubit.load();

      expect(cubit.state.totalCount, 0);
      expect(cubit.state.activeCount, 0);
      expect(cubit.state.totalActiveAssignments, 0);
      expect(cubit.state.presentStatuses, isEmpty);
    });

    test('the summary state exposes no total assignment figure', () {
      // The list read returns no `assignment_count` for any row, so summing one
      // would be inventing it.
      const VendorProductListState state = VendorProductListState();

      expect(
        state.toString().toLowerCase().contains('totalassignments'),
        isFalse,
      );
    });
  });

  group('session isolation', () {
    test('clear empties every piece of state', () async {
      final VendorProductListCubit cubit = build();
      await cubit.load();
      cubit.search('espresso');
      cubit.filterByStatus(VendorProductStatus.active);

      cubit.clear();

      expect(cubit.state.products, isEmpty);
      expect(cubit.state.searchTerm, isEmpty);
      expect(cubit.state.statusFilter, isNull);
      expect(cubit.state.failure, isNull);
      expect(cubit.state.isRefreshing, isFalse);
      expect(cubit.state.phase, VendorProductListPhase.initial);
    });

    test('clear also drops a recorded failure', () async {
      repository.productsResult =
          deniedProductRead<List<VendorProductSummary>>();
      final VendorProductListCubit cubit = build();
      await cubit.load();
      expect(cubit.state.failure, isNotNull);

      cubit.clear();

      expect(cubit.state.failure, isNull);
    });

    test(
      'a response in flight when clear runs is discarded on arrival',
      () async {
        // The stale-response race: an answer for the previous person must not
        // refill a list that has just been emptied for the next one.
        repository.manualProducts = true;
        final VendorProductListCubit cubit = build();
        final Future<void> pending = cubit.load();
        expect(repository.pendingProductCount, 1);

        cubit.clear();
        repository.completeProducts();
        await pending;

        expect(cubit.state.products, isEmpty);
        expect(cubit.state.phase, VendorProductListPhase.initial);
      },
    );

    test('a fresh load after clear still works', () async {
      repository.manualProducts = true;
      final VendorProductListCubit cubit = build();
      final Future<void> stale = cubit.load();
      cubit.clear();

      final Future<void> fresh = cubit.load();
      // A's answer lands first and is dropped; B's lands second and is kept.
      repository.completeProducts(
        ReadSuccess<List<VendorProductSummary>>(productCatalogueSummaries),
      );
      await stale;
      expect(cubit.state.products, isEmpty);

      repository.completeProducts(
        ReadSuccess<List<VendorProductSummary>>(<VendorProductSummary>[
          decafSummary,
        ]),
      );
      await fresh;

      expect(cubit.state.products, <VendorProductSummary>[decafSummary]);
    });

    test(
      'clear resets the in-flight guard so the next load is not blocked',
      () async {
        repository.manualProducts = true;
        final VendorProductListCubit cubit = build();
        final Future<void> pending = cubit.load();

        cubit.clear();
        // isRefreshing was true when clear ran; the reset state must not leave the
        // cubit permanently unable to load.
        expect(cubit.state.isRefreshing, isFalse);

        unawaitedLoad(cubit);
        expect(repository.productsCallCount, 2);

        repository.completeProducts();
        repository.completeProducts();
        await pending;
      },
    );
  });
}

/// Starts a load without awaiting it, so a test can assert on the call count
/// while the read is still pending.
void unawaitedLoad(VendorProductListCubit cubit) {
  cubit.load();
}
