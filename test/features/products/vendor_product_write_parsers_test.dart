import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/features/products/data/models/vendor_product_parsers.dart';
import 'package:sale_reward/features/products/data/models/vendor_product_write_parsers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/vendor_product_fakes.dart';

/// The write-response parsers, and the one place a backend message is read.
void main() {
  group('the create response — a scalar uuid', () {
    test('a uuid string is accepted and returned verbatim', () {
      // PostgREST answers a `returns uuid` function with the bare scalar as JSON, so
      // `rpc<Object?>` resolves to a Dart String.
      expect(parseCreatedProductId(createdProductUuid), createdProductUuid);
    });

    test('upper-case hexadecimal is accepted', () {
      const String upper = '4B8C9D0E-1F23-4456-8789-A0B1C2D3E4F5';
      expect(parseCreatedProductId(upper), upper);
    });

    test('null is refused', () {
      expect(
        () => parseCreatedProductId(null),
        throwsA(isA<VendorProductFormatException>()),
      );
    });

    test('an empty string is refused', () {
      expect(
        () => parseCreatedProductId(''),
        throwsA(isA<VendorProductFormatException>()),
      );
    });

    test('a malformed uuid is refused', () {
      for (final String malformed in <String>[
        'not-a-uuid',
        '4b8c9d0e1f2344568789a0b1c2d3e4f5', // no hyphens
        '4b8c9d0e-1f23-4456-8789', // too short
        '4b8c9d0e-1f23-4456-8789-a0b1c2d3e4f5f', // too long
        '4b8c9d0e-1f23-4456-8789-a0b1c2d3e4fg', // not hexadecimal
        ' 4b8c9d0e-1f23-4456-8789-a0b1c2d3e4f5', // padded
      ]) {
        expect(
          () => parseCreatedProductId(malformed),
          throwsA(isA<VendorProductFormatException>()),
          reason: '"$malformed" should be refused',
        );
      }
    });

    test('a list is refused rather than unwrapped', () {
      // The function returns a scalar. A list would mean the response is not the
      // shape this build was written against, and reaching into it would be guessing.
      expect(
        () => parseCreatedProductId(<Object?>[createdProductUuid]),
        throwsA(isA<VendorProductFormatException>()),
      );
    });

    test('a map is refused rather than searched for a likely key', () {
      expect(
        () => parseCreatedProductId(<String, Object?>{
          'product_id': createdProductUuid,
        }),
        throwsA(isA<VendorProductFormatException>()),
      );
    });

    test('an unexpected scalar type is refused', () {
      for (final Object? raw in <Object?>[42, 4.2, true, <Object?>{}]) {
        expect(
          () => parseCreatedProductId(raw),
          throwsA(isA<VendorProductFormatException>()),
        );
      }
    });

    test('the refusal never carries the offending value', () {
      // A parser reason names only what was expected, which is what makes those
      // reasons safe to log.
      for (final Object? raw in <Object?>[
        'super-secret-not-a-uuid',
        <String, Object?>{'token': 'sb_secret_abc'},
        99,
      ]) {
        try {
          parseCreatedProductId(raw);
          fail('expected a refusal for $raw');
        } on VendorProductFormatException catch (error) {
          expect(error.reason.contains('secret'), isFalse);
          expect(error.reason.contains('99'), isFalse);
          expect(error.toString().contains('secret'), isFalse);
        }
      }
    });
  });

  group('the void response — update and status', () {
    test('null is the established successful shape', () {
      // PostgREST answers `returns void` with an empty body, and the SDK maps an
      // empty body to null.
      expect(isVoidWriteResponse(null), isTrue);
    });

    test('any body at all is not that shape', () {
      for (final Object raw in <Object>[
        '',
        'ok',
        0,
        false,
        <Object?>[],
        <String, Object?>{},
        <Object?>[<String, Object?>{}],
      ]) {
        expect(
          isVoidWriteResponse(raw),
          isFalse,
          reason: '$raw is not the void shape',
        );
      }
    });
  });

  group('write error classification', () {
    PostgrestException pg(String code, String message) =>
        PostgrestException(message: message, code: code);

    test('42501 is one generic denial, whatever caused it', () {
      // The backend raises the same 42501 for an unauthorized caller, an unknown
      // product, a foreign product and a null id — and this preserves that.
      for (final String message in <String>[
        'Not authorized to manage products',
        'Not authorized to manage this product',
      ]) {
        expect(
          mapVendorProductWriteError(pg('42501', message)),
          const DeniedFailure(),
        );
      }
    });

    test('23514 is a generic invalid, with no field', () {
      // The backend's five validation messages are English prose this client does
      // not parse; anything a person can act on has already been reported by the
      // app's own checks against the same rules.
      for (final String message in <String>[
        'Enter a valid product code',
        'Enter a product name',
        'Enter a valid barcode, or leave it blank',
        'Brand is too long',
        'Description is too long',
        'Choose a valid product status',
      ]) {
        final Failure failure = mapVendorProductWriteError(
          pg('23514', message),
        );
        expect(failure, isA<InvalidFailure>());
        expect((failure as InvalidFailure).field, isNull);
      }
    });

    test('a duplicate product code is attributed to the code field', () {
      final Failure failure = mapVendorProductWriteError(
        pg('23505', 'A product with that code already exists'),
      );
      expect(failure, const DuplicateFailure(field: 'productCode'));
    });

    test('a duplicate barcode is attributed to the barcode field', () {
      final Failure failure = mapVendorProductWriteError(
        pg('23505', 'A product with that barcode already exists'),
      );
      expect(failure, const DuplicateFailure(field: 'barcode'));
    });

    test('the two literals are distinguished, not conflated', () {
      // The literal for a barcode contains the word "barcode"; the one for a code
      // does not contain it. A naive substring order could match the wrong one.
      final Failure code = mapVendorProductWriteError(
        pg('23505', 'A product with that code already exists'),
      );
      final Failure barcode = mapVendorProductWriteError(
        pg('23505', 'A product with that barcode already exists'),
      );
      expect(code, isNot(barcode));
      expect((code as DuplicateFailure).field, 'productCode');
      expect((barcode as DuplicateFailure).field, 'barcode');
    });

    test('the literals are matched inside a longer message', () {
      // PostgREST can prefix or wrap a message; the match is a `contains`.
      expect(
        mapVendorProductWriteError(
          pg(
            '23505',
            'ERROR: A product with that barcode already exists (SQL)',
          ),
        ),
        const DuplicateFailure(field: 'barcode'),
      );
    });

    test('an unrecognised duplicate degrades to a hint-less duplicate', () {
      // Rather than being echoed, or guessed at, or pointed at the wrong input.
      final Failure failure = mapVendorProductWriteError(
        pg(
          '23505',
          'duplicate key value violates unique constraint "some_idx"',
        ),
      );
      expect(failure, const DuplicateFailure());
      expect((failure as DuplicateFailure).field, isNull);
    });

    test('the matched message never travels onward', () {
      final Failure failure = mapVendorProductWriteError(
        pg(
          '23505',
          'duplicate key value violates unique constraint '
              '"vendor_products_barcode_unique_idx" on relation "vendor_products"',
        ),
      );
      // Only a field key can leave, and here not even that.
      expect(failure, isA<DuplicateFailure>());
      expect(failure.toString().contains('vendor_products'), isFalse);
      expect(failure.props.whereType<String>(), isEmpty);
    });

    test('an auth exception is unauthenticated, never denied', () {
      // Signed out is not the same event as signed in and refused, and only one of
      // them is fixed by signing in again.
      expect(
        mapVendorProductWriteError(const AuthException('expired')),
        const UnauthenticatedFailure(),
      );
    });

    test('a transport failure is unavailable, never a denial', () {
      for (final Object error in <Object>[
        Exception('SocketException: failed host lookup'),
        StateError('connection closed'),
        const FormatException('unexpected end of input'),
        Object(),
      ]) {
        expect(
          mapVendorProductWriteError(error),
          const UnavailableFailure(),
          reason: '$error must not be presented as an authorization answer',
        );
      }
    });

    test('an unrecognised SQLSTATE is unavailable', () {
      expect(
        mapVendorProductWriteError(pg('40001', 'serialization failure')),
        const UnavailableFailure(),
      );
      expect(
        mapVendorProductWriteError(
          pg('22P02', 'invalid input syntax for uuid'),
        ),
        const UnavailableFailure(),
      );
    });

    test(
      '55000 stays a not-ready result, and is unreachable from these writes',
      () {
        // It belongs to the assignment functions, which this milestone never calls. It
        // is classified honestly rather than being folded into a wording it does not
        // have.
        expect(
          mapVendorProductWriteError(
            pg('55000', 'Activate this product first'),
          ),
          const NotReadyFailure(),
        );
      },
    );

    test('no classification carries backend text of any kind', () {
      for (final String code in <String>[
        '42501',
        '23514',
        '23505',
        '55000',
        '40001',
      ]) {
        final Failure failure = mapVendorProductWriteError(
          pg(code, 'relation "vendor_products" constraint "x" function y()'),
        );
        final String rendered = failure.toString();
        for (final String forbidden in <String>[
          'vendor_products',
          'constraint',
          'relation',
          'function',
          code,
        ]) {
          expect(
            rendered.contains(forbidden),
            isFalse,
            reason: '$rendered leaks "$forbidden"',
          );
        }
      }
    });
  });
}
