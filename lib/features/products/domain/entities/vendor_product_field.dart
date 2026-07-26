/// The five product fields a write can address, and nothing else.
///
/// An enum rather than a set of string keys so a field error, a focus target and
/// a duplicate hint can only ever name a field that exists. There is deliberately
/// no `status`, `vendor`, `organization`, `price`, `stock`, `image`, `reward`,
/// `campaign` or `assignment` member: none of those is a parameter of any
/// deployed product write, so none of them can be a form field, a validation
/// subject or an error target.
enum VendorProductField {
  /// Required on create, **never** submitted on edit — the backend accepts no
  /// product-code parameter on `update_vendor_product` and a trigger refuses a
  /// direct change.
  productCode,

  /// Required on both.
  productName,

  /// Optional, clearable, and text throughout. Never a number.
  barcode,

  /// Optional and clearable.
  brand,

  /// Optional, clearable, and multi-line.
  description;

  /// The stable key used as a [DuplicateFailure] hint across the data and
  /// presentation layers.
  ///
  /// It names a *client-side form field*, never a database column: `productCode`
  /// rather than `product_code`, so nothing here can be mistaken for a value
  /// travelling to or from PostgREST.
  String get key => name;

  /// The field [key] names, or null when it names none.
  ///
  /// Null rather than a throw or a default: a hint this build does not recognise
  /// must degrade to "a duplicate, somewhere in this form" rather than point at
  /// the wrong input, which would send somebody to change a value that is fine.
  static VendorProductField? fromKey(String? key) {
    for (final VendorProductField field in values) {
      if (field.key == key) {
        return field;
      }
    }
    return null;
  }
}
