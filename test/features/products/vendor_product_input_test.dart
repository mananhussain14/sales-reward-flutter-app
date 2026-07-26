import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_draft.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_edit.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_field.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_input.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_status.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_status_change.dart';

/// The client-side half of the write contract: normalization, validation, and the
/// request value objects.
///
/// Nothing here is an enforcement boundary — PostgreSQL re-normalizes and
/// re-validates every value from scratch — so these tests are not about security.
/// They are about **agreement**: if this file and the deployed migration disagreed
/// about what `"sr-100"` means, a form would report a code as available that the
/// unique index then refuses as a duplicate.
void main() {
  group('the whitespace set matches the deployed migration exactly', () {
    /// The 25 code points
    /// `20260807090000_repair_vendor_product_write_normalization.sql` lists, which
    /// is exactly JavaScript's `\s` — the set the web's `product-input.ts` strips
    /// in the browser.
    const List<int> expected = <int>[
      0x0020, // space
      0x0009, // tab
      0x000A, // line feed
      0x000B, // vertical tab
      0x000C, // form feed
      0x000D, // carriage return
      0x00A0, // no-break space
      0x1680, // ogham space mark
      0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, // en/em quad family
      0x2006, 0x2007, 0x2008, 0x2009, 0x200A,
      0x2028, // line separator
      0x2029, // paragraph separator
      0x202F, // narrow no-break space
      0x205F, // medium mathematical space
      0x3000, // ideographic space
      0xFEFF, // zero-width no-break space
    ];

    test('there are exactly 25 of them', () {
      expect(expected.toSet().length, 25);
    });

    test('every one collapses away in a single-line value', () {
      for (final int code in expected) {
        final String ws = String.fromCharCode(code);
        expect(
          VendorProductInput.normalizeLine('${ws}Widget$ws${ws}Two$ws'),
          'Widget Two',
          reason:
              'U+${code.toRadixString(16).toUpperCase().padLeft(4, '0')} is not '
              'treated as whitespace',
        );
      }
    });

    test('every one is trimmed from the ends of a block value', () {
      for (final int code in expected) {
        final String ws = String.fromCharCode(code);
        expect(VendorProductInput.normalizeBlock('$ws${ws}Body$ws'), 'Body');
      }
    });

    test('U+0085 NEXT LINE is NOT whitespace here, because it is not in JS \\s', () {
      // The whole reason `String.trim()` is banned in this feature. Dart's trim
      // strips U+0085; JavaScript's `\s` and the migration's explicit class do
      // not. If Dart stripped it, the same keystrokes would store one value from
      // the browser and a different one from this client.
      final String nel = String.fromCharCode(0x85);
      expect(VendorProductInput.normalizeLine('${nel}Widget'), '${nel}Widget');
      expect(VendorProductInput.normalizeBlock('${nel}Widget'), '${nel}Widget');

      // And the proof that this is a real difference rather than a coincidence.
      expect('${nel}Widget'.trim(), 'Widget');
    });

    test('the pattern source names no literal invisible character', () {
      // Spelled with `\u` escapes so a diff of the source can be read as text —
      // the same discipline the migration applies, for the same reason.
      for (final int code in expected) {
        if (code == 0x0020) {
          continue;
        }
        expect(
          VendorProductInput.whitespacePattern.contains(
            String.fromCharCode(code),
          ),
          isFalse,
          reason: 'the pattern embeds a literal invisible character',
        );
      }
    });
  });

  group('normalizeLine — collapse, then trim', () {
    test('trims both ends and collapses internal runs', () {
      expect(
        VendorProductInput.normalizeLine('  Clean   Name  '),
        'Clean Name',
      );
    });

    test('a value with nothing but whitespace becomes empty', () {
      expect(VendorProductInput.normalizeLine('   \t\n  '), '');
    });

    test('an empty value stays empty', () {
      expect(VendorProductInput.normalizeLine(''), '');
    });

    test('a clean value is returned byte-identical', () {
      // The property the deployed repair rests on: for every value the browser can
      // send — already trimmed and collapsed — collapse-then-trim and
      // trim-then-collapse agree exactly. It is also what keeps the backend's no-op
      // comparison from turning unchanged edits into real ones.
      expect(VendorProductInput.normalizeLine('Clean Name'), 'Clean Name');
    });

    test('case is preserved', () {
      expect(
        VendorProductInput.normalizeLine('Harvest Roasters'),
        'Harvest Roasters',
      );
    });

    test('a multi-byte value survives intact', () {
      expect(VendorProductInput.normalizeLine('  Café   Noir  '), 'Café Noir');
    });
  });

  group('normalizeBlock — trim only', () {
    test('internal newlines and blank lines are preserved verbatim', () {
      // A paragraph break belongs to its author. This is the one rule that makes a
      // description different from a name, and the backend enforces the same one.
      const String body = 'First line.\n\nSecond paragraph.\n  indented';
      expect(VendorProductInput.normalizeBlock('  $body  '), body);
    });

    test('leading and trailing newlines are removed', () {
      expect(VendorProductInput.normalizeBlock('\n\nBody\n\n'), 'Body');
    });

    test('internal runs of spaces are NOT collapsed', () {
      expect(
        VendorProductInput.normalizeBlock('Two  spaces  kept'),
        'Two  spaces  kept',
      );
    });

    test('whitespace-only becomes empty', () {
      expect(VendorProductInput.normalizeBlock(' \n\t '), '');
    });
  });

  group('normalizeProductCode — upper-cased last', () {
    test('lower case is folded up', () {
      expect(VendorProductInput.normalizeProductCode('  sr-100  '), 'SR-100');
    });

    test('internal runs collapse to one space, satisfying the shape rule', () {
      // The table's shape constraint refuses two consecutive spaces, so the
      // collapse is what makes a spaced code storable at all.
      expect(VendorProductInput.normalizeProductCode('a  b'), 'A B');
    });

    test('mixed case is one product, not two', () {
      expect(
        VendorProductInput.normalizeProductCode('sr-100'),
        VendorProductInput.normalizeProductCode('SR-100'),
      );
    });
  });

  group('normalizeBarcode — separators removed, text throughout', () {
    test('spaces and hyphens are stripped', () {
      expect(
        VendorProductInput.normalizeBarcode(' 012 345-678-905 '),
        '012345678905',
      );
    });

    test('a leading zero survives, which is why it is never a number', () {
      const String raw = '012345678905';
      expect(VendorProductInput.normalizeBarcode(raw), raw);
      expect(VendorProductInput.normalizeBarcode(raw), startsWith('0'));
      // The value a numeric parse would have produced instead.
      expect(int.parse(raw).toString(), isNot(raw));
    });

    test('a 14-digit GTIN survives exactly', () {
      // Beyond what a double holds without loss, which is the second reason a
      // barcode is text.
      const String gtin = '10012345678905';
      expect(VendorProductInput.normalizeBarcode(gtin), gtin);
      expect(gtin.length, 14);
    });

    test('a non-digit is left in place rather than silently removed', () {
      // So the shape check can refuse it, instead of the field quietly accepting a
      // value the backend would reject.
      expect(VendorProductInput.normalizeBarcode('50123x5678'), '50123x5678');
    });

    test('whitespace-only and separator-only become empty', () {
      expect(VendorProductInput.normalizeBarcode('  -- '), '');
    });
  });

  group('optionalOrNull', () {
    test('an empty value becomes null, never an empty string', () {
      expect(VendorProductInput.optionalOrNull(''), isNull);
    });

    test('a present value is passed through', () {
      expect(VendorProductInput.optionalOrNull('Acme'), 'Acme');
    });

    test('no placeholder phrase is ever produced', () {
      // "Not recorded" is how a null is *rendered*; it must never become a stored
      // value.
      expect(VendorProductInput.optionalOrNull(''), isNot('Not recorded'));
    });
  });

  group('the form values normalize all five at once', () {
    test('each field gets its own rule', () {
      const VendorProductFormValues raw = VendorProductFormValues(
        productCode: '  sr-100  ',
        productName: '  Clean   Name  ',
        barcode: ' 012 345-678-905 ',
        brand: '  Acme  Co ',
        description: '  Two  spaces\n\nkept  ',
      );

      final VendorProductFormValues values = raw.normalized;

      // The exact five results the deployed function stores for this input, taken
      // from the migration's own verified example.
      expect(values.productCode, 'SR-100');
      expect(values.productName, 'Clean Name');
      expect(values.barcode, '012345678905');
      expect(values.brand, 'Acme Co');
      // Trim only: the internal double space and the blank line are the author's.
      expect(values.description, 'Two  spaces\n\nkept');
    });

    test('normalizing twice changes nothing', () {
      const VendorProductFormValues raw = VendorProductFormValues(
        productCode: ' a  b ',
        productName: ' c  d ',
        barcode: ' 1 2-3 ',
        brand: ' e  f ',
        description: ' g  h ',
      );
      expect(raw.normalized.normalized, raw.normalized);
    });

    test('an all-blank form normalizes to five empty strings', () {
      const VendorProductFormValues blank = VendorProductFormValues(
        productCode: '   ',
        productName: '\t',
        barcode: ' - ',
        brand: '\n',
        description: '  ',
      );
      final VendorProductFormValues values = blank.normalized;
      expect(values, const VendorProductFormValues());
    });
  });

  group('create validation', () {
    Map<VendorProductField, String> validate(VendorProductFormValues v) =>
        validateVendorProductInput(v.normalized, VendorProductInputMode.create);

    const VendorProductFormValues valid = VendorProductFormValues(
      productCode: 'ESP-1000',
      productName: 'Espresso Blend 1kg',
      barcode: '5012345678900',
      brand: 'Harvest Roasters',
      description: 'A dark roast blend.',
    );

    test('a fully populated valid form has no errors', () {
      expect(validate(valid), isEmpty);
    });

    test('the three optionals may all be blank', () {
      expect(
        validate(
          const VendorProductFormValues(
            productCode: 'DEC-2000',
            productName: 'Decaf Ground 500g',
          ),
        ),
        isEmpty,
      );
    });

    test('a missing product code is reported', () {
      expect(
        validate(valid.copyWith(productCode: '')),
        containsPair(VendorProductField.productCode, 'Enter a product code.'),
      );
    });

    test('a whitespace-only product code is the same omission', () {
      expect(
        validate(valid.copyWith(productCode: ' \t\n ')),
        containsPair(VendorProductField.productCode, 'Enter a product code.'),
      );
    });

    test('a missing product name is reported', () {
      expect(
        validate(valid.copyWith(productName: '')),
        containsPair(VendorProductField.productName, 'Enter a product name.'),
      );
    });

    test('a whitespace-only product name is the same omission', () {
      expect(
        validate(valid.copyWith(productName: '   ')),
        containsPair(VendorProductField.productName, 'Enter a product name.'),
      );
    });

    test('a 64-character code is accepted and 65 is not', () {
      expect(validate(valid.copyWith(productCode: 'A' * 64)), isEmpty);
      expect(
        validate(valid.copyWith(productCode: 'A' * 65)),
        contains(VendorProductField.productCode),
      );
    });

    test('a 200-character name is accepted and 201 is not', () {
      expect(validate(valid.copyWith(productName: 'A' * 200)), isEmpty);
      expect(
        validate(valid.copyWith(productName: 'A' * 201)),
        contains(VendorProductField.productName),
      );
    });

    test('a 120-character brand is accepted and 121 is not', () {
      expect(validate(valid.copyWith(brand: 'A' * 120)), isEmpty);
      expect(
        validate(valid.copyWith(brand: 'A' * 121)),
        contains(VendorProductField.brand),
      );
    });

    test('a 2000-character description is accepted and 2001 is not', () {
      expect(validate(valid.copyWith(description: 'A' * 2000)), isEmpty);
      expect(
        validate(valid.copyWith(description: 'A' * 2001)),
        contains(VendorProductField.description),
      );
    });

    test('lengths are counted in characters, not bytes', () {
      // 200 multi-byte characters is a valid name; the backend counts the same way.
      expect(validate(valid.copyWith(productName: 'é' * 200)), isEmpty);
      expect(
        validate(valid.copyWith(productName: 'é' * 201)),
        contains(VendorProductField.productName),
      );
    });

    test('the code shape rule matches the storage constraint', () {
      for (final String accepted in <String>[
        'A',
        '0',
        'ESP-1000',
        'SR 100',
        'A.B_C/D-E',
        'esp-1000', // upper-cased first
      ]) {
        expect(
          validate(valid.copyWith(productCode: accepted)),
          isEmpty,
          reason: '"$accepted" should be a valid code',
        );
      }
      for (final String refused in <String>[
        '-LEADING-HYPHEN',
        '.LEADING-DOT',
        ' _UNDERSCORE-FIRST',
        'HAS#HASH',
        'HAS(PAREN)',
        'HAS,COMMA',
      ]) {
        expect(
          validate(valid.copyWith(productCode: refused)),
          contains(VendorProductField.productCode),
          reason: '"$refused" should be refused',
        );
      }
    });

    test('a barcode of 8 to 14 digits is accepted at both ends', () {
      expect(validate(valid.copyWith(barcode: '0' * 8)), isEmpty);
      expect(validate(valid.copyWith(barcode: '0' * 14)), isEmpty);
    });

    test('7 and 15 digits are refused', () {
      for (final String bad in <String>['0' * 7, '0' * 15]) {
        expect(
          validate(valid.copyWith(barcode: bad)),
          contains(VendorProductField.barcode),
        );
      }
    });

    test('a non-digit barcode is refused', () {
      expect(
        validate(valid.copyWith(barcode: '50123x567890')),
        contains(VendorProductField.barcode),
      );
    });

    test('a barcode written with separators is accepted', () {
      expect(validate(valid.copyWith(barcode: '012 345-678-905')), isEmpty);
    });

    test('a blank barcode is never an error', () {
      expect(validate(valid.copyWith(barcode: '')), isEmpty);
      expect(validate(valid.copyWith(barcode: '  -  ')), isEmpty);
    });

    test('several offending fields are all reported at once', () {
      final Map<VendorProductField, String> errors = validate(
        const VendorProductFormValues(barcode: '1', brand: 'x'),
      );
      expect(errors.keys, <VendorProductField>{
        VendorProductField.productCode,
        VendorProductField.productName,
        VendorProductField.barcode,
      });
    });

    test('no message names a table, column, constraint or SQLSTATE', () {
      final Map<VendorProductField, String> errors = validate(
        VendorProductFormValues(
          productCode: '#BAD',
          productName: 'A' * 201,
          barcode: '1',
          brand: 'B' * 121,
          description: 'C' * 2001,
        ),
      );
      expect(errors.length, 5);
      for (final String message in errors.values) {
        for (final String forbidden in <String>[
          'vendor_products',
          'check constraint',
          'violates',
          'SQLSTATE',
          '23514',
          '23505',
          '42501',
          'null value',
          'relation',
        ]) {
          expect(
            message.contains(forbidden),
            isFalse,
            reason: '"$message" leaks backend vocabulary',
          );
        }
      }
    });
  });

  group('update validation', () {
    Map<VendorProductField, String> validate(VendorProductFormValues v) =>
        validateVendorProductInput(v.normalized, VendorProductInputMode.update);

    test('the product code is never judged, whatever it holds', () {
      // Not a leniency: the edit form cannot send a code, so a rule about one would
      // have no subject and any message it produced would describe a field nobody
      // can change.
      for (final String code in <String>['', '#INVALID', 'A' * 200]) {
        expect(
          validate(
            VendorProductFormValues(
              productCode: code,
              productName: 'Espresso Blend 1kg',
            ),
          ),
          isEmpty,
        );
      }
    });

    test('the name is still required', () {
      expect(
        validate(const VendorProductFormValues()),
        containsPair(VendorProductField.productName, 'Enter a product name.'),
      );
    });

    test('clearing all three optionals is valid', () {
      expect(
        validate(const VendorProductFormValues(productName: 'Renamed')),
        isEmpty,
      );
    });

    test('the other four rules are identical to create', () {
      const VendorProductFormValues bad = VendorProductFormValues(
        productName: '',
        barcode: '1',
        brand: '',
        description: '',
      );
      expect(
        validate(bad.copyWith(brand: 'B' * 121, description: 'C' * 2001)).keys,
        <VendorProductField>{
          VendorProductField.productName,
          VendorProductField.barcode,
          VendorProductField.brand,
          VendorProductField.description,
        },
      );
    });
  });

  group('duplicate messages', () {
    test('the two unique fields get their own sentences', () {
      expect(
        duplicateMessageFor(VendorProductField.productCode),
        'A product with this code already exists.',
      );
      expect(
        duplicateMessageFor(VendorProductField.barcode),
        'A product with this barcode already exists.',
      );
    });

    test('neither sentence mentions another Vendor', () {
      // Both are safe precisely because the two unique indexes are scoped PER
      // VENDOR: each describes the reader's own catalogue and neither can reveal
      // that somebody else uses the same value.
      for (final VendorProductField field in VendorProductField.values) {
        final String message = duplicateMessageFor(field);
        for (final String forbidden in <String>[
          'Vendor',
          'another',
          'organization',
          'tenant',
        ]) {
          expect(message.contains(forbidden), isFalse);
        }
      }
    });

    test('the three non-unique fields stay deliberately unspecific', () {
      // No unique index exists on them, so the backend cannot report a conflict
      // against one, and inventing a rule would be worse than saying little.
      for (final VendorProductField field in <VendorProductField>[
        VendorProductField.productName,
        VendorProductField.brand,
        VendorProductField.description,
      ]) {
        expect(duplicateMessageFor(field), 'This value is already in use.');
      }
    });
  });

  group('the field enum', () {
    test('there are exactly five fields, and no status or tenant member', () {
      expect(
        VendorProductField.values.map((VendorProductField f) => f.key),
        <String>[
          'productCode',
          'productName',
          'barcode',
          'brand',
          'description',
        ],
      );
    });

    test('a key round-trips, and an unknown one answers null', () {
      for (final VendorProductField field in VendorProductField.values) {
        expect(VendorProductField.fromKey(field.key), field);
      }
      // Degrades rather than pointing at the wrong input, or throwing.
      expect(VendorProductField.fromKey('product_code'), isNull);
      expect(VendorProductField.fromKey('status'), isNull);
      expect(VendorProductField.fromKey(null), isNull);
    });

    test('a key is a form-field name, never a database column name', () {
      for (final VendorProductField field in VendorProductField.values) {
        expect(field.key.contains('_'), isFalse);
      }
    });
  });

  group('the status request type', () {
    test('it has exactly two members, carrying the two accepted tokens', () {
      expect(VendorProductStatusChange.values.length, 2);
      expect(VendorProductStatusChange.activate.code, 'ACTIVE');
      expect(VendorProductStatusChange.deactivate.code, 'INACTIVE');
    });

    test('an active product offers deactivation, and the reverse', () {
      expect(
        VendorProductStatusChange.forCurrent(VendorProductStatus.active),
        VendorProductStatusChange.deactivate,
      );
      expect(
        VendorProductStatusChange.forCurrent(VendorProductStatus.inactive),
        VendorProductStatusChange.activate,
      );
    });

    test('an unrecognised status offers neither', () {
      // The opposite of an unfamiliar status is not knowable, and guessing either
      // way would invent a transition.
      expect(
        VendorProductStatusChange.forCurrent(VendorProductStatus.unknown),
        isNull,
      );
    });

    test(
      'the response enum\'s unknown member is not expressible as a request',
      () {
        expect(
          VendorProductStatusChange.values.map(
            (VendorProductStatusChange c) => c.code,
          ),
          isNot(contains(VendorProductStatus.unknown.code)),
        );
      },
    );
  });

  group('the request value objects', () {
    test('a create draft carries five values and no sixth', () {
      const VendorProductDraft draft = VendorProductDraft(
        productCode: 'ESP-1000',
        productName: 'Espresso Blend 1kg',
        barcode: '5012345678900',
        brand: 'Harvest Roasters',
        description: 'Line one.\n\nLine two.',
      );

      expect(draft.productCode, 'ESP-1000');
      expect(draft.productName, 'Espresso Blend 1kg');
      expect(draft.barcode, '5012345678900');
      expect(draft.brand, 'Harvest Roasters');
      // The multiline description survives the request object untouched.
      expect(draft.description, 'Line one.\n\nLine two.');
    });

    test('a create draft may omit all three optionals', () {
      const VendorProductDraft draft = VendorProductDraft(
        productCode: 'DEC-2000',
        productName: 'Decaf Ground 500g',
      );
      expect(draft.barcode, isNull);
      expect(draft.brand, isNull);
      expect(draft.description, isNull);
    });

    test('an edit carries four values, and nulls clear the optionals', () {
      const VendorProductEdit edit = VendorProductEdit(
        productName: 'Renamed',
        barcode: null,
        brand: null,
        description: null,
      );
      expect(edit.productName, 'Renamed');
      expect(edit.barcode, isNull);
      expect(edit.brand, isNull);
      expect(edit.description, isNull);
    });

    test('a barcode is a String on both request types', () {
      const VendorProductDraft draft = VendorProductDraft(
        productCode: 'A',
        productName: 'B',
        barcode: '012345678905',
      );
      const VendorProductEdit edit = VendorProductEdit(
        productName: 'B',
        barcode: '012345678905',
      );
      expect(draft.barcode, isA<String>());
      expect(edit.barcode, isA<String>());
    });
  });
}
