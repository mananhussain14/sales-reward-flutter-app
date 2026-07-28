import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/parsing/rpc_row.dart';
import 'package:sale_reward/features/staff/data/models/retailer_staff_shop_assignment_parser.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_shop_assignment.dart';

/// `set_retailer_staff_shop_assignments()` response parsing.
///
/// This parser sits behind a **committed write**, which is what makes its
/// strictness load-bearing: substituting a zero for a count it could not read
/// would report "nothing changed" about a transaction that may have retired
/// three shops and added two. So every malformation is refused, and the
/// repository turns the refusal into "the result could not be read" — never into
/// a change summary the backend did not send, and never into "the write failed".
void main() {
  Matcher throwsFormat() => throwsA(isA<RpcFormatException>());

  Map<String, Object?> row({
    Object? added = 1,
    Object? removed = 1,
    Object? unchanged = 1,
  }) => <String, Object?>{
    'shops_added': added,
    'shops_removed': removed,
    'shops_unchanged': unchanged,
  };

  group('a valid single-row result', () {
    test('parses all three counts', () {
      final RetailerStaffShopAssignmentChange change =
          RetailerStaffShopAssignmentParser.parse(<Object?>[
            row(added: 1, removed: 2, unchanged: 3),
          ]);

      expect(change.shopsAdded, 1);
      expect(change.shopsRemoved, 2);
      expect(change.shopsUnchanged, 3);
    });

    test('all-zero counts are a real answer, not an error', () {
      // Submitting exactly the set a member already holds is a valid, committed
      // no-op. It must never be reported as a failure.
      final RetailerStaffShopAssignmentChange change =
          RetailerStaffShopAssignmentParser.parse(<Object?>[
            row(added: 0, removed: 0, unchanged: 0),
          ]);

      expect(change.shopsAdded, 0);
      expect(change.shopsRemoved, 0);
      expect(change.shopsUnchanged, 0);
      expect(change.hasChanges, isFalse);
    });

    test('hasChanges is true when anything moved, in either direction', () {
      expect(
        RetailerStaffShopAssignmentParser.parse(<Object?>[
          row(added: 1, removed: 0, unchanged: 4),
        ]).hasChanges,
        isTrue,
      );
      expect(
        RetailerStaffShopAssignmentParser.parse(<Object?>[
          row(added: 0, removed: 1, unchanged: 4),
        ]).hasChanges,
        isTrue,
      );
      // Unchanged rows alone are not a change.
      expect(
        RetailerStaffShopAssignmentParser.parse(<Object?>[
          row(added: 0, removed: 0, unchanged: 9),
        ]).hasChanges,
        isFalse,
      );
    });

    test('unrecognized extra fields are ignored', () {
      // The contract is additive. A column added by a later migration must not
      // break a client that does not need it.
      final RetailerStaffShopAssignmentChange change =
          RetailerStaffShopAssignmentParser.parse(<Object?>[
            row()
              ..['audit_log_id'] = '11111111-1111-1111-1111-111111111111'
              ..['shops_preserved'] = 2,
          ]);

      expect(change.shopsAdded, 1);
    });
  });

  group('the row count is exactly one', () {
    test('no row is refused, never read as zero of everything', () {
      // The function always projects one row. An empty array means the response
      // is not this contract, and reading it as all-zeros would invent a summary
      // the backend never sent.
      expect(
        () => RetailerStaffShopAssignmentParser.parse(const <Object?>[]),
        throwsFormat(),
      );
    });

    test('more than one row is refused rather than taking the first', () {
      // Two summaries for one call means the deployed function is not the one
      // this build expects. Picking one would be choosing arbitrarily between
      // two disagreeing answers.
      expect(
        () => RetailerStaffShopAssignmentParser.parse(<Object?>[row(), row()]),
        throwsFormat(),
      );
    });

    test('a body that is not a list is refused', () {
      for (final Object? body in <Object?>[
        null,
        42,
        'ok',
        <String, Object?>{'shops_added': 1},
      ]) {
        expect(
          () => RetailerStaffShopAssignmentParser.parse(body),
          throwsFormat(),
          reason: '$body',
        );
      }
    });

    test('a row that is not an object is refused', () {
      expect(
        () => RetailerStaffShopAssignmentParser.parse(<Object?>['nope']),
        throwsFormat(),
      );
    });
  });

  group('every count must be a non-negative integer', () {
    test('a missing field is refused', () {
      for (final String key in <String>[
        'shops_added',
        'shops_removed',
        'shops_unchanged',
      ]) {
        final Map<String, Object?> broken = row()..remove(key);
        expect(
          () => RetailerStaffShopAssignmentParser.parse(<Object?>[broken]),
          throwsFormat(),
          reason: key,
        );
      }
    });

    test('a null field is refused', () {
      for (final String key in <String>[
        'shops_added',
        'shops_removed',
        'shops_unchanged',
      ]) {
        final Map<String, Object?> broken = row()..[key] = null;
        expect(
          () => RetailerStaffShopAssignmentParser.parse(<Object?>[broken]),
          throwsFormat(),
          reason: key,
        );
      }
    });

    test('a non-integer value is refused, including a whole double', () {
      // PostgREST renders an `integer` column as a JSON integer, so a float
      // arriving here means the value did not come from the declared column —
      // and rounding it would be this build deciding what the backend meant.
      for (final Object? bad in <Object?>[
        '1',
        true,
        1.0,
        2.5,
        <Object?>[1],
      ]) {
        final Map<String, Object?> broken = row()..['shops_added'] = bad;
        expect(
          () => RetailerStaffShopAssignmentParser.parse(<Object?>[broken]),
          throwsFormat(),
          reason: '$bad',
        );
      }
    });

    test('a negative value is refused on every field', () {
      // Not a small number: impossible for a row count, and putting one in a
      // sentence would be worse than admitting the answer was unreadable.
      for (final String key in <String>[
        'shops_added',
        'shops_removed',
        'shops_unchanged',
      ]) {
        final Map<String, Object?> broken = row()..[key] = -1;
        expect(
          () => RetailerStaffShopAssignmentParser.parse(<Object?>[broken]),
          throwsFormat(),
          reason: key,
        );
      }
    });
  });

  test('the change type exposes no total', () {
    // `shopsAdded + shopsUnchanged` is not the number of shops a person works
    // in: assignments to non-ACTIVE shops are preserved by the write and counted
    // by none of these. There is deliberately no getter for anyone to reach for,
    // and the canonical roster is the authority.
    final RetailerStaffShopAssignmentChange change =
        RetailerStaffShopAssignmentParser.parse(<Object?>[row()]);

    expect(change.props, <Object?>[
      change.shopsAdded,
      change.shopsRemoved,
      change.shopsUnchanged,
    ]);
  });
}
