import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/retailer_read_problem.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_assignable_shop.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_member.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_shop_assignment.dart';
import 'package:sale_reward/features/staff/domain/repositories/retailer_assignable_shops_reader.dart';
import 'package:sale_reward/features/staff/presentation/retailer/cubit/retailer_manage_staff_shops_cubit.dart';

import '../../support/retailer_invite_staff_fakes.dart';
import '../../support/retailer_manage_staff_shops_fakes.dart';
import '../../support/retailer_read_fakes.dart';

/// The Manage Shops editor's cubit.
///
/// The properties under test are the ones a person's shop assignments depend on:
/// the preselection is the roster's ACTIVE ids **intersected** with what is
/// assignable now; the complete desired set is what leaves; a committed save
/// closes the editor so nothing can resubmit it; a failed roster reread is never
/// reported as a failed write; and no answer from a previous session, Retailer
/// or colleague can land in the current editor.
void main() {
  /// Priya: active, accepted Sales Staff holding Downtown and Marina.
  final RetailerStaffMember priya = exampleStaff[1];

  /// Tom: Sales Staff, but SUSPENDED and never accepted.
  final RetailerStaffMember tom = exampleStaff[2];

  /// Amina: the Retailer Owner. Holds no shop rows at all.
  final RetailerStaffMember amina = exampleStaff[0];

  /// Noor: active, accepted Sales Staff with no ACTIVE shops today.
  final RetailerStaffMember noor = exampleStaff[3];

  ({
    RetailerManageStaffShopsCubit cubit,
    FakeRetailerStaffInvitationRepository shops,
    FakeRetailerStaffShopAssignmentRepository assignments,
    List<bool> rereads,
  })
  build({
    bool manualShops = false,
    bool manualSave = false,
    bool rereadSucceeds = true,
    List<RetailerAssignableShop>? options,
  }) {
    final FakeRetailerStaffInvitationRepository shops =
        FakeRetailerStaffInvitationRepository()
          ..manualShops = manualShops
          ..nextShops = options ?? exampleAssignableShops;
    final FakeRetailerStaffShopAssignmentRepository assignments =
        FakeRetailerStaffShopAssignmentRepository()..manual = manualSave;
    final List<bool> rereads = <bool>[];

    return (
      cubit: RetailerManageStaffShopsCubit(
        shops: shops,
        assignments: assignments,
        rereadRoster: () async {
          rereads.add(true);
          return rereadSucceeds;
        },
      ),
      shops: shops,
      assignments: assignments,
      rereads: rereads,
    );
  }

  // -------------------------------------------------------------------------
  group('initial state', () {
    test('nothing is open, selected, loaded or reported', () {
      final RetailerManageStaffShopsCubit cubit = build().cubit;

      expect(cubit.state.isOpen, isFalse);
      expect(cubit.state.membershipId, isNull);
      expect(cubit.state.staffName, isNull);
      expect(cubit.state.selectedShopIds, isEmpty);
      expect(cubit.state.shops, isNull);
      expect(cubit.state.optionsPhase, RetailerManageShopsOptionsPhase.initial);
      expect(cubit.state.notice, isNull);
      expect(cubit.state.change, isNull);
      expect(cubit.state.isSubmitting, isFalse);
      expect(cubit.state.canSave, isFalse);
    });

    test('no request is issued until an editor is opened', () async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = build();

      await h.cubit.save();

      expect(h.shops.shopCallCount, 0);
      expect(h.assignments.callCount, 0);
    });
  });

  // -------------------------------------------------------------------------
  group('opening', () {
    test(
      'an eligible Sales Staff member opens and reads the options',
      () async {
        final ({
          RetailerManageStaffShopsCubit cubit,
          FakeRetailerStaffInvitationRepository shops,
          FakeRetailerStaffShopAssignmentRepository assignments,
          List<bool> rereads,
        })
        h = build();

        h.cubit.open(priya);
        await Future<void>.value();

        expect(h.cubit.state.isOpen, isTrue);
        expect(h.cubit.state.staffName, 'Priya Raman');
        expect(h.cubit.state.roleName, 'Sales Staff');
        expect(h.cubit.state.currentShopNames, priya.shopNames);
        expect(h.shops.shopCallCount, 1);
      },
    );

    test('the target is the roster membership id, not a name or an index', () {
      final RetailerManageStaffShopsCubit cubit = build().cubit;

      cubit.open(priya);

      expect(cubit.state.membershipId, priyaMembershipId);
      expect(cubit.state.membershipId, isNot(contains('Priya')));
    });

    test('an ineligible row does not open', () {
      // Presentation scope for the same rows the function refuses: suspended and
      // never-accepted Sales Staff, and every non-Sales-Staff role.
      for (final RetailerStaffMember member in <RetailerStaffMember>[
        amina,
        tom,
      ]) {
        final ({
          RetailerManageStaffShopsCubit cubit,
          FakeRetailerStaffInvitationRepository shops,
          FakeRetailerStaffShopAssignmentRepository assignments,
          List<bool> rereads,
        })
        h = build();

        h.cubit.open(member);

        expect(h.cubit.state.isOpen, isFalse, reason: member.fullName);
        expect(h.shops.shopCallCount, 0, reason: member.fullName);
      }
    });

    test('the eligibility rule matches the backend\'s three conditions', () {
      expect(priya.isEditableSalesStaff, isTrue);
      expect(noor.isEditableSalesStaff, isTrue);
      // Suspended, and never accepted.
      expect(tom.isEditableSalesStaff, isFalse);
      // Not Sales Staff.
      expect(amina.isEditableSalesStaff, isFalse);
    });

    test('opening a second member replaces the first entirely', () async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = build();

      h.cubit.open(priya);
      await Future<void>.value();
      h.cubit.open(noor);
      await Future<void>.value();

      expect(h.cubit.state.membershipId, noorMembershipId);
      expect(h.cubit.state.staffName, 'Noor Aziz');
      expect(h.cubit.state.currentShopNames, isEmpty);
      // Noor holds nothing, so nothing of Priya's may be preselected.
      expect(h.cubit.state.selectedShopIds, isEmpty);
    });

    test('the options are re-read on every open, never cached', () async {
      // Availability is exactly the thing that goes stale.
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = build();

      h.cubit.open(priya);
      await Future<void>.value();
      h.cubit.closeEditor();
      h.cubit.open(priya);
      await Future<void>.value();

      expect(h.shops.shopCallCount, 2);
    });
  });

  // -------------------------------------------------------------------------
  group('preselection is an intersection', () {
    test(
      'the roster\'s ACTIVE ids that are still assignable are ticked',
      () async {
        final ({
          RetailerManageStaffShopsCubit cubit,
          FakeRetailerStaffInvitationRepository shops,
          FakeRetailerStaffShopAssignmentRepository assignments,
          List<bool> rereads,
        })
        h = build();

        h.cubit.open(priya);
        await Future<void>.value();

        expect(h.cubit.state.selectedShopIds, <String>{
          northwindMarinaId,
          northwindDowntownId,
        });
        // Offered but not held.
        expect(
          h.cubit.state.selectedShopIds.contains(northwindWarehouseId),
          isFalse,
        );
      },
    );

    test(
      'a roster shop that is no longer assignable is dropped silently',
      () async {
        // It stopped being ACTIVE between the two reads, so it is a hidden
        // assignment the write preserves — not something the person deselected,
        // and not a reason to warn them.
        final ({
          RetailerManageStaffShopsCubit cubit,
          FakeRetailerStaffInvitationRepository shops,
          FakeRetailerStaffShopAssignmentRepository assignments,
          List<bool> rereads,
        })
        h = build(
          options: <RetailerAssignableShop>[
            const RetailerAssignableShop(
              id: northwindMarinaId,
              name: 'Northwind Marina',
              code: 'NW-01',
              city: 'Dubai',
            ),
          ],
        );

        h.cubit.open(priya);
        await Future<void>.value();

        expect(h.cubit.state.selectedShopIds, <String>{northwindMarinaId});
        expect(h.cubit.state.availabilityChanged, isFalse);
        // And it is the baseline too, so the editor does not immediately claim an
        // unsaved change.
        expect(h.cubit.state.hasChanges, isFalse);
        expect(h.cubit.state.canSave, isFalse);
      },
    );

    test('a member with no ACTIVE shops opens with nothing ticked', () async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = build();

      h.cubit.open(noor);
      await Future<void>.value();

      expect(h.cubit.state.isOpen, isTrue);
      expect(h.cubit.state.selectedShopIds, isEmpty);
      expect(h.cubit.state.canSave, isFalse);
    });

    test('another Retailer\'s shop ids can never be preselected', () async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = build(options: otherAssignableShops);

      h.cubit.open(priya);
      await Future<void>.value();

      expect(h.cubit.state.selectedShopIds, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  group('the options read', () {
    test('a loading state is observable before the answer lands', () async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = build(manualShops: true);

      h.cubit.open(priya);

      expect(h.cubit.state.isOptionsLoading, isTrue);
      expect(h.cubit.state.canSave, isFalse);

      h.shops.completeShops();
      await Future<void>.value();

      expect(h.cubit.state.isOptionsReady, isTrue);
    });

    test(
      'a failure is scoped to the read and never becomes a write failure',
      () async {
        final ({
          RetailerManageStaffShopsCubit cubit,
          FakeRetailerStaffInvitationRepository shops,
          FakeRetailerStaffShopAssignmentRepository assignments,
          List<bool> rereads,
        })
        h = build();
        h.shops.shopsResult = const RetailerAssignableShopsFailed(
          RetailerReadProblem.network,
        );

        h.cubit.open(priya);
        await Future<void>.value();

        expect(h.cubit.state.hasOptionsFailed, isTrue);
        expect(h.cubit.state.optionsProblem, RetailerReadProblem.network);
        // The editor is still open, Save is refused, and no save notice exists.
        expect(h.cubit.state.isOpen, isTrue);
        expect(h.cubit.state.canSave, isFalse);
        expect(h.cubit.state.notice, isNull);
        expect(h.assignments.callCount, 0);
      },
    );

    test('a denial is a denial, never an empty picker', () async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = build();
      h.shops.shopsResult = const RetailerAssignableShopsFailed(
        RetailerReadProblem.denied,
      );

      h.cubit.open(priya);
      await Future<void>.value();

      expect(h.cubit.state.hasOptionsFailed, isTrue);
      expect(h.cubit.state.isOptionsEmpty, isFalse);
    });

    test('an empty answer is an empty estate, not a failure', () async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = build(options: const <RetailerAssignableShop>[]);

      h.cubit.open(priya);
      await Future<void>.value();

      expect(h.cubit.state.isOptionsEmpty, isTrue);
      expect(h.cubit.state.hasOptionsFailed, isFalse);
      expect(h.cubit.state.canSave, isFalse);
    });

    test('a retry re-reads only the options', () async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = build();
      h.shops.shopsResult = const RetailerAssignableShopsFailed(
        RetailerReadProblem.timeout,
      );

      h.cubit.open(priya);
      await Future<void>.value();

      h.shops.shopsResult = null;
      await h.cubit.loadAssignableShops();

      expect(h.shops.shopCallCount, 2);
      expect(h.cubit.state.isOptionsReady, isTrue);
      expect(h.cubit.state.optionsProblem, isNull);
      expect(h.assignments.callCount, 0);
      // The preselection is applied on the retry, because that is the first read
      // that actually produced options.
      expect(h.cubit.state.selectedShopIds, <String>{
        northwindMarinaId,
        northwindDowntownId,
      });
    });

    test('a duplicate read is suppressed while one is in flight', () async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = build(manualShops: true);

      h.cubit.open(priya);
      await h.cubit.loadAssignableShops();

      expect(h.shops.shopCallCount, 1);
    });
  });

  // -------------------------------------------------------------------------
  group('selection', () {
    Future<RetailerManageStaffShopsCubit> opened() async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = build();
      h.cubit.open(priya);
      await Future<void>.value();
      return h.cubit;
    }

    test('toggling adds and removes, keyed on the backend id', () async {
      final RetailerManageStaffShopsCubit cubit = await opened();

      cubit.shopSelectionToggled(northwindWarehouseId);
      expect(cubit.state.selectedShopIds, contains(northwindWarehouseId));

      cubit.shopSelectionToggled(northwindWarehouseId);
      expect(
        cubit.state.selectedShopIds.contains(northwindWarehouseId),
        isFalse,
      );
    });

    test('a duplicate is structurally impossible', () async {
      final RetailerManageStaffShopsCubit cubit = await opened();

      // Ticking the same shop repeatedly can only ever produce one entry, and
      // the submittable list is deduplicated by construction.
      cubit.shopSelectionToggled(northwindWarehouseId);
      cubit.shopSelectionToggled(northwindWarehouseId);
      cubit.shopSelectionToggled(northwindWarehouseId);

      final List<String> submittable = cubit.state.submittableShopIds;
      expect(submittable.toSet().length, submittable.length);
    });

    test('an id that is not in the options is ignored outright', () async {
      final RetailerManageStaffShopsCubit cubit = await opened();
      final Set<String> before = cubit.state.selectedShopIds;

      cubit.shopSelectionToggled(southgateCentralId);
      cubit.shopSelectionToggled('not-a-uuid');

      expect(cubit.state.selectedShopIds, before);
    });

    test(
      'the submittable set is intersected with the options and sorted',
      () async {
        final RetailerManageStaffShopsCubit cubit = await opened();
        cubit.shopSelectionToggled(northwindWarehouseId);

        final List<String> submittable = cubit.state.submittableShopIds;
        expect(submittable.toSet(), <String>{
          northwindMarinaId,
          northwindDowntownId,
          northwindWarehouseId,
        });
        for (final String id in submittable) {
          expect(
            cubit.state.shops!.any((RetailerAssignableShop s) => s.id == id),
            isTrue,
          );
        }
      },
    );

    test('the selected count reflects what could actually be sent', () async {
      final RetailerManageStaffShopsCubit cubit = await opened();
      expect(cubit.state.selectedCount, 2);

      cubit.shopSelectionToggled(northwindWarehouseId);
      expect(cubit.state.selectedCount, 3);
    });

    test('an empty selection cannot be saved', () async {
      final RetailerManageStaffShopsCubit cubit = await opened();

      cubit.shopSelectionToggled(northwindMarinaId);
      cubit.shopSelectionToggled(northwindDowntownId);

      expect(cubit.state.selectedCount, 0);
      expect(cubit.state.canSave, isFalse);
    });

    test('an unchanged selection cannot be saved', () async {
      final RetailerManageStaffShopsCubit cubit = await opened();

      expect(cubit.state.hasChanges, isFalse);
      expect(cubit.state.canSave, isFalse);

      // Ticking and unticking returns to the baseline, in any order.
      cubit.shopSelectionToggled(northwindWarehouseId);
      expect(cubit.state.canSave, isTrue);
      cubit.shopSelectionToggled(northwindWarehouseId);
      expect(cubit.state.canSave, isFalse);
    });

    test('the selection survives while the editor stays open', () async {
      final RetailerManageStaffShopsCubit cubit = await opened();

      cubit.shopSelectionToggled(northwindWarehouseId);
      cubit.shopSelectionToggled(northwindMarinaId);

      expect(cubit.state.selectedShopIds, <String>{
        northwindDowntownId,
        northwindWarehouseId,
      });
    });
  });

  // -------------------------------------------------------------------------
  group('a selected shop that becomes unavailable', () {
    Future<
      ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
    >
    withVanishedOption() async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = build();

      h.cubit.open(priya);
      await Future<void>.value();

      // A shop the person deliberately ticked in this session.
      h.cubit.shopSelectionToggled(northwindWarehouseId);

      // The next read no longer offers it.
      h.shops.nextShops = exampleAssignableShops
          .where((RetailerAssignableShop s) => s.id != northwindWarehouseId)
          .toList();
      await h.cubit.loadAssignableShops();

      return h;
    }

    test('it is removed from the requested set and flagged', () async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = await withVanishedOption();

      expect(
        h.cubit.state.selectedShopIds.contains(northwindWarehouseId),
        isFalse,
      );
      expect(h.cubit.state.availabilityChanged, isTrue);
    });

    test('Save is blocked until the change is reviewed', () async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = await withVanishedOption();

      expect(h.cubit.state.canSave, isFalse);

      h.cubit.acknowledgeAvailabilityChange();

      expect(h.cubit.state.availabilityChanged, isFalse);
      // Still nothing to save, because the surviving set equals the baseline.
      expect(h.cubit.state.hasChanges, isFalse);
    });

    test('changing the selection is itself the review', () async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = await withVanishedOption();

      h.cubit.shopSelectionToggled(northwindMarinaId);

      expect(h.cubit.state.availabilityChanged, isFalse);
      expect(h.cubit.state.canSave, isTrue);
    });

    test('the vanished id is never submitted', () async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = await withVanishedOption();

      h.cubit.shopSelectionToggled(northwindMarinaId);
      await h.cubit.save();

      expect(h.assignments.sentRequests, hasLength(1));
      expect(
        h.assignments.sentRequests.single.shopIds,
        isNot(contains(northwindWarehouseId)),
      );
    });
  });

  // -------------------------------------------------------------------------
  group('saving', () {
    Future<
      ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
    >
    changed({bool manualSave = false, bool rereadSucceeds = true}) async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = build(manualSave: manualSave, rereadSucceeds: rereadSucceeds);

      h.cubit.open(priya);
      await Future<void>.value();
      // Add Warehouse, drop Downtown: the example from the milestone brief.
      h.cubit.shopSelectionToggled(northwindWarehouseId);
      h.cubit.shopSelectionToggled(northwindDowntownId);

      return h;
    }

    test('the complete desired set leaves, not a diff', () async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = await changed();

      await h.cubit.save();

      final RetailerStaffShopAssignmentRequest sent =
          h.assignments.sentRequests.single;
      expect(sent.membershipId, priyaMembershipId);
      expect(sent.shopIds.toSet(), <String>{
        northwindMarinaId,
        northwindWarehouseId,
      });
      // The dropped shop is simply absent — there is no removal list.
      expect(sent.shopIds, isNot(contains(northwindDowntownId)));
    });

    test(
      'a submitting state is observable, and Save is refused during it',
      () async {
        final ({
          RetailerManageStaffShopsCubit cubit,
          FakeRetailerStaffInvitationRepository shops,
          FakeRetailerStaffShopAssignmentRepository assignments,
          List<bool> rereads,
        })
        h = await changed(manualSave: true);

        final Future<void> first = h.cubit.save();

        expect(h.cubit.state.isSubmitting, isTrue);
        expect(h.cubit.state.canSave, isFalse);

        h.assignments.complete();
        await first;
      },
    );

    test('a second press while one is in flight writes nothing', () async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = await changed(manualSave: true);

      final Future<void> first = h.cubit.save();
      await h.cubit.save();
      await h.cubit.save();

      expect(h.assignments.callCount, 1);

      h.assignments.complete();
      await first;

      expect(h.assignments.callCount, 1);
    });

    test('a success closes the editor, so nothing can resubmit it', () async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = await changed();

      await h.cubit.save();

      expect(h.cubit.state.notice, RetailerManageShopsNotice.saved);
      expect(h.cubit.state.isOpen, isFalse);
      expect(h.cubit.state.membershipId, isNull);
      expect(h.cubit.state.selectedShopIds, isEmpty);
      expect(h.cubit.state.shops, isNull);

      // An ordinary retry has nothing left to send.
      await h.cubit.save();
      expect(h.assignments.callCount, 1);
    });

    test('the counts are carried as a change summary', () async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = await changed();
      h.assignments.result = appliedOneForOne;

      await h.cubit.save();

      expect(h.cubit.state.change!.shopsAdded, 1);
      expect(h.cubit.state.change!.shopsRemoved, 1);
      expect(h.cubit.state.change!.shopsUnchanged, 1);
    });

    test('an all-unchanged answer is a success, not a failure', () async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = await changed();
      h.assignments.result = appliedNoChange;

      await h.cubit.save();

      expect(h.cubit.state.notice, RetailerManageShopsNotice.saved);
      expect(h.cubit.state.change!.hasChanges, isFalse);
    });

    test('the canonical roster is re-read after a success', () async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = await changed();

      await h.cubit.save();

      expect(h.rereads, hasLength(1));
      expect(h.cubit.state.rosterRereadFailed, isFalse);
    });

    test(
      'a failed reread is reported separately, never as a failed write',
      () async {
        final ({
          RetailerManageStaffShopsCubit cubit,
          FakeRetailerStaffInvitationRepository shops,
          FakeRetailerStaffShopAssignmentRepository assignments,
          List<bool> rereads,
        })
        h = await changed(rereadSucceeds: false);

        await h.cubit.save();

        // The save still stands.
        expect(h.cubit.state.notice, RetailerManageShopsNotice.saved);
        expect(h.cubit.state.change, isNotNull);
        // And the stale roster is its own, additional fact.
        expect(h.cubit.state.rosterRereadFailed, isTrue);
        // The write is not repeated to resolve it.
        expect(h.assignments.callCount, 1);
      },
    );

    test('no reread happens after a refusal', () async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = await changed();
      h.assignments.result = refused(RetailerStaffShopAssignmentProblem.denied);

      await h.cubit.save();

      expect(h.rereads, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  group('a refusal', () {
    Future<RetailerManageShopsNotice> noticeFor(
      RetailerStaffShopAssignmentProblem problem,
    ) async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = build();
      h.assignments.result = refused(problem);

      h.cubit.open(priya);
      await Future<void>.value();
      h.cubit.shopSelectionToggled(northwindWarehouseId);
      await h.cubit.save();

      return h.cubit.state.notice!;
    }

    test('every problem maps to its own notice', () async {
      final Map<RetailerStaffShopAssignmentProblem, RetailerManageShopsNotice>
      expected =
          <RetailerStaffShopAssignmentProblem, RetailerManageShopsNotice>{
            RetailerStaffShopAssignmentProblem.denied:
                RetailerManageShopsNotice.accessDenied,
            RetailerStaffShopAssignmentProblem.invalidSelection:
                RetailerManageShopsNotice.invalidSelection,
            RetailerStaffShopAssignmentProblem.retailerUnavailable:
                RetailerManageShopsNotice.retailerUnavailable,
            RetailerStaffShopAssignmentProblem.malformedRequest:
                RetailerManageShopsNotice.invalidRequest,
            RetailerStaffShopAssignmentProblem.signedOut:
                RetailerManageShopsNotice.signedOut,
            RetailerStaffShopAssignmentProblem.malformedResponse:
                RetailerManageShopsNotice.unreadableAnswer,
            RetailerStaffShopAssignmentProblem.network:
                RetailerManageShopsNotice.network,
            RetailerStaffShopAssignmentProblem.timeout:
                RetailerManageShopsNotice.timedOut,
            RetailerStaffShopAssignmentProblem.unexpected:
                RetailerManageShopsNotice.unexpected,
          };

      // Exhaustive by construction: a new problem with no mapping fails here.
      expect(
        expected.keys.toSet(),
        RetailerStaffShopAssignmentProblem.values.toSet(),
      );

      for (final MapEntry<
            RetailerStaffShopAssignmentProblem,
            RetailerManageShopsNotice
          >
          entry
          in expected.entries) {
        expect(await noticeFor(entry.key), entry.value, reason: '${entry.key}');
      }
    });

    test('the editor stays open with the selection intact', () async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = build();
      h.assignments.result = refused(
        RetailerStaffShopAssignmentProblem.invalidSelection,
      );

      h.cubit.open(priya);
      await Future<void>.value();
      h.cubit.shopSelectionToggled(northwindWarehouseId);
      await h.cubit.save();

      expect(h.cubit.state.isOpen, isTrue);
      expect(h.cubit.state.isSubmitting, isFalse);
      expect(h.cubit.state.selectedShopIds, contains(northwindWarehouseId));
      // A deliberate retry costs no re-ticking, and is exactly one more write.
      await h.cubit.save();
      expect(h.assignments.callCount, 2);
    });

    test('the three unresolved outcomes are marked as such', () async {
      for (final RetailerStaffShopAssignmentProblem problem
          in <RetailerStaffShopAssignmentProblem>[
            RetailerStaffShopAssignmentProblem.timeout,
            RetailerStaffShopAssignmentProblem.malformedResponse,
            RetailerStaffShopAssignmentProblem.unexpected,
          ]) {
        expect(
          (await noticeFor(problem)).isUnresolved,
          isTrue,
          reason: '$problem',
        );
      }
    });

    test('a definite refusal is not marked unresolved', () async {
      for (final RetailerStaffShopAssignmentProblem problem
          in <RetailerStaffShopAssignmentProblem>[
            RetailerStaffShopAssignmentProblem.denied,
            RetailerStaffShopAssignmentProblem.invalidSelection,
            RetailerStaffShopAssignmentProblem.retailerUnavailable,
            RetailerStaffShopAssignmentProblem.network,
            RetailerStaffShopAssignmentProblem.signedOut,
          ]) {
        final RetailerManageShopsNotice notice = await noticeFor(problem);
        expect(notice.isUnresolved, isFalse, reason: '$problem');
        expect(notice.isSuccess, isFalse, reason: '$problem');
      }
    });
  });

  // -------------------------------------------------------------------------
  group('local validation refuses before anything leaves', () {
    test('an empty selection produces a message and no write', () async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = build();

      h.cubit.open(noor);
      await Future<void>.value();
      await h.cubit.save();

      expect(h.assignments.callCount, 0);
      expect(h.cubit.state.notice, RetailerManageShopsNotice.checkTheSelection);
      expect(
        h.cubit.state.problemFor(RetailerStaffShopAssignmentField.shops),
        RetailerStaffShopAssignmentInputProblem.noShopsSelected,
      );
    });
  });

  // -------------------------------------------------------------------------
  group('the target leaving the roster', () {
    test('closes the editor and says so', () async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = build();

      h.cubit.open(priya);
      await Future<void>.value();

      h.cubit.rosterChanged(<String>[aminaMembershipId, tomMembershipId]);

      expect(h.cubit.state.isOpen, isFalse);
      expect(h.cubit.state.membershipId, isNull);
      expect(h.cubit.state.notice, RetailerManageShopsNotice.targetUnavailable);
    });

    test('a roster that still contains the target leaves it alone', () async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = build();

      h.cubit.open(priya);
      await Future<void>.value();
      h.cubit.shopSelectionToggled(northwindWarehouseId);

      h.cubit.rosterChanged(<String>[priyaMembershipId, aminaMembershipId]);

      expect(h.cubit.state.isOpen, isTrue);
      expect(h.cubit.state.selectedShopIds, contains(northwindWarehouseId));
    });

    test('a save in flight is never interrupted by a roster change', () async {
      // The write already names the target, and its answer decides what
      // happened. Closing underneath it would leave it with nowhere to report.
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = build(manualSave: true);

      h.cubit.open(priya);
      await Future<void>.value();
      h.cubit.shopSelectionToggled(northwindWarehouseId);
      final Future<void> save = h.cubit.save();

      h.cubit.rosterChanged(const <String>[]);
      expect(h.cubit.state.isSubmitting, isTrue);

      h.assignments.complete();
      await save;

      expect(h.cubit.state.notice, RetailerManageShopsNotice.saved);
    });
  });

  // -------------------------------------------------------------------------
  group('closing', () {
    test('drops the target, the selection and the options', () async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = build();

      h.cubit.open(priya);
      await Future<void>.value();
      h.cubit.closeEditor();

      expect(h.cubit.state.isOpen, isFalse);
      expect(h.cubit.state.membershipId, isNull);
      expect(h.cubit.state.staffName, isNull);
      expect(h.cubit.state.selectedShopIds, isEmpty);
      expect(h.cubit.state.rosterShopIds, isEmpty);
      expect(h.cubit.state.shops, isNull);
    });

    test('keeps the last result, which belongs beside the roster', () async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = build();

      h.cubit.open(priya);
      await Future<void>.value();
      h.cubit.shopSelectionToggled(northwindWarehouseId);
      await h.cubit.save();
      h.cubit.closeEditor();

      expect(h.cubit.state.notice, RetailerManageShopsNotice.saved);
      expect(h.cubit.state.change, isNotNull);
    });

    test('cancelling writes nothing', () async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = build();

      h.cubit.open(priya);
      await Future<void>.value();
      h.cubit.shopSelectionToggled(northwindWarehouseId);
      h.cubit.closeEditor();

      expect(h.assignments.callCount, 0);
      expect(h.rereads, isEmpty);
    });

    test('closing is refused while a save is in flight', () async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = build(manualSave: true);

      h.cubit.open(priya);
      await Future<void>.value();
      h.cubit.shopSelectionToggled(northwindWarehouseId);
      final Future<void> save = h.cubit.save();

      h.cubit.closeEditor();
      expect(h.cubit.state.isOpen, isTrue);

      h.assignments.complete();
      await save;
    });
  });

  // -------------------------------------------------------------------------
  group('session isolation', () {
    test('clear drops everything, including the last result', () async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = build();

      h.cubit.open(priya);
      await Future<void>.value();
      h.cubit.shopSelectionToggled(northwindWarehouseId);
      await h.cubit.save();

      h.cubit.clear();

      expect(h.cubit.state, const RetailerManageStaffShopsState());
      expect(h.cubit.state.membershipId, isNull);
      expect(h.cubit.state.shops, isNull);
      expect(h.cubit.state.notice, isNull);
      expect(h.cubit.state.change, isNull);
    });

    test('clear advances the token so nothing in flight can land', () async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = build();

      final int before = h.cubit.requestToken;
      h.cubit.clear();
      expect(h.cubit.requestToken, greaterThan(before));
    });

    test('a shop read answering after a logout is dropped', () async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = build(manualShops: true);

      h.cubit.open(priya);
      h.cubit.clear();

      h.shops.completeShops();
      await Future<void>.value();

      expect(h.cubit.state.shops, isNull);
      expect(h.cubit.state.isOpen, isFalse);
    });

    test('a save answering after a logout leaves no result behind', () async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = build(manualSave: true);

      h.cubit.open(priya);
      await Future<void>.value();
      h.cubit.shopSelectionToggled(northwindWarehouseId);
      final Future<void> save = h.cubit.save();

      h.cubit.clear();
      h.assignments.complete();
      await save;

      expect(h.cubit.state.notice, isNull);
      expect(h.cubit.state.change, isNull);
      // And the roster is not re-read on a dead session's behalf.
      expect(h.rereads, isEmpty);
    });

    test(
      'a previous Retailer\'s shop options cannot reach the next one',
      () async {
        final ({
          RetailerManageStaffShopsCubit cubit,
          FakeRetailerStaffInvitationRepository shops,
          FakeRetailerStaffShopAssignmentRepository assignments,
          List<bool> rereads,
        })
        h = build(manualShops: true);

        h.cubit.open(priya);
        h.cubit.clear();

        // The second Retailer's estate answers first; the first Retailer's read
        // then completes and must be ignored.
        h.shops.nextShops = otherAssignableShops;
        h.cubit.open(priya);
        h.shops.completeShopsAt(1);
        await Future<void>.value();
        h.shops.completeShopsAt(
          0,
          RetailerAssignableShopsLoaded(exampleAssignableShops),
        );
        await Future<void>.value();

        final Set<String> ids = <String>{
          for (final RetailerAssignableShop s in h.cubit.state.shops!) s.id,
        };
        expect(ids, <String>{southgateCentralId});
      },
    );

    test('an answer for a previous target is dropped', () async {
      final ({
        RetailerManageStaffShopsCubit cubit,
        FakeRetailerStaffInvitationRepository shops,
        FakeRetailerStaffShopAssignmentRepository assignments,
        List<bool> rereads,
      })
      h = build(manualShops: true);

      h.cubit.open(priya);
      h.cubit.open(noor);

      // Priya's read finishes last and must not fill Noor's editor.
      h.shops.completeShopsAt(1);
      await Future<void>.value();
      h.shops.completeShopsAt(0);
      await Future<void>.value();

      expect(h.cubit.state.membershipId, noorMembershipId);
      // Noor holds nothing, so nothing may be preselected.
      expect(h.cubit.state.selectedShopIds, isEmpty);
    });
  });
}
