import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/dashboard/data/models/retailer_owner_overview_parser.dart';
import 'package:sale_reward/features/dashboard/domain/entities/retailer_owner_overview.dart';

import '../../support/retailer_owner_overview_fakes.dart';

/// `get_retailer_owner_portal_context()` body parsing.
///
/// The contract returns **at most one row** of seven display values, rendered by
/// PostgREST as a JSON array. These tests fix the three answers apart — a row,
/// a well-formed empty set, and a body this build cannot read — because
/// collapsing any pair of them puts something false on screen: an empty set
/// shown as zeros claims a Retailer has no shops, and a malformed body shown as
/// an empty set claims the account is not eligible.
void main() {
  /// The row, as a one-element array.
  List<Object?> body(Map<String, Object?> row) => <Object?>[row];

  RetailerOwnerOverview parseRow(Map<String, Object?> row) {
    final ParsedRetailerOverview parsed = RetailerOwnerOverviewParser.parse(
      body(row),
    );
    return (parsed as ParsedRetailerOverviewRow).overview;
  }

  Matcher throwsFormat() =>
      throwsA(isA<RetailerOwnerOverviewFormatException>());

  group('a valid row', () {
    test('parses every one of the seven values', () {
      final RetailerOwnerOverview overview = parseRow(retailerOverviewRow());

      expect(overview.retailerName, 'Northwind Retail');
      expect(overview.retailerStatus, RetailerLifecycleStatus.active);
      expect(overview.countryCode, 'AE');
      expect(overview.defaultCurrency, 'AED');
      expect(overview.membershipStatus, RetailerMembershipStatus.active);
      expect(overview.totalShopCount, 12);
      expect(overview.activeShopCount, 9);
      expect(overview.inactiveShopCount, 3);
      expect(overview.isFullyActive, isTrue);
    });

    test('zero shops is a real answer, not an absence', () {
      final RetailerOwnerOverview overview = parseRow(
        retailerOverviewRow(totalShopCount: 0, activeShopCount: 0),
      );

      expect(overview.totalShopCount, 0);
      expect(overview.activeShopCount, 0);
      expect(overview.inactiveShopCount, 0);
    });

    test('equal active and total counts are accepted', () {
      // The boundary of the subset rule: every shop active is legal.
      final RetailerOwnerOverview overview = parseRow(
        retailerOverviewRow(totalShopCount: 5, activeShopCount: 5),
      );
      expect(overview.inactiveShopCount, 0);
    });
  });

  group('row count', () {
    test('zero rows is a well-formed empty answer, never an error', () {
      // The single answer the backend gives every ineligible caller. It must not
      // become a format exception, because a failure state offers a retry that
      // could not possibly change the answer.
      expect(
        RetailerOwnerOverviewParser.parse(<Object?>[]),
        isA<ParsedRetailerOverviewEmpty>(),
      );
    });

    test('two rows are rejected rather than truncated to the first', () {
      // Impossible against the deployed contract, so it means this build and the
      // backend disagree. Taking the first would render figures whose
      // organization is a coin toss.
      expect(
        () => RetailerOwnerOverviewParser.parse(<Object?>[
          retailerOverviewRow(),
          retailerOverviewRow(retailerName: 'Someone Else'),
        ]),
        throwsFormat(),
      );
    });

    test('a body that is not a list is rejected', () {
      expect(
        () => RetailerOwnerOverviewParser.parse(retailerOverviewRow()),
        throwsFormat(),
      );
      expect(() => RetailerOwnerOverviewParser.parse(null), throwsFormat());
      expect(() => RetailerOwnerOverviewParser.parse('rows'), throwsFormat());
    });

    test('a row that is not an object is rejected', () {
      expect(
        () => RetailerOwnerOverviewParser.parse(<Object?>['a row']),
        throwsFormat(),
      );
    });
  });

  group('required fields', () {
    test('a null or missing retailer_name is rejected', () {
      expect(
        () => parseRow(retailerOverviewRow(retailerName: null)),
        throwsFormat(),
      );
      final Map<String, Object?> without = retailerOverviewRow()
        ..remove('retailer_name');
      expect(() => parseRow(without), throwsFormat());
    });

    test('a blank retailer_name is rejected', () {
      // `organizations_name_not_empty` guarantees a non-empty name, so a blank
      // one is evidence the response is not this shape. Rendering it would
      // produce a page titled with nothing.
      expect(
        () => parseRow(retailerOverviewRow(retailerName: '   ')),
        throwsFormat(),
      );
    });

    test('a non-string retailer_name is rejected', () {
      expect(
        () => parseRow(retailerOverviewRow(retailerName: 42)),
        throwsFormat(),
      );
    });

    test('a null or non-string status is rejected on both fields', () {
      expect(
        () => parseRow(retailerOverviewRow(retailerStatus: null)),
        throwsFormat(),
      );
      expect(
        () => parseRow(retailerOverviewRow(membershipStatus: null)),
        throwsFormat(),
      );
      expect(
        () => parseRow(retailerOverviewRow(retailerStatus: 1)),
        throwsFormat(),
      );
    });
  });

  group('status vocabulary', () {
    test('every deployed organization status is recognised', () {
      for (final (String code, RetailerLifecycleStatus expected)
          in <(String, RetailerLifecycleStatus)>[
            ('ACTIVE', RetailerLifecycleStatus.active),
            ('SUSPENDED', RetailerLifecycleStatus.suspended),
            ('DEACTIVATED', RetailerLifecycleStatus.deactivated),
          ]) {
        expect(
          parseRow(retailerOverviewRow(retailerStatus: code)).retailerStatus,
          expected,
        );
      }
    });

    test('every deployed membership status is recognised', () {
      // INVITED exists here and nowhere in the organization vocabulary, which is
      // why the two are separate enums.
      for (final (String code, RetailerMembershipStatus expected)
          in <(String, RetailerMembershipStatus)>[
            ('INVITED', RetailerMembershipStatus.invited),
            ('ACTIVE', RetailerMembershipStatus.active),
            ('SUSPENDED', RetailerMembershipStatus.suspended),
            ('DEACTIVATED', RetailerMembershipStatus.deactivated),
          ]) {
        expect(
          parseRow(
            retailerOverviewRow(membershipStatus: code),
          ).membershipStatus,
          expected,
        );
      }
    });

    test('an unrecognised status token degrades to unknown, not to active', () {
      // Additive forward compatibility: a newer backend value must not fail the
      // whole read, and must never arrive at "active" by failing to match
      // something else.
      final RetailerOwnerOverview overview = parseRow(
        retailerOverviewRow(
          retailerStatus: 'ARCHIVED',
          membershipStatus: 'PROBATION',
        ),
      );

      expect(overview.retailerStatus, RetailerLifecycleStatus.unknown);
      expect(overview.membershipStatus, RetailerMembershipStatus.unknown);
      expect(overview.retailerStatus.isActive, isFalse);
      expect(overview.membershipStatus.isActive, isFalse);
      expect(overview.isFullyActive, isFalse);
    });

    test('an unknown status never carries the raw token to the label', () {
      final RetailerOwnerOverview overview = parseRow(
        retailerOverviewRow(retailerStatus: 'SOME_INTERNAL_TOKEN'),
      );
      expect(overview.retailerStatus.label, 'Unknown');
      expect(overview.retailerStatus.label, isNot(contains('INTERNAL')));
    });
  });

  group('nullable code columns', () {
    test('a null country or currency is a real answer', () {
      final RetailerOwnerOverview overview = parseRow(
        retailerOverviewRow(countryCode: null, defaultCurrency: null),
      );

      // Never defaulted to a country or a currency.
      expect(overview.countryCode, isNull);
      expect(overview.defaultCurrency, isNull);
    });

    test('a missing key is treated the same as null', () {
      final Map<String, Object?> row = retailerOverviewRow()
        ..remove('country_code')
        ..remove('default_currency');
      final RetailerOwnerOverview overview = parseRow(row);

      expect(overview.countryCode, isNull);
      expect(overview.defaultCurrency, isNull);
    });

    test('a blank code is treated as not recorded', () {
      final RetailerOwnerOverview overview = parseRow(
        retailerOverviewRow(countryCode: '  ', defaultCurrency: ''),
      );
      expect(overview.countryCode, isNull);
      expect(overview.defaultCurrency, isNull);
    });

    test('a non-string code is rejected', () {
      expect(
        () => parseRow(retailerOverviewRow(countryCode: 971)),
        throwsFormat(),
      );
    });

    test('an unfamiliar code length is displayed, not refused', () {
      // The schema enforces the lengths at write time. Re-asserting them here
      // would refuse to display a value the database has already accepted.
      final RetailerOwnerOverview overview = parseRow(
        retailerOverviewRow(defaultCurrency: 'USDT'),
      );
      expect(overview.defaultCurrency, 'USDT');
    });
  });

  group('counts', () {
    test('a null or missing count is rejected on both fields', () {
      expect(
        () => parseRow(retailerOverviewRow(totalShopCount: null)),
        throwsFormat(),
      );
      expect(
        () => parseRow(retailerOverviewRow(activeShopCount: null)),
        throwsFormat(),
      );
      final Map<String, Object?> without = retailerOverviewRow()
        ..remove('total_shop_count');
      expect(() => parseRow(without), throwsFormat());
    });

    test('a negative count is rejected rather than clamped to zero', () {
      // `count(*)` cannot be negative, so this is evidence the response is not
      // the expected one. Clamping would state a fact the backend never sent.
      expect(
        () => parseRow(retailerOverviewRow(totalShopCount: -1)),
        throwsFormat(),
      );
      expect(
        () => parseRow(
          retailerOverviewRow(totalShopCount: 5, activeShopCount: -2),
        ),
        throwsFormat(),
      );
    });

    test('an active count above the total is rejected', () {
      // The active set is a subset of the total by construction, so the pair
      // cannot both be true — and cannot be repaired by picking one.
      expect(
        () => parseRow(
          retailerOverviewRow(totalShopCount: 3, activeShopCount: 4),
        ),
        throwsFormat(),
      );
    });

    test('a floating-point count is rejected rather than rounded', () {
      // A double large enough to matter has already been rounded, so converting
      // it would launder a wrong number into a confident one.
      expect(
        () => parseRow(retailerOverviewRow(totalShopCount: 12.0)),
        throwsFormat(),
      );
    });

    test('a numeric string is rejected', () {
      expect(
        () => parseRow(retailerOverviewRow(activeShopCount: '9')),
        throwsFormat(),
      );
    });

    test('a count beyond exact integer range is rejected', () {
      // Above 2^53-1 the value has already lost precision on Flutter web. It is
      // refused on every platform so the app and the web portal cannot quietly
      // disagree about the same figure.
      expect(
        () => parseRow(
          retailerOverviewRow(
            totalShopCount: maxSafeRetailerShopCount + 1,
            activeShopCount: 0,
          ),
        ),
        throwsFormat(),
      );
    });

    test('the exact-range boundary itself is accepted', () {
      final RetailerOwnerOverview overview = parseRow(
        retailerOverviewRow(
          totalShopCount: maxSafeRetailerShopCount,
          activeShopCount: maxSafeRetailerShopCount,
        ),
      );
      expect(overview.totalShopCount, maxSafeRetailerShopCount);
    });
  });

  group('forward compatibility', () {
    test('unexpected extra fields are ignored', () {
      // The contract is explicitly additive; a new column must not break an old
      // client.
      final Map<String, Object?> row = retailerOverviewRow()
        ..['loyalty_tier'] = 'GOLD'
        ..['pending_invitation_count'] = 3
        ..['future_object'] = <String, Object?>{'nested': true};

      final RetailerOwnerOverview overview = parseRow(row);

      expect(overview.retailerName, 'Northwind Retail');
      expect(overview.totalShopCount, 12);
    });

    test('no identifier is read even when the backend sends one', () {
      // The deployed contract returns no UUID. If a future one did, nothing in
      // the entity could hold it — this asserts that the parser does not begin
      // carrying identifiers just because they appear.
      final Map<String, Object?> row = retailerOverviewRow()
        ..['organization_id'] = '11111111-1111-1111-1111-111111111111'
        ..['membership_id'] = '33333333-3333-3333-3333-333333333333';

      final RetailerOwnerOverview overview = parseRow(row);

      expect(
        overview.props.whereType<String>(),
        isNot(contains(contains('1111-1111'))),
      );
      expect(overview.props, hasLength(7));
    });
  });
}
