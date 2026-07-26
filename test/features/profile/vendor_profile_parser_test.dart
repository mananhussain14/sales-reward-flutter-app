import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/profile/data/models/vendor_profile_parser.dart';
import 'package:sale_reward/features/profile/domain/entities/vendor_administrator_profile.dart';

import '../../support/vendor_profile_fakes.dart';

/// The parser is the boundary at which an untyped response becomes an identity.
///
/// Everything below is one of three rules:
///
/// 1. **Exactly one row, or nothing.** Zero rows and two rows are both
///    unreachable against the deployed contract, so both are rejected rather than
///    tolerated — a denial is an exception in SQL, never an empty body, so an
///    empty body must never become a blank profile.
/// 2. **Both fields or neither.** A malformed role array fails the whole profile;
///    there is no partial identity to emit.
/// 3. **Nothing is composed, derived, defaulted or re-ordered.** The name is
///    rendered verbatim, the role order is the backend's, and no field the
///    contract does not return is looked for.
void main() {
  VendorAdministratorProfile parse(Object? raw) =>
      VendorProfileParser.parse(raw);

  Matcher throwsFormat() => throwsA(isA<VendorProfileFormatException>());

  group('a well-formed row', () {
    test('a display name and one role parse into the entity', () {
      final VendorAdministratorProfile profile = parse(
        administratorProfileBody(),
      );

      expect(profile.displayName, 'Amina Rahman');
      expect(profile.roleNames, <String>['Vendor Super Admin']);
      expect(profile, aminaAdministratorProfile);
    });

    test('the display name is taken exactly as returned', () {
      // Not split, not trimmed and recombined, not re-cased, and never replaced
      // by anything else. The database composed it.
      final VendorAdministratorProfile profile = parse(
        administratorProfileBody(
          administratorProfileRow(displayName: "Mary-Jane O'Neill de la Cruz"),
        ),
      );

      expect(profile.displayName, "Mary-Jane O'Neill de la Cruz");
    });

    test('a single-word display name is accepted, not rejected', () {
      // The SQL floor is the literal 'Member', and it is unreachable — but a
      // single-token name is a perfectly ordinary string and this build accepts
      // any non-blank one rather than pattern-matching the fallback.
      final VendorAdministratorProfile profile = parse(
        administratorProfileBody(
          administratorProfileRow(displayName: 'Member'),
        ),
      );

      expect(profile.displayName, 'Member');
    });

    test('multiple roles preserve the order they arrived in', () {
      final VendorAdministratorProfile profile = parse(
        administratorProfileBody(
          administratorProfileRow(
            roleNames: const <Object?>[
              'Catalogue Manager',
              'Finance Admin',
              'Vendor Super Admin',
            ],
          ),
        ),
      );

      expect(profile.roleNames, <String>[
        'Catalogue Manager',
        'Finance Admin',
        'Vendor Super Admin',
      ]);
    });

    test('an order Dart would not produce is preserved verbatim', () {
      // The load-bearing assertion for "do not re-sort". Alphabetising this
      // would visibly change it, so anything that sorted would fail here.
      final VendorAdministratorProfile profile = parse(
        administratorProfileBody(
          administratorProfileRow(
            roleNames: const <Object?>[
              'Vendor Super Admin',
              'Finance Admin',
              'Catalogue Manager',
            ],
          ),
        ),
      );

      expect(profile.roleNames, <String>[
        'Vendor Super Admin',
        'Finance Admin',
        'Catalogue Manager',
      ]);
    });

    test('a repeated role name is preserved, not collapsed or refused', () {
      // `public.roles` constrains `code` to be unique but NOT `name`, so two
      // distinct ACTIVE definitions sharing a display name is a legal database
      // state. Collapsing it would hide a real answer; a Set would also change
      // the order.
      final VendorAdministratorProfile profile = parse(
        administratorProfileBody(
          administratorProfileRow(
            roleNames: const <Object?>['Finance Admin', 'Finance Admin'],
          ),
        ),
      );

      expect(profile.roleNames, <String>['Finance Admin', 'Finance Admin']);
    });

    test('an empty role array is accepted defensively, never as an error', () {
      // Unreachable for an authorized caller — the ACTIVE Vendor Super Admin
      // assignment that authorized them is always in the array — but it parses
      // safely rather than crashing.
      final VendorAdministratorProfile profile = parse(
        administratorProfileBody(
          administratorProfileRow(roleNames: const <Object?>[]),
        ),
      );

      expect(profile.roleNames, isEmpty);
      expect(profile, noRoleAdministratorProfile);
    });

    test('a role name with internal punctuation is kept intact', () {
      final VendorAdministratorProfile profile = parse(
        administratorProfileBody(
          administratorProfileRow(
            roleNames: const <Object?>['Claims & Payouts Reviewer'],
          ),
        ),
      );

      expect(profile.roleNames, <String>['Claims & Payouts Reviewer']);
    });
  });

  group('the display name is refused rather than guessed', () {
    test('a missing key is a format error', () {
      expect(
        () => parse(<Object?>[
          <String, Object?>{
            'administrator_role_names': <Object?>['Vendor Super Admin'],
          },
        ]),
        throwsFormat(),
      );
    });

    test('an explicit null is a format error, never a placeholder', () {
      expect(
        () => parse(
          administratorProfileBody(administratorProfileRow(displayName: null)),
        ),
        throwsFormat(),
      );
    });

    test('a non-string value is a format error', () {
      for (final Object? wrong in <Object?>[
        7,
        7.5,
        true,
        <Object?>['Amina'],
        <String, Object?>{'first': 'Amina'},
      ]) {
        expect(
          () => parse(
            administratorProfileBody(
              administratorProfileRow(displayName: wrong),
            ),
          ),
          throwsFormat(),
          reason: 'a display name of $wrong must not parse',
        );
      }
    });

    test('an empty string is a format error', () {
      expect(
        () => parse(
          administratorProfileBody(administratorProfileRow(displayName: '')),
        ),
        throwsFormat(),
      );
    });

    test('a whitespace-only string is a format error', () {
      for (final String blank in <String>[' ', '   ', '\t', '\n', ' \t\n ']) {
        expect(
          () => parse(
            administratorProfileBody(
              administratorProfileRow(displayName: blank),
            ),
          ),
          throwsFormat(),
          reason: 'a blank display name must not parse',
        );
      }
    });
  });

  group('the role array is refused rather than guessed', () {
    test('a missing key is a format error, not an empty list', () {
      expect(
        () => parse(<Object?>[
          <String, Object?>{'administrator_display_name': 'Amina Rahman'},
        ]),
        throwsFormat(),
      );
    });

    test('an explicit null is a format error, not "no roles"', () {
      // The SQL coalesces the aggregate to '{}', so a null array is a response
      // this build was not written against. Reading it as "no roles" would be a
      // guess about an entitlement.
      expect(
        () => parse(
          administratorProfileBody(administratorProfileRow(roleNames: null)),
        ),
        throwsFormat(),
      );
    });

    test('a non-list value is a format error', () {
      for (final Object? wrong in <Object?>[
        'Vendor Super Admin',
        7,
        true,
        <String, Object?>{'0': 'Vendor Super Admin'},
      ]) {
        expect(
          () => parse(
            administratorProfileBody(administratorProfileRow(roleNames: wrong)),
          ),
          throwsFormat(),
          reason: 'a role array of $wrong must not parse',
        );
      }
    });

    test('a non-string entry is a format error', () {
      for (final Object? wrong in <Object?>[
        7,
        true,
        null,
        <Object?>['nested'],
        <String, Object?>{'name': 'Finance Admin'},
      ]) {
        expect(
          () => parse(
            administratorProfileBody(
              administratorProfileRow(
                roleNames: <Object?>['Vendor Super Admin', wrong],
              ),
            ),
          ),
          throwsFormat(),
          reason: 'a role entry of $wrong must not parse',
        );
      }
    });

    test('an empty entry is a format error', () {
      expect(
        () => parse(
          administratorProfileBody(
            administratorProfileRow(
              roleNames: const <Object?>['Vendor Super Admin', ''],
            ),
          ),
        ),
        throwsFormat(),
      );
    });

    test('a whitespace-only entry is a format error', () {
      expect(
        () => parse(
          administratorProfileBody(
            administratorProfileRow(
              roleNames: const <Object?>['Vendor Super Admin', '   '],
            ),
          ),
        ),
        throwsFormat(),
      );
    });

    test('one bad entry fails the whole profile, not just that entry', () {
      // No partial role list, and no partial identity: the name is not rendered
      // beside a silently shortened list of entitlements.
      expect(
        () => parse(
          administratorProfileBody(
            administratorProfileRow(
              roleNames: const <Object?>['Vendor Super Admin', 42],
            ),
          ),
        ),
        throwsFormat(),
      );
    });
  });

  group('the row count is checked rather than assumed', () {
    test('zero rows is a format error, never a blank profile', () {
      // A denial is an exception in SQL, never an empty body — so an empty body
      // must never become a profile screen for an identity the caller may not
      // hold.
      expect(() => parse(<Object?>[]), throwsFormat());
    });

    test('two rows is a format error, and neither row is taken', () {
      expect(
        () => parse(<Object?>[
          administratorProfileRow(),
          administratorProfileRow(displayName: 'Jo Nakamura'),
        ]),
        throwsFormat(),
      );
    });

    test('a body that is not a list is a format error', () {
      for (final Object? wrong in <Object?>[
        null,
        administratorProfileRow(),
        'Amina Rahman',
        7,
      ]) {
        expect(() => parse(wrong), throwsFormat());
      }
    });

    test('a row that is not an object is a format error', () {
      for (final Object? wrong in <Object?>[
        'Amina Rahman',
        7,
        <Object?>['Amina Rahman'],
      ]) {
        expect(() => parse(<Object?>[wrong]), throwsFormat());
      }
    });
  });

  group('nothing outside the two contracted fields is read', () {
    test('an id in the response is ignored, not modelled', () {
      // The contract returns no id of any kind. A response that carried one
      // parses to the same entity, because there is nowhere to put it.
      final VendorAdministratorProfile profile = parse(<Object?>[
        <String, Object?>{
          'administrator_display_name': 'Amina Rahman',
          'administrator_role_names': <Object?>['Vendor Super Admin'],
          'membership_id': '11111111-1111-1111-1111-111111111111',
          'profile_id': '22222222-2222-2222-2222-222222222222',
          'auth_user_id': '33333333-3333-3333-3333-333333333333',
        },
      ]);

      expect(profile, aminaAdministratorProfile);
      expect(profile.props, <Object?>[
        'Amina Rahman',
        <String>['Vendor Super Admin'],
      ]);
    });

    test('an organization name in the response is ignored', () {
      // The company name has exactly one source, and it is the session. Even if
      // a future response carried one, this model could not hold it.
      final VendorAdministratorProfile profile = parse(<Object?>[
        <String, Object?>{
          'administrator_display_name': 'Amina Rahman',
          'administrator_role_names': <Object?>['Vendor Super Admin'],
          'organization_name': 'Northwind Trading',
          'organization_id': '44444444-4444-4444-4444-444444444444',
        },
      ]);

      expect(profile, aminaAdministratorProfile);
      expect(profile.toString(), isNot(contains('Northwind')));
    });

    test(
      'email, mobile, status and timestamps are neither required nor read',
      () {
        // A row carrying none of them parses; a row carrying all of them parses to
        // exactly the same entity.
        expect(parse(administratorProfileBody()), aminaAdministratorProfile);

        final VendorAdministratorProfile profile = parse(<Object?>[
          <String, Object?>{
            'administrator_display_name': 'Amina Rahman',
            'administrator_role_names': <Object?>['Vendor Super Admin'],
            'email': 'amina@example.com',
            'mobile_number': '+971500000000',
            'profile_status': 'ACTIVE',
            'membership_status': 'ACTIVE',
            'organization_status': 'ACTIVE',
            'created_at': '2026-01-01T00:00:00Z',
            'updated_at': '2026-01-02T00:00:00Z',
          },
        ]);

        expect(profile, aminaAdministratorProfile);
        expect(profile.toString(), isNot(contains('example.com')));
        expect(profile.toString(), isNot(contains('ACTIVE')));
      },
    );

    test('no role code is parsed or inferred', () {
      // The backend returns names. Nothing maps one back to a code, and a code
      // arriving under a different key is not read.
      final VendorAdministratorProfile profile = parse(<Object?>[
        <String, Object?>{
          'administrator_display_name': 'Amina Rahman',
          'administrator_role_names': <Object?>['Vendor Super Admin'],
          'administrator_role_codes': <Object?>['VENDOR_SUPER_ADMIN'],
        },
      ]);

      expect(profile.roleNames, <String>['Vendor Super Admin']);
      expect(profile.roleNames, isNot(contains('VENDOR_SUPER_ADMIN')));
    });
  });

  group('the entity', () {
    test('equality is by name and role list together', () {
      expect(
        const VendorAdministratorProfile(
          displayName: 'Amina Rahman',
          roleNames: <String>['Vendor Super Admin'],
        ),
        aminaAdministratorProfile,
      );
      expect(
        const VendorAdministratorProfile(
          displayName: 'Amina Rahman',
          roleNames: <String>['Finance Admin'],
        ),
        isNot(aminaAdministratorProfile),
      );
      expect(
        const VendorAdministratorProfile(
          displayName: 'Jo Nakamura',
          roleNames: <String>['Vendor Super Admin'],
        ),
        isNot(aminaAdministratorProfile),
      );
    });

    test('two role lists differing only in order are not equal', () {
      // Order is part of the contract, so it is part of the identity of the
      // value — a cubit comparing states must notice a reordering.
      expect(multiRoleAdministratorProfile, isNot(reversedOrderProfile));
    });
  });
}
