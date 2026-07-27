import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/parsing/rpc_row.dart';
import 'package:sale_reward/features/shops/data/models/retailer_shop_parser.dart';
import 'package:sale_reward/features/shops/domain/entities/retailer_shop.dart';

/// `list_retailer_owner_portal_shops()` body parsing.
///
/// The contract returns five display columns and **no `shop_id`**, which is the
/// fact these tests exist to pin: nothing in the parsed entity is an
/// identifier, and nothing may become one.
void main() {
  Map<String, Object?> row({
    Object? shopName = 'Northwind Marina',
    Object? shopCode = 'NW-01',
    Object? city = 'Dubai',
    Object? countryCode = 'AE',
    Object? shopStatus = 'ACTIVE',
  }) => <String, Object?>{
    'shop_name': shopName,
    'shop_code': shopCode,
    'city': city,
    'country_code': countryCode,
    'shop_status': shopStatus,
  };

  Matcher throwsFormat() => throwsA(isA<RpcFormatException>());

  group('valid rows', () {
    test('every column parses', () {
      final List<RetailerShop> shops = RetailerShopParser.parse(<Object?>[
        row(),
      ]);

      expect(shops, hasLength(1));
      expect(shops.single.name, 'Northwind Marina');
      expect(shops.single.code, 'NW-01');
      expect(shops.single.city, 'Dubai');
      expect(shops.single.countryCode, 'AE');
      expect(shops.single.status, RetailerShopStatus.active);
    });

    test('an empty body is an empty estate, not an error', () {
      // A real, successful answer — and on this contract an ambiguous one, since
      // an unauthorized caller receives exactly the same thing.
      expect(RetailerShopParser.parse(<Object?>[]), isEmpty);
    });

    test('rows keep the backend order', () {
      final List<RetailerShop> shops = RetailerShopParser.parse(<Object?>[
        row(shopName: 'A Shop'),
        row(shopName: 'B Shop'),
      ]);
      expect(shops.map((RetailerShop s) => s.name), <String>[
        'A Shop',
        'B Shop',
      ]);
    });
  });

  group('nullable columns', () {
    test('a shop recorded with a name alone parses', () {
      final RetailerShop shop = RetailerShopParser.parse(<Object?>[
        row(shopCode: null, city: null, countryCode: null),
      ]).single;

      expect(shop.code, isNull);
      expect(shop.city, isNull);
      expect(shop.countryCode, isNull);
      expect(shop.hasOnlyName, isTrue);
    });

    test('missing optional keys are the same as null', () {
      final Map<String, Object?> sparse = row()
        ..remove('shop_code')
        ..remove('city')
        ..remove('country_code');
      final RetailerShop shop = RetailerShopParser.parse(<Object?>[
        sparse,
      ]).single;

      expect(shop.code, isNull);
      expect(shop.city, isNull);
    });

    test('a blank optional column is treated as not recorded', () {
      final RetailerShop shop = RetailerShopParser.parse(<Object?>[
        row(shopCode: '   ', city: ''),
      ]).single;

      expect(shop.code, isNull);
      expect(shop.city, isNull);
    });

    test('a non-string optional column is rejected', () {
      expect(
        () => RetailerShopParser.parse(<Object?>[row(city: 42)]),
        throwsFormat(),
      );
    });
  });

  group('required columns', () {
    test('a null, missing or blank shop_name is rejected', () {
      expect(
        () => RetailerShopParser.parse(<Object?>[row(shopName: null)]),
        throwsFormat(),
      );
      expect(
        () => RetailerShopParser.parse(<Object?>[row(shopName: '  ')]),
        throwsFormat(),
      );
      final Map<String, Object?> without = row()..remove('shop_name');
      expect(
        () => RetailerShopParser.parse(<Object?>[without]),
        throwsFormat(),
      );
    });

    test('a null or non-string shop_status is rejected', () {
      expect(
        () => RetailerShopParser.parse(<Object?>[row(shopStatus: null)]),
        throwsFormat(),
      );
      expect(
        () => RetailerShopParser.parse(<Object?>[row(shopStatus: 3)]),
        throwsFormat(),
      );
    });

    test('one malformed row fails the whole list', () {
      // Skipping it would silently under-report the estate, and nothing on
      // screen would say so.
      expect(
        () => RetailerShopParser.parse(<Object?>[row(), row(shopName: null)]),
        throwsFormat(),
      );
    });
  });

  group('status vocabulary', () {
    test('every deployed status is recognised', () {
      for (final (String code, RetailerShopStatus expected)
          in <(String, RetailerShopStatus)>[
            ('ACTIVE', RetailerShopStatus.active),
            ('SUSPENDED', RetailerShopStatus.suspended),
            ('DEACTIVATED', RetailerShopStatus.deactivated),
          ]) {
        expect(
          RetailerShopParser.parse(<Object?>[
            row(shopStatus: code),
          ]).single.status,
          expected,
        );
      }
    });

    test('an invalid status degrades to unknown, never to active', () {
      final RetailerShop shop = RetailerShopParser.parse(<Object?>[
        row(shopStatus: 'CLOSED_FOR_REFIT'),
      ]).single;

      expect(shop.status, RetailerShopStatus.unknown);
      expect(shop.status.isActive, isFalse);
      // And the raw token never becomes the label.
      expect(shop.status.label, 'Unknown');
      expect(shop.status.label, isNot(contains('REFIT')));
    });
  });

  group('shape', () {
    test('a body that is not a list is rejected', () {
      expect(() => RetailerShopParser.parse(row()), throwsFormat());
      expect(() => RetailerShopParser.parse(null), throwsFormat());
    });

    test('a row that is not an object is rejected', () {
      expect(
        () => RetailerShopParser.parse(<Object?>['a shop']),
        throwsFormat(),
      );
    });

    test('unexpected extra fields are ignored', () {
      final Map<String, Object?> extra = row()
        ..['region'] = 'Gulf'
        ..['opened_at'] = '2026-01-01T00:00:00Z'
        ..['future'] = <String, Object?>{'nested': true};

      final RetailerShop shop = RetailerShopParser.parse(<Object?>[
        extra,
      ]).single;
      expect(shop.name, 'Northwind Marina');
    });

    test('a shop_id sent by a future backend is not carried', () {
      // The single most important property of this feature: no identifier
      // exists in the entity, so one cannot be rendered, persisted or sent.
      final Map<String, Object?> withId = row()
        ..['shop_id'] = '11111111-1111-1111-1111-111111111111';

      final RetailerShop shop = RetailerShopParser.parse(<Object?>[
        withId,
      ]).single;

      expect(shop.props, hasLength(5));
      expect(
        shop.props.whereType<String>().join(' '),
        isNot(contains('1111-1111')),
      );
    });
  });

  group('duplicate display fields', () {
    test('two identical-looking shops are both kept', () {
      // With no id in the contract there is no way to tell a genuine duplicate
      // from two distinct shops that look alike, so neither is hidden.
      final List<RetailerShop> shops = RetailerShopParser.parse(<Object?>[
        row(),
        row(),
      ]);

      expect(shops, hasLength(2));
      expect(shops.first, shops.last);
    });

    test('the presentation key collides for them, and that is harmless', () {
      // It exists only so Flutter can diff a list. Nothing keyed on it is
      // addressable: there is no detail screen, no selection and no write.
      final List<RetailerShop> shops = RetailerShopParser.parse(<Object?>[
        row(),
        row(),
      ]);

      expect(shops.first.presentationKey, shops.last.presentationKey);
    });

    test('the presentation key separates shops that differ in any field', () {
      final List<RetailerShop> shops = RetailerShopParser.parse(<Object?>[
        row(),
        row(shopCode: 'NW-02'),
        row(city: 'Sharjah'),
        row(shopStatus: 'SUSPENDED'),
      ]);

      expect(
        shops.map((RetailerShop s) => s.presentationKey).toSet(),
        hasLength(4),
      );
    });
  });
}
