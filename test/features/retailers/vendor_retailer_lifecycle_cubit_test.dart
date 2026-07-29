import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_lifecycle_action.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_lifecycle_status.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_manage_capability.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_status.dart';
import 'package:sale_reward/features/retailers/domain/repositories/vendor_retailer_write_result.dart';
import 'package:sale_reward/features/retailers/presentation/vendor/cubit/vendor_retailer_capability_cubit.dart';
import 'package:sale_reward/features/retailers/presentation/vendor/cubit/vendor_retailer_lifecycle_cubit.dart';
import 'package:sale_reward/features/retailers/presentation/vendor/cubit/vendor_retailer_lifecycle_notice.dart';

import '../../support/vendor_retailer_fakes.dart';
import '../../support/vendor_retailer_lifecycle_fakes.dart';

void main() {
  const String vendorOrganizationId = '9f8e7d6c-5b4a-4392-8180-7f6e5d4c3b2a';
  const String otherOrganizationId = '1a2b3c4d-5e6f-4071-8293-a4b5c6d7e8f9';

  final VendorRetailerLifecycleAction deactivateAction =
      VendorRetailerLifecycleAction.forPair(
        retailerStatus: VendorRetailerStatus.active,
        relationshipStatus: VendorRetailerStatus.active,
      )!;
  final VendorRetailerLifecycleAction reactivateAction =
      VendorRetailerLifecycleAction.forPair(
        retailerStatus: VendorRetailerStatus.suspended,
        relationshipStatus: VendorRetailerStatus.suspended,
      )!;

  late FakeVendorRetailerLifecycleRepository repository;
  late List<VendorRetailerLifecycleNotice> notices;

  setUp(() {
    repository = FakeVendorRetailerLifecycleRepository();
    notices = <VendorRetailerLifecycleNotice>[];
  });

  VendorRetailerLifecycleCubit buildCubit() =>
      VendorRetailerLifecycleCubit(repository, onRetailerWritten: notices.add);

  group('the write cubit', () {
    test('62. calls the repository once, with the derived action', () async {
      final VendorRetailerLifecycleCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.apply(northwindRelationshipUuid, deactivateAction);

      expect(repository.writeCallCount, 1);
      expect(
        repository.writes.single.relationshipId,
        northwindRelationshipUuid,
      );
      expect(
        repository.writes.single.status,
        VendorRetailerLifecycleStatus.suspended,
      );
    });

    test('a reactivation sends ACTIVE', () async {
      final VendorRetailerLifecycleCubit cubit = buildCubit();
      addTearDown(cubit.close);
      repository.writeResult = const VendorRetailerWriteSuccess(
        confirmedStatus: VendorRetailerLifecycleStatus.active,
        statusChanged: true,
      );

      await cubit.apply(northwindRelationshipUuid, reactivateAction);

      expect(
        repository.writes.single.status,
        VendorRetailerLifecycleStatus.active,
      );
    });

    test('61. a duplicate submission while busy is ignored', () async {
      final VendorRetailerLifecycleCubit cubit = buildCubit();
      addTearDown(cubit.close);
      repository.manualWrite = true;

      final Future<void> first = cubit.apply(
        northwindRelationshipUuid,
        deactivateAction,
      );
      // A second confirmation while the first is still in flight.
      await cubit.apply(northwindRelationshipUuid, deactivateAction);
      await cubit.apply(northwindRelationshipUuid, deactivateAction);

      expect(repository.writeCallCount, 1);
      expect(cubit.state.isBusyFor(northwindRelationshipUuid), isTrue);

      repository.completeWrite();
      await first;

      expect(repository.writeCallCount, 1);
    });

    test('the busy flag is scoped to the Retailer it is about', () async {
      final VendorRetailerLifecycleCubit cubit = buildCubit();
      addTearDown(cubit.close);
      repository.manualWrite = true;

      final Future<void> pending = cubit.apply(
        northwindRelationshipUuid,
        deactivateAction,
      );

      expect(cubit.state.isBusyFor(northwindRelationshipUuid), isTrue);
      expect(cubit.state.isBusyFor(contosoRelationshipUuid), isFalse);

      repository.completeWrite();
      await pending;
    });

    test('64. a described success notifies the canonical refresh', () async {
      final VendorRetailerLifecycleCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.apply(northwindRelationshipUuid, deactivateAction);

      expect(notices, <VendorRetailerLifecycleNotice>[
        VendorRetailerLifecycleNotice.deactivated,
      ]);
      expect(cubit.state.phase, VendorRetailerLifecyclePhase.applied);
    });

    test(
      'the notice comes from the confirmed status, not the request',
      () async {
        final VendorRetailerLifecycleCubit cubit = buildCubit();
        addTearDown(cubit.close);
        // A deactivation whose response says the pair is ACTIVE.
        repository.writeResult = const VendorRetailerWriteSuccess(
          confirmedStatus: VendorRetailerLifecycleStatus.active,
          statusChanged: true,
        );

        await cubit.apply(northwindRelationshipUuid, deactivateAction);

        expect(notices, <VendorRetailerLifecycleNotice>[
          VendorRetailerLifecycleNotice.reactivated,
        ]);
      },
    );

    test(
      'an idempotent no-op is reported as a no-op, not as a change',
      () async {
        final VendorRetailerLifecycleCubit cubit = buildCubit();
        addTearDown(cubit.close);
        repository.writeResult = const VendorRetailerWriteSuccess(
          confirmedStatus: VendorRetailerLifecycleStatus.suspended,
          statusChanged: false,
        );

        await cubit.apply(northwindRelationshipUuid, deactivateAction);

        expect(notices, <VendorRetailerLifecycleNotice>[
          VendorRetailerLifecycleNotice.alreadyInactive,
        ]);
      },
    );

    test(
      '65. an unconfirmed write also notifies the canonical refresh',
      () async {
        final VendorRetailerLifecycleCubit cubit = buildCubit();
        addTearDown(cubit.close);
        repository.writeResult = const VendorRetailerWriteUnconfirmed();

        await cubit.apply(northwindRelationshipUuid, deactivateAction);

        expect(notices, <VendorRetailerLifecycleNotice>[
          VendorRetailerLifecycleNotice.unconfirmed,
        ]);
        // Reached the same settled phase as a plain success: the transaction
        // committed in both, so this is never presented as a failure.
        expect(cubit.state.phase, VendorRetailerLifecyclePhase.applied);
        expect(cubit.state.failure, isNull);
      },
    );

    test('66. a failure notifies nothing and records no status', () async {
      final VendorRetailerLifecycleCubit cubit = buildCubit();
      addTearDown(cubit.close);
      repository.writeResult = refusedLifecycleWrite(const DeniedFailure());

      await cubit.apply(northwindRelationshipUuid, deactivateAction);

      // Nothing was written, so nothing is re-read and the statuses on screen
      // are still correct. The cubit holds no status of its own to have
      // changed — it never did.
      expect(notices, isEmpty);
      expect(cubit.state.phase, VendorRetailerLifecyclePhase.failed);
      expect(cubit.state.failure, isA<DeniedFailure>());
      expect(cubit.state.hasFailureFor(northwindRelationshipUuid), isTrue);
      expect(cubit.state.hasFailureFor(contosoRelationshipUuid), isFalse);
    });

    test('67. no failure is ever retried automatically', () async {
      final VendorRetailerLifecycleCubit cubit = buildCubit();
      addTearDown(cubit.close);

      for (final Failure failure in <Failure>[
        const DeniedFailure(),
        const InvalidFailure(),
        const NotReadyFailure(),
        const UnavailableFailure(),
        const UnauthenticatedFailure(),
      ]) {
        repository.writes.clear();
        repository.writeResult = refusedLifecycleWrite(failure);
        cubit.dismissFailure();
        await cubit.apply(northwindRelationshipUuid, deactivateAction);
        expect(
          repository.writeCallCount,
          1,
          reason: '$failure must produce exactly one call',
        );
      }
    });

    test('an unconfirmed write is not retried either', () async {
      final VendorRetailerLifecycleCubit cubit = buildCubit();
      addTearDown(cubit.close);
      repository.writeResult = const VendorRetailerWriteUnconfirmed();

      await cubit.apply(northwindRelationshipUuid, deactivateAction);

      expect(repository.writeCallCount, 1);
    });

    test('63. a stale result is dropped after clear', () async {
      final VendorRetailerLifecycleCubit cubit = buildCubit();
      addTearDown(cubit.close);
      repository.manualWrite = true;

      final Future<void> pending = cubit.apply(
        northwindRelationshipUuid,
        deactivateAction,
      );

      // The signed-in person changes while the write is in flight.
      cubit.clear();
      expect(cubit.state, const VendorRetailerLifecycleState());

      repository.completeWrite();
      await pending;

      // The answer landed for somebody who is no longer signed in. It must not
      // repopulate the state, and must not leave a notice over the new
      // session's Retailer.
      expect(cubit.state, const VendorRetailerLifecycleState());
      expect(notices, isEmpty);
    });

    test('89. clear empties every field of the state', () async {
      final VendorRetailerLifecycleCubit cubit = buildCubit();
      addTearDown(cubit.close);
      repository.writeResult = refusedLifecycleWrite(const DeniedFailure());
      await cubit.apply(northwindRelationshipUuid, deactivateAction);

      cubit.clear();

      expect(cubit.state.relationshipId, isNull);
      expect(cubit.state.pending, isNull);
      expect(cubit.state.failure, isNull);
      expect(cubit.state.phase, VendorRetailerLifecyclePhase.idle);
    });

    test('dismissFailure returns to rest and does not re-issue', () async {
      final VendorRetailerLifecycleCubit cubit = buildCubit();
      addTearDown(cubit.close);
      repository.writeResult = refusedLifecycleWrite(const NotReadyFailure());
      await cubit.apply(northwindRelationshipUuid, deactivateAction);

      cubit.dismissFailure();

      expect(cubit.state.phase, VendorRetailerLifecyclePhase.idle);
      expect(repository.writeCallCount, 1);
    });
  });

  group('the capability cubit', () {
    test('59. probes the organization it is given', () async {
      final VendorRetailerCapabilityCubit cubit = VendorRetailerCapabilityCubit(
        repository,
      );
      addTearDown(cubit.close);

      await cubit.load(vendorOrganizationId);

      expect(repository.capabilityOrganizationIds, <String>[
        vendorOrganizationId,
      ]);
      expect(cubit.state.isConfirmed, isTrue);
    });

    test('60. never probes a Retailer organization id', () async {
      final VendorRetailerCapabilityCubit cubit = VendorRetailerCapabilityCubit(
        repository,
      );
      addTearDown(cubit.close);

      await cubit.load(vendorOrganizationId);

      expect(
        repository.capabilityOrganizationIds,
        isNot(contains(northwindOrganizationUuid)),
      );
      expect(
        repository.capabilityOrganizationIds,
        isNot(contains(contosoOrganizationUuid)),
      );
      expect(
        repository.capabilityOrganizationIds,
        isNot(contains(northwindRelationshipUuid)),
      );
    });

    test('55. only a confirmed answer permits the control', () async {
      final VendorRetailerCapabilityCubit cubit = VendorRetailerCapabilityCubit(
        repository,
      );
      addTearDown(cubit.close);
      repository.capabilityResult = VendorRetailerManageCapability.confirmed;

      await cubit.load(vendorOrganizationId);

      expect(cubit.state.isConfirmed, isTrue);
    });

    test('56. a denied answer hides the control', () async {
      final VendorRetailerCapabilityCubit cubit = VendorRetailerCapabilityCubit(
        repository,
      );
      addTearDown(cubit.close);
      repository.capabilityResult = VendorRetailerManageCapability.denied;

      await cubit.load(vendorOrganizationId);

      expect(cubit.state.isConfirmed, isFalse);
      expect(cubit.state.capability, VendorRetailerManageCapability.denied);
    });

    test('57. an unavailable answer hides the control', () async {
      final VendorRetailerCapabilityCubit cubit = VendorRetailerCapabilityCubit(
        repository,
      );
      addTearDown(cubit.close);
      repository.capabilityResult = VendorRetailerManageCapability.unavailable;

      await cubit.load(vendorOrganizationId);

      expect(cubit.state.isConfirmed, isFalse);
      // Still distinguishable from denied — only one of the two is a fact about
      // the caller — even though both hide the control.
      expect(
        cubit.state.capability,
        VendorRetailerManageCapability.unavailable,
      );
    });

    test('58. an unresolved probe fails closed', () {
      final VendorRetailerCapabilityCubit cubit = VendorRetailerCapabilityCubit(
        repository,
      );
      addTearDown(cubit.close);

      // Before anything was asked.
      expect(cubit.state.isConfirmed, isFalse);
      expect(
        cubit.state.capability,
        VendorRetailerManageCapability.unavailable,
      );
    });

    test('the control stays hidden while the probe is in flight', () async {
      final VendorRetailerCapabilityCubit cubit = VendorRetailerCapabilityCubit(
        repository,
      );
      addTearDown(cubit.close);
      repository.manualCapability = true;

      final Future<void> pending = cubit.load(vendorOrganizationId);

      expect(cubit.state.phase, VendorRetailerCapabilityPhase.loading);
      expect(cubit.state.isConfirmed, isFalse);

      repository.completeCapability();
      await pending;

      expect(cubit.state.isConfirmed, isTrue);
    });

    test('a repeat probe for the same organization is skipped', () async {
      final VendorRetailerCapabilityCubit cubit = VendorRetailerCapabilityCubit(
        repository,
      );
      addTearDown(cubit.close);

      await cubit.load(vendorOrganizationId);
      await cubit.load(vendorOrganizationId);
      await cubit.load(vendorOrganizationId);

      expect(repository.capabilityCallCount, 1);
    });

    test('a different organization always re-probes', () async {
      final VendorRetailerCapabilityCubit cubit = VendorRetailerCapabilityCubit(
        repository,
      );
      addTearDown(cubit.close);

      await cubit.load(vendorOrganizationId);
      await cubit.load(otherOrganizationId);

      expect(repository.capabilityOrganizationIds, <String>[
        vendorOrganizationId,
        otherOrganizationId,
      ]);
    });

    test('68. clear empties the capability and re-probes afterwards', () async {
      final VendorRetailerCapabilityCubit cubit = VendorRetailerCapabilityCubit(
        repository,
      );
      addTearDown(cubit.close);
      await cubit.load(vendorOrganizationId);
      expect(cubit.state.isConfirmed, isTrue);

      cubit.clear();

      expect(cubit.state.isConfirmed, isFalse);
      expect(cubit.state.organizationId, isNull);
      expect(
        cubit.state.capability,
        VendorRetailerManageCapability.unavailable,
      );

      await cubit.load(vendorOrganizationId);
      expect(repository.capabilityCallCount, 2);
    });

    test(
      '90. a probe in flight at clear cannot confirm the next session',
      () async {
        final VendorRetailerCapabilityCubit cubit =
            VendorRetailerCapabilityCubit(repository);
        addTearDown(cubit.close);
        repository.manualCapability = true;

        final Future<void> pending = cubit.load(vendorOrganizationId);
        cubit.clear();

        repository.completeCapability(VendorRetailerManageCapability.confirmed);
        await pending;

        // The previous Vendor's answer landed after the switch. It must not
        // confirm a capability for whoever replaced them.
        expect(cubit.state.isConfirmed, isFalse);
        expect(cubit.state.phase, VendorRetailerCapabilityPhase.initial);
      },
    );
  });
}
