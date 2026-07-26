import '../../../../core/errors/failure.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../../../core/result/read_result.dart';
import '../../domain/entities/vendor_dashboard_summary.dart';
import '../../domain/repositories/vendor_dashboard_repository.dart';
import '../datasources/vendor_dashboard_rpc_data_source.dart';
import '../models/vendor_dashboard_summary_parser.dart';

/// The real [VendorDashboardRepository].
///
/// The read does exactly three things, in order: call the RPC, parse the body,
/// classify the answer. Each of the three is somebody else's code — the data
/// source, the parser, and `mapSupabaseError` — so this class contains no
/// branching of its own beyond "did it throw?".
///
/// ## It reproduces no backend authorization logic
///
/// There is no Vendor organization id here, no membership lookup, no permission
/// check and no tenant predicate. Whether this caller may read the summary is
/// decided in SQL by `get_vendor_super_admin_context()` **and**
/// `has_organization_permission` for all three of the read permissions the four
/// counted relations already require — a pair of gates deliberately narrower than
/// those tables' own RLS policies, which are `OR`s. Restating any of it here would
/// create a second definition free to drift, and only one of the two could be
/// right.
///
/// ## It reproduces no metric logic either
///
/// No count is derived, summed, filtered or combined on this side of the wire.
/// The four figures arrive already computed, which is what keeps their
/// definitions — including which two of them are deployment-wide catalogue
/// figures rather than this Vendor's — in one place for both clients.
final class SupabaseVendorDashboardRepository
    implements VendorDashboardRepository {
  const SupabaseVendorDashboardRepository({
    required VendorDashboardRpcDataSource rpc,
  }) : _rpc = rpc;

  final VendorDashboardRpcDataSource _rpc;

  /// Call → parse → classify, with the two failure modes kept apart.
  ///
  /// * A **thrown** call is classified by SQLSTATE. `42501` becomes
  ///   [DeniedFailure] and everything unrecognized becomes [UnavailableFailure],
  ///   so a transport fault can never be presented as an authorization denial —
  ///   nor the reverse. The backend raises the same generic `42501` for "not
  ///   signed in", "not a Vendor Super Admin", "your membership is suspended" and
  ///   "this Vendor's role no longer holds one of the three read permissions"
  ///   alike, and this client preserves that: one denial, no permission code, no
  ///   hint at which of them it was.
  /// * An **unparseable body** is [UnavailableFailure]. Unreadable is not
  ///   refused, and it is certainly not a summary of zeros: fabricating one would
  ///   tell a Vendor they have no members and no recorded history when the
  ///   response simply could not be understood.
  ///
  /// Neither path can produce a partially populated summary. The parser reads all
  /// four counts before constructing anything, and the success branch below emits
  /// the whole snapshot or none of it.
  @override
  Future<ReadResult<VendorDashboardSummary>> summary() async {
    final Object? raw;
    try {
      raw = await _rpc.fetchSummary();
    } on Object catch (error) {
      // mapSupabaseError discriminates on SQLSTATE and returns a discriminant;
      // the backend's own message never travels past this line, so no table,
      // column, function or policy name can reach a screen.
      return ReadFailure<VendorDashboardSummary>(mapSupabaseError(error));
    }

    try {
      return ReadSuccess<VendorDashboardSummary>(
        VendorDashboardSummaryParser.parse(raw),
      );
    } on VendorDashboardFormatException {
      return const ReadFailure<VendorDashboardSummary>(UnavailableFailure());
    }
  }
}
