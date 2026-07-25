import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/core/result/read_result.dart';
import 'package:sale_reward/features/products/data/datasources/vendor_product_rpc_data_source.dart';
import 'package:sale_reward/features/products/data/repositories/supabase_vendor_product_repository.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_assigned_retailer.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_assignment_status.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_detail.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_status.dart';
import 'package:sale_reward/features/products/presentation/vendor/cubit/vendor_product_detail_cubit.dart';

import '../../support/vendor_product_fakes.dart';

/// The product detail cubit.
///
/// The property this file exists for is the **loading sequence**:
/// `get_vendor_product_detail` first, `list_vendor_product_assigned_retailers`
/// only after one valid row is confirmed, never in parallel. Both reads answer
/// an empty result for a product this caller cannot address, and only the detail
/// read's zero rows is authoritative — so a companion issued first, or issued at
/// all for an unaddressable id, would make "never assigned" and "not yours"
/// indistinguishable, and the safe reading of the second is not the first.
void main() {
  late FakeVendorProductRepository repository;

  setUp(() => repository = FakeVendorProductRepository());

  VendorProductDetailCubit build() => VendorProductDetailCubit(repository);

  group('the loading sequence', () {
    test('detail is read first, then the assignments, once each', () async {
      final VendorProductDetailCubit cubit = build();

      await cubit.open(espressoProductUuid);

      expect(repository.callLog, <String>['detail', 'assignments']);
      expect(repository.requestedDetailIds, <String>[espressoProductUuid]);
      expect(repository.requestedAssignmentIds, <String>[espressoProductUuid]);
    });

    test('the two reads are never issued in parallel', () async {
      repository.manualDetail = true;
      final VendorProductDetailCubit cubit = build();

      final Future<void> pending = cubit.open(espressoProductUuid);
      // The detail is in flight and the companion has not been asked.
      expect(repository.pendingDetailCount, 1);
      expect(repository.assignmentsCallCount, 0);

      repository.completeDetail();
      await pending;

      expect(repository.assignmentsCallCount, 1);
    });

    test('both companions receive the same product id', () async {
      final VendorProductDetailCubit cubit = build();

      await cubit.open(retiredProductUuid);

      expect(
        repository.requestedDetailIds.single,
        repository.requestedAssignmentIds.single,
      );
    });

    test('a ready product exposes the detail and its rows', () async {
      final VendorProductDetailCubit cubit = build();

      await cubit.open(espressoProductUuid);

      expect(cubit.state.phase, VendorProductDetailPhase.ready);
      expect(cubit.state.detail, espressoDetail);
      expect(cubit.state.assignmentsPhase, VendorProductAssignmentsPhase.ready);
      expect(cubit.state.assignments, espressoAssignments);
      expect(cubit.state.productId, espressoProductUuid);
    });
  });

  group('a product this caller cannot address', () {
    test('zero rows becomes notFound and issues NO assignment read', () async {
      repository.detailResult = const ReadSuccess<VendorProductDetail?>(null);
      final VendorProductDetailCubit cubit = build();

      await cubit.open(unknownProductUuid);

      expect(cubit.state.phase, VendorProductDetailPhase.notFound);
      expect(cubit.state.detail, isNull);
      // The whole point: an empty assignment list would look like a product
      // that has never been assigned.
      expect(repository.assignmentsCallCount, 0);
      expect(repository.callLog, <String>['detail']);
    });

    test('a valid unknown id makes exactly one detail call', () async {
      // Driven through the **real** repository over a counting data source, so
      // the guard is genuinely in the path rather than stubbed out.
      int detailCalls = 0;
      int assignmentCalls = 0;

      final SupabaseVendorProductRepository real =
          SupabaseVendorProductRepository(
            rpc: VendorProductRpcDataSource(
              products: () async => productRows(),
              detail: (String productId) async {
                detailCalls++;
                return const <Object?>[]; // zero rows
              },
              assignedRetailers: (String productId) async {
                assignmentCalls++;
                return const <Object?>[];
              },
            ),
          );

      final VendorProductDetailCubit cubit = VendorProductDetailCubit(real);
      await cubit.open(unknownProductUuid);

      expect(detailCalls, 1);
      expect(assignmentCalls, 0);
      expect(cubit.state.phase, VendorProductDetailPhase.notFound);
    });

    test('a malformed id makes ZERO RPC calls of either kind', () async {
      // Both companions take a PostgreSQL `uuid`, so a malformed selector that
      // reached either would come back as a `22P02` cast error — raised before
      // the function body runs, and therefore an operational failure wearing the
      // wrong clothes, with a retry that could never succeed.
      int detailCalls = 0;
      int assignmentCalls = 0;

      final SupabaseVendorProductRepository real =
          SupabaseVendorProductRepository(
            rpc: VendorProductRpcDataSource(
              products: () async => productRows(),
              detail: (String productId) async {
                detailCalls++;
                return <Map<String, Object?>>[productDetailRow()];
              },
              assignedRetailers: (String productId) async {
                assignmentCalls++;
                return <Map<String, Object?>>[assignedRetailerRow()];
              },
            ),
          );

      final VendorProductDetailCubit cubit = VendorProductDetailCubit(real);
      await cubit.open('not-a-uuid');

      expect(detailCalls, 0);
      expect(assignmentCalls, 0);
      expect(cubit.state.phase, VendorProductDetailPhase.notFound);
    });

    test('an empty route segment reaches the same state, silently', () async {
      final SupabaseVendorProductRepository real =
          SupabaseVendorProductRepository(
            rpc: VendorProductRpcDataSource(
              products: () async => productRows(),
              detail: (String productId) async =>
                  fail('the detail read must not be issued'),
              assignedRetailers: (String productId) async =>
                  fail('the assignment read must not be issued'),
            ),
          );

      final VendorProductDetailCubit cubit = VendorProductDetailCubit(real);
      await cubit.open('');

      expect(cubit.state.phase, VendorProductDetailPhase.notFound);
    });

    test('notFound is not retryable', () async {
      repository.detailResult = const ReadSuccess<VendorProductDetail?>(null);
      final VendorProductDetailCubit cubit = build();
      await cubit.open(unknownProductUuid);

      // The backend answered, and it will answer the same way. `retryDetail`
      // exists for an outage, and `retryAssignments` refuses outside `ready`.
      await cubit.retryAssignments();

      expect(repository.assignmentsCallCount, 0);
      expect(cubit.state.phase, VendorProductDetailPhase.notFound);
    });
  });

  group('a product with zero assignments', () {
    test('is distinguishable from an unaddressable one', () async {
      final VendorProductDetailCubit cubit = build();

      await cubit.open(unassignedProductUuid);

      expect(cubit.state.phase, VendorProductDetailPhase.ready);
      expect(cubit.state.hasNoAssignments, isTrue);
      // The companion WAS called — the empty list is a real answer, not the
      // ambiguous one an unknown id would have produced.
      expect(repository.assignmentsCallCount, 1);
      expect(cubit.state.assignments, isEmpty);
    });

    test('both counts are zero, never null', () async {
      final VendorProductDetailCubit cubit = build();

      await cubit.open(unassignedProductUuid);

      expect(cubit.state.detail!.assignmentCount, 0);
      expect(cubit.state.detail!.activeAssignmentCount, 0);
      expect(cubit.state.assignmentCountDisagrees, isFalse);
    });
  });

  group('an inactive product', () {
    test('is fully readable and keeps its assignments', () async {
      // set_vendor_product_status deliberately does not cascade.
      final VendorProductDetailCubit cubit = build();

      await cubit.open(retiredProductUuid);

      expect(cubit.state.phase, VendorProductDetailPhase.ready);
      expect(cubit.state.detail!.status, VendorProductStatus.inactive);
      expect(cubit.state.detail!.assignmentCount, 1);
      expect(cubit.state.detail!.activeAssignmentCount, 1);
      expect(cubit.state.assignments, hasLength(1));
      expect(
        cubit.state.assignments.single.assignmentStatus,
        VendorProductAssignmentStatus.active,
      );
    });

    test(
      'the assignment read is issued exactly as for an active product',
      () async {
        final VendorProductDetailCubit cubit = build();

        await cubit.open(retiredProductUuid);

        expect(repository.callLog, <String>['detail', 'assignments']);
      },
    );
  });

  group('assignment rows', () {
    test('active and inactive rows are both kept, in backend order', () async {
      final VendorProductDetailCubit cubit = build();

      await cubit.open(espressoProductUuid);

      expect(cubit.state.assignments, hasLength(3));
      expect(
        cubit.state.assignments.map(
          (VendorProductAssignedRetailer a) => a.retailerName,
        ),
        <String>['Harbour Provisions', 'Northwind Retail', 'Old Town Grocers'],
      );
      expect(cubit.state.activeAssignments, hasLength(2));
      expect(cubit.state.inactiveAssignments, hasLength(1));
    });

    test('the rendered rows equal assignment_count', () async {
      // The invariant the backend asserts in pgTAP, checked from this side.
      final VendorProductDetailCubit cubit = build();

      await cubit.open(espressoProductUuid);

      expect(
        cubit.state.assignments.length,
        cubit.state.detail!.assignmentCount,
      );
      expect(
        cubit.state.activeAssignments.length,
        cubit.state.detail!.activeAssignmentCount,
      );
      expect(cubit.state.assignmentCountDisagrees, isFalse);
    });

    test('a null relationship row is kept and marked unlinkable', () async {
      final VendorProductDetailCubit cubit = build();

      await cubit.open(espressoProductUuid);

      final VendorProductAssignedRetailer orphan = cubit.state.assignments.last;
      expect(orphan.retailerName, 'Old Town Grocers');
      expect(orphan.relationshipId, isNull);
      expect(orphan.relationshipStatus, isNull);
      expect(orphan.isCrossLinkable, isFalse);
      // Still a real assignment with a real status, and still counted.
      expect(orphan.assignmentStatus, VendorProductAssignmentStatus.inactive);
      expect(cubit.state.hasUnlinkedAssignments, isTrue);
    });

    test('a non-null relationship row is cross-linkable by that id', () async {
      final VendorProductDetailCubit cubit = build();

      await cubit.open(espressoProductUuid);

      final VendorProductAssignedRetailer linked = cubit.state.assignments
          .firstWhere(
            (VendorProductAssignedRetailer a) =>
                a.retailerName == 'Northwind Retail',
          );
      expect(linked.isCrossLinkable, isTrue);
      expect(linked.relationshipId, northwindRelationshipId);
      // Never the organization id: it names a tenant other Vendors may manage,
      // and the Retailer route does not accept it.
      expect(linked.relationshipId, isNot(linked.retailerOrganizationId));
    });

    test(
      'an active assignment on a suspended relationship stays linkable',
      () async {
        // What makes a row un-openable is the absence of the row to open, never a
        // status.
        final VendorProductDetailCubit cubit = build();

        await cubit.open(espressoProductUuid);

        final VendorProductAssignedRetailer suspended =
            cubit.state.assignments.first;
        expect(suspended.retailerName, 'Harbour Provisions');
        expect(suspended.assignmentStatus.isActive, isTrue);
        expect(suspended.relationshipStatus!.isActive, isFalse);
        expect(suspended.retailerStatus.isActive, isFalse);
        expect(suspended.isCrossLinkable, isTrue);
      },
    );

    test('a product with no unlinkable rows reports so', () async {
      final VendorProductDetailCubit cubit = build();

      await cubit.open(retiredProductUuid);

      expect(cubit.state.hasUnlinkedAssignments, isFalse);
    });

    test('a count mismatch is surfaced without changing either side', () async {
      repository.assignmentsResult =
          ReadSuccess<List<VendorProductAssignedRetailer>>(
            <VendorProductAssignedRetailer>[espressoAssignments.first],
          );
      final VendorProductDetailCubit cubit = build();

      await cubit.open(espressoProductUuid);

      expect(cubit.state.assignmentCountDisagrees, isTrue);
      // Everything returned is still held, and the count is still the backend's.
      expect(cubit.state.assignments, hasLength(1));
      expect(cubit.state.detail!.assignmentCount, 3);
      expect(cubit.state.detail!.activeAssignmentCount, 2);
    });
  });

  group('the assignment section degrades on its own', () {
    test('a failure keeps the loaded product on screen', () async {
      repository.assignmentsResult =
          unavailableProductRead<List<VendorProductAssignedRetailer>>();
      final VendorProductDetailCubit cubit = build();

      await cubit.open(espressoProductUuid);

      expect(cubit.state.phase, VendorProductDetailPhase.ready);
      expect(cubit.state.detail, espressoDetail);
      expect(
        cubit.state.assignmentsPhase,
        VendorProductAssignmentsPhase.failed,
      );
      expect(cubit.state.assignmentsFailure, isA<UnavailableFailure>());
    });

    test('a denial on the companion alone is still a section failure', () async {
      // The companion needs RETAILERS_READ as well as PRODUCTS_READ, so a role
      // holding only the latter reads the product and is refused its Retailers.
      // That split is invisible here: one generic denial, one degraded section.
      repository.assignmentsResult =
          deniedProductRead<List<VendorProductAssignedRetailer>>();
      final VendorProductDetailCubit cubit = build();

      await cubit.open(espressoProductUuid);

      expect(cubit.state.phase, VendorProductDetailPhase.ready);
      expect(cubit.state.assignmentsFailure, isA<DeniedFailure>());
      expect(cubit.state.assignmentsFailure!.props, isEmpty);
    });

    test('the retry re-reads ONLY the companion', () async {
      repository.assignmentsResult =
          unavailableProductRead<List<VendorProductAssignedRetailer>>();
      final VendorProductDetailCubit cubit = build();
      await cubit.open(espressoProductUuid);
      expect(repository.detailCallCount, 1);

      repository.assignmentsResult = null;
      await cubit.retryAssignments();

      // Re-reading the detail to recover a companion would throw away a good
      // answer to fix a different one.
      expect(repository.detailCallCount, 1);
      expect(repository.assignmentsCallCount, 2);
      expect(cubit.state.assignmentsPhase, VendorProductAssignmentsPhase.ready);
      expect(cubit.state.assignments, espressoAssignments);
    });

    test('the retry clears the previous section failure', () async {
      repository.assignmentsResult =
          unavailableProductRead<List<VendorProductAssignedRetailer>>();
      final VendorProductDetailCubit cubit = build();
      await cubit.open(espressoProductUuid);

      repository.assignmentsResult = null;
      await cubit.retryAssignments();

      expect(cubit.state.assignmentsFailure, isNull);
    });

    test('a second retry while one is in flight is suppressed', () async {
      repository.assignmentsResult =
          unavailableProductRead<List<VendorProductAssignedRetailer>>();
      final VendorProductDetailCubit cubit = build();
      await cubit.open(espressoProductUuid);

      repository.assignmentsResult = null;
      repository.manualAssignments = true;
      final Future<void> first = cubit.retryAssignments();
      await cubit.retryAssignments();

      expect(repository.pendingAssignmentCount, 1);

      repository.completeAssignments();
      await first;
    });
  });

  group('the detail read failing', () {
    test('an outage is retryable and the retry re-runs the sequence', () async {
      repository.detailResult = unavailableProductRead<VendorProductDetail?>();
      final VendorProductDetailCubit cubit = build();
      await cubit.open(espressoProductUuid);

      expect(cubit.state.phase, VendorProductDetailPhase.failed);
      expect(cubit.state.failure, isA<UnavailableFailure>());
      // No companion for a product that never loaded.
      expect(repository.assignmentsCallCount, 0);

      repository.detailResult = null;
      await cubit.retryDetail();

      expect(cubit.state.phase, VendorProductDetailPhase.ready);
      expect(repository.detailCallCount, 2);
      expect(repository.assignmentsCallCount, 1);
    });

    test('a denial is a denial, never notFound', () async {
      repository.detailResult = deniedProductRead<VendorProductDetail?>();
      final VendorProductDetailCubit cubit = build();

      await cubit.open(espressoProductUuid);

      expect(cubit.state.phase, VendorProductDetailPhase.failed);
      expect(cubit.state.failure, isA<DeniedFailure>());
      expect(repository.assignmentsCallCount, 0);
    });

    test('retryDetail is a no-op while a detail read is in flight', () async {
      repository.manualDetail = true;
      final VendorProductDetailCubit cubit = build();
      final Future<void> pending = cubit.open(espressoProductUuid);

      await cubit.retryDetail();

      expect(repository.pendingDetailCount, 1);
      expect(repository.detailCallCount, 1);

      repository.completeDetail();
      await pending;
    });

    test('retryDetail with nothing open does nothing', () async {
      final VendorProductDetailCubit cubit = build();

      await cubit.retryDetail();

      expect(repository.detailCallCount, 0);
    });
  });

  group('duplicate loads', () {
    test('opening the same product twice issues one pair of reads', () async {
      final VendorProductDetailCubit cubit = build();

      await cubit.open(espressoProductUuid);
      await cubit.open(espressoProductUuid);

      expect(repository.detailCallCount, 1);
      expect(repository.assignmentsCallCount, 1);
    });

    test('opening a different product does start a fresh load', () async {
      final VendorProductDetailCubit cubit = build();
      await cubit.open(espressoProductUuid);

      await cubit.open(retiredProductUuid);

      expect(repository.requestedDetailIds, <String>[
        espressoProductUuid,
        retiredProductUuid,
      ]);
      expect(cubit.state.detail, retiredDetail);
    });

    test('the same product after a clear does reload', () async {
      final VendorProductDetailCubit cubit = build();
      await cubit.open(espressoProductUuid);

      cubit.clear();
      await cubit.open(espressoProductUuid);

      expect(repository.detailCallCount, 2);
    });
  });

  group('stale responses', () {
    test('an older detail answer cannot overwrite a newer product', () async {
      repository.manualDetail = true;
      final VendorProductDetailCubit cubit = build();

      unawaited(cubit.open(espressoProductUuid));
      unawaited(cubit.open(retiredProductUuid));
      expect(repository.pendingDetailCount, 2);

      // The NEWER request answers first…
      repository.completeDetailAt(1);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.detail, retiredDetail);

      // …and the older one lands afterwards. It must be dropped.
      repository.completeDetailAt(0);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.detail, retiredDetail);
      expect(cubit.state.productId, retiredProductUuid);
    });

    test('a detail answer after clear is discarded', () async {
      repository.manualDetail = true;
      final VendorProductDetailCubit cubit = build();
      unawaited(cubit.open(espressoProductUuid));

      cubit.clear();
      repository.completeDetail();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.detail, isNull);
      expect(cubit.state.phase, VendorProductDetailPhase.initial);
    });

    test('an assignment answer after clear is discarded', () async {
      repository.manualAssignments = true;
      final VendorProductDetailCubit cubit = build();
      unawaited(cubit.open(espressoProductUuid));
      await Future<void>.delayed(Duration.zero);
      expect(repository.pendingAssignmentCount, 1);

      cubit.clear();
      repository.completeAssignments();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.assignments, isEmpty);
      expect(
        cubit.state.assignmentsPhase,
        VendorProductAssignmentsPhase.initial,
      );
    });
  });

  group('session isolation', () {
    test('clear empties every piece of state', () async {
      final VendorProductDetailCubit cubit = build();
      await cubit.open(espressoProductUuid);

      cubit.clear();

      expect(cubit.state.productId, isNull);
      expect(cubit.state.detail, isNull);
      expect(cubit.state.failure, isNull);
      expect(cubit.state.assignments, isEmpty);
      expect(cubit.state.assignmentsFailure, isNull);
      expect(cubit.state.phase, VendorProductDetailPhase.initial);
      expect(
        cubit.state.assignmentsPhase,
        VendorProductAssignmentsPhase.initial,
      );
    });

    test('clear drops the Retailer names that rode on the rows', () async {
      final VendorProductDetailCubit cubit = build();
      await cubit.open(espressoProductUuid);
      expect(cubit.state.assignments, isNotEmpty);

      cubit.clear();

      expect(cubit.state.activeAssignments, isEmpty);
      expect(cubit.state.inactiveAssignments, isEmpty);
      expect(cubit.state.hasUnlinkedAssignments, isFalse);
      expect(cubit.state.hasNoAssignments, isFalse);
    });
  });
}
