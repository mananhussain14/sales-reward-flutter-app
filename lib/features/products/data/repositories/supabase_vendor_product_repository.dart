import '../../../../core/errors/failure.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../../../core/result/read_result.dart';
import '../../domain/entities/vendor_product_assigned_retailer.dart';
import '../../domain/entities/vendor_product_assignment_request.dart';
import '../../domain/entities/vendor_product_detail.dart';
import '../../domain/entities/vendor_product_draft.dart';
import '../../domain/entities/vendor_product_edit.dart';
import '../../domain/entities/vendor_product_status_change.dart';
import '../../domain/entities/vendor_product_summary.dart';
import '../../domain/repositories/vendor_product_repository.dart';
import '../../domain/repositories/vendor_product_write_result.dart';
import '../datasources/vendor_product_assignment_rpc_data_source.dart';
import '../datasources/vendor_product_rpc_data_source.dart';
import '../datasources/vendor_product_write_rpc_data_source.dart';
import '../models/vendor_product_parsers.dart';
import '../models/vendor_product_write_parsers.dart';

/// The real [VendorProductRepository].
///
/// Each read does exactly three things, in order: call the RPC, parse the body,
/// classify the answer. Each write does the same three, with one addition — an
/// unreadable answer from a write that already committed is a *third* outcome
/// rather than a failure. Each of those steps is somebody else's code — the data
/// sources, the parsers, and the error mappers — so this class contains no
/// branching of its own beyond "did it throw?" and the id-shape guards below.
///
/// ## It reproduces no backend authorization logic
///
/// There is no Vendor organization id here, no comparison of a product's owner,
/// no join over `vendor_products`, `vendor_product_retailer_assignments`,
/// `vendor_retailers` and `organizations`, and no count assembled from rows.
/// Whether this caller may read the catalogue is decided in SQL by
/// `get_vendor_super_admin_context()` and by `has_organization_permission` on
/// **every** call — and the assignment companion deliberately requires one
/// permission more than the other two, a split this client neither knows nor
/// could enforce. Restating any of it would create a second definition free to
/// drift, and only one of the two could be right.
///
/// Nor is ownership inferred. A product's status, its counts, its dates and the
/// statuses of the Retailers it is assigned to are all *display* data; none of
/// them decides whether anything may be read.
/// ## Authorization is still nowhere in this file, including for the writes
///
/// Whether this caller may *manage* products is decided in SQL by
/// `get_vendor_super_admin_context()` and `has_organization_permission` on every
/// single call — and the write permission is a **different** one from the read
/// permission, a split this client neither knows nor could enforce. There is no
/// permission code here, no check of a product's owner, no comparison of a status
/// against an allowed transition table, and no local decision about whether a
/// product "can" be edited. A loaded product's status decides which *label* the
/// status action carries and nothing else.
/// ## The assignment writes are a third source, for a third reason
///
/// They are gated on `PRODUCT_RETAILER_ASSIGN` rather than `PRODUCTS_MANAGE` —
/// a split the backend proved holds in both directions — and their payload
/// vocabulary is two addresses rather than five Product fields. Keeping them in
/// their own data source is what lets each boundary test assert one exact
/// parameter set. Neither code is named, sent or compared anywhere in this file.
final class SupabaseVendorProductRepository implements VendorProductRepository {
  const SupabaseVendorProductRepository({
    required VendorProductRpcDataSource rpc,
    required VendorProductWriteRpcDataSource writes,
    required VendorProductAssignmentRpcDataSource assignments,
  }) : _rpc = rpc,
       _writes = writes,
       _assignments = assignments;

  final VendorProductRpcDataSource _rpc;
  final VendorProductWriteRpcDataSource _writes;
  final VendorProductAssignmentRpcDataSource _assignments;

  @override
  Future<ReadResult<List<VendorProductSummary>>> products() {
    return _read<List<VendorProductSummary>>(
      _rpc.fetchProducts,
      VendorProductSummaryParser.parseList,
    );
  }

  @override
  Future<ReadResult<VendorProductDetail?>> productDetail(String productId) {
    // A malformed id names no product. The backend's own answer for an id that
    // names no product is zero rows, so answering `null` here is the *same*
    // answer rather than a new one — and it keeps a mistyped URL from reaching
    // PostgREST as a `22P02` cast error that would surface as a database
    // outage, complete with a retry that could never succeed.
    //
    // The cast happens *before* the function body runs and therefore before any
    // authorization check, so the error would also be a fourth outcome the
    // contract does not define. Deciding it locally keeps this client's error
    // model to the three that are real: denied, zero rows, unavailable.
    //
    // It is emphatically not a claim about existence: null is what an unknown
    // id, another Vendor's id, an id belonging to another table and a malformed
    // id all produce.
    if (!isProductIdShaped(productId)) {
      return Future<ReadResult<VendorProductDetail?>>.value(
        const ReadSuccess<VendorProductDetail?>(null),
      );
    }
    return _read<VendorProductDetail?>(
      () => _rpc.fetchDetail(productId),
      VendorProductDetailParser.parseSingle,
    );
  }

  @override
  Future<ReadResult<List<VendorProductAssignedRetailer>>> assignedRetailers(
    String productId,
  ) {
    // Defence in depth rather than the primary guard. A caller reaches this
    // method only after [productDetail] has returned a row, and a malformed id
    // can never return one — so in the shipped flow this branch is unreachable.
    // It is here so that the *rule* holds at the boundary that talks to
    // PostgREST: no malformed selector is ever put into a `uuid` parameter,
    // whoever calls.
    //
    // The empty list is the backend's own answer for an id that names no
    // product, so this substitutes nothing.
    if (!isProductIdShaped(productId)) {
      return Future<ReadResult<List<VendorProductAssignedRetailer>>>.value(
        const ReadSuccess<List<VendorProductAssignedRetailer>>(
          <VendorProductAssignedRetailer>[],
        ),
      );
    }
    return _read<List<VendorProductAssignedRetailer>>(
      () => _rpc.fetchAssignedRetailers(productId),
      VendorProductAssignedRetailerParser.parseList,
    );
  }

  @override
  Future<VendorProductWriteResult<String>> createProduct(
    VendorProductDraft draft,
  ) async {
    // No id guard: create addresses nothing. There is also no organization to
    // resolve, no status to choose and no assignment to seed — the five values
    // below are the whole payload.
    final Object? raw;
    try {
      raw = await _writes.createProduct(
        productCode: draft.productCode,
        productName: draft.productName,
        barcode: draft.barcode,
        brand: draft.brand,
        description: draft.description,
      );
    } on Object catch (error) {
      // Nothing was written: every refusal these functions raise rolls the whole
      // transaction back, so a failure here leaves no product and no audit row.
      return VendorProductWriteFailure<String>(
        mapVendorProductWriteError(error),
      );
    }

    try {
      return VendorProductWriteSuccess<String>(parseCreatedProductId(raw));
    } on VendorProductFormatException {
      // The product EXISTS. The call returned success, which for this function
      // means the insert and its audit row committed — only the id could not be
      // read. Reporting a failure here would be false, and re-arming a create
      // button would invite a duplicate.
      return const VendorProductWriteUnconfirmed<String>();
    }
  }

  @override
  Future<VendorProductWriteResult<void>> updateProduct(
    String productId,
    VendorProductEdit edit,
  ) {
    return _write(
      productId,
      () => _writes.updateProduct(
        productId: productId,
        productName: edit.productName,
        barcode: edit.barcode,
        brand: edit.brand,
        description: edit.description,
        // No product code, and no status. Neither is a parameter of the deployed
        // function, so neither can be sent from here.
      ),
    );
  }

  @override
  Future<VendorProductWriteResult<void>> setProductStatus(
    String productId,
    VendorProductStatusChange change,
  ) {
    return _write(
      productId,
      () => _writes.setProductStatus(
        productId: productId,
        // The only source of this token is the two-member request enum, so
        // `unknown` — the response enum's forward-compatibility case — cannot
        // reach the wire.
        status: change.code,
      ),
    );
  }

  @override
  Future<VendorProductWriteResult<void>> assignRetailer(
    VendorProductAssignmentRequest request,
  ) {
    return _assignmentWrite(
      request,
      () => _assignments.assign(
        productId: request.productId,
        retailerOrganizationId: request.retailerOrganizationId,
        // Two arguments, and there is no third to pass: no Vendor, no tenant,
        // no actor, no relationship id, no assignment status and no audit
        // metadata. The function has a parameter for none of them.
      ),
    );
  }

  @override
  Future<VendorProductWriteResult<void>> withdrawRetailer(
    VendorProductAssignmentRequest request,
  ) {
    return _assignmentWrite(
      request,
      () => _assignments.withdraw(
        productId: request.productId,
        retailerOrganizationId: request.retailerOrganizationId,
      ),
    );
  }

  /// A `void` assignment write against one pairing: guard both ids, call,
  /// classify.
  ///
  /// The id-shape guard is the rule the Product writes apply, applied to **both**
  /// addresses. A malformed uuid comes back as a `22P02` cast error raised
  /// *before* the function body runs and therefore before any authorization
  /// check, which is neither an authorization answer nor an outage; it is decided
  /// locally and answered as [DeniedFailure], which is byte-identically what the
  /// backend answers for an id naming no Product, an id belonging to another
  /// Vendor and a null id. It says nothing about whether anything exists.
  ///
  /// In the shipped flow the guard is unreachable — both ids come from a
  /// canonical read that already returned them — so it is defence in depth at the
  /// boundary that talks to PostgREST.
  ///
  /// ## The error mapping is [mapSupabaseError] directly, with nothing on top
  ///
  /// Unlike the Product-record writes, these two accept **no text input at all**,
  /// so there is no duplicate to attribute to a form field and no reason to read
  /// a message literal. Every outcome is decided by SQLSTATE alone: `42501` — the
  /// backend's single answer for an unauthorized caller, an unknown Product, a
  /// foreign Product, an unknown Retailer, a foreign Retailer, a suspended
  /// Retailer, a suspended relationship and a missing relationship alike —
  /// becomes one generic [DeniedFailure]; `55000`, which only an ineligible
  /// Product produces, becomes [NotReadyFailure]; the theoretical `23505` of a
  /// uniqueness race becomes [DuplicateFailure]; an `AuthException` becomes
  /// [UnauthenticatedFailure]; and every transport fault becomes
  /// [UnavailableFailure]. No backend message travels past this line.
  Future<VendorProductWriteResult<void>> _assignmentWrite(
    VendorProductAssignmentRequest request,
    Future<Object?> Function() call,
  ) async {
    if (!request.isAddressable) {
      return const VendorProductWriteFailure<void>(DeniedFailure());
    }

    final Object? raw;
    try {
      raw = await call();
    } on Object catch (error) {
      // Nothing was written. Authorization, eligibility, the mutation and the
      // audit insert are one plpgsql body and therefore one transaction, so a
      // refusal leaves no assignment row, no status change and no audit row —
      // and the person may safely be offered another attempt.
      return VendorProductWriteFailure<void>(mapSupabaseError(error));
    }

    // `null` is the established shape for a `returns void` function. A body is a
    // response this build cannot read — but a 2xx from either function means the
    // row and its audit row are already committed, so it is emphatically NOT a
    // failure and is emphatically not retried: a repeated assign of a pairing
    // that is now `ACTIVE` is a no-op, but a repeated *withdraw* after a
    // reactivation elsewhere would undo somebody's work. It becomes
    // "unconfirmed", and the canonical reads say what the pairing now looks
    // like.
    return isVoidWriteResponse(raw)
        ? const VendorProductWriteSuccess<void>(null)
        : const VendorProductWriteUnconfirmed<void>();
  }

  /// A `void` write against one product id: guard the id, call, classify.
  ///
  /// The id-shape guard is the same rule the reads apply, for the same reason and
  /// with a different answer. A malformed id put into a `uuid` parameter comes back
  /// as `22P02` from the type system — raised *before* the function body runs and
  /// therefore before any authorization check — which is neither an authorization
  /// answer nor an outage, and would surface as a database fault offering a retry
  /// that could never succeed.
  ///
  /// So it is decided locally, and answered as [DeniedFailure]: that is precisely
  /// what the backend answers for an id naming no product, an id belonging to
  /// another Vendor and a null id, byte-identically. Adding a malformed id to that
  /// same set keeps this client's write error model to the outcomes that are real,
  /// and says nothing about whether any product exists.
  ///
  /// In the shipped flow this branch is unreachable — a form is only rendered
  /// after the canonical detail read returned a row, and a malformed id can never
  /// return one — so it is defence in depth at the boundary that talks to
  /// PostgREST.
  Future<VendorProductWriteResult<void>> _write(
    String productId,
    Future<Object?> Function() call,
  ) async {
    if (!isProductIdShaped(productId)) {
      return const VendorProductWriteFailure<void>(DeniedFailure());
    }

    final Object? raw;
    try {
      raw = await call();
    } on Object catch (error) {
      return VendorProductWriteFailure<void>(mapVendorProductWriteError(error));
    }

    // `null` is the established shape for a `returns void` function, and it is
    // the only one this build was written against. A body is a response this
    // build cannot read — but a 2xx from either function means the row and its
    // audit row are already committed, so it is emphatically NOT a failure. It
    // becomes "unconfirmed": the caller re-reads the canonical detail, which is
    // the authority on what the product now looks like, and says something
    // truthful rather than claiming a save it cannot vouch for.
    return isVoidWriteResponse(raw)
        ? const VendorProductWriteSuccess<void>(null)
        : const VendorProductWriteUnconfirmed<void>();
  }

  /// Call → parse → classify, with the two failure modes kept apart.
  ///
  /// * A **thrown** call is classified by SQLSTATE. `42501` becomes
  ///   [DeniedFailure] and everything unrecognized becomes
  ///   [UnavailableFailure], so a transport fault can never be presented as an
  ///   authorization denial — nor the reverse. The backend raises the same
  ///   generic `42501` for "not signed in", "not a Vendor Super Admin", "no
  ///   `PRODUCTS_READ`" and "no `RETAILERS_READ`" alike, and this client
  ///   preserves that: one denial, no permission code, no hint at which of the
  ///   four it was.
  /// * An **unparseable body** is [UnavailableFailure]. Unreadable is not
  ///   refused, and it is certainly not an empty catalogue: fabricating one
  ///   would tell a Vendor they have no products when the response simply could
  ///   not be understood — and, on the assignment read, would claim a product
  ///   has never been assigned to anybody.
  Future<ReadResult<T>> _read<T>(
    Future<Object?> Function() call,
    T Function(Object? raw) parse,
  ) async {
    final Object? raw;
    try {
      raw = await call();
    } on Object catch (error) {
      // mapSupabaseError discriminates on SQLSTATE and returns a discriminant;
      // the backend's own message never travels past this line, so no table,
      // column, function or policy name can reach a screen.
      return ReadFailure<T>(mapSupabaseError(error));
    }

    try {
      return ReadSuccess<T>(parse(raw));
    } on VendorProductFormatException {
      return ReadFailure<T>(const UnavailableFailure());
    }
  }
}
