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
/// * **Nothing here names a write this client cannot perform.** There is create,
///   edit, activate and deactivate copy, because those three RPCs are called. There
///   is **no** delete string — no delete control, action, RPC or `DELETE`
///   statement exists anywhere in the product — and **no** assign, withdraw or
///   bulk-assignment string, because assignment writes are a separate milestone on
///   a separate permission and the assigned-Retailer section stays read-only. An
///   affordance, even a disabled one, would advertise a capability that does not
///   exist.
/// * **Deactivation is never worded as deletion or as removal.** The row, its
///   history and every one of its assignment rows survive, so the vocabulary is
///   *Deactivate* / *Activate* and *availability*, and the confirmation says
///   plainly what is and is not affected.
/// * **A succeeded write is never described as failed.** A mutation whose
///   follow-up canonical read did not answer has its own wording, which says the
///   change was saved and that the figures on screen may be stale.
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

  /// States the absence, and now invites the one action that answers it — the
  /// catalogue can add a product, so saying so is a fact rather than a promise.
  static const String emptyBody =
      'This Vendor organization has no products on record. Add one to start '
      'building the catalogue.';

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

  /// The name's own label. Absent from the detail screen's fact list, where the
  /// name *is* the page title — a form needs one, and a form needs the same word
  /// the catalogue's search placeholder already uses.
  static const String nameLabel = 'Product name';
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

  // -- creating a product ----------------------------------------------------

  static const String addProduct = 'Add product';
  static const String addProductSemantics =
      'Add product. Opens a form to create a new product in this catalogue.';

  static const String createTitle = 'Add a product';
  static const String createDescription =
      'A new product is added to your own catalogue and is active straight '
      'away. It is not assigned to any Retailer until you assign it.';

  static const String createSubmit = 'Create product';
  static const String createSubmitting = 'Creating product…';
  static const String cancel = 'Cancel';
  static const String backToProduct = 'Back to product';

  /// Shown while the created product is being read back. The create itself is
  /// already done at this point, which is why the wording is about reading rather
  /// than about saving.
  static const String createdOpening = 'Opening the new product…';

  /// The acknowledgement on the canonical product screen. Says the product was
  /// created and stops — the figures beside it are the backend's own.
  static const String createdTitle = 'Product created';
  static const String createdBody =
      'The details below were read back from your catalogue. The product is not '
      'assigned to any Retailer yet.';

  /// The create succeeded and its id could not be read.
  ///
  /// Every word here matters. It must not say the create failed, because it did
  /// not; it must not offer to create again, because that would duplicate the
  /// product or be refused as a duplicate code; and it must send the reader to the
  /// catalogue, which is the only authority on what exists.
  static const String createUnconfirmedTitle = 'Product created';
  static const String createUnconfirmedBody =
      'The product was created, but we could not open it just now. Find it in '
      'your catalogue — do not create it again, or you may end up with two.';
  static const String goToCatalogue = 'Go to Products';

  // -- editing a product -----------------------------------------------------

  static const String edit = 'Edit';
  static const String editSemantics =
      'Edit. Opens a form to change this product’s name, barcode, brand and '
      'description.';

  static const String editTitle = 'Edit product';
  static const String editDescription =
      'Change this product’s name, barcode, brand and description. The product '
      'code cannot be changed, and the product’s status and Retailer '
      'assignments are not affected.';

  static const String save = 'Save changes';
  static const String saving = 'Saving changes…';

  /// The read-only code on the edit screen, and the sentence that explains why it
  /// cannot be changed without naming a trigger or a constraint.
  static const String codeReadOnlyHint =
      'The product code is set when a product is created and cannot be changed.';
  static const String codeReadOnlySemantics =
      'Product code, read only. Set when the product was created and cannot be '
      'changed.';

  static const String updatedTitle = 'Changes saved';

  /// True whether the save changed something or matched what was already stored —
  /// the backend deliberately makes those indistinguishable, so this sentence must
  /// not claim to know which happened.
  static const String updatedBody =
      'This product’s details below are the ones now on record.';

  // -- activating and deactivating -------------------------------------------

  static const String deactivate = 'Deactivate';
  static const String activate = 'Activate';
  static const String deactivating = 'Deactivating…';
  static const String activating = 'Activating…';

  static const String deactivateSemantics =
      'Deactivate product. Asks for confirmation first.';
  static const String activateSemantics =
      'Activate product. Asks for confirmation first.';

  static const String statusSectionTitle = 'Product availability';
  static const String statusSectionActiveDescription =
      'This product is active, so it can be assigned to your Retailers.';
  static const String statusSectionInactiveDescription =
      'This product is inactive. It cannot be assigned to a Retailer while it '
      'stays that way, and Retailers do not see it in their assigned products.';

  /// Shown when a status token this build does not recognise came back. No action
  /// is offered, because the opposite of an unfamiliar status is not knowable.
  static const String statusSectionUnknownDescription =
      'This product’s status is not one this version of the app recognises, so '
      'it cannot be changed from here.';

  static const String deactivateConfirmTitle = 'Deactivate this product?';

  /// Four sentences, and every one is provable from the deployed contract:
  /// deactivation changes availability; it does not delete; history is preserved;
  /// and assignment rows are not removed. Nothing is claimed about receipts — the
  /// backend audit is explicit that no receipt-matching step exists yet — beyond
  /// the two effects it does prove.
  static const String deactivateConfirmBody =
      'The product stays in your catalogue and nothing is deleted. Its history '
      'and its existing Retailer assignments are kept exactly as they are.\n\n'
      'While it is inactive it cannot be assigned to a Retailer, and Retailers '
      'do not see it among their assigned products. You can activate it again '
      'at any time.';

  static const String activateConfirmTitle = 'Activate this product?';
  static const String activateConfirmBody =
      'The product becomes available to assign to your Retailers again. Its '
      'existing Retailer assignments are unchanged.';

  static const String statusChangedTitle = 'Product status updated';
  static const String statusChangedBody =
      'The status below was read back from your catalogue. Retailer '
      'assignments were not changed.';

  // -- write failures --------------------------------------------------------

  /// A duplicate the backend did not attribute to a field. Deliberately
  /// unspecific: pointing at the wrong input would send somebody to change a value
  /// that is fine.
  static const String duplicateUnattributedTitle =
      'That product already exists';
  static const String duplicateUnattributedBody =
      'One of these values is already used by another product in your '
      'catalogue.';

  /// A value the backend rejected that this app’s own checks let through. It names
  /// no column and no constraint, and offers the one useful instruction.
  static const String invalidWriteTitle = 'Check these details';
  static const String invalidWriteBody =
      'One of these values was not accepted. Review the fields and try again.';

  static const String writeUnavailableTitle = 'That did not go through';
  static const String writeUnavailableBody =
      'We could not complete that just now. Check your connection and try '
      'again.';

  /// One generic wording for every refusal the backend answers `42501` to — an
  /// unauthorized caller, a product that does not exist, and a product belonging to
  /// another Vendor alike. It names no permission and says nothing about whether
  /// any product exists, because telling those apart is the existence oracle the
  /// backend is careful to deny.
  static const String writeDeniedTitle = 'That is not available';
  static const String writeDeniedBody =
      'This change is not available to your account. Refresh and try again.';

  static const String writeSignedOutTitle = 'Your session has ended';
  static const String writeSignedOutBody =
      'Sign in again to make changes to your catalogue.';

  static const String statusFailedTitle = 'Status not changed';

  /// The important half: the product's status is unchanged, so what is on screen is
  /// still correct.
  static const String statusFailedBody =
      'We could not change this product’s status just now, so it is unchanged. '
      'Try again.';

  // -- a write that landed, and a read that did not ---------------------------

  /// The partial-success wording, and the reason this state is modelled at all: the
  /// change is saved, and only the picture of it is stale.
  static const String staleAfterWriteTitle =
      'Saved, but this may be out of date';
  static const String staleAfterWriteBody =
      'Your change was saved. We could not read the product back just now, so '
      'the details below may not reflect it yet.';
  static const String reload = 'Reload';
  static const String reloading = 'Reloading…';
  static const String reloadSemantics =
      'Reload this product. Reads its current details from your catalogue '
      'again.';

  /// A `void` write that answered with something this build could not read. The
  /// change may well have been applied — the transaction commits or raises — so the
  /// wording neither claims nor denies it and points at the re-read figures.
  static const String unconfirmedWriteTitle = 'This may have been applied';
  static const String unconfirmedWriteBody =
      'We could not confirm the change from the response. The details below '
      'were read back from your catalogue and are what is on record.';

  static const String refreshingProduct = 'Reading this product again…';

  // -- form field labels -----------------------------------------------------

  static const String codeFieldHint =
      'Letters, numbers, spaces and . _ / - only. Stored in capitals, and '
      'unique within your own catalogue.';
  static const String namePlaceholder = 'Espresso Blend 1kg';
  static const String codePlaceholder = 'ESP-1000';
  static const String barcodePlaceholder = '5012345678900';

  /// Says the two things a person needs: how long, and that separators are fine.
  /// It does not promise a scanner — there is none — and it does not call the value
  /// a number, because it is stored and compared as text.
  static const String barcodeFieldHint =
      '8 to 14 digits. Spaces and hyphens are ignored. Unique within your own '
      'catalogue. Leave blank if the product has none.';
  static const String brandPlaceholder = 'Harvest Roasters';
  static const String descriptionFieldHint =
      'Line breaks and paragraphs are kept as you write them.';
}
