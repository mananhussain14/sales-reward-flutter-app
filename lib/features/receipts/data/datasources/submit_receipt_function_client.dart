import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/entities/receipt_file.dart';
import '../../domain/entities/receipt_rejection_reason.dart';
import '../../domain/entities/receipt_submission_outcome.dart';
import '../models/receipt_parsers.dart';

/// The deployed Edge Function.
const String submitReceiptFunctionName = 'submit-receipt';

/// The two multipart field names. Fixed literals on both sides — the function
/// declares `const SHOP_ID_FIELD = "shop_id"` and `const FILE_FIELD = "file"`.
const String submitReceiptShopIdField = 'shop_id';
const String submitReceiptFileField = 'file';

/// Supplies the current access token, or null when there is no usable session.
///
/// A function rather than a `SupabaseClient` so this transport can be exercised
/// with no SDK at all, and so the one place that decides "is this session still
/// good enough to send?" is visible and replaceable.
typedef ReceiptAccessTokenProvider = Future<String?> Function();

/// Posts one receipt to the `submit-receipt` Edge Function.
///
/// ## Why a multipart POST rather than `functions.invoke`
///
/// `functions_client` 2.6.4 — the version `supabase_flutter` 2.16.0 installs —
/// serialises its `body` as JSON, a `String`, or raw bytes. It has no multipart
/// mode, so it cannot express "a `shop_id` field beside a file part", which is
/// exactly and only what the deployed function reads. `package:http` can, its
/// default `Client()` resolves to a browser XHR client on web and an IO client
/// elsewhere, and it is already in the dependency graph beneath the SDK.
///
/// ## What is sent, exhaustively
///
/// * `Authorization: Bearer <the caller's own access token>`
/// * `apikey: <the publishable key>` — public by definition; the same value the
///   web bundle embeds and the one the gateway expects.
/// * one `shop_id` field
/// * one `file` part
///
/// Nothing else. No user id, profile id, organization id, Retailer id,
/// membership id, role, permission, status, product id, reward, coin amount,
/// hash, bucket, storage path or submitted-by value — the backend derives every
/// one of those, and a supplied value would be ignored even if it were sent.
/// **No service-role key exists anywhere in this application.**
///
/// ## What is never logged
///
/// This class writes no log line at all. An `Authorization` header, a response
/// body and a transport exception can each carry material that must not reach a
/// device log, and the cheapest way to guarantee none of them does is to log
/// nothing.
///
/// ## The declared content type is deliberately omitted
///
/// The part is sent without a `Content-Type`. The function does not read one —
/// *"The multipart part's own `type` is not read"* — and deriving the stored
/// type from the bytes is the property that makes a `.jpg` full of ZIP bytes
/// impossible to smuggle in. Sending a declared type would add a value that
/// looks authoritative and is not.
final class SubmitReceiptFunctionClient {
  const SubmitReceiptFunctionClient({
    required Uri endpoint,
    required String publishableKey,
    required ReceiptAccessTokenProvider accessToken,
    required http.Client httpClient,
    Duration timeout = const Duration(seconds: 90),
  }) : _endpoint = endpoint,
       _publishableKey = publishableKey,
       _accessToken = accessToken,
       _httpClient = httpClient,
       _timeout = timeout;

  /// Builds the endpoint for a project URL: `<url>/functions/v1/submit-receipt`.
  static Uri endpointFor(String supabaseUrl) {
    return Uri.parse(supabaseUrl).replace(
      pathSegments: <String>['functions', 'v1', submitReceiptFunctionName],
    );
  }

  final Uri _endpoint;
  final String _publishableKey;
  final ReceiptAccessTokenProvider _accessToken;
  final http.Client _httpClient;
  final Duration _timeout;

  /// Sends the receipt and classifies the answer.
  ///
  /// Never throws, and **never retries**. A retry is a decision about whether a
  /// second copy of somebody's receipt might be created, and this layer does not
  /// have the information to make it — see [ReceiptSubmissionUnconfirmed].
  Future<ReceiptSubmissionOutcome> submit({
    required String shopId,
    required ReceiptFile file,
  }) async {
    // A malformed id would reach the function as a clean `invalid-shop`, but
    // stopping here means an obviously wrong value never leaves the device.
    if (!isUuid(shopId)) {
      return const ReceiptSubmissionRefused(ReceiptRejectionReason.invalidShop);
    }

    final String? token;
    try {
      token = await _accessToken();
    } on Object {
      // The session could not be established or refreshed. Unauthenticated, not
      // denied: the caller may well be permitted once they sign in again.
      return const ReceiptSubmissionUnauthenticated();
    }

    if (token == null || token.isEmpty) {
      return const ReceiptSubmissionUnauthenticated();
    }

    final http.MultipartRequest request =
        http.MultipartRequest('POST', _endpoint)
          ..headers['Authorization'] = 'Bearer $token'
          ..headers['apikey'] = _publishableKey
          ..fields[submitReceiptShopIdField] = shopId
          ..files.add(
            http.MultipartFile.fromBytes(
              submitReceiptFileField,
              file.bytes,
              filename: file.fileName,
            ),
          );

    try {
      final http.StreamedResponse streamed = await _httpClient
          .send(request)
          .timeout(_timeout);
      final http.Response response = await http.Response.fromStream(
        streamed,
      ).timeout(_timeout);

      return mapSubmitReceiptResponse(
        statusCode: response.statusCode,
        body: response.body,
      );
    } on TimeoutException {
      // The request was sent. The server may have stored the receipt and simply
      // answered too late, so this is not a failure — it is the absence of an
      // answer, and resending could create a second submission.
      return const ReceiptSubmissionUnconfirmed();
    } on Object {
      // `package:http` wraps socket-level faults as ClientException, on every
      // platform. A connection that drops part-way through a multipart body is
      // indistinguishable from one that drops after the server committed, so
      // the conservative classification is the only correct one.
      return const ReceiptSubmissionUnconfirmed();
    }
  }
}

/// Maps one HTTP answer to an outcome.
///
/// Separated from the transport so the whole mapping table is testable without a
/// socket, and so that adding a status is a change to one pure function.
///
/// | HTTP | `status` | Outcome |
/// | --- | --- | --- |
/// | 200 | `submitted` | [ReceiptSubmissionAccepted] with the parsed id |
/// | 400 | `invalid` | [ReceiptSubmissionRefused] carrying `reason` |
/// | 401 | `unauthenticated` | [ReceiptSubmissionUnauthenticated] |
/// | 403 | `denied` | [ReceiptSubmissionDenied] |
/// | 409 | `duplicate` | [ReceiptSubmissionDuplicate] |
/// | 502 | `upload-failed` | [ReceiptSubmissionUploadFailed] |
/// | 503 | `unavailable` | [ReceiptSubmissionUnavailable] |
/// | anything else | — | [ReceiptSubmissionUnavailable] |
///
/// A `200` this client cannot parse is **not** a success and **not** a plain
/// failure: the receipt probably landed, so it becomes
/// [ReceiptSubmissionUnconfirmed] and the history read decides.
ReceiptSubmissionOutcome mapSubmitReceiptResponse({
  required int statusCode,
  required String body,
}) {
  final Map<String, Object?>? parsed = _decode(body);

  switch (statusCode) {
    case 200:
      final Object? status = parsed?['status'];
      final Object? submissionId = parsed?['submission_id'];
      if (status == 'submitted' &&
          submissionId is String &&
          isUuid(submissionId)) {
        return ReceiptSubmissionAccepted(submissionId);
      }
      // A success code whose body says something else, or nothing usable. The
      // object may well be stored; only the history can settle it.
      return const ReceiptSubmissionUnconfirmed();

    case 400:
      return ReceiptSubmissionRefused(
        ReceiptRejectionReason.fromCode(
          parsed?['reason'] is String ? parsed!['reason']! as String : null,
        ),
      );

    case 401:
      return const ReceiptSubmissionUnauthenticated();

    case 403:
      return const ReceiptSubmissionDenied();

    case 409:
      return const ReceiptSubmissionDuplicate();

    case 502:
      return const ReceiptSubmissionUploadFailed();

    default:
      // 503, 405, and every status this build has no rule for. Operational —
      // never a denial, and never a success.
      return const ReceiptSubmissionUnavailable();
  }
}

/// Decodes a JSON object body, or null when it is not one.
///
/// Never throws and never retains the raw text: an unparseable body is simply
/// absent information.
Map<String, Object?>? _decode(String body) {
  if (body.isEmpty) {
    return null;
  }
  try {
    final Object? decoded = jsonDecode(body);
    if (decoded is Map) {
      return decoded.map<String, Object?>(
        (Object? key, Object? value) =>
            MapEntry<String, Object?>('$key', value),
      );
    }
    return null;
  } on FormatException {
    return null;
  }
}
