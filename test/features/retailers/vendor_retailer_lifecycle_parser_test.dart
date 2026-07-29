import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/retailers/data/models/vendor_retailer_lifecycle_parser.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_lifecycle_status.dart';

import '../../support/vendor_retailer_fakes.dart';
import '../../support/vendor_retailer_lifecycle_fakes.dart';

/// The strict `set_vendor_retailer_status` response parser.
///
/// **Null means "committed, but undescribable" — never "nothing happened".**
/// This function is only ever reached when nothing was thrown, which means the
/// transaction committed, so every rejection below describes a response this
/// build cannot trust rather than a write that failed. The repository maps every
/// one of them to `VendorRetailerWriteUnconfirmed`.
void main() {
  const String submitted = northwindRelationshipUuid;

  VendorRetailerLifecycleRow? parse(Object? raw, [String? expected]) =>
      parseVendorRetailerLifecycleRow(raw, expected ?? submitted);

  group('accepted responses', () {
    test('19. one valid matching row is accepted', () {
      final VendorRetailerLifecycleRow? row = parse(
        lifecycleRows(relationshipId: submitted),
      );

      expect(row, isNotNull);
      expect(row!.confirmedStatus, VendorRetailerLifecycleStatus.suspended);
      expect(row.statusChanged, isTrue);
    });

    test('a reactivation row is accepted', () {
      final VendorRetailerLifecycleRow? row = parse(
        lifecycleRows(
          relationshipId: submitted,
          retailerStatus: 'ACTIVE',
          relationshipStatus: 'ACTIVE',
          statusChanged: false,
        ),
      );

      expect(row!.confirmedStatus, VendorRetailerLifecycleStatus.active);
      // An idempotent no-op is an honest outcome, not a rejection.
      expect(row.statusChanged, isFalse);
    });

    test('20. an upper-cased matching UUID is accepted', () {
      // A UUID's canonical form differs only in case, and an upper-cased echo
      // addresses the same row. This is a check that the right ROW came back,
      // not a string-formatting check.
      final VendorRetailerLifecycleRow? row = parse(
        lifecycleRows(relationshipId: submitted.toUpperCase()),
      );

      expect(row, isNotNull);
    });

    test('an upper-cased SUBMITTED id is compared on equal terms', () {
      final VendorRetailerLifecycleRow? row = parse(
        lifecycleRows(relationshipId: submitted),
        submitted.toUpperCase(),
      );

      expect(row, isNotNull);
    });

    test('a bare single-row map is accepted', () {
      // Defensive: a transport that unwraps a single-row body is not drift.
      final VendorRetailerLifecycleRow? row = parse(
        lifecycleRow(relationshipId: submitted),
      );

      expect(row, isNotNull);
    });
  });

  group('rejected responses become unconfirmed', () {
    test('21. zero rows', () {
      expect(parse(<Map<String, Object?>>[]), isNull);
    });

    test('22. multiple rows', () {
      // Two rows would otherwise have the second silently discarded, which is
      // the more dangerous of the two failures and is refused explicitly.
      expect(
        parse(<Map<String, Object?>>[
          lifecycleRow(relationshipId: submitted),
          lifecycleRow(relationshipId: submitted),
        ]),
        isNull,
      );
    });

    test('23. a missing relationship_id', () {
      expect(parse(<Map<String, Object?>>[<String, Object?>{}]), isNull);
    });

    test('24. a null relationship_id', () {
      expect(parse(lifecycleRows(relationshipId: null)), isNull);
    });

    test('25. a non-string relationship_id', () {
      expect(parse(lifecycleRows(relationshipId: 42)), isNull);
      expect(parse(lifecycleRows(relationshipId: true)), isNull);
      expect(parse(lifecycleRows(relationshipId: <String>['a'])), isNull);
    });

    test('26. a malformed UUID', () {
      expect(parse(lifecycleRows(relationshipId: 'not-a-uuid')), isNull);
      expect(parse(lifecycleRows(relationshipId: '')), isNull);
      expect(parse(lifecycleRows(relationshipId: '$submitted-extra')), isNull);
    });

    test('27. a valid but DIFFERENT UUID', () {
      // The check that makes the other three worth doing: a response describing
      // another relationship must never be rendered as this one's outcome.
      expect(
        parse(lifecycleRows(relationshipId: contosoRelationshipUuid)),
        isNull,
      );
      expect(
        parse(lifecycleRows(relationshipId: foreignRelationshipUuid)),
        isNull,
      );
    });

    test('28. an invalid retailer_status', () {
      for (final Object? status in <Object?>[
        null,
        '',
        'INACTIVE',
        'DEACTIVATED',
        'active',
        'PAUSED',
        7,
        true,
      ]) {
        expect(
          parse(
            lifecycleRows(
              relationshipId: submitted,
              retailerStatus: status,
              relationshipStatus: status,
            ),
          ),
          isNull,
          reason: 'retailer_status $status must be refused',
        );
      }
    });

    test('29. an invalid relationship_status', () {
      for (final Object? status in <Object?>[
        null,
        '',
        'INACTIVE',
        'DEACTIVATED',
        'suspended',
        3.5,
      ]) {
        expect(
          parse(
            lifecycleRows(
              relationshipId: submitted,
              relationshipStatus: status,
            ),
          ),
          isNull,
          reason: 'relationship_status $status must be refused',
        );
      }
    });

    test('30. mismatched but individually valid statuses', () {
      // The operation moves both rows in one transaction, so a mismatched pair
      // coming back contradicts the function's own guarantee.
      expect(
        parse(
          lifecycleRows(
            relationshipId: submitted,
            retailerStatus: 'ACTIVE',
            relationshipStatus: 'SUSPENDED',
          ),
        ),
        isNull,
      );
      expect(
        parse(
          lifecycleRows(
            relationshipId: submitted,
            retailerStatus: 'SUSPENDED',
            relationshipStatus: 'ACTIVE',
          ),
        ),
        isNull,
      );
    });

    test('31. a missing status_changed', () {
      expect(
        parse(<Map<String, Object?>>[
          <String, Object?>{
            'relationship_id': submitted,
            'retailer_status': 'SUSPENDED',
            'relationship_status': 'SUSPENDED',
          },
        ]),
        isNull,
      );
    });

    test('32. a non-boolean status_changed', () {
      // Truthy is not enough: the difference between "you did that" and
      // "somebody already had" is decided by this flag.
      for (final Object? changed in <Object?>[null, 'true', 1, 0, <String>[]]) {
        expect(
          parse(
            lifecycleRows(relationshipId: submitted, statusChanged: changed),
          ),
          isNull,
          reason: 'status_changed $changed must be refused',
        );
      }
    });

    test('33. a malformed shape never throws', () {
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
    test('34. the validated relationship id is not carried out', () {
      final VendorRetailerLifecycleRow row = parse(
        lifecycleRows(relationshipId: submitted),
      )!;

      // The row type has exactly two fields, and neither is an identifier: the
      // id has done its job once it proves the response describes the row that
      // was addressed, and the screen already holds it from its own route.
      expect(
        row.toString().contains(submitted),
        isFalse,
        reason: 'the returned identifier must not survive the parser',
      );
    });

    test('a rejected response yields no value of any kind', () {
      // Nothing partial, nothing defaulted, nothing coerced — one null.
      expect(
        parse(lifecycleRows(relationshipId: foreignRelationshipUuid)),
        isNull,
      );
    });
  });
}
