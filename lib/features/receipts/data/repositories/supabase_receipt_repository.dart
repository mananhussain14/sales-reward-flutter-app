import '../../../../core/errors/failure.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../domain/entities/receipt_file.dart';
import '../../domain/entities/receipt_product.dart';
import '../../domain/entities/receipt_shop.dart';
import '../../domain/entities/receipt_submission.dart';
import '../../domain/entities/receipt_submission_outcome.dart';
import '../../domain/repositories/receipt_repository.dart';
import '../../domain/repositories/receipt_result.dart';
import '../datasources/receipt_rpc_data_source.dart';
import '../datasources/submit_receipt_function_client.dart';
import '../models/receipt_parsers.dart';

/// The real [ReceiptRepository].
///
/// Each read does exactly three things, in order: call the RPC, parse the body,
/// classify the answer. Each of the three is somebody else's code — the data
/// source, the parser, and `mapSupabaseError` — so this class contains no
/// branching of its own beyond "did it throw?".
///
/// ## It reproduces no backend authorization logic
///
/// There is no join over profiles, memberships, roles or permissions here, no
/// permission code, no role comparison and no capability check. Whether this
/// caller may list shops, list products, read a submission or create one is
/// decided in SQL by `resolve_retailer_member_organization`, and by the Edge
/// Function under the caller's own token. Restating any of it would create a
/// second definition free to drift, and only one of the two could be right.
///
/// ## It never touches Storage
///
/// `storage.objects` carries RLS with zero policies, so a client-side upload
/// cannot work and an attempt to add one would be the first step toward putting
/// a service-role key on a device. The Edge Function performs the upload and the
/// finalization; this class only posts the bytes to it.
final class SupabaseReceiptRepository implements ReceiptRepository {
  const SupabaseReceiptRepository({
    required ReceiptRpcDataSource rpc,
    required SubmitReceiptFunctionClient functions,
  }) : _rpc = rpc,
       _functions = functions;

  final ReceiptRpcDataSource _rpc;
  final SubmitReceiptFunctionClient _functions;

  @override
  Future<ReceiptResult<List<ReceiptShop>>> assignedShops() {
    return _read<List<ReceiptShop>>(
      _rpc.fetchAssignedShops,
      ReceiptShopParser.parseList,
    );
  }

  @override
  Future<ReceiptResult<List<ReceiptProduct>>> receiptProducts() {
    return _read<List<ReceiptProduct>>(
      _rpc.fetchProducts,
      ReceiptProductParser.parseList,
    );
  }

  @override
  Future<ReceiptResult<List<ReceiptSubmission>>> submissions() {
    return _read<List<ReceiptSubmission>>(
      _rpc.fetchSubmissions,
      ReceiptSubmissionParser.parseList,
    );
  }

  @override
  Future<ReceiptResult<ReceiptSubmission?>> submission(String submissionId) {
    // A malformed id would reach PostgREST as a cast error and come back as an
    // opaque transport failure. Refusing it here keeps the answer honest without
    // ever telling the caller whether a well-formed id exists.
    if (!isUuid(submissionId)) {
      return Future<ReceiptResult<ReceiptSubmission?>>.value(
        const ReceiptReadFailure<ReceiptSubmission?>(InvalidFailure()),
      );
    }
    return _read<ReceiptSubmission?>(
      () => _rpc.fetchSubmission(submissionId),
      ReceiptSubmissionParser.parseSingle,
    );
  }

  @override
  Future<ReceiptSubmissionOutcome> submitReceipt({
    required String shopId,
    required ReceiptFile file,
  }) {
    return _functions.submit(shopId: shopId, file: file);
  }

  /// Call → parse → classify, with the two failure modes kept apart.
  ///
  /// * A **thrown** call is classified by SQLSTATE. `42501` becomes
  ///   [DeniedFailure] and everything unrecognized becomes
  ///   [UnavailableFailure], so a transport fault can never be presented as an
  ///   authorization denial.
  /// * An **unparseable body** is [UnavailableFailure]. Unreadable is not
  ///   refused, and it is certainly not an empty list: fabricating one would
  ///   tell a Sales Staff member they have no assigned shops when the response
  ///   simply could not be understood.
  Future<ReceiptResult<T>> _read<T>(
    Future<Object?> Function() call,
    T Function(Object? raw) parse,
  ) async {
    final Object? raw;
    try {
      raw = await call();
    } on Object catch (error) {
      // mapSupabaseError discriminates on SQLSTATE and returns a discriminant;
      // the backend's own message never travels past this line.
      return ReceiptReadFailure<T>(mapSupabaseError(error));
    }

    try {
      return ReceiptReadSuccess<T>(parse(raw));
    } on ReceiptFormatException {
      return ReceiptReadFailure<T>(const UnavailableFailure());
    }
  }
}
