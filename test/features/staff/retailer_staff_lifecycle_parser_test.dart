import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/staff/data/models/retailer_staff_lifecycle_parser.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_lifecycle_status.dart';

import '../../support/retailer_staff_lifecycle_fakes.dart';

/// The strict `set_retailer_staff_membership_status` response parser.
///
/// **Null means "committed, but undescribable" — never "nothing happened".**
/// This function is only ever reached when nothing was thrown, which means the
/// transaction committed, so every rejection below describes a response this
/// build cannot trust rather than a write that failed. The repository maps every
/// one of them to `RetailerStaffLifecycleUnconfirmed`.
///
/// Two of these checks are deliberately **stricter than the Web wrapper**, whose
/// `readStatusRow` takes `data[0]` with no length check and never compares the
/// returned `membership_id`: the row-count rule and the id-echo rule.
void main() {
  const String submitted = '11111111-1111-4111-8111-111111111111';
  const String other = '22222222-2222-4222-8222-222222222222';

  RetailerStaffLifecycleRow? parse(Object? raw, [String? expected]) =>
      parseRetailerStaffLifecycleRow(raw, expected ?? submitted);

  group('accepted responses', () {
    test('one valid matching row is accepted', () {
      final RetailerStaffLifecycleRow? row = parse(
        staffLifecycleRows(membershipId: submitted),
      );

      expect(row, isNotNull);
      expect(row!.confirmedStatus, RetailerStaffLifecycleStatus.deactivated);
      expect(row.statusChanged, isTrue);
    });

    test('a reactivation row is accepted', () {
      final RetailerStaffLifecycleRow? row = parse(
        staffLifecycleRows(
          membershipId: submitted,
          membershipStatus: 'ACTIVE',
          statusChanged: false,
        ),
      );

      expect(row!.confirmedStatus, RetailerStaffLifecycleStatus.active);
      // An idempotent no-op is an honest outcome, not a rejection.
      expect(row.statusChanged, isFalse);
    });

    test('an upper-cased matching UUID is accepted', () {
      expect(
        parse(staffLifecycleRows(membershipId: submitted.toUpperCase())),
        isNotNull,
      );
    });

    test('an upper-cased SUBMITTED id is compared on equal terms', () {
      expect(
        parse(
          staffLifecycleRows(membershipId: submitted),
          submitted.toUpperCase(),
        ),
        isNotNull,
      );
    });

    test('a bare single-row map is accepted', () {
      expect(parse(staffLifecycleRow(membershipId: submitted)), isNotNull);
    });

    test('an unrecognised role_code does not fail the row', () {
      // `role_code` is present in the contract and deliberately never read.
      expect(
        parse(
          staffLifecycleRows(membershipId: submitted, roleCode: 'ANYTHING'),
        ),
        isNotNull,
      );
      expect(
        parse(staffLifecycleRows(membershipId: submitted, roleCode: null)),
        isNotNull,
      );
    });
  });

  group('rejected responses become unconfirmed', () {
    test('zero rows', () {
      expect(parse(<Map<String, Object?>>[]), isNull);
    });

    test('multiple rows', () {
      // Two rows would otherwise have the second silently discarded.
      expect(
        parse(<Map<String, Object?>>[
          staffLifecycleRow(membershipId: submitted),
          staffLifecycleRow(membershipId: submitted),
        ]),
        isNull,
      );
    });

    test('a missing membership_id', () {
      expect(parse(<Map<String, Object?>>[<String, Object?>{}]), isNull);
    });

    test('a null or non-string membership_id', () {
      for (final Object? id in <Object?>[
        null,
        42,
        true,
        <String>['a'],
      ]) {
        expect(
          parse(staffLifecycleRows(membershipId: id)),
          isNull,
          reason: 'membership_id $id must be refused',
        );
      }
    });

    test('a malformed UUID', () {
      for (final String id in <String>['not-a-uuid', '', '$submitted-extra']) {
        expect(
          parse(staffLifecycleRows(membershipId: id)),
          isNull,
          reason: 'membership_id "$id" must be refused',
        );
      }
    });

    test('a valid but DIFFERENT membership id', () {
      // The check that makes the other three worth doing: a response describing
      // another colleague must never be rendered as this one's outcome.
      expect(parse(staffLifecycleRows(membershipId: other)), isNull);
    });

    test('an invalid membership_status', () {
      for (final Object? status in <Object?>[
        null,
        '',
        'INACTIVE',
        'SUSPENDED',
        'INVITED',
        'active',
        'PAUSED',
        7,
        true,
      ]) {
        expect(
          parse(
            staffLifecycleRows(
              membershipId: submitted,
              membershipStatus: status,
            ),
          ),
          isNull,
          reason: 'membership_status $status must be refused',
        );
      }
    });

    test('a missing status_changed', () {
      expect(
        parse(<Map<String, Object?>>[
          <String, Object?>{
            'membership_id': submitted,
            'membership_status': 'DEACTIVATED',
            'role_code': 'SALES_STAFF',
          },
        ]),
        isNull,
      );
    });

    test('a non-boolean status_changed', () {
      // Truthy is not enough: the difference between "you did that" and
      // "somebody already had" is decided by this flag.
      for (final Object? changed in <Object?>[null, 'true', 1, 0, <String>[]]) {
        expect(
          parse(
            staffLifecycleRows(membershipId: submitted, statusChanged: changed),
          ),
          isNull,
          reason: 'status_changed $changed must be refused',
        );
      }
    });

    test('a malformed shape never throws', () {
      for (final Object? raw in <Object?>[
        null,
        'a string',
        42,
        true,
        <String>['a', 'b'],
        <String, Object?>{'unexpected': 'shape'},
        <Object?>[null],
        <Object?>[42],
        <Object?>[
          <String>['nested'],
        ],
      ]) {
        expect(
          () => parse(raw),
          returnsNormally,
          reason: '$raw must not throw',
        );
        expect(parse(raw), isNull);
      }
    });
  });

  group('what the parser does not expose', () {
    test('the validated membership id is not carried out', () {
      final RetailerStaffLifecycleRow row = parse(
        staffLifecycleRows(membershipId: submitted),
      )!;

      // The row type has exactly two fields, and neither is an identifier or a
      // role code: both have done their job once the response is trusted.
      expect(
        row.toString().contains(submitted),
        isFalse,
        reason: 'the returned identifier must not survive the parser',
      );
      expect(row.toString().contains('SALES_STAFF'), isFalse);
    });
  });
}
