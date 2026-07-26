import 'vendor_product_field.dart';

/// Client-side normalization and validation for the Vendor Product write forms.
///
/// ## This is not the enforcement boundary, and it must not read as one
///
/// Every rule below is applied again, independently, in PostgreSQL by
/// `create_vendor_product` and `update_vendor_product` under the caller's own
/// token — those functions re-normalize and re-validate from scratch, and the
/// table's `CHECK` constraints and its two per-Vendor unique indexes are the
/// final authority. This file exists so a Vendor sees a useful message before a
/// round trip, and for no other reason. Nothing here decides whether a write is
/// allowed, and nothing here is trusted after a write: the values a screen shows
/// afterwards come from `get_vendor_product_detail`, never from what was typed.
///
/// ## Normalization matters more than validation, and this is why
///
/// If this file and the RPC disagreed about what `"sr-100"` means, a form could
/// report a code as available that the unique index then refuses as a duplicate —
/// or report one as taken that is not. The rules are therefore stated to match
/// the deployed migration expression for expression:
///
/// | Field | Rule |
/// | --- | --- |
/// | product code | collapse → trim → **upper-case** |
/// | product name | collapse → trim |
/// | brand | collapse → trim, empty becomes absent |
/// | barcode | collapse → trim, then **remove spaces and hyphens**, empty becomes absent |
/// | description | **trim only** — internal formatting belongs to its author |
///
/// ## Why `String.trim()` is never used here
///
/// Dart's `trim()` strips the Unicode `White_Space` set, which includes **U+0085
/// NEXT LINE**. JavaScript's `\s` does not, and the deployed migration's
/// whitespace class — written out literally, precisely so it cannot drift — does
/// not either. Using `trim()` would make Dart quietly stricter than both other
/// definitions: a name submitted with a leading U+0085 would be sent as
/// `"Widget"` from this client and stored as `"<U+0085>Widget"` from the
/// browser, and the same keystrokes would produce two different products. So the class is spelled out
/// in [whitespacePattern] and used everywhere, and a test pins its membership at
/// exactly the 25 code points the migration lists.
///
/// The one place a *dumb* space trim is correct is after the collapse step, where
/// every whitespace character has already become U+0020 — which is exactly what
/// the migration's `btrim(..., ' ')` relies on.
abstract final class VendorProductInput {
  /// The whitespace set, character for character as
  /// `20260807090000_repair_vendor_product_write_normalization.sql` writes it,
  /// and therefore exactly JavaScript's `\s` — the set `lib/products/
  /// product-input.ts` strips in the browser.
  ///
  /// U+0020 space · U+0009 tab · U+000A line feed · U+000B vertical tab ·
  /// U+000C form feed · U+000D carriage return · U+00A0 no-break space ·
  /// U+1680 ogham space mark · U+2000–U+200A the en/em quad family ·
  /// U+2028 line separator · U+2029 paragraph separator ·
  /// U+202F narrow no-break space · U+205F medium mathematical space ·
  /// U+3000 ideographic space · U+FEFF zero-width no-break space.
  ///
  /// Written with `\u` escapes rather than literal characters, so this file
  /// contains no invisible bytes and a diff of it can be read as text — the same
  /// discipline the migration applies for the same reason.
  static const String whitespacePattern =
      r'[\u0020\u0009\u000A\u000B\u000C\u000D'
      r'\u00A0\u1680\u2000-\u200A'
      r'\u2028\u2029\u202F\u205F\u3000\uFEFF]';

  static final RegExp _whitespace = RegExp(whitespacePattern);
  static final RegExp _whitespaceEdges = RegExp(
    '^$whitespacePattern+|$whitespacePattern+\$',
  );
  static final RegExp _spaceRun = RegExp(' +');

  /// Byte-identical to `vendor_products_code_shape` in the storage migration,
  /// and to `PRODUCT_CODE_PATTERN` in the web's input module.
  static final RegExp productCodePattern = RegExp(r'^[A-Z0-9][A-Z0-9 ._/-]*$');

  /// Byte-identical to `vendor_products_barcode_shape`: a GTIN-8/12/13/14 digit
  /// string. **Text throughout** — a barcode is never parsed as a number, because
  /// `int` would lose a leading zero and `double` would lose precision above 15
  /// digits.
  static final RegExp barcodePattern = RegExp(r'^[0-9]{8,14}$');

  static const int maxProductCodeLength = 64;
  static const int maxProductNameLength = 200;
  static const int maxBrandLength = 120;
  static const int maxDescriptionLength = 2000;

  /// The minimum and maximum digit counts a barcode may carry.
  static const int minBarcodeDigits = 8;
  static const int maxBarcodeDigits = 14;

  /// Collapse, then trim — in that order, which is the whole correction the
  /// deployed repair made.
  ///
  /// Every whitespace character becomes U+0020, every run of spaces becomes one
  /// space, and the ends are trimmed. For values that are one line by nature: the
  /// product code, the product name and the brand.
  static String normalizeLine(String value) => value
      .replaceAll(_whitespace, ' ')
      .replaceAll(_spaceRun, ' ')
      .replaceAll(RegExp(r'^ +| +$'), '');

  /// Trim the ends only, leaving internal formatting untouched.
  ///
  /// For the description, whose paragraph breaks belong to whoever wrote them —
  /// the one rule that distinguishes a description from a name.
  static String normalizeBlock(String value) =>
      value.replaceAll(_whitespaceEdges, '');

  /// [normalizeLine], then upper-cased.
  ///
  /// Upper-casing last so the result satisfies the table's
  /// `vendor_products_code_normalized` constraint by construction, exactly as the
  /// RPC's `upper(public.normalize_product_line(...))` does. `sr-100` and
  /// `SR-100` are therefore one product rather than two.
  static String normalizeProductCode(String value) =>
      normalizeLine(value).toUpperCase();

  /// [normalizeLine], then spaces and hyphens removed.
  ///
  /// A barcode is a number people transcribe with separators; `012 345-678-905`
  /// and `012345678905` are the same barcode. Nothing else is stripped: a letter
  /// or a punctuation mark stays, so the shape check can refuse it rather than
  /// silently accepting a value the backend would reject.
  static String normalizeBarcode(String value) =>
      normalizeLine(value).replaceAll(' ', '').replaceAll('-', '');

  /// The value an optional field sends: the text, or **null** when it is empty.
  ///
  /// `null`, `''` and whitespace-only are one thing to the backend — all three
  /// store SQL NULL — so all three leave here as null. An optional field is never
  /// sent as an empty string, and never as a placeholder phrase: "Not recorded"
  /// is how this client *renders* a null and is never a value it stores.
  static String? optionalOrNull(String normalized) =>
      normalized.isEmpty ? null : normalized;
}

/// The five raw form values, exactly as typed.
///
/// Held raw rather than normalized so the text a person is part-way through
/// typing is never rewritten under their cursor. Normalization happens once, on
/// submit, through [normalized] — which is what the web does too: its action
/// normalizes the submitted `FormData` and echoes the canonical values back.
final class VendorProductFormValues {
  const VendorProductFormValues({
    this.productCode = '',
    this.productName = '',
    this.barcode = '',
    this.brand = '',
    this.description = '',
  });

  final String productCode;
  final String productName;
  final String barcode;
  final String brand;
  final String description;

  VendorProductFormValues copyWith({
    String? productCode,
    String? productName,
    String? barcode,
    String? brand,
    String? description,
  }) {
    return VendorProductFormValues(
      productCode: productCode ?? this.productCode,
      productName: productName ?? this.productName,
      barcode: barcode ?? this.barcode,
      brand: brand ?? this.brand,
      description: description ?? this.description,
    );
  }

  /// The canonical values, normalized by the rules in [VendorProductInput].
  VendorProductFormValues get normalized => VendorProductFormValues(
    productCode: VendorProductInput.normalizeProductCode(productCode),
    productName: VendorProductInput.normalizeLine(productName),
    barcode: VendorProductInput.normalizeBarcode(barcode),
    brand: VendorProductInput.normalizeLine(brand),
    description: VendorProductInput.normalizeBlock(description),
  );

  @override
  bool operator ==(Object other) =>
      other is VendorProductFormValues &&
      other.productCode == productCode &&
      other.productName == productName &&
      other.barcode == barcode &&
      other.brand == brand &&
      other.description == description;

  @override
  int get hashCode =>
      Object.hash(productCode, productName, barcode, brand, description);
}

/// Which fields a validation pass is entitled to judge.
enum VendorProductInputMode {
  /// Every field, including the product code.
  create,

  /// Every field **except** the product code.
  ///
  /// `update_vendor_product` has no code parameter and the edit form has no
  /// control for one, so validating a value that cannot be sent would be a rule
  /// with no subject — and any message it produced would describe a field the
  /// person cannot change.
  update,
}

/// Advisory validation of already-[VendorProductFormValues.normalized] values.
///
/// Returns one message per offending field, in this feature's own words. **No
/// message here is a backend string**, and none names a table, a column, a
/// constraint, a function or a SQLSTATE — a Vendor reads about the field in front
/// of them, not about PostgreSQL.
Map<VendorProductField, String> validateVendorProductInput(
  VendorProductFormValues normalized,
  VendorProductInputMode mode,
) {
  final Map<VendorProductField, String> errors = <VendorProductField, String>{};

  if (mode == VendorProductInputMode.create) {
    final String code = normalized.productCode;
    if (code.isEmpty) {
      // Covers empty, blank and whitespace-only alike: all three normalize to
      // the empty string, and all three are the same omission.
      errors[VendorProductField.productCode] = 'Enter a product code.';
    } else if (code.length > VendorProductInput.maxProductCodeLength) {
      errors[VendorProductField.productCode] =
          'Product codes must be '
          '${VendorProductInput.maxProductCodeLength} characters or fewer.';
    } else if (!VendorProductInput.productCodePattern.hasMatch(code)) {
      errors[VendorProductField.productCode] =
          'Use letters, numbers, spaces and . _ / - only, starting with a '
          'letter or number.';
    }
  }

  final String name = normalized.productName;
  if (name.isEmpty) {
    errors[VendorProductField.productName] = 'Enter a product name.';
  } else if (name.length > VendorProductInput.maxProductNameLength) {
    errors[VendorProductField.productName] =
        'Product names must be '
        '${VendorProductInput.maxProductNameLength} characters or fewer.';
  }

  // Optional. Only a NON-EMPTY value is judged, so leaving it blank — or
  // clearing one that was set — is never an error.
  if (normalized.barcode.isNotEmpty &&
      !VendorProductInput.barcodePattern.hasMatch(normalized.barcode)) {
    errors[VendorProductField.barcode] =
        'Enter a barcode of ${VendorProductInput.minBarcodeDigits} to '
        '${VendorProductInput.maxBarcodeDigits} digits, or leave it blank.';
  }

  if (normalized.brand.length > VendorProductInput.maxBrandLength) {
    errors[VendorProductField.brand] =
        'Brand must be ${VendorProductInput.maxBrandLength} characters or '
        'fewer.';
  }

  if (normalized.description.length > VendorProductInput.maxDescriptionLength) {
    errors[VendorProductField.description] =
        'Description must be ${VendorProductInput.maxDescriptionLength} '
        'characters or fewer.';
  }

  return errors;
}

/// The field message for a uniqueness conflict the backend attributed to [field].
///
/// Both sentences are safe to say, and safe for one reason: the two unique indexes
/// behind them are scoped **per Vendor**, so each describes the reader's own
/// catalogue and neither can reveal that another Vendor uses the same code or the
/// same barcode. The same code and the same barcode are legitimately available to
/// every other Vendor, and nothing here hints otherwise.
///
/// This is a sentence in this application's own words, chosen from a field key. The
/// backend's message is what the data layer matched to *derive* that key, and it
/// never travels this far.
///
/// Uniqueness exists on exactly two of the five fields. A conflict reported against
/// any other would be a hint this build cannot honour, which is why
/// [VendorProductField.fromKey] answers null for an unrecognised one and the caller
/// falls back to a form-level notice.
String duplicateMessageFor(VendorProductField field) => switch (field) {
  VendorProductField.productCode => 'A product with this code already exists.',
  VendorProductField.barcode => 'A product with this barcode already exists.',
  VendorProductField.productName ||
  VendorProductField.brand ||
  VendorProductField.description =>
    // No unique index exists on these three, so the backend cannot report a
    // conflict against one. The wording stays deliberately unspecific rather than
    // inventing a rule that does not exist.
    'This value is already in use.',
};
