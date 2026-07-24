import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/receipts/data/models/receipt_parsers.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_product.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_shop.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_submission.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_submission_status.dart';

import '../../support/receipt_fakes.dart';

/// The parsers are the boundary between "what the backend said" and "what the
/// app believes". Everything below is an assertion that the boundary refuses to
/// guess: a malformed response becomes an exception the repository turns into an
/// operational failure, never a default, never an empty list, and never a value
/// the backend did not send.
void main() {
  group('shops', () {
    test('parses the three columns the RPC returns', () {
      final List<ReceiptShop> shops = ReceiptShopParser.parseList(shopRows());

      expect(shops, hasLength(2));
      expect(shops.first.shopId, shopAUuid);
      expect(shops.first.shopName, 'Marina Mall');
      expect(shops.first.shopCode, 'MM-01');
      expect(shops.first.displayLabel, 'Marina Mall · MM-01');
    });

    test('a null shop_code is supported — the column is nullable', () {
      final List<ReceiptShop> shops = ReceiptShopParser.parseList(shopRows());

      expect(shops[1].shopCode, isNull);
      expect(shops[1].displayLabel, 'Airport Kiosk');
    });

    test('an absent shop_code key is the same as a null one', () {
      final List<ReceiptShop> shops = ReceiptShopParser.parseList(
        <Map<String, Object?>>[
          <String, Object?>{'shop_id': shopAUuid, 'shop_name': 'Only'},
        ],
      );

      expect(shops.single.shopCode, isNull);
    });

    test('an empty list is a real answer, not a failure', () {
      expect(ReceiptShopParser.parseList(<Object?>[]), isEmpty);
    });

    test('a malformed shop id throws rather than being carried', () {
      expect(
        () => ReceiptShopParser.parseList(<Map<String, Object?>>[
          <String, Object?>{
            'shop_id': 'not-a-uuid',
            'shop_name': 'Marina Mall',
          },
        ]),
        throwsA(isA<ReceiptFormatException>()),
      );
    });

    test(
      'a missing shop_name throws rather than defaulting to a placeholder',
      () {
        expect(
          () => ReceiptShopParser.parseList(<Map<String, Object?>>[
            <String, Object?>{'shop_id': shopAUuid},
          ]),
          throwsA(isA<ReceiptFormatException>()),
        );
      },
    );

    test('a blank shop_name is missing, not empty', () {
      expect(
        () => ReceiptShopParser.parseList(<Map<String, Object?>>[
          <String, Object?>{'shop_id': shopAUuid, 'shop_name': '   '},
        ]),
        throwsA(isA<ReceiptFormatException>()),
      );
    });

    test('a body that is not a list throws', () {
      expect(
        () => ReceiptShopParser.parseList(<String, Object?>{'shop_id': 'x'}),
        throwsA(isA<ReceiptFormatException>()),
      );
      expect(
        () => ReceiptShopParser.parseList(null),
        throwsA(isA<ReceiptFormatException>()),
      );
    });

    test('a row that is not an object throws', () {
      expect(
        () => ReceiptShopParser.parseList(<Object?>['a string']),
        throwsA(isA<ReceiptFormatException>()),
      );
    });
  });

  group('products', () {
    test('parses the five columns the RPC returns', () {
      final List<ReceiptProduct> products = ReceiptProductParser.parseList(
        productRows(),
      );

      expect(products, hasLength(2));
      expect(products.first.productId, productAUuid);
      expect(products.first.productCode, 'SKU-100');
      expect(products.first.barcode, '01234567');
      expect(products.first.productName, 'Chocolate Bar 50g');
      expect(products.first.brand, 'Northwind');
    });

    test(
      'a null barcode and brand are supported — both columns are nullable',
      () {
        final List<ReceiptProduct> products = ReceiptProductParser.parseList(
          productRows(),
        );

        expect(products[1].barcode, isNull);
        expect(products[1].brand, isNull);
      },
    );

    test('no field the RPC withholds is invented', () {
      // The migration withholds vendor_organization_id, the Vendor name,
      // created_by_profile_id, timestamps, the assignment id, assignment_status
      // and description. The entity has nowhere to put any of them, and extra
      // keys in the response are ignored rather than surfaced.
      final List<ReceiptProduct> products = ReceiptProductParser.parseList(
        <Map<String, Object?>>[
          <String, Object?>{
            'product_id': productAUuid,
            'product_code': 'SKU-100',
            'product_name': 'Chocolate Bar 50g',
            'vendor_organization_id': 'should-be-ignored',
            'assignment_status': 'ACTIVE',
            'description': 'catalogue prose',
          },
        ],
      );

      expect(products.single.props, hasLength(5));
    });

    test('an empty catalogue is a real answer', () {
      expect(ReceiptProductParser.parseList(<Object?>[]), isEmpty);
    });

    test('a missing product_code throws', () {
      expect(
        () => ReceiptProductParser.parseList(<Map<String, Object?>>[
          <String, Object?>{
            'product_id': productAUuid,
            'product_name': 'Chocolate Bar 50g',
          },
        ]),
        throwsA(isA<ReceiptFormatException>()),
      );
    });

    test('a non-string barcode is malformed, not coerced', () {
      expect(
        () => ReceiptProductParser.parseList(<Map<String, Object?>>[
          <String, Object?>{
            'product_id': productAUuid,
            'product_code': 'SKU-100',
            'product_name': 'Chocolate Bar 50g',
            'barcode': 1234567,
          },
        ]),
        throwsA(isA<ReceiptFormatException>()),
      );
    });

    test('matches searches every returned field and nothing else', () {
      expect(productA.matches('choc'), isTrue);
      expect(productA.matches('SKU-100'), isTrue);
      expect(productA.matches('northwind'), isTrue);
      expect(productA.matches('0123'), isTrue);
      expect(productA.matches(''), isTrue);
      expect(productA.matches('nothing here'), isFalse);
      // A product with no brand or barcode must not crash the filter.
      expect(productB.matches('sparkling'), isTrue);
      expect(productB.matches('northwind'), isFalse);
    });
  });

  group('submissions', () {
    test('parses the nine columns both RPCs return', () {
      final ReceiptSubmission row = ReceiptSubmissionParser.parse(
        submissionRow(),
      );

      expect(row.submissionId, submissionUuid);
      expect(row.shopName, 'Marina Mall');
      expect(row.shopCode, 'MM-01');
      expect(row.status, ReceiptSubmissionStatus.submitted);
      expect(row.originalFileName, 'receipt.png');
      expect(row.mimeType, 'image/png');
      expect(row.fileSizeBytes, 24576);
      expect(row.submittedAt, DateTime.utc(2026, 7, 25, 9, 30));
      expect(row.createdAt, DateTime.utc(2026, 7, 25, 9, 29));
      // Nine columns and no tenth.
      expect(row.props, hasLength(9));
    });

    test('one parser deserializes the list and the single-row read', () {
      // The migration made the two shapes byte-identical on purpose. This is the
      // test that would fail if a second, drifting model were introduced.
      final List<ReceiptSubmission> fromList =
          ReceiptSubmissionParser.parseList(<Map<String, Object?>>[
            submissionRow(),
          ]);
      final ReceiptSubmission? fromSingle = ReceiptSubmissionParser.parseSingle(
        <Map<String, Object?>>[submissionRow()],
      );

      expect(fromList.single, fromSingle);
    });

    test('zero rows is null, not an error', () {
      // A nonexistent id, another person's id and another Retailer's id all
      // return zero rows. Preserving one representation for all three is what
      // keeps the endpoint from being an existence oracle.
      expect(ReceiptSubmissionParser.parseSingle(<Object?>[]), isNull);
    });

    test('more than one row for a primary-key lookup is malformed', () {
      expect(
        () => ReceiptSubmissionParser.parseSingle(<Map<String, Object?>>[
          submissionRow(),
          submissionRow(),
        ]),
        throwsA(isA<ReceiptFormatException>()),
      );
    });

    test('RESERVED and UPLOAD_FAILED parse, with a null submitted_at', () {
      final ReceiptSubmission reserved = ReceiptSubmissionParser.parse(
        submissionRow(status: 'RESERVED', submittedAt: null),
      );
      final ReceiptSubmission failed = ReceiptSubmissionParser.parse(
        submissionRow(status: 'UPLOAD_FAILED', submittedAt: null),
      );

      expect(reserved.status, ReceiptSubmissionStatus.reserved);
      expect(reserved.submittedAt, isNull);
      expect(reserved.displayedAt, reserved.createdAt);
      expect(failed.status, ReceiptSubmissionStatus.uploadFailed);
      expect(failed.status.isRetryable, isTrue);
      expect(failed.status.isSubmitted, isFalse);
    });

    test('an unknown status degrades rather than failing the whole read', () {
      final ReceiptSubmission row = ReceiptSubmissionParser.parse(
        submissionRow(status: 'APPROVED', submittedAt: null),
      );

      expect(row.status, ReceiptSubmissionStatus.unknown);
      // And it grants nothing.
      expect(row.status.isSubmitted, isFalse);
      expect(row.status.isRetryable, isFalse);
      // The raw token is not retained anywhere on the entity.
      expect(row.props.contains('APPROVED'), isFalse);
    });

    test('a missing status is a malformed response, not an unknown one', () {
      expect(
        () => ReceiptSubmissionParser.parse(
          <String, Object?>{...submissionRow()}..remove('status'),
        ),
        throwsA(isA<ReceiptFormatException>()),
      );
    });

    test('a malformed submission id throws', () {
      expect(
        () => ReceiptSubmissionParser.parse(<String, Object?>{
          ...submissionRow(),
          'submission_id': '99999999-8888-7777-6666',
        }),
        throwsA(isA<ReceiptFormatException>()),
      );
    });

    test('file_size_bytes must be a number', () {
      expect(
        () => ReceiptSubmissionParser.parse(<String, Object?>{
          ...submissionRow(),
          'file_size_bytes': '24576',
        }),
        throwsA(isA<ReceiptFormatException>()),
      );
    });

    test('an integral double is accepted — JSON has one number type', () {
      final ReceiptSubmission row = ReceiptSubmissionParser.parse(
        <String, Object?>{...submissionRow(), 'file_size_bytes': 24576.0},
      );

      expect(row.fileSizeBytes, 24576);
    });

    test('a missing created_at throws', () {
      expect(
        () => ReceiptSubmissionParser.parse(
          <String, Object?>{...submissionRow()}..remove('created_at'),
        ),
        throwsA(isA<ReceiptFormatException>()),
      );
    });

    test('an unparseable timestamp throws', () {
      expect(
        () => ReceiptSubmissionParser.parse(<String, Object?>{
          ...submissionRow(),
          'created_at': 'yesterday',
        }),
        throwsA(isA<ReceiptFormatException>()),
      );
    });

    test('a submitted_at that is present but unparseable throws', () {
      expect(
        () => ReceiptSubmissionParser.parse(submissionRow(submittedAt: 'soon')),
        throwsA(isA<ReceiptFormatException>()),
      );
    });

    test('timestamps are normalized to UTC on the way in', () {
      final ReceiptSubmission row = ReceiptSubmissionParser.parse(
        <String, Object?>{
          ...submissionRow(),
          'created_at': '2026-07-25T13:29:00+04:00',
        },
      );

      expect(row.createdAt.isUtc, isTrue);
      expect(row.createdAt, DateTime.utc(2026, 7, 25, 9, 29));
    });

    test('no storage bucket, object path or hash has anywhere to land', () {
      // Both RPCs withhold them. An extra key in the response is ignored, so a
      // future backend that leaked one could not surface it through this model.
      final ReceiptSubmission row =
          ReceiptSubmissionParser.parse(<String, Object?>{
            ...submissionRow(),
            'storage_bucket': 'receipts',
            'storage_object_path': 'org/user/sub/file.png',
            'file_sha256': 'a' * 64,
          });

      expect(row.props, hasLength(9));
      expect(row.props.contains('receipts'), isFalse);
      expect(row.props.contains('org/user/sub/file.png'), isFalse);
    });
  });

  group('uuid shape', () {
    test('accepts the 8-4-4-4-12 form in either case', () {
      expect(isUuid(submissionUuid), isTrue);
      expect(isUuid(submissionUuid.toUpperCase()), isTrue);
    });

    test('rejects everything else', () {
      for (final String value in <String>[
        '',
        'null',
        '99999999-8888-7777-6666',
        '99999999888877776666555555555555',
        "' or 1=1 --",
        '../../etc/passwd',
      ]) {
        expect(isUuid(value), isFalse, reason: '"$value" must not pass');
      }
    });
  });
}
