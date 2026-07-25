/// Every user-facing sentence this feature renders, in one place.
///
/// Centralised for the same reason the receipt, Retailer, User and Role features
/// centralise theirs: a string that explains a *backend* answer is part of the
/// security boundary, not decoration. The rules these strings obey:
///
/// * **No raw backend text.** No Postgres message, SQLSTATE, table, column,
///   function, policy or permission name appears in any of them. A caller
///   without `RETAILERS_READ` sees the same generic wording as a caller who is
///   not signed in.
/// * **An inaccessible product is never described as somebody else's.**
///   [detailNotFoundTitle] and [detailNotFoundBody] are the single wording for
///   an unknown id, another Vendor's id, an id from another table and a
///   malformed id alike. "This product belongs to another Vendor" would hand
///   back the existence oracle the backend is careful to deny.
/// * **An inactive assignment is never called "currently assigned".** The
///   vocabulary is *Active assignment* / *Inactive assignment*, *Assigned on*,
///   *Last updated* — see `vendor_product_formatting.dart`.
/// * **`assignment_count` is never called "Retailers currently assigned"**,
///   because withdrawn rows are included in it. [assignmentsTitle] and the count
///   sentences say *assignments*, and the active subset is stated separately.
/// * **Nothing here names a write.** There is no create, edit, delete, activate,
///   deactivate, assign, withdraw, upload, price or reward string, because this
///   milestone performs none of those — and an affordance, even a disabled one,
///   would advertise a capability this screen does not have.
/// * **Nothing here names an image or a category**, because no such column
///   exists anywhere in the schema.
/// * **An outage is never a denial**, and a denial never reads as "not found".
///   Those two live in `SrFailureView`, which this feature reuses rather than
///   rewording.
abstract final class VendorProductCopy {
  // -- the catalogue ---------------------------------------------------------

  static const String listTitle = 'Products';

  /// Says what the catalogue is and what the count on each card means, because
  /// "12 Retailers" beside a product would otherwise read as a total rather than
  /// as the active subset it is.
  static const String listDescription =
      'Your product catalogue. Each product shows how many Retailers currently '
      'hold an active assignment of it.';

  static const String searchLabel = 'Search products';
  static const String searchPlaceholder =
      'Search by name, code, barcode or brand';
  static const String searchHint =
      'Filters the products already loaded. Nothing is sent to the server.';

  static const String statusFilterLabel = 'Product status';
  static const String filterAll = 'All';

  static const String refresh = 'Refresh';
  static const String refreshing = 'Refreshing…';
  static const String clearFilters = 'Clear filters';

  static const String loadingList = 'Loading products';

  static const String emptyTitle = 'No products yet';

  /// States the absence and stops. It does not suggest adding one: this screen
  /// cannot, and no mobile screen can.
  static const String emptyBody =
      'This Vendor organization has no products on record.';

  static const String noMatchesTitle = 'No products match';
  static const String noMatchesBody =
      'No loaded product matches the current search or status filter.';

  static const String staleListTitle = 'This list may be out of date';
  static const String staleListBody =
      'We could not refresh the product catalogue just now.';

  static const String openDetails = 'View details';

  /// Deliberately not the bare word "Products": that is the page title, and two
  /// identical strings on one screen make the summary card read as a heading.
  static const String totalLabel = 'Products in catalogue';
  static const String totalHint = 'In your Vendor organization';
  static const String activeLabel = 'Active products';
  static const String activeHint = 'Available to assign to Retailers';
  static const String inactiveLabel = 'Inactive products';
  static const String inactiveHint = 'Withdrawn from the catalogue';

  /// Deliberately "assignments" rather than "Retailers": a Retailer holding four
  /// products contributes four, and the number of distinct Retailers is a
  /// question this contract does not answer.
  static const String activeAssignmentsLabel = 'Active assignments';
  static const String activeAssignmentsHint = 'Across every product';

  // -- one product -----------------------------------------------------------

  static const String detailEyebrow = 'Product';
  static const String backToList = 'Back to Products';
  static const String loadingDetail = 'Loading product';

  static const String overviewTitle = 'Product details';

  static const String codeLabel = 'Product code';
  static const String barcodeLabel = 'Barcode';
  static const String brandLabel = 'Brand';
  static const String descriptionLabel = 'Description';
  static const String statusLabel = 'Product status';
  static const String assignmentsLabel = 'Retailer assignments';
  static const String createdLabel = 'Created';
  static const String updatedLabel = 'Last updated';

  /// Shown where a nullable field is absent. A phrase rather than a blank or an
  /// em dash — a screen reader announcing "dash" tells nobody anything — and
  /// never a value invented from another field.
  static const String notRecorded = 'Not recorded';

  /// The single wording for every product id this caller cannot address.
  static const String detailNotFoundTitle = 'Product not available';

  /// Says nothing about whether the product exists or who owns it, and offers no
  /// retry — the backend already answered, and it will answer the same way.
  static const String detailNotFoundBody =
      'This product is not available to your account. The link may be out of '
      'date or may not name a product.';

  // -- assigned Retailers ----------------------------------------------------

  static const String assignmentsTitle = 'Assigned Retailers';

  /// The careful sentence. It says the list includes history, so a reader
  /// scanning it does not read every row as a current assignment.
  static const String assignmentsDescription =
      'Every Retailer this product has been assigned to, including assignments '
      'that have since been withdrawn.';

  static const String assignmentsEmptyTitle = 'Not assigned to any Retailer';
  static const String assignmentsEmptyBody =
      'This product has not been assigned to any Retailer.';

  static const String assignmentsUnavailableTitle =
      'Assigned Retailers unavailable';
  static const String assignmentsUnavailableBody =
      'We could not load the Retailer assignments for this product. The product '
      'details above are still current.';
  static const String retryAssignments = 'Try again';

  static const String loadingAssignments = 'Loading assigned Retailers';

  /// The cross-link into the shipped Vendor Retailer detail screen. Offered only
  /// when `relationship_id` is present.
  static const String viewRetailer = 'View Retailer';

  /// The honest description of an assignment whose `vendor_retailers` row is
  /// gone. It is not a Retailer problem and not an assignment problem — the
  /// assignment is intact and its status is real — so the wording names the one
  /// thing that is actually missing.
  static const String relationshipUnavailable =
      'Retailer relationship unavailable';

  /// Explained once above the rows rather than repeated on each, so a reader
  /// understands why one row offers no action.
  static const String relationshipUnavailableNote =
      'One or more assignments below no longer have a Vendor–Retailer '
      'relationship on record, so the Retailer cannot be opened from here. The '
      'assignments themselves are unaffected.';

  static const String relationshipUnavailableSemantics =
      'Retailer relationship unavailable. This Retailer cannot be opened from '
      'this assignment.';

  /// Surfaced when the product row and the assignment list disagree about how
  /// many assignments there are. Every returned row is still shown and both
  /// counts are still reported unchanged.
  static const String countMismatchTitle = 'This list may have just changed';
  static const String countMismatchBody =
      'The number of assignments recorded for this product does not match the '
      'list below. Everything returned is shown. Refresh to read both again.';

  // -- assignment status semantics -------------------------------------------

  /// The subject prefix on an assignment status pill, so three pills sharing a
  /// vocabulary are never mistaken for one another.
  static const String assignmentStatusSubject = 'Assignment';
  static const String relationshipStatusSubject = 'Relationship';
  static const String retailerStatusSubject = 'Retailer';

  static const String assignedOnLabel = 'Assigned on';

  /// Named for what the column is. There is no `withdrawn_at` anywhere in the
  /// schema, so this is never labelled or spoken as one — not even on an
  /// inactive row, where it happens to be the moment of withdrawal.
  static const String assignmentUpdatedLabel = 'Assignment last updated';
}
