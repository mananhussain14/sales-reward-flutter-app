import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/retailers/data/models/vendor_retailer_parsers.dart';
import 'package:sale_reward/features/retailers/domain/entities/retailer_owner_state.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_detail.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_shop.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_status.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_summary.dart';

import '../../support/vendor_retailer_fakes.dart';

/// The parsers are the boundary where an untrusted body becomes a trusted
/// value, so almost every test here is a *refusal*.
///
/// The rule they all serve: **a default is a value the backend never sent,
/// presented as though it had.** There is no branch anywhere in these parsers
/// that substitutes one — a shop with no status, a Retailer with no name and a
/// count that arrived as text are all format errors, and a format error becomes
/// a retryable outage rather than an empty list or a fabricated row.
void main() {
  group('summary — the happy path', () {
    test('parses every column of a well-formed row', () {
      final List<VendorRetailerSummary> parsed =
          VendorRetailerSummaryParser.parseList(retailerRows());

      expect(parsed, hasLength(2));

      final VendorRetailerSummary first = parsed.first;
      expect(first.relationshipId, northwindRelationshipUuid);
      expect(first.retailerOrganizationId, northwindOrganizationUuid);
      expect(first.retailerName, 'Northwind Retail');
      expect(first.retailerStatus, VendorRetailerStatus.active);
      expect(first.relationshipStatus, VendorRetailerStatus.active);
      expect(first.relationshipCreatedAt, DateTime.utc(2026, 3, 12, 8, 15));
      expect(first.shopCount, 4);
      expect(first.activeShopCount, 3);
      expect(first.ownerState, RetailerOwnerState.active);
      expect(first.inactiveShopCount, 1);
    });

    test('preserves the backend order rather than re-sorting', () {
      // The SQL orders by retailer_name then relationship_id. Re-sorting here
      // would be a second definition of "the directory order", and the two
      // clients would disagree the moment the definitions drifted.
      final List<VendorRetailerSummary> parsed =
          VendorRetailerSummaryParser.parseList(<Map<String, Object?>>[
            retailerRow(retailerName: 'Zulu Retail'),
            retailerRow(
              relationshipId: contosoRelationshipUuid,
              retailerName: 'Alpha Retail',
            ),
          ]);

      expect(parsed.map((VendorRetailerSummary r) => r.retailerName), <String>[
        'Zulu Retail',
        'Alpha Retail',
      ]);
    });

    test('an empty response is an empty list, not an error', () {
      // "This Vendor has not onboarded a Retailer yet" is a real answer.
      expect(VendorRetailerSummaryParser.parseList(const <Object?>[]), isEmpty);
    });

    test('accepts zero counts', () {
      final VendorRetailerSummary parsed = VendorRetailerSummaryParser.parse(
        retailerRow(shopCount: 0, activeShopCount: 0),
      );

      expect(parsed.shopCount, 0);
      expect(parsed.activeShopCount, 0);
      expect(parsed.inactiveShopCount, 0);
    });

    test('accepts an integral count delivered as a JSON number', () {
      // JSON has one number type; a transport is entitled to hand back 4.0.
      final VendorRetailerSummary parsed = VendorRetailerSummaryParser.parse(
        retailerRow(shopCount: 4.0, activeShopCount: 3.0),
      );

      expect(parsed.shopCount, 4);
      expect(parsed.activeShopCount, 3);
    });

    test('normalizes a non-UTC timestamp to UTC', () {
      final VendorRetailerSummary parsed = VendorRetailerSummaryParser.parse(
        retailerRow(createdAt: '2026-03-12T12:15:00+04:00'),
      );

      expect(parsed.relationshipCreatedAt.isUtc, isTrue);
      expect(parsed.relationshipCreatedAt, DateTime.utc(2026, 3, 12, 8, 15));
    });
  });

  group('summary — every status and owner state the backend can send', () {
    for (final (String token, VendorRetailerStatus expected)
        in <(String, VendorRetailerStatus)>[
          ('ACTIVE', VendorRetailerStatus.active),
          ('SUSPENDED', VendorRetailerStatus.suspended),
          ('DEACTIVATED', VendorRetailerStatus.deactivated),
        ]) {
      test('$token maps to $expected on both status columns', () {
        final VendorRetailerSummary parsed = VendorRetailerSummaryParser.parse(
          retailerRow(retailerStatus: token, relationshipStatus: token),
        );

        expect(parsed.retailerStatus, expected);
        expect(parsed.relationshipStatus, expected);
      });
    }

    for (final (String token, RetailerOwnerState expected)
        in <(String, RetailerOwnerState)>[
          ('ACTIVE', RetailerOwnerState.active),
          ('PENDING', RetailerOwnerState.pending),
          ('DELIVERY_FAILED', RetailerOwnerState.deliveryFailed),
          ('EXPIRED', RetailerOwnerState.expired),
          ('NONE', RetailerOwnerState.none),
        ]) {
      test('owner state $token maps to $expected', () {
        expect(
          VendorRetailerSummaryParser.parse(
            retailerRow(ownerState: token),
          ).ownerState,
          expected,
        );
      });
    }
  });

  group('summary — an unknown token degrades, and never upward', () {
    test('an unrecognised status is unknown, and unknown is not active', () {
      final VendorRetailerSummary parsed = VendorRetailerSummaryParser.parse(
        retailerRow(
          retailerStatus: 'ARCHIVED',
          relationshipStatus: 'TERMINATED',
        ),
      );

      expect(parsed.retailerStatus, VendorRetailerStatus.unknown);
      expect(parsed.relationshipStatus, VendorRetailerStatus.unknown);
      expect(parsed.retailerStatus.isActive, isFalse);
      expect(parsed.relationshipStatus.isActive, isFalse);
    });

    test('a lower-case token is not accepted as its upper-case twin', () {
      // The schema stores upper-case literals. Case-folding here would be the
      // client inventing an equivalence the database does not have.
      expect(
        VendorRetailerSummaryParser.parse(
          retailerRow(relationshipStatus: 'active'),
        ).relationshipStatus,
        VendorRetailerStatus.unknown,
      );
    });

    test(
      'an unrecognised owner state never reads as an accepted or active owner',
      () {
        final VendorRetailerSummary parsed = VendorRetailerSummaryParser.parse(
          retailerRow(ownerState: 'ACCEPTED'),
        );

        expect(parsed.ownerState, RetailerOwnerState.unknown);
        expect(parsed.ownerState.hasActiveOwner, isFalse);
        // Nor does it manufacture a problem to act on.
        expect(parsed.ownerState.needsAttention, isFalse);
      },
    );

    test('the raw token is not retained anywhere on the entity', () {
      final VendorRetailerSummary parsed = VendorRetailerSummaryParser.parse(
        retailerRow(relationshipStatus: 'TERMINATED'),
      );

      expect(parsed.relationshipStatus.code, isEmpty);
      expect(parsed.toString(), isNot(contains('TERMINATED')));
    });
  });

  group('summary — a malformed row is refused, never patched', () {
    void expectRefused(String what, Map<String, Object?> row) {
      test(what, () {
        expect(
          () => VendorRetailerSummaryParser.parse(row),
          throwsA(isA<VendorRetailerFormatException>()),
        );
      });
    }

    expectRefused(
      'a malformed relationship UUID',
      retailerRow(relationshipId: 'not-a-uuid'),
    );
    expectRefused(
      'a relationship UUID of the wrong length',
      retailerRow(relationshipId: '3f7c1a10-2b4d-4e6f-8a90-1b2c3d4e5f'),
    );
    expectRefused(
      'a malformed Retailer organization UUID',
      retailerRow(retailerOrganizationId: '12345'),
    );
    expectRefused(
      'a missing relationship id',
      retailerRow(relationshipId: null),
    );
    expectRefused('a missing name', retailerRow(retailerName: null));
    expectRefused('a blank name', retailerRow(retailerName: '   '));
    expectRefused(
      'a missing relationship status',
      retailerRow(relationshipStatus: null),
    );
    expectRefused('a blank Retailer status', retailerRow(retailerStatus: ''));
    expectRefused('a missing owner state', retailerRow(ownerState: null));
    expectRefused(
      'a malformed timestamp',
      retailerRow(createdAt: '12 March 2026'),
    );
    expectRefused('a numeric timestamp', retailerRow(createdAt: 1773907200));
    expectRefused('a missing timestamp', retailerRow(createdAt: null));
    expectRefused('a missing shop count', retailerRow(shopCount: null));
    expectRefused('a shop count sent as text', retailerRow(shopCount: '4'));
    expectRefused('a fractional shop count', retailerRow(shopCount: 4.5));
    expectRefused('a negative shop count', retailerRow(shopCount: -1));
    expectRefused(
      'a negative active shop count',
      retailerRow(activeShopCount: -2),
    );

    test('an active count larger than the total count', () {
      // `active_shop_count` is a filtered count over the rows `shop_count`
      // counts, so the backend cannot produce this pair. Rendering "2 shops (9
      // active)" would be worse than an honest retry.
      expect(
        () => VendorRetailerSummaryParser.parse(
          retailerRow(shopCount: 2, activeShopCount: 9),
        ),
        throwsA(isA<VendorRetailerFormatException>()),
      );
    });

    test('an active count equal to the total count is fine', () {
      expect(
        VendorRetailerSummaryParser.parse(
          retailerRow(shopCount: 3, activeShopCount: 3),
        ).inactiveShopCount,
        0,
      );
    });

    test('a body that is not a list', () {
      expect(
        () => VendorRetailerSummaryParser.parseList(<String, Object?>{}),
        throwsA(isA<VendorRetailerFormatException>()),
      );
    });

    test('a row that is not an object', () {
      expect(
        () => VendorRetailerSummaryParser.parseList(<Object?>['nope']),
        throwsA(isA<VendorRetailerFormatException>()),
      );
    });

    test('one malformed row fails the whole list', () {
      // A partially-rendered directory is a directory that is silently missing
      // Retailers, which is worse than a retry.
      expect(
        () => VendorRetailerSummaryParser.parseList(<Map<String, Object?>>[
          retailerRow(),
          retailerRow(relationshipId: 'broken'),
        ]),
        throwsA(isA<VendorRetailerFormatException>()),
      );
    });
  });

  group('detail — the single-row read', () {
    test('parses the list columns plus the two profile columns', () {
      final VendorRetailerDetail? parsed =
          VendorRetailerDetailParser.parseSingle(<Map<String, Object?>>[
            detailRow(),
          ]);

      expect(parsed, isNotNull);
      expect(parsed!.relationshipId, northwindRelationshipUuid);
      expect(parsed.retailerName, 'Northwind Retail');
      expect(parsed.countryCode, 'AE');
      expect(parsed.defaultCurrency, 'AED');
      expect(parsed.relationshipStatus, VendorRetailerStatus.active);
      expect(parsed.shopCount, 4);
      expect(parsed.activeShopCount, 3);
      expect(parsed.ownerState, RetailerOwnerState.active);
    });

    test('zero rows is null — the one non-leaking answer', () {
      // An unknown id, another Vendor's id and a null id all produce zero rows
      // in SQL. One representation for all three is what keeps this from being
      // an existence oracle.
      expect(VendorRetailerDetailParser.parseSingle(const <Object?>[]), isNull);
    });

    test(
      'a null country and currency are accepted — both columns are nullable',
      () {
        final VendorRetailerDetail? parsed =
            VendorRetailerDetailParser.parseSingle(<Map<String, Object?>>[
              detailRow(countryCode: null, defaultCurrency: null),
            ]);

        expect(parsed!.countryCode, isNull);
        expect(parsed.defaultCurrency, isNull);
      },
    );

    test('a blank country is normalized to null rather than rendered', () {
      final VendorRetailerDetail? parsed =
          VendorRetailerDetailParser.parseSingle(<Map<String, Object?>>[
            detailRow(countryCode: '   '),
          ]);

      expect(parsed!.countryCode, isNull);
    });

    test('a country of the wrong type is malformed, not "close enough"', () {
      expect(
        () => VendorRetailerDetailParser.parseSingle(<Map<String, Object?>>[
          detailRow(countryCode: 971),
        ]),
        throwsA(isA<VendorRetailerFormatException>()),
      );
    });

    test('several rows are refused — the function filters on a key', () {
      expect(
        () => VendorRetailerDetailParser.parseSingle(<Map<String, Object?>>[
          detailRow(),
          detailRow(),
        ]),
        throwsA(isA<VendorRetailerFormatException>()),
      );
    });

    test('an unknown status on the detail is unknown, not active', () {
      final VendorRetailerDetail? parsed =
          VendorRetailerDetailParser.parseSingle(<Map<String, Object?>>[
            detailRow(relationshipStatus: 'PAUSED'),
          ]);

      expect(parsed!.relationshipStatus, VendorRetailerStatus.unknown);
      expect(parsed.relationshipStatus.isActive, isFalse);
    });

    test('a negative count is refused on the detail too', () {
      expect(
        () => VendorRetailerDetailParser.parseSingle(<Map<String, Object?>>[
          detailRow(shopCount: -3),
        ]),
        throwsA(isA<VendorRetailerFormatException>()),
      );
    });

    test(
      'an active count exceeding the total is refused on the detail too',
      () {
        expect(
          () => VendorRetailerDetailParser.parseSingle(<Map<String, Object?>>[
            detailRow(shopCount: 1, activeShopCount: 4),
          ]),
          throwsA(isA<VendorRetailerFormatException>()),
        );
      },
    );
  });

  group('shops', () {
    test('parses every column of a well-formed row', () {
      final List<VendorRetailerShop> parsed =
          VendorRetailerShopParser.parseList(shopRows());

      expect(parsed, hasLength(2));
      expect(parsed.first.shopId, marinaShopUuid);
      expect(parsed.first.shopName, 'Marina Mall');
      expect(parsed.first.shopCode, 'MM-01');
      expect(parsed.first.city, 'Dubai');
      expect(parsed.first.countryCode, 'AE');
      expect(parsed.first.shopStatus, VendorRetailerStatus.active);
    });

    test('a shop with no code, city or country is legitimate', () {
      // All three columns are declared nullable in `retailer_shops`.
      final VendorRetailerShop parsed = VendorRetailerShopParser.parse(
        shopRow(shopCode: null, city: null, countryCode: null),
      );

      expect(parsed.shopCode, isNull);
      expect(parsed.city, isNull);
      expect(parsed.countryCode, isNull);
      expect(parsed.shopStatus, VendorRetailerStatus.active);
    });

    test('a blank code is normalized to null', () {
      // `retailer_shops_code_not_empty` forbids storing one, so a blank string
      // cannot be meaningful data.
      expect(
        VendorRetailerShopParser.parse(shopRow(shopCode: '  ')).shopCode,
        isNull,
      );
    });

    test('an empty shop list is a real answer', () {
      expect(VendorRetailerShopParser.parseList(const <Object?>[]), isEmpty);
    });

    test('the backend order is preserved', () {
      final List<VendorRetailerShop> parsed =
          VendorRetailerShopParser.parseList(<Map<String, Object?>>[
            shopRow(shopName: 'Zulu Store'),
            shopRow(shopId: airportShopUuid, shopName: 'Alpha Store'),
          ]);

      expect(parsed.map((VendorRetailerShop s) => s.shopName), <String>[
        'Zulu Store',
        'Alpha Store',
      ]);
    });

    test('every shop status maps, and an unknown one is not active', () {
      expect(
        VendorRetailerShopParser.parse(
          shopRow(shopStatus: 'SUSPENDED'),
        ).shopStatus,
        VendorRetailerStatus.suspended,
      );
      expect(
        VendorRetailerShopParser.parse(
          shopRow(shopStatus: 'DEACTIVATED'),
        ).shopStatus,
        VendorRetailerStatus.deactivated,
      );

      final VendorRetailerShop future = VendorRetailerShopParser.parse(
        shopRow(shopStatus: 'CLOSED_TEMPORARILY'),
      );
      expect(future.shopStatus, VendorRetailerStatus.unknown);
      expect(future.shopStatus.isActive, isFalse);
    });

    test('a missing status is refused — never inferred as active', () {
      // `retailer_shops.status` is NOT NULL. This is the one inference the
      // parser exists to refuse.
      expect(
        () => VendorRetailerShopParser.parse(shopRow(shopStatus: null)),
        throwsA(isA<VendorRetailerFormatException>()),
      );
    });

    test('a malformed shop id is refused', () {
      expect(
        () => VendorRetailerShopParser.parse(shopRow(shopId: 'shop-1')),
        throwsA(isA<VendorRetailerFormatException>()),
      );
    });

    test('a missing shop name is refused', () {
      expect(
        () => VendorRetailerShopParser.parse(shopRow(shopName: null)),
        throwsA(isA<VendorRetailerFormatException>()),
      );
    });

    test('a city of the wrong type is refused', () {
      expect(
        () => VendorRetailerShopParser.parse(shopRow(city: 12)),
        throwsA(isA<VendorRetailerFormatException>()),
      );
    });
  });

  group('the id-shape guard', () {
    test('accepts a well-formed UUID in either case', () {
      expect(isRelationshipIdShaped(northwindRelationshipUuid), isTrue);
      expect(
        isRelationshipIdShaped(northwindRelationshipUuid.toUpperCase()),
        isTrue,
      );
    });

    test('refuses everything else', () {
      for (final String malformed in <String>[
        '',
        '   ',
        'null',
        '1',
        'undefined',
        '3f7c1a10-2b4d-4e6f-8a90-1b2c3d4e5f6',
        '3f7c1a10-2b4d-4e6f-8a90-1b2c3d4e5f600',
        "3f7c1a10-2b4d-4e6f-8a90-1b2c3d4e5f60' or '1'='1",
      ]) {
        expect(
          isRelationshipIdShaped(malformed),
          isFalse,
          reason: '$malformed must not pass as a relationship id',
        );
      }
    });
  });

  group('no privileged default exists anywhere', () {
    test('there is no fallback that produces an ACTIVE anything', () {
      // Belt and braces over the individual cases above: for a row missing every
      // optional-looking field, the parser refuses rather than assembling a
      // Retailer out of defaults.
      expect(
        () => VendorRetailerSummaryParser.parse(const <String, Object?>{}),
        throwsA(isA<VendorRetailerFormatException>()),
      );
      expect(
        () => VendorRetailerShopParser.parse(const <String, Object?>{}),
        throwsA(isA<VendorRetailerFormatException>()),
      );
      expect(
        () => VendorRetailerDetailParser.parse(const <String, Object?>{}),
        throwsA(isA<VendorRetailerFormatException>()),
      );
    });

    test('the unknown members carry no backend token', () {
      expect(VendorRetailerStatus.unknown.code, isEmpty);
      expect(RetailerOwnerState.unknown.code, isEmpty);
    });

    test('fromCode never returns a member for an empty token', () {
      // The empty string is `unknown`'s own code; matching it would let a blank
      // value select a real member by accident.
      expect(VendorRetailerStatus.fromCode(''), VendorRetailerStatus.unknown);
      expect(RetailerOwnerState.fromCode(''), RetailerOwnerState.unknown);
    });
  });
}
