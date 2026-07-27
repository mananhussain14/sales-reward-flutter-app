import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/parsing/rpc_row.dart';
import 'package:sale_reward/features/products/data/models/retailer_assigned_product_parser.dart';
import 'package:sale_reward/features/products/domain/entities/retailer_assigned_product.dart';

/// `list_retailer_assigned_products()` body parsing.
///
/// The contract returns `product_id`; this client deliberately drops it, which
/// is one of the two things these tests exist to pin. The other is that only
/// currently-active assignments exist in the answer at all.
void main() {
  Map<String, Object?> row({
    Object? productCode = 'ESP-1000',
    Object? productName = 'Espresso Blend 1kg',
    Object? barcode = '5012345678900',
    Object? brand = 'Aurora',
    Object? description = 'A dark roast blend.',
    Object? assignmentStatus = 'ACTIVE',
  }) => <String, Object?>{
    'product_id': '55555555-5555-5555-5555-555555555555',
    'product_code': productCode,
    'barcode': barcode,
    'product_name': productName,
    'brand': brand,
    'description': description,
    'assignment_status': assignmentStatus,
  };

  Matcher throwsFormat() => throwsA(isA<RpcFormatException>());

  group('valid rows', () {
    test('every displayed column parses', () {
      final RetailerAssignedProduct p = RetailerAssignedProductParser.parse(
        <Object?>[row()],
      ).single;

      expect(p.productCode, 'ESP-1000');
      expect(p.productName, 'Espresso Blend 1kg');
      expect(p.barcode, '5012345678900');
      expect(p.brand, 'Aurora');
      expect(p.description, 'A dark roast blend.');
      expect(p.assignmentStatus, 'ACTIVE');
      expect(p.isActiveAssignment, isTrue);
    });

    test('an empty body is a real answer', () {
      expect(RetailerAssignedProductParser.parse(<Object?>[]), isEmpty);
    });

    test('rows keep the backend order', () {
      final List<RetailerAssignedProduct> products =
          RetailerAssignedProductParser.parse(<Object?>[
            row(productName: 'Alpha'),
            row(productName: 'Beta'),
          ]);
      expect(
        products.map((RetailerAssignedProduct p) => p.productName),
        <String>['Alpha', 'Beta'],
      );
    });
  });

  group('nullable columns', () {
    test('a product with only the required columns parses', () {
      final RetailerAssignedProduct p = RetailerAssignedProductParser.parse(
        <Object?>[row(barcode: null, brand: null, description: null)],
      ).single;

      expect(p.barcode, isNull);
      expect(p.brand, isNull);
      expect(p.description, isNull);
    });

    test('missing optional keys are the same as null', () {
      final Map<String, Object?> sparse = row()
        ..remove('barcode')
        ..remove('brand')
        ..remove('description');
      final RetailerAssignedProduct p = RetailerAssignedProductParser.parse(
        <Object?>[sparse],
      ).single;

      expect(p.barcode, isNull);
      expect(p.brand, isNull);
    });

    test('a numeric barcode is rejected rather than stringified', () {
      // A number that has been through a JSON parser has already lost its
      // leading zeros, and a GTIN with a leading zero is a different barcode.
      expect(
        () =>
            RetailerAssignedProductParser.parse(<Object?>[row(barcode: 5012)]),
        throwsFormat(),
      );
    });

    test('a non-string brand or description is rejected', () {
      expect(
        () => RetailerAssignedProductParser.parse(<Object?>[row(brand: 7)]),
        throwsFormat(),
      );
      expect(
        () => RetailerAssignedProductParser.parse(<Object?>[
          row(description: <String>['a']),
        ]),
        throwsFormat(),
      );
    });
  });

  group('required columns', () {
    test('a null, missing or blank code or name is rejected', () {
      for (final String key in <String>['product_code', 'product_name']) {
        final Map<String, Object?> nulled = row()..[key] = null;
        expect(
          () => RetailerAssignedProductParser.parse(<Object?>[nulled]),
          throwsFormat(),
          reason: key,
        );

        final Map<String, Object?> blank = row()..[key] = '   ';
        expect(
          () => RetailerAssignedProductParser.parse(<Object?>[blank]),
          throwsFormat(),
          reason: key,
        );

        final Map<String, Object?> missing = row()..remove(key);
        expect(
          () => RetailerAssignedProductParser.parse(<Object?>[missing]),
          throwsFormat(),
          reason: key,
        );
      }
    });

    test('a malformed assignment_status is rejected', () {
      expect(
        () => RetailerAssignedProductParser.parse(<Object?>[
          row(assignmentStatus: null),
        ]),
        throwsFormat(),
      );
      expect(
        () => RetailerAssignedProductParser.parse(<Object?>[
          row(assignmentStatus: 1),
        ]),
        throwsFormat(),
      );
    });

    test('an unfamiliar assignment_status token is carried, not rejected', () {
      // It is display data that nothing branches on, so an unfamiliar value is
      // not worth failing a catalogue over. What is validated is that it is
      // present and a string — the part that would signal a different shape.
      final RetailerAssignedProduct p = RetailerAssignedProductParser.parse(
        <Object?>[row(assignmentStatus: 'PROVISIONAL')],
      ).single;

      expect(p.assignmentStatus, 'PROVISIONAL');
      expect(p.isActiveAssignment, isFalse);
    });

    test('one malformed row fails the whole catalogue', () {
      expect(
        () => RetailerAssignedProductParser.parse(<Object?>[
          row(),
          row(productCode: null),
        ]),
        throwsFormat(),
      );
    });
  });

  group('shape', () {
    test('a body that is not a list is rejected', () {
      expect(() => RetailerAssignedProductParser.parse(row()), throwsFormat());
      expect(() => RetailerAssignedProductParser.parse(null), throwsFormat());
    });

    test('a row that is not an object is rejected', () {
      expect(
        () => RetailerAssignedProductParser.parse(<Object?>['a product']),
        throwsFormat(),
      );
    });

    test('unexpected extra fields are ignored', () {
      final Map<String, Object?> extra = row()
        ..['vendor_name'] = 'Aurora Foods'
        ..['assigned_at'] = '2026-01-01T00:00:00Z';

      expect(
        RetailerAssignedProductParser.parse(<Object?>[
          extra,
        ]).single.productName,
        'Espresso Blend 1kg',
      );
    });

    test('product_id is never carried', () {
      final RetailerAssignedProduct p = RetailerAssignedProductParser.parse(
        <Object?>[row()],
      ).single;

      expect(p.props, hasLength(6));
      expect(
        p.props.whereType<String>().join(' '),
        isNot(contains('5555-5555')),
      );
    });
  });

  group('duplicates', () {
    test('two identical-looking products are both kept', () {
      // Without product_id there is no key on which a genuine duplicate could be
      // told from two similar products, so neither is hidden.
      final List<RetailerAssignedProduct> products =
          RetailerAssignedProductParser.parse(<Object?>[row(), row()]);

      expect(products, hasLength(2));
      expect(products.first, products.last);
    });
  });
}
