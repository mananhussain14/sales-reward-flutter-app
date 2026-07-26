import '../../../../core/result/read_result.dart';
import '../entities/vendor_product_assigned_retailer.dart';
import '../entities/vendor_product_detail.dart';
import '../entities/vendor_product_draft.dart';
import '../entities/vendor_product_edit.dart';
import '../entities/vendor_product_status_change.dart';
import '../entities/vendor_product_summary.dart';
import 'vendor_product_write_result.dart';

/// The three Vendor Product reads and the three Vendor Product writes.
///
/// One repository for all six deliberately: they share a Vendor derivation, a
/// selector vocabulary, an id-shape guard and a failure contract, and splitting
/// them would create two places for those to drift — while every write is
/// immediately followed by one of the reads, so a caller would have needed both
/// halves anyway.
///
/// ## Reads and writes are separate result types, on purpose
///
/// The reads answer [ReadResult]; the writes answer [VendorProductWriteResult],
/// which has a third case a read cannot need — "it happened, but the answer could
/// not be read". See that file for why conflating the two would be unsafe.
///
/// ## The write surface is exactly three operations
///
/// Create, edit, and status. There is deliberately **no delete** — no control, no
/// action, no RPC and no `DELETE` statement exists anywhere in the schema, so a
/// method here would be one this client could never fulfil. There is deliberately
/// **no assign, withdraw or bulk-assignment** method either: those are two
/// separate functions gated on a *different* permission
/// (`PRODUCT_RETAILER_ASSIGN`, not `PRODUCTS_MANAGE`), they are a separate
/// milestone, and the existing assigned-Retailer section stays read-only. Product
/// create, edit and status neither create, read nor mutate an assignment row —
/// the backend's own suite proves a full create → edit → deactivate → activate
/// lifecycle produces zero of them.
///
/// And no image upload, price, stock, reward, incentive or campaign method,
/// because none of those columns exists anywhere in the schema.
///
/// ## What the signatures make impossible
///
/// [products] takes **no arguments**. [productDetail] and [assignedRetailers]
/// take exactly one each, and it is a product id. [createProduct] takes the five
/// product fields and nothing beside them — there is no organization id to send.
/// [updateProduct] and [setProductStatus] take a product id plus the values being
/// changed. There is no auth user id, profile id, membership id, Vendor
/// organization id, tenant id, Retailer organization id, product code on the edit
/// path, product status on the create or edit path, assignment status, role code,
/// permission code, actor, audit metadata, search term or page cursor anywhere on
/// this interface — not as an optional, not as a named argument with a default.
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

  /// `public.create_vendor_product(p_product_code, p_product_name, p_barcode,
  /// p_brand, p_description)` — five text arguments, and `returns uuid`.
  ///
  /// The new product is `ACTIVE`, because the function says so; there is no
  /// initial-status argument to pass and none is invented. It creates **no
  /// assignment row**, and it writes exactly one `PRODUCT_CREATED` audit row in
  /// the same transaction — which this client neither performs nor supplements.
  ///
  /// On success the value is the new `vendor_products.id`, and it is the *only*
  /// thing the write returns. The canonical product is obtained by reading
  /// [productDetail] with it: a screen must never assemble a product from the
  /// values it submitted, because the backend normalizes every one of them and the
  /// stored result can legitimately differ from what was typed.
  ///
  /// A success whose value is not shaped like a uuid answers
  /// [VendorProductWriteUnconfirmed] — the product exists and cannot be
  /// addressed — and is never retried.
  Future<VendorProductWriteResult<String>> createProduct(
    VendorProductDraft draft,
  );

  /// `public.update_vendor_product(p_product_id, p_product_name, p_barcode,
  /// p_brand, p_description)` — `returns void`.
  ///
  /// [productId] is an **address**, not an authorization: the row is matched on
  /// both its own id and the Vendor derived from `auth.uid()`, so an unknown id,
  /// another Vendor's id and a null one are refused byte-identically and arrive
  /// here as one generic [DeniedFailure]. A **malformed** id is refused locally,
  /// without a request leaving the device, and joins that same set rather than
  /// becoming a fourth outcome.
  ///
  /// There is no product-code and no status parameter. Assignment rows are
  /// untouched. A submission that changes nothing succeeds silently and writes no
  /// audit row.
  Future<VendorProductWriteResult<void>> updateProduct(
    String productId,
    VendorProductEdit edit,
  );

  /// `public.set_vendor_product_status(p_product_id, p_status)` — `returns void`.
  ///
  /// [change] can only be `ACTIVE` or `INACTIVE`, because
  /// [VendorProductStatusChange] has only those two members; the response enum's
  /// forward-compatibility `unknown` is not expressible here.
  ///
  /// Both transitions are permitted in both directions, and setting the status a
  /// product already has is an idempotent no-op in SQL — no write, no `updated_at`
  /// movement, **no audit row** — which is what stops a double tap recording two
  /// decisions.
  ///
  /// **Deactivation is not deletion, and it does not cascade.** The row, its
  /// `created_at` and every one of its assignment rows survive untouched, down to
  /// their `updated_at`. It makes the product ineligible for a *new* assignment
  /// and removes it from the Retailer-facing list, and that is all.
  Future<VendorProductWriteResult<void>> setProductStatus(
    String productId,
    VendorProductStatusChange change,
  );
}
