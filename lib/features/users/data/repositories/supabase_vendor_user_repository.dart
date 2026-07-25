import '../../../../core/errors/failure.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../../../core/result/read_result.dart';
import '../../domain/entities/vendor_user_detail.dart';
import '../../domain/entities/vendor_user_summary.dart';
import '../../domain/repositories/vendor_user_repository.dart';
import '../datasources/vendor_user_rpc_data_source.dart';
import '../models/vendor_user_parsers.dart';

/// The real [VendorUserRepository].
///
/// Each read does exactly three things, in order: call the RPC, parse the body,
/// classify the answer. Each of the three is somebody else's code — the data
/// source, the parser, and `mapSupabaseError` — so this class contains no
/// branching of its own beyond "did it throw?" and the one id-shape guard below.
///
/// ## It reproduces no backend authorization logic
///
/// There is no join over `organization_members`, `profiles`, `member_roles` or
/// `roles` here, no Vendor organization id, no role comparison, no permission
/// code and no capability check. Whether this caller may list Vendor users or
/// open one is decided in SQL by `get_vendor_super_admin_context()` and by
/// `has_organization_permission` for **both** `ORGANIZATION_MEMBERS_READ` and
/// `RBAC_READ`, on **every** call. Restating any of it would create a second
/// definition free to drift, and only one of the two could be right.
///
/// The web assembles the same directory from four table reads and a TypeScript
/// join. That is exactly what this class does not do: the whole point of the
/// deployed functions is that a second client should not have to reimplement the
/// tenant scoping and the ACTIVE-role filter that join carries.
final class SupabaseVendorUserRepository implements VendorUserRepository {
  const SupabaseVendorUserRepository({required VendorUserRpcDataSource rpc})
    : _rpc = rpc;

  final VendorUserRpcDataSource _rpc;

  @override
  Future<ReadResult<List<VendorUserSummary>>> users() {
    return _read<List<VendorUserSummary>>(
      _rpc.fetchUsers,
      VendorUserSummaryParser.parseList,
    );
  }

  @override
  Future<ReadResult<VendorUserDetail?>> userDetail(String membershipId) {
    // A malformed id names no row. The backend's own answer for an id that names
    // no row is zero rows, so answering `null` here is the *same* answer rather
    // than a new one — and it keeps a mistyped URL from reaching PostgREST as a
    // `22P02` cast error that would surface as a database outage.
    //
    // It is emphatically not a claim about existence: null is what a nonexistent
    // id, another Vendor's id, a Retailer-owned membership id and a malformed id
    // all produce.
    if (!isMembershipIdShaped(membershipId)) {
      return Future<ReadResult<VendorUserDetail?>>.value(
        const ReadSuccess<VendorUserDetail?>(null),
      );
    }
    return _read<VendorUserDetail?>(
      () => _rpc.fetchDetail(membershipId),
      VendorUserDetailParser.parseSingle,
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
  ///   tell a Vendor Super Admin their organization has no users — including
  ///   themselves, which the authorization chain guarantees is false — when the
  ///   response simply could not be understood.
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
    } on VendorUserFormatException {
      return ReadFailure<T>(const UnavailableFailure());
    }
  }
}
