import 'package:supabase_flutter/supabase_flutter.dart';

/// The four receipt RPCs, named exactly once each.
const String listMyAssignedReceiptShopsRpc = 'list_my_assigned_receipt_shops';
const String listMyReceiptProductsRpc = 'list_my_receipt_products';
const String listMyReceiptSubmissionsRpc = 'list_my_receipt_submissions';
const String getMyReceiptSubmissionRpc = 'get_my_receipt_submission';

/// The **only** parameter any of them accepts.
const String submissionIdParameter = 'p_submission_id';

/// Invokes a zero-argument receipt read and returns its raw body.
///
/// ## The signature is the security property
///
/// Three of the four RPCs take no arguments at all, and this typedef takes none
/// either. That is not a convenience — it makes a Retailer id, membership id,
/// profile id, role code, permission code, email or token **impossible to
/// express** at this boundary. There is no argument to pass, so there is no
/// argument to get wrong, and no future edit can quietly add one without
/// changing this type.
typedef ReceiptListInvoker = Future<Object?> Function();

/// Invokes `get_my_receipt_submission(uuid)`.
///
/// One `String`, and it is a submission id. No identity travels beside it: the
/// function derives the caller from `auth.uid()` and filters on both
/// `submitted_by_profile_id` and the resolved Retailer, neither of which this
/// client can name.
typedef ReceiptSubmissionInvoker =
    Future<Object?> Function(String submissionId);

/// The production invokers.
///
/// The only place in the application that names a receipt RPC and touches the
/// Supabase client for it. Note the call sites: a function name, and — once — a
/// single id.
ReceiptListInvoker supabaseAssignedReceiptShopsInvoker(SupabaseClient client) {
  return () => client.rpc<Object?>(listMyAssignedReceiptShopsRpc);
}

ReceiptListInvoker supabaseReceiptProductsInvoker(SupabaseClient client) {
  return () => client.rpc<Object?>(listMyReceiptProductsRpc);
}

ReceiptListInvoker supabaseReceiptSubmissionsInvoker(SupabaseClient client) {
  return () => client.rpc<Object?>(listMyReceiptSubmissionsRpc);
}

ReceiptSubmissionInvoker supabaseReceiptSubmissionInvoker(
  SupabaseClient client,
) {
  return (String submissionId) => client.rpc<Object?>(
    getMyReceiptSubmissionRpc,
    params: <String, Object?>{submissionIdParameter: submissionId},
  );
}

/// Reads the receipt data a Sales Staff member is entitled to.
///
/// Thin by design: it performs each call and lets exceptions propagate. Turning
/// an exception into a `Failure` is the repository's job and turning a body into
/// domain objects is the parser's, so each of the three has one reason to
/// change.
final class ReceiptRpcDataSource {
  const ReceiptRpcDataSource({
    required ReceiptListInvoker assignedShops,
    required ReceiptListInvoker products,
    required ReceiptListInvoker submissions,
    required ReceiptSubmissionInvoker submission,
  }) : _assignedShops = assignedShops,
       _products = products,
       _submissions = submissions,
       _submission = submission;

  /// Builds the data source against a live client.
  factory ReceiptRpcDataSource.forClient(SupabaseClient client) {
    return ReceiptRpcDataSource(
      assignedShops: supabaseAssignedReceiptShopsInvoker(client),
      products: supabaseReceiptProductsInvoker(client),
      submissions: supabaseReceiptSubmissionsInvoker(client),
      submission: supabaseReceiptSubmissionInvoker(client),
    );
  }

  final ReceiptListInvoker _assignedShops;
  final ReceiptListInvoker _products;
  final ReceiptListInvoker _submissions;
  final ReceiptSubmissionInvoker _submission;

  Future<Object?> fetchAssignedShops() => _assignedShops();

  Future<Object?> fetchProducts() => _products();

  Future<Object?> fetchSubmissions() => _submissions();

  Future<Object?> fetchSubmission(String submissionId) =>
      _submission(submissionId);
}
