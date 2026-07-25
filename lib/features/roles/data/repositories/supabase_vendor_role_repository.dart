import '../../../../core/errors/failure.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../../../core/result/read_result.dart';
import '../../domain/entities/vendor_role_detail.dart';
import '../../domain/entities/vendor_role_permission.dart';
import '../../domain/entities/vendor_role_summary.dart';
import '../../domain/repositories/vendor_role_repository.dart';
import '../datasources/vendor_role_rpc_data_source.dart';
import '../models/vendor_role_parsers.dart';

/// The real [VendorRoleRepository].
///
/// Each read does exactly three things, in order: call the RPC, parse the body,
/// classify the answer. Each of the three is somebody else's code — the data
/// source, the parser, and `mapSupabaseError` — so this class contains no
/// branching of its own beyond "did it throw?" and the id-shape guards below.
///
/// ## It reproduces no backend authorization logic
///
/// There is no join over `roles`, `permissions` and `role_permissions` here, no
/// member count assembled from `member_roles` and `organization_members`, no
/// Vendor organization id, no role comparison, no permission code and no
/// capability check. Whether this caller may read the catalogue is decided in
/// SQL by `get_vendor_super_admin_context()` and by `has_organization_permission`
/// on **every** call — and the permission companion deliberately requires one
/// permission where the two counting reads require two, a split this client
/// neither knows nor could enforce. Restating any of it would create a second
/// definition free to drift, and only one of the two could be right.
final class SupabaseVendorRoleRepository implements VendorRoleRepository {
  const SupabaseVendorRoleRepository({required VendorRoleRpcDataSource rpc})
    : _rpc = rpc;

  final VendorRoleRpcDataSource _rpc;

  @override
  Future<ReadResult<List<VendorRoleSummary>>> roles() {
    return _read<List<VendorRoleSummary>>(
      _rpc.fetchRoles,
      VendorRoleSummaryParser.parseList,
    );
  }

  @override
  Future<ReadResult<VendorRoleDetail?>> roleDetail(String roleId) {
    // A malformed id names no role. The backend's own answer for an id that
    // names no role is zero rows, so answering `null` here is the *same* answer
    // rather than a new one — and it keeps a mistyped URL from reaching
    // PostgREST as a `22P02` cast error that would surface as a database
    // outage, complete with a retry that could never succeed.
    //
    // It is emphatically not a claim about existence: null is what an unknown
    // id, an id belonging to another table and a malformed id all produce.
    if (!isRoleIdShaped(roleId)) {
      return Future<ReadResult<VendorRoleDetail?>>.value(
        const ReadSuccess<VendorRoleDetail?>(null),
      );
    }
    return _read<VendorRoleDetail?>(
      () => _rpc.fetchDetail(roleId),
      VendorRoleDetailParser.parseSingle,
    );
  }

  @override
  Future<ReadResult<List<VendorRolePermission>>> rolePermissions(
    String roleId,
  ) {
    // Defence in depth rather than the primary guard. A caller reaches this
    // method only after [roleDetail] has returned a row, and a malformed id can
    // never return one — so in the shipped flow this branch is unreachable. It
    // is here so that the *rule* holds at the boundary that talks to PostgREST:
    // no malformed selector is ever put into a `uuid` parameter, whoever calls.
    //
    // The empty list is the backend's own answer for an id that names no role,
    // so this substitutes nothing.
    if (!isRoleIdShaped(roleId)) {
      return Future<ReadResult<List<VendorRolePermission>>>.value(
        const ReadSuccess<List<VendorRolePermission>>(<VendorRolePermission>[]),
      );
    }
    return _read<List<VendorRolePermission>>(
      () => _rpc.fetchPermissions(roleId),
      VendorRolePermissionParser.parseList,
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
  ///   tell a Vendor Super Admin the platform has no role definitions — which
  ///   cannot be true of a caller authorized by holding one of them — when the
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
    } on VendorRoleFormatException {
      return ReadFailure<T>(const UnavailableFailure());
    }
  }
}
