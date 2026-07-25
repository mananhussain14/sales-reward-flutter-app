import '../../../../core/result/read_result.dart';
import '../entities/vendor_product_assigned_retailer.dart';
import '../entities/vendor_product_detail.dart';
import '../entities/vendor_product_summary.dart';

/// The three Vendor Product reads, and nothing else.
///
/// One repository for all three deliberately: they share a Vendor derivation, a
/// selector vocabulary and a failure contract, and splitting them would create
/// three places for those to drift.
///
/// ## This milestone is read-only, and the interface is the proof
///
/// There is no create, update, delete, activate, deactivate, assign, withdraw,
/// image-upload, price or reward method here, and no place to add one without
/// changing this file. Those RPCs *do* exist on the backend — unlike the Roles
/// surface, where no write backend exists at all — which makes the absence a
/// deliberate scope decision rather than a limitation, and makes it worth
/// stating: the write contracts discriminate a duplicate code from a duplicate
/// barcode by an **English message substring** and return `void` where "changed"
/// and "already so" would need telling apart, both of which the backend contract
/// records as defects to fix before a client depends on them.
///
/// No disabled affordance is offered either. An action a screen shows and cannot
/// perform is a promise about a feature that has not been built.
///
/// ## What the signatures make impossible
///
/// [products] takes **no arguments**. [productDetail] and [assignedRetailers]
/// take exactly one each, and it is a product id. There is no auth user id,
/// profile id, membership id, Vendor organization id, tenant id, Retailer
/// organization id, product code, product status, assignment status, role code,
/// permission code, search term or page cursor anywhere on this interface — not
/// as an optional, not as a named argument with a default.
///
/// The absence is the point. The Vendor is derived from `auth.uid()` in SQL by
/// `get_vendor_super_admin_context()`, and the product id **selects** which
/// already-authorized row is read without ever deciding *whether* anything may
/// be read. Holding one grants nothing: `vendor_products.vendor_organization_id`
/// is `NOT NULL` and immutable by trigger, so another Vendor's product id
/// matches nothing.
///
/// The Retailer organization id is deliberately an **output only**, for the same
/// reason it is in the Retailer reads: it names a tenant some other Vendor may
/// also manage.
///
/// ## Why the detail read exists, given the list already has the row
///
/// Three reasons, and the third is the one this client depends on: a refresh
/// that costs one row instead of the catalogue; a deep link openable without the
/// list; and an **authoritative answer to "is this id addressable by me"**.
/// [assignedRetailers] answers an empty list for a genuinely unassigned product
/// *and* for an id that names no product this caller may read, indistinguishably.
/// Zero rows from [productDetail] is what tells those apart — which is why a
/// caller loads the detail first and issues the assignment read only after a row
/// comes back.
///
/// The web, by contrast, has no detail read at all: it downloads the whole
/// catalogue and finds the row with `Array.find()` in TypeScript. Reimplementing
/// that in Dart would make a second client responsible for a scoping decision
/// that belongs in SQL, and would transfer every product to render one.
abstract interface class VendorProductRepository {
  /// `public.list_vendor_products()` — zero arguments.
  ///
  /// The calling Vendor's whole catalogue in the backend's
  /// `created_at desc, product_id desc` order — newest first, and total, so a
  /// re-fetching client sees a stable sequence.
  ///
  /// Unpaginated by design. Each row carries its own `active_assignment_count`
  /// as a scalar aggregate computed in the same statement, so there is no
  /// per-product assignment read and nothing here is N+1.
  ///
  /// An empty list is a legitimate answer — a Vendor with no products — and is
  /// never produced from a failure. A refusal is `42501` and arrives as a
  /// [ReadFailure], because a denial and an empty catalogue are opposite claims.
  Future<ReadResult<List<VendorProductSummary>>> products();

  /// `public.get_vendor_product_detail(p_product_id)`.
  ///
  /// Returns `null` inside a success for zero rows — the backend's answer for an
  /// unknown id, another Vendor's id, an id belonging to some other table, and
  /// `null` alike. This client adds a **malformed** id to that same set rather
  /// than inventing a fifth outcome, answering it locally without a request ever
  /// leaving the device.
  ///
  /// A zero-row answer is a **success carrying null**, never a failure: the
  /// backend answered, and reporting it as an outage would offer a retry that
  /// cannot change anything. It is also never worded as "another Vendor owns
  /// this" — the backend makes unknown and foreign byte-identical precisely so
  /// that an id sweep reveals neither the existence nor the size of another
  /// Vendor's catalogue, and a client that told them apart would hand that
  /// oracle back.
  Future<ReadResult<VendorProductDetail?>> productDetail(String productId);

  /// `public.list_vendor_product_assigned_retailers(p_product_id)`.
  ///
  /// One row per **existing** assignment, in the backend's
  /// `retailer_name, retailer_organization_id` order. Never-assigned Retailers
  /// are absent; withdrawn (`INACTIVE`) assignments are present and marked.
  ///
  /// An empty list means the product has never been assigned — **provided**
  /// [productDetail] has already confirmed the id is addressable. Called for an
  /// id that is not, it returns the same empty list, which is why it is never
  /// called first.
  ///
  /// This read requires `RETAILERS_READ` in addition to `PRODUCTS_READ`, because
  /// it returns Retailer identity. That split is enforced entirely in SQL; this
  /// client neither knows nor sends either code, and a refusal arrives as the
  /// same generic [DeniedFailure] every other refusal does.
  Future<ReadResult<List<VendorProductAssignedRetailer>>> assignedRetailers(
    String productId,
  );
}
