import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/receipt_extraction_problem.dart';
import '../../domain/repositories/receipt_extraction_result.dart';

/// The three receipt-extraction Edge Functions, named exactly once each.
const String requestReceiptExtractionFunction = 'request-receipt-extraction';
const String getReceiptExtractionFunction = 'get-receipt-extraction';
const String receiptImagePreviewFunction = 'receipt-image-preview';

/// The **only** key any of their request bodies may carry.
///
/// > *"One allowed key, and the allowlist is the validation. A body may carry
/// > `submission_id` and nothing else. An unknown key is a 400, not an ignored
/// > extra."*
///
/// So there is one constant here and no second one. No fixture key, outcome,
/// provider, mode, organization id, profile id, membership id, shop id,
/// extraction id, claim token, storage coordinate, file hash, entry mode,
/// changed-fields list or duplicate signal can be expressed at this boundary,
/// because there is no name for one.
const String extractionSubmissionIdField = 'submission_id';

/// Builds the one-key body all three endpoints share.
Map<String, Object?> receiptExtractionRequestBody(String submissionId) {
  return <String, Object?>{extractionSubmissionIdField: submissionId};
}

/// Everything one Edge Function reply carries, before anything has been made of
/// it.
///
/// A data-layer type, mirroring the staff-invitation transport: it hands the
/// repository the two facts it needs — what status came back and what body came
/// with it — without the repository ever touching an SDK exception.
///
/// [body] is deliberately `Object?` rather than a map: a body that is not a JSON
/// object is a real possibility (a gateway error page, an empty reply) and must
/// be refused by the mapper rather than crash the transport. It never leaves the
/// data layer, and no part of it is ever rendered.
final class ReceiptExtractionReply {
  const ReceiptExtractionReply({required this.status, required this.body});

  /// The HTTP status. The endpoints pair it one-to-one with the body's own
  /// `status` token, and the mapper below reads the HTTP status first.
  final int status;

  /// The decoded body, whatever shape it arrived in.
  final Object? body;
}

/// Posts one body to one of the three functions and returns the reply.
///
/// The function name travels as an argument rather than being baked into three
/// typedefs, because all three share one request shape, one response vocabulary
/// and one mapper. Three typedefs would be three copies of the same signature.
typedef ReceiptExtractionInvoker =
    Future<ReceiptExtractionReply> Function(
      String functionName,
      Map<String, Object?> body,
    );

/// The production invoker.
///
/// ## Why `functions.invoke` rather than a hand-built request
///
/// Because the one thing these calls must get right is *whose* session they run
/// under. The SDK's functions client carries the publishable key and keeps its
/// `Authorization` header in step with the signed-in user's access token, so the
/// request arrives as the caller — which is what makes `auth.uid()` mean
/// something inside `assert_my_receipt_extraction_access`, resolves the Retailer
/// in PostgreSQL, and restricts every one of these endpoints to the person who
/// submitted the receipt.
///
/// (The receipt *upload* builds its own request only because it needs multipart,
/// which this client cannot express. A one-key JSON body needs no such
/// workaround.)
///
/// **No key of any other kind is attached.** The privileged credential these
/// functions use internally lives only in their own environment and appears
/// nowhere in this application.
///
/// ## Every reply becomes a value, including the refusals
///
/// `invoke` throws `FunctionException` for any non-2xx — and five of this
/// contract's statuses are non-2xx by design (`400`, `401`, `403`, `404`,
/// `503`). Those are *answers*, not faults, so the exception is unwrapped back
/// into a [ReceiptExtractionReply] and its body is classified exactly like a
/// 200's. Only a fault that produced no reply at all is allowed to propagate,
/// which is what the repository classifies as transport.
///
/// Nothing here is logged. A reply or an exception can quote a body, and the
/// preview reply carries a live capability.
ReceiptExtractionInvoker supabaseReceiptExtractionInvoker(
  SupabaseClient client,
) {
  return (String functionName, Map<String, Object?> body) async {
    try {
      final FunctionResponse response = await client.functions.invoke(
        functionName,
        body: body,
      );
      return ReceiptExtractionReply(
        status: response.status,
        body: response.data,
      );
    } on FunctionException catch (error) {
      // A refusal the contract defines, or a gateway status with no contract
      // body. Both are replies; the mapper decides which.
      return ReceiptExtractionReply(status: error.status, body: error.details);
    }
  };
}

/// The three Edge Function calls, and no fourth.
///
/// Thin by design: it performs the call and lets a genuine transport fault
/// propagate. Classifying a fault is the repository's job and turning a body
/// into domain values is the parser's, so each of the three has one reason to
/// change.
///
/// **No worker endpoint and no storage call.** There is no claim, no operation
/// registration, no success or failure recording, no worker-state read, no
/// object reference lookup and no reaper here — those seven RPCs are granted to
/// the privileged database role alone, and this application holds no credential
/// that could reach them.
final class ReceiptExtractionFunctionClient {
  const ReceiptExtractionFunctionClient({
    required ReceiptExtractionInvoker invoke,
  }) : _invoke = invoke;

  /// Builds the client against a live Supabase client.
  factory ReceiptExtractionFunctionClient.forClient(SupabaseClient client) {
    return ReceiptExtractionFunctionClient(
      invoke: supabaseReceiptExtractionInvoker(client),
    );
  }

  final ReceiptExtractionInvoker _invoke;

  /// `request-receipt-extraction`. **Mutating**, and called exactly once per
  /// deliberate act — never twice for one tap.
  Future<ReceiptExtractionReply> requestExtraction(String submissionId) =>
      _invoke(
        requestReceiptExtractionFunction,
        receiptExtractionRequestBody(submissionId),
      );

  /// `get-receipt-extraction`. Reads, and completes an attempt that is in
  /// flight. One call, one poll — there is no loop here.
  Future<ReceiptExtractionReply> getExtraction(String submissionId) => _invoke(
    getReceiptExtractionFunction,
    receiptExtractionRequestBody(submissionId),
  );

  /// `receipt-image-preview`. Returns a capability whose lifetime is measured
  /// in seconds; nothing in this layer retains it.
  Future<ReceiptExtractionReply> imagePreview(String submissionId) => _invoke(
    receiptImagePreviewFunction,
    receiptExtractionRequestBody(submissionId),
  );
}

/// Maps one Edge Function reply to a body or a typed problem.
///
/// Separated from the transport so the whole mapping table is testable without a
/// socket, and so that adding a status is a change to one pure function.
///
/// | HTTP | body `status` | Result |
/// | --- | --- | --- |
/// | 200 | `ok` | the body |
/// | 200 | anything else | malformed |
/// | 400 / 405 | `invalid` | invalid, carrying `reason` |
/// | 401 | `unauthenticated` | unauthenticated |
/// | 403 | `denied` | forbidden |
/// | 404 | `not-found` | not-found |
/// | 503 | `unavailable` | service unavailable |
/// | anything else | — | unknown |
///
/// The HTTP status is read first because it is the one thing present on every
/// reply, including a gateway error that carries no contract body at all. The
/// body's own `status` is then used to confirm a `200` really is an `ok` — a
/// success code whose body says something else is not a success, and inventing
/// one from it would be the worst available guess.
///
/// **Nothing from the body is retained on a failure path.** No message, no
/// reason string beyond the closed token, no id, no URL.
ReceiptExtractionResult<Map<String, Object?>> mapReceiptExtractionReply({
  required int status,
  required Object? body,
}) {
  final Map<String, Object?>? parsed = _asObject(body);

  switch (status) {
    case 200:
      if (parsed == null || parsed['status'] != 'ok') {
        return const ReceiptExtractionFailed<Map<String, Object?>>(
          ExtractionMalformedResponseProblem(),
        );
      }
      return ReceiptExtractionSuccess<Map<String, Object?>>(parsed);

    case 400:
    case 405:
      final Object? reason = parsed?['reason'];
      return ReceiptExtractionFailed<Map<String, Object?>>(
        ExtractionInvalidRequestProblem(
          ExtractionInvalidReason.fromCode(reason is String ? reason : null),
        ),
      );

    case 401:
      return const ReceiptExtractionFailed<Map<String, Object?>>(
        ExtractionUnauthenticatedProblem(),
      );

    case 403:
      return const ReceiptExtractionFailed<Map<String, Object?>>(
        ExtractionForbiddenProblem(),
      );

    case 404:
      return const ReceiptExtractionFailed<Map<String, Object?>>(
        ExtractionNotFoundProblem(),
      );

    case 503:
      return const ReceiptExtractionFailed<Map<String, Object?>>(
        ExtractionServiceUnavailableProblem(),
      );

    default:
      // A status this build has no rule for. Fails closed: never a success,
      // and never a denial.
      return const ReceiptExtractionFailed<Map<String, Object?>>(
        ExtractionUnknownProblem(),
      );
  }
}

/// The body as a string-keyed map, or null when it is not a JSON object.
///
/// Never throws and never retains the raw value: an unusable body is simply
/// absent information.
Map<String, Object?>? _asObject(Object? body) {
  if (body is Map) {
    return body.map<String, Object?>(
      (Object? key, Object? value) => MapEntry<String, Object?>('$key', value),
    );
  }
  return null;
}
