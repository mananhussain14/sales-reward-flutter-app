import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/parsing/rpc_row.dart';
import 'package:sale_reward/features/staff/data/models/retailer_staff_parsers.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_invitation.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_member.dart';

/// `list_retailer_staff_members()` and `list_retailer_staff_invitations()` body
/// parsing.
///
/// Two properties carry most of the weight here.
///
/// **The roster's two identifier columns are read strictly, and no other
/// identifier survives.** `membership_id` and `shop_ids` are carried, because
/// the shop editor addresses a membership with one and preselects from the
/// other — so both are validated as uuids and a malformation fails the row,
/// unlike the display columns beside them. `invitation_id` is still dropped
/// entirely; nothing addresses an invitation.
///
/// **`derived_state` may legitimately be null**, because the backend's `CASE`
/// has no `ELSE` branch.
void main() {
  Matcher throwsFormat() => throwsA(isA<RpcFormatException>());

  // -------------------------------------------------------------------------
  group('roster', () {
    Map<String, Object?> row({
      Object? firstName = 'Priya',
      Object? lastName = 'Raman',
      Object? roleCode = 'SALES_STAFF',
      Object? roleName = 'Sales Staff',
      Object? membershipStatus = 'ACTIVE',
      Object? shopIds = const <Object?>['11111111-1111-1111-1111-111111111111'],
      Object? shopNames = const <Object?>['Northwind Marina'],
      Object? joinedAt = '2026-04-12T09:00:00Z',
      Object? createdAt = '2026-04-10T09:00:00Z',
    }) => <String, Object?>{
      'membership_id': '22222222-2222-2222-2222-222222222222',
      'first_name': firstName,
      'last_name': lastName,
      'role_code': roleCode,
      'role_name': roleName,
      'membership_status': membershipStatus,
      'shop_ids': shopIds,
      'shop_names': shopNames,
      'joined_at': joinedAt,
      'created_at': createdAt,
    };

    test('a valid Owner roster row parses every displayed field', () {
      final RetailerStaffMember m = RetailerStaffMemberParser.parse(<Object?>[
        row(),
      ]).single;

      expect(m.firstName, 'Priya');
      expect(m.lastName, 'Raman');
      expect(m.fullName, 'Priya Raman');
      expect(m.roleCode, 'SALES_STAFF');
      expect(m.roleName, 'Sales Staff');
      expect(m.status, RetailerMemberStatus.active);
      expect(m.membershipId, '22222222-2222-2222-2222-222222222222');
      expect(m.shopIds, <String>['11111111-1111-1111-1111-111111111111']);
      expect(m.shopNames, <String>['Northwind Marina']);
      expect(m.joinedAt, DateTime.utc(2026, 4, 12, 9));
      expect(m.createdAt, DateTime.utc(2026, 4, 10, 9));
    });

    test('the Manager roster is the same shape, just fewer rows', () {
      // The narrowing is `and (v_can_manage or m.status = 'ACTIVE')` in SQL.
      // The client parses whatever it is given and applies no filter — so an
      // all-ACTIVE body parses exactly like a mixed one.
      final List<RetailerStaffMember> members = RetailerStaffMemberParser.parse(
        <Object?>[row(), row(firstName: 'Amina', lastName: 'Farouk')],
      );

      expect(members, hasLength(2));
      expect(
        members.every((RetailerStaffMember m) => m.status.isActive),
        isTrue,
      );
    });

    test('an empty roster is a real answer', () {
      expect(RetailerStaffMemberParser.parse(<Object?>[]), isEmpty);
    });

    test('a null joined_at parses as an absence, not as created_at', () {
      // A membership created by an invitation that was never accepted has no
      // joining date. Substituting created_at would state a day the person
      // joined on when they have not joined.
      final RetailerStaffMember m = RetailerStaffMemberParser.parse(<Object?>[
        row(joinedAt: null),
      ]).single;

      expect(m.joinedAt, isNull);
      expect(m.createdAt, isNotNull);
    });

    test('an unparseable joined_at is rejected, unlike a null one', () {
      expect(
        () => RetailerStaffMemberParser.parse(<Object?>[
          row(joinedAt: 'not-a-date'),
        ]),
        throwsFormat(),
      );
    });

    test('a missing or unparseable created_at is rejected', () {
      expect(
        () => RetailerStaffMemberParser.parse(<Object?>[row(createdAt: null)]),
        throwsFormat(),
      );
    });

    test('an empty shop array parses as no assignments', () {
      // The expected shape for an Owner or a Manager, who hold no shop rows.
      final RetailerStaffMember m = RetailerStaffMemberParser.parse(<Object?>[
        row(shopIds: const <Object?>[], shopNames: const <Object?>[]),
      ]).single;

      expect(m.shopIds, isEmpty);
      expect(m.shopNames, isEmpty);
      expect(m.hasShops, isFalse);
    });

    test('a missing shop_names key is rejected', () {
      // `coalesce(..., '{}')` means the column is never null, so absence is a
      // malformed row rather than "no shops".
      final Map<String, Object?> without = row()..remove('shop_names');
      expect(
        () => RetailerStaffMemberParser.parse(<Object?>[without]),
        throwsFormat(),
      );
    });

    test('mismatched shop_ids and shop_names cannot mis-pair anything', () {
      // Both are read now, and the client still never zips them: the ids seed a
      // selection and the names are displayed. So a length mismatch is
      // structurally incapable of attributing a name to the wrong shop, and both
      // arrive exactly as sent.
      final RetailerStaffMember m = RetailerStaffMemberParser.parse(<Object?>[
        row(
          shopIds: const <Object?>[
            '11111111-1111-1111-1111-111111111111',
            '33333333-3333-3333-3333-333333333333',
            '44444444-4444-4444-4444-444444444444',
          ],
          shopNames: const <Object?>['Only One Shop'],
        ),
      ]).single;

      expect(m.shopNames, <String>['Only One Shop']);
      expect(m.shopIds, hasLength(3));
    });

    test('membership_id must be present and shaped like a uuid', () {
      // It becomes `p_membership_id`. A value that is not a uuid would reach
      // PostgREST as a `22P02` cast error, dressed up as a database fault.
      for (final Object? bad in <Object?>[
        null,
        '',
        '   ',
        42,
        'not-a-uuid',
        '22222222-2222-2222-2222-2222222222',
      ]) {
        final Map<String, Object?> broken = row()..['membership_id'] = bad;
        expect(
          () => RetailerStaffMemberParser.parse(<Object?>[broken]),
          throwsFormat(),
          reason: '\$bad',
        );
      }
    });

    test('membership_id and shop ids are lower-cased', () {
      // The value held is the value the contract canonicalizes to, so two
      // spellings of one id can never be counted as two shops.
      final RetailerStaffMember m = RetailerStaffMemberParser.parse(<Object?>[
        row()
          ..['membership_id'] = '22222222-AAAA-2222-2222-222222222222'
          ..['shop_ids'] = const <Object?>[
            '11111111-BBBB-1111-1111-111111111111',
          ],
      ]).single;

      expect(m.membershipId, '22222222-aaaa-2222-2222-222222222222');
      expect(m.shopIds, <String>['11111111-bbbb-1111-1111-111111111111']);
    });

    test('a malformed or duplicated shop id fails the row', () {
      // Strict where `shop_names` is lenient, and deliberately so: a dropped
      // name is one missing chip, a dropped id silently shortens the set the
      // editor preselects — and saving from a short set retires an assignment
      // nobody chose to remove.
      for (final Object? bad in <Object?>[
        null,
        'not-a-uuid',
        const <Object?>['11111111-1111-1111-1111-111111111111', null],
        const <Object?>[
          '11111111-1111-1111-1111-111111111111',
          '11111111-1111-1111-1111-111111111111',
        ],
      ]) {
        final Map<String, Object?> broken = row()..['shop_ids'] = bad;
        expect(
          () => RetailerStaffMemberParser.parse(<Object?>[broken]),
          throwsFormat(),
          reason: '\$bad',
        );
      }
    });

    test('a missing shop_ids key is rejected', () {
      final Map<String, Object?> without = row()..remove('shop_ids');
      expect(
        () => RetailerStaffMemberParser.parse(<Object?>[without]),
        throwsFormat(),
      );
    });

    test('null and blank entries inside shop_names are dropped', () {
      // One unshowable name is a missing chip, not a reason to hide a person.
      final RetailerStaffMember m = RetailerStaffMemberParser.parse(<Object?>[
        row(shopNames: const <Object?>['Real Shop', null, '  ', 42]),
      ]).single;

      expect(m.shopNames, <String>['Real Shop']);
    });

    test('every membership status is recognised', () {
      for (final (String code, RetailerMemberStatus expected)
          in <(String, RetailerMemberStatus)>[
            ('INVITED', RetailerMemberStatus.invited),
            ('ACTIVE', RetailerMemberStatus.active),
            ('SUSPENDED', RetailerMemberStatus.suspended),
            ('DEACTIVATED', RetailerMemberStatus.deactivated),
          ]) {
        expect(
          RetailerStaffMemberParser.parse(<Object?>[
            row(membershipStatus: code),
          ]).single.status,
          expected,
        );
      }
    });

    test('an invalid membership status degrades to unknown', () {
      final RetailerStaffMember m = RetailerStaffMemberParser.parse(<Object?>[
        row(membershipStatus: 'ON_LEAVE'),
      ]).single;

      expect(m.status, RetailerMemberStatus.unknown);
      expect(m.status.isActive, isFalse);
      expect(m.status.label, isNot(contains('LEAVE')));
    });

    test('an unknown role code is carried, because role_name is displayed', () {
      // The role catalogue is data rather than a closed enum. A Retailer that
      // gains a role should see its name, not a parse failure.
      final RetailerStaffMember m = RetailerStaffMemberParser.parse(<Object?>[
        row(roleCode: 'RETAILER_AUDITOR', roleName: 'Retailer Auditor'),
      ]).single;

      expect(m.roleCode, 'RETAILER_AUDITOR');
      expect(m.roleName, 'Retailer Auditor');
    });

    test('a missing required name or role is rejected', () {
      for (final String key in <String>[
        'first_name',
        'last_name',
        'role_code',
        'role_name',
        'membership_status',
      ]) {
        final Map<String, Object?> broken = row()..[key] = null;
        expect(
          () => RetailerStaffMemberParser.parse(<Object?>[broken]),
          throwsFormat(),
          reason: key,
        );
      }
    });

    test('the two carried identifiers are the only ones, and are bounded', () {
      // The contract also returns nothing else addressable, and the entity holds
      // no auth user id, profile id, member-role id or organization id — there
      // is no field for one. What it does hold is checked here so a future
      // widening is visible as a test change.
      final RetailerStaffMember m = RetailerStaffMemberParser.parse(<Object?>[
        row()..['user_id'] = '99999999-9999-9999-9999-999999999999',
      ]).single;

      final String flattened = m.props
          .map((Object? p) => p.toString())
          .join(' ');

      expect(flattened, contains('22222222-2222-2222-2222-222222222222'));
      expect(flattened, contains('11111111-1111-1111-1111-111111111111'));
      // An identifier the entity has no field for cannot arrive by being in the
      // body.
      expect(flattened, isNot(contains('9999-9999')));
    });

    test('nothing a card renders carries an identifier', () {
      // The proof that the ids are bounded is what reaches a screen, and every
      // displayed value is asserted here rather than in a widget test that could
      // be satisfied by a lucky layout.
      final RetailerStaffMember m = RetailerStaffMemberParser.parse(<Object?>[
        row(),
      ]).single;

      for (final String displayed in <String>[
        m.fullName,
        m.roleName,
        m.status.label,
        ...m.shopNames,
      ]) {
        expect(displayed, isNot(contains(m.membershipId)));
        for (final String shopId in m.shopIds) {
          expect(displayed, isNot(contains(shopId)));
        }
      }
    });

    test('unexpected extra fields are ignored', () {
      final Map<String, Object?> extra = row()..['pending_receipts'] = 4;
      expect(
        RetailerStaffMemberParser.parse(<Object?>[extra]).single.fullName,
        'Priya Raman',
      );
    });
  });

  // -------------------------------------------------------------------------
  group('invitations', () {
    Map<String, Object?> row({
      Object? firstName = 'Lena',
      Object? lastName = 'Osei',
      Object? email = 'lena@example.com',
      Object? roleCode = 'SALES_STAFF',
      Object? derivedState = 'PENDING',
      Object? failureCode,
      Object? createdAt = '2026-06-01T09:00:00Z',
      Object? sentAt = '2026-06-01T09:05:00Z',
      Object? acceptedAt,
      Object? revokedAt,
      Object? expiresAt = '2026-07-01T09:00:00Z',
    }) => <String, Object?>{
      'invitation_id': '33333333-3333-3333-3333-333333333333',
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'role_code': roleCode,
      'derived_state': derivedState,
      'created_at': createdAt,
      'sent_at': sentAt,
      'accepted_at': acceptedAt,
      'revoked_at': revokedAt,
      'expires_at': expiresAt,
      'failure_code': failureCode,
      'shop_ids': const <Object?>['44444444-4444-4444-4444-444444444444'],
    };

    test('a valid row parses every displayed field', () {
      final RetailerStaffInvitation i = RetailerStaffInvitationParser.parse(
        <Object?>[row()],
      ).single;

      expect(i.fullName, 'Lena Osei');
      expect(i.email, 'lena@example.com');
      expect(i.roleCode, 'SALES_STAFF');
      expect(i.state, RetailerInvitationState.pending);
      expect(i.hasDeliveryFailure, isFalse);
      expect(i.sentAt, DateTime.utc(2026, 6, 1, 9, 5));
      expect(i.expiresAt, DateTime.utc(2026, 7, 1, 9));
      expect(i.acceptedAt, isNull);
      expect(i.revokedAt, isNull);
    });

    test('every derived state the backend can emit is recognised', () {
      for (final (String code, RetailerInvitationState expected)
          in <(String, RetailerInvitationState)>[
            ('RESERVED', RetailerInvitationState.reserved),
            ('PENDING', RetailerInvitationState.pending),
            ('ACCEPTED', RetailerInvitationState.accepted),
            ('REVOKED', RetailerInvitationState.revoked),
            ('EXPIRED', RetailerInvitationState.expired),
            ('DELIVERY_FAILED', RetailerInvitationState.deliveryFailed),
          ]) {
        expect(
          RetailerStaffInvitationParser.parse(<Object?>[
            row(derivedState: code),
          ]).single.state,
          expected,
          reason: code,
        );
      }
    });

    test('a NULL derived_state is indeterminate, not malformed', () {
      // The backend's CASE has no ELSE branch: a PENDING, unexpired, sent
      // invitation carrying a failure_code other than EMAIL_DISPATCH_FAILED
      // matches no arm and yields NULL. Rejecting the row would hide an
      // invitation that genuinely exists.
      final RetailerStaffInvitation i = RetailerStaffInvitationParser.parse(
        <Object?>[row(derivedState: null, failureCode: 'SOMETHING_ELSE')],
      ).single;

      expect(i.state, RetailerInvitationState.indeterminate);
      expect(i.state.isRecognised, isFalse);
      expect(i.state.label, 'Status unavailable');
    });

    test('an unknown derived_state token degrades safely', () {
      final RetailerStaffInvitation i = RetailerStaffInvitationParser.parse(
        <Object?>[row(derivedState: 'BOUNCED_HARD')],
      ).single;

      expect(i.state, RetailerInvitationState.unknown);
      expect(i.state.isRecognised, isFalse);
      // The raw token never becomes the label.
      expect(i.state.label, isNot(contains('BOUNCED')));
    });

    test('a delivery failure is reduced to a boolean, never a code', () {
      final RetailerStaffInvitation i = RetailerStaffInvitationParser.parse(
        <Object?>[
          row(
            derivedState: 'DELIVERY_FAILED',
            failureCode: 'EMAIL_DISPATCH_FAILED',
          ),
        ],
      ).single;

      expect(i.hasDeliveryFailure, isTrue);
      // The code exists nowhere on the entity.
      expect(
        i.props.map((Object? p) => p.toString()).join(' '),
        isNot(contains('EMAIL_DISPATCH')),
      );
    });

    test('an unrecognised failure code still reads as a delivery failure', () {
      final RetailerStaffInvitation i = RetailerStaffInvitationParser.parse(
        <Object?>[row(failureCode: 'SMTP_QUOTA_EXCEEDED')],
      ).single;

      expect(i.hasDeliveryFailure, isTrue);
      expect(
        i.props.map((Object? p) => p.toString()).join(' '),
        isNot(contains('SMTP')),
      );
    });

    test('nullable instants parse as absences', () {
      final RetailerStaffInvitation i = RetailerStaffInvitationParser.parse(
        <Object?>[row(sentAt: null)],
      ).single;
      expect(i.sentAt, isNull);
    });

    test('a missing created_at or expires_at is rejected', () {
      for (final String key in <String>['created_at', 'expires_at']) {
        final Map<String, Object?> broken = row()..[key] = null;
        expect(
          () => RetailerStaffInvitationParser.parse(<Object?>[broken]),
          throwsFormat(),
          reason: key,
        );
      }
    });

    test('a malformed invitation row fails the whole history', () {
      expect(
        () => RetailerStaffInvitationParser.parse(<Object?>[
          row(),
          row(email: null),
        ]),
        throwsFormat(),
      );
    });

    test('an unparseable timestamp is rejected', () {
      expect(
        () => RetailerStaffInvitationParser.parse(<Object?>[
          row(expiresAt: 'yesterday'),
        ]),
        throwsFormat(),
      );
    });

    test('no identifier survives parsing', () {
      final RetailerStaffInvitation i = RetailerStaffInvitationParser.parse(
        <Object?>[row()],
      ).single;

      final String flattened = i.props
          .map((Object? p) => p.toString())
          .join(' ');
      expect(flattened, isNot(contains('3333-3333')));
      expect(flattened, isNot(contains('4444-4444')));
    });

    test('an empty history is a real answer', () {
      expect(RetailerStaffInvitationParser.parse(<Object?>[]), isEmpty);
    });

    test('unexpected extra fields are ignored', () {
      final Map<String, Object?> extra = row()..['resend_count'] = 2;
      expect(
        RetailerStaffInvitationParser.parse(<Object?>[extra]).single.fullName,
        'Lena Osei',
      );
    });

    test('settled states are identified for de-emphasis only', () {
      for (final String code in <String>['ACCEPTED', 'REVOKED', 'EXPIRED']) {
        expect(
          RetailerStaffInvitationParser.parse(<Object?>[
            row(derivedState: code),
          ]).single.isSettled,
          isTrue,
          reason: code,
        );
      }
      expect(
        RetailerStaffInvitationParser.parse(<Object?>[
          row(derivedState: 'PENDING'),
        ]).single.isSettled,
        isFalse,
      );
    });
  });
}
