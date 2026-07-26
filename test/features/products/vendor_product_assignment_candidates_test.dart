import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_assigned_retailer.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_assignment_candidate.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_assignment_status.dart';
import 'package:sale_reward/features/retailers/domain/entities/retailer_owner_state.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_status.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_summary.dart';

import '../../support/vendor_product_fakes.dart';

/// Composing the assign surface's choices from the two trusted reads.
///
/// The composition is a **hint**, never an authorization: the backend re-decides
/// every one of these verdicts inside the write, under row locks, and may refuse
/// a Retailer this function called assignable. What is asserted here is that the
/// hint mirrors the deployed gate rather than inventing a rule, that no row is
/// silently dropped, and that the order is total.
void main() {
  List<VendorProductAssignmentCandidate> compose({
    List<VendorRetailerSummary>? retailers,
    List<VendorProductAssignedRetailer>? assignments,
  }) => VendorProductAssignmentCandidate.compose(
    retailers: retailers ?? assignmentDirectory,
    assignments: assignments ?? compositionAssignments,
  );

  VendorProductAssignmentCandidate byName(
    List<VendorProductAssignmentCandidate> candidates,
    String name,
  ) => candidates.firstWhere(
    (VendorProductAssignmentCandidate c) => c.retailerName == name,
  );

  VendorRetailerSummary directoryRow({
    required String relationshipId,
    required String retailerOrganizationId,
    required String retailerName,
    VendorRetailerStatus retailerStatus = VendorRetailerStatus.active,
    VendorRetailerStatus relationshipStatus = VendorRetailerStatus.active,
  }) => VendorRetailerSummary(
    relationshipId: relationshipId,
    retailerOrganizationId: retailerOrganizationId,
    retailerName: retailerName,
    retailerStatus: retailerStatus,
    relationshipStatus: relationshipStatus,
    relationshipCreatedAt: DateTime.utc(2026),
    shopCount: 0,
    activeShopCount: 0,
    ownerState: RetailerOwnerState.active,
  );

  group('the five states', () {
    test('a never-assigned active Retailer is assignable', () {
      final VendorProductAssignmentCandidate lakeside = byName(
        compose(),
        'Lakeside Market',
      );

      expect(lakeside.state, VendorProductAssignmentCandidateState.assignable);
      expect(lakeside.isActionable, isTrue);
      expect(lakeside.hasHistory, isFalse);
      expect(lakeside.assignmentStatus, isNull);
      expect(lakeside.assignedAt, isNull);
    });

    test('an active assignment is already assigned, and offers nothing', () {
      final VendorProductAssignmentCandidate northwind = byName(
        compose(),
        'Northwind Retail',
      );

      expect(
        northwind.state,
        VendorProductAssignmentCandidateState.alreadyAssigned,
      );
      expect(northwind.isActionable, isFalse);
      expect(northwind.assignmentStatus, VendorProductAssignmentStatus.active);
    });

    test('an inactive assignment to an eligible Retailer is reactivatable', () {
      final VendorProductAssignmentCandidate riverside = byName(
        compose(),
        'Riverside Foods',
      );

      expect(
        riverside.state,
        VendorProductAssignmentCandidateState.reactivatable,
      );
      expect(riverside.isActionable, isTrue);
      expect(riverside.hasHistory, isTrue);
      expect(
        riverside.assignmentStatus,
        VendorProductAssignmentStatus.inactive,
      );
      // The previous activation start, carried so the row can show it. Never
      // spoken as a first-assignment date.
      expect(riverside.assignedAt, DateTime.utc(2026, 3, 2, 9));
    });

    test(
      'a suspended relationship makes an inactive assignment ineligible',
      () {
        final VendorProductAssignmentCandidate summit = byName(
          compose(),
          'Summit Stores',
        );

        expect(summit.state, VendorProductAssignmentCandidateState.ineligible);
        expect(summit.isActionable, isFalse);
        // The organization itself is fine; the relationship is not. Both are
        // reported exactly as read, and neither is derived from the other.
        expect(summit.retailerStatus, VendorRetailerStatus.active);
        expect(summit.relationshipStatus, VendorRetailerStatus.suspended);
      },
    );

    test('an assignment with no relationship row is its own state', () {
      final VendorProductAssignmentCandidate oldTown = byName(
        compose(),
        'Old Town Grocers',
      );

      expect(
        oldTown.state,
        VendorProductAssignmentCandidateState.relationshipUnavailable,
      );
      expect(oldTown.isActionable, isFalse);
      expect(oldTown.relationshipStatus, isNull);
      // The row is kept, not dropped: the picker must not disagree with the
      // history below it about which Retailers this product has reached.
      expect(oldTown.hasHistory, isTrue);
    });
  });

  group('an active assignment outranks every other consideration', () {
    test('a suspended Retailer with an active assignment reads as assigned', () {
      final VendorProductAssignmentCandidate harbour = byName(
        compose(),
        'Harbour Provisions',
      );

      // Both statuses are SUSPENDED and the assignment is nevertheless ACTIVE —
      // a real, reachable state. Offering an assignment here would be offering
      // to spend a call on a backend no-op.
      expect(
        harbour.state,
        VendorProductAssignmentCandidateState.alreadyAssigned,
      );
      expect(harbour.retailerStatus, VendorRetailerStatus.suspended);
      expect(harbour.relationshipStatus, VendorRetailerStatus.suspended);
    });
  });

  group('eligibility is a positive test in both halves', () {
    test('a suspended organization is ineligible even when related', () {
      final List<VendorProductAssignmentCandidate> composed = compose(
        retailers: <VendorRetailerSummary>[
          directoryRow(
            relationshipId: lakesideRelationshipId,
            retailerOrganizationId: lakesideOrgId,
            retailerName: 'Lakeside Market',
            retailerStatus: VendorRetailerStatus.suspended,
          ),
        ],
        assignments: const <VendorProductAssignedRetailer>[],
      );

      expect(
        composed.single.state,
        VendorProductAssignmentCandidateState.ineligible,
      );
    });

    test('a deactivated organization is ineligible', () {
      final List<VendorProductAssignmentCandidate> composed = compose(
        retailers: <VendorRetailerSummary>[
          directoryRow(
            relationshipId: lakesideRelationshipId,
            retailerOrganizationId: lakesideOrgId,
            retailerName: 'Lakeside Market',
            retailerStatus: VendorRetailerStatus.deactivated,
          ),
        ],
        assignments: const <VendorProductAssignedRetailer>[],
      );

      expect(
        composed.single.state,
        VendorProductAssignmentCandidateState.ineligible,
      );
    });

    test('an unrecognised status never reaches eligible', () {
      // Forward compatibility must fail closed: a token this build does not know
      // is not "probably active".
      final List<VendorProductAssignmentCandidate> composed = compose(
        retailers: <VendorRetailerSummary>[
          directoryRow(
            relationshipId: lakesideRelationshipId,
            retailerOrganizationId: lakesideOrgId,
            retailerName: 'Lakeside Market',
            relationshipStatus: VendorRetailerStatus.unknown,
          ),
        ],
        assignments: const <VendorProductAssignedRetailer>[],
      );

      expect(
        composed.single.state,
        VendorProductAssignmentCandidateState.ineligible,
      );
    });

    test('an unrecognised ASSIGNMENT status offers no transition', () {
      final List<VendorProductAssignmentCandidate> composed = compose(
        retailers: <VendorRetailerSummary>[
          directoryRow(
            relationshipId: lakesideRelationshipId,
            retailerOrganizationId: lakesideOrgId,
            retailerName: 'Lakeside Market',
          ),
        ],
        assignments: <VendorProductAssignedRetailer>[
          VendorProductAssignedRetailer(
            relationshipId: lakesideRelationshipId,
            retailerOrganizationId: lakesideOrgId,
            retailerName: 'Lakeside Market',
            retailerStatus: VendorRetailerStatus.active,
            relationshipStatus: VendorRetailerStatus.active,
            assignmentStatus: VendorProductAssignmentStatus.unknown,
            assignedAt: DateTime.utc(2026, 5),
            assignmentUpdatedAt: DateTime.utc(2026, 5),
          ),
        ],
      );

      // Neither reactivatable — that would be guessing an unfamiliar status is
      // withdrawn — nor assignable, since a row plainly exists.
      expect(
        composed.single.state,
        VendorProductAssignmentCandidateState.ineligible,
      );
      expect(composed.single.isActionable, isFalse);
    });
  });

  group('completeness and de-duplication', () {
    test('every directory Retailer and every assignment appears', () {
      final List<VendorProductAssignmentCandidate> composed = compose();

      // Five directory rows plus the one historical pairing the directory no
      // longer contains.
      expect(composed.length, 6);
      expect(
        composed.map((VendorProductAssignmentCandidate c) => c.retailerName),
        <String>[
          'Harbour Provisions',
          'Lakeside Market',
          'Northwind Retail',
          'Old Town Grocers',
          'Riverside Foods',
          'Summit Stores',
        ],
      );
    });

    test('no Retailer organization appears twice', () {
      final List<VendorProductAssignmentCandidate> composed = compose();

      expect(
        composed
            .map(
              (VendorProductAssignmentCandidate c) => c.retailerOrganizationId,
            )
            .toSet()
            .length,
        composed.length,
      );
    });

    test('a duplicated directory row still yields one candidate', () {
      final VendorRetailerSummary row = directoryRow(
        relationshipId: lakesideRelationshipId,
        retailerOrganizationId: lakesideOrgId,
        retailerName: 'Lakeside Market',
      );
      final List<VendorProductAssignmentCandidate> composed = compose(
        retailers: <VendorRetailerSummary>[row, row],
        assignments: const <VendorProductAssignedRetailer>[],
      );

      expect(composed.length, 1);
    });

    test('a duplicated assignment row still yields one candidate', () {
      final VendorProductAssignedRetailer row = VendorProductAssignedRetailer(
        relationshipId: null,
        retailerOrganizationId: orphanedOrgId,
        retailerName: 'Old Town Grocers',
        retailerStatus: VendorRetailerStatus.deactivated,
        relationshipStatus: null,
        assignmentStatus: VendorProductAssignmentStatus.inactive,
        assignedAt: DateTime.utc(2026),
        assignmentUpdatedAt: DateTime.utc(2026),
      );
      final List<VendorProductAssignmentCandidate> composed = compose(
        retailers: const <VendorRetailerSummary>[],
        assignments: <VendorProductAssignedRetailer>[row, row],
      );

      expect(composed.length, 1);
    });

    test('an empty directory with history still lists the history', () {
      final List<VendorProductAssignmentCandidate> composed = compose(
        retailers: const <VendorRetailerSummary>[],
      );

      expect(composed.length, 5);
      expect(
        composed.every(
          (VendorProductAssignmentCandidate c) =>
              c.state ==
                  VendorProductAssignmentCandidateState.alreadyAssigned ||
              c.state ==
                  VendorProductAssignmentCandidateState.relationshipUnavailable,
        ),
        isTrue,
        reason: 'a Retailer absent from the directory can never be assignable',
      );
    });

    test('no history at all leaves every directory row assignable', () {
      final List<VendorProductAssignmentCandidate> composed = compose(
        assignments: const <VendorProductAssignedRetailer>[],
      );

      expect(composed.length, 5);
      expect(
        composed
            .where(
              (VendorProductAssignmentCandidate c) =>
                  c.state == VendorProductAssignmentCandidateState.assignable,
            )
            .map((VendorProductAssignmentCandidate c) => c.retailerName),
        <String>['Lakeside Market', 'Northwind Retail', 'Riverside Foods'],
      );
    });

    test('two empty inputs compose an empty list, not an error', () {
      expect(
        compose(
          retailers: const <VendorRetailerSummary>[],
          assignments: const <VendorProductAssignedRetailer>[],
        ),
        isEmpty,
      );
    });
  });

  group('ordering is deterministic and total', () {
    test('it is by Retailer name, then by organization id', () {
      final List<VendorProductAssignmentCandidate> composed = compose(
        retailers: <VendorRetailerSummary>[
          directoryRow(
            relationshipId: summitRelationshipId,
            retailerOrganizationId: 'ffffffff-0000-4000-8000-000000000002',
            retailerName: 'Same Name Stores',
          ),
          directoryRow(
            relationshipId: lakesideRelationshipId,
            retailerOrganizationId: 'ffffffff-0000-4000-8000-000000000001',
            retailerName: 'Same Name Stores',
          ),
        ],
        assignments: const <VendorProductAssignedRetailer>[],
      );

      // Two Retailers sharing a name cannot swap places between requests: the
      // tie is broken on the organization id, exactly as the backend's own
      // ordering does.
      expect(
        composed.map(
          (VendorProductAssignmentCandidate c) => c.retailerOrganizationId,
        ),
        <String>[
          'ffffffff-0000-4000-8000-000000000001',
          'ffffffff-0000-4000-8000-000000000002',
        ],
      );
    });

    test('the input order does not change the output order', () {
      final List<VendorProductAssignmentCandidate> forwards = compose();
      final List<VendorProductAssignmentCandidate> backwards = compose(
        retailers: assignmentDirectory.reversed.toList(),
        assignments: compositionAssignments.reversed.toList(),
      );

      expect(
        backwards.map((VendorProductAssignmentCandidate c) => c.retailerName),
        forwards.map((VendorProductAssignmentCandidate c) => c.retailerName),
      );
    });

    test('the composed list is unmodifiable', () {
      // Nothing downstream may add or drop a choice.
      expect(() => compose().add(compose().first), throwsUnsupportedError);
    });
  });

  group('search', () {
    test('it matches a name fragment case-insensitively', () {
      final VendorProductAssignmentCandidate lakeside = byName(
        compose(),
        'Lakeside Market',
      );

      expect(lakeside.matches('lake'), isTrue);
      expect(lakeside.matches('MARKET'), isTrue);
      expect(lakeside.matches('  lakeside  '), isTrue);
    });

    test('an empty or blank term matches everything', () {
      final VendorProductAssignmentCandidate lakeside = byName(
        compose(),
        'Lakeside Market',
      );

      expect(lakeside.matches(''), isTrue);
      expect(lakeside.matches('   '), isTrue);
    });

    test('it never matches an identifier', () {
      // A Retailer must not be findable — and therefore selectable — by pasting
      // an address.
      final VendorProductAssignmentCandidate lakeside = byName(
        compose(),
        'Lakeside Market',
      );

      expect(lakeside.matches(lakesideOrgId), isFalse);
      expect(lakeside.matches(lakesideRelationshipId), isFalse);
    });

    test('a non-matching term matches nothing', () {
      expect(
        compose().where(
          (VendorProductAssignmentCandidate c) => c.matches('zzzz'),
        ),
        isEmpty,
      );
    });
  });

  group('what the candidate deliberately cannot carry', () {
    test('its identity is seven display and state fields, and no id but one', () {
      final VendorProductAssignmentCandidate lakeside = byName(
        compose(),
        'Lakeside Market',
      );

      // The organization id is the only identifier present. There is no
      // relationship id field, so a selection made from a candidate cannot send
      // one — which is what keeps the write in the address space the assignment
      // table actually stores.
      expect(lakeside.props.length, 7);
      expect(lakeside.props.contains(lakesideRelationshipId), isFalse);
      expect(lakeside.props.contains(lakesideOrgId), isTrue);
    });
  });
}
