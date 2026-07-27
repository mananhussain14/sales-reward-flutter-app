import '../../../../core/errors/retailer_read_problem.dart';
import '../../../../core/parsing/rpc_row.dart';
import '../../domain/repositories/retailer_product_repository.dart';
import '../datasources/retailer_product_rpc_data_source.dart';
import '../models/retailer_assigned_product_parser.dart';

/// The real [RetailerProductRepository].
///
/// Call, parse, classify. Each is somebody else's code, so this class contains
/// no branching of its own beyond "did it throw?".
///
/// ## It reproduces no backend authorization logic
///
/// There is no Retailer organization id here, no Vendor id, no membership
/// lookup, no role check and no permission check. Whether this caller may read
/// the assigned catalogue is decided in SQL by
/// `resolve_retailer_member_organization('RETAILER_PRODUCTS_READ')`, which both
/// Retailer roles satisfy and Sales Staff do not.
///
/// ## It reproduces no assignment logic either
///
/// The `a.status = 'ACTIVE' and vp.status = 'ACTIVE'` filter is the backend's
/// and is not restated here. That matters more than it looks: if this client
/// filtered on the returned `assignment_status` as well, the two definitions
/// could drift, and the client's copy of the rule would be the one nobody
/// noticed was wrong.
///
/// **A denial is never an empty catalogue.** `42501` becomes
/// [RetailerReadProblem.denied]; "you may not read this" and "no Vendor assigns
/// you anything" are opposite claims.
final class SupabaseRetailerProductRepository
    implements RetailerProductRepository {
  const SupabaseRetailerProductRepository({
    required RetailerProductRpcDataSource rpc,
    Duration timeout = retailerReadTimeout,
  }) : _rpc = rpc,
       _timeout = timeout;

  final RetailerProductRpcDataSource _rpc;
  final Duration _timeout;

  @override
  Future<RetailerProductsResult> products() async {
    final Object? raw;
    try {
      raw = await _rpc.fetchProducts().timeout(_timeout);
    } on Object catch (error) {
      return RetailerProductsFailed(classifyRetailerReadError(error));
    }

    try {
      return RetailerProductsLoaded(RetailerAssignedProductParser.parse(raw));
    } on RpcFormatException {
      // The exception's own `reason` is developer-facing and stays here. Only
      // the discriminant travels onward.
      return const RetailerProductsFailed(RetailerReadProblem.malformed);
    }
  }
}
