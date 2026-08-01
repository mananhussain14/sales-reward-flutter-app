import 'package:supabase_flutter/supabase_flutter.dart';

/// The four authenticated RPCs this client calls directly, named exactly once
/// each.
///
/// The other three of the seven authenticated functions are reached through Edge
/// Functions instead, deliberately:
///
/// * `assert_my_receipt_extraction_access` is the shared authorization
///   predicate; the endpoints call it under the caller's token before doing
///   anything, and a client calling it itself would be asking a question whose
///   answer it must not act on.
/// * `request_receipt_extraction` must be paired with the claim-and-submit
///   sequence that only the server can perform.
/// * `get_my_receipt_extraction` is read through `get-receipt-extraction`
///   because that endpoint also narrows `retry_allowed` against the Edge gate,
///   reaps a stale claim and completes an attempt in flight. Reading the RPC
///   directly would return a `retry_allowed` that had passed through only one
///   of the two gates.
///
/// **No worker RPC appears here or anywhere in this application.** The seven
/// worker functions are executable by the privileged database role alone.
const String listMyReceiptExtractionLineItemsRpc =
    'list_my_receipt_extraction_line_items';
const String confirmReceiptExtractionRpc = 'confirm_receipt_extraction';
const String getMyReceiptConfirmationRpc = 'get_my_receipt_confirmation';

/// The authoritative currency-width lookup.
///
/// One code in, at most one row out. It is **not** a list endpoint: there is no
/// parameterless form, no prefix search and no "all currencies" mode, and this
/// client never reads the seeded table behind it — that table carries RLS with
/// zero policies and no grant to the browser roles, so a direct query would
/// return nothing and making it "work" would mean putting a privileged
/// credential on a device.
const String getReceiptCurrencyMinorUnitRpc = 'get_receipt_currency_minor_unit';

/// The only parameter the two id-only reads accept.
const String extractionSubmissionIdParameter = 'p_submission_id';

/// The only parameter the currency lookup accepts.
const String currencyMinorUnitCodeParameter = 'p_currency_code';

/// Invokes one of the two id-only reads.
///
/// One `String`, and it is a submission id. **No identity travels beside it**:
/// every one of these functions opens by calling
/// `assert_my_receipt_extraction_access`, which derives the caller from
/// `auth.uid()` and resolves the Retailer in SQL. There is no organization id,
/// profile id, membership id, shop id, extraction id, role code or permission
/// code to pass, so there is none to get wrong.
typedef ReceiptExtractionReadInvoker =
    Future<Object?> Function(String submissionId);

/// Invokes `get_receipt_currency_minor_unit(text)`.
///
/// One `String`, and it is an alphabetic currency code. **No identity travels
/// beside it and no receipt is named**: the function resolves the caller through
/// the same permission gate as every other authenticated receipt RPC and reads
/// nothing that belongs to a tenant.
typedef ReceiptCurrencyMinorUnitInvoker =
    Future<Object?> Function(String currencyCode);

/// Invokes `confirm_receipt_extraction(...)`.
///
/// Takes the already-encoded ten-parameter map rather than a domain request, so
/// this boundary has one job and the encoding is pinned by its own test.
typedef ReceiptConfirmationInvoker =
    Future<Object?> Function(Map<String, Object?> params);

/// The production invokers.
///
/// The only place in the application that names these four RPCs and touches the
/// Supabase client for them. Note the call sites: a function name, and one
/// submission id, or one currency code — or, once, the ten values a confirmation
/// is.
ReceiptExtractionReadInvoker supabaseReceiptExtractionLineItemsInvoker(
  SupabaseClient client,
) {
  return (String submissionId) => client.rpc<Object?>(
    listMyReceiptExtractionLineItemsRpc,
    params: <String, Object?>{extractionSubmissionIdParameter: submissionId},
  );
}

ReceiptExtractionReadInvoker supabaseReceiptConfirmationInvoker(
  SupabaseClient client,
) {
  return (String submissionId) => client.rpc<Object?>(
    getMyReceiptConfirmationRpc,
    params: <String, Object?>{extractionSubmissionIdParameter: submissionId},
  );
}

/// The ordinary authenticated client, and no other. The lookup is granted to
/// `authenticated` alone, so a privileged key would buy nothing and cost
/// everything.
ReceiptCurrencyMinorUnitInvoker supabaseReceiptCurrencyMinorUnitInvoker(
  SupabaseClient client,
) {
  return (String currencyCode) => client.rpc<Object?>(
    getReceiptCurrencyMinorUnitRpc,
    params: <String, Object?>{currencyMinorUnitCodeParameter: currencyCode},
  );
}

ReceiptConfirmationInvoker supabaseConfirmReceiptExtractionInvoker(
  SupabaseClient client,
) {
  return (Map<String, Object?> params) =>
      client.rpc<Object?>(confirmReceiptExtractionRpc, params: params);
}

/// Reads and writes the extraction data an authorized Sales Staff member is
/// entitled to, for their own receipts.
///
/// Thin by design: it performs each call and lets exceptions propagate. Turning
/// an exception into a typed problem is the repository's job and turning a body
/// into domain objects is the parser's.
///
/// ## No table is ever read or written here
///
/// There is no query against `receipt_extractions`,
/// `receipt_extraction_line_items`, `receipt_confirmations`,
/// `receipt_extraction_runtime` or `iso_currency_codes` under any spelling — no
/// select, insert, update, upsert or delete of any kind. All five tables have
/// RLS enabled with **zero policies** and every privilege revoked from the
/// browser roles, so a direct read would not merely be poor layering: it would
/// return nothing, and making it "work" would mean putting a privileged
/// credential on a device.
final class ReceiptExtractionRpcDataSource {
  const ReceiptExtractionRpcDataSource({
    required ReceiptExtractionReadInvoker lineItems,
    required ReceiptExtractionReadInvoker confirmation,
    required ReceiptCurrencyMinorUnitInvoker currencyMinorUnit,
    required ReceiptConfirmationInvoker confirm,
  }) : _lineItems = lineItems,
       _confirmation = confirmation,
       _currencyMinorUnit = currencyMinorUnit,
       _confirm = confirm;

  /// Builds the data source against a live client.
  factory ReceiptExtractionRpcDataSource.forClient(SupabaseClient client) {
    return ReceiptExtractionRpcDataSource(
      lineItems: supabaseReceiptExtractionLineItemsInvoker(client),
      confirmation: supabaseReceiptConfirmationInvoker(client),
      currencyMinorUnit: supabaseReceiptCurrencyMinorUnitInvoker(client),
      confirm: supabaseConfirmReceiptExtractionInvoker(client),
    );
  }

  final ReceiptExtractionReadInvoker _lineItems;
  final ReceiptExtractionReadInvoker _confirmation;
  final ReceiptCurrencyMinorUnitInvoker _currencyMinorUnit;
  final ReceiptConfirmationInvoker _confirm;

  Future<Object?> fetchLineItems(String submissionId) =>
      _lineItems(submissionId);

  Future<Object?> fetchConfirmation(String submissionId) =>
      _confirmation(submissionId);

  /// One currency's decimal width. A pure read, and safe to call again.
  Future<Object?> fetchCurrencyMinorUnit(String currencyCode) =>
      _currencyMinorUnit(currencyCode);

  /// One confirmation, in one round trip. Never called twice for one submission
  /// of the form.
  Future<Object?> confirm(Map<String, Object?> params) => _confirm(params);
}
