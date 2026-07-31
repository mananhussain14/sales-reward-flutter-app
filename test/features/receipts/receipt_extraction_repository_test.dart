import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/receipts/data/datasources/receipt_extraction_function_client.dart';
import 'package:sale_reward/features/receipts/data/datasources/receipt_extraction_rpc_data_source.dart';
import 'package:sale_reward/features/receipts/data/repositories/supabase_receipt_extraction_repository.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_civil_date.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_confirmation.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_confirmation_input.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_confirmation_outcome.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_confirmation_result.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_line_item.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_problem.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_request_outcome.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_request_result.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_image_preview.dart';
import 'package:sale_reward/features/receipts/domain/repositories/receipt_extraction_result.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/receipt_extraction_fakes.dart';

/// The data layer's contract with the backend.
///
/// Four properties are asserted repeatedly, because each is a boundary rather
/// than a convenience:
///
/// 1. **Every call sends one submission id, and the confirmation sends eight
///    values beside it.** Nothing nominates whose data comes back.
/// 2. **Every HTTP status maps to exactly one typed problem**, and an outage is
///    never presented as a denial.
/// 3. **A refusal the contract defines is an answer, not a fault** — a 403 and a
///    404 arrive as replies, not exceptions, and the transport unwraps them.
/// 4. **Nothing mutating is retried.** One call in, one call out.
void main() {
  late List<(String, Map<String, Object?>)> invocations;
  late List<String> lineItemIds;
  late List<String> confirmationIds;
  late List<String> currencyCodes;
  late List<Map<String, Object?>> confirmParams;

  late int functionStatus;
  late Object? functionBody;
  late Object? functionThrows;
  late Object? rpcResult;
  late Object? rpcThrows;

  SupabaseReceiptExtractionRepository buildRepository() {
    return SupabaseReceiptExtractionRepository(
      functions: ReceiptExtractionFunctionClient(
        invoke: (String name, Map<String, Object?> body) async {
          invocations.add((name, body));
          if (functionThrows != null) throw functionThrows!;
          return ReceiptExtractionReply(
            status: functionStatus,
            body: functionBody,
          );
        },
      ),
      rpc: ReceiptExtractionRpcDataSource(
        lineItems: (String id) async {
          lineItemIds.add(id);
          if (rpcThrows != null) throw rpcThrows!;
          return rpcResult;
        },
        confirmation: (String id) async {
          confirmationIds.add(id);
          if (rpcThrows != null) throw rpcThrows!;
          return rpcResult;
        },
        currencyMinorUnit: (String code) async {
          currencyCodes.add(code);
          if (rpcThrows != null) throw rpcThrows!;
          return rpcResult;
        },
        confirm: (Map<String, Object?> params) async {
          confirmParams.add(params);
          if (rpcThrows != null) throw rpcThrows!;
          return rpcResult;
        },
      ),
    );
  }

  ReceiptConfirmationInput validInput() => const ReceiptConfirmationInput(
    submissionId: extractionSubmissionUuid,
    transactionDate: ReceiptCivilDate(2026, 7, 25),
    currencyCode: 'AED',
    currencyMinorUnit: 2,
    totalMinor: 12550,
  );

  setUp(() {
    invocations = <(String, Map<String, Object?>)>[];
    lineItemIds = <String>[];
    confirmationIds = <String>[];
    currencyCodes = <String>[];
    confirmParams = <Map<String, Object?>>[];
    functionStatus = 200;
    functionBody = getExtractionBody();
    functionThrows = null;
    rpcResult = <Object?>[];
    rpcThrows = null;
  });

  group('what each call sends', () {
    test('requestExtraction posts one key to the request function', () async {
      functionBody = requestExtractionBody(extraction: extractionPayload());
      await buildRepository().requestExtraction(extractionSubmissionUuid);

      expect(invocations, hasLength(1));
      expect(invocations.single.$1, 'request-receipt-extraction');
      expect(invocations.single.$2, <String, Object?>{
        'submission_id': extractionSubmissionUuid,
      });
    });

    test('extraction posts one key to the get function', () async {
      await buildRepository().extraction(extractionSubmissionUuid);

      expect(invocations.single.$1, 'get-receipt-extraction');
      expect(invocations.single.$2.keys.toList(), <String>['submission_id']);
    });

    test('imagePreview posts one key to the preview function', () async {
      functionBody = imagePreviewBody();
      await buildRepository().imagePreview(extractionSubmissionUuid);

      expect(invocations.single.$1, 'receipt-image-preview');
      expect(invocations.single.$2.keys.toList(), <String>['submission_id']);
    });

    test('lineItems passes the id and nothing else', () async {
      await buildRepository().lineItems(extractionSubmissionUuid);
      expect(lineItemIds, <String>[extractionSubmissionUuid]);
    });

    test('confirmation passes the id and nothing else', () async {
      await buildRepository().confirmation(extractionSubmissionUuid);
      expect(confirmationIds, <String>[extractionSubmissionUuid]);
    });

    test('confirm passes exactly the ten declared parameters', () async {
      rpcResult = <Map<String, Object?>>[confirmationResultRow()];
      await buildRepository().confirm(validInput());

      expect(confirmParams.single.keys.toList(), <String>[
        'p_submission_id',
        'p_transaction_date',
        'p_currency_code',
        'p_currency_minor_unit',
        'p_total_minor',
        'p_merchant_name',
        'p_document_number',
        'p_transaction_time',
        'p_subtotal_minor',
        'p_tax_total_minor',
      ]);
      expect(confirmParams.single['p_total_minor'], 12550);
    });

    test('confirm declares the scale its amounts were built with', () async {
      rpcResult = <Map<String, Object?>>[confirmationResultRow()];
      await buildRepository().confirm(
        const ReceiptConfirmationInput(
          submissionId: extractionSubmissionUuid,
          transactionDate: ReceiptCivilDate(2026, 7, 25),
          currencyCode: 'JPY',
          currencyMinorUnit: 0,
          totalMinor: 1000,
        ),
      );

      // 1000 minor units of a zero-decimal currency is ¥1000, and the request
      // says so. The old nine-argument form could not have, which is the whole
      // reason it no longer exists.
      expect(confirmParams.single['p_currency_minor_unit'], 0);
      expect(confirmParams.single['p_total_minor'], 1000);
    });

    test('the declared scale is an int, never a double', () async {
      rpcResult = <Map<String, Object?>>[confirmationResultRow()];
      await buildRepository().confirm(validInput());

      expect(confirmParams.single['p_currency_minor_unit'], isA<int>());
      expect(confirmParams.single['p_total_minor'], isA<int>());
    });

    test('the nine-argument parameter set cannot be produced', () async {
      rpcResult = <Map<String, Object?>>[confirmationResultRow()];
      await buildRepository().confirm(validInput());

      // The dropped signature. A payload without the tenth key would reach
      // PostgREST as "function not found", so the client must never build one —
      // and with a required, non-nullable field it cannot.
      expect(confirmParams.single.keys, contains('p_currency_minor_unit'));
      expect(confirmParams.single.keys, hasLength(10));
      expect(confirmParams.single['p_currency_minor_unit'], isNotNull);
    });

    test('a malformed id never leaves the device', () async {
      final SupabaseReceiptExtractionRepository repository = buildRepository();

      final ReceiptExtractionResult<ReceiptExtraction> result = await repository
          .extraction('not-a-uuid');
      final ReceiptExtractionResult<List<ReceiptExtractionLineItem>> rows =
          await repository.lineItems('not-a-uuid');

      expect(invocations, isEmpty);
      expect(lineItemIds, isEmpty);
      expect(
        (result as ReceiptExtractionFailed<ReceiptExtraction>).problem,
        const ExtractionInvalidRequestProblem(
          ExtractionInvalidReason.invalidSubmissionId,
        ),
      );
      expect(
        (rows as ReceiptExtractionFailed<List<ReceiptExtractionLineItem>>)
            .problem,
        isA<ExtractionInvalidRequestProblem>(),
      );
    });
  });

  group('successful answers', () {
    test('a 200 request response parses through', () async {
      functionBody = requestExtractionBody(
        outcome: 'QUEUED',
        extraction: extractionPayload(<String, Object?>{'status': 'QUEUED'}),
      );

      final ReceiptExtractionResult<ReceiptExtractionRequestResult> result =
          await buildRepository().requestExtraction(extractionSubmissionUuid);

      final ReceiptExtractionRequestResult value =
          (result as ReceiptExtractionSuccess<ReceiptExtractionRequestResult>)
              .value;
      expect(value.outcome, ReceiptExtractionRequestOutcome.queued);
      expect(value.extraction!.extractionId, extractionAttemptUuid);
    });

    test('a failed extraction is a success, not a problem', () async {
      // The distinction the whole union exists for: a recorded failure is an
      // answer, and the review screen must show it rather than an error state.
      functionBody = getExtractionBody(
        extractionPayload(<String, Object?>{
          'status': 'FAILED',
          'failure_code': 'IMAGE_NOT_A_RECEIPT',
        }),
      );

      final ReceiptExtractionResult<ReceiptExtraction> result =
          await buildRepository().extraction(extractionSubmissionUuid);

      expect(result, isA<ReceiptExtractionSuccess<ReceiptExtraction>>());
    });

    test(
      'an EXTRACTION_UNAVAILABLE outcome is a success, not a problem',
      () async {
        // A shut gate and broken infrastructure are indistinguishable by design.
        // Neither is a transport failure, and the counters stay honest.
        functionBody = requestExtractionBody(
          outcome: 'EXTRACTION_UNAVAILABLE',
          attemptsUsed: 0,
          attemptsRemaining: 3,
        );

        final ReceiptExtractionResult<ReceiptExtractionRequestResult> result =
            await buildRepository().requestExtraction(extractionSubmissionUuid);

        final ReceiptExtractionRequestResult value =
            (result as ReceiptExtractionSuccess<ReceiptExtractionRequestResult>)
                .value;
        expect(
          value.outcome,
          ReceiptExtractionRequestOutcome.extractionUnavailable,
        );
        expect(value.attemptsRemaining, 3);
        expect(value.retryAllowed, isFalse);
      },
    );

    test('an empty line-item list is a success, not a refusal', () async {
      rpcResult = <Object?>[];

      final ReceiptExtractionResult<List<ReceiptExtractionLineItem>> result =
          await buildRepository().lineItems(extractionSubmissionUuid);

      expect(
        (result as ReceiptExtractionSuccess<List<ReceiptExtractionLineItem>>)
            .value,
        isEmpty,
      );
    });

    test('no confirmation is a null success, never not-found', () async {
      rpcResult = <Object?>[];

      final ReceiptExtractionResult<ReceiptConfirmation?> result =
          await buildRepository().confirmation(extractionSubmissionUuid);

      expect(
        (result as ReceiptExtractionSuccess<ReceiptConfirmation?>).value,
        isNull,
      );
    });

    test('a preview parses and carries its window', () async {
      functionBody = imagePreviewBody();

      final ReceiptExtractionResult<ReceiptImagePreview> result =
          await buildRepository().imagePreview(extractionSubmissionUuid);

      expect(
        (result as ReceiptExtractionSuccess<ReceiptImagePreview>)
            .value
            .expiresInSeconds,
        120,
      );
    });

    test('a confirmation result parses', () async {
      rpcResult = <Map<String, Object?>>[confirmationResultRow()];

      final ReceiptExtractionResult<ReceiptConfirmationResult> result =
          await buildRepository().confirm(validInput());

      expect(
        (result as ReceiptExtractionSuccess<ReceiptConfirmationResult>)
            .value
            .outcome,
        ReceiptConfirmationOutcome.confirmed,
      );
    });
  });

  group('Edge Function status mapping', () {
    Future<ReceiptExtractionProblem> problemFor(
      int status,
      Object? body,
    ) async {
      functionStatus = status;
      functionBody = body;
      final ReceiptExtractionResult<ReceiptExtraction> result =
          await buildRepository().extraction(extractionSubmissionUuid);
      return (result as ReceiptExtractionFailed<ReceiptExtraction>).problem;
    }

    test('401 is unauthenticated, never denied', () async {
      expect(
        await problemFor(401, <String, Object?>{'status': 'unauthenticated'}),
        isA<ExtractionUnauthenticatedProblem>(),
      );
    });

    test('403 is forbidden', () async {
      expect(
        await problemFor(403, <String, Object?>{'status': 'denied'}),
        isA<ExtractionForbiddenProblem>(),
      );
    });

    test('404 is not-found, and carries no detail', () async {
      expect(
        await problemFor(404, <String, Object?>{'status': 'not-found'}),
        const ExtractionNotFoundProblem(),
      );
    });

    test('400 carries the closed reason vocabulary', () async {
      for (final (String token, ExtractionInvalidReason expected)
          in <(String, ExtractionInvalidReason)>[
            ('malformed-body', ExtractionInvalidReason.malformedBody),
            ('body-too-large', ExtractionInvalidReason.bodyTooLarge),
            ('unknown-field', ExtractionInvalidReason.unknownField),
            (
              'invalid-submission-id',
              ExtractionInvalidReason.invalidSubmissionId,
            ),
          ]) {
        expect(
          await problemFor(400, invalidBody(token)),
          ExtractionInvalidRequestProblem(expected),
          reason: token,
        );
      }
    });

    test('405 is method-not-allowed', () async {
      expect(
        await problemFor(405, invalidBody('method-not-allowed')),
        const ExtractionInvalidRequestProblem(
          ExtractionInvalidReason.methodNotAllowed,
        ),
      );
    });

    test('an unrecognised reason degrades without leaking the token', () async {
      final ReceiptExtractionProblem problem = await problemFor(
        400,
        invalidBody('receipt-too-crumpled'),
      );

      expect(
        problem,
        const ExtractionInvalidRequestProblem(ExtractionInvalidReason.unknown),
      );
      expect(problem.toString(), isNot(contains('crumpled')));
    });

    test('503 is a service problem, never a denial', () async {
      expect(
        await problemFor(503, <String, Object?>{'status': 'unavailable'}),
        isA<ExtractionServiceUnavailableProblem>(),
      );
    });

    test('a status with no rule fails closed', () async {
      expect(
        await problemFor(418, <String, Object?>{'status': 'ok'}),
        isA<ExtractionUnknownProblem>(),
      );
      expect(await problemFor(500, null), isA<ExtractionUnknownProblem>());
    });

    test('a 200 whose body is not ok is malformed, never a success', () async {
      expect(
        await problemFor(200, <String, Object?>{'status': 'unavailable'}),
        isA<ExtractionMalformedResponseProblem>(),
      );
      expect(
        await problemFor(200, 'not json at all'),
        isA<ExtractionMalformedResponseProblem>(),
      );
    });

    test('a 200 this build cannot parse is malformed', () async {
      expect(
        await problemFor(200, <String, Object?>{
          'status': 'ok',
          'extraction': extractionPayload()..remove('status'),
        }),
        isA<ExtractionMalformedResponseProblem>(),
      );
    });

    test('a transport fault is a network problem, not an outage', () async {
      functionThrows = const SocketFault();

      final ReceiptExtractionResult<ReceiptExtraction> result =
          await buildRepository().extraction(extractionSubmissionUuid);

      expect(
        (result as ReceiptExtractionFailed<ReceiptExtraction>).problem,
        isA<ExtractionNetworkProblem>(),
      );
    });
  });

  group('RPC error mapping', () {
    Future<ReceiptExtractionProblem> problemFor(Object error) async {
      rpcThrows = error;
      final ReceiptExtractionResult<List<ReceiptExtractionLineItem>> result =
          await buildRepository().lineItems(extractionSubmissionUuid);
      return (result
              as ReceiptExtractionFailed<List<ReceiptExtractionLineItem>>)
          .problem;
    }

    test('42501 is forbidden, never not-found', () async {
      expect(
        await problemFor(
          const PostgrestException(message: 'refused', code: '42501'),
        ),
        isA<ExtractionForbiddenProblem>(),
      );
    });

    test('23514 is an invalid request', () async {
      expect(
        await problemFor(
          const PostgrestException(message: 'check', code: '23514'),
        ),
        isA<ExtractionInvalidRequestProblem>(),
      );
    });

    test('22P02 is an invalid request with no field named', () async {
      expect(
        await problemFor(
          const PostgrestException(message: 'cast', code: '22P02'),
        ),
        const ExtractionInvalidRequestProblem(ExtractionInvalidReason.unknown),
      );
    });

    test('an unrecognised SQLSTATE is operational, never a denial', () async {
      final ReceiptExtractionProblem problem = await problemFor(
        const PostgrestException(message: 'boom', code: '08006'),
      );

      expect(problem, isA<ExtractionServiceUnavailableProblem>());
      expect(problem, isNot(isA<ExtractionForbiddenProblem>()));
    });

    test('an auth failure is unauthenticated', () async {
      expect(
        await problemFor(const AuthException('token expired')),
        isA<ExtractionUnauthenticatedProblem>(),
      );
    });

    test('a timeout is a network problem', () async {
      expect(
        await problemFor(TimeoutException('slow')),
        isA<ExtractionNetworkProblem>(),
      );
    });

    test('no backend message reaches the problem', () async {
      final ReceiptExtractionProblem problem = await problemFor(
        const PostgrestException(
          message: 'permission denied for table receipt_extractions',
          code: '42501',
        ),
      );

      expect(problem.toString(), isNot(contains('receipt_extractions')));
      expect(problem.toString(), isNot(contains('permission denied')));
    });

    test('an unreadable row is malformed, never an empty list', () async {
      rpcResult = <Map<String, Object?>>[lineItemRow()..remove('line_number')];

      final ReceiptExtractionResult<List<ReceiptExtractionLineItem>> result =
          await buildRepository().lineItems(extractionSubmissionUuid);

      expect(
        (result as ReceiptExtractionFailed<List<ReceiptExtractionLineItem>>)
            .problem,
        isA<ExtractionMalformedResponseProblem>(),
      );
    });
  });

  group('confirmation refusals', () {
    test('an input the pre-check refuses never reaches the RPC', () async {
      final ReceiptExtractionResult<ReceiptConfirmationResult> result =
          await buildRepository().confirm(
            const ReceiptConfirmationInput(
              submissionId: 'not-a-uuid',
              transactionDate: ReceiptCivilDate(2026, 7, 25),
              currencyCode: 'AED',
              currencyMinorUnit: 2,
              totalMinor: 12550,
            ),
          );

      expect(confirmParams, isEmpty);
      expect(
        (result as ReceiptExtractionFailed<ReceiptConfirmationResult>).problem,
        isA<ExtractionInvalidRequestProblem>(),
      );
    });

    test('zero rows is not-found — the access predicate said no', () async {
      rpcResult = <Object?>[];

      final ReceiptExtractionResult<ReceiptConfirmationResult> result =
          await buildRepository().confirm(validInput());

      expect(
        (result as ReceiptExtractionFailed<ReceiptConfirmationResult>).problem,
        const ExtractionNotFoundProblem(),
      );
    });

    test('a blocked confirmation is a success carrying the outcome', () async {
      rpcResult = <Map<String, Object?>>[
        confirmationResultRow(<String, Object?>{
          'outcome': 'EXTRACTION_IN_PROGRESS',
          'confirmation_id': null,
          'entry_mode': null,
          'changed_fields': null,
        }),
      ];

      final ReceiptExtractionResult<ReceiptConfirmationResult> result =
          await buildRepository().confirm(validInput());

      expect(
        (result as ReceiptExtractionSuccess<ReceiptConfirmationResult>)
            .value
            .outcome,
        ReceiptConfirmationOutcome.extractionInProgress,
      );
    });

    test(
      'SQLSTATE 22023 is the currency-scale mismatch and nothing else',
      () async {
        rpcThrows = const PostgrestException(
          message:
              'That confirmation did not state the currency minor unit '
              'this system uses',
          code: '22023',
        );

        final ReceiptExtractionResult<ReceiptConfirmationResult> result =
            await buildRepository().confirm(validInput());

        expect(
          (result as ReceiptExtractionFailed<ReceiptConfirmationResult>)
              .problem,
          const ExtractionCurrencyScaleMismatchProblem(),
        );
      },
    );

    test(
      '22023 is not an outage, a denial or an unsupported currency',
      () async {
        rpcThrows = const PostgrestException(message: 'x', code: '22023');

        final ReceiptExtractionProblem problem =
            (await buildRepository().confirm(validInput())
                    as ReceiptExtractionFailed<ReceiptConfirmationResult>)
                .problem;

        expect(problem, isNot(isA<ExtractionServiceUnavailableProblem>()));
        expect(problem, isNot(isA<ExtractionNetworkProblem>()));
        expect(problem, isNot(isA<ExtractionForbiddenProblem>()));
        // An unsupported currency is still 23514, raised before the scale is
        // considered at all, and it maps to the invalid-request problem.
        expect(problem, isNot(isA<ExtractionInvalidRequestProblem>()));
      },
    );

    test(
      'an unsupported currency stays 23514 and stays invalid-request',
      () async {
        rpcThrows = const PostgrestException(
          message: 'That currency could not be accepted',
          code: '23514',
        );

        final ReceiptExtractionResult<ReceiptConfirmationResult> result =
            await buildRepository().confirm(validInput());

        expect(
          (result as ReceiptExtractionFailed<ReceiptConfirmationResult>)
              .problem,
          isA<ExtractionInvalidRequestProblem>(),
        );
      },
    );

    test('22023 does not carry the SQLSTATE or the backend message', () async {
      rpcThrows = const PostgrestException(
        message: 'iso_currency_codes says 0',
        code: '22023',
      );

      final ReceiptExtractionProblem problem =
          (await buildRepository().confirm(validInput())
                  as ReceiptExtractionFailed<ReceiptConfirmationResult>)
              .problem;

      // The union carries no field at all, so there is nowhere for a message,
      // a code or an expected value to hide.
      expect(problem.props, isEmpty);
      expect(problem.toString(), isNot(contains('22023')));
      expect(problem.toString(), isNot(contains('iso_currency_codes')));
    });

    test('22023 on a confirmation is attempted exactly once', () async {
      rpcThrows = const PostgrestException(message: 'x', code: '22023');

      await buildRepository().confirm(validInput());

      // Nothing resends a confirmation, least of all one whose declared scale
      // has just been refused.
      expect(confirmParams, hasLength(1));
    });
  });

  group('22023 is mapped in the confirmation context only', () {
    test(
      'the line-item read treats it as operational, not a scale problem',
      () async {
        rpcThrows = const PostgrestException(message: 'x', code: '22023');

        final ReceiptExtractionResult<List<ReceiptExtractionLineItem>> result =
            await buildRepository().lineItems(extractionSubmissionUuid);

        expect(
          (result as ReceiptExtractionFailed<List<ReceiptExtractionLineItem>>)
              .problem,
          const ExtractionServiceUnavailableProblem(),
        );
      },
    );

    test('the confirmation read treats it as operational too', () async {
      rpcThrows = const PostgrestException(message: 'x', code: '22023');

      final ReceiptExtractionResult<ReceiptConfirmation?> result =
          await buildRepository().confirmation(extractionSubmissionUuid);

      expect(
        (result as ReceiptExtractionFailed<ReceiptConfirmation?>).problem,
        const ExtractionServiceUnavailableProblem(),
      );
    });
  });

  group('nothing is retried', () {
    test('a failed request extraction is attempted exactly once', () async {
      functionThrows = const SocketFault();

      await buildRepository().requestExtraction(extractionSubmissionUuid);

      // A second attempt could consume a second of the three.
      expect(invocations, hasLength(1));
    });

    test('a failed confirmation is attempted exactly once', () async {
      rpcThrows = const PostgrestException(message: 'boom', code: '08006');

      await buildRepository().confirm(validInput());

      expect(confirmParams, hasLength(1));
    });

    test('a 503 read is not retried either', () async {
      functionStatus = 503;
      functionBody = <String, Object?>{'status': 'unavailable'};

      await buildRepository().extraction(extractionSubmissionUuid);

      expect(invocations, hasLength(1));
    });
  });
}

/// A socket-level fault, standing in for whatever the platform throws.
final class SocketFault implements Exception {
  const SocketFault();
}
