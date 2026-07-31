import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/sql_state.dart';
import '../../domain/entities/receipt_confirmation.dart';
import '../../domain/entities/receipt_confirmation_input.dart';
import '../../domain/entities/receipt_confirmation_result.dart';
import '../../domain/entities/receipt_extraction.dart';
import '../../domain/entities/receipt_extraction_line_item.dart';
import '../../domain/entities/receipt_extraction_problem.dart';
import '../../domain/entities/receipt_extraction_request_result.dart';
import '../../domain/entities/receipt_image_preview.dart';
import '../../domain/repositories/receipt_extraction_repository.dart';
import '../../domain/repositories/receipt_extraction_result.dart';
import '../datasources/receipt_extraction_function_client.dart';
import '../datasources/receipt_extraction_rpc_data_source.dart';
import '../models/receipt_confirmation_request_body.dart';
import '../models/receipt_extraction_parsers.dart';
import '../models/receipt_parsers.dart';

/// The real [ReceiptExtractionRepository].
///
/// Each call does exactly three things, in order: make the call, classify the
/// answer, parse the body. Each of the three is somebody else's code — the
/// transport, [mapReceiptExtractionReply] or [_rpcProblem], and a parser — so
/// this class contains no branching of its own beyond "did it throw?".
///
/// ## It reproduces no backend authorization logic
///
/// There is no join over profiles, memberships, roles or permissions here, no
/// permission code, no role comparison and no capability check. Whether this
/// caller may read this receipt is decided once, in SQL, by
/// `assert_my_receipt_extraction_access` — which every one of these six
/// operations opens by calling, and which returns a bare boolean so that no
/// organization id, profile id, extraction id or storage coordinate can leave
/// it. Restating any of that here would create a second definition free to
/// drift, and only one of the two could be right.
///
/// ## It never touches Storage, and never touches the five tables
///
/// The image is fetched through a short-lived capability the preview endpoint
/// mints server-side; this class holds no bucket name, no object path and no
/// credential that could read one. All five extraction tables carry RLS with
/// zero policies and no privilege for the browser roles, so every access here is
/// an approved function call.
///
/// ## Nothing mutating is ever retried
///
/// [requestExtraction] can consume one of three attempts a receipt gets in its
/// lifetime and [confirm] writes a row that can never be changed. A transport
/// fault on either is reported as [ExtractionNetworkProblem] and stops there:
/// this layer does not have the information to decide that a second attempt is
/// acceptable, and the backend's own posture is the same — *"retry is the
/// caller's explicit act, the only path that respects the three-attempt cap."*
final class SupabaseReceiptExtractionRepository
    implements ReceiptExtractionRepository {
  const SupabaseReceiptExtractionRepository({
    required ReceiptExtractionFunctionClient functions,
    required ReceiptExtractionRpcDataSource rpc,
  }) : _functions = functions,
       _rpc = rpc;

  final ReceiptExtractionFunctionClient _functions;
  final ReceiptExtractionRpcDataSource _rpc;

  @override
  Future<ReceiptExtractionResult<ReceiptExtractionRequestResult>>
  requestExtraction(String submissionId) {
    return _callFunction<ReceiptExtractionRequestResult>(
      () => _functions.requestExtraction(submissionId),
      ReceiptExtractionRequestResultParser.parse,
      submissionId,
    );
  }

  @override
  Future<ReceiptExtractionResult<ReceiptExtraction>> extraction(
    String submissionId,
  ) {
    return _callFunction<ReceiptExtraction>(
      () => _functions.getExtraction(submissionId),
      ReceiptExtractionEnvelopeParser.parse,
      submissionId,
    );
  }

  @override
  Future<ReceiptExtractionResult<ReceiptImagePreview>> imagePreview(
    String submissionId,
  ) {
    return _callFunction<ReceiptImagePreview>(
      () => _functions.imagePreview(submissionId),
      ReceiptImagePreviewParser.parse,
      submissionId,
    );
  }

  @override
  Future<ReceiptExtractionResult<List<ReceiptExtractionLineItem>>> lineItems(
    String submissionId,
  ) {
    return _callRpc<List<ReceiptExtractionLineItem>>(
      () => _rpc.fetchLineItems(submissionId),
      ReceiptExtractionLineItemParser.parseList,
      submissionId,
    );
  }

  @override
  Future<ReceiptExtractionResult<ReceiptConfirmation?>> confirmation(
    String submissionId,
  ) {
    return _callRpc<ReceiptConfirmation?>(
      () => _rpc.fetchConfirmation(submissionId),
      ReceiptConfirmationParser.parseSingle,
      submissionId,
    );
  }

  @override
  Future<ReceiptExtractionResult<ReceiptConfirmationResult>> confirm(
    ReceiptConfirmationInput input,
  ) async {
    // A backstop, refused before anything leaves the device. Every rule is
    // enforced again in SQL; stopping here only means an obviously impossible
    // value never becomes a round trip, and never becomes a `23514` a caller has
    // to interpret.
    //
    // A form wanting to highlight *which* control is wrong calls
    // `input.validate()` itself and reads the richer discriminant; this layer
    // deliberately reports only that the request was invalid, because that is
    // all the backend's own refusal would have told it.
    if (input.validate() != null) {
      return const ReceiptExtractionFailed<ReceiptConfirmationResult>(
        ExtractionInvalidRequestProblem(ExtractionInvalidReason.unknown),
      );
    }

    final Object? raw;
    try {
      raw = await _rpc.confirm(buildReceiptConfirmationParams(input));
    } on Object catch (error) {
      return ReceiptExtractionFailed<ReceiptConfirmationResult>(
        _rpcProblem(error),
      );
    }

    final ReceiptConfirmationResult? parsed;
    try {
      parsed = ReceiptConfirmationResultParser.parseSingle(raw);
    } on ReceiptFormatException {
      return const ReceiptExtractionFailed<ReceiptConfirmationResult>(
        ExtractionMalformedResponseProblem(),
      );
    }

    // Zero rows is the access predicate answering false, which is reported as
    // not-found — byte-identical to every other unreadable receipt, so the call
    // cannot be used to discover that somebody else's exists.
    if (parsed == null) {
      return const ReceiptExtractionFailed<ReceiptConfirmationResult>(
        ExtractionNotFoundProblem(),
      );
    }
    return ReceiptExtractionSuccess<ReceiptConfirmationResult>(parsed);
  }

  /// Call → classify → parse, for an Edge Function.
  ///
  /// The submission id is shape-checked first. A malformed one would come back
  /// as a clean `400 invalid-submission-id`, but stopping here means an
  /// obviously wrong value never leaves the device — and produces the same typed
  /// problem either way, so no caller can tell which side refused it.
  Future<ReceiptExtractionResult<T>> _callFunction<T>(
    Future<ReceiptExtractionReply> Function() call,
    T Function(Map<String, Object?> body) parse,
    String submissionId,
  ) async {
    if (!isUuid(submissionId)) {
      return ReceiptExtractionFailed<T>(
        const ExtractionInvalidRequestProblem(
          ExtractionInvalidReason.invalidSubmissionId,
        ),
      );
    }

    final ReceiptExtractionReply reply;
    try {
      reply = await call();
    } on Object {
      // `functions.invoke` surfaces every contract refusal as a reply, so
      // anything that reaches here produced no answer at all: a socket fault, a
      // timeout, a DNS failure. The error object itself is never bound, logged
      // or rendered — it can quote a URL, a body or a token.
      return ReceiptExtractionFailed<T>(const ExtractionNetworkProblem());
    }

    final ReceiptExtractionResult<Map<String, Object?>> classified =
        mapReceiptExtractionReply(status: reply.status, body: reply.body);

    switch (classified) {
      case ReceiptExtractionFailed<Map<String, Object?>>(:final problem):
        return ReceiptExtractionFailed<T>(problem);
      case ReceiptExtractionSuccess<Map<String, Object?>>(:final value):
        try {
          return ReceiptExtractionSuccess<T>(parse(value));
        } on ReceiptFormatException {
          return ReceiptExtractionFailed<T>(
            const ExtractionMalformedResponseProblem(),
          );
        }
    }
  }

  /// Call → classify → parse, for an RPC.
  Future<ReceiptExtractionResult<T>> _callRpc<T>(
    Future<Object?> Function() call,
    T Function(Object? raw) parse,
    String submissionId,
  ) async {
    if (!isUuid(submissionId)) {
      return ReceiptExtractionFailed<T>(
        const ExtractionInvalidRequestProblem(
          ExtractionInvalidReason.invalidSubmissionId,
        ),
      );
    }

    final Object? raw;
    try {
      raw = await call();
    } on Object catch (error) {
      return ReceiptExtractionFailed<T>(_rpcProblem(error));
    }

    try {
      return ReceiptExtractionSuccess<T>(parse(raw));
    } on ReceiptFormatException {
      return ReceiptExtractionFailed<T>(
        const ExtractionMalformedResponseProblem(),
      );
    }
  }
}

/// Classifies a thrown RPC error by SQLSTATE, and by nothing else.
///
/// This is the extraction feature's counterpart to `mapSupabaseError`, and it
/// obeys the same three rules:
///
/// 1. **No raw message escapes.** Nothing here reads `error.message`, for
///    display or for discrimination. Postgres messages name tables, columns,
///    functions and policies, and the backend contract is explicit that message
///    text is not an API.
/// 2. **Transport is never a denial.** Anything that is not a recognized
///    SQLSTATE becomes an operational problem.
/// 3. **Fail closed.** No branch returns a success-shaped value.
///
/// It is separate from `mapSupabaseError` rather than a call into it because the
/// two produce different unions: that one has no case for `not-found` or for an
/// invalid-request reason, and widening the shared `Failure` for one feature
/// would push this contract's distinctions into every other screen.
ReceiptExtractionProblem _rpcProblem(Object error) {
  if (error is PostgrestException) {
    return switch (error.code) {
      // The access predicate refused: not an authorized Sales Staff member at
      // all. Never rendered as "not found" — the backend distinguishes the two
      // deliberately, and collapsing them here would undo that.
      SqlState.insufficientPrivilege => const ExtractionForbiddenProblem(),
      // A business rule on a confirmation: the date floor, the currency foreign
      // key, an amount outside the permitted range, an over-long name.
      SqlState.checkViolation => const ExtractionInvalidRequestProblem(
        ExtractionInvalidReason.unknown,
      ),
      // A value PostgreSQL could not cast to the declared parameter type. A
      // defect in this build's request, not anything the person did — and the
      // reason is left unnamed, because the cast could have been the id, the
      // date or the time and guessing which would send somebody to fix a field
      // that was never the problem.
      SqlState.invalidTextRepresentation =>
        const ExtractionInvalidRequestProblem(ExtractionInvalidReason.unknown),
      _ => const ExtractionServiceUnavailableProblem(),
    };
  }

  if (error is AuthException) {
    // The session is absent, expired, or rejected. Deliberately not bound to a
    // message: auth exceptions can carry token material.
    return const ExtractionUnauthenticatedProblem();
  }

  if (error is TimeoutException) {
    return const ExtractionNetworkProblem();
  }

  return const ExtractionServiceUnavailableProblem();
}
