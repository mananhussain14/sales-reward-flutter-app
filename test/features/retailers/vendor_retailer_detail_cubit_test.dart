import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_detail.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_shop.dart';
import 'package:sale_reward/features/retailers/domain/repositories/vendor_retailer_result.dart';
import 'package:sale_reward/features/retailers/presentation/vendor/cubit/vendor_retailer_detail_cubit.dart';

import '../../support/vendor_retailer_fakes.dart';

void main() {
  late FakeVendorRetailerRepository repository;
  late VendorRetailerDetailCubit cubit;

  setUp(() {
    repository = FakeVendorRetailerRepository();
    cubit = VendorRetailerDetailCubit(repository);
  });

  tearDown(() => cubit.close());

  group('the loading sequence', () {
    test('detail first, then shops — each exactly once', () async {
      await cubit.open(northwindRelationshipUuid);

      expect(repository.requestedDetailIds, <String>[
        northwindRelationshipUuid,
      ]);
      expect(repository.requestedShopIds, <String>[northwindRelationshipUuid]);
      expect(cubit.state.phase, VendorRetailerDetailPhase.ready);
      expect(cubit.state.shopsPhase, VendorRetailerShopsPhase.ready);
      expect(cubit.state.shops, hasLength(2));
    });

    test('the shop read is not issued before the detail returns', () async {
      repository.manualDetail = true;

      final Future<void> opening = cubit.open(northwindRelationshipUuid);

      expect(repository.detailCallCount, 1);
      expect(repository.shopsCallCount, 0);
      expect(cubit.state.phase, VendorRetailerDetailPhase.loading);

      repository.completeDetail();
      await opening;

      expect(repository.shopsCallCount, 1);
    });

    test('both reads are addressed by the same relationship id', () async {
      await cubit.open(northwindRelationshipUuid);

      expect(
        repository.requestedShopIds.single,
        repository.requestedDetailIds.single,
      );
    });

    test('the detail lands before the shops do', () async {
      final List<
        ({VendorRetailerDetailPhase detail, VendorRetailerShopsPhase shops})
      >
      seen =
          <
            ({VendorRetailerDetailPhase detail, VendorRetailerShopsPhase shops})
          >[];
      cubit.stream.listen(
        (VendorRetailerDetailState s) =>
            seen.add((detail: s.phase, shops: s.shopsPhase)),
      );

      await cubit.open(northwindRelationshipUuid);
      await Future<void>.delayed(Duration.zero);

      expect(seen.first.detail, VendorRetailerDetailPhase.loading);
      // Ready with the shops still loading: the header renders before the shop
      // section resolves, rather than the whole screen waiting on both.
      expect(
        seen.any(
          (
            ({VendorRetailerDetailPhase detail, VendorRetailerShopsPhase shops})
            s,
          ) =>
              s.detail == VendorRetailerDetailPhase.ready &&
              s.shops == VendorRetailerShopsPhase.loading,
        ),
        isTrue,
      );
      expect(seen.last.shops, VendorRetailerShopsPhase.ready);
    });
  });

  group('an inaccessible relationship', () {
    setUp(() {
      repository.detailResult =
          const VendorRetailerReadSuccess<VendorRetailerDetail?>(null);
    });

    test('zero rows becomes notFound, and no shop read is issued', () async {
      await cubit.open(foreignRelationshipUuid);

      expect(cubit.state.phase, VendorRetailerDetailPhase.notFound);
      expect(cubit.state.detail, isNull);
      // The critical assertion: an empty shop list would have looked like a
      // Retailer with no shops.
      expect(repository.shopsCallCount, 0);
      expect(cubit.state.shopsPhase, VendorRetailerShopsPhase.initial);
    });

    test('an unknown id and a foreign id reach the identical state', () async {
      await cubit.open(foreignRelationshipUuid);
      final VendorRetailerDetailState foreign = cubit.state;

      cubit.clear();
      await cubit.open(contosoRelationshipUuid);

      expect(cubit.state.phase, foreign.phase);
      expect(cubit.state.failure, foreign.failure);
      expect(cubit.state.detail, foreign.detail);
      expect(cubit.state.shops, foreign.shops);
    });

    test('a malformed id reaches the same state, with no RPC at all', () async {
      // The repository refuses the id shape; the state is indistinguishable
      // from a well-formed id that names nothing readable.
      final FakeVendorRetailerRepository real = FakeVendorRetailerRepository();
      final VendorRetailerDetailCubit fresh = VendorRetailerDetailCubit(real);
      addTearDown(fresh.close);
      real.detailResult =
          const VendorRetailerReadSuccess<VendorRetailerDetail?>(null);

      await fresh.open('not-a-uuid');

      expect(fresh.state.phase, VendorRetailerDetailPhase.notFound);
      expect(real.shopsCallCount, 0);
    });

    test('notFound is not a failure and carries no discriminant', () async {
      await cubit.open(foreignRelationshipUuid);

      expect(cubit.state.failure, isNull);
    });

    test('retryDetail re-reads, and finds the same answer', () async {
      await cubit.open(foreignRelationshipUuid);

      await cubit.retryDetail();

      expect(cubit.state.phase, VendorRetailerDetailPhase.notFound);
      expect(repository.detailCallCount, 2);
      expect(repository.shopsCallCount, 0);
    });
  });

  group('a Retailer with no shops', () {
    test('is distinguishable from an inaccessible one', () async {
      repository.detailResult =
          VendorRetailerReadSuccess<VendorRetailerDetail?>(contosoDetail);
      repository.shopsResult =
          const VendorRetailerReadSuccess<List<VendorRetailerShop>>(
            <VendorRetailerShop>[],
          );

      await cubit.open(contosoRelationshipUuid);

      expect(cubit.state.phase, VendorRetailerDetailPhase.ready);
      expect(cubit.state.shopsPhase, VendorRetailerShopsPhase.ready);
      expect(cubit.state.hasNoShops, isTrue);
      expect(cubit.state.detail!.shopCount, 0);
    });
  });

  group('failures degrade independently', () {
    test('a detail failure is a failure, and stops the sequence', () async {
      repository.detailResult =
          unavailableRetailerRead<VendorRetailerDetail?>();

      await cubit.open(northwindRelationshipUuid);

      expect(cubit.state.phase, VendorRetailerDetailPhase.failed);
      expect(cubit.state.failure, isA<UnavailableFailure>());
      expect(repository.shopsCallCount, 0);
    });

    test('a denial is a denial, never a "not found"', () async {
      repository.detailResult = deniedRetailerRead<VendorRetailerDetail?>();

      await cubit.open(northwindRelationshipUuid);

      expect(cubit.state.phase, VendorRetailerDetailPhase.failed);
      expect(cubit.state.failure, isA<DeniedFailure>());
    });

    test('a shop failure leaves the loaded detail intact', () async {
      repository.shopsResult =
          unavailableRetailerRead<List<VendorRetailerShop>>();

      await cubit.open(northwindRelationshipUuid);

      expect(cubit.state.phase, VendorRetailerDetailPhase.ready);
      expect(cubit.state.detail!.retailerName, 'Northwind Retail');
      expect(cubit.state.shopsPhase, VendorRetailerShopsPhase.failed);
      expect(cubit.state.shopsFailure, isA<UnavailableFailure>());
      expect(cubit.state.shops, isEmpty);
    });

    test('retryShops re-reads only the shops', () async {
      repository.shopsResult =
          unavailableRetailerRead<List<VendorRetailerShop>>();
      await cubit.open(northwindRelationshipUuid);

      repository.shopsResult =
          const VendorRetailerReadSuccess<List<VendorRetailerShop>>(
            <VendorRetailerShop>[marinaShop],
          );
      await cubit.retryShops();

      expect(cubit.state.shopsPhase, VendorRetailerShopsPhase.ready);
      expect(cubit.state.shops, hasLength(1));
      expect(cubit.state.shopsFailure, isNull);
      // One detail read for the whole episode.
      expect(repository.detailCallCount, 1);
      expect(repository.shopsCallCount, 2);
    });

    test('retryShops does nothing when no detail is loaded', () async {
      repository.detailResult =
          const VendorRetailerReadSuccess<VendorRetailerDetail?>(null);
      await cubit.open(foreignRelationshipUuid);

      await cubit.retryShops();

      expect(repository.shopsCallCount, 0);
    });

    test('retryDetail re-runs the whole sequence after an outage', () async {
      repository.detailResult =
          unavailableRetailerRead<VendorRetailerDetail?>();
      await cubit.open(northwindRelationshipUuid);

      repository.detailResult =
          VendorRetailerReadSuccess<VendorRetailerDetail?>(northwindDetail);
      await cubit.retryDetail();

      expect(cubit.state.phase, VendorRetailerDetailPhase.ready);
      expect(cubit.state.shopsPhase, VendorRetailerShopsPhase.ready);
      expect(repository.detailCallCount, 2);
      expect(repository.shopsCallCount, 1);
    });
  });

  group('duplicate loads are impossible', () {
    test('re-opening the same relationship issues nothing', () async {
      await cubit.open(northwindRelationshipUuid);

      await cubit.open(northwindRelationshipUuid);
      await cubit.open(northwindRelationshipUuid);

      expect(repository.detailCallCount, 1);
      expect(repository.shopsCallCount, 1);
    });

    test(
      're-opening while the first read is still in flight is a no-op',
      () async {
        repository.manualDetail = true;

        final Future<void> first = cubit.open(northwindRelationshipUuid);
        final Future<void> second = cubit.open(northwindRelationshipUuid);

        expect(repository.detailCallCount, 1);

        repository.completeDetail();
        await Future.wait(<Future<void>>[first, second]);

        expect(repository.detailCallCount, 1);
      },
    );

    test('a different relationship always starts a fresh read', () async {
      await cubit.open(northwindRelationshipUuid);
      repository.detailResult =
          VendorRetailerReadSuccess<VendorRetailerDetail?>(contosoDetail);

      await cubit.open(contosoRelationshipUuid);

      expect(repository.requestedDetailIds, <String>[
        northwindRelationshipUuid,
        contosoRelationshipUuid,
      ]);
      expect(cubit.state.detail!.retailerName, 'Contoso Stores');
    });

    test('retryDetail is dropped while a read is in flight', () async {
      repository.manualDetail = true;
      final Future<void> opening = cubit.open(northwindRelationshipUuid);

      await cubit.retryDetail();
      expect(repository.detailCallCount, 1);

      repository.completeDetail();
      await opening;
    });

    test('a stale answer cannot overwrite a newer one', () async {
      // The classic race: open A, open B, then let A's response land last.
      repository.manualDetail = true;

      final Future<void> first = cubit.open(northwindRelationshipUuid);
      cubit.clear();
      final Future<void> second = cubit.open(contosoRelationshipUuid);

      expect(repository.pendingDetailCount, 2);

      // B answers, then the stale A answers.
      repository.completeDetail(
        VendorRetailerReadSuccess<VendorRetailerDetail?>(northwindDetail),
      );
      await first;
      repository.completeDetail(
        VendorRetailerReadSuccess<VendorRetailerDetail?>(contosoDetail),
      );
      await second;

      // The state belongs to the relationship that was opened last.
      expect(cubit.state.relationshipId, contosoRelationshipUuid);
      expect(cubit.state.detail!.retailerName, 'Contoso Stores');
    });
  });

  group('private data is cleared on a session change', () {
    test('clear empties the detail, the shops and the open id', () async {
      await cubit.open(northwindRelationshipUuid);

      cubit.clear();

      expect(cubit.state.relationshipId, isNull);
      expect(cubit.state.detail, isNull);
      expect(cubit.state.shops, isEmpty);
      expect(cubit.state.phase, VendorRetailerDetailPhase.initial);
      expect(cubit.state.shopsPhase, VendorRetailerShopsPhase.initial);
      expect(cubit.state.failure, isNull);
      expect(cubit.state.shopsFailure, isNull);
    });

    test('an in-flight read cannot repopulate a cleared state', () async {
      repository.manualDetail = true;
      final Future<void> pending = cubit.open(northwindRelationshipUuid);

      cubit.clear();
      repository.completeDetail();
      await pending;

      expect(cubit.state.detail, isNull);
      expect(cubit.state.phase, VendorRetailerDetailPhase.initial);
      // And no shop read was chased for the previous person's Retailer.
      expect(repository.shopsCallCount, 0);
    });

    test('the same relationship reloads after a clear', () async {
      await cubit.open(northwindRelationshipUuid);
      cubit.clear();

      await cubit.open(northwindRelationshipUuid);

      expect(repository.detailCallCount, 2);
      expect(cubit.state.phase, VendorRetailerDetailPhase.ready);
    });

    test('a read that lands after close is dropped', () async {
      repository.manualDetail = true;
      final Future<void> pending = cubit.open(northwindRelationshipUuid);

      await cubit.close();
      repository.completeDetail();
      await pending;

      expect(repository.shopsCallCount, 0);
    });
  });
}
