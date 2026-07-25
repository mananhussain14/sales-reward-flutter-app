/// The lifecycle status of a **product** in a Vendor's catalogue.
///
/// The deployed `public.vendor_products` table constrains its `status` column
/// with `vendor_products_status_allowed`, which permits exactly two values —
/// `ACTIVE` and `INACTIVE`. Both are read from the migration rather than
/// assumed, and the backend audit is explicit that nothing else exists:
///
/// > *There is **no** draft, archived, discontinued, review or approval state in
/// > this schema, and none is invented.*
///
/// So there is no `draft`, no `archived`, no `discontinued` and no `pending`
/// member here, and no screen may offer a filter for one.
///
/// ## An `INACTIVE` product is fully readable, and keeps its assignments
///
/// Neither `list_vendor_products()` nor `get_vendor_product_detail()` filters by
/// product status, and `set_vendor_product_status` deliberately does **not**
/// cascade — so an inactive product still reports its real
/// `assignment_count` and `active_assignment_count`. Hiding it, or zeroing its
/// counts, would make deactivating look like deleting. This enum therefore
/// carries no "should this be shown" property, because the answer is always yes.
///
/// ## This is a separate concept from an assignment's status
///
/// `VendorProductAssignmentStatus` shares this vocabulary and is a **different
/// fact about a different row**: this one says whether the product is live in
/// the catalogue, that one says whether one Retailer currently holds it. They
/// are deliberately two types rather than one shared enum, because collapsing
/// them would make it possible to pass a product status where an assignment
/// status belongs and have it compile.
///
/// > Contrast [VendorRetailerStatus] in the Retailer feature, which genuinely
/// > *is* one enum for three columns — `organizations.status`,
/// > `vendor_retailers.status` and `retailer_shops.status` all share the same
/// > three-value `ACTIVE / SUSPENDED / DEACTIVATED` constraint. Sharing a
/// > vocabulary is what makes one type right there; here the vocabularies
/// > coincide at two values but the subjects do not.
///
/// ## Why [unknown] exists, and what it may never do
///
/// A token this build does not recognise means the backend is newer than the
/// app. That is an additive change, so it degrades to [unknown] and renders as a
/// neutral "Unknown" badge rather than failing the read or dropping the product
/// from the catalogue — a Vendor must not lose sight of a product because its
/// status is unfamiliar.
///
/// [unknown] is **never** [active]: it is counted as neither active nor
/// inactive, and it never carries the raw backend token to the screen. A
/// **missing or blank** status is a different thing entirely — a required value
/// the response did not supply — and the parser raises a format error for it.
enum VendorProductStatus {
  /// Live in the catalogue.
  active('ACTIVE'),

  /// Withdrawn from the catalogue. Still listed, still openable, and still
  /// reporting its real assignment counts.
  inactive('INACTIVE'),

  /// A value this build does not know. Displayed neutrally, and nothing more.
  unknown('');

  const VendorProductStatus(this.code);

  /// The backend token, or the empty string for [unknown].
  final String code;

  /// Maps a backend token to a status, falling back to [unknown].
  ///
  /// Never throws: the caller has already established that a status string is
  /// present, and an unrecognised value is a forward-compatibility case rather
  /// than a malformed response.
  static VendorProductStatus fromCode(String raw) {
    for (final VendorProductStatus status in values) {
      if (status != unknown && status.code == raw) {
        return status;
      }
    }
    return unknown;
  }

  /// Whether this is the one status that means "active".
  ///
  /// Deliberately a positive test against a single member rather than
  /// `!= inactive`, so a future token can never arrive at "active" by failing to
  /// match something else.
  bool get isActive => this == active;
}
