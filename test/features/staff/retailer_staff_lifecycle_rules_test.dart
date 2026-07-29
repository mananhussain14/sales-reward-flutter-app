import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_lifecycle_action.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_lifecycle_status.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_member.dart';

/// The pure lifecycle rules, with no I/O and no widget.
///
/// The **whole-roster** rules are the point of this file. `list_retailer_staff_
/// members()` joins `member_roles` and `roles` without `DISTINCT`, so a
/// multi-role membership arrives as several rows sharing one id — and a per-row
/// predicate would offer the control for targets the RPC refuses, including on
/// the non-Owner row of an Owner.
void main() {
  const String managerId = '11111111-1111-4111-8111-111111111111';
  const String salesId = '22222222-2222-4222-8222-222222222222';
  const String ownerId = '33333333-3333-4333-8333-333333333333';
  const String dualId = '44444444-4444-4444-8444-444444444444';

  RetailerStaffMember member({
    required String membershipId,
    required String roleCode,
    String status = 'ACTIVE',
    String firstName = 'Sam',
  }) => RetailerStaffMember(
    membershipId: membershipId,
    firstName: firstName,
    lastName: 'Taylor',
    roleCode: roleCode,
    roleName: roleCode,
    status: RetailerMemberStatus.fromCode(status),
    shopIds: const <String>[],
    shopNames: const <String>[],
    joinedAt: DateTime.utc(2026, 3, 1),
    createdAt: DateTime.utc(2026, 2, 1),
  );

  Set<String> eligible(List<RetailerStaffMember> roster) =>
      RetailerStaffLifecycleEligibility.eligibleMemberships(roster);

  RetailerStaffLifecycleAction? actionFor(
    RetailerStaffMember target,
    List<RetailerStaffMember> roster,
  ) => RetailerStaffLifecycleEligibility.actionFor(target, eligible(roster));

  group('eligible single-role memberships', () {
    test('an ACTIVE Manager is eligible', () {
      final RetailerStaffMember m = member(
        membershipId: managerId,
        roleCode: 'RETAILER_MANAGER',
      );
      expect(eligible(<RetailerStaffMember>[m]), <String>{managerId});
    });

    test('an ACTIVE Sales Staff member is eligible', () {
      final RetailerStaffMember m = member(
        membershipId: salesId,
        roleCode: 'SALES_STAFF',
      );
      expect(eligible(<RetailerStaffMember>[m]), <String>{salesId});
    });

    test('a DEACTIVATED Manager is eligible', () {
      final RetailerStaffMember m = member(
        membershipId: managerId,
        roleCode: 'RETAILER_MANAGER',
        status: 'DEACTIVATED',
      );
      expect(eligible(<RetailerStaffMember>[m]), <String>{managerId});
    });

    test('a DEACTIVATED Sales Staff member is eligible', () {
      final RetailerStaffMember m = member(
        membershipId: salesId,
        roleCode: 'SALES_STAFF',
        status: 'DEACTIVATED',
      );
      expect(eligible(<RetailerStaffMember>[m]), <String>{salesId});
    });
  });

  group('the transition table', () {
    test('ACTIVE offers Deactivate and requests DEACTIVATED', () {
      final RetailerStaffMember m = member(
        membershipId: salesId,
        roleCode: 'SALES_STAFF',
      );
      final RetailerStaffLifecycleAction a = actionFor(m, <RetailerStaffMember>[
        m,
      ])!;

      expect(a.displayLabel, 'Active');
      expect(a.actionLabel, 'Deactivate');
      expect(a.dialogTitle, 'Deactivate staff');
      expect(a.confirmLabel, 'Deactivate staff');
      expect(a.pendingLabel, 'Deactivating…');
      expect(a.requestedStatus, RetailerStaffLifecycleStatus.deactivated);
      expect(a.requestedStatus.code, 'DEACTIVATED');
      expect(a.isDeactivation, isTrue);
    });

    test('DEACTIVATED offers Reactivate and requests ACTIVE', () {
      final RetailerStaffMember m = member(
        membershipId: salesId,
        roleCode: 'SALES_STAFF',
        status: 'DEACTIVATED',
      );
      final RetailerStaffLifecycleAction a = actionFor(m, <RetailerStaffMember>[
        m,
      ])!;

      expect(a.displayLabel, 'Inactive');
      expect(a.actionLabel, 'Reactivate');
      expect(a.dialogTitle, 'Reactivate staff');
      expect(a.confirmLabel, 'Reactivate staff');
      expect(a.pendingLabel, 'Reactivating…');
      expect(a.requestedStatus, RetailerStaffLifecycleStatus.active);
      expect(a.requestedStatus.code, 'ACTIVE');
      expect(a.isDeactivation, isFalse);
    });

    test('the requested status is the opposite of the current one', () {
      for (final String status in <String>['ACTIVE', 'DEACTIVATED']) {
        final RetailerStaffMember m = member(
          membershipId: salesId,
          roleCode: 'SALES_STAFF',
          status: status,
        );
        final RetailerStaffLifecycleAction a = actionFor(
          m,
          <RetailerStaffMember>[m],
        )!;
        expect(a.requestedStatus, isNot(a.currentStatus));
      }
    });
  });

  group('excluded roles and statuses', () {
    test('a Retailer Owner is excluded', () {
      final RetailerStaffMember m = member(
        membershipId: ownerId,
        roleCode: 'RETAILER_OWNER',
      );
      expect(eligible(<RetailerStaffMember>[m]), isEmpty);
    });

    test('an unsupported or unknown role is excluded', () {
      for (final String role in <String>[
        'VENDOR_SUPER_ADMIN',
        'AUDITOR',
        '',
        'sales_staff',
      ]) {
        final RetailerStaffMember m = member(
          membershipId: salesId,
          roleCode: role,
        );
        expect(
          eligible(<RetailerStaffMember>[m]),
          isEmpty,
          reason: 'role "$role" must be excluded',
        );
      }
    });

    test('an INVITED membership is excluded', () {
      final RetailerStaffMember m = member(
        membershipId: salesId,
        roleCode: 'SALES_STAFF',
        status: 'INVITED',
      );
      expect(eligible(<RetailerStaffMember>[m]), isEmpty);
    });

    test('a SUSPENDED membership is excluded', () {
      final RetailerStaffMember m = member(
        membershipId: salesId,
        roleCode: 'SALES_STAFF',
        status: 'SUSPENDED',
      );
      expect(eligible(<RetailerStaffMember>[m]), isEmpty);
    });

    test('an unknown, blank or INACTIVE status is excluded', () {
      for (final String status in <String>[
        '',
        'INACTIVE',
        'PAUSED',
        'active',
        'deactivated',
      ]) {
        final RetailerStaffMember m = member(
          membershipId: salesId,
          roleCode: 'SALES_STAFF',
          status: status,
        );
        expect(
          eligible(<RetailerStaffMember>[m]),
          isEmpty,
          reason: 'status "$status" must be excluded',
        );
      }
    });

    test('a blank membership id is never a key', () {
      final RetailerStaffMember m = member(
        membershipId: '   ',
        roleCode: 'SALES_STAFF',
      );
      expect(eligible(<RetailerStaffMember>[m]), isEmpty);
    });
  });

  group('the duplicate-membership rule', () {
    /// Two roster rows sharing one membership id — the shape the roster RPC
    /// produces for a member holding two ACTIVE roles.
    List<RetailerStaffMember> dual(String roleA, String roleB) =>
        <RetailerStaffMember>[
          member(membershipId: dualId, roleCode: roleA),
          member(membershipId: dualId, roleCode: roleB),
        ];

    test('Owner + Sales Staff hides the action on BOTH rows', () {
      final List<RetailerStaffMember> roster = dual(
        'RETAILER_OWNER',
        'SALES_STAFF',
      );

      expect(eligible(roster), isEmpty);
      // The dangerous half: the SALES_STAFF row looks eligible on its own, and
      // would defeat the Owner exclusion if judged in isolation.
      expect(actionFor(roster[0], roster), isNull);
      expect(actionFor(roster[1], roster), isNull);
    });

    test('Owner + Manager hides the action on BOTH rows', () {
      final List<RetailerStaffMember> roster = dual(
        'RETAILER_OWNER',
        'RETAILER_MANAGER',
      );

      expect(eligible(roster), isEmpty);
      expect(actionFor(roster[0], roster), isNull);
      expect(actionFor(roster[1], roster), isNull);
    });

    test('Manager + Sales Staff hides the action on BOTH rows', () {
      final List<RetailerStaffMember> roster = dual(
        'RETAILER_MANAGER',
        'SALES_STAFF',
      );

      // Both rows are individually eligible. The RPC still refuses the target,
      // because it compares the COMPLETE ACTIVE role set to a single-element
      // array — so neither row may offer the control.
      expect(eligible(roster), isEmpty);
      expect(actionFor(roster[0], roster), isNull);
      expect(actionFor(roster[1], roster), isNull);
    });

    test('every repeated membership id is excluded, whatever the cause', () {
      // A historical duplicate of one identical row. The rule is deliberately
      // blind to WHY a membership appears twice.
      final List<RetailerStaffMember> roster = <RetailerStaffMember>[
        member(membershipId: dualId, roleCode: 'SALES_STAFF'),
        member(membershipId: dualId, roleCode: 'SALES_STAFF'),
      ];

      expect(eligible(roster), isEmpty);
    });

    test('three rows for one membership are excluded too', () {
      final List<RetailerStaffMember> roster = <RetailerStaffMember>[
        member(membershipId: dualId, roleCode: 'RETAILER_OWNER'),
        member(membershipId: dualId, roleCode: 'RETAILER_MANAGER'),
        member(membershipId: dualId, roleCode: 'SALES_STAFF'),
      ];

      expect(eligible(roster), isEmpty);
    });

    test('ids differing only in case count as ONE membership', () {
      // Two spellings of one id must not read as two unique memberships, which
      // would turn a genuine duplicate into two apparently-eligible rows.
      final List<RetailerStaffMember> roster = <RetailerStaffMember>[
        member(membershipId: dualId, roleCode: 'RETAILER_OWNER'),
        member(membershipId: dualId.toUpperCase(), roleCode: 'SALES_STAFF'),
      ];

      expect(eligible(roster), isEmpty);
      expect(actionFor(roster[1], roster), isNull);
    });

    test('a unique eligible membership beside duplicated ones still works', () {
      final RetailerStaffMember unique = member(
        membershipId: salesId,
        roleCode: 'SALES_STAFF',
        firstName: 'Alex',
      );
      final List<RetailerStaffMember> roster = <RetailerStaffMember>[
        // A duplicated Owner+Sales member.
        member(membershipId: dualId, roleCode: 'RETAILER_OWNER'),
        member(membershipId: dualId, roleCode: 'SALES_STAFF'),
        // A duplicated Manager+Sales member.
        member(membershipId: managerId, roleCode: 'RETAILER_MANAGER'),
        member(membershipId: managerId, roleCode: 'SALES_STAFF'),
        // And one clean row.
        unique,
      ];

      expect(eligible(roster), <String>{salesId});
      expect(actionFor(unique, roster), isNotNull);
      expect(actionFor(roster[0], roster), isNull);
      expect(actionFor(roster[2], roster), isNull);
    });

    test('an empty roster yields no eligible memberships', () {
      expect(eligible(const <RetailerStaffMember>[]), isEmpty);
    });
  });

  group('the request vocabulary is closed', () {
    test('only ACTIVE and DEACTIVATED exist', () {
      expect(
        RetailerStaffLifecycleStatus.values.map(
          (RetailerStaffLifecycleStatus s) => s.code,
        ),
        <String>['ACTIVE', 'DEACTIVATED'],
      );
    });

    test('INACTIVE is not a request value', () {
      expect(RetailerStaffLifecycleStatus.tryParse('INACTIVE'), isNull);
    });

    test('SUSPENDED is not a request value', () {
      expect(RetailerStaffLifecycleStatus.tryParse('SUSPENDED'), isNull);
    });

    test(
      'INVITED, lower case, blank and non-strings are not request values',
      () {
        for (final Object? value in <Object?>[
          'INVITED',
          'active',
          'deactivated',
          '',
          ' ACTIVE',
          null,
          1,
          true,
        ]) {
          expect(
            RetailerStaffLifecycleStatus.tryParse(value),
            isNull,
            reason: '$value must not parse',
          );
        }
      },
    );

    test('every offered action requests a token the RPC accepts', () {
      for (final String status in <String>['ACTIVE', 'DEACTIVATED']) {
        final RetailerStaffMember m = member(
          membershipId: salesId,
          roleCode: 'SALES_STAFF',
          status: status,
        );
        final RetailerStaffLifecycleAction a = actionFor(
          m,
          <RetailerStaffMember>[m],
        )!;
        expect(<String>[
          'ACTIVE',
          'DEACTIVATED',
        ], contains(a.requestedStatus.code));
        expect(a.requestedStatus.code, isNot('INACTIVE'));
        expect(a.requestedStatus.code, isNot('SUSPENDED'));
        expect(a.requestedStatus.code, isNot('INVITED'));
      }
    });
  });

  group('staff status terminology', () {
    test('DEACTIVATED displays Inactive', () {
      expect(RetailerMemberStatus.deactivated.label, 'Inactive');
    });

    test('SUSPENDED remains Suspended', () {
      expect(RetailerMemberStatus.suspended.label, 'Suspended');
    });

    test('SUSPENDED and DEACTIVATED are not collapsed', () {
      // One is reversible by this very control; the other the RPC refuses in
      // both directions. Two words, so a reader can tell which is which.
      expect(
        RetailerMemberStatus.suspended.label,
        isNot(RetailerMemberStatus.deactivated.label),
      );
    });

    test('ACTIVE displays Active and INVITED displays Invited', () {
      expect(RetailerMemberStatus.active.label, 'Active');
      expect(RetailerMemberStatus.invited.label, 'Invited');
    });

    test('no staff label leaks a raw backend token', () {
      for (final RetailerMemberStatus status in RetailerMemberStatus.values) {
        expect(status.label, isNot('ACTIVE'));
        expect(status.label, isNot('DEACTIVATED'));
        expect(status.label, isNot('SUSPENDED'));
        expect(status.label, isNot('INVITED'));
      }
    });
  });
}
