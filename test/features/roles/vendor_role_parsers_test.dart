import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/roles/data/models/vendor_role_parsers.dart';
import 'package:sale_reward/features/roles/domain/entities/vendor_role_detail.dart';
import 'package:sale_reward/features/roles/domain/entities/vendor_role_permission.dart';
import 'package:sale_reward/features/roles/domain/entities/vendor_role_status.dart';
import 'package:sale_reward/features/roles/domain/entities/vendor_role_summary.dart';

import '../../support/vendor_role_fakes.dart';

/// The strictness rules, one test each.
///
/// The theme throughout: a field the response did not supply is a **format
/// error**, never a substituted default. A default here would be a value the
/// backend never sent, presented as though it had — which is how a malformed
/// response becomes fabricated data, how an unreadable status becomes an ACTIVE
/// role, and how a broken count becomes "this role grants nothing".
void main() {
  group('the role list', () {
    test('parses every field the contract returns', () {
      final List<VendorRoleSummary> parsed = VendorRoleSummaryParser.parseList(
        roleRows(),
      );

      expect(parsed, hasLength(2));

      final VendorRoleSummary superAdmin = parsed[1];
      expect(superAdmin.roleId, superAdminRoleUuid);
      expect(superAdmin.roleName, 'Vendor Super Admin');
      expect(
        superAdmin.description,
        'Full administrative control of a Vendor organization.',
      );
      expect(superAdmin.status, VendorRoleStatus.active);
      expect(superAdmin.createdAt, DateTime.utc(2026, 1, 5, 8));
      expect(superAdmin.permissionCount, 3);
      expect(superAdmin.assignedMemberCount, 2);
    });

    test('preserves the backend order rather than re-sorting', () {
      // The SQL orders by role_name then role_id — total, and in the database's
      // own collation. Re-sorting here would be a second, drifting definition.
      final List<VendorRoleSummary> parsed =
          VendorRoleSummaryParser.parseList(<Map<String, Object?>>[
            roleRow(roleName: 'Zebra Handler'),
            roleRow(roleId: claimReviewerRoleUuid, roleName: 'Alpha Handler'),
          ]);

      expect(parsed.map((VendorRoleSummary r) => r.roleName), <String>[
        'Zebra Handler',
        'Alpha Handler',
      ]);
    });

    test('an empty catalogue is an empty list, not a failure', () {
      expect(VendorRoleSummaryParser.parseList(const <Object?>[]), isEmpty);
    });

    test('a null description stays null and is never fabricated', () {
      final VendorRoleSummary parsed = VendorRoleSummaryParser.parse(
        roleRow(description: null),
      );

      expect(parsed.description, isNull);
    });

    test('a blank description is treated as absent, not as a description', () {
      // Whitespace must not satisfy a "is there a description?" test on screen.
      final VendorRoleSummary parsed = VendorRoleSummaryParser.parse(
        roleRow(description: '   '),
      );

      expect(parsed.description, isNull);
    });

    test('an INACTIVE role parses, and is not hidden', () {
      final VendorRoleSummary parsed = VendorRoleSummaryParser.parse(
        roleRow(status: 'INACTIVE'),
      );

      expect(parsed.status, VendorRoleStatus.inactive);
      expect(parsed.status.isActive, isFalse);
      expect(parsed.status.grantsMappedPermissions, isFalse);
    });

    test('a zero permission count is a real answer', () {
      final VendorRoleSummary parsed = VendorRoleSummaryParser.parse(
        roleRow(permissionCount: 0),
      );

      expect(parsed.permissionCount, 0);
      expect(parsed.hasNoPermissions, isTrue);
    });

    test('a zero member count is a real answer', () {
      // The true answer for a Retailer role read by a Vendor — not a hidden row.
      final VendorRoleSummary parsed = VendorRoleSummaryParser.parse(
        roleRow(assignedMemberCount: 0),
      );

      expect(parsed.assignedMemberCount, 0);
      expect(parsed.hasNoAssignedMembers, isTrue);
    });

    test('an integral double count is accepted', () {
      // JSON has one number type, and a transport may hand back 3.0.
      final VendorRoleSummary parsed = VendorRoleSummaryParser.parse(
        roleRow(permissionCount: 3.0, assignedMemberCount: 2.0),
      );

      expect(parsed.permissionCount, 3);
      expect(parsed.assignedMemberCount, 2);
    });
  });

  group('an unknown role status', () {
    test('degrades to unknown rather than failing the read', () {
      final VendorRoleSummary parsed = VendorRoleSummaryParser.parse(
        roleRow(status: 'ARCHIVED'),
      );

      expect(parsed.status, VendorRoleStatus.unknown);
    });

    test('is never ACTIVE, and never reports permissions as effective', () {
      // The one guess that would matter: an unrecognised status must not become
      // "this role currently grants these permissions".
      final VendorRoleSummary parsed = VendorRoleSummaryParser.parse(
        roleRow(status: 'SOMETHING_NEW'),
      );

      expect(parsed.status.isActive, isFalse);
      expect(parsed.status.grantsMappedPermissions, isFalse);
    });

    test('never carries the raw backend token', () {
      final VendorRoleSummary parsed = VendorRoleSummaryParser.parse(
        roleRow(status: 'ARCHIVED'),
      );

      expect(parsed.status.code, isEmpty);
    });

    test('the role is still parsed, so it cannot disappear from the list', () {
      final List<VendorRoleSummary> parsed = VendorRoleSummaryParser.parseList(
        <Map<String, Object?>>[roleRow(status: 'ARCHIVED')],
      );

      expect(parsed, hasLength(1));
      expect(parsed.single.roleName, 'Vendor Super Admin');
    });
  });

  group('the role list refuses a malformed row', () {
    void expectRejected(String what, Map<String, Object?> row) {
      test(what, () {
        expect(
          () => VendorRoleSummaryParser.parse(row),
          throwsA(isA<VendorRoleFormatException>()),
        );
      });
    }

    expectRejected('a malformed role id', roleRow(roleId: 'not-a-uuid'));
    expectRejected('a missing role id', roleRow(roleId: null));
    expectRejected('an empty role id', roleRow(roleId: ''));
    expectRejected('a non-string role id', roleRow(roleId: 42));
    expectRejected('a missing role name', roleRow(roleName: null));
    expectRejected('a blank role name', roleRow(roleName: '  '));
    expectRejected('a non-string role name', roleRow(roleName: 7));
    expectRejected('a missing role status', roleRow(status: null));
    expectRejected('a blank role status', roleRow(status: ''));
    expectRejected('a non-string role status', roleRow(status: true));
    expectRejected('a missing created timestamp', roleRow(createdAt: null));
    expectRejected(
      'a malformed created timestamp',
      roleRow(createdAt: 'the fifth of January'),
    );
    expectRejected(
      'a non-string created timestamp',
      roleRow(createdAt: 1767590400),
    );
    expectRejected('a description of the wrong type', roleRow(description: 42));
    expectRejected(
      'a missing permission count',
      roleRow(permissionCount: null),
    );
    expectRejected(
      'a non-integer permission count',
      roleRow(permissionCount: '3'),
    );
    expectRejected(
      'a fractional permission count',
      roleRow(permissionCount: 2.5),
    );
    expectRejected('a negative permission count', roleRow(permissionCount: -1));
    expectRejected(
      'a missing assigned member count',
      roleRow(assignedMemberCount: null),
    );
    expectRejected(
      'a non-integer assigned member count',
      roleRow(assignedMemberCount: 'two'),
    );
    expectRejected(
      'a negative assigned member count',
      roleRow(assignedMemberCount: -4),
    );

    test('a body that is not a list', () {
      expect(
        () => VendorRoleSummaryParser.parseList(<String, Object?>{}),
        throwsA(isA<VendorRoleFormatException>()),
      );
    });

    test('a row that is not an object', () {
      expect(
        () => VendorRoleSummaryParser.parseList(<Object?>['role']),
        throwsA(isA<VendorRoleFormatException>()),
      );
    });

    test('one bad row fails the whole read rather than being dropped', () {
      // A silently shortened catalogue is worse than an honest retry.
      expect(
        () => VendorRoleSummaryParser.parseList(<Map<String, Object?>>[
          roleRow(),
          roleRow(roleName: null),
        ]),
        throwsA(isA<VendorRoleFormatException>()),
      );
    });

    test('a negative count is refused rather than clamped to zero', () {
      // Clamping would report "no permissions mapped" on the strength of a
      // number the backend never produced.
      expect(
        () => VendorRoleSummaryParser.parse(roleRow(permissionCount: -1)),
        throwsA(isA<VendorRoleFormatException>()),
      );
    });
  });

  group('the role detail', () {
    test('parses one row into the same shape as a list row', () {
      final VendorRoleDetail? parsed = VendorRoleDetailParser.parseSingle(
        <Map<String, Object?>>[roleRow()],
      );

      expect(parsed, isNotNull);
      expect(parsed, isA<VendorRoleSummary>());
      expect(parsed!.roleId, superAdminRoleUuid);
      expect(parsed.permissionCount, 3);
      expect(parsed.assignedMemberCount, 2);
    });

    test('zero rows is a legitimate answer and yields null', () {
      // One representation for an unknown uuid, an id from another table and
      // null alike — there is no existence oracle to build from this.
      expect(VendorRoleDetailParser.parseSingle(const <Object?>[]), isNull);
    });

    test('several rows is malformed, because the filter is a primary key', () {
      expect(
        () => VendorRoleDetailParser.parseSingle(<Map<String, Object?>>[
          roleRow(),
          roleRow(roleId: claimReviewerRoleUuid),
        ]),
        throwsA(isA<VendorRoleFormatException>()),
      );
    });

    test('an inactive role parses with its status intact', () {
      final VendorRoleDetail? parsed = VendorRoleDetailParser.parseSingle(
        <Map<String, Object?>>[roleRow(status: 'INACTIVE', permissionCount: 4)],
      );

      // The count is untouched by the status: four mappings, none effective.
      expect(parsed!.status, VendorRoleStatus.inactive);
      expect(parsed.permissionCount, 4);
    });

    test('a malformed detail row is a format error, never null', () {
      // Null means "no such role". A body that could not be read is a different
      // event, and conflating them would offer the wrong screen.
      expect(
        () => VendorRoleDetailParser.parseSingle(<Map<String, Object?>>[
          roleRow(roleId: 'nope'),
        ]),
        throwsA(isA<VendorRoleFormatException>()),
      );
    });
  });

  group('the permission companion', () {
    test('parses name and description', () {
      final List<VendorRolePermission> parsed =
          VendorRolePermissionParser.parseList(<Map<String, Object?>>[
            permissionRow(),
          ]);

      expect(parsed.single.name, 'Read roles');
      expect(parsed.single.description, 'See roles and their permissions.');
    });

    test('a null permission description stays null', () {
      final List<VendorRolePermission> parsed =
          VendorRolePermissionParser.parseList(<Map<String, Object?>>[
            permissionRow(description: null),
          ]);

      expect(parsed.single.description, isNull);
    });

    test('a blank permission description is treated as absent', () {
      final List<VendorRolePermission> parsed =
          VendorRolePermissionParser.parseList(<Map<String, Object?>>[
            permissionRow(description: ' '),
          ]);

      expect(parsed.single.description, isNull);
    });

    test('an empty mapping list is a legitimate answer', () {
      expect(VendorRolePermissionParser.parseList(const <Object?>[]), isEmpty);
    });

    test('the backend order is preserved, and nothing is de-duplicated', () {
      // A Set here would hide a genuine backend duplication bug rather than
      // prevent one.
      final List<VendorRolePermission> parsed =
          VendorRolePermissionParser.parseList(<Map<String, Object?>>[
            permissionRow(name: 'Zeta'),
            permissionRow(name: 'Alpha'),
            permissionRow(name: 'Alpha'),
          ]);

      expect(parsed.map((VendorRolePermission p) => p.name), <String>[
        'Zeta',
        'Alpha',
        'Alpha',
      ]);
    });

    test('a missing permission name is a format error', () {
      expect(
        () => VendorRolePermissionParser.parseList(<Map<String, Object?>>[
          permissionRow(name: null),
        ]),
        throwsA(isA<VendorRoleFormatException>()),
      );
    });

    test('a blank permission name is a format error', () {
      expect(
        () => VendorRolePermissionParser.parseList(<Map<String, Object?>>[
          permissionRow(name: '   '),
        ]),
        throwsA(isA<VendorRoleFormatException>()),
      );
    });

    test('a permission description of the wrong type is a format error', () {
      expect(
        () => VendorRolePermissionParser.parseList(<Map<String, Object?>>[
          permissionRow(description: 99),
        ]),
        throwsA(isA<VendorRoleFormatException>()),
      );
    });

    test('one malformed row fails the whole companion read', () {
      // The list length is guaranteed by the backend to equal permission_count.
      // Dropping a row would silently break that invariant on screen.
      expect(
        () => VendorRolePermissionParser.parseList(<Map<String, Object?>>[
          permissionRow(),
          permissionRow(name: null),
        ]),
        throwsA(isA<VendorRoleFormatException>()),
      );
    });

    test('a body that is not a list is a format error', () {
      expect(
        () => VendorRolePermissionParser.parseList('permissions'),
        throwsA(isA<VendorRoleFormatException>()),
      );
    });
  });

  group('what the contract does not carry', () {
    test('a role row exposes no code, scope, kind or organization', () {
      // Read off the *fixture* rather than the entity: the point is that the
      // shape this build parses has no such field to read.
      final Map<String, Object?> row = roleRow();

      for (final String absent in <String>[
        'role_code',
        'code',
        'role_kind',
        'is_system',
        'is_custom',
        'is_editable',
        'organization_id',
        'role_updated_at',
        'active_permission_count',
      ]) {
        expect(row.containsKey(absent), isFalse, reason: '$absent is returned');
      }
    });

    test('a permission row exposes no code, module, id or status', () {
      final Map<String, Object?> row = permissionRow();

      expect(row.keys, <String>['permission_name', 'permission_description']);
      for (final String absent in <String>[
        'permission_code',
        'permission_id',
        'module',
        'permission_status',
        'status',
      ]) {
        expect(row.containsKey(absent), isFalse, reason: '$absent is returned');
      }
    });

    test('nothing infers a scope or a kind from a role name', () {
      // A Retailer role definition parses exactly like a Vendor one. There is no
      // property on the entity that could carry an inferred taxonomy.
      final VendorRoleSummary retailerRole = VendorRoleSummaryParser.parse(
        roleRow(roleId: retailerOwnerRoleUuid, roleName: 'Retailer Owner'),
      );

      expect(retailerRole.roleName, 'Retailer Owner');
      expect(retailerRole.status, VendorRoleStatus.active);
      expect(retailerRole.props, hasLength(7));
    });
  });

  group('the id shape guard', () {
    test('accepts a well-formed uuid', () {
      expect(isRoleIdShaped(superAdminRoleUuid), isTrue);
      expect(isRoleIdShaped(unknownRoleUuid), isTrue);
    });

    test('rejects anything else', () {
      for (final String bad in <String>[
        'not-a-uuid',
        '',
        '   ',
        'VENDOR_SUPER_ADMIN',
        '1a2b3c4d-5e6f-4071-8293-a4b5c6d7e8f',
        '1a2b3c4d5e6f40718293a4b5c6d7e8f9',
      ]) {
        expect(isRoleIdShaped(bad), isFalse, reason: '"$bad" was accepted');
      }
    });
  });
}
