import '../../../../core/errors/failure.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../domain/entities/vendor_retailer_detail.dart';
import '../../domain/entities/vendor_retailer_shop.dart';
import '../../domain/entities/vendor_retailer_summary.dart';
import '../../domain/repositories/vendor_retailer_repository.dart';
import '../../domain/repositories/vendor_retailer_result.dart';
import '../datasources/vendor_retailer_rpc_data_source.dart';
import '../models/vendor_retailer_parsers.dart';

/// The real [VendorRetailerRepository].
///
/// Each read does exactly three things, in order: call the RPC, parse the body,
/// classify the answer. Each of the three is somebody else's code — the data
/// source, the parser, and `mapSupabaseError` — so this class contains no
/// branching of its own beyond "did it throw?" and the one id-shape guard below.
///
/// ## It reproduces no backend authorization logic
///
/// There is no join over `vendor_retailers`, `organizations` or `retailer_shops`
/// here, no Vendor organization id, no role comparison, no permission code and
/// no capability check. Whether this caller may list Retailers, open one, or
/// read its shops is decided in SQL by `get_vendor_super_admin_context()` and
/// `has_organization_permission(…, 'RETAILERS_READ')`, on **every** call.
/// Restating any of it would create a second definition free to drift, and only
/// one of the two could be right.
///
/// The web assembles the same directory from three table reads and a TypeScript
/// join. That is exactly what this class does not do: the whole point of the
/// deployed functions is that a second client should not have to reimplement the
/// tenant scoping that join carries.
final class SupabaseVendorRetailerRepository
    implements VendorRetailerRepository {
  const SupabaseVendorRetailerRepository({
    required VendorRetailerRpcDataSource rpc,
  }) : _rpc = rpc;

  final VendorRetailerRpcDataSource _rpc;

  @override
  Future<VendorRetailerResult<List<VendorRetailerSummary>>> retailers() {
    return _read<List<VendorRetailerSummary>>(
      _rpc.fetchRetailers,
      VendorRetailerSummaryParser.parseList,
    );
  }

  @override
  Future<VendorRetailerResult<VendorRetailerDetail?>> retailerDetail(
    String relationshipId,
  ) {
    // A malformed id names no row. The backend's own answer for an id that names
    // no row is zero rows, so answering `null` here is the *same* answer rather
    // than a new one — and it keeps a mistyped URL from reaching PostgREST as a
    // `22P02` cast error that would surface as a database outage.
    //
    // It is emphatically not a claim about existence: null is what a nonexistent
    // id, another Vendor's id and a malformed id all produce.
    if (!isRelationshipIdShaped(relationshipId)) {
      return Future<VendorRetailerResult<VendorRetailerDetail?>>.value(
        const VendorRetailerReadSuccess<VendorRetailerDetail?>(null),
      );
    }
    return _read<VendorRetailerDetail?>(
      () => _rpc.fetchDetail(relationshipId),
      VendorRetailerDetailParser.parseSingle,
    );
  }

  @override
  Future<VendorRetailerResult<List<VendorRetailerShop>>> retailerShops(
    String relationshipId,
  ) {
    // Unreachable in the shipped flow — the shop read runs only after a detail
    // row came back for this same id, which proves it was well formed. Guarded
    // anyway, and deliberately **not** as an empty list: an empty list here
    // means "this Retailer has no shops", and a client-side refusal is not that.
    if (!isRelationshipIdShaped(relationshipId)) {
      return Future<VendorRetailerResult<List<VendorRetailerShop>>>.value(
        const VendorRetailerReadFailure<List<VendorRetailerShop>>(
          InvalidFailure(),
        ),
      );
    }
    return _read<List<VendorRetailerShop>>(
      () => _rpc.fetchShops(relationshipId),
      VendorRetailerShopParser.parseList,
    );
  }

  /// Call → parse → classify, with the two failure modes kept apart.
  ///
  /// * A **thrown** call is classified by SQLSTATE. `42501` becomes
  ///   [DeniedFailure] and everything unrecognized becomes
  ///   [UnavailableFailure], so a transport fault can never be presented as an
  ///   authorization denial — nor the reverse.
  /// * An **unparseable body** is [UnavailableFailure]. Unreadable is not
  ///   refused, and it is certainly not an empty list: fabricating one would
  ///   tell a Vendor they manage no Retailers when the response simply could not
  ///   be understood.
  Future<VendorRetailerResult<T>> _read<T>(
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
      return VendorRetailerReadFailure<T>(mapSupabaseError(error));
    }

    try {
      return VendorRetailerReadSuccess<T>(parse(raw));
    } on VendorRetailerFormatException {
      return VendorRetailerReadFailure<T>(const UnavailableFailure());
    }
  }
}
