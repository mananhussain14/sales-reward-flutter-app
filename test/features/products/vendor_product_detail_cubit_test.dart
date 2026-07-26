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
import 'package:sale_reward/features/products/presentation/vendor/cubit/vendor_product_write_notice.dart';

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
            writes: unusedVendorProductWrites(),
            assignments: unusedVendorProductAssignments(),
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
            writes: unusedVendorProductWrites(),
            assignments: unusedVendorProductAssignments(),
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
            writes: unusedVendorProductWrites(),
            assignments: unusedVendorProductAssignments(),
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

  group('the canonical read after a write', () {
    test(
      'openCreated loads the product and remembers that it was created',
      () async {
        final VendorProductDetailCubit cubit = build();

        await cubit.openCreated(createdProductUuid);

        expect(cubit.state.phase, VendorProductDetailPhase.ready);
        expect(cubit.state.detail, createdDetail);
        expect(cubit.state.currentNotice, VendorProductWriteNotice.created);
        // The canonical sequence, unchanged: detail first, then the companion.
        expect(repository.callLog, <String>['detail', 'assignments']);
      },
    );

    test('openCreated always starts a fresh load', () async {
      // A create always names a product this cubit has never held, so idempotence
      // would be wrong here.
      final VendorProductDetailCubit cubit = build();
      await cubit.openCreated(createdProductUuid);
      await cubit.openCreated(createdProductUuid);

      expect(repository.requestedDetailIds.length, 2);
    });

    test('the created notice survives a failed canonical read', () async {
      // The case the notice exists for: the product WAS created, and only the read
      // of it did not answer.
      repository.detailResult = unavailableProductRead();
      final VendorProductDetailCubit cubit = build();

      await cubit.openCreated(createdProductUuid);

      expect(cubit.state.phase, VendorProductDetailPhase.failed);
      expect(cubit.state.currentNotice, VendorProductWriteNotice.created);
    });

    test('the notice is dropped when a different product is opened', () async {
      final VendorProductDetailCubit cubit = build();
      await cubit.openCreated(createdProductUuid);
      expect(cubit.state.currentNotice, VendorProductWriteNotice.created);

      await cubit.open(espressoProductUuid);

      expect(cubit.state.currentNotice, isNull);
      expect(cubit.state.notice, isNull);
    });

    test('a notice never outlives its subject', () async {
      // Keyed to a product id, so an acknowledgement can never start describing
      // whatever the reader opened next.
      final VendorProductDetailCubit cubit = build();
      await cubit.openCreated(createdProductUuid);
      await cubit.open(espressoProductUuid);
      expect(cubit.state.currentNotice, isNull);
    });

    test(
      'refreshDetail replaces the row in place, keeping it visible',
      () async {
        final VendorProductDetailCubit cubit = build();
        await cubit.open(espressoProductUuid);
        expect(repository.callLog, <String>['detail', 'assignments']);

        // The product as the backend now reports it — a real change would arrive
        // exactly this way.
        final VendorProductDetail renamed = VendorProductDetail(
          productId: espressoProductUuid,
          productCode: 'ESP-1000',
          barcode: null,
          productName: 'Espresso Blend 1kg (renamed)',
          brand: null,
          description: null,
          status: VendorProductStatus.inactive,
          assignmentCount: 3,
          activeAssignmentCount: 2,
          createdAt: espressoCreatedAt,
          updatedAt: espressoUpdatedAt,
        );
        repository.knownDetails = <String, VendorProductDetail>{
          espressoProductUuid: renamed,
        };

        await cubit.refreshDetail(notice: VendorProductWriteNotice.updated);

        expect(cubit.state.phase, VendorProductDetailPhase.ready);
        expect(cubit.state.detail, renamed);
        expect(cubit.state.currentNotice, VendorProductWriteNotice.updated);
        expect(cubit.state.isRefreshing, isFalse);
        expect(cubit.state.refreshFailure, isNull);
      },
    );

    test('the assignment rows are NOT re-read', () async {
      // A product create, edit or status change touches no assignment row — not even
      // its `updated_at` — so a second companion call would spend a round trip to
      // learn nothing, and would replace a good answer for unrelated reasons.
      final VendorProductDetailCubit cubit = build();
      await cubit.open(espressoProductUuid);
      final int before = repository.assignmentsCallCount;
      final List<VendorProductAssignedRetailer> rows = cubit.state.assignments;

      await cubit.refreshDetail(notice: VendorProductWriteNotice.statusChanged);

      expect(repository.assignmentsCallCount, before);
      expect(cubit.state.assignments, same(rows));
      expect(repository.callLog, <String>['detail', 'assignments', 'detail']);
    });

    test('both counts still come from the re-read product row', () async {
      final VendorProductDetailCubit cubit = build();
      await cubit.open(espressoProductUuid);

      await cubit.refreshDetail(notice: VendorProductWriteNotice.updated);

      expect(cubit.state.detail!.assignmentCount, 3);
      expect(cubit.state.detail!.activeAssignmentCount, 2);
      // Nothing was computed from the loaded list.
      expect(cubit.state.assignments.length, 3);
    });

    test('a failed refresh keeps the product and records the failure', () async {
      final VendorProductDetailCubit cubit = build();
      await cubit.open(espressoProductUuid);
      final VendorProductDetail before = cubit.state.detail!;

      repository.detailResult = unavailableProductRead();
      await cubit.refreshDetail(notice: VendorProductWriteNotice.updated);

      // The write stands: only the picture of it is stale.
      expect(cubit.state.phase, VendorProductDetailPhase.ready);
      expect(cubit.state.detail, before);
      expect(cubit.state.refreshFailure, const UnavailableFailure());
      expect(cubit.state.isRefreshing, isFalse);
      // And the acknowledgement is still shown, because the change did happen.
      expect(cubit.state.currentNotice, VendorProductWriteNotice.updated);
    });

    test('a denied refresh is never presented as a failed write', () async {
      final VendorProductDetailCubit cubit = build();
      await cubit.open(espressoProductUuid);

      repository.detailResult = deniedProductRead();
      await cubit.refreshDetail(notice: VendorProductWriteNotice.statusChanged);

      expect(cubit.state.phase, VendorProductDetailPhase.ready);
      expect(cubit.state.detail, isNotNull);
      expect(cubit.state.refreshFailure, const DeniedFailure());
      expect(cubit.state.currentNotice, VendorProductWriteNotice.statusChanged);
    });

    test(
      'a Reload keeps the existing notice and clears the stale warning',
      () async {
        final VendorProductDetailCubit cubit = build();
        await cubit.open(espressoProductUuid);

        repository.detailResult = unavailableProductRead();
        await cubit.refreshDetail(notice: VendorProductWriteNotice.updated);
        expect(cubit.state.refreshFailure, isNotNull);

        repository.detailResult = null;
        await cubit.refreshDetail();

        expect(cubit.state.refreshFailure, isNull);
        expect(cubit.state.currentNotice, VendorProductWriteNotice.updated);
        expect(cubit.state.detail, espressoDetail);
      },
    );

    test('a repeated Reload while one is running is a no-op', () async {
      repository.manualDetail = true;
      final VendorProductDetailCubit cubit = build();
      final Future<void> opening = cubit.open(espressoProductUuid);
      repository.completeDetail();
      await opening;

      final Future<void> first = cubit.refreshDetail(
        notice: VendorProductWriteNotice.updated,
      );
      expect(cubit.state.isRefreshing, isTrue);

      await cubit.refreshDetail();
      await cubit.refreshDetail();
      expect(repository.pendingDetailCount, 1);

      repository.completeDetail();
      await first;
      expect(cubit.state.isRefreshing, isFalse);
    });

    test('a refresh with nothing open is a no-op', () async {
      final VendorProductDetailCubit cubit = build();
      await cubit.refreshDetail(notice: VendorProductWriteNotice.updated);

      expect(repository.callLog, isEmpty);
      expect(cubit.state.currentNotice, isNull);
    });

    test('a refresh over an unaddressable product is a no-op', () async {
      // Nothing on screen to refresh, and no notice to attach to it.
      final VendorProductDetailCubit cubit = build();
      await cubit.open(unknownProductUuid);
      expect(cubit.state.phase, VendorProductDetailPhase.notFound);

      await cubit.refreshDetail(notice: VendorProductWriteNotice.updated);
      expect(repository.requestedDetailIds.length, 1);
    });

    test('a product that stopped being addressable drops the stale row', () async {
      // No product write can cause this, so it is somebody else's change or a
      // session that is no longer what it was — and the one safe answer is the
      // non-leaking state a foreign id produces.
      final VendorProductDetailCubit cubit = build();
      await cubit.open(espressoProductUuid);

      repository.detailResult = const ReadSuccess<VendorProductDetail?>(null);
      await cubit.refreshDetail(notice: VendorProductWriteNotice.updated);

      expect(cubit.state.phase, VendorProductDetailPhase.notFound);
      expect(cubit.state.detail, isNull);
      // Acknowledging a change to a product that is no longer there would be the
      // least useful sentence available.
      expect(cubit.state.currentNotice, isNull);
    });

    test('a refresh that lands after clear() is dropped', () async {
      repository.manualDetail = true;
      final VendorProductDetailCubit cubit = build();
      final Future<void> opening = cubit.open(espressoProductUuid);
      repository.completeDetail();
      await opening;

      final Future<void> pending = cubit.refreshDetail(
        notice: VendorProductWriteNotice.updated,
      );
      cubit.clear();

      repository.completeDetail();
      await pending;

      // The previous Vendor's product, and the acknowledgement of their write, are
      // both gone.
      expect(cubit.state, const VendorProductDetailState());
      expect(cubit.state.currentNotice, isNull);
      expect(cubit.state.refreshFailure, isNull);
    });

    test(
      'clear() drops the notice, the progress and the stale warning',
      () async {
        final VendorProductDetailCubit cubit = build();
        await cubit.openCreated(createdProductUuid);
        repository.detailResult = unavailableProductRead();
        await cubit.refreshDetail(notice: VendorProductWriteNotice.updated);

        cubit.clear();

        expect(cubit.state.notice, isNull);
        expect(cubit.state.noticeProductId, isNull);
        expect(cubit.state.isRefreshing, isFalse);
        expect(cubit.state.refreshFailure, isNull);
      },
    );

    test('a full retry from a failed read clears the notice', () async {
      // retryDetail re-runs the whole sequence, which is a fresh load rather than a
      // read-after-write, so it carries no acknowledgement.
      repository.detailResult = unavailableProductRead();
      final VendorProductDetailCubit cubit = build();
      await cubit.openCreated(createdProductUuid);
      expect(cubit.state.currentNotice, VendorProductWriteNotice.created);

      repository.detailResult = null;
      await cubit.retryDetail();

      expect(cubit.state.phase, VendorProductDetailPhase.ready);
      expect(cubit.state.currentNotice, isNull);
    });
  });

  /// The canonical read after an **assignment** write.
  ///
  /// Different from the product-record refresh in exactly one way, and it is the
  /// way that matters: an assign or a withdrawal moves values in *both* reads —
  /// the history gains or changes a row, and both counts are recomputed by the
  /// detail statement — so both are re-read, and applied together.
  group('the canonical read after an assignment write', () {
    test('it re-reads the product row AND the assignment history', () async {
      final VendorProductDetailCubit cubit = build();
      await cubit.open(espressoProductUuid);
      expect(repository.callLog, <String>['detail', 'assignments']);

      await cubit.refreshAfterAssignment(
        notice: VendorProductWriteNotice.withdrawn,
      );

      expect(repository.callLog, <String>[
        'detail',
        'assignments',
        'detail',
        'assignments',
      ]);
      expect(cubit.state.currentNotice, VendorProductWriteNotice.withdrawn);
    });

    test(
      'the detail read goes first, and the companion only after a row',
      () async {
        // The same load-bearing order as the initial read: an empty assignment
        // list means "never assigned" only once the detail read has confirmed the
        // id is still addressable.
        final VendorProductDetailCubit cubit = build();
        await cubit.open(espressoProductUuid);
        repository.detailResult = const ReadSuccess<VendorProductDetail?>(null);
        final int assignmentsBefore = repository.assignmentsCallCount;

        await cubit.refreshAfterAssignment(
          notice: VendorProductWriteNotice.withdrawn,
        );

        expect(cubit.state.phase, VendorProductDetailPhase.notFound);
        expect(
          repository.assignmentsCallCount,
          assignmentsBefore,
          reason:
              'a product that is no longer addressable has no assignments to '
              'read',
        );
      },
    );

    test('the product and its history land in ONE emission', () async {
      final VendorProductDetailCubit cubit = build();
      await cubit.open(espressoProductUuid);

      final List<VendorProductDetailState> emitted =
          <VendorProductDetailState>[];
      final StreamSubscription<VendorProductDetailState> subscription = cubit
          .stream
          .listen(emitted.add);
      addTearDown(subscription.cancel);

      await cubit.refreshAfterAssignment(
        notice: VendorProductWriteNotice.assigned,
      );
      await Future<void>.value();

      // One emission to start the refresh, and one to finish it. A count and the
      // rows it describes are never rendered a frame apart.
      expect(emitted.length, 2);
      expect(emitted.first.isRefreshing, isTrue);
      expect(emitted.last.isRefreshing, isFalse);
      expect(
        emitted.last.assignmentsPhase,
        VendorProductAssignmentsPhase.ready,
      );
    });

    test('nothing is inserted, removed or re-statused locally', () async {
      final VendorProductDetailCubit cubit = build();
      await cubit.open(espressoProductUuid);

      await cubit.refreshAfterAssignment(
        notice: VendorProductWriteNotice.withdrawn,
      );

      // The fake does not simulate storage, so the re-read returns the same
      // three rows and the same counts. A client that had patched anything would
      // now disagree with what it just read back.
      expect(cubit.state.assignments, espressoAssignments);
      expect(cubit.state.detail!.assignmentCount, 3);
      expect(cubit.state.detail!.activeAssignmentCount, 2);
    });

    test(
      'a failed detail re-read keeps BOTH the product and the rows',
      () async {
        final VendorProductDetailCubit cubit = build();
        await cubit.open(espressoProductUuid);
        repository.detailResult = unavailableProductRead();

        await cubit.refreshAfterAssignment(
          notice: VendorProductWriteNotice.withdrawn,
        );

        expect(cubit.state.phase, VendorProductDetailPhase.ready);
        expect(cubit.state.detail, espressoDetail);
        expect(cubit.state.assignments, espressoAssignments);
        expect(cubit.state.refreshFailure, const UnavailableFailure());
        expect(
          cubit.state.currentNotice,
          VendorProductWriteNotice.withdrawn,
          reason: 'the mutation committed; only the picture of it is stale',
        );
      },
    );

    test(
      'a failed HISTORY re-read is a partial success, not a failed write',
      () async {
        final VendorProductDetailCubit cubit = build();
        await cubit.open(espressoProductUuid);
        repository.assignmentsResult = unavailableProductRead();

        await cubit.refreshAfterAssignment(
          notice: VendorProductWriteNotice.assigned,
        );

        // The fresh product row is kept — it answered — and so are the previous
        // rows, because replacing a real history with an empty one would make
        // ending one assignment look like erasing every assignment.
        expect(cubit.state.detail, espressoDetail);
        expect(cubit.state.assignments, espressoAssignments);
        expect(
          cubit.state.assignmentsPhase,
          VendorProductAssignmentsPhase.ready,
          reason:
              'the section is not degraded; the whole screen is marked stale',
        );
        expect(cubit.state.refreshFailure, const UnavailableFailure());
        expect(cubit.state.currentNotice, VendorProductWriteNotice.assigned);
      },
    );

    test('the refresh scope is recorded, so a Reload repeats it', () async {
      final VendorProductDetailCubit cubit = build();
      await cubit.open(espressoProductUuid);

      await cubit.refreshDetail(notice: VendorProductWriteNotice.updated);
      expect(cubit.state.refreshIncludesAssignments, isFalse);

      await cubit.refreshAfterAssignment(
        notice: VendorProductWriteNotice.withdrawn,
      );
      expect(cubit.state.refreshIncludesAssignments, isTrue);
    });

    test('reloadCanonical repeats the assignment scope', () async {
      final VendorProductDetailCubit cubit = build();
      await cubit.open(espressoProductUuid);
      await cubit.refreshAfterAssignment(
        notice: VendorProductWriteNotice.withdrawn,
      );
      repository.callLog.clear();

      await cubit.reloadCanonical();

      expect(repository.callLog, <String>['detail', 'assignments']);
    });

    test('reloadCanonical repeats the product-only scope', () async {
      final VendorProductDetailCubit cubit = build();
      await cubit.open(espressoProductUuid);
      await cubit.refreshDetail(notice: VendorProductWriteNotice.updated);
      repository.callLog.clear();

      await cubit.reloadCanonical();

      expect(repository.callLog, <String>['detail']);
    });

    test('a reload keeps the acknowledgement already showing', () async {
      final VendorProductDetailCubit cubit = build();
      await cubit.open(espressoProductUuid);
      await cubit.refreshAfterAssignment(
        notice: VendorProductWriteNotice.reactivated,
      );

      await cubit.reloadCanonical();

      expect(cubit.state.currentNotice, VendorProductWriteNotice.reactivated);
    });

    test('a second refresh while one runs is refused', () async {
      repository.manualDetail = true;
      final VendorProductDetailCubit cubit = build();
      repository.manualDetail = false;
      await cubit.open(espressoProductUuid);
      repository.manualDetail = true;

      unawaited(
        cubit.refreshAfterAssignment(
          notice: VendorProductWriteNotice.withdrawn,
        ),
      );
      await Future<void>.value();
      final int pending = repository.pendingDetailCount;

      unawaited(
        cubit.refreshAfterAssignment(notice: VendorProductWriteNotice.assigned),
      );
      await Future<void>.value();

      expect(repository.pendingDetailCount, pending);
    });

    test('a stale assignment refresh cannot land after a clear', () async {
      repository.manualAssignments = true;
      final VendorProductDetailCubit cubit = build();
      repository.manualAssignments = false;
      await cubit.open(espressoProductUuid);
      repository.manualAssignments = true;

      unawaited(
        cubit.refreshAfterAssignment(
          notice: VendorProductWriteNotice.withdrawn,
        ),
      );
      await Future<void>.value();
      await Future<void>.value();

      cubit.clear();
      repository.completeAssignments();
      await Future<void>.value();

      expect(cubit.state, const VendorProductDetailState());
    });

    test('it does nothing when nothing is open', () async {
      final VendorProductDetailCubit cubit = build();

      await cubit.refreshAfterAssignment(
        notice: VendorProductWriteNotice.withdrawn,
      );

      expect(repository.callLog, isEmpty);
      expect(cubit.state.currentNotice, isNull);
    });
  });
}
