import '../../../../core/errors/retailer_read_problem.dart';
import '../../../../core/parsing/rpc_row.dart';
import '../../domain/repositories/retailer_shop_repository.dart';
import '../datasources/retailer_shop_rpc_data_source.dart';
import '../models/retailer_shop_parser.dart';

/// The real [RetailerShopRepository].
///
/// Call, parse, classify. Each is somebody else's code — the data source, the
/// parser, and [classifyRetailerReadError] — so this class contains no branching
/// of its own beyond "did it throw?".
///
/// ## It reproduces no backend authorization logic
///
/// There is no Retailer organization id here, no membership lookup, no role
/// check and no permission check. Whether this caller may read the estate is
/// decided in SQL by `resolve_retailer_owner_organization('RETAILER_SHOPS_READ')`
/// — and note that a caller holding `RETAILER_PORTAL_READ` but not
/// `RETAILER_SHOPS_READ` resolves NULL here and receives no shops even though the
/// Overview answers them. Restating any of that in Dart would create a second
/// definition free to drift, and only one of the two could be right.
///
/// ## An empty list is never converted into a denial
///
/// This function does not raise on refusal; it returns nothing. So there is no
/// branch below that turns emptiness into [RetailerReadProblem.denied], and none
/// that inspects the caller's role to guess which kind of empty this was. The
/// ambiguity is the contract's, and it is preserved rather than resolved — see
/// [RetailerShopRepository.shops].
final class SupabaseRetailerShopRepository implements RetailerShopRepository {
  const SupabaseRetailerShopRepository({
    required RetailerShopRpcDataSource rpc,
    Duration timeout = retailerReadTimeout,
  }) : _rpc = rpc,
       _timeout = timeout;

  final RetailerShopRpcDataSource _rpc;
  final Duration _timeout;

  @override
  Future<RetailerShopsResult> shops() async {
    final Object? raw;
    try {
      raw = await _rpc.fetchShops().timeout(_timeout);
    } on Object catch (error) {
      return RetailerShopsFailed(classifyRetailerReadError(error));
    }

    try {
      return RetailerShopsLoaded(RetailerShopParser.parse(raw));
    } on RpcFormatException {
      // The exception's own `reason` is developer-facing and stays here. Only
      // the discriminant travels onward — no table, column, function or policy
      // name can reach a screen through this line.
      return const RetailerShopsFailed(RetailerReadProblem.malformed);
    }
  }
}
