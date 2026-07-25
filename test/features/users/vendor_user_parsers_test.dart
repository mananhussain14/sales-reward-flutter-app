import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/users/data/models/vendor_user_parsers.dart';
import 'package:sale_reward/features/users/domain/entities/vendor_user_detail.dart';
import 'package:sale_reward/features/users/domain/entities/vendor_user_status.dart';
import 'package:sale_reward/features/users/domain/entities/vendor_user_summary.dart';

import '../../support/vendor_user_fakes.dart';

/// The parsers are the boundary where an untrusted body becomes a trusted
/// value, so almost every test here is a *refusal*.
///
/// The rule they all serve: **a default is a value the backend never sent,
/// presented as though it had.** There is no branch anywhere in these parsers
/// that substitutes one — and the sharpest case is `role_names`, where the wrong
/// guess would not merely be inaccurate but would grant a privilege.
void main() {
  group('summary — the happy path', () {
    test('parses every column of a well-formed row', () {
      final List<VendorUserSummary> parsed = VendorUserSummaryParser.parseList(
        userRows(),
      );

      expect(parsed, hasLength(2));

      final VendorUserSummary first = parsed.first;
      expect(first.membershipId, aminaMembershipUuid);
      expect(first.displayName, 'Amina Rahman');
      expect(first.profileStatus, VendorUserStatus.active);
      expect(first.membershipStatus, VendorUserStatus.active);
      expect(first.membershipCreatedAt, DateTime.utc(2026, 1, 14, 9, 5));
      expect(first.joinedAt, DateTime.utc(2026, 1, 15, 10, 30));
      expect(first.roleNames, <String>['Finance Admin', 'Vendor Super Admin']);
      expect(first.hasNoRoles, isFalse);
    });

    test('preserves the backend order rather than re-sorting', () {
      // The SQL orders by display_name then membership_id, in the database
      // collation. Re-sorting here would be a second definition of "the
      // directory order" using a different collation, and the two clients would
      // disagree.
      final List<VendorUserSummary> parsed =
          VendorUserSummaryParser.parseList(<Map<String, Object?>>[
            userRow(displayName: 'Zoe Adeyemi'),
            userRow(membershipId: joMembershipUuid, displayName: 'Aaron Bell'),
          ]);

      expect(parsed.map((VendorUserSummary u) => u.displayName), <String>[
        'Zoe Adeyemi',
        'Aaron Bell',
      ]);
    });

    test('an empty response is an empty list, not an error', () {
      // Not reachable while the caller is authorized — their own row is always
      // present — but a match-nothing query is still an empty set, not a raise.
      expect(VendorUserSummaryParser.parseList(const <Object?>[]), isEmpty);
    });

    test('a single-user directory parses', () {
      // The real "no colleagues" case: a Vendor whose only user is its
      // administrator returns exactly one row.
      expect(
        VendorUserSummaryParser.parseList(<Map<String, Object?>>[userRow()]),
        hasLength(1),
      );
    });

    test('normalizes a non-UTC timestamp to UTC', () {
      final VendorUserSummary parsed = VendorUserSummaryParser.parse(
        userRow(createdAt: '2026-01-14T13:05:00+04:00'),
      );

      expect(parsed.membershipCreatedAt.isUtc, isTrue);
      expect(parsed.membershipCreatedAt, DateTime.utc(2026, 1, 14, 9, 5));
    });
  });

  group('summary — every status the backend can send', () {
    for (final (String token, VendorUserStatus expected)
        in <(String, VendorUserStatus)>[
          ('INVITED', VendorUserStatus.invited),
          ('ACTIVE', VendorUserStatus.active),
          ('SUSPENDED', VendorUserStatus.suspended),
          ('DEACTIVATED', VendorUserStatus.deactivated),
        ]) {
      test('$token maps to $expected on both status columns', () {
        final VendorUserSummary parsed = VendorUserSummaryParser.parse(
          userRow(profileStatus: token, membershipStatus: token),
        );

        expect(parsed.profileStatus, expected);
        expect(parsed.membershipStatus, expected);
      });
    }

    test('the two statuses are independent', () {
      // The backend is explicit that they are separate facts about separate
      // rows. An ACTIVE profile with a SUSPENDED membership here is exactly the
      // case an administrator opens this screen to find.
      final VendorUserSummary parsed = VendorUserSummaryParser.parse(
        userRow(profileStatus: 'ACTIVE', membershipStatus: 'SUSPENDED'),
      );

      expect(parsed.profileStatus, VendorUserStatus.active);
      expect(parsed.membershipStatus, VendorUserStatus.suspended);
      expect(parsed.profileStatus.isActive, isTrue);
      expect(parsed.membershipStatus.isActive, isFalse);
    });
  });

  group('summary — an unknown token degrades, and never upward', () {
    test('an unrecognised status is unknown, and unknown is not active', () {
      final VendorUserSummary parsed = VendorUserSummaryParser.parse(
        userRow(profileStatus: 'ARCHIVED', membershipStatus: 'PENDING_REVIEW'),
      );

      expect(parsed.profileStatus, VendorUserStatus.unknown);
      expect(parsed.membershipStatus, VendorUserStatus.unknown);
      expect(parsed.profileStatus.isActive, isFalse);
      expect(parsed.membershipStatus.isActive, isFalse);
      expect(parsed.membershipStatus.isInvited, isFalse);
    });

    test('the user is still parsed — never dropped from the directory', () {
      // Losing sight of a colleague because their status is unfamiliar would be
      // worse than showing it plainly.
      final List<VendorUserSummary> parsed = VendorUserSummaryParser.parseList(
        <Map<String, Object?>>[userRow(membershipStatus: 'ARCHIVED')],
      );

      expect(parsed, hasLength(1));
      expect(parsed.single.displayName, 'Amina Rahman');
    });

    test('a lower-case token is not accepted as its upper-case twin', () {
      expect(
        VendorUserSummaryParser.parse(
          userRow(membershipStatus: 'active'),
        ).membershipStatus,
        VendorUserStatus.unknown,
      );
    });

    test('the raw token is not retained anywhere on the entity', () {
      final VendorUserSummary parsed = VendorUserSummaryParser.parse(
        userRow(membershipStatus: 'ARCHIVED'),
      );

      expect(parsed.membershipStatus.code, isEmpty);
      expect(parsed.toString(), isNot(contains('ARCHIVED')));
    });
  });

  group('role_names — the array whose wrong guess would grant something', () {
    test('a single role parses', () {
      expect(
        VendorUserSummaryParser.parse(
          userRow(roleNames: const <Object?>['Finance Admin']),
        ).roleNames,
        <String>['Finance Admin'],
      );
    });

    test('several roles keep the backend order exactly', () {
      // Ordered by role name then role id in SQL. Nothing re-sorts it here.
      expect(
        VendorUserSummaryParser.parse(
          userRow(
            roleNames: const <Object?>['Zeta Role', 'Alpha Role', 'Mid Role'],
          ),
        ).roleNames,
        <String>['Zeta Role', 'Alpha Role', 'Mid Role'],
      );
    });

    test('an empty array stays empty, and is never a privilege', () {
      final VendorUserSummary parsed = VendorUserSummaryParser.parse(
        userRow(roleNames: const <Object?>[]),
      );

      expect(parsed.roleNames, isEmpty);
      expect(parsed.hasNoRoles, isTrue);
      // The one guess that would matter.
      expect(parsed.roleNames, isNot(contains('Vendor Super Admin')));
    });

    test('duplicates are preserved rather than collapsed', () {
      // A Set would hide a genuine backend duplication bug rather than prevent
      // one; the SQL cannot produce duplicates, so seeing them is information.
      expect(
        VendorUserSummaryParser.parse(
          userRow(roleNames: const <Object?>['Finance Admin', 'Finance Admin']),
        ).roleNames,
        <String>['Finance Admin', 'Finance Admin'],
      );
    });

    test('a null array is refused, never read as "no roles"', () {
      // The SQL coalesces the aggregate to '{}', so null is not "no roles" — it
      // is a response this build was not written against.
      expect(
        () => VendorUserSummaryParser.parse(userRow(roleNames: null)),
        throwsA(isA<VendorUserFormatException>()),
      );
    });

    test('a missing array is refused', () {
      final Map<String, Object?> row = userRow()..remove('role_names');
      expect(
        () => VendorUserSummaryParser.parse(row),
        throwsA(isA<VendorUserFormatException>()),
      );
    });

    test('an array that is not a list is refused', () {
      expect(
        () => VendorUserSummaryParser.parse(
          userRow(roleNames: 'Vendor Super Admin'),
        ),
        throwsA(isA<VendorUserFormatException>()),
      );
    });

    test('a non-string entry is refused', () {
      expect(
        () => VendorUserSummaryParser.parse(
          userRow(roleNames: const <Object?>['Finance Admin', 7]),
        ),
        throwsA(isA<VendorUserFormatException>()),
      );
    });

    test('a null entry is refused', () {
      expect(
        () => VendorUserSummaryParser.parse(
          userRow(roleNames: const <Object?>['Finance Admin', null]),
        ),
        throwsA(isA<VendorUserFormatException>()),
      );
    });

    test('a blank entry is refused', () {
      expect(
        () => VendorUserSummaryParser.parse(
          userRow(roleNames: const <Object?>['   ']),
        ),
        throwsA(isA<VendorUserFormatException>()),
      );
    });

    test('a nested array is refused', () {
      expect(
        () => VendorUserSummaryParser.parse(
          userRow(
            roleNames: const <Object?>[
              <Object?>['Finance Admin'],
            ],
          ),
        ),
        throwsA(isA<VendorUserFormatException>()),
      );
    });
  });

  group('summary — nullable joined_at', () {
    test('null is a real answer and is preserved', () {
      final VendorUserSummary parsed = VendorUserSummaryParser.parse(
        userRow(joinedAt: null),
      );

      expect(parsed.joinedAt, isNull);
      // And it is emphatically not the creation date wearing a different name.
      expect(parsed.membershipCreatedAt, isNotNull);
    });

    test('a missing key is the same as null', () {
      final Map<String, Object?> row = userRow()..remove('joined_at');
      expect(VendorUserSummaryParser.parse(row).joinedAt, isNull);
    });

    test('a malformed value is refused, never quietly dropped to null', () {
      // Dropping it would turn an unreadable date into a confident "not joined
      // yet", which is a claim about a person's state.
      expect(
        () => VendorUserSummaryParser.parse(userRow(joinedAt: 'yesterday')),
        throwsA(isA<VendorUserFormatException>()),
      );
    });

    test('a non-string value is refused', () {
      expect(
        () => VendorUserSummaryParser.parse(userRow(joinedAt: 1773907200)),
        throwsA(isA<VendorUserFormatException>()),
      );
    });
  });

  group('summary — a malformed row is refused, never patched', () {
    void expectRefused(String what, Map<String, Object?> row) {
      test(what, () {
        expect(
          () => VendorUserSummaryParser.parse(row),
          throwsA(isA<VendorUserFormatException>()),
        );
      });
    }

    expectRefused(
      'a malformed membership UUID',
      userRow(membershipId: 'not-a-uuid'),
    );
    expectRefused(
      'a membership UUID of the wrong length',
      userRow(membershipId: '8a1b2c3d-4e5f-4061-9273-8495a6b7c8'),
    );
    expectRefused('an empty membership id', userRow(membershipId: ''));
    expectRefused('a missing membership id', userRow(membershipId: null));
    expectRefused('a numeric membership id', userRow(membershipId: 12345));
    expectRefused('a missing display name', userRow(displayName: null));
    expectRefused('a blank display name', userRow(displayName: '   '));
    expectRefused('a display name of the wrong type', userRow(displayName: 42));
    expectRefused('a missing profile status', userRow(profileStatus: null));
    expectRefused(
      'a missing membership status',
      userRow(membershipStatus: null),
    );
    expectRefused('a blank profile status', userRow(profileStatus: ''));
    expectRefused(
      'a malformed membership_created_at',
      userRow(createdAt: '14 January 2026'),
    );
    expectRefused('a null membership_created_at', userRow(createdAt: null));
    expectRefused(
      'a numeric membership_created_at',
      userRow(createdAt: 1773907200),
    );

    test('a body that is not a list', () {
      expect(
        () => VendorUserSummaryParser.parseList(<String, Object?>{}),
        throwsA(isA<VendorUserFormatException>()),
      );
    });

    test('a row that is not an object', () {
      expect(
        () => VendorUserSummaryParser.parseList(<Object?>['nope']),
        throwsA(isA<VendorUserFormatException>()),
      );
    });

    test('one malformed row fails the whole list', () {
      // A partially-rendered directory is a directory silently missing people,
      // which is worse than a retry.
      expect(
        () => VendorUserSummaryParser.parseList(<Map<String, Object?>>[
          userRow(),
          userRow(membershipId: 'broken'),
        ]),
        throwsA(isA<VendorUserFormatException>()),
      );
    });
  });

  group('detail — the single-row read', () {
    test('parses the list columns plus deactivated_at', () {
      final VendorUserDetail? parsed = VendorUserDetailParser.parseSingle(
        <Map<String, Object?>>[
          userDetailRow(deactivatedAt: '2026-07-20T16:45:00+00:00'),
        ],
      );

      expect(parsed, isNotNull);
      expect(parsed!.membershipId, aminaMembershipUuid);
      expect(parsed.displayName, 'Amina Rahman');
      expect(parsed.profileStatus, VendorUserStatus.active);
      expect(parsed.membershipStatus, VendorUserStatus.active);
      expect(parsed.membershipCreatedAt, DateTime.utc(2026, 1, 14, 9, 5));
      expect(parsed.joinedAt, DateTime.utc(2026, 1, 15, 10, 30));
      expect(parsed.deactivatedAt, DateTime.utc(2026, 7, 20, 16, 45));
      expect(parsed.roleNames, <String>['Finance Admin', 'Vendor Super Admin']);
    });

    test('the shared columns parse identically to the list', () {
      // The backend pins the detail contract as "the list plus one column", so
      // one body parsed by both parsers must agree on every shared field.
      final Map<String, Object?> row = userDetailRow();
      final VendorUserSummary summary = VendorUserSummaryParser.parse(row);
      final VendorUserDetail detail = VendorUserDetailParser.parse(row);

      expect(detail.membershipId, summary.membershipId);
      expect(detail.displayName, summary.displayName);
      expect(detail.profileStatus, summary.profileStatus);
      expect(detail.membershipStatus, summary.membershipStatus);
      expect(detail.membershipCreatedAt, summary.membershipCreatedAt);
      expect(detail.joinedAt, summary.joinedAt);
      expect(detail.roleNames, summary.roleNames);
    });

    test('zero rows is null — the one non-leaking answer', () {
      // An unknown id, another Vendor's id, a Retailer-owned membership id and
      // a null id all produce zero rows in SQL. One representation for all four
      // is what keeps this from being an existence oracle.
      expect(VendorUserDetailParser.parseSingle(const <Object?>[]), isNull);
    });

    test('a null deactivated_at is a live membership', () {
      final VendorUserDetail? parsed = VendorUserDetailParser.parseSingle(
        <Map<String, Object?>>[userDetailRow()],
      );

      expect(parsed!.deactivatedAt, isNull);
    });

    test('a missing deactivated_at key is the same as null', () {
      final Map<String, Object?> row = userDetailRow()
        ..remove('deactivated_at');
      expect(VendorUserDetailParser.parse(row).deactivatedAt, isNull);
    });

    test('a malformed deactivated_at is refused', () {
      expect(
        () => VendorUserDetailParser.parseSingle(<Map<String, Object?>>[
          userDetailRow(deactivatedAt: 'last week'),
        ]),
        throwsA(isA<VendorUserFormatException>()),
      );
    });

    test('a null joined_at with a set deactivated_at is legitimate', () {
      // Somebody recorded, deactivated, and never joined. Neither date is
      // inferred from the other, nor from the status.
      final VendorUserDetail? parsed = VendorUserDetailParser.parseSingle(
        <Map<String, Object?>>[
          userDetailRow(
            joinedAt: null,
            deactivatedAt: '2026-07-20T16:45:00+00:00',
          ),
        ],
      );

      expect(parsed!.joinedAt, isNull);
      expect(parsed.deactivatedAt, isNotNull);
    });

    test('an empty role array parses on the detail too', () {
      final VendorUserDetail? parsed = VendorUserDetailParser.parseSingle(
        <Map<String, Object?>>[userDetailRow(roleNames: const <Object?>[])],
      );

      expect(parsed!.roleNames, isEmpty);
      expect(parsed.hasNoRoles, isTrue);
    });

    test('a null role array is refused on the detail too', () {
      expect(
        () => VendorUserDetailParser.parseSingle(<Map<String, Object?>>[
          userDetailRow(roleNames: null),
        ]),
        throwsA(isA<VendorUserFormatException>()),
      );
    });

    test('several rows are refused — the function filters on a key', () {
      expect(
        () => VendorUserDetailParser.parseSingle(<Map<String, Object?>>[
          userDetailRow(),
          userDetailRow(),
        ]),
        throwsA(isA<VendorUserFormatException>()),
      );
    });

    test('an unknown status on the detail is unknown, not active', () {
      final VendorUserDetail? parsed = VendorUserDetailParser.parseSingle(
        <Map<String, Object?>>[userDetailRow(membershipStatus: 'ARCHIVED')],
      );

      expect(parsed!.membershipStatus, VendorUserStatus.unknown);
      expect(parsed.membershipStatus.isActive, isFalse);
    });

    test('a malformed membership id is refused on the detail too', () {
      expect(
        () => VendorUserDetailParser.parseSingle(<Map<String, Object?>>[
          userDetailRow(membershipId: 'nope'),
        ]),
        throwsA(isA<VendorUserFormatException>()),
      );
    });
  });

  group('the id-shape guard', () {
    test('accepts a well-formed UUID in either case', () {
      expect(isMembershipIdShaped(aminaMembershipUuid), isTrue);
      expect(isMembershipIdShaped(aminaMembershipUuid.toUpperCase()), isTrue);
    });

    test('refuses everything else', () {
      for (final String malformed in <String>[
        '',
        '   ',
        'null',
        '1',
        'undefined',
        'me',
        '8a1b2c3d-4e5f-4061-9273-8495a6b7c8d',
        '8a1b2c3d-4e5f-4061-9273-8495a6b7c8d90',
        "8a1b2c3d-4e5f-4061-9273-8495a6b7c8d9' or '1'='1",
      ]) {
        expect(
          isMembershipIdShaped(malformed),
          isFalse,
          reason: '$malformed must not pass as a membership id',
        );
      }
    });
  });

  group('no privileged default exists anywhere', () {
    test('an empty row is refused rather than assembled from defaults', () {
      expect(
        () => VendorUserSummaryParser.parse(const <String, Object?>{}),
        throwsA(isA<VendorUserFormatException>()),
      );
      expect(
        () => VendorUserDetailParser.parse(const <String, Object?>{}),
        throwsA(isA<VendorUserFormatException>()),
      );
    });

    test('the unknown member carries no backend token', () {
      expect(VendorUserStatus.unknown.code, isEmpty);
    });

    test('fromCode never returns a member for an empty token', () {
      // The empty string is `unknown`'s own code; matching it would let a blank
      // value select a real member by accident.
      expect(VendorUserStatus.fromCode(''), VendorUserStatus.unknown);
    });

    test('no status maps to active except ACTIVE itself', () {
      for (final VendorUserStatus status in VendorUserStatus.values) {
        expect(
          status.isActive,
          status == VendorUserStatus.active,
          reason: '$status must not report itself active',
        );
      }
    });

    test('the parsers expose no email, phone or identity field', () {
      // Belt and braces over the entity surface: a body carrying these must not
      // produce an entity that holds them.
      final VendorUserSummary parsed =
          VendorUserSummaryParser.parse(<String, Object?>{
            ...userRow(),
            'email': 'someone@example.com',
            'mobile_number': '+10000000000',
            'user_id': aminaMembershipUuid,
          });

      expect(parsed.props, hasLength(7));
      expect(parsed.toString(), isNot(contains('@example.com')));
      expect(parsed.toString(), isNot(contains('+10000000000')));
    });
  });
}
