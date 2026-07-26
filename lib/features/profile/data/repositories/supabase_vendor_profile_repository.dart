import '../../../../core/errors/failure.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../../../core/result/read_result.dart';
import '../../domain/entities/vendor_administrator_profile.dart';
import '../../domain/repositories/vendor_profile_repository.dart';
import '../datasources/vendor_profile_rpc_data_source.dart';
import '../models/vendor_profile_parser.dart';

/// The real [VendorProfileRepository].
///
/// The read does exactly three things, in order: call the RPC, parse the body,
/// classify the answer. Each of the three is somebody else's code — the data
/// source, the parser, and `mapSupabaseError` — so this class contains no
/// branching of its own beyond "did it throw?".
///
/// ## It reproduces no backend authorization logic
///
/// There is no Vendor organization id here, no membership lookup, no permission
/// check and no tenant predicate. Whether this caller may read their own profile
/// is decided in SQL by `get_vendor_super_admin_context()` **and**
/// `has_organization_permission(..., 'RBAC_READ')` — a pair of gates deliberately
/// narrower than the underlying tables' own RLS policies, which are `OR`s.
/// Restating any of it here would create a second definition free to drift, and
/// only one of the two could be right.
///
/// ## It composes nothing either
///
/// No name is assembled from parts, no role is filtered by status, no array is
/// re-ordered and no organization name is fetched. The two fields arrive already
/// composed and already ordered, which is what keeps their definitions in one
/// place for both clients.
final class SupabaseVendorProfileRepository implements VendorProfileRepository {
  const SupabaseVendorProfileRepository({
    required VendorProfileRpcDataSource rpc,
  }) : _rpc = rpc;

  final VendorProfileRpcDataSource _rpc;

  /// Call → parse → classify, with the two failure modes kept apart.
  ///
  /// * A **thrown** call is classified by SQLSTATE. `42501` becomes
  ///   [DeniedFailure] and everything unrecognized becomes [UnavailableFailure],
  ///   so a transport fault can never be presented as an authorization denial —
  ///   nor the reverse. The backend raises the same generic `42501` for "not
  ///   signed in", "not a Vendor Super Admin", "your membership is suspended",
  ///   "your organization is suspended" and "your role no longer holds
  ///   RBAC_READ" alike, and this client preserves that: one denial, no
  ///   permission code, no hint at which of the gates it was.
  /// * An **unparseable body** is [UnavailableFailure]. Unreadable is not
  ///   refused, and it is certainly not a blank profile: fabricating one would
  ///   put a placeholder identity on a screen whose entire subject is who the
  ///   signed-in person is.
  ///
  /// Neither path can produce a partially populated profile. The parser reads
  /// both fields before constructing anything, and the success branch below emits
  /// the whole profile or none of it.
  @override
  Future<ReadResult<VendorAdministratorProfile>> administratorProfile() async {
    final Object? raw;
    try {
      raw = await _rpc.fetchAdministratorProfile();
    } on Object catch (error) {
      // mapSupabaseError discriminates on SQLSTATE and returns a discriminant;
      // the backend's own message never travels past this line, so no table,
      // column, function or policy name can reach a screen.
      return ReadFailure<VendorAdministratorProfile>(mapSupabaseError(error));
    }

    try {
      return ReadSuccess<VendorAdministratorProfile>(
        VendorProfileParser.parse(raw),
      );
    } on VendorProfileFormatException {
      return const ReadFailure<VendorAdministratorProfile>(
        UnavailableFailure(),
      );
    }
  }
}
