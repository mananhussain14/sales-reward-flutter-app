import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_status_change.dart';
import 'package:sale_reward/features/products/domain/repositories/vendor_product_write_result.dart';
import 'package:sale_reward/features/products/presentation/vendor/cubit/vendor_product_status_cubit.dart';
import 'package:sale_reward/features/products/presentation/vendor/cubit/vendor_product_write_notice.dart';

import '../../support/vendor_product_fakes.dart';

/// The activate / deactivate action.
///
/// The confirmation dialog is the screen's job and this cubit knows nothing about
/// it — which is why these tests can exercise the write without a widget, and why a
/// screen cannot skip the confirmation by calling something cheaper.
void main() {
  late FakeVendorProductRepository repository;
  late List<VendorProductWriteNotice> written;

  VendorProductStatusCubit build() =>
      VendorProductStatusCubit(repository, onProductWritten: written.add);

  setUp(() {
    repository = FakeVendorProductRepository();
    written = <VendorProductWriteNotice>[];
  });

  group('the initial state', () {
    test('it is idle, with nothing pending', () {
      final VendorProductStatusCubit cubit = build();

      expect(cubit.state.phase, VendorProductStatusPhase.idle);
      expect(cubit.state.productId, isNull);
      expect(cubit.state.pending, isNull);
      expect(cubit.state.failure, isNull);
      expect(cubit.state.isBusy, isFalse);
    });

    test('nothing is written before an action is applied', () {
      build();
      expect(repository.submittedStatusChanges, isEmpty);
    });
  });

  group('which change a product offers', () {
    test('an ACTIVE product offers deactivation', () {
      expect(
        VendorProductStatusChange.forCurrent(espressoDetail.status),
        VendorProductStatusChange.deactivate,
      );
    });

    test('an INACTIVE product offers activation', () {
      expect(
        VendorProductStatusChange.forCurrent(retiredDetail.status),
        VendorProductStatusChange.activate,
      );
    });
  });

  group('a confirmed deactivation', () {
    test('sends INACTIVE for that product', () async {
      final VendorProductStatusCubit cubit = build();
      await cubit.apply(
        espressoProductUuid,
        VendorProductStatusChange.deactivate,
      );

      expect(repository.submittedStatusChanges.length, 1);
      expect(
        repository.submittedStatusChanges.single.productId,
        espressoProductUuid,
      );
      expect(
        repository.submittedStatusChanges.single.change,
        VendorProductStatusChange.deactivate,
      );
    });

    test('it reaches `applied` and asks for the canonical re-read', () async {
      final VendorProductStatusCubit cubit = build();
      await cubit.apply(
        espressoProductUuid,
        VendorProductStatusChange.deactivate,
      );

      expect(cubit.state.phase, VendorProductStatusPhase.applied);
      expect(cubit.state.failure, isNull);
      expect(written, <VendorProductWriteNotice>[
        VendorProductWriteNotice.statusChanged,
      ]);
    });

    test('no assignment operation is performed', () async {
      // Deactivation does not touch an assignment row, not even its `updated_at`, so
      // nothing here writes, removes or re-reads one.
      final VendorProductStatusCubit cubit = build();
      await cubit.apply(
        espressoProductUuid,
        VendorProductStatusChange.deactivate,
      );

      expect(repository.callLog, <String>['status']);
      expect(repository.requestedAssignmentIds, isEmpty);
    });
  });

  group('a confirmed activation', () {
    test('sends ACTIVE for that product', () async {
      final VendorProductStatusCubit cubit = build();
      await cubit.apply(retiredProductUuid, VendorProductStatusChange.activate);

      expect(
        repository.submittedStatusChanges.single.change,
        VendorProductStatusChange.activate,
      );
      expect(
        repository.submittedStatusChanges.single.productId,
        retiredProductUuid,
      );
      expect(written, <VendorProductWriteNotice>[
        VendorProductWriteNotice.statusChanged,
      ]);
    });

    test('only the two accepted tokens are ever sent', () async {
      final VendorProductStatusCubit cubit = build();
      for (final VendorProductStatusChange change
          in VendorProductStatusChange.values) {
        await cubit.apply(espressoProductUuid, change);
        cubit.dismissFailure();
      }

      expect(
        repository.submittedStatusChanges
            .map(
              (({String productId, VendorProductStatusChange change}) c) =>
                  c.change.code,
            )
            .toSet(),
        <String>{'ACTIVE', 'INACTIVE'},
      );
    });
  });

  group('duplicate confirmation is impossible', () {
    test('a second call while one is in flight is a no-op', () async {
      repository.manualStatus = true;
      final VendorProductStatusCubit cubit = build();

      final Future<void> first = cubit.apply(
        espressoProductUuid,
        VendorProductStatusChange.deactivate,
      );
      expect(cubit.state.isBusy, isTrue);
      expect(cubit.state.isBusyFor(espressoProductUuid), isTrue);

      await cubit.apply(
        espressoProductUuid,
        VendorProductStatusChange.deactivate,
      );
      await cubit.apply(
        espressoProductUuid,
        VendorProductStatusChange.activate,
      );
      expect(repository.pendingStatusCount, 1);

      repository.completeStatus();
      await first;

      expect(repository.submittedStatusChanges.length, 1);
      expect(written.length, 1);
    });

    test('a busy action is busy only for its own product', () async {
      repository.manualStatus = true;
      final VendorProductStatusCubit cubit = build();
      final Future<void> pending = cubit.apply(
        espressoProductUuid,
        VendorProductStatusChange.deactivate,
      );

      expect(cubit.state.isBusyFor(espressoProductUuid), isTrue);
      // A second product's action must not spin for a decision that was not about
      // it.
      expect(cubit.state.isBusyFor(decafProductUuid), isFalse);

      repository.completeStatus();
      await pending;
    });
  });

  group('a failure preserves the previous status', () {
    test('a denial leaves the state failed and nothing re-read', () async {
      repository.statusResult = const VendorProductWriteFailure<void>(
        DeniedFailure(),
      );
      final VendorProductStatusCubit cubit = build();
      await cubit.apply(
        espressoProductUuid,
        VendorProductStatusChange.deactivate,
      );

      expect(cubit.state.phase, VendorProductStatusPhase.failed);
      expect(cubit.state.failure, const DeniedFailure());
      // Nothing was written, so the status already on screen is still correct and no
      // re-read is needed to restore it.
      expect(written, isEmpty);
    });

    test('a transport failure is retryable and never a denial', () async {
      repository.statusResult = const VendorProductWriteFailure<void>(
        UnavailableFailure(),
      );
      final VendorProductStatusCubit cubit = build();
      await cubit.apply(retiredProductUuid, VendorProductStatusChange.activate);

      expect(cubit.state.failure, const UnavailableFailure());
      expect(cubit.state.isBusy, isFalse);
    });

    test('nothing is flipped optimistically at any point', () async {
      // The cubit holds the requested change and never a resulting status: the
      // visible status comes from the re-read product row alone.
      repository.statusResult = const VendorProductWriteFailure<void>(
        UnavailableFailure(),
      );
      final VendorProductStatusCubit cubit = build();
      await cubit.apply(
        espressoProductUuid,
        VendorProductStatusChange.deactivate,
      );

      expect(cubit.state.pending, VendorProductStatusChange.deactivate);
      expect(written, isEmpty);
    });

    test('a failure is attributed to its own product', () async {
      repository.statusResult = const VendorProductWriteFailure<void>(
        DeniedFailure(),
      );
      final VendorProductStatusCubit cubit = build();
      await cubit.apply(
        espressoProductUuid,
        VendorProductStatusChange.deactivate,
      );

      expect(cubit.state.hasFailureFor(espressoProductUuid), isTrue);
      // A refusal that landed for one product must not appear under another.
      expect(cubit.state.hasFailureFor(decafProductUuid), isFalse);
    });

    test('the action may be taken again after a failure', () async {
      repository.statusResult = const VendorProductWriteFailure<void>(
        UnavailableFailure(),
      );
      final VendorProductStatusCubit cubit = build();
      await cubit.apply(
        espressoProductUuid,
        VendorProductStatusChange.deactivate,
      );

      repository.statusResult = null;
      await cubit.apply(
        espressoProductUuid,
        VendorProductStatusChange.deactivate,
      );

      expect(repository.submittedStatusChanges.length, 2);
      expect(cubit.state.phase, VendorProductStatusPhase.applied);
      expect(cubit.state.failure, isNull);
    });

    test('dismissing a failure returns the action to rest', () async {
      repository.statusResult = const VendorProductWriteFailure<void>(
        DeniedFailure(),
      );
      final VendorProductStatusCubit cubit = build();
      await cubit.apply(
        espressoProductUuid,
        VendorProductStatusChange.deactivate,
      );

      cubit.dismissFailure();
      expect(cubit.state, const VendorProductStatusState());
    });
  });

  group('a change that landed with an unreadable answer', () {
    test('it is a success, with its own notice', () async {
      repository.statusResult = const VendorProductWriteUnconfirmed<void>();
      final VendorProductStatusCubit cubit = build();
      await cubit.apply(
        espressoProductUuid,
        VendorProductStatusChange.deactivate,
      );

      // Never a failure: a 2xx means the row and its audit row are committed.
      expect(cubit.state.phase, VendorProductStatusPhase.applied);
      expect(cubit.state.failure, isNull);
      expect(written, <VendorProductWriteNotice>[
        VendorProductWriteNotice.statusUnconfirmed,
      ]);
    });
  });

  group('a stale answer cannot cross a session', () {
    test('a change that lands after clear() is dropped', () async {
      repository.manualStatus = true;
      final VendorProductStatusCubit cubit = build();
      final Future<void> pending = cubit.apply(
        espressoProductUuid,
        VendorProductStatusChange.deactivate,
      );

      cubit.clear();
      expect(cubit.state, const VendorProductStatusState());

      repository.completeStatus();
      await pending;

      // No acknowledgement over the new session's product, and no re-read.
      expect(cubit.state.phase, VendorProductStatusPhase.idle);
      expect(cubit.state.productId, isNull);
      expect(written, isEmpty);
    });

    test('a refusal that lands after clear() is dropped too', () async {
      repository.manualStatus = true;
      final VendorProductStatusCubit cubit = build();
      final Future<void> pending = cubit.apply(
        espressoProductUuid,
        VendorProductStatusChange.deactivate,
      );

      cubit.clear();
      repository.completeStatus(
        const VendorProductWriteFailure<void>(DeniedFailure()),
      );
      await pending;

      expect(cubit.state.phase, VendorProductStatusPhase.idle);
      expect(cubit.state.failure, isNull);
    });
  });

  group('clearing on a session change', () {
    test('a pending decision, its progress and its error all go', () async {
      repository.statusResult = const VendorProductWriteFailure<void>(
        DeniedFailure(),
      );
      final VendorProductStatusCubit cubit = build();
      await cubit.apply(
        espressoProductUuid,
        VendorProductStatusChange.deactivate,
      );
      expect(cubit.state.failure, isNotNull);

      cubit.clear();

      expect(cubit.state.productId, isNull);
      expect(cubit.state.pending, isNull);
      expect(cubit.state.phase, VendorProductStatusPhase.idle);
      expect(cubit.state.failure, isNull);
    });
  });
}
