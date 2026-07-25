import '../../../../core/errors/failure.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../../../core/result/read_result.dart';
import '../../domain/entities/vendor_product_assigned_retailer.dart';
import '../../domain/entities/vendor_product_detail.dart';
import '../../domain/entities/vendor_product_summary.dart';
import '../../domain/repositories/vendor_product_repository.dart';
import '../datasources/vendor_product_rpc_data_source.dart';
import '../models/vendor_product_parsers.dart';

/// The real [VendorProductRepository].
///
/// Each read does exactly three things, in order: call the RPC, parse the body,
/// classify the answer. Each of the three is somebody else's code — the data
/// source, the parser, and `mapSupabaseError` — so this class contains no
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
final class SupabaseVendorProductRepository implements VendorProductRepository {
  const SupabaseVendorProductRepository({
    required VendorProductRpcDataSource rpc,
  }) : _rpc = rpc;

  final VendorProductRpcDataSource _rpc;

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
