import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sale_reward/app/shells/retailer_manager/retailer_manager_navigation.dart';
import 'package:sale_reward/app/shells/retailer_owner/retailer_owner_navigation.dart';
import 'package:sale_reward/app/shells/sales_staff/sales_staff_navigation.dart';
import 'package:sale_reward/app/shells/vendor/vendor_navigation.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_lifecycle_status.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_member.dart';
import 'package:sale_reward/features/staff/domain/repositories/retailer_staff_lifecycle_repository.dart';
import 'package:sale_reward/features/staff/presentation/retailer/cubit/retailer_staff_lifecycle_cubit.dart';
import 'package:sale_reward/features/staff/presentation/retailer/widgets/retailer_staff_lifecycle_copy.dart';
import 'package:sale_reward/features/staff/presentation/retailer/widgets/retailer_staff_member_card.dart';

import '../../support/pump_app.dart';
import '../../support/retailer_read_fakes.dart';
import '../../support/retailer_staff_lifecycle_fakes.dart';

/// Drives the Retailer staff lifecycle control through the real application:
/// real router, real shell, real cubits, over fakes that never touch Supabase.
void main() {
  Future<void> goTo(WidgetTester tester, String location) async {
    GoRouter.of(tester.element(find.byType(Navigator).first)).go(location);
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Taps without settling.
  ///
  /// Required whenever another row already has a request in flight: that row's
  /// progress spinner animates indefinitely by design, so `pumpAndSettle` would
  /// time out rather than fail meaningfully.
  Future<void> tapVisibleNoSettle(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  late FakeRetailerStaffRepository staff;
  late FakeRetailerStaffLifecycleRepository lifecycle;

  setUp(() {
    staff = FakeRetailerStaffRepository();
    lifecycle = FakeRetailerStaffLifecycleRepository();
  });

  Future<PumpedApp> onOwnerStaff(
    WidgetTester tester, {
    List<RetailerStaffMember>? roster,
    Size surface = phoneSurface,
  }) async {
    if (roster != null) {
      staff.nextMembers = roster;
    }
    final PumpedApp app = await pumpAppInRole(
      tester,
      PortalKind.retailerOwner,
      surface: surface,
      retailerStaff: staff,
      retailerStaffLifecycle: lifecycle,
    );
    await goTo(tester, RetailerOwnerNavigation.staff);
    return app;
  }

  /// Any text inside the card for [name].
  Finder inCard(String name, String text) => find.descendant(
    of: find.ancestor(
      of: find.text(name),
      matching: find.byType(RetailerStaffMemberCard),
    ),
    matching: find.text(text),
  );

  Future<void> confirmDialog(
    WidgetTester tester,
    String label, {
    bool settle = true,
  }) async {
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text(label)),
    );
    if (settle) {
      await tester.pumpAndSettle();
      return;
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// A roster row, built from the shared fixtures' shape.
  RetailerStaffMember row({
    required String membershipId,
    required String firstName,
    required String roleCode,
    required String roleName,
    required RetailerMemberStatus status,
  }) => RetailerStaffMember(
    membershipId: membershipId,
    firstName: firstName,
    lastName: 'Example',
    roleCode: roleCode,
    roleName: roleName,
    status: status,
    shopIds: const <String>[],
    shopNames: const <String>[],
    joinedAt: DateTime.utc(2026, 4, 1),
    createdAt: DateTime.utc(2026, 3, 1),
  );

  group('who gets the control', () {
    testWidgets('an ACTIVE Sales Staff member shows Deactivate', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(tester);

      expect(inCard('Priya Raman', 'Deactivate'), findsOneWidget);
      expect(inCard('Priya Raman', 'Reactivate'), findsNothing);
    });

    testWidgets('an ACTIVE Manager shows Deactivate', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(
        tester,
        roster: <RetailerStaffMember>[
          row(
            membershipId: priyaMembershipId,
            firstName: 'Priya',
            roleCode: 'RETAILER_MANAGER',
            roleName: 'Retailer Manager',
            status: RetailerMemberStatus.active,
          ),
        ],
      );

      expect(inCard('Priya Example', 'Deactivate'), findsOneWidget);
    });

    testWidgets('a DEACTIVATED member shows Reactivate and reads Inactive', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(
        tester,
        roster: <RetailerStaffMember>[
          row(
            membershipId: priyaMembershipId,
            firstName: 'Priya',
            roleCode: 'SALES_STAFF',
            roleName: 'Sales Staff',
            status: RetailerMemberStatus.deactivated,
          ),
        ],
      );

      expect(inCard('Priya Example', 'Reactivate'), findsOneWidget);
      expect(inCard('Priya Example', 'Deactivate'), findsNothing);
      expect(inCard('Priya Example', 'Inactive'), findsOneWidget);
      expect(inCard('Priya Example', 'Deactivated'), findsNothing);
    });

    testWidgets('a Retailer Owner gets no control', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(tester);

      // Amina is the Owner in the shared fixture — and, by the transitive rule,
      // also the signed-in caller's own row.
      expect(inCard('Amina Farouk', 'Deactivate'), findsNothing);
      expect(inCard('Amina Farouk', 'Reactivate'), findsNothing);
    });

    testWidgets('a SUSPENDED member gets no control and reads Suspended', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(tester);

      // Tom is SUSPENDED in the shared fixture. The RPC refuses it in both
      // directions, and the word stays distinct from "Inactive".
      expect(inCard('Tom Byrne', 'Deactivate'), findsNothing);
      expect(inCard('Tom Byrne', 'Reactivate'), findsNothing);
      expect(inCard('Tom Byrne', 'Suspended'), findsOneWidget);
      expect(inCard('Tom Byrne', 'Inactive'), findsNothing);
    });

    testWidgets('an INVITED member gets no control', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(
        tester,
        roster: <RetailerStaffMember>[
          row(
            membershipId: priyaMembershipId,
            firstName: 'Priya',
            roleCode: 'SALES_STAFF',
            roleName: 'Sales Staff',
            status: RetailerMemberStatus.invited,
          ),
        ],
      );

      expect(inCard('Priya Example', 'Deactivate'), findsNothing);
      expect(inCard('Priya Example', 'Invited'), findsOneWidget);
    });

    testWidgets('an unsupported role gets no control', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(
        tester,
        roster: <RetailerStaffMember>[
          row(
            membershipId: priyaMembershipId,
            firstName: 'Priya',
            roleCode: 'AUDITOR',
            roleName: 'Auditor',
            status: RetailerMemberStatus.active,
          ),
        ],
      );

      expect(inCard('Priya Example', 'Deactivate'), findsNothing);
    });
  });

  group('the duplicate-membership rule, on screen', () {
    /// Two roster rows sharing one membership id — a multi-role member.
    List<RetailerStaffMember> dual(String roleA, String roleB) =>
        <RetailerStaffMember>[
          row(
            membershipId: priyaMembershipId,
            firstName: 'Priya',
            roleCode: roleA,
            roleName: roleA,
            status: RetailerMemberStatus.active,
          ),
          row(
            membershipId: priyaMembershipId,
            firstName: 'Priya',
            roleCode: roleB,
            roleName: roleB,
            status: RetailerMemberStatus.active,
          ),
        ];

    testWidgets('Owner + Sales Staff hides the control on both rows', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(tester, roster: dual('RETAILER_OWNER', 'SALES_STAFF'));

      expect(find.text('Deactivate'), findsNothing);
      expect(find.text('Reactivate'), findsNothing);
    });

    testWidgets('Owner + Manager hides the control on both rows', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(
        tester,
        roster: dual('RETAILER_OWNER', 'RETAILER_MANAGER'),
      );

      expect(find.text('Deactivate'), findsNothing);
    });

    testWidgets('Manager + Sales Staff hides the control on both rows', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(
        tester,
        roster: dual('RETAILER_MANAGER', 'SALES_STAFF'),
      );

      expect(find.text('Deactivate'), findsNothing);
    });

    testWidgets('a unique eligible row beside duplicates still works', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(
        tester,
        roster: <RetailerStaffMember>[
          ...dual('RETAILER_OWNER', 'SALES_STAFF'),
          row(
            membershipId: noorMembershipId,
            firstName: 'Noor',
            roleCode: 'SALES_STAFF',
            roleName: 'Sales Staff',
            status: RetailerMemberStatus.active,
          ),
        ],
      );

      expect(inCard('Noor Example', 'Deactivate'), findsOneWidget);
      expect(find.text('Deactivate'), findsOneWidget);
    });

    testWidgets(
      'a local search that hides one duplicate row still hides the control',
      (WidgetTester tester) async {
        // The regression this guards: eligibility computed over the SEARCH-
        // FILTERED list would make a duplicated membership look unique the
        // moment a search matched only one of its rows.
        await onOwnerStaff(
          tester,
          roster: <RetailerStaffMember>[
            row(
              membershipId: priyaMembershipId,
              firstName: 'Priya',
              roleCode: 'RETAILER_OWNER',
              roleName: 'Retailer Owner',
              status: RetailerMemberStatus.active,
            ),
            row(
              membershipId: priyaMembershipId,
              firstName: 'Priya',
              roleCode: 'SALES_STAFF',
              roleName: 'Sales Staff',
              status: RetailerMemberStatus.active,
            ),
          ],
        );

        await tester.enterText(find.byType(TextField).first, 'Sales');
        await tester.pumpAndSettle();

        expect(find.text('Deactivate'), findsNothing);
      },
    );
  });

  group('submitting', () {
    testWidgets('the confirmed direction is what reaches the repository', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(tester);

      await tapVisible(tester, inCard('Priya Raman', 'Deactivate'));
      await confirmDialog(tester, 'Deactivate staff');

      expect(lifecycle.callCount, 1);
      expect(lifecycle.writes.single.membershipId, priyaMembershipId);
      expect(
        lifecycle.writes.single.status,
        RetailerStaffLifecycleStatus.deactivated,
      );
    });

    testWidgets('cancelling writes nothing at all', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(tester);

      await tapVisible(tester, inCard('Priya Raman', 'Deactivate'));
      await confirmDialog(tester, RetailerStaffLifecycleCopy.cancel);

      expect(lifecycle.callCount, 0);
      expect(inCard('Priya Raman', 'Active'), findsOneWidget);
    });

    testWidgets('the dialog names the person and shows no identifier', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(tester);

      await tapVisible(tester, inCard('Priya Raman', 'Deactivate'));

      expect(find.text('Deactivate staff\nPriya Raman'), findsOneWidget);
      expect(find.textContaining(priyaMembershipId), findsNothing);

      final String body = RetailerStaffLifecycleCopy.deactivateBody;
      expect(body, contains('lose access'));
      expect(body, contains('receipt submission'));
      expect(body, contains('already signed in'));
      expect(body, contains('not signed out'));
      expect(body, contains('role and Shop assignments are kept'));
      expect(body, contains('Nothing is deleted'));
      expect(body, contains('reactivate them at any time'));
    });

    testWidgets('the reactivate dialog explains what returns', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(
        tester,
        roster: <RetailerStaffMember>[
          row(
            membershipId: priyaMembershipId,
            firstName: 'Priya',
            roleCode: 'SALES_STAFF',
            roleName: 'Sales Staff',
            status: RetailerMemberStatus.deactivated,
          ),
        ],
      );

      await tapVisible(tester, inCard('Priya Example', 'Reactivate'));

      final String body = RetailerStaffLifecycleCopy.reactivateBody;
      expect(body, contains('never removed'));
      expect(body, contains('access returns exactly as it was'));
      expect(body, contains('Receipt access resumes'));
      expect(find.text(body), findsOneWidget);
    });

    testWidgets('a pending request spins THIS row only', (
      WidgetTester tester,
    ) async {
      lifecycle.manual = true;
      await onOwnerStaff(tester);

      await tapVisible(tester, inCard('Priya Raman', 'Deactivate'));
      await confirmDialog(tester, 'Deactivate staff', settle: false);

      // Priya's control shows progress…
      expect(inCard('Priya Raman', 'Deactivating…'), findsOneWidget);
      expect(inCard('Priya Raman', 'Deactivate'), findsNothing);
      // …and Noor's is untouched and still pressable.
      expect(inCard('Noor Aziz', 'Deactivate'), findsOneWidget);
      expect(inCard('Noor Aziz', 'Deactivating…'), findsNothing);

      expect(lifecycle.callCount, 1);
      lifecycle.complete();
      await tester.pumpAndSettle();
      expect(lifecycle.callCount, 1);
    });

    testWidgets('the badge does not change before the canonical reread', (
      WidgetTester tester,
    ) async {
      lifecycle.manual = true;
      await onOwnerStaff(tester);

      await tapVisible(tester, inCard('Priya Raman', 'Deactivate'));
      await confirmDialog(tester, 'Deactivate staff', settle: false);

      // Nothing is optimistic: the badge is still what the roster reported.
      expect(inCard('Priya Raman', 'Active'), findsOneWidget);
      expect(inCard('Priya Raman', 'Inactive'), findsNothing);

      lifecycle.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('a committed change acknowledges and rereads the roster', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(tester);
      final int readsBefore = staff.memberCallCount;

      await tapVisible(tester, inCard('Priya Raman', 'Deactivate'));
      await confirmDialog(tester, 'Deactivate staff');

      expect(
        find.text(
          RetailerStaffLifecycleCopy.noticeTitle(
            RetailerStaffLifecycleNotice.deactivated,
          ),
        ),
        findsOneWidget,
      );
      expect(staff.memberCallCount, greaterThan(readsBefore));
    });

    testWidgets('a refusal shows safe generic copy and does not reread', (
      WidgetTester tester,
    ) async {
      lifecycle.result = refusedStaffLifecycle(
        RetailerStaffLifecycleProblem.denied,
      );
      await onOwnerStaff(tester);
      final int readsBefore = staff.memberCallCount;

      await tapVisible(tester, inCard('Priya Raman', 'Deactivate'));
      await confirmDialog(tester, 'Deactivate staff');

      expect(
        find.text(
          RetailerStaffLifecycleCopy.problemBody(
            RetailerStaffLifecycleProblem.denied,
          ),
        ),
        findsOneWidget,
      );
      expect(staff.memberCallCount, readsBefore);
      // The badge is untouched: nothing was written.
      expect(inCard('Priya Raman', 'Active'), findsOneWidget);
    });

    testWidgets('the denied copy discloses no cause', (
      WidgetTester tester,
    ) async {
      final String copy =
          '${RetailerStaffLifecycleCopy.problemTitle(RetailerStaffLifecycleProblem.denied)} '
          '${RetailerStaffLifecycleCopy.problemBody(RetailerStaffLifecycleProblem.denied)}';

      for (final String forbidden in <String>[
        'owner',
        'yourself',
        'another Retailer',
        'invited',
        'suspended',
        'roles',
        'multi',
        '42501',
      ]) {
        expect(
          copy.toLowerCase(),
          isNot(contains(forbidden.toLowerCase())),
          reason: 'the denied copy must not mention "$forbidden"',
        );
      }
    });

    testWidgets('an unconfirmed write never invites a retry', (
      WidgetTester tester,
    ) async {
      lifecycle.result = const RetailerStaffLifecycleUnconfirmed();
      await onOwnerStaff(tester);

      await tapVisible(tester, inCard('Priya Raman', 'Deactivate'));
      await confirmDialog(tester, 'Deactivate staff');

      final String copy =
          '${RetailerStaffLifecycleCopy.noticeTitle(RetailerStaffLifecycleNotice.unconfirmed)} '
          '${RetailerStaffLifecycleCopy.noticeBody(RetailerStaffLifecycleNotice.unconfirmed)}';
      expect(copy.toLowerCase(), isNot(contains('try again')));
      expect(copy.toLowerCase(), isNot(contains('retry')));
      expect(copy.toLowerCase(), isNot(contains('resubmit')));
      expect(lifecycle.callCount, 1);
    });

    testWidgets('no UUID, SQLSTATE or backend message is ever rendered', (
      WidgetTester tester,
    ) async {
      lifecycle.result = refusedStaffLifecycle(
        RetailerStaffLifecycleProblem.denied,
      );
      await onOwnerStaff(tester);

      await tapVisible(tester, inCard('Priya Raman', 'Deactivate'));
      await confirmDialog(tester, 'Deactivate staff');

      for (final Text widget in tester.widgetList<Text>(find.byType(Text))) {
        final String text = widget.data ?? '';
        for (final String forbidden in <String>[
          priyaMembershipId,
          aminaMembershipId,
          '42501',
          '23514',
          '55000',
          '22P02',
          'organization_members',
          'member_roles',
          'PostgrestException',
          'RETAILER_STAFF_MANAGE',
          'SALES_STAFF',
          'DEACTIVATED',
        ]) {
          expect(
            text,
            isNot(contains(forbidden)),
            reason: '"$text" leaks $forbidden',
          );
        }
      }
    });
  });

  group('an enabled control is never silently ignored', () {
    testWidgets('pressing B while A is pending issues a real request for B', (
      WidgetTester tester,
    ) async {
      lifecycle.manual = true;
      await onOwnerStaff(tester);

      // A is submitting.
      await tapVisible(tester, inCard('Priya Raman', 'Deactivate'));
      await confirmDialog(tester, 'Deactivate staff', settle: false);
      expect(lifecycle.callCount, 1);

      // B's control is visibly enabled…
      expect(inCard('Noor Aziz', 'Deactivate'), findsOneWidget);
      expect(inCard('Noor Aziz', 'Deactivating…'), findsNothing);

      // …and pressing it is genuinely acted on. Under the previous global
      // guard this press opened a dialog, took a confirmation, and did
      // nothing at all.
      await tapVisibleNoSettle(tester, inCard('Noor Aziz', 'Deactivate'));
      await confirmDialog(tester, 'Deactivate staff', settle: false);

      expect(lifecycle.callCount, 2);
      expect(
        lifecycle.writes.map(
          (({String membershipId, RetailerStaffLifecycleStatus status}) w) =>
              w.membershipId,
        ),
        <String>[priyaMembershipId, noorMembershipId],
      );

      lifecycle.complete();
      lifecycle.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('two pending rows each spin, and no other row does', (
      WidgetTester tester,
    ) async {
      lifecycle.manual = true;
      await onOwnerStaff(tester);

      await tapVisible(tester, inCard('Priya Raman', 'Deactivate'));
      await confirmDialog(tester, 'Deactivate staff', settle: false);
      await tapVisibleNoSettle(tester, inCard('Noor Aziz', 'Deactivate'));
      await confirmDialog(tester, 'Deactivate staff', settle: false);

      expect(inCard('Priya Raman', 'Deactivating…'), findsOneWidget);
      expect(inCard('Noor Aziz', 'Deactivating…'), findsOneWidget);
      // The Owner and the suspended member never had a control at all.
      expect(inCard('Amina Farouk', 'Deactivating…'), findsNothing);
      expect(inCard('Tom Byrne', 'Deactivating…'), findsNothing);

      lifecycle.complete();
      lifecycle.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('each row shows only its own outcome', (
      WidgetTester tester,
    ) async {
      lifecycle.manual = true;
      await onOwnerStaff(tester);

      await tapVisible(tester, inCard('Priya Raman', 'Deactivate'));
      await confirmDialog(tester, 'Deactivate staff', settle: false);
      await tapVisibleNoSettle(tester, inCard('Noor Aziz', 'Deactivate'));
      await confirmDialog(tester, 'Deactivate staff', settle: false);

      // A succeeds; B is refused. Completed out of order.
      //
      // Pumped in frames rather than settled after the first completion: A is
      // still in flight, and its progress spinner animates indefinitely by
      // design.
      lifecycle.completeAt(
        1,
        refusedStaffLifecycle(RetailerStaffLifecycleProblem.denied),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      lifecycle.completeAt(0);
      await tester.pumpAndSettle();

      final String successTitle = RetailerStaffLifecycleCopy.noticeTitle(
        RetailerStaffLifecycleNotice.deactivated,
      );
      final String deniedBody = RetailerStaffLifecycleCopy.problemBody(
        RetailerStaffLifecycleProblem.denied,
      );

      expect(inCard('Priya Raman', successTitle), findsOneWidget);
      expect(inCard('Priya Raman', deniedBody), findsNothing);
      expect(inCard('Noor Aziz', deniedBody), findsOneWidget);
      expect(inCard('Noor Aziz', successTitle), findsNothing);
    });

    testWidgets('a second press of the SAME row is refused while pending', (
      WidgetTester tester,
    ) async {
      lifecycle.manual = true;
      await onOwnerStaff(tester);

      await tapVisible(tester, inCard('Priya Raman', 'Deactivate'));
      await confirmDialog(tester, 'Deactivate staff', settle: false);

      // The control is gone — replaced by its own progress label — so there is
      // nothing enabled to press twice.
      expect(inCard('Priya Raman', 'Deactivate'), findsNothing);
      expect(inCard('Priya Raman', 'Deactivating…'), findsOneWidget);
      expect(lifecycle.callCount, 1);

      lifecycle.complete();
      await tester.pumpAndSettle();
      expect(lifecycle.callCount, 1);
    });
  });

  group('scope', () {
    testWidgets('the Manager staff screen has no lifecycle control', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(
        tester,
        PortalKind.retailerManager,
        retailerStaff: staff,
        retailerStaffLifecycle: lifecycle,
      );
      await goTo(tester, RetailerManagerNavigation.staff);

      expect(find.text('Deactivate'), findsNothing);
      expect(find.text('Reactivate'), findsNothing);
    });

    testWidgets('the Sales Staff shell has no lifecycle control', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(
        tester,
        PortalKind.salesStaff,
        retailerStaff: staff,
        retailerStaffLifecycle: lifecycle,
      );
      await goTo(tester, SalesStaffNavigation.submit);

      expect(find.text('Deactivate'), findsNothing);
      expect(find.text('Reactivate'), findsNothing);
    });

    testWidgets('the Vendor shell has no lifecycle control', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(
        tester,
        PortalKind.vendorSuperAdmin,
        retailerStaff: staff,
        retailerStaffLifecycle: lifecycle,
      );

      for (final String location in <String>[
        VendorNavigation.dashboard,
        VendorNavigation.retailers,
        VendorNavigation.users,
      ]) {
        await goTo(tester, location);
        expect(
          find.text('Deactivate staff'),
          findsNothing,
          reason: '$location must carry no staff lifecycle control',
        );
      }
    });

    testWidgets('the control does not overflow a narrow layout', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(tester, surface: smallPhoneSurface);

      expect(inCard('Priya Raman', 'Deactivate'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the dialog body scrolls on a small phone', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(tester, surface: smallPhoneSurface);

      await tapVisible(tester, inCard('Priya Raman', 'Deactivate'));

      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
