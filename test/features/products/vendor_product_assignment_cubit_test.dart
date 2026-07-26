import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_assigned_retailer.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_assignment_action.dart';
import 'package:sale_reward/features/products/domain/repositories/vendor_product_write_result.dart';
import 'package:sale_reward/features/products/presentation/vendor/cubit/vendor_product_assignment_cubit.dart';
import 'package:sale_reward/features/products/presentation/vendor/cubit/vendor_product_write_notice.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_summary.dart';
import 'package:sale_reward/features/retailers/domain/repositories/vendor_retailer_result.dart';

import '../../support/vendor_product_fakes.dart';
import '../../support/vendor_retailer_fakes.dart';

/// The assignment surface's cubit.
///
/// The confirmation dialogs are the screen's job and this cubit knows nothing
/// about them — which is why these tests can exercise both writes without a
/// widget, and why a screen cannot skip a confirmation by calling something
/// cheaper.
void main() {
  late FakeVendorProductRepository products;
  late FakeVendorRetailerRepository retailers;
  late List<VendorProductWriteNotice> written;

  VendorProductAssignmentCubit build() => VendorProductAssignmentCubit(
    products,
    retailers,
    onAssignmentWritten: written.add,
  );

  Future<void> loadCandidates(VendorProductAssignmentCubit cubit) =>
      cubit.loadCandidates(
        productId: espressoProductUuid,
        assignments: compositionAssignments,
      );

  setUp(() {
    products = FakeVendorProductRepository();
    useAssignmentFixtures(products);
    retailers = FakeVendorRetailerRepository();
    retailers.retailersResult =
        VendorRetailerReadSuccess<List<VendorRetailerSummary>>(
          assignmentDirectory,
        );
    written = <VendorProductWriteNotice>[];
  });

  group('the initial state', () {
    test('nothing is loaded, pending or written', () {
      final VendorProductAssignmentCubit cubit = build();

      expect(cubit.state.productId, isNull);
      expect(
        cubit.state.candidatesPhase,
        VendorProductAssignmentCandidatesPhase.initial,
      );
      expect(cubit.state.candidates, isEmpty);
      expect(cubit.state.searchTerm, isEmpty);
      expect(cubit.state.phase, VendorProductAssignmentPhase.idle);
      expect(cubit.state.isBusy, isFalse);
      expect(cubit.state.failure, isNull);
      expect(cubit.state.notice, isNull);
    });

    test('creating it issues no request of any kind', () {
      build();

      expect(retailers.retailersCallCount, 0);
      expect(products.submittedAssignments, isEmpty);
      expect(products.callLog, isEmpty);
    });
  });

  group('loading the candidates', () {
    test('it reads the shipped Retailer directory exactly once', () async {
      await loadCandidates(build());

      expect(retailers.retailersCallCount, 1);
    });

    test('it issues no read of its own for the assignments', () async {
      // The history is passed in from the product screen, so the picker cannot
      // disagree with the list underneath it.
      await loadCandidates(build());

      expect(products.assignmentsCallCount, 0);
      expect(products.detailCallCount, 0);
    });

    test('the composed list is the full directory plus the history', () async {
      final VendorProductAssignmentCubit cubit = build();
      await loadCandidates(cubit);

      expect(
        cubit.state.candidatesPhase,
        VendorProductAssignmentCandidatesPhase.ready,
      );
      expect(cubit.state.candidates.length, 6);
      expect(cubit.state.productId, espressoProductUuid);
    });

    test('a directory failure is a failure, never an empty list', () async {
      retailers.retailersResult =
          const VendorRetailerReadFailure<List<VendorRetailerSummary>>(
            DeniedFailure(),
          );

      final VendorProductAssignmentCubit cubit = build();
      await loadCandidates(cubit);

      expect(
        cubit.state.candidatesPhase,
        VendorProductAssignmentCandidatesPhase.failed,
      );
      expect(cubit.state.candidatesFailure, const DeniedFailure());
      expect(cubit.state.candidates, isEmpty);
      expect(
        cubit.state.hasNoCandidates,
        isFalse,
        reason: '"no Retailers" and "could not read" are opposite claims',
      );
    });

    test('a genuinely empty directory is a real, successful answer', () async {
      retailers.retailersResult =
          const VendorRetailerReadSuccess<List<VendorRetailerSummary>>(
            <VendorRetailerSummary>[],
          );

      final VendorProductAssignmentCubit cubit = build();
      await cubit.loadCandidates(
        productId: unassignedProductUuid,
        assignments: const <VendorProductAssignedRetailer>[],
      );

      expect(cubit.state.hasNoCandidates, isTrue);
    });

    test('a second load while one is in flight is a no-op', () async {
      retailers.manualRetailers = true;
      final VendorProductAssignmentCubit cubit = build();

      unawaited(loadCandidates(cubit));
      unawaited(loadCandidates(cubit));
      await Future<void>.value();

      expect(retailers.retailersCallCount, 1);
    });

    test('reopening for another product starts a fresh list', () async {
      final VendorProductAssignmentCubit cubit = build();
      await loadCandidates(cubit);
      cubit.searchCandidates('lake');

      await cubit.loadCandidates(
        productId: decafProductUuid,
        assignments: const <VendorProductAssignedRetailer>[],
      );

      expect(cubit.state.productId, decafProductUuid);
      expect(
        cubit.state.searchTerm,
        isEmpty,
        reason: 'a search term belongs to one open picker',
      );
      expect(retailers.retailersCallCount, 2);
    });
  });

  group('search', () {
    test('it narrows the visible candidates without dropping any', () async {
      final VendorProductAssignmentCubit cubit = build();
      await loadCandidates(cubit);

      cubit.searchCandidates('lake');

      expect(cubit.state.candidates.length, 6);
      expect(cubit.state.visibleCandidates.length, 1);
      expect(
        cubit.state.visibleCandidates.single.retailerName,
        'Lakeside Market',
      );
    });

    test(
      'a term matching nothing is distinguishable from an empty list',
      () async {
        final VendorProductAssignmentCubit cubit = build();
        await loadCandidates(cubit);

        cubit.searchCandidates('zzzz');

        expect(cubit.state.hasNoMatches, isTrue);
        expect(cubit.state.hasNoCandidates, isFalse);
      },
    );

    test('nothing typed is ever sent anywhere', () async {
      final VendorProductAssignmentCubit cubit = build();
      await loadCandidates(cubit);

      cubit.searchCandidates('lake');

      expect(retailers.retailersCallCount, 1);
      expect(products.callLog, isEmpty);
    });
  });

  group('closing the picker', () {
    test('it drops the candidates and the search term', () async {
      final VendorProductAssignmentCubit cubit = build();
      await loadCandidates(cubit);
      cubit.searchCandidates('lake');

      cubit.closeCandidates();

      expect(cubit.state.candidates, isEmpty);
      expect(cubit.state.searchTerm, isEmpty);
      expect(
        cubit.state.candidatesPhase,
        VendorProductAssignmentCandidatesPhase.initial,
      );
    });

    test(
      'it keeps a write acknowledgement, which belongs to the screen',
      () async {
        final VendorProductAssignmentCubit cubit = build();
        await cubit.apply(
          productId: espressoProductUuid,
          retailerOrganizationId: lakesideOrgId,
          action: VendorProductAssignmentAction.assign,
        );

        cubit.closeCandidates();

        expect(cubit.state.notice, VendorProductWriteNotice.assigned);
      },
    );

    test('a candidate read still in flight cannot repopulate it', () async {
      retailers.manualRetailers = true;
      final VendorProductAssignmentCubit cubit = build();
      unawaited(loadCandidates(cubit));
      await Future<void>.value();

      cubit.closeCandidates();
      retailers.completeRetailers();
      await Future<void>.value();

      expect(cubit.state.candidates, isEmpty);
    });
  });

  group('a confirmed assignment', () {
    test('it sends the two addresses to the assign function', () async {
      final VendorProductAssignmentCubit cubit = build();
      await cubit.apply(
        productId: espressoProductUuid,
        retailerOrganizationId: lakesideOrgId,
        action: VendorProductAssignmentAction.assign,
      );

      expect(products.submittedAssignments.length, 1);
      expect(products.submittedAssignments.single.isWithdrawal, isFalse);
      expect(
        products.submittedAssignments.single.request.productId,
        espressoProductUuid,
      );
      expect(
        products.submittedAssignments.single.request.retailerOrganizationId,
        lakesideOrgId,
      );
    });

    test('it settles as applied and asks for the canonical re-read', () async {
      final VendorProductAssignmentCubit cubit = build();
      await cubit.apply(
        productId: espressoProductUuid,
        retailerOrganizationId: lakesideOrgId,
        action: VendorProductAssignmentAction.assign,
      );

      expect(cubit.state.phase, VendorProductAssignmentPhase.applied);
      expect(written, <VendorProductWriteNotice>[
        VendorProductWriteNotice.assigned,
      ]);
    });

    test('it drops the candidate list it was chosen from', () async {
      final VendorProductAssignmentCubit cubit = build();
      await loadCandidates(cubit);

      await cubit.apply(
        productId: espressoProductUuid,
        retailerOrganizationId: lakesideOrgId,
        action: VendorProductAssignmentAction.assign,
      );

      // The list described eligibility before the transition; a reopened picker
      // must ask again rather than offer a verdict about the pairing that moved.
      expect(cubit.state.candidates, isEmpty);
    });
  });

  group('a confirmed reactivation', () {
    test('it reaches the SAME function as a fresh assignment', () async {
      final VendorProductAssignmentCubit cubit = build();
      await cubit.apply(
        productId: espressoProductUuid,
        retailerOrganizationId: riversideOrgId,
        action: VendorProductAssignmentAction.reactivate,
      );

      expect(
        products.submittedAssignments.single.isWithdrawal,
        isFalse,
        reason: 'creating and reactivating are one operation in SQL',
      );
    });

    test(
      'its acknowledgement is its own, because its consequence is',
      () async {
        final VendorProductAssignmentCubit cubit = build();
        await cubit.apply(
          productId: espressoProductUuid,
          retailerOrganizationId: riversideOrgId,
          action: VendorProductAssignmentAction.reactivate,
        );

        expect(written, <VendorProductWriteNotice>[
          VendorProductWriteNotice.reactivated,
        ]);
      },
    );
  });

  group('a confirmed withdrawal', () {
    test('it sends the two addresses to the withdrawal function', () async {
      final VendorProductAssignmentCubit cubit = build();
      await cubit.apply(
        productId: espressoProductUuid,
        retailerOrganizationId: northwindOrgId,
        action: VendorProductAssignmentAction.withdraw,
      );

      expect(products.submittedAssignments.single.isWithdrawal, isTrue);
      expect(
        products.submittedAssignments.single.request.retailerOrganizationId,
        northwindOrgId,
      );
      expect(written, <VendorProductWriteNotice>[
        VendorProductWriteNotice.withdrawn,
      ]);
    });

    test('it removes nothing locally — the re-read is the authority', () async {
      final VendorProductAssignmentCubit cubit = build();
      await loadCandidates(cubit);
      final int before = cubit.state.candidates.length;

      await cubit.apply(
        productId: espressoProductUuid,
        retailerOrganizationId: northwindOrgId,
        action: VendorProductAssignmentAction.withdraw,
      );

      expect(before, 6);
      // Nothing is patched: the list is dropped whole and re-composed on the
      // next open, from reads the backend answered.
      expect(cubit.state.candidates, isEmpty);
    });
  });

  group('a backend no-op is a success, indistinguishably', () {
    test('assigning an already-active pairing settles as applied', () async {
      // The backend writes no row and no audit entry, and returns normally. A
      // client that tried to tell that apart from a real change would be
      // inventing a distinction the contract deliberately denies.
      final VendorProductAssignmentCubit cubit = build();
      await cubit.apply(
        productId: espressoProductUuid,
        retailerOrganizationId: northwindOrgId,
        action: VendorProductAssignmentAction.assign,
      );

      expect(cubit.state.phase, VendorProductAssignmentPhase.applied);
      expect(written, <VendorProductWriteNotice>[
        VendorProductWriteNotice.assigned,
      ]);
    });
  });

  group('duplicate submission', () {
    test('a second call while one is in flight is refused', () async {
      products.manualAssignmentWrites = true;
      final VendorProductAssignmentCubit cubit = build();

      unawaited(
        cubit.apply(
          productId: espressoProductUuid,
          retailerOrganizationId: lakesideOrgId,
          action: VendorProductAssignmentAction.assign,
        ),
      );
      await Future<void>.value();
      unawaited(
        cubit.apply(
          productId: espressoProductUuid,
          retailerOrganizationId: lakesideOrgId,
          action: VendorProductAssignmentAction.assign,
        ),
      );
      await Future<void>.value();

      expect(products.submittedAssignments.length, 1);
    });

    test('a different pairing is refused too while one is settling', () async {
      products.manualAssignmentWrites = true;
      final VendorProductAssignmentCubit cubit = build();

      unawaited(
        cubit.apply(
          productId: espressoProductUuid,
          retailerOrganizationId: lakesideOrgId,
          action: VendorProductAssignmentAction.assign,
        ),
      );
      await Future<void>.value();
      unawaited(
        cubit.apply(
          productId: espressoProductUuid,
          retailerOrganizationId: northwindOrgId,
          action: VendorProductAssignmentAction.withdraw,
        ),
      );
      await Future<void>.value();

      expect(products.submittedAssignments.length, 1);
    });

    test('only the pairing being written reports as busy', () async {
      products.manualAssignmentWrites = true;
      final VendorProductAssignmentCubit cubit = build();

      unawaited(
        cubit.apply(
          productId: espressoProductUuid,
          retailerOrganizationId: lakesideOrgId,
          action: VendorProductAssignmentAction.assign,
        ),
      );
      await Future<void>.value();

      expect(
        cubit.state.isBusyForPairing(espressoProductUuid, lakesideOrgId),
        isTrue,
      );
      expect(
        cubit.state.isBusyForPairing(espressoProductUuid, northwindOrgId),
        isFalse,
      );
      expect(
        cubit.state.isBusyForPairing(decafProductUuid, lakesideOrgId),
        isFalse,
      );
    });
  });

  group('an unconfirmed answer', () {
    test('it is a success in a quieter voice, and is never retried', () async {
      products.assignResult = const VendorProductWriteUnconfirmed<void>();
      final VendorProductAssignmentCubit cubit = build();

      await cubit.apply(
        productId: espressoProductUuid,
        retailerOrganizationId: lakesideOrgId,
        action: VendorProductAssignmentAction.assign,
      );

      expect(cubit.state.phase, VendorProductAssignmentPhase.applied);
      expect(cubit.state.failure, isNull);
      expect(written, <VendorProductWriteNotice>[
        VendorProductWriteNotice.assignmentUnconfirmed,
      ]);
      expect(products.submittedAssignments.length, 1);
    });

    test('a withdrawal answers the same way', () async {
      products.withdrawResult = const VendorProductWriteUnconfirmed<void>();
      final VendorProductAssignmentCubit cubit = build();

      await cubit.apply(
        productId: espressoProductUuid,
        retailerOrganizationId: northwindOrgId,
        action: VendorProductAssignmentAction.withdraw,
      );

      expect(written, <VendorProductWriteNotice>[
        VendorProductWriteNotice.assignmentUnconfirmed,
      ]);
    });
  });

  group('a refusal', () {
    test('it fails without asking for a re-read', () async {
      products.assignResult = const VendorProductWriteFailure<void>(
        DeniedFailure(),
      );
      final VendorProductAssignmentCubit cubit = build();

      await cubit.apply(
        productId: espressoProductUuid,
        retailerOrganizationId: lakesideOrgId,
        action: VendorProductAssignmentAction.assign,
      );

      expect(cubit.state.phase, VendorProductAssignmentPhase.failed);
      expect(cubit.state.failure, const DeniedFailure());
      expect(
        written,
        isEmpty,
        reason: 'nothing was written, so nothing needs re-reading',
      );
    });

    test('an ineligible product keeps its own outcome', () async {
      products.assignResult = const VendorProductWriteFailure<void>(
        NotReadyFailure(),
      );
      final VendorProductAssignmentCubit cubit = build();

      await cubit.apply(
        productId: espressoProductUuid,
        retailerOrganizationId: lakesideOrgId,
        action: VendorProductAssignmentAction.assign,
      );

      expect(cubit.state.failure, const NotReadyFailure());
    });

    test('the candidate list survives, because it is still correct', () async {
      products.assignResult = const VendorProductWriteFailure<void>(
        DeniedFailure(),
      );
      final VendorProductAssignmentCubit cubit = build();
      await loadCandidates(cubit);

      await cubit.apply(
        productId: espressoProductUuid,
        retailerOrganizationId: lakesideOrgId,
        action: VendorProductAssignmentAction.assign,
      );

      expect(cubit.state.candidates.length, 6);
    });

    test('a failure is reported for its own product only', () async {
      products.assignResult = const VendorProductWriteFailure<void>(
        DeniedFailure(),
      );
      final VendorProductAssignmentCubit cubit = build();

      await cubit.apply(
        productId: espressoProductUuid,
        retailerOrganizationId: lakesideOrgId,
        action: VendorProductAssignmentAction.assign,
      );

      expect(cubit.state.hasFailureFor(espressoProductUuid), isTrue);
      expect(cubit.state.hasFailureFor(decafProductUuid), isFalse);
    });

    test(
      'dismissing it returns the action to rest and keeps the list',
      () async {
        products.assignResult = const VendorProductWriteFailure<void>(
          DeniedFailure(),
        );
        final VendorProductAssignmentCubit cubit = build();
        await loadCandidates(cubit);
        await cubit.apply(
          productId: espressoProductUuid,
          retailerOrganizationId: lakesideOrgId,
          action: VendorProductAssignmentAction.assign,
        );

        cubit.dismissFailure();

        expect(cubit.state.phase, VendorProductAssignmentPhase.idle);
        expect(cubit.state.failure, isNull);
        expect(cubit.state.candidates.length, 6);
      },
    );

    test('dismissing when nothing failed changes nothing', () async {
      final VendorProductAssignmentCubit cubit = build();
      await loadCandidates(cubit);
      final VendorProductAssignmentState before = cubit.state;

      cubit.dismissFailure();

      expect(cubit.state, before);
    });
  });

  group('a stale answer never lands', () {
    test('a write that settles after clear() is dropped', () async {
      products.manualAssignmentWrites = true;
      final VendorProductAssignmentCubit cubit = build();
      unawaited(
        cubit.apply(
          productId: espressoProductUuid,
          retailerOrganizationId: lakesideOrgId,
          action: VendorProductAssignmentAction.assign,
        ),
      );
      await Future<void>.value();

      cubit.clear();
      products.completeAssignment();
      await Future<void>.value();

      expect(cubit.state.phase, VendorProductAssignmentPhase.idle);
      expect(cubit.state.notice, isNull);
      expect(
        written,
        isEmpty,
        reason: 'a dropped answer must not trigger a canonical re-read either',
      );
    });

    test('a withdrawal that settles after clear() is dropped too', () async {
      products.manualAssignmentWrites = true;
      final VendorProductAssignmentCubit cubit = build();
      unawaited(
        cubit.apply(
          productId: espressoProductUuid,
          retailerOrganizationId: northwindOrgId,
          action: VendorProductAssignmentAction.withdraw,
        ),
      );
      await Future<void>.value();

      cubit.clear();
      products.completeAssignment();
      await Future<void>.value();

      expect(cubit.state.notice, isNull);
      expect(written, isEmpty);
    });

    test('a candidate read that lands after clear() is dropped', () async {
      retailers.manualRetailers = true;
      final VendorProductAssignmentCubit cubit = build();
      unawaited(loadCandidates(cubit));
      await Future<void>.value();

      cubit.clear();
      retailers.completeRetailers();
      await Future<void>.value();

      expect(cubit.state.candidates, isEmpty);
      expect(
        cubit.state.candidatesPhase,
        VendorProductAssignmentCandidatesPhase.initial,
      );
    });

    test('a refusal that lands after clear() cannot appear', () async {
      products.manualAssignmentWrites = true;
      final VendorProductAssignmentCubit cubit = build();
      unawaited(
        cubit.apply(
          productId: espressoProductUuid,
          retailerOrganizationId: lakesideOrgId,
          action: VendorProductAssignmentAction.assign,
        ),
      );
      await Future<void>.value();

      cubit.clear();
      products.completeAssignment(
        const VendorProductWriteFailure<void>(DeniedFailure()),
      );
      await Future<void>.value();

      expect(cubit.state.failure, isNull);
      expect(cubit.state.phase, VendorProductAssignmentPhase.idle);
    });
  });

  group('clear', () {
    test('it empties every field', () async {
      final VendorProductAssignmentCubit cubit = build();
      await loadCandidates(cubit);
      cubit.searchCandidates('lake');
      await cubit.apply(
        productId: espressoProductUuid,
        retailerOrganizationId: lakesideOrgId,
        action: VendorProductAssignmentAction.assign,
      );

      cubit.clear();

      expect(cubit.state, const VendorProductAssignmentState());
      expect(cubit.state.candidates, isEmpty);
      expect(cubit.state.searchTerm, isEmpty);
      expect(cubit.state.pendingRetailerOrganizationId, isNull);
      expect(cubit.state.pendingAction, isNull);
      expect(cubit.state.notice, isNull);
      expect(cubit.state.failure, isNull);
      expect(cubit.state.productId, isNull);
    });

    test('clearing twice is harmless', () {
      final VendorProductAssignmentCubit cubit = build()..clear();
      cubit.clear();

      expect(cubit.state, const VendorProductAssignmentState());
    });
  });

  group('an acknowledgement is bound to its product', () {
    test('it is offered for the product it was about, and no other', () async {
      final VendorProductAssignmentCubit cubit = build();
      await cubit.apply(
        productId: espressoProductUuid,
        retailerOrganizationId: lakesideOrgId,
        action: VendorProductAssignmentAction.assign,
      );

      expect(
        cubit.state.noticeFor(espressoProductUuid),
        VendorProductWriteNotice.assigned,
      );
      expect(cubit.state.noticeFor(decafProductUuid), isNull);
    });
  });
}
